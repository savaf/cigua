# Mini-asserts para los tests. Se carga con source: sin shebang.
#   check "descripción" comando args…    # pasa si el comando sale 0
#   refute "descripción" comando args…   # pasa si el comando sale distinto de 0

fails=0

check() {
  local desc="$1"; shift
  if "$@"; then echo "  ok   ${desc}"; else echo "  FAIL ${desc}"; fails=$((fails + 1)); fi
}

refute() {
  local desc="$1"; shift
  if "$@"; then echo "  FAIL ${desc}"; fails=$((fails + 1)); else echo "  ok   ${desc}"; fi
}

finish() {
  (( fails == 0 )) || { echo "${fails} fallo(s)"; exit 1; }
}
