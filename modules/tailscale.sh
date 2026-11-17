# Une el VPS a la tailnet. Antes, define tag:server en la política (tailscale/policy.hujson):
# sin eso, --advertise-tags falla.
#   sudo ./bootstrap.sh tailscale                       # login interactivo (abre una URL)
#   sudo TS_AUTHKEY=tskey-auth-… ./bootstrap.sh tailscale   # sin interacción
# --accept-dns=false: no tocar el DNS del VPS (Docker/Coolify lo agradecen); el VPS no
# necesita resolver a los demás equipos porque nunca inicia conexiones hacia ellos.

# El login interactivo necesita terminal; sin ella hace falta una auth key.
tailscale_login_possible() { [[ -n "${TS_AUTHKEY:-}" ]] || have_tty; }

run_tailscale() {
  if ! exists tailscale; then
    log "instalando Tailscale"
    curl -fsSL https://tailscale.com/install.sh | sh
  fi
  systemctl enable --now tailscaled

  local state
  state="$(tailscale status --json 2>/dev/null | jq -r '.BackendState // ""' || true)"
  if [[ "${state}" == "Running" ]]; then
    log "ya en la tailnet como $(tailscale status --json | jq -r '.Self.DNSName')"
    tailscale set --hostname="${VPS_HOSTNAME}" --accept-dns=false
    return
  fi

  tailscale_login_possible || die "sin terminal ni TS_AUTHKEY: tailscale up se quedaría esperando el login. Usa una terminal o TS_AUTHKEY"
  local args=(--hostname="${VPS_HOSTNAME}" --accept-dns=false)
  [[ -n "${TAILSCALE_TAGS:-}" ]] && args+=(--advertise-tags="${TAILSCALE_TAGS}")
  [[ -n "${TS_AUTHKEY:-}" ]] && args+=(--auth-key="${TS_AUTHKEY}")
  log "tailscale up ${args[*]//--auth-key=*/--auth-key=***}"
  tailscale up "${args[@]}"
  log "IP en la tailnet: $(tailscale ip -4)"
}
