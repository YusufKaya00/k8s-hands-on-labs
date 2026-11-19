#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROFILE="logging-lab-1"
RELEASE="logging-lab"

echo "Resetting Lesson 01 / Lab 1 back to initial broken state on '${PROFILE}'..."

cp "${SCRIPT_DIR}/values-broken.yaml" "${LAB_DIR}/helm/logging-pipeline/values.yaml"
cp -r "${SCRIPT_DIR}/helm/logging-pipeline/templates/." "${LAB_DIR}/helm/logging-pipeline/templates/"

kubectl --context "${PROFILE}" taint nodes "${PROFILE}" dedicated=logging-lab:NoSchedule --overwrite
helm --kube-context "${PROFILE}" upgrade --install "${RELEASE}" "${LAB_DIR}/helm/logging-pipeline" \
  -f "${LAB_DIR}/helm/logging-pipeline/values.yaml"

echo "Lab reset complete. Run './check.sh' from ${LAB_DIR} to verify broken baseline."
