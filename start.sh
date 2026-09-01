#!/bin/bash

BEARER_TOKEN=$1
SPACE_NAME=${2:-Scratchpad}
OCTOPUS_HOSTNAME=${3:-mattc.octopus.app}

if [ -z "$BEARER_TOKEN" ]; then
  echo "Error: No bearer token supplied"
  echo "Usage: $0 <bearer-token> [space-name] [hostname]"
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

OCTOPUS_TEMPK8S_GRPC_HOSTNAME=${OCTOPUS_HOSTNAME}:8443 \
OCTOPUS_TEMPK8S_HOSTNAME=${OCTOPUS_HOSTNAME} \
OCTOPUS_TEMPK8S_POLLING_HOSTNAME=polling.${OCTOPUS_HOSTNAME} \
OCTOPUS_TEMPK8S_SPACE="${SPACE_NAME}" \
OCTOPUS_TEMPK8S_SPACE_ID="${SPACE_ID}" \
OCTOPUS_TEMPK8S_BEARER_TOKEN="${BEARER_TOKEN}" \
vagrant up
