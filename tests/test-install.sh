#!/usr/bin/env bash
set -euo pipefail

# Guardas de install.sh: nunca da acceso por defecto y escribe host.env sin secretos.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/tests/lib.sh"
CIGUA_INSTALL_SOURCED=1 source "${ROOT_DIR}/install.sh"

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
out="${work}/host.env"
ex="${ROOT_DIR}/host.env.example"

# shellcheck disable=SC2016
gen() { env -i PATH="${PATH}" "$@" bash -c 'CIGUA_INSTALL_SOURCED=1 source "$0/install.sh"; render_host_env "$1" "$2"' "${ROOT_DIR}" "${out}" "${ex}" >/dev/null 2>&1; }

echo "install"
refute "sin AUTHORIZED_KEYS_URLS: falla" gen VPS_USER=ana
refute "sin VPS_USER: falla" gen AUTHORIZED_KEYS_URLS=https://x.test/a.pub
refute "URL http (no https): falla" gen VPS_USER=ana AUTHORIZED_KEYS_URLS=http://x.test/a.pub
# shellcheck disable=SC2016
refute "valor con comillas o \$(): falla" gen VPS_USER='ana$(id)' AUTHORIZED_KEYS_URLS=https://x.test/a.pub
refute "no escribe nada si falla" test -e "${out}"

gen VPS_USER=ana AUTHORIZED_KEYS_URLS="https://x.test/a.pub https://x.test/b.pub" TS_AUTHKEY=tskey-secreto
check "host.env creado" test -f "${out}"
check "modo 600" test "$(stat -c %a "${out}")" = 600
check "usuario elegido" grep -qx 'VPS_USER="ana"' "${out}"
check "ambas llaves" bash -c "grep -q 'x.test/a.pub' '${out}' && grep -q 'x.test/b.pub' '${out}'"
refute "no copia secretos del entorno" grep -q 'tskey' "${out}"
# shellcheck disable=SC2016
res="$(env -i PATH="${PATH}" bash -c 'source "$0"; echo "${AUTHORIZED_KEYS_URLS}"' "${out}")"
check "la última asignación gana: solo las llaves pedidas" test "$(grep -c 'x.test' <<<"${res}")" = 2
refute "no hereda llaves de otro del ejemplo" grep -q 'dotfiles' <<<"${res}"

pub="${work}/cigua_ed25519.pub"
check "sin llave: show_pubkey no imprime ni falla" test -z "$(show_pubkey "${pub}")"
echo "ssh-ed25519 AAAAtest cigua" >"${pub}"
res="$(show_pubkey "${pub}")"
check "imprime la pública" grep -q 'ssh-ed25519 AAAAtest cigua' <<<"${res}"
check "sugiere ssh/.ssh/cigua.pub" grep -q 'ssh/.ssh/cigua.pub' <<<"${res}"

echo "ask_yes_no"
# shellcheck disable=SC2016
yn() { env -i PATH="${PATH}" "$@" bash -c 'CIGUA_INSTALL_SOURCED=1 source "$0/install.sh"; ask_yes_no X "¿?" "${DEF:-n}"; echo "${X}"' "${ROOT_DIR}" </dev/null; }
for v in 1 s si yes Y true; do check "COOLIFY=${v}: sí" test "$(yn X="${v}")" = 1; done
for v in 0 n no nunca; do check "COOLIFY=${v}: no" test "$(yn X="${v}")" = 0; done
check "sin terminal ni valor: usa el defecto (n)" test "$(yn)" = 0
check "sin terminal ni valor: usa el defecto (s)" test "$(yn DEF=s)" = 1

echo "setup_coolify"
# shellcheck disable=SC2016
sc() { env -i PATH="${PATH}" "$@" bash -c 'CIGUA_INSTALL_SOURCED=1 source "$0/install.sh"; setup_coolify; echo "C=${COOLIFY} P=${PUBLIC_TCP_PORTS:-}"' "${ROOT_DIR}" </dev/null 2>&1; }
check "por defecto no instala Coolify y no pide nada" test "$(sc)" = "C=0 P="
check "COOLIFY=1 abre 80 y 443" grep -q 'P=80 443' <<<"$(sc COOLIFY=1 COOLIFY_ADMIN_EMAIL=a@b.c COOLIFY_ADMIN_PASSWORD=12345678)"
check "respeta PUBLIC_TCP_PORTS del entorno" grep -q 'P=443' <<<"$(sc COOLIFY=1 PUBLIC_TCP_PORTS=443 COOLIFY_ADMIN_EMAIL=a@b.c COOLIFY_ADMIN_PASSWORD=12345678)"
check "COOLIFY=1 sin admin ni terminal: falla con mensaje" grep -q 'necesita' <<<"$(sc COOLIFY=1)"
check "contraseña corta: falla" grep -q 'al menos 8' <<<"$(sc COOLIFY=1 COOLIFY_ADMIN_EMAIL=a@b.c COOLIFY_ADMIN_PASSWORD=corta)"

gen COOLIFY=1 PUBLIC_TCP_PORTS="80 443" VPS_USER=ana AUTHORIZED_KEYS_URLS=https://x.test/a.pub COOLIFY_ADMIN_PASSWORD=secreto-admin COOLIFY_ADMIN_EMAIL=a@b.c
check "host.env guarda COOLIFY=1" grep -qx 'COOLIFY="1"' "${out}"
check "host.env guarda los puertos 80 443" grep -qx 'PUBLIC_TCP_PORTS="80 443"' "${out}"
refute "host.env no guarda la contraseña del admin" grep -q 'secreto-admin' "${out}"
refute "host.env no guarda el correo del admin" grep -q 'a@b.c' "${out}"

finish
