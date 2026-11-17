# Endurece sshd con un drop-in (no toca sshd_config). Solo cierra el login de root si
# VPS_USER ya tiene llaves: si no, te quedarías fuera.
# El drop-in se valida antes de dejarlo activo: si sshd -t falla se restaura el anterior.

run_ssh() {
  local ak dropin="${SSHD_DROPIN:-/etc/ssh/sshd_config.d/10-cigua.conf}"
  ak="$(user_home)/.ssh/authorized_keys"
  if ! grep -qE '^(ssh-|ecdsa-|sk-)' "${ak}" 2>/dev/null; then
    warn "${VPS_USER} no tiene llaves en ${ak}: no endurezco sshd (corre el módulo user)."
    return
  fi

  local backup
  backup="$(mktemp)"
  if [[ -f "${dropin}" ]]; then cp -p "${dropin}" "${backup}"; else : >"${backup}"; fi

  install_if_changed "${ROOT_DIR}/files/sshd/10-cigua.conf" "${dropin}" || true
  if ! sshd -t; then
    # Restaurar antes de morir: un drop-in roto dejaría sshd sin arrancar tras un reinicio.
    if [[ -s "${backup}" ]]; then cp -p "${backup}" "${dropin}"; else rm -f "${dropin}"; fi
    rm -f "${backup}"
    die "sshd -t falló; deshice el cambio de ${dropin}"
  fi
  rm -f "${backup}"
  # Siempre se recarga (también en repeticiones): ssh por socket puede no estar activo todavía.
  systemctl try-reload-or-restart ssh 2>/dev/null || systemctl try-reload-or-restart sshd
  log "sshd validado y recargado: solo llaves, sin root. Tu sesión actual sigue abierta."
}
