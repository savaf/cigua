# ufw: todo cerrado salvo el SSH y PUBLIC_TCP_PORTS.
#
# SSH_PUBLIC=1 (por defecto): el 22 queda abierto también fuera de la tailnet (solo llaves, sin
# root, fail2ban). Así Coolify valida su servidor localhost y entras sin Tailscale. Los puertos del
# panel de Coolify (8000, 6001, 6002) NO se abren aquí: solo escuchan en la IP de la tailnet.
# SSH_PUBLIC=0: SSH solo por tailscale0, con la guarda anti-bloqueo de abajo.
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

  reconcile_public_ports

  if [[ "${SSH_PUBLIC:-1}" == 1 ]]; then
    ufw allow 22/tcp comment 'cigua: ssh público' >/dev/null
    log "SSH público abierto (SSH_PUBLIC=1): solo llaves, sin root. 8000/6001/6002 siguen solo en la tailnet"
    ufw --force enable >/dev/null
    ufw status verbose
    return
  fi

  local client local_ip
  client="$(ssh_client_ip)"
  local_ip="$(awk '{print $3}' <<<"${SSH_CONNECTION:-}")"
  # Solo se cierra con una prueba positiva: FORCE, cliente de la tailnet (y, si se conoce, que la
  # sesión también entrara por una IP de la tailnet) o una consola real. Ante la duda se queda abierto:
  # dentro de tmux/herdr no hay SSH_CONNECTION ni `who -m`, y eso NO prueba que sea una consola.
  if [[ "${FORCE_FIREWALL:-0}" == 1 ]] \
      || { [[ -n "${client}" ]] && is_tailnet_ip "${client}" \
           && { [[ -z "${local_ip}" ]] || is_tailnet_ip "${local_ip}"; }; } \
      || { [[ -z "${client}" ]] && is_console_tty; }; then
    close_public_ssh
  else
    ufw allow 22/tcp comment 'cigua: ssh público temporal' >/dev/null
    warn "entraste desde ${client:-una IP desconocida} (no confirmo que sea la tailnet): dejo el SSH público abierto."
    warn "Entra con 'ssh -t ${VPS_HOSTNAME}' por Tailscale y corre de nuevo: sudo ./bootstrap.sh firewall"
  fi

  ufw --force enable >/dev/null
  ufw status verbose
}

# Quita las reglas "cigua: público" que ya no están en PUBLIC_TCP_PORTS: vacío = solo la tailnet.
reconcile_public_ports() {
  local rule port keep
  while read -r rule; do
    keep=0
    for port in ${PUBLIC_TCP_PORTS:-}; do [[ "${rule}" == "${port}/tcp" ]] && keep=1; done
    (( keep )) && continue
    ufw delete allow "${rule}" >/dev/null 2>&1 || true
    log "puerto público cerrado: ${rule}"
  done < <(ufw status | awk '/cigua: público/ {print $1}' | sort -u)
}

close_public_ssh() {
  local rule
  for rule in '22/tcp' '22' 'OpenSSH'; do
    ufw delete allow "${rule}" >/dev/null 2>&1 || true
  done
  log "SSH público cerrado: solo se entra por la tailnet"
}
