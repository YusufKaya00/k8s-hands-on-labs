#!/usr/bin/env bash
set -euo pipefail

PROFILE="vault-lab-1"
echo "Deleting isolated Minikube profile '${PROFILE}'..."
minikube delete -p "${PROFILE}"
echo "Cleanup complete."
