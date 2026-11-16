# Llave SSH propia del VPS para GitHub (autenticación y firma de commits).
#
# Excepción documentada a "las llaves privadas solo viven en Bitwarden": aquí no hay
# Bitwarden de escritorio y los agentes tienen que poder hacer commit y push sin ti.
# La llave vive en disco, la carga un ssh-agent de usuario, y tus dotfiles la usan igual
# que en las PCs (~/.ssh/github.pub -> ~/.ssh/<hostname>.pub).
# Costo: quien tenga el VPS firma como tú. Rótala si lo sospechas (docs/recuperacion.md).

run_git_key() {
  local home key pub
  home="$(user_home)"
  key="${home}/.ssh/${VPS_HOSTNAME}_ed25519"
  pub="${key}.pub"
  # Directorios creados como el usuario: install -D como root los dejaría de root.
  as_user mkdir -p "${home}/.ssh" "${home}/.config/systemd/user"
  chmod 700 "${home}/.ssh"

  if [[ ! -f "${key}" ]]; then
    log "generando ${key}"
    as_user ssh-keygen -q -t ed25519 -N "" -C "${VPS_HOSTNAME}" -f "${key}"
  fi

  # ssh-agent de usuario, siempre arriba gracias a linger (módulo user).
  local unit="${home}/.config/systemd/user/ssh-agent.service"
  local tmp
  tmp="$(mktemp)"
  sed "s|@KEY@|${VPS_HOSTNAME}_ed25519|" "${ROOT_DIR}/files/systemd-user/ssh-agent.service" >"${tmp}"
  if install_if_changed "${tmp}" "${unit}"; then
    chown "${VPS_USER}:${VPS_USER}" "${unit}"
    as_user systemctl --user daemon-reload
  fi
  rm -f "${tmp}"
  as_user systemctl --user enable --now ssh-agent.service >/dev/null
  as_user systemctl --user restart ssh-agent.service

  # zsh lee ~/.zshenv en toda shell (también en los paneles de herdr). Tus dotfiles no
  # gestionan ~/.zshenv, así que no hay conflicto con stow.
  local zshenv="${home}/.zshenv"
  touch "${zshenv}"
  # shellcheck disable=SC2016 # se expande al cargar ~/.zshenv, no aquí
  write_managed_block "${zshenv}" 'export SSH_AUTH_SOCK="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/ssh-agent.socket"'
  chown "${VPS_USER}:${VPS_USER}" "${zshenv}"

  if as_user ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -T git@github.com 2>&1 \
      | grep -q 'successfully authenticated'; then
    log "GitHub acepta la llave de ${VPS_HOSTNAME} ✔"
    return
  fi

  local email
  email="$(as_user git config --global user.email 2>/dev/null || true)"
  cat <<EOF

[cigua] Falta registrar la llave del VPS. Desde una PC, en tus dotfiles:

  1. Guarda la pública como ssh/.ssh/${VPS_HOSTNAME}.pub:

     $(cat "${pub}")

  2. Añade esta línea a ssh/.ssh/allowed_signers:

     ${email:-10409334+savaf@users.noreply.github.com} namespaces="git" $(cut -d' ' -f1,2 "${pub}")

  3. Commit + push, y en GitHub → Settings → SSH keys regístrala dos veces:
     como Authentication key y como Signing key.

  4. De vuelta en el VPS: sudo ./bootstrap.sh dotfiles git-key agents

EOF
}
