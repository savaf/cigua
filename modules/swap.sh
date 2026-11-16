# Swapfile. Varios agentes + un build de Node en 4-8 GB de RAM acaban en el OOM killer;
# con swap se vuelven lentos en vez de morir.

run_swap() {
  local gb="${SWAP_GB:-0}"
  if [[ "${gb}" == 0 ]]; then
    log "SWAP_GB=0: sin swap"
    return
  fi
  if swapon --show=NAME --noheadings | grep -q .; then
    log "ya hay swap activa: $(swapon --show=NAME,SIZE --noheadings | tr '\n' ' ')"
    return
  fi
  log "creando /swapfile de ${gb} GB"
  fallocate -l "${gb}G" /swapfile
  chmod 600 /swapfile
  mkswap /swapfile >/dev/null
  swapon /swapfile
  grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >>/etc/fstab
  # Usa la swap solo bajo presión real, no para aparcar páginas frías.
  install_if_changed - /etc/sysctl.d/90-cigua-swap.conf <<'EOF' && sysctl -q --system || true
vm.swappiness = 10
EOF
}
