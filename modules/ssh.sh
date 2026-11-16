# Endurece sshd con un drop-in (no toca sshd_config). Solo cierra el login de root si
# VPS_USER ya tiene llaves: si no, te quedarías fuera.

run_ssh() {
  local ak
  ak="$(user_home)/.ssh/authorized_keys"
  if ! grep -qE '^(ssh-|ecdsa-|sk-)' "${ak}" 2>/dev/null; then
    warn "${VPS_USER} no tiene llaves en ${ak}: no endurezco sshd (corre el módulo user)."
    return
  fi

  if install_if_changed "${ROOT_DIR}/files/sshd/10-cigua.conf" /etc/ssh/sshd_config.d/10-cigua.conf; then
    sshd -t || die "sshd -t falló; revisa /etc/ssh/sshd_config.d/10-cigua.conf"
    # Ubuntu 24.04 activa ssh por socket; recargar el servicio basta en ambos casos.
    systemctl reload ssh 2>/dev/null || systemctl reload sshd
    log "sshd recargado: solo llaves, sin root. Tu sesión actual sigue abierta."
  else
    log "sshd ya endurecido"
  fi
}
