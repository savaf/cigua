#!/usr/bin/env bash
set -euo pipefail

# Guardas de modules/coolify.sh y contenido de los archivos de hardening, sin tocar el sistema.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/lib/common.sh"
source "${ROOT_DIR}/tests/lib.sh"
source "${ROOT_DIR}/modules/coolify.sh"

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
mkdir -p "${work}/bin"
cat >"${work}/bin/tailscale" <<'FAKE'
#!/bin/sh
echo "${TS_IP-100.101.1.2}"
FAKE
cat >"${work}/bin/curl" <<'FAKE'
#!/bin/sh
echo "$*" >>"${CALLS}"
FAKE
chmod +x "${work}/bin/"*
export PATH="${work}/bin:${PATH}" CALLS="${work}/calls"
: >"${CALLS}"
VPS_USER=nadie

# Corre el módulo en un subshell limpio con las variables dadas.
run_with() {
  # shellcheck disable=SC2016
  env "$@" bash -c 'source "$ROOT_DIR/lib/common.sh"; source "$ROOT_DIR/modules/coolify.sh"; run_coolify' >/dev/null 2>&1
}
export ROOT_DIR

echo "coolify"
COOLIFY=0 run_coolify >/dev/null
refute "COOLIFY=0: no descarga nada" test -s "${CALLS}"

refute "IP que no es de tailnet: falla" run_with COOLIFY=1 TS_IP=8.8.8.8 COOLIFY_ADMIN_EMAIL=a@b COOLIFY_ADMIN_PASSWORD=x
refute "sin admin por entorno: falla" run_with COOLIFY=1 COOLIFY_ADMIN_EMAIL= COOLIFY_ADMIN_PASSWORD=
refute "falla antes de descargar nada" test -s "${CALLS}"

out="$(render_coolify_compose 100.101.1.2)"
check "override: panel en la IP de la tailnet" grep -q '"100.101.1.2:8000:8080"' <<<"${out}"
check "override: realtime en la IP de la tailnet" grep -q '"100.101.1.2:6001:6001"' <<<"${out}"
refute "override: nada en 0.0.0.0" grep -q '0\.0\.0\.0' <<<"$(grep -v '^ *#' <<<"${out}")"
refute "override: sin marcador sin sustituir" grep -q '__TAILNET_IP__' <<<"${out}"

echo "hardening (archivos)"
check "fail2ban exime la tailnet" grep -q '100.64.0.0/10' "${ROOT_DIR}/files/fail2ban/cigua.conf"
check "sysctl: rp_filter" grep -q 'rp_filter = 1' "${ROOT_DIR}/files/sysctl/90-cigua-hardening.conf"
refute "sshd principal sin Match (no filtra a otros archivos)" grep -q '^Match' "${ROOT_DIR}/files/sshd/10-cigua.conf"
ssh90="${ROOT_DIR}/files/sshd/90-cigua-coolify.conf"
refute "ssh de Coolify: no toca PermitRootLogin" grep -q 'PermitRootLogin' "${ssh90}"
check "ssh de Coolify: niega al usuario fuera de local/Docker" grep -q 'DenyUsers __COOLIFY_USER__' "${ssh90}"

echo "usuario de coolify"
check "sudoers del usuario" test "$(coolify_sudoers coolify)" = "coolify ALL=(ALL) NOPASSWD:SETENV:ALL"
refute "COOLIFY_USER igual a VPS_USER: falla" run_with COOLIFY=1 VPS_USER=cigua COOLIFY_USER=cigua COOLIFY_ADMIN_EMAIL=a@b COOLIFY_ADMIN_PASSWORD=x
refute "COOLIFY_USER=root: falla" run_with COOLIFY=1 VPS_USER=cigua COOLIFY_USER=root COOLIFY_ADMIN_EMAIL=a@b COOLIFY_ADMIN_PASSWORD=x
refute "usuario inválido: no descarga nada" test -s "${CALLS}"

echo "docker_cidrs"
export DOCKER_DAEMON_JSON="${work}/daemon.json"
rm -f "${DOCKER_DAEMON_JSON}"
check "sin daemon.json: rango por defecto de Docker" test "$(docker_cidrs)" = "172.16.0.0/12"
echo '{"log-driver":"json-file"}' >"${DOCKER_DAEMON_JSON}"
check "daemon.json sin pools: rango por defecto" test "$(docker_cidrs)" = "172.16.0.0/12"
echo '{"default-address-pools":[{"base":"10.0.0.0/8","size":24}]}' >"${DOCKER_DAEMON_JSON}"
check "un pool: usa su base" test "$(docker_cidrs)" = "10.0.0.0/8"
echo '{"default-address-pools":[{"base":"10.0.0.0/8","size":24},{"base":"192.168.0.0/16","size":24}]}' >"${DOCKER_DAEMON_JSON}"
check "varios pools: los devuelve todos" test "$(docker_cidrs | tr '\n' ' ')" = "10.0.0.0/8 192.168.0.0/16 "
echo '{"default-address-pools":[{"base":"10.0.0.0/8; reboot","size":24}]}' >"${DOCKER_DAEMON_JSON}"
check "base que no es CIDR: se descarta y vuelve al defecto" test "$(docker_cidrs)" = "172.16.0.0/12"
echo 'esto no es json' >"${DOCKER_DAEMON_JSON}"
check "daemon.json roto: rango por defecto" test "$(docker_cidrs)" = "172.16.0.0/12"

