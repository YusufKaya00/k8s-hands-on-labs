#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROFILE="dr-lab-1"
RELEASE="dr-lab"

echo "Resetting Lesson 02 / Lab 1 back to initial broken state on '${PROFILE}'..."

cp "${SCRIPT_DIR}/values-broken.yaml" "${LAB_DIR}/helm/dr-pipeline/values.yaml"
mkdir -p "${LAB_DIR}/helm/dr-pipeline/crds"
cp -r "${SCRIPT_DIR}/helm/dr-pipeline/crds/." "${LAB_DIR}/helm/dr-pipeline/crds/"
cp -r "${SCRIPT_DIR}/helm/dr-pipeline/templates/." "${LAB_DIR}/helm/dr-pipeline/templates/"

kubectl --context "${PROFILE}" apply -f "${LAB_DIR}/helm/dr-pipeline/crds/crds.yaml" >/dev/null
kubectl --context "${PROFILE}" -n velero delete backup,restore --all --ignore-not-found=true >/dev/null 2>&1 || true
helm --kube-context "${PROFILE}" upgrade --install "${RELEASE}" "${LAB_DIR}/helm/dr-pipeline" \
  -f "${LAB_DIR}/helm/dr-pipeline/values.yaml"

echo "Lab reset complete. Run './check.sh' from ${LAB_DIR} to verify broken baseline."
