# ufw: todo cerrado salvo SSH por la tailnet y PUBLIC_TCP_PORTS.
#
# Guarda anti-bloqueo: el SSH público solo se cierra si quien corre esto entró por la
# tailnet (IP 100.64.0.0/10) o desde la consola del proveedor. Si entraste por la IP
# pública, el puerto 22 público se queda abierto y te avisa: entra con `ssh <hostname>`
# por Tailscale y vuelve a correr `sudo ./bootstrap.sh firewall`.
# FORCE_FIREWALL=1 se salta la guarda (solo si sabes lo que haces).
#
# Docker publica puertos con sus propias reglas de iptables y se salta ufw: si este VPS
# corre Coolify o contenedores con puertos publicados, ver docs/recuperacion.md.

run_firewall() {
  tailscale status >/dev/null 2>&1 || die "Tailscale no está conectado; corre el módulo tailscale primero"
  ip link show tailscale0 >/dev/null 2>&1 || die "no existe la interfaz tailscale0"

  ufw default deny incoming >/dev/null
  ufw default allow outgoing >/dev/null
  ufw allow in on tailscale0 to any port 22 proto tcp comment 'cigua: ssh por tailnet' >/dev/null

  local port
  for port in ${PUBLIC_TCP_PORTS:-}; do
    ufw allow "${port}/tcp" comment 'cigua: público' >/dev/null
    log "puerto público abierto: ${port}/tcp"
  done

  local client
  client="$(ssh_client_ip)"
  if [[ "${FORCE_FIREWALL:-0}" == 1 ]] \
      || { [[ -n "${client}" ]] && is_tailnet_ip "${client}"; } \
      || { [[ -z "${client}" ]] && ! in_ssh_session; }; then
    close_public_ssh
  else
    ufw allow 22/tcp comment 'cigua: ssh público temporal' >/dev/null
    warn "entraste desde ${client:-una IP desconocida} (no confirmo que sea la tailnet): dejo el SSH público abierto."
    warn "Entra con 'ssh -t ${VPS_HOSTNAME}' por Tailscale y corre de nuevo: sudo ./bootstrap.sh firewall"
  fi

  ufw --force enable >/dev/null
  ufw status verbose
}

close_public_ssh() {
  local rule
  for rule in '22/tcp' '22' 'OpenSSH'; do
    ufw delete allow "${rule}" >/dev/null 2>&1 || true
  done
  log "SSH público cerrado: solo se entra por la tailnet"
}
