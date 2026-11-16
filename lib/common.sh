# Utilidades compartidas por bootstrap.sh y los módulos. Se carga con source: sin shebang.
# Nada aquí cambia el sistema por sí solo.

log()  { echo "[cigua] $*"; }
warn() { echo "[cigua] AVISO: $*" >&2; }
die()  { echo "[cigua] ERROR: $*" >&2; exit 1; }
exists() { command -v "$1" >/dev/null 2>&1; }

require_root() {
  [[ "${EUID}" -eq 0 ]] || die "corre con sudo: sudo ./bootstrap.sh $*"
}

# Carga host.env (config no secreta). Falla con un mensaje claro si falta algo obligatorio.
load_host_env() {
  local env_file="${ROOT_DIR}/host.env"
  [[ -r "${env_file}" ]] || die "falta host.env: cp host.env.example host.env y ajústalo"
  set -a
  # shellcheck source=../host.env.example
  source "${env_file}"
  set +a
  : "${VPS_HOSTNAME:?VPS_HOSTNAME vacío en host.env}"
  : "${VPS_USER:?VPS_USER vacío en host.env}"
}

# Home y uid del usuario de trabajo (vacíos si aún no existe).
user_home() { getent passwd "${VPS_USER}" | cut -d: -f6; }
user_uid()  { id -u "${VPS_USER}" 2>/dev/null; }

# Ejecuta un comando como el usuario de trabajo, con el entorno que necesitan
# systemctl --user (XDG_RUNTIME_DIR) y git por SSH (el ssh-agent del módulo git-key).
as_user() {
  local uid home
  uid="$(user_uid)" || die "el usuario ${VPS_USER} no existe; corre el módulo user"
  home="$(user_home)"
  sudo -u "${VPS_USER}" -H env \
    HOME="${home}" \
    XDG_RUNTIME_DIR="/run/user/${uid}" \
    SSH_AUTH_SOCK="/run/user/${uid}/ssh-agent.socket" \
    PATH="${home}/.local/bin:/usr/local/bin:/usr/bin:/bin" \
    "$@"
}

# Escribe (o reemplaza) un bloque delimitado en un archivo, sin tocar el resto.
# Uso: write_managed_block <archivo> <contenido> [prefijo de comentario]
write_managed_block() {
  local file="$1" content="$2" c="${3:-#}"
  local begin="${c} >>> cigua (gestionado, no editar a mano) >>>"
  local end="${c} <<< cigua <<<"
  local tmp
  tmp="$(mktemp)"
  if [[ -f "${file}" ]]; then
    awk -v b="${begin}" -v e="${end}" '
      $0 == b { skip = 1; next }
      $0 == e { skip = 0; next }
      !skip' "${file}" >"${tmp}"
  fi
  { printf '%s\n%s\n%s\n' "${begin}" "${content}" "${end}"; } >>"${tmp}"
  cat "${tmp}" >"${file}"   # cat > preserva dueño y permisos del archivo existente
  rm -f "${tmp}"
}

# Copia un archivo a su destino solo si cambió. Devuelve 0 si lo cambió, 1 si no.
# src "-" lee el contenido de stdin (para heredocs).
install_if_changed() {
  local src="$1" dest="$2" mode="${3:-0644}" tmp="" rc=1
  if [[ "${src}" == "-" ]]; then
    tmp="$(mktemp)"
    cat >"${tmp}"
    src="${tmp}"
  fi
  if ! { [[ -f "${dest}" ]] && cmp -s "${src}" "${dest}"; }; then
    install -D -m "${mode}" "${src}" "${dest}"
    log "instalado ${dest}"
    rc=0
  fi
  [[ -n "${tmp}" ]] && rm -f "${tmp}"
  return "${rc}"
}

# 100.64.0.0/10: el rango CGNAT del que Tailscale asigna las IPs de la tailnet.
is_tailnet_ip() {
  local a b c d
  IFS=. read -r a b c d <<<"$1"
  [[ "${a}" =~ ^[0-9]+$ && "${b}" =~ ^[0-9]+$ && "${c}" =~ ^[0-9]+$ && "${d}" =~ ^[0-9]+$ ]] || return 1
  (( a == 100 && b >= 64 && b <= 127 && c <= 255 && d <= 255 ))
}

# IP del cliente SSH de quien corre esto, incluso bajo sudo (que limpia SSH_CONNECTION).
ssh_client_ip() {
  if [[ -n "${SSH_CONNECTION:-}" ]]; then
    echo "${SSH_CONNECTION%% *}"
    return
  fi
  who -m 2>/dev/null | sed -n 's/.*(\(.*\)).*/\1/p'
}

# ¿Este proceso desciende de una sesión SSH? Cubre `ssh host 'sudo …'` sin TTY, donde
# no hay SSH_CONNECTION (sudo la limpia) ni `who -m`. sshd-session: OpenSSH ≥ 9.8.
in_ssh_session() {
  [[ -n "${SSH_CONNECTION:-}${SSH_CLIENT:-}${SSH_TTY:-}" ]] && return 0
  local pid=$$ comm
  while [[ -n "${pid}" ]] && (( pid > 1 )); do
    comm="$(ps -o comm= -p "${pid}" 2>/dev/null)" || return 1
    [[ "${comm}" == sshd* ]] && return 0
    pid="$(ps -o ppid= -p "${pid}" 2>/dev/null | tr -d ' ')"
  done
  return 1
}
