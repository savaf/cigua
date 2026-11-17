# Coolify en este mismo VPS, solo si COOLIFY=1 en el archivo de config del host.
#
# Riesgo asumido: Coolify controla Docker, o sea root efectivo en la máquina. Por eso:
#  - corre bajo su propio usuario (COOLIFY_USER, por defecto "coolify"), distinto de VPS_USER:
#    los agentes no comparten usuario, home ni llaves con Coolify;
#  - panel (8000) y realtime (6001/6002) publicados SOLO en la IP de la tailnet;
#  - 80/443 los abre PUBLIC_TCP_PORTS (proxy de Coolify), nada más;
#  - VPS_USER nunca entra al grupo docker (módulo user);
#  - root sigue sin poder entrar por SSH; ese usuario solo entra desde localhost y Docker;
#  - el admin se crea desde el entorno, para que nadie se registre primero.
# Secretos solo por entorno: COOLIFY_ADMIN_EMAIL, COOLIFY_ADMIN_PASSWORD (y opc. COOLIFY_ADMIN_USER).
#   sudo COOLIFY_ADMIN_EMAIL=… COOLIFY_ADMIN_PASSWORD=… ./bootstrap.sh coolify

COOLIFY_DIR="${COOLIFY_DIR:-/data/coolify/source}"
COOLIFY_USER="${COOLIFY_USER:-coolify}"

# Renderiza el compose de override con la IP de la tailnet.
render_coolify_compose() {
  sed "s/__TAILNET_IP__/$1/g" "${ROOT_DIR}/files/coolify/docker-compose.custom.yml.tpl"
}

# Línea de sudoers: Coolify administra Docker y el host. SETENV para el `sudo -E` del instalador.
coolify_sudoers() {
  echo "$1 ALL=(ALL) NOPASSWD:SETENV:ALL"
}

# Crea el usuario sin contraseña (solo entra por llave) y su sudoers, validado con visudo.
ensure_coolify_user() {
  local user="$1" tmp
  if ! id "${user}" >/dev/null 2>&1; then
    useradd --create-home --shell /bin/bash --comment "Coolify" "${user}"
    passwd -l "${user}" >/dev/null
    log "usuario ${user} creado (sin contraseña)"
  fi
  install -d -m 700 -o "${user}" -g "${user}" "$(getent passwd "${user}" | cut -d: -f6)/.ssh"
  tmp="$(mktemp)"
  coolify_sudoers "${user}" >"${tmp}"
  visudo -cf "${tmp}" >/dev/null || { rm -f "${tmp}"; die "sudoers inválido para ${user}"; }
  install_if_changed "${tmp}" "/etc/sudoers.d/90-cigua-coolify" 0440 || true
  rm -f "${tmp}"
}

run_coolify() {
  if [[ "${COOLIFY:-0}" != 1 ]]; then
    log "COOLIFY!=1: omitido"
    return
  fi

  local ip
  ip="$(tailscale ip -4 2>/dev/null | head -n1)"
  is_tailnet_ip "${ip}" || die "no obtengo la IP de la tailnet: corre el módulo tailscale primero"
  : "${COOLIFY_ADMIN_EMAIL:?pasa COOLIFY_ADMIN_EMAIL por entorno (el primer registro sería admin)}"
  : "${COOLIFY_ADMIN_PASSWORD:?pasa COOLIFY_ADMIN_PASSWORD por entorno}"

  [[ "${COOLIFY_USER}" != "${VPS_USER}" ]] || die "COOLIFY_USER y VPS_USER deben ser distintos (si no, los agentes serían Coolify)"
  [[ "${COOLIFY_USER}" != root ]] || die "COOLIFY_USER no puede ser root"
  if id -nG "${VPS_USER}" 2>/dev/null | tr ' ' '\n' | grep -qx docker; then
    die "${VPS_USER} está en el grupo docker: quítalo antes (sudo gpasswd -d ${VPS_USER} docker)"
  fi

  ensure_coolify_user "${COOLIFY_USER}"

  # El usuario de Coolify solo entra por SSH desde localhost y la red de Docker.
  if sed "s/__COOLIFY_USER__/${COOLIFY_USER}/g" "${ROOT_DIR}/files/sshd/90-cigua-coolify.conf" \
      | install_if_changed - /etc/ssh/sshd_config.d/90-cigua-coolify.conf; then
    sshd -t || die "sshd -t falló con 90-cigua-coolify.conf"
    systemctl reload ssh 2>/dev/null || systemctl reload sshd
  fi

  # El override va ANTES de instalar: así el panel nunca llega a escuchar en 0.0.0.0.
  mkdir -p "${COOLIFY_DIR}"
  render_coolify_compose "${ip}" | install_if_changed - "${COOLIFY_DIR}/docker-compose.custom.yml" 0644 || true

  if exists docker && docker ps -a --format '{{.Names}}' | grep -qx coolify; then
    log "Coolify ya instalado: aplico el override de puertos"
    (cd "${COOLIFY_DIR}" && docker compose -f docker-compose.yml -f docker-compose.prod.yml -f docker-compose.custom.yml up -d) \
      || warn "no pude reaplicar el compose; revisa ${COOLIFY_DIR}"
    return
  fi

  local script
  script="$(mktemp)"
  curl -fsSL https://cdn.coollabs.io/coolify/install.sh -o "${script}"
  chmod 755 "${script}"
  log "instalador descargado, sha256 $(sha256sum "${script}" | cut -d' ' -f1)"
  # Como usuario no root, el instalador se lanza con `sudo -E` (docs de Coolify). Los secretos
  # pasan por entorno (--preserve-env), no por argumentos visibles en ps.
  ROOT_USERNAME="${COOLIFY_ADMIN_USER:-admin}" \
  ROOT_USER_EMAIL="${COOLIFY_ADMIN_EMAIL}" \
  ROOT_USER_PASSWORD="${COOLIFY_ADMIN_PASSWORD}" \
    sudo -u "${COOLIFY_USER}" -H --preserve-env=ROOT_USERNAME,ROOT_USER_EMAIL,ROOT_USER_PASSWORD \
      sudo -E bash "${script}"
  rm -f "${script}"

  # Coolify opera Docker como este usuario; el grupo existe una vez instalado Docker.
  if getent group docker >/dev/null; then usermod -aG docker "${COOLIFY_USER}"; fi
  log "panel en http://${ip}:8000 (solo por la tailnet). Revisa: ss -tlnp | grep -E ':(8000|6001|6002)'"
}
