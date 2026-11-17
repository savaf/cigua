#!/usr/bin/env bash
set -euo pipefail

# Instalador de una línea. Corre como root en un Ubuntu nuevo:
#
#   curl -fsSL https://raw.githubusercontent.com/savaf/cigua/main/install.sh \
#     | sudo bash
#
# Hace: instala git y curl, clona (o actualiza) el repo, genera host.env y corre
# ./bootstrap.sh. Es idempotente: volver a correrlo actualiza y reaplica.
#
# Variables (por entorno o, si hay terminal, se preguntan):
#   VPS_USER              usuario de trabajo (por defecto: cigua).
#   AUTHORIZED_KEYS_URLS  URLs de llaves públicas, separadas por espacio. Por defecto, las
#                         llaves de savaf/dotfiles (andrea y songbird).
#   VPS_HOSTNAME TIMEZONE SWAP_GB SSH_PUBLIC PUBLIC_TCP_PORTS COOLIFY NTFY_URL DOTFILES_REPO TAILSCALE_TAGS
#   CIGUA_REPO (por defecto este repo) · CIGUA_REF (rama, tag o commit) · CIGUA_DIR (/opt/cigua)
# Coolify: COOLIFY=1 (o responde "s" a la pregunta) lo instala; entonces pide COOLIFY_ADMIN_EMAIL y
#   COOLIFY_ADMIN_PASSWORD y abre 80/443. Todas las preguntas tienen defecto: Enter las acepta.
# Secretos, solo por entorno y nunca a disco: TS_AUTHKEY, COOLIFY_ADMIN_EMAIL, COOLIFY_ADMIN_PASSWORD.

CIGUA_REPO="${CIGUA_REPO:-https://github.com/savaf/cigua.git}"
CIGUA_REF="${CIGUA_REF:-main}"
CIGUA_DIR="${CIGUA_DIR:-/opt/cigua}"
DEFAULT_KEYS="https://raw.githubusercontent.com/savaf/dotfiles/main/ssh/.ssh/andrea.pub https://raw.githubusercontent.com/savaf/dotfiles/main/ssh/.ssh/songbird.pub"

# ¿Hay una terminal real? [[ -r /dev/tty ]] no basta: da cierto aunque no haya terminal
# de control (cloud-init, cron) y el open falla después. Se prueba abriéndola.
have_tty() { (: </dev/tty) 2>/dev/null; }

say()  { echo "[install] $*"; }
fail() { echo "[install] ERROR: $*" >&2; exit 1; }

# Valor por entorno; si falta y hay terminal, lo pregunta. $1 nombre, $2 pregunta, $3 defecto opcional.
ask() {
  local name="$1" prompt="$2" default="${3:-}" value="${!1:-}"
  if [[ -z "${value}" ]] && have_tty; then
    read -r -p "${prompt}${default:+ [${default}]}: " value </dev/tty || true
  fi
  printf -v "${name}" '%s' "${value:-${default}}"
}

# Sí/no por entorno (1, s, si, y, yes, true) o, con terminal, por pregunta. Deja 1 o 0 en $1.
# $1 nombre, $2 pregunta, $3 defecto (s|n).
ask_yes_no() {
  local name="$1" prompt="$2" default="${3:-n}" value="${!1:-}" hint="s/N"
  [[ "${default}" == s ]] && hint="S/n"
  if [[ -z "${value}" ]] && have_tty; then
    read -r -p "${prompt} [${hint}]: " value </dev/tty || true
  fi
  value="${value:-${default}}"
  case "${value,,}" in s|si|sí|y|yes|1|true) printf -v "${name}" 1 ;; *) printf -v "${name}" 0 ;; esac
}

# Secreto por entorno o, con terminal, escrito sin eco. Nunca va a disco.
ask_secret() {
  local name="$1" prompt="$2" value="${!1:-}"
  if [[ -z "${value}" ]] && have_tty; then
    read -r -s -p "${prompt}: " value </dev/tty || true
    echo >/dev/tty
  fi
  printf -v "${name}" '%s' "${value}"
}

