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
#   VPS_HOSTNAME TIMEZONE SWAP_GB PUBLIC_TCP_PORTS COOLIFY NTFY_URL DOTFILES_REPO TAILSCALE_TAGS
#   CIGUA_REPO (por defecto este repo) · CIGUA_REF (rama, tag o commit) · CIGUA_DIR (/opt/cigua)
# Secretos, solo por entorno y nunca a disco: TS_AUTHKEY, COOLIFY_ADMIN_EMAIL, COOLIFY_ADMIN_PASSWORD.

CIGUA_REPO="${CIGUA_REPO:-https://github.com/savaf/cigua.git}"
CIGUA_REF="${CIGUA_REF:-main}"
CIGUA_DIR="${CIGUA_DIR:-/opt/cigua}"
DEFAULT_KEYS="https://raw.githubusercontent.com/savaf/dotfiles/main/ssh/.ssh/andrea.pub https://raw.githubusercontent.com/savaf/dotfiles/main/ssh/.ssh/songbird.pub"

say()  { echo "[install] $*"; }
fail() { echo "[install] ERROR: $*" >&2; exit 1; }

# Valor por entorno; si falta y hay terminal, lo pregunta. $1 nombre, $2 pregunta, $3 defecto opcional.
ask() {
  local name="$1" prompt="$2" default="${3:-}" value="${!1:-}"
  if [[ -z "${value}" && -r /dev/tty ]]; then
    read -r -p "${prompt}${default:+ [${default}]}: " value </dev/tty || true
  fi
  printf -v "${name}" '%s' "${value:-${default}}"
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
  local names=(VPS_USER VPS_HOSTNAME TIMEZONE SWAP_GB PUBLIC_TCP_PORTS COOLIFY NTFY_URL DOTFILES_REPO TAILSCALE_TAGS)
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

main() {
  [[ "${EUID}" -eq 0 ]] || fail "corre como root: curl … | sudo bash"
  command -v apt-get >/dev/null || fail "pensado para Ubuntu/Debian"

  ask VPS_USER "Usuario de trabajo" cigua
  ask AUTHORIZED_KEYS_URLS "URLs de llaves públicas (https, separadas por espacio)" "${DEFAULT_KEYS}"
  ask VPS_HOSTNAME "Hostname" cigua
  export VPS_USER AUTHORIZED_KEYS_URLS VPS_HOSTNAME

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
  [[ -r /dev/tty ]] && exec </dev/tty
  ./bootstrap.sh

  show_pubkey "$(getent passwd "${VPS_USER}" | cut -d: -f6)/.ssh/${VPS_HOSTNAME}_ed25519.pub"

  cat <<EOF

[install] Listo. Siguiente:
  1. Entra por la tailnet:  ssh ${VPS_USER}@${VPS_HOSTNAME}
  2. Cierra el SSH público: cd ${CIGUA_DIR} && sudo ./bootstrap.sh firewall
  3. Revisa docs/primer-arranque.md (llave del VPS, ntfy).
EOF
}

# CIGUA_INSTALL_SOURCED=1 permite cargar las funciones en tests sin ejecutar nada.
[[ -n "${CIGUA_INSTALL_SOURCED:-}" ]] || main "$@"
