#!/bin/bash

# Adds (or updates) the Mock Git Repo in Argo CD with the supplied credentials,
# then refreshes and syncs every Argo CD application so they pick up the new
# credentials. This is the same "argocd repo add" that provisioning runs, so it
# can be used to change the credentials without rebuilding the VM.
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
  echo "No password supplied, using a random password"
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

REPO_ADDED=false

for i in {1..5}; do
    argocd repo add https://mockgit.octopusdemos.com/repo/argocd --upsert --username "${GIT_USER}" --password "${GIT_PASS}" && REPO_ADDED=true && break
    echo "Attempt $i failed. Retrying in 30 seconds..."
    sleep 30
done

if [ "${REPO_ADDED}" != "true" ]; then
  echo "Error: could not add the Mock Git Repo to Argo CD"
  exit 1
fi

APPS=$(argocd app list -o name)

if [ -z "${APPS}" ]; then
  echo "No Argo CD applications to sync"
  exit 0
fi

# The applications cache the manifests fetched with the old credentials, so
# hard refresh each one before syncing it
SYNC_RESULT=0

for APP in ${APPS}; do
    for i in {1..5}; do
        echo "Syncing Argo CD application ${APP} (attempt $i)..."
        argocd app get "${APP}" --hard-refresh >/dev/null && argocd app sync "${APP}" && break

        if [ "$i" -eq 5 ]; then
          echo "Error: could not sync ${APP}"
          SYNC_RESULT=1
        else
          sleep 30
        fi
    done
done

exit ${SYNC_RESULT}
REMOTE

if [ $? -ne 0 ]; then
  echo "Error: updating the Mock Git Repo credentials failed"
  exit 1
fi

echo "Added https://mockgit.octopusdemos.com/repo/argocd as ${GIT_USER} and synced the Argo CD applications"
