# Config de Claude Code que solo aplica a este VPS, sin tocar tus dotfiles.
#
# Claude Code lee /etc/claude-code/managed-settings.json y el directorio de fragmentos
# managed-settings.d/*.json (orden alfabético). Sus hooks se suman a los de tu
# ~/.claude/settings.json (mientras no se active allowManagedHooksOnly, que aquí no se usa).
# Así el aviso a ntfy existe solo en el VPS y el settings.json compartido queda igual.
#
# Excepción conocida: si una cuenta tiene ajustes gestionados desde el servidor de
# Anthropic (típico en cuentas Enterprise/Team, como el perfil de trabajo), esos ganan y
# los archivos de /etc/claude-code se ignoran para esa cuenta.

run_claude_managed() {
  install_if_changed "${ROOT_DIR}/files/bin/cigua-notify" /usr/local/bin/cigua-notify 0755 || true
  install_if_changed "${ROOT_DIR}/files/claude/50-cigua.json" \
    /etc/claude-code/managed-settings.d/50-cigua.json 0644 || true

  # Config del aviso, del usuario y privada: aquí va el token de ntfy, nunca en el repo.
  local conf
  conf="$(user_home)/.config/cigua/notify.env"
  if [[ ! -f "${conf}" ]]; then
    as_user mkdir -p "$(dirname "${conf}")"
    chmod 700 "$(dirname "${conf}")"
    install -m 600 -o "${VPS_USER}" -g "${VPS_USER}" /dev/null "${conf}"
    printf 'NTFY_URL=%s\nNTFY_TOKEN=\n' "${NTFY_URL:-}" >"${conf}"
    log "creado ${conf}: pon tu token de ntfy en NTFY_TOKEN"
  fi
}
