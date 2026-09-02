#!/bin/bash

# Re-registers the Argo CD instance with Octopus:
#
#   1. Deletes the Argo CD instance (gateway registration) named "Kind" from Octopus
#   2. Uninstalls the kindargocd Helm release from the Kind cluster
#   3. Reruns the Helm install, which registers the Argo CD instance again
#
# Usage: ./reregister.sh <bearer-token> [space-name] [hostname] [instance-name]

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "${SCRIPT_DIR}" || exit 1

BEARER_TOKEN=${1:-}
SPACE_NAME=${2:-Scratchpad}
OCTOPUS_HOSTNAME=${3:-mattc.octopus.app}
INSTANCE_NAME=${4:-Kind}

HELM_RELEASE=kindargocd
HELM_NAMESPACE=octo-argo-gateway-kind

if [ -z "$BEARER_TOKEN" ]; then
  echo "Error: No bearer token supplied"
  echo "Usage: $0 <bearer-token> [space-name] [hostname] [instance-name]"
  exit 1
fi

if ! vagrant status --machine-readable | grep -q ",state,running"; then
  echo "Error: the Vagrant VM is not running. Start it with ./start.sh <bearer-token>"
  exit 1
fi

# Get space ID from Octopus API using the space name
SPACE_ID=$(curl -s -G -H "Authorization: Bearer ${BEARER_TOKEN}" \
  --data-urlencode "partialName=${SPACE_NAME}" \
  "https://${OCTOPUS_HOSTNAME}/api/spaces" | \
  jq -r --arg name "${SPACE_NAME}" '.Items[] | select(.Name==$name) | .Id')

if [ -z "$SPACE_ID" ] || [ "$SPACE_ID" == "null" ]; then
  echo "Error: Could not find space named ${SPACE_NAME}"
  exit 1
fi

echo "Found space: ${SPACE_NAME} (${SPACE_ID})"

# Find the Argo CD instance by name. The gateway registration is what Octopus
# shows under Infrastructure -> Argo CD Instances.
GATEWAY_ID=$(curl -s -G -H "Authorization: Bearer ${BEARER_TOKEN}" \
  --data-urlencode "partialName=${INSTANCE_NAME}" \
  "https://${OCTOPUS_HOSTNAME}/api/spaces/${SPACE_ID}/argocdinstances/summaries" | \
  jq -r --arg name "${INSTANCE_NAME}" 'first(.Resources[]? | select(.Name==$name) | .GatewayId) // empty')

if [ -z "$GATEWAY_ID" ]; then
  echo "No Argo CD instance named ${INSTANCE_NAME} found in ${SPACE_NAME}, nothing to delete"
else
  echo "Deleting Argo CD instance ${INSTANCE_NAME} (${GATEWAY_ID})..."
  DELETE_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE \
    -H "Authorization: Bearer ${BEARER_TOKEN}" \
    "https://${OCTOPUS_HOSTNAME}/api/spaces/${SPACE_ID}/argocdgateways/${GATEWAY_ID}")

  if [ "$DELETE_STATUS" -lt 200 ] || [ "$DELETE_STATUS" -ge 300 ]; then
    echo "Error: deleting the Argo CD instance returned HTTP ${DELETE_STATUS}"
    exit 1
  fi
fi

# Everything from here runs in the VM as root, because the kubeconfig created
# during provisioning belongs to root.
vagrant ssh -c "sudo \
  HELM_RELEASE='${HELM_RELEASE}' \
  HELM_NAMESPACE='${HELM_NAMESPACE}' \
  INSTANCE_NAME='${INSTANCE_NAME}' \
  OCTOPUS_TEMPK8S_HOSTNAME='${OCTOPUS_HOSTNAME}' \
  OCTOPUS_TEMPK8S_SPACE_ID='${SPACE_ID}' \
  OCTOPUS_TEMPK8S_BEARER_TOKEN='${BEARER_TOKEN}' \
  bash -s" -- -T <<'REMOTE'
