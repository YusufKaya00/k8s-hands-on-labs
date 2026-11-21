#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo ">>> Resetting ZephyrMesh v20.0 (Lab 37) back to initial broken manifests..."
cp "${SCRIPT_DIR}/values-broken.yaml" "${LAB_DIR}/helm/zephyrmesh/values.yaml"
cp -r "${SCRIPT_DIR}/helm/zephyrmesh/templates/." "${LAB_DIR}/helm/zephyrmesh/templates/"

"${LAB_DIR}/setup.sh" "$@"
