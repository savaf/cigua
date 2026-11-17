#!/usr/bin/env bash
set -euo pipefail

# Test de la guarda anti-bloqueo de modules/firewall.sh con ufw/tailscale/ip/who falsos:
# el SSH público solo se cierra si entraste por la tailnet, por consola o con FORCE.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/lib/common.sh"
source "${ROOT_DIR}/tests/lib.sh"
source "${ROOT_DIR}/modules/firewall.sh"

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
mkdir -p "${work}/bin"
for cmd in tailscale ip who; do printf '#!/bin/sh\nexit 0\n' >"${work}/bin/${cmd}"; done
cat >"${work}/bin/ufw" <<'EOF'
#!/bin/sh
echo "$*" >>"${UFW_LOG}"
EOF
chmod +x "${work}/bin/"*
export PATH="${work}/bin:${PATH}" UFW_LOG="${work}/ufw.log"
VPS_HOSTNAME=cigua
# Estos tests cubren la guarda de SSH_PUBLIC=0; SSH_PUBLIC=1 (el defecto) tiene su sección al final.
export SSH_PUBLIC=0
# Determinista: "es una consola real" lo decide FAKE_CONSOLE, no la tty del test.
is_console_tty() { [[ "${FAKE_CONSOLE:-0}" == 1 ]]; }

# Corre el módulo como si la sesión viniera de $1 (vacío = sin SSH_CONNECTION ni who).
# $2 = IP local por la que entró (por defecto, una de la tailnet si el cliente lo es).
run_from() {
  : >"${UFW_LOG}"
  if [[ -n "$1" ]]; then
    local local_ip="${2:-10.0.0.5}"
    is_tailnet_ip "$1" && local_ip="${2:-100.100.0.9}"
    SSH_CONNECTION="$1 50000 ${local_ip} 22" run_firewall >/dev/null 2>&1
  else
    (unset SSH_CONNECTION; run_firewall >/dev/null 2>&1)
  fi
}
closed()   { grep -qx 'delete allow 22/tcp' "${UFW_LOG}"; }
kept()     { grep -q '^allow 22/tcp' "${UFW_LOG}"; }
tailnet()  { grep -q '^allow in on tailscale0 to any port 22 proto tcp' "${UFW_LOG}"; }
enabled()  { grep -qx -- '--force enable' "${UFW_LOG}"; }

echo "firewall"
run_from 100.101.1.2
check "desde la tailnet: abre 22 en tailscale0" tailnet
check "desde la tailnet: cierra el 22 público" closed
refute "desde la tailnet: no deja el 22 público" kept
check "desde la tailnet: activa ufw" enabled

run_from 203.0.113.7
check "desde IP pública: deja el 22 público" kept
refute "desde IP pública: NO cierra el 22 público" closed
check "desde IP pública: igual abre 22 en tailscale0" tailnet

FORCE_FIREWALL=1 run_from 203.0.113.7
check "FORCE_FIREWALL=1: cierra aunque vengas de fuera" closed

FAKE_CONSOLE=1 run_from ""
check "desde consola real (sin IP de cliente): cierra el 22 público" closed

run_from ""
check "tmux/herdr dentro de SSH (sin IP ni consola): deja el 22 público" kept
refute "tmux/herdr dentro de SSH: NO cierra" closed

run_from 100.101.1.2 10.0.0.5
check "cliente 100.64/10 pero entró por IP no tailnet: deja el 22 público" kept
refute "cliente 100.64/10 pero entró por IP no tailnet: NO cierra" closed

cat >"${work}/bin/ufw" <<'EOF'
#!/bin/sh
echo "$*" >>"${UFW_LOG}"
[ "$1" = status ] && printf '80/tcp ALLOW IN Anywhere # cigua: público\n443/tcp ALLOW IN Anywhere # cigua: público\n22/tcp ALLOW IN Anywhere # cigua: ssh por tailnet\n'
exit 0
EOF
PUBLIC_TCP_PORTS="443" run_from 100.101.1.2
check "regla pública que sobra (80): se borra" grep -qx 'delete allow 80/tcp' "${UFW_LOG}"
refute "regla pública que sigue en la lista (443): no se borra" grep -qx 'delete allow 443/tcp' "${UFW_LOG}"
refute "la regla de la tailnet no se borra al conciliar" grep -q 'delete allow in on tailscale0' "${UFW_LOG}"
PUBLIC_TCP_PORTS="" run_from 100.101.1.2
check "PUBLIC_TCP_PORTS vacío: se borran 80 y 443" bash -c "grep -qx 'delete allow 80/tcp' '${UFW_LOG}' && grep -qx 'delete allow 443/tcp' '${UFW_LOG}'"

PUBLIC_TCP_PORTS="80 443" run_from 100.101.1.2
check "PUBLIC_TCP_PORTS abre 80" grep -q '^allow 80/tcp' "${UFW_LOG}"
check "PUBLIC_TCP_PORTS abre 443" grep -q '^allow 443/tcp' "${UFW_LOG}"

echo "firewall (SSH_PUBLIC=1, el defecto)"
unset SSH_PUBLIC
run_from 203.0.113.7
check "por defecto: 22 público abierto aunque vengas de fuera" kept
refute "por defecto: nunca cierra el 22 público" closed
check "por defecto: activa ufw" enabled
run_from 100.101.1.2
refute "por defecto: tampoco lo cierra desde la tailnet" closed
refute "por defecto: no abre 8000 ni los puertos del panel" grep -Eq 'allow (8000|6001|6002)' "${UFW_LOG}"
FAKE_CONSOLE=1 run_from ""
refute "por defecto: ni desde consola" closed
SSH_PUBLIC=0 run_from 100.101.1.2
check "SSH_PUBLIC=0: vuelve a cerrar desde la tailnet" closed

finish
