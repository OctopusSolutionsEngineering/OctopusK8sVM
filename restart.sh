#!/bin/bash

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

if [ -z "$1" ]; then
  echo "Error: No bearer token supplied"
  echo "Usage: $0 <bearer-token> [space-name] [hostname]"
  exit 1
fi

vagrant destroy -f

exec "${SCRIPT_DIR}/start.sh" "$@"
