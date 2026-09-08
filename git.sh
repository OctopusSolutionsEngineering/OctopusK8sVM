#!/bin/bash

# Adds (or updates) the Mock Git Repo in Argo CD with the supplied credentials.
# This is the same "argocd repo add" that provisioning runs, so it can be used
# to change the credentials without rebuilding the VM.
#
# Usage: ./git.sh <git-username> [git-password]
#
# The password is optional and defaults to a random GUID.

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "${SCRIPT_DIR}" || exit 1

GIT_USER=${1:-}

if [ -z "$GIT_USER" ]; then
  echo "Error: No git username supplied"
  echo "Usage: $0 <git-username> [git-password]"
  exit 1
fi

if [ $# -ge 2 ] && [ -n "$2" ]; then
  GIT_PASS=$2
else
  GIT_PASS=$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid)
  echo "No password supplied, using the generated password ${GIT_PASS}"
fi

if ! vagrant status --machine-readable | grep -q ",state,running"; then
  echo "Error: the Vagrant VM is not running. Start it with ./start.sh <bearer-token>"
  exit 1
fi

# Everything from here runs in the VM as root, because the kubeconfig created
# during provisioning belongs to root.
vagrant ssh -c "sudo \
  GIT_USER='${GIT_USER}' \
  GIT_PASS='${GIT_PASS}' \
  bash -s" -- -T <<'REMOTE'
set -uo pipefail

PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

if [ -z "$PASSWORD" ]; then
  echo "Error: could not read the Argo CD admin password from argocd-initial-admin-secret"
  exit 1
fi

argocd login "localhost:8080" --username admin --password "$PASSWORD" --insecure || exit 1

for i in {1..5}; do
    argocd repo add https://mockgit.octopusdemos.com/repo/argocd --upsert --username "${GIT_USER}" --password "${GIT_PASS}" && exit 0
    echo "Attempt $i failed. Retrying in 30 seconds..."
    sleep 30
done

echo "Error: could not add the Mock Git Repo to Argo CD"
exit 1
REMOTE

if [ $? -ne 0 ]; then
  echo "Error: adding the Mock Git Repo failed"
  exit 1
fi

echo "Added https://mockgit.octopusdemos.com/repo/argocd as ${GIT_USER}"
