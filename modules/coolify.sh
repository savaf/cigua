# Coolify en este mismo VPS, solo si COOLIFY=1 en el archivo de config del host.
#
# Riesgo asumido: Coolify controla Docker, o sea root efectivo en la máquina. Por eso:
#  - corre bajo su propio usuario (COOLIFY_USER, por defecto "coolify"), distinto de VPS_USER:
#    los agentes no comparten usuario, home ni llaves con Coolify;
#  - panel (8000) publicado SOLO en la IP de la tailnet; realtime y terminal (6001/6002) no se
#    publican en el host: van por el proxy cuando la instancia tiene dominio (COOLIFY_DOMAIN);
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

# Renderiza el drop-in de sshd: el Match exime a localhost y a los rangos de Docker (docker_cidrs).
# $1 = usuario de Coolify.
render_coolify_sshd() {
  local cidrs="" c
  while read -r c; do cidrs+=",!${c}"; done < <(docker_cidrs)
  sed -e "s/__COOLIFY_USER__/$1/g" -e "s|__DOCKER_CIDRS__|${cidrs}|g" "${ROOT_DIR}/files/sshd/90-cigua-coolify.conf"
}

# Instala el drop-in validado: si sshd -t falla se restaura el anterior (un Match roto deja sshd sin
# arrancar tras un reinicio). Siempre valida y recarga, también en repeticiones. $1 = usuario.
install_coolify_sshd() {
  local dropin="${COOLIFY_SSHD_DROPIN:-/etc/ssh/sshd_config.d/90-cigua-coolify.conf}" backup
  backup="$(mktemp)"
  if [[ -f "${dropin}" ]]; then cp -p "${dropin}" "${backup}"; else : >"${backup}"; fi
  render_coolify_sshd "$1" | install_if_changed - "${dropin}" || true
  if ! sshd -t; then
    if [[ -s "${backup}" ]]; then cp -p "${backup}" "${dropin}"; else rm -f "${dropin}"; fi
    rm -f "${backup}"
    die "sshd -t falló con ${dropin}; deshice el cambio"
  fi
  rm -f "${backup}"
  systemctl try-reload-or-restart ssh 2>/dev/null || systemctl try-reload-or-restart sshd
}

# ¿Quién escucha en el puerto $1 (TCP)? Imprime el nombre del proceso (o "proceso desconocido") y
# sale 0 si hay alguien; sale 1 si está libre. Sirve para parar antes de instalar el proxy.
port_in_use_by() {
  local line proc
  line="$(ss -ltnpH "sport = :$1" 2>/dev/null | head -n1 || true)"
  [[ -n "${line}" ]] || return 1
  proc="$(grep -o 'users:(("[^"]*"' <<<"${line}" | head -n1 | sed 's/users:(("//; s/"$//' || true)"
  echo "${proc:-proceso desconocido}"
}

# El proxy de Coolify (Traefik) necesita el 80 y el 443 libres: si no, el instalador falla con un
# "Port 80 is in use" poco claro. Se para antes y se dice quién los tiene.
check_proxy_ports_free() {
  local port who
  for port in 80 443; do
    if who="$(port_in_use_by "${port}")"; then
      die "el puerto ${port} está en uso por ${who}: páralo (p. ej. sudo systemctl disable --now ${who}) y repite"
    fi
  done
}

# Los contenedores entran al host por SSH (Coolify valida su servidor localhost): se permite
# desde los rangos de Docker aunque el 22 público esté cerrado. No lleva el comentario
# "cigua: público", así que el firewall no la concilia ni la borra.
allow_docker_to_ssh() {
  local c
  while read -r c; do
    ufw allow from "${c}" to any port 22 proto tcp comment 'cigua: docker a host' >/dev/null
  done < <(docker_cidrs)
}

# ¿Tiene el archivo alguna llave pública? Solo cuenta líneas, nunca lee llaves privadas.
coolify_has_key() { grep -qE '^(ssh-|ecdsa-|sk-)' "$1" 2>/dev/null; }

# Avisos de lo que el módulo no puede hacer solo. $1 = usuario de Coolify.
coolify_post_checks() {
  local home
  home="$(getent passwd "$1" | cut -d: -f6)"
  coolify_has_key "${home}/.ssh/authorized_keys" \
    || warn "${home}/.ssh/authorized_keys no tiene la llave pública del panel: cópiala desde Servidores → localhost → Current Public Key"
  if [[ -n "${COOLIFY_DOMAIN:-}" ]]; then
    if [[ "${COOLIFY_DOMAIN}" =~ ^[A-Za-z0-9.-]+$ ]]; then
      log "Dominio ${COOLIFY_DOMAIN}: crea un registro A hacia la IP pública del VPS y luego pon https://${COOLIFY_DOMAIN} en Settings → Instance's Domain"
    else
      warn "COOLIFY_DOMAIN no parece un dominio válido; lo ignoro"
    fi
  fi
  warn "El instalador de Coolify crea el servidor localhost con usuario root: en el panel (Servidores → localhost) cámbialo a $1 y pulsa Validate."
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
  install_coolify_sshd "${COOLIFY_USER}"
  allow_docker_to_ssh

  # El override va ANTES de instalar: así el panel nunca llega a escuchar en 0.0.0.0.
  mkdir -p "${COOLIFY_DIR}"
  render_coolify_compose "${ip}" | install_if_changed - "${COOLIFY_DIR}/docker-compose.custom.yml" 0644 || true

  if exists docker && docker ps -a --format '{{.Names}}' | grep -qx coolify; then
    log "Coolify ya instalado: aplico el override de puertos"
    (cd "${COOLIFY_DIR}" && docker compose -f docker-compose.yml -f docker-compose.prod.yml -f docker-compose.custom.yml up -d) \
      || warn "no pude reaplicar el compose; revisa ${COOLIFY_DIR}"
    coolify_post_checks "${COOLIFY_USER}"
    return
  fi

  check_proxy_ports_free

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
  log "panel en http://${ip}:8000 (solo por la tailnet). Revisa: ss -tlnp | grep ':8000'"
  coolify_post_checks "${COOLIFY_USER}"
}
