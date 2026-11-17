#!/usr/bin/env bash
set -euo pipefail

# Guardas anti-bloqueo y de repetición: llaves, GitHub, sshd, apt, módulos, host.env, Tailscale.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/lib/common.sh"
source "${ROOT_DIR}/tests/lib.sh"
source "${ROOT_DIR}/modules/user.sh"
source "${ROOT_DIR}/modules/ssh.sh"
source "${ROOT_DIR}/modules/base.sh"
source "${ROOT_DIR}/modules/tailscale.sh"
CIGUA_BOOTSTRAP_SOURCED=1 source "${ROOT_DIR}/bootstrap.sh"
CIGUA_INSTALL_SOURCED=1 source "${ROOT_DIR}/install.sh"

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
mkdir -p "${work}/bin"
export PATH="${work}/bin:${PATH}"
log() { :; }
warn() { :; }
# Silencia el comando, no al refute (redirigir `refute …` también ocultaría su FAIL).
quiet() { ( "$@" ) >/dev/null 2>&1; }   # subshell: un die (exit) no mata el test

echo "collect_authorized_keys"
cat >"${work}/bin/curl" <<'EOF'
#!/bin/sh
# El último argumento es la URL.
for last; do :; done
case "${last}" in
  *bad*) exit 22 ;;
  *notkey*) echo "hola mundo" ;;
  *ecdsa*) echo "ecdsa-sha2-nistp256 AAAA ecdsa" ;;
  *sk*) echo "sk-ssh-ed25519@openssh.com AAAA sk" ;;
  *) echo "ssh-ed25519 AAAA ${last}" ;;
esac
EOF
chmod +x "${work}/bin/curl"
printf 'ssh-rsa AAAAroot root\n# comentario\n' >"${work}/root_keys"
export ROOT_AUTH_KEYS="${work}/root_keys"

AUTHORIZED_KEYS_URLS="https://x/ok https://x/ecdsa https://x/sk"
out="$(collect_authorized_keys)"
check "todas las URLs bien: sale 0" quiet collect_authorized_keys
check "acepta ecdsa-" grep -q '^ecdsa-' <<<"${out}"
check "acepta sk-" grep -q '^sk-' <<<"${out}"
check "mezcla las llaves de root" grep -q 'AAAAroot' <<<"${out}"
refute "no copia comentarios de root" grep -q 'comentario' <<<"${out}"

AUTHORIZED_KEYS_URLS="https://x/ok https://x/bad"
refute "una URL caída: sale distinto de 0" quiet collect_authorized_keys
out="$(collect_authorized_keys || true)"
check "una URL caída: aun así imprime las demás" grep -q 'https://x/ok' <<<"${out}"
AUTHORIZED_KEYS_URLS="https://x/notkey"
refute "contenido que no es llave: sale distinto de 0" quiet collect_authorized_keys
unset ROOT_AUTH_KEYS

echo "github_accepts_key"
as_user() { "$@"; }
printf '#!/bin/sh\necho "Hi savaf! You have successfully authenticated, but GitHub does not provide shell access." >&2\nexit 1\n' >"${work}/bin/ssh"
chmod +x "${work}/bin/ssh"
check "ssh sale 1 pero GitHub reconoce la llave: cierto (pipefail)" github_accepts_key
printf '#!/bin/sh\necho "Permission denied (publickey)." >&2\nexit 255\n' >"${work}/bin/ssh"
refute "Permission denied: falso" github_accepts_key

echo "ssh: drop-in validado"
VPS_USER=ana
user_home() { echo "${work}/home"; }
mkdir -p "${work}/home/.ssh" "${work}/etc" "${work}/files/sshd"
ROOT_DIR_REAL="${ROOT_DIR}"
ROOT_DIR="${work}"
echo "PermitRootLogin no" >"${work}/files/sshd/10-cigua.conf"
export SSHD_DROPIN="${work}/etc/10-cigua.conf"
printf '#!/bin/sh\necho "$@" >>"%s/systemctl.log"\n' "${work}" >"${work}/bin/systemctl"
printf '#!/bin/sh\nexit 0\n' >"${work}/bin/sshd"
chmod +x "${work}/bin/systemctl" "${work}/bin/sshd"
die() { echo "DIE: $*" >&2; exit 1; }

