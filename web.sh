#!/bin/bash

# Forwards the Argo CD web UI from the Vagrant VM to the host and prints the
# admin credentials.
#
# Usage: ./web.sh [host-port]

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "${SCRIPT_DIR}" || exit 1

HOST_PORT=${1:-8080}
GUEST_PORT=8080

if ! vagrant status --machine-readable | grep -q ",state,running"; then
  echo "Error: the Vagrant VM is not running. Start it with ./start.sh <bearer-token>"
  exit 1
fi

echo "Retrieving the Argo CD admin password..."
PASSWORD=$(vagrant ssh -c 'sudo kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d' 2>/dev/null | tr -d '\r')

if [ -z "${PASSWORD}" ]; then
  echo "Error: could not read the argocd-initial-admin-secret secret."
  echo "Argo CD may still be installing, or the secret may have been deleted."
  exit 1
fi

echo
echo "Argo CD UI:  https://localhost:${HOST_PORT}"
echo "Username:    admin"
echo "Password:    ${PASSWORD}"
echo
echo "The certificate is self signed, so the browser will warn about it."
echo "Press Ctrl+C to stop the port forward."
echo

# The argocd-port-forward systemd service in the VM keeps a "kubectl
# port-forward" running on guest port 8080, so this only has to tunnel the
# guest port to the host.
exec vagrant ssh -- -N -L "${HOST_PORT}:localhost:${GUEST_PORT}"
