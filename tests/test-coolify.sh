#!/usr/bin/env bash
set -euo pipefail

# Guardas de modules/coolify.sh y contenido de los archivos de hardening, sin tocar el sistema.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/lib/common.sh"
source "${ROOT_DIR}/tests/lib.sh"
source "${ROOT_DIR}/modules/coolify.sh"

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
mkdir -p "${work}/bin"
cat >"${work}/bin/tailscale" <<'FAKE'
#!/bin/sh
echo "${TS_IP-100.101.1.2}"
FAKE
cat >"${work}/bin/curl" <<'FAKE'
#!/bin/sh
echo "$*" >>"${CALLS}"
FAKE
chmod +x "${work}/bin/"*
export PATH="${work}/bin:${PATH}" CALLS="${work}/calls"
: >"${CALLS}"
VPS_USER=nadie

# Corre el módulo en un subshell limpio con las variables dadas.
run_with() {
  # shellcheck disable=SC2016
  env "$@" bash -c 'source "$ROOT_DIR/lib/common.sh"; source "$ROOT_DIR/modules/coolify.sh"; run_coolify' >/dev/null 2>&1
}
export ROOT_DIR

echo "coolify"
COOLIFY=0 run_coolify >/dev/null
refute "COOLIFY=0: no descarga nada" test -s "${CALLS}"

refute "IP que no es de tailnet: falla" run_with COOLIFY=1 TS_IP=8.8.8.8 COOLIFY_ADMIN_EMAIL=a@b COOLIFY_ADMIN_PASSWORD=x
refute "sin admin por entorno: falla" run_with COOLIFY=1 COOLIFY_ADMIN_EMAIL= COOLIFY_ADMIN_PASSWORD=
refute "falla antes de descargar nada" test -s "${CALLS}"

out="$(render_coolify_compose 100.101.1.2)"
check "override: panel en la IP de la tailnet" grep -q '"100.101.1.2:8000:8080"' <<<"${out}"
check "override: realtime en la IP de la tailnet" grep -q '"100.101.1.2:6001:6001"' <<<"${out}"
refute "override: nada en 0.0.0.0" grep -q '0\.0\.0\.0' <<<"$(grep -v '^ *#' <<<"${out}")"
refute "override: sin marcador sin sustituir" grep -q '__TAILNET_IP__' <<<"${out}"

echo "hardening (archivos)"
check "fail2ban exime la tailnet" grep -q '100.64.0.0/10' "${ROOT_DIR}/files/fail2ban/cigua.conf"
check "sysctl: rp_filter" grep -q 'rp_filter = 1' "${ROOT_DIR}/files/sysctl/90-cigua-hardening.conf"
refute "sshd principal sin Match (no filtra a otros archivos)" grep -q '^Match' "${ROOT_DIR}/files/sshd/10-cigua.conf"
ssh90="${ROOT_DIR}/files/sshd/90-cigua-coolify.conf"
refute "ssh de Coolify: no toca PermitRootLogin" grep -q 'PermitRootLogin' "${ssh90}"
check "ssh de Coolify: niega al usuario fuera de local/Docker" grep -q 'DenyUsers __COOLIFY_USER__' "${ssh90}"

echo "usuario de coolify"
check "sudoers del usuario" test "$(coolify_sudoers coolify)" = "coolify ALL=(ALL) NOPASSWD:SETENV:ALL"
refute "COOLIFY_USER igual a VPS_USER: falla" run_with COOLIFY=1 VPS_USER=cigua COOLIFY_USER=cigua COOLIFY_ADMIN_EMAIL=a@b COOLIFY_ADMIN_PASSWORD=x
refute "COOLIFY_USER=root: falla" run_with COOLIFY=1 VPS_USER=cigua COOLIFY_USER=root COOLIFY_ADMIN_EMAIL=a@b COOLIFY_ADMIN_PASSWORD=x
refute "usuario inválido: no descarga nada" test -s "${CALLS}"

finish
