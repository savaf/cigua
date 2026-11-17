# Paquetes base, hostname, zona horaria y parches de seguridad automáticos.
# Lo demás (zsh, mise, herdr, nvim…) lo instala el bootstrap de dotfiles.

BASE_PACKAGES=(git curl jq ufw ca-certificates unattended-upgrades)

APT_UPGRADE_MARKER="${APT_UPGRADE_MARKER:-/var/lib/cigua/apt-upgraded}"

should_apt_upgrade() { [[ "${APT_UPGRADE:-0}" == 1 || ! -e "${APT_UPGRADE_MARKER}" ]]; }

run_base() {
  log "apt: actualizando índices e instalando ${BASE_PACKAGES[*]}"
  DEBIAN_FRONTEND=noninteractive apt-get update -qq
  # Parches antes que nada, pero solo la primera vez: repetirlo reiniciaría dockerd o tailscaled
  # en medio de una sesión. APT_UPGRADE=1 lo fuerza. force-confold conserva tus configs.
  if should_apt_upgrade; then
    log "apt: actualizando Ubuntu (puede tardar unos minutos)"
    DEBIAN_FRONTEND=noninteractive apt-get -y -qq -o Dpkg::Options::=--force-confold upgrade
    install -d "$(dirname "${APT_UPGRADE_MARKER}")" && touch "${APT_UPGRADE_MARKER}"
  fi
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${BASE_PACKAGES[@]}"

  if [[ "$(hostnamectl --static 2>/dev/null)" != "${VPS_HOSTNAME}" ]]; then
    log "hostname → ${VPS_HOSTNAME}"
    hostnamectl set-hostname "${VPS_HOSTNAME}"
  fi
  # Que sudo no tarde resolviendo el nombre nuevo.
  grep -qE "^127\.0\.1\.1[[:space:]]+${VPS_HOSTNAME}\$" /etc/hosts \
    || write_managed_block /etc/hosts "127.0.1.1 ${VPS_HOSTNAME}"

  if [[ -n "${TIMEZONE:-}" ]] && [[ "$(timedatectl show -p Timezone --value 2>/dev/null)" != "${TIMEZONE}" ]]; then
    log "zona horaria → ${TIMEZONE}"
    timedatectl set-timezone "${TIMEZONE}"
  fi

  # Solo parches de seguridad, sin reinicio automático: un reinicio mata a los agentes.
  install_if_changed - /etc/apt/apt.conf.d/20auto-upgrades <<'EOF' || true
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
}
