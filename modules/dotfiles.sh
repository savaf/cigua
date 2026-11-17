# Clona (o actualiza) tus dotfiles y corre su bootstrap como VPS_USER: zsh, mise, herdr,
# el paquete claude (settings, agentes, hooks, skills), perfiles. La ruta de Ubuntu ya existe.
# El bootstrap de dotfiles pide sudo por su cuenta (la contraseña de VPS_USER).

run_dotfiles() {
  local dir
  dir="$(user_home)/${DOTFILES_DIR:-dotfiles}"

  if [[ -d "${dir}/.git" ]]; then
    log "actualizando ${dir}"
    as_user git -C "${dir}" pull --ff-only || warn "pull falló (¿cambios locales?); sigo con lo que hay"
  else
    log "clonando ${DOTFILES_REPO} → ${dir}"
    as_user git clone "${DOTFILES_REPO}" "${dir}"
  fi

  if [[ ! -f "${dir}/ssh/.ssh/${VPS_HOSTNAME}.pub" ]]; then
    warn "tus dotfiles no tienen ssh/.ssh/${VPS_HOSTNAME}.pub todavía."
    warn "Normal en el primer arranque: el módulo git-key la genera y te dice qué commitear."
  fi

  has_password "${VPS_USER}" || die "${VPS_USER} no tiene contraseña y el bootstrap de dotfiles pide sudo: passwd ${VPS_USER}"
  log "corriendo el bootstrap de dotfiles (pedirá la contraseña de ${VPS_USER} para sudo)"
  as_user bash -c "cd '${dir}' && ./scripts/bootstrap.sh"
}