set -uo pipefail

echo "Uninstalling Helm release ${HELM_RELEASE} from namespace ${HELM_NAMESPACE}..."
helm uninstall "${HELM_RELEASE}" --namespace "${HELM_NAMESPACE}" --wait ||
  echo "Helm release ${HELM_RELEASE} was not installed, continuing"

# The argocd CLI talks to the Argo CD server over a port forward. Provisioning
# starts one, but it does not survive a reboot, so start one if needed.
if ! timeout 2 bash -c 'exec 3<>/dev/tcp/127.0.0.1/8080' 2>/dev/null; then
  kubectl port-forward svc/argocd-server -n argocd 8080:443 >/dev/null 2>&1 &
  PORT_FORWARD_PID=$!
  trap 'kill "${PORT_FORWARD_PID}" 2>/dev/null' EXIT
  sleep 5
fi

PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

if [ -z "$PASSWORD" ]; then
  echo "Error: could not read the Argo CD admin password from argocd-initial-admin-secret"
  exit 1
fi

argocd login "localhost:8080" --username admin --password "$PASSWORD" --insecure || exit 1

# The gateway authenticates against Argo CD as the octopus account
TOKEN=$(argocd account generate-token --account octopus) || exit 1

echo "Installing Helm release ${HELM_RELEASE}..."
helm upgrade --install --rollback-on-failure \
  --create-namespace --namespace "${HELM_NAMESPACE}" \
  --version "*.*" \
  --set registration.octopus.name="${INSTANCE_NAME}" \
  --set registration.octopus.serverApiUrl="https://${OCTOPUS_TEMPK8S_HOSTNAME}" \
  --set registration.octopus.serverAccessToken="${OCTOPUS_TEMPK8S_BEARER_TOKEN}" \
  --set registration.octopus.spaceId="${OCTOPUS_TEMPK8S_SPACE_ID}" \
  --set gateway.octopus.serverGrpcUrl="grpc://${OCTOPUS_TEMPK8S_HOSTNAME}:8443" \
  --set gateway.argocd.serverGrpcUrl="grpc://argocd-server.argocd.svc.cluster.local" \
  --set gateway.argocd.insecure="true" \
  --set gateway.argocd.plaintext="false" \
  --set gateway.argocd.authenticationToken="${TOKEN}" \
  "${HELM_RELEASE}" \
  oci://registry-1.docker.io/octopusdeploy/octopus-argocd-gateway-chart
REMOTE

if [ $? -ne 0 ]; then
  echo "Error: the Helm reinstall failed"
  exit 1
fi

# The registration job runs as a Helm hook, so the instance shows up shortly
# after the install returns
for i in {1..10}; do
  NEW_GATEWAY_ID=$(curl -s -G -H "Authorization: Bearer ${BEARER_TOKEN}" \
    --data-urlencode "partialName=${INSTANCE_NAME}" \
    "https://${OCTOPUS_HOSTNAME}/api/spaces/${SPACE_ID}/argocdinstances/summaries" | \
    jq -r --arg name "${INSTANCE_NAME}" 'first(.Resources[]? | select(.Name==$name) | .GatewayId) // empty')

  if [ -n "$NEW_GATEWAY_ID" ]; then
    echo "Argo CD instance ${INSTANCE_NAME} registered as ${NEW_GATEWAY_ID}"
    exit 0
  fi

  echo "Waiting for the Argo CD instance to register (attempt $i)..."
  sleep 10
done

echo "Warning: the Helm install succeeded, but no Argo CD instance named ${INSTANCE_NAME} appeared in ${SPACE_NAME}."
echo "Check the registration job logs with: vagrant ssh -c 'sudo kubectl -n ${HELM_NAMESPACE} logs -l app.kubernetes.io/name=octopus-argocd-gateway --tail=100'"
exit 1
