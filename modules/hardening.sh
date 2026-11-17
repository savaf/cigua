# Endurecimiento del sistema: parámetros de kernel y fail2ban para sshd.
# (Las directivas extra de sshd viven en files/sshd/10-cigua.conf, módulo ssh.)

run_hardening() {
  if install_if_changed "${ROOT_DIR}/files/sysctl/90-cigua-hardening.conf" /etc/sysctl.d/90-cigua-hardening.conf; then
    sysctl -q --system || warn "sysctl no aplicó todo; revisa /etc/sysctl.d/90-cigua-hardening.conf"
  fi

  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq fail2ban >/dev/null
  if install_if_changed "${ROOT_DIR}/files/fail2ban/cigua.conf" /etc/fail2ban/jail.d/cigua.conf; then
    systemctl restart fail2ban
  fi
  systemctl enable --now fail2ban >/dev/null 2>&1 || true
  log "hardening listo: sysctl + fail2ban (tailnet exenta)"
}
