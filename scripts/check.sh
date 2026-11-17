#!/usr/bin/env bash
set -euo pipefail

# Chequeos locales y de CI: sintaxis, shellcheck, JSON y tests. No cambia nada del sistema.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

shell_files=(bootstrap.sh install.sh lib/*.sh modules/*.sh scripts/*.sh tests/*.sh files/bin/*)

echo "== bash -n"
for f in "${shell_files[@]}"; do bash -n "${f}"; done

echo "== shellcheck"
shellcheck -x "${shell_files[@]}"

echo "== json"
for f in files/claude/*.json; do jq empty "${f}"; done

echo "== tests"
for t in tests/test-*.sh; do bash "${t}"; done

echo "OK"
