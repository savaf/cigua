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
# Determinista: "hay sesión SSH" lo decide FAKE_SSH, no el árbol de procesos del test.
in_ssh_session() { [[ -n "${SSH_CONNECTION:-}" || "${FAKE_SSH:-0}" == 1 ]]; }

# Corre el módulo como si la sesión viniera de $1 (vacío = consola).
run_from() {
  : >"${UFW_LOG}"
  if [[ -n "$1" ]]; then
    SSH_CONNECTION="$1 50000 10.0.0.5 22" run_firewall >/dev/null 2>&1
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

run_from ""
check "desde consola (sin SSH): cierra el 22 público" closed

FAKE_SSH=1 run_from ""
check "SSH sin TTY (IP desconocida): deja el 22 público" kept
refute "SSH sin TTY (IP desconocida): NO cierra" closed

PUBLIC_TCP_PORTS="80 443" run_from 100.101.1.2
check "PUBLIC_TCP_PORTS abre 80" grep -q '^allow 80/tcp' "${UFW_LOG}"
check "PUBLIC_TCP_PORTS abre 443" grep -q '^allow 443/tcp' "${UFW_LOG}"

finish