# Pregunta si instalar Coolify. Si sí: abre 80/443 y pide el admin (solo por entorno, no a disco),
# porque sin admin el primer registro en el panel sería el dueño.
setup_coolify() {
  ask_yes_no COOLIFY "¿Instalar Coolify en este VPS? (panel solo por la tailnet)" n
  export COOLIFY
  [[ "${COOLIFY}" == 1 ]] || return 0
  PUBLIC_TCP_PORTS="${PUBLIC_TCP_PORTS:-80 443}"
  ask COOLIFY_ADMIN_EMAIL "Correo del admin de Coolify"
  ask_secret COOLIFY_ADMIN_PASSWORD "Contraseña del admin de Coolify (mín. 8, no se muestra)"
  [[ -n "${COOLIFY_ADMIN_EMAIL}" && -n "${COOLIFY_ADMIN_PASSWORD}" ]] \
    || fail "COOLIFY=1 necesita COOLIFY_ADMIN_EMAIL y COOLIFY_ADMIN_PASSWORD (por entorno si no hay terminal)"
  (( ${#COOLIFY_ADMIN_PASSWORD} >= 8 )) || fail "la contraseña del admin de Coolify debe tener al menos 8 caracteres"
  export PUBLIC_TCP_PORTS COOLIFY_ADMIN_EMAIL COOLIFY_ADMIN_PASSWORD
}

# Los valores acaban en un archivo que se carga con source: solo caracteres inocuos.
safe_value() { [[ "$1" =~ ^[A-Za-z0-9_.:/@+,=?%~\ -]*$ ]]; }

# Escribe host.env: copia el ejemplo y añade al final lo elegido (la última asignación gana).
# Uso: render_host_env <destino> <ejemplo>; lee el entorno.
render_host_env() {
  local dest="$1" example="$2" name keys url
  [[ -n "${VPS_USER:-}" ]] || fail "falta VPS_USER"
  [[ -n "${AUTHORIZED_KEYS_URLS:-}" ]] || fail "falta AUTHORIZED_KEYS_URLS: sin llaves te quedarías fuera del servidor"
  for url in ${AUTHORIZED_KEYS_URLS}; do
    [[ "${url}" == https://* ]] || fail "solo URLs https en AUTHORIZED_KEYS_URLS: ${url}"
  done

  # Todo se valida antes de abrir el destino: un fallo no deja un host.env a medias.
  local names=(VPS_USER VPS_HOSTNAME TIMEZONE SWAP_GB SSH_PUBLIC PUBLIC_TCP_PORTS COOLIFY NTFY_URL DOTFILES_REPO TAILSCALE_TAGS)
  for name in "${names[@]}"; do
    safe_value "${!name:-}" || fail "valor no permitido en ${name}"
  done
  keys=""
  for url in ${AUTHORIZED_KEYS_URLS}; do
    safe_value "${url}" || fail "URL no permitida: ${url}"
    keys+="${url}"$'\n'
  done

  (
    umask 077
    {
      cat "${example}"
      printf '\n# --- generado por install.sh ---\n'
      for name in "${names[@]}"; do
        [[ -n "${!name:-}" ]] && printf '%s="%s"\n' "${name}" "${!name}"
      done
      printf 'AUTHORIZED_KEYS_URLS="\n%s"\n' "${keys}"
    } >"${dest}"
  )
}

fetch_repo() {
  if [[ -d "${CIGUA_DIR}/.git" ]]; then
    say "actualizando ${CIGUA_DIR}"
    git -C "${CIGUA_DIR}" fetch --quiet origin
  else
    say "clonando ${CIGUA_REPO} en ${CIGUA_DIR}"
    git clone --quiet "${CIGUA_REPO}" "${CIGUA_DIR}"
    git -C "${CIGUA_DIR}" fetch --quiet origin
  fi
  git -C "${CIGUA_DIR}" checkout --quiet "${CIGUA_REF}"
  # Solo avanza si es una rama; un tag o commit queda fijo.
  git -C "${CIGUA_DIR}" merge --ff-only --quiet "origin/${CIGUA_REF}" 2>/dev/null || true
  say "versión: $(git -C "${CIGUA_DIR}" rev-parse --short HEAD)"
}

# Reimprime la llave pública del VPS al final: el módulo git-key ya la generó, pero su
# mensaje queda enterrado en la salida del bootstrap. Uso: show_pubkey <archivo.pub>
show_pubkey() {
  [[ -r "$1" ]] || return 0
  printf '\n[install] Llave pública del VPS (guárdala en dotfiles como ssh/.ssh/%s.pub):\n\n  %s\n' \
    "$(basename "$1" _ed25519.pub)" "$(cat "$1")"
}

# Valor de una variable de un host.env existente (vacío si no está). Se lee en un subshell
# porque host.env es shell; lo generó este instalador, en modo 600.
host_env_value() {
  [[ -r "$1" ]] || return 0
  ( set +u; source "$1" >/dev/null 2>&1; printf '%s' "${!2:-}" )
}

main() {
  [[ "${EUID}" -eq 0 ]] || fail "corre como root: curl … | sudo bash"
  command -v apt-get >/dev/null || fail "pensado para Ubuntu/Debian"

  if [[ -e "${CIGUA_DIR}/host.env" ]]; then
    # host.env manda: no se pregunta lo que luego se ignoraría, y el resumen usa sus valores.
    say "host.env ya existe: uso su usuario y hostname (bórralo para regenerarlo)"
    VPS_USER="$(host_env_value "${CIGUA_DIR}/host.env" VPS_USER)"
    VPS_HOSTNAME="$(host_env_value "${CIGUA_DIR}/host.env" VPS_HOSTNAME)"
    COOLIFY="${COOLIFY:-$(host_env_value "${CIGUA_DIR}/host.env" COOLIFY)}"
    [[ -n "${VPS_USER}" && -n "${VPS_HOSTNAME}" ]] || fail "host.env no define VPS_USER y VPS_HOSTNAME"
    export VPS_USER VPS_HOSTNAME
    setup_coolify
  else
    ask VPS_USER "Usuario de trabajo" cigua
    ask AUTHORIZED_KEYS_URLS "URLs de llaves públicas (https, separadas por espacio)" "${DEFAULT_KEYS}"
    ask VPS_HOSTNAME "Hostname" cigua
    export VPS_USER AUTHORIZED_KEYS_URLS VPS_HOSTNAME
    setup_coolify
  fi

  DEBIAN_FRONTEND=noninteractive apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq git curl ca-certificates >/dev/null
  fetch_repo

  if [[ -e "${CIGUA_DIR}/host.env" ]]; then
    say "host.env ya existe: lo conservo (bórralo para regenerarlo)"
  else
    render_host_env "${CIGUA_DIR}/host.env" "${CIGUA_DIR}/host.env.example"
    say "host.env generado (modo 600)"
  fi

  cd "${CIGUA_DIR}"
  # Con `curl | bash` stdin es el pipe: passwd y sudo (dotfiles) necesitan la terminal.
  have_tty && exec </dev/tty
  ./bootstrap.sh

  show_pubkey "$(getent passwd "${VPS_USER}" | cut -d: -f6)/.ssh/${VPS_HOSTNAME}_ed25519.pub"

  cat <<EOF

[install] Listo. Siguiente:
  1. Entra por la tailnet:  ssh ${VPS_USER}@${VPS_HOSTNAME}
  2. Revisa docs/primer-arranque.md (llave del VPS, ntfy).
EOF
  # Con SSH_PUBLIC=0 el 22 público se queda abierto en la primera pasada (entraste desde fuera).
  if [[ "$(host_env_value "${CIGUA_DIR}/host.env" SSH_PUBLIC)" == 0 ]]; then
    echo "  3. Cierra el SSH público: cd ${CIGUA_DIR} && sudo ./bootstrap.sh firewall"
  fi
}

# CIGUA_INSTALL_SOURCED=1 permite cargar las funciones en tests sin ejecutar nada.
[[ -n "${CIGUA_INSTALL_SOURCED:-}" ]] || main "$@"
