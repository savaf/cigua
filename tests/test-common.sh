#!/usr/bin/env bash
set -euo pipefail

# Tests de lib/common.sh: la guarda anti-bloqueo del firewall y los bloques gestionados.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/lib/common.sh"
source "${ROOT_DIR}/tests/lib.sh"

echo "is_tailnet_ip"
for ip in 100.64.0.1 100.100.100.100 100.127.255.254; do
  check "${ip} es tailnet" is_tailnet_ip "${ip}"
done
for ip in 100.63.255.255 100.128.0.1 10.0.0.1 192.168.1.10 8.8.8.8 "" "100.64" "fe80::1" "100.64.0.x"; do
  refute "'${ip}' no es tailnet" is_tailnet_ip "${ip}"
done

echo "ssh_client_ip"
got="$(SSH_CONNECTION="100.101.1.2 51234 10.0.0.5 22" ssh_client_ip)"
check "lee SSH_CONNECTION" test "${got}" = "100.101.1.2"

echo "write_managed_block"
tmp="$(mktemp)"
printf 'linea propia\n' >"${tmp}"
write_managed_block "${tmp}" "uno"
write_managed_block "${tmp}" "dos"
check "un solo bloque tras dos escrituras" test "$(grep -c '>>> cigua' "${tmp}")" = 1
check "escribe el contenido nuevo" grep -qx 'dos' "${tmp}"
refute "borra el contenido viejo" grep -qx 'uno' "${tmp}"
check "respeta lo de fuera del bloque" grep -qx 'linea propia' "${tmp}"
rm -f "${tmp}"

echo "install_if_changed"
dir="$(mktemp -d)"
installs() { printf 'a\n' | install_if_changed - "${dir}/f" >/dev/null; }
check "instala si no existe" installs
refute "no reinstala si es igual" installs
check "contenido desde stdin" test "$(cat "${dir}/f")" = a
rm -rf "${dir}"

finish