run_ssh >/dev/null 2>&1 || true
refute "sin llaves en authorized_keys: no instala el drop-in" test -e "${SSHD_DROPIN}"
echo "ssh-ed25519 AAAA ana" >"${work}/home/.ssh/authorized_keys"
run_ssh >/dev/null 2>&1
check "con llaves y sshd -t ok: instala el drop-in" test -f "${SSHD_DROPIN}"
check "recarga con try-reload-or-restart" grep -q 'try-reload-or-restart' "${work}/systemctl.log"
: >"${work}/systemctl.log"
run_ssh >/dev/null 2>&1
check "repetición sin cambios: vuelve a recargar" grep -q 'try-reload-or-restart' "${work}/systemctl.log"

echo "PermitRootLogin yes # previo" >"${SSHD_DROPIN}"
echo "Roto" >"${work}/files/sshd/10-cigua.conf"
printf '#!/bin/sh\nexit 1\n' >"${work}/bin/sshd"
refute "sshd -t en rojo: el módulo falla" quiet run_ssh
check "sshd -t en rojo: restaura el drop-in anterior" grep -q 'previo' "${SSHD_DROPIN}"
rm -f "${SSHD_DROPIN}"
refute "sshd -t en rojo sin drop-in previo: falla" quiet run_ssh
refute "sshd -t en rojo sin drop-in previo: no lo deja puesto" test -e "${SSHD_DROPIN}"
ROOT_DIR="${ROOT_DIR_REAL}"

echo "should_apt_upgrade"
export APT_UPGRADE_MARKER="${work}/marker"
check "sin marcador: sube" should_apt_upgrade
touch "${APT_UPGRADE_MARKER}"
refute "con marcador: no repite" should_apt_upgrade
check "APT_UPGRADE=1 lo fuerza" env APT_UPGRADE=1 APT_UPGRADE_MARKER="${APT_UPGRADE_MARKER}" \
  bash -c "source '${ROOT_DIR}/modules/base.sh'; should_apt_upgrade"

echo "order_modules"
die() { echo "[cigua] ERROR: $*" >&2; exit 1; }
res="$(order_modules firewall tailscale)"
check "respeta el orden de MODULES, no el de los argumentos" test "${res}" = $'tailscale\nfirewall'
res="$(order_modules ssh ssh)"
check "no repite módulos" test "${res}" = ssh
load="source '${ROOT_DIR}/lib/common.sh'; CIGUA_BOOTSTRAP_SOURCED=1 source '${ROOT_DIR}/bootstrap.sh'"
refute "módulo desconocido: falla" bash -c "${load}; order_modules nada" 2>/dev/null
refute "ruta como módulo: falla" bash -c "${load}; order_modules ../../tmp/x" 2>/dev/null

echo "host_env_value"
printf 'VPS_USER="savaf"\nVPS_HOSTNAME=otro\n' >"${work}/host.env"
check "lee VPS_USER de host.env" test "$(host_env_value "${work}/host.env" VPS_USER)" = savaf
check "lee VPS_HOSTNAME de host.env" test "$(host_env_value "${work}/host.env" VPS_HOSTNAME)" = otro
check "variable ausente: vacío" test -z "$(host_env_value "${work}/host.env" NOPE)"
check "archivo ausente: vacío" test -z "$(host_env_value "${work}/no-existe" VPS_USER)"

echo "tailscale_login_possible"
ts="source '${ROOT_DIR}/lib/common.sh'; source '${ROOT_DIR}/modules/tailscale.sh'; tailscale_login_possible"
check "con TS_AUTHKEY basta" env TS_AUTHKEY=tskey-x bash -c "${ts}"
if exists setsid; then
  refute "sin terminal ni TS_AUTHKEY: no se puede" setsid -w env -u TS_AUTHKEY bash -c "${ts}" </dev/null
fi

finish
