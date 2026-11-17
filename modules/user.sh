# Usuario de trabajo: dueño de los agentes, de herdr y de los repos.
# Nunca en el grupo docker: un agente con acceso a docker es root en la máquina.

run_user() {
  if ! id "${VPS_USER}" >/dev/null 2>&1; then
    log "creando usuario ${VPS_USER}"
    adduser --disabled-password --gecos "" "${VPS_USER}"
  fi
  # La contraseña la usa sudo (y el bootstrap de dotfiles). Se lee de la terminal, no de
  # stdin: con `curl | bash` stdin es el pipe y passwd aborta sin contraseña.
  if ! has_password "${VPS_USER}"; then
    if have_tty; then
      log "elige la contraseña de ${VPS_USER} (la pide sudo)"
      local _
      for _ in 1 2 3; do
        passwd "${VPS_USER}" </dev/tty || true
        has_password "${VPS_USER}" && break
      done
      has_password "${VPS_USER}" || die "no se fijó la contraseña de ${VPS_USER}: corre 'passwd ${VPS_USER}' y repite"
    else
      die "${VPS_USER} no tiene contraseña y no hay terminal: corre 'passwd ${VPS_USER}' y repite"
    fi
  fi
  usermod -aG sudo "${VPS_USER}"

  if id -nG "${VPS_USER}" | tr ' ' '\n' | grep -qx docker; then
    warn "${VPS_USER} está en el grupo docker: los agentes tendrían root."
    warn "Quítalo con: sudo gpasswd -d ${VPS_USER} docker"
  fi

  # linger: el systemd de usuario (ssh-agent, teamclaude) vive sin sesión abierta.
  loginctl enable-linger "${VPS_USER}"

  install_authorized_keys
}

install_authorized_keys() {
  local home keys="" url key
  home="$(user_home)"
  install -d -m 700 -o "${VPS_USER}" -g "${VPS_USER}" "${home}/.ssh"

  for url in ${AUTHORIZED_KEYS_URLS:-}; do
    key="$(curl -fsSL -m 10 "${url}")" || { warn "no pude bajar ${url}"; continue; }
    [[ "${key}" == ssh-* ]] || { warn "${url} no parece una llave pública; la salto"; continue; }
    keys+="${key}"$'\n'
  done

  # Las llaves con las que ya entras como root, para no perder el acceso al cerrar root (módulo ssh).
  if [[ -s /root/.ssh/authorized_keys ]]; then
    keys+="$(grep -E '^(ssh-|ecdsa-|sk-)' /root/.ssh/authorized_keys || true)"$'\n'
  fi

  keys="$(printf '%s' "${keys}" | sed '/^$/d' | sort -u)"
  [[ -n "${keys}" ]] || { warn "ninguna llave para ${VPS_USER}: el módulo ssh no cerrará root"; return; }

  local ak="${home}/.ssh/authorized_keys"
  touch "${ak}"
  write_managed_block "${ak}" "${keys}"
  chown "${VPS_USER}:${VPS_USER}" "${ak}"
  chmod 600 "${ak}"
  log "authorized_keys: $(grep -c '^ssh-\|^ecdsa-\|^sk-' "${ak}") llave(s)"
}
