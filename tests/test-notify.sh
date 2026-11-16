#!/usr/bin/env bash
set -euo pipefail

# Test de files/bin/cigua-notify con un curl falso: qué manda y que nunca falla.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/tests/lib.sh"
hook="${ROOT_DIR}/files/bin/cigua-notify"

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
mkdir -p "${work}/bin" "${work}/cfg/cigua"
cat >"${work}/bin/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >"${CURL_LOG}"
EOF
chmod +x "${work}/bin/curl"
export CURL_LOG="${work}/curl.log" XDG_CONFIG_HOME="${work}/cfg" PATH="${work}/bin:${PATH}"

event='{"cwd":"/home/user/Projects/proyecto","message":"Claude needs your permission to use Bash"}'
send() { printf '%s' "$1" | "${hook}"; }

echo "cigua-notify"
check "sin config: sale 0" send "${event}"
refute "sin config: no llama a curl" test -f "${CURL_LOG}"

printf 'NTFY_URL=https://ntfy.example/agentes\nNTFY_TOKEN=tk_prueba\n' >"${work}/cfg/cigua/notify.env"
check "con config: sale 0" send "${event}"
check "mensaje 'repo: texto'" grep -qx 'proyecto: Claude needs your permission to use Bash' "${CURL_LOG}"
check "manda el token" grep -qx 'Authorization: Bearer tk_prueba' "${CURL_LOG}"
check "usa NTFY_URL" grep -qx 'https://ntfy.example/agentes' "${CURL_LOG}"

check "entrada rota: sale 0" send 'esto no es json'
check "entrada rota: mensaje genérico" grep -qx 'un agente espera respuesta' "${CURL_LOG}"

finish
