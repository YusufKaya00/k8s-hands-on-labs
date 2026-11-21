#!/usr/bin/env bash
set -euo pipefail

PROFILE="dr-lab-1"

echo "Deleting isolated Minikube profile '${PROFILE}'..."
minikube delete -p "${PROFILE}" || true
docker volume rm "${PROFILE}" >/dev/null 2>&1 || true

echo ""
echo "Cleanup complete. Verify your active kubectl context:"
echo "  kubectl config get-contexts"
