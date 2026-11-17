#!/usr/bin/env bash
set -euo pipefail

# Guardas de install.sh: nunca da acceso por defecto y escribe host.env sin secretos.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/tests/lib.sh"
CIGUA_INSTALL_SOURCED=1 source "${ROOT_DIR}/install.sh"

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
out="${work}/host.env"
ex="${ROOT_DIR}/host.env.example"

# shellcheck disable=SC2016
gen() { env -i PATH="${PATH}" "$@" bash -c 'CIGUA_INSTALL_SOURCED=1 source "$0/install.sh"; render_host_env "$1" "$2"' "${ROOT_DIR}" "${out}" "${ex}" >/dev/null 2>&1; }

echo "install"
refute "sin AUTHORIZED_KEYS_URLS: falla" gen VPS_USER=ana
refute "sin VPS_USER: falla" gen AUTHORIZED_KEYS_URLS=https://x.test/a.pub
refute "URL http (no https): falla" gen VPS_USER=ana AUTHORIZED_KEYS_URLS=http://x.test/a.pub
# shellcheck disable=SC2016
refute "valor con comillas o \$(): falla" gen VPS_USER='ana$(id)' AUTHORIZED_KEYS_URLS=https://x.test/a.pub
refute "no escribe nada si falla" test -e "${out}"

gen VPS_USER=ana AUTHORIZED_KEYS_URLS="https://x.test/a.pub https://x.test/b.pub" TS_AUTHKEY=tskey-secreto
check "host.env creado" test -f "${out}"
check "modo 600" test "$(stat -c %a "${out}")" = 600
check "usuario elegido" grep -qx 'VPS_USER="ana"' "${out}"
check "ambas llaves" bash -c "grep -q 'x.test/a.pub' '${out}' && grep -q 'x.test/b.pub' '${out}'"
refute "no copia secretos del entorno" grep -q 'tskey' "${out}"
# shellcheck disable=SC2016
res="$(env -i PATH="${PATH}" bash -c 'source "$0"; echo "${AUTHORIZED_KEYS_URLS}"' "${out}")"
check "la última asignación gana: solo las llaves pedidas" test "$(grep -c 'x.test' <<<"${res}")" = 2
refute "no hereda llaves de otro del ejemplo" grep -q 'dotfiles' <<<"${res}"

finish
