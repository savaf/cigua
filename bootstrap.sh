#!/usr/bin/env bash
set -euo pipefail

# Punto de entrada único del VPS. Idempotente: se puede correr cuantas veces haga falta.
#   sudo ./bootstrap.sh            # todos los módulos, en orden
#   sudo ./bootstrap.sh firewall   # solo los módulos indicados
#   ./bootstrap.sh --list          # lista los módulos sin ejecutar nada
# Ver docs/primer-arranque.md.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export ROOT_DIR
source "${ROOT_DIR}/lib/common.sh"

# Orden importa: el usuario antes que ssh (que cierra el login de root), Tailscale antes
# que el firewall (que deja el SSH solo en la tailnet), git-key antes que agents (clona por SSH).
MODULES=(base swap user tailscale ssh firewall hardening coolify dotfiles git-key claude-managed agents)

describe() {
  case "$1" in
    base)           echo "paquetes base, hostname, zona horaria, actualizaciones automáticas" ;;
    swap)           echo "swapfile (agentes + builds en un VPS pequeño)" ;;
    user)           echo "usuario de trabajo, sudo, linger, authorized_keys" ;;
    tailscale)      echo "unir el VPS a la tailnet con tag:server" ;;
    ssh)            echo "endurecer sshd: sin contraseñas ni root" ;;
    firewall)       echo "ufw: SSH solo por tailscale0 (con guarda anti-bloqueo)" ;;
    hardening)      echo "sysctl y fail2ban (tailnet exenta)" ;;
    coolify)        echo "Coolify en este VPS, solo con COOLIFY=1 (panel solo por la tailnet)" ;;
    dotfiles)       echo "clonar savaf/dotfiles y correr su bootstrap (shell, Claude, herdr)" ;;
    git-key)        echo "llave SSH de la máquina + ssh-agent de usuario" ;;
    claude-managed) echo "hooks de Claude solo de este VPS (avisos a ntfy)" ;;
    agents)         echo "Claude Code instalado y repos de repos.txt clonados" ;;
  esac
}

# Módulos pedidos, en el orden de MODULES y sin repetir. Un nombre que no esté en MODULES
# muere: así `../../tmp/x` nunca llega a cargarse como código.
order_modules() {
  local m want ok
  for want in "$@"; do
    ok=0
    for m in "${MODULES[@]}"; do [[ "${m}" == "${want}" ]] && ok=1; done
    (( ok )) || die "módulo desconocido: ${want} (ver --list)"
  done
  for m in "${MODULES[@]}"; do
    for want in "$@"; do
      if [[ "${m}" == "${want}" ]]; then echo "${m}"; break; fi
    done
  done
}

main() {
  if [[ "${1:-}" == "--list" ]]; then
    for m in "${MODULES[@]}"; do printf '%-15s %s\n' "${m}" "$(describe "${m}")"; done
    return
  fi

  require_root "$@"
  load_host_env

  local selected=() ordered
  if (( $# )); then
    ordered="$(order_modules "$@")"   # asignación simple: si muere, set -e corta aquí
    mapfile -t selected <<<"${ordered}"
  else
    selected=("${MODULES[@]}")
  fi

  local n=0 total=${#selected[@]}
  for m in "${selected[@]}"; do
    n=$((n + 1))
    log "── [${n}/${total}] ${m}: $(describe "${m}")"
    # Cada módulo define run_<nombre con _> y nada más.
    source "${ROOT_DIR}/modules/${m}.sh"
    "run_${m//-/_}"
  done
  [[ -e /var/run/reboot-required ]] && warn "Ubuntu pide reiniciar (kernel o libc nuevos). Hazlo cuando no haya agentes corriendo: sudo reboot"
  log "Listo."
}

# CIGUA_BOOTSTRAP_SOURCED=1 permite cargar las funciones en tests sin ejecutar nada.
[[ -n "${CIGUA_BOOTSTRAP_SOURCED:-}" ]] || main "$@"