echo "render_coolify_sshd"
echo '{"default-address-pools":[{"base":"10.0.0.0/8","size":24}]}' >"${DOCKER_DAEMON_JSON}"
out="$(render_coolify_sshd coolify)"
check "Match exime localhost y el pool de Docker" grep -qx 'Match User coolify Address \*,!127.0.0.1,!::1,!10.0.0.0/8' <<<"${out}"
refute "ya no exime 172.16.0.0/12 si el pool es otro" grep -q '172.16.0.0/12' <<<"$(grep -v '^ *#' <<<"${out}")"
refute "sin marcadores sin sustituir" grep -Eq '__(COOLIFY_USER|DOCKER_CIDRS)__' <<<"$(grep -v '^ *#' <<<"${out}")"
last="$(grep -v '^ *\(#\|$\)' <<<"${out}" | head -1)"
check "el Match va primero entre las líneas activas y DenyUsers después" test "${last%% *}" = Match

echo "install_coolify_sshd"
mkdir -p "${work}/etc"
export COOLIFY_SSHD_DROPIN="${work}/etc/90-cigua-coolify.conf" ROOT_DIR
printf '#!/bin/sh\nexit 0\n' >"${work}/bin/sshd"
printf '#!/bin/sh\necho "$@" >>"%s/systemctl.log"\n' "${work}" >"${work}/bin/systemctl"
chmod +x "${work}/bin/sshd" "${work}/bin/systemctl"
log() { :; }
warn() { :; }
quiet() { ( "$@" ) >/dev/null 2>&1; }   # subshell: un die (exit) no mata el test
die() { echo "DIE: $*" >&2; exit 1; }
quiet install_coolify_sshd coolify
check "instala el drop-in con sshd -t en verde" grep -q '^Match User coolify' "${COOLIFY_SSHD_DROPIN}"
: >"${work}/systemctl.log"
quiet install_coolify_sshd coolify
check "repetición sin cambios: vuelve a recargar" grep -q try-reload-or-restart "${work}/systemctl.log"
echo "Match previo" >"${COOLIFY_SSHD_DROPIN}"
printf '#!/bin/sh\nexit 1\n' >"${work}/bin/sshd"
refute "sshd -t en rojo: falla" quiet install_coolify_sshd coolify
check "sshd -t en rojo: restaura el drop-in anterior" grep -q 'Match previo' "${COOLIFY_SSHD_DROPIN}"
rm -f "${COOLIFY_SSHD_DROPIN}"
refute "sshd -t en rojo sin previo: falla" quiet install_coolify_sshd coolify
refute "sshd -t en rojo sin previo: no lo deja puesto" test -e "${COOLIFY_SSHD_DROPIN}"

echo "allow_docker_to_ssh"
printf '#!/bin/sh\necho "$*" >>"%s/ufw.log"\n' "${work}" >"${work}/bin/ufw"
chmod +x "${work}/bin/ufw"
echo '{"default-address-pools":[{"base":"10.0.0.0/8","size":24},{"base":"192.168.0.0/16","size":24}]}' >"${DOCKER_DAEMON_JSON}"
allow_docker_to_ssh
check "regla de ufw por cada rango de Docker (10/8)" grep -qx "allow from 10.0.0.0/8 to any port 22 proto tcp comment cigua: docker a host" "${work}/ufw.log"
check "regla de ufw por cada rango de Docker (192.168/16)" grep -q "allow from 192.168.0.0/16 to any port 22" "${work}/ufw.log"
refute "el comentario no es el que concilia el firewall" grep -q 'cigua: público' "${work}/ufw.log"

echo "coolify_has_key"
printf 'ssh-ed25519 AAAA panel\n' >"${work}/ak"
check "con llave pública: cierto" coolify_has_key "${work}/ak"
printf '# solo un comentario\n' >"${work}/ak"
refute "solo comentarios: falso" coolify_has_key "${work}/ak"
refute "archivo ausente: falso" coolify_has_key "${work}/no-existe"

finish
