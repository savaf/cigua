# Deja el VPS listo para correr agentes: Claude Code instalado y los repos de repos.txt
# clonados en las mismas rutas que en las PCs (así `hw` y /horde funcionan igual).
# Los logins (claude /login, teamclaude) son interactivos: ver docs/agentes.md.

run_agents() {
  local home
  home="$(user_home)"

  if ! as_user bash -c 'command -v claude' >/dev/null; then
    log "instalando Claude Code"
    as_user bash -c 'curl -fsSL https://claude.ai/install.sh | bash'
  fi
  as_user bash -c 'command -v herdr' >/dev/null \
    || warn "herdr no está en el PATH de ${VPS_USER}; corre el módulo dotfiles"

  clone_repos "${home}"

  as_user bash -c 'claude --version' 2>/dev/null | sed 's/^/[cigua] claude /' || true
  as_user bash -c 'herdr --version' 2>/dev/null | sed 's/^/[cigua] /' || true
}

# repos.txt: "<ruta relativa a $HOME> <url git>" por línea; # comenta.
clone_repos() {
  local home="$1" list="${ROOT_DIR}/repos.txt" path url
  [[ -f "${list}" ]] || return 0

  if ! as_user ssh -o BatchMode=yes -T git@github.com 2>&1 | grep -q 'successfully authenticated'; then
    warn "GitHub aún no acepta la llave del VPS: no clono repos (ver el módulo git-key)"
    return
  fi

  while read -r path url _; do
    [[ -z "${path}" || "${path}" == \#* ]] && continue
    if [[ -d "${home}/${path}/.git" ]]; then
      log "ya existe ~/${path}"
      continue
    fi
    log "clonando ${url} → ~/${path}"
    as_user mkdir -p "$(dirname "${home}/${path}")"
    as_user git clone "${url}" "${home}/${path}" || warn "falló el clon de ${url}"
  done <"${list}"
}
