# Recuperación

## Me quedé fuera por SSH

1. Entra por la consola web del proveedor (VNC/serial). No depende de SSH ni de Tailscale.
2. Mira qué falla:
   ```bash
   tailscale status                 # ¿sigue en la tailnet?
   ufw status verbose               # ¿está la regla de tailscale0?
   sshd -t                          # ¿config de sshd válida?
   ```
3. Abrir el 22 público de forma temporal: `ufw allow 22/tcp`. Ciérralo de nuevo con `sudo ./bootstrap.sh firewall` desde la tailnet.
4. Tailscale caído o sin login: `tailscale up --hostname=cigua --advertise-tags=tag:server --accept-dns=false`.

## Docker se salta ufw

Docker inserta sus reglas de iptables antes que ufw: un `-p 8080:8080` queda expuesto a internet aunque ufw diga lo contrario.

- En un VPS solo para agentes: no publiques puertos de contenedores; usa `-p 127.0.0.1:8080:8080`.
- En el VPS de Coolify: el proxy de Coolify ya publica 80/443 y es lo esperado. Revisa con `ss -tlnp` que no haya otros puertos a `0.0.0.0`.
- `VPS_USER` nunca en el grupo `docker` (el módulo `user` avisa).

## Rotar la llave del VPS

Si sospechas que alguien tuvo acceso al VPS:

1. GitHub → Settings → SSH keys: borra las dos entradas de `cigua` (*Authentication* y *Signing*).
2. En el VPS: `rm ~/.ssh/cigua_ed25519*` y `sudo ./bootstrap.sh git-key`.
3. Registra la llave nueva y actualiza `ssh/.ssh/cigua.pub` y `allowed_signers` en dotfiles.
4. Las firmas viejas dejan de verificar: es el precio de rotar.

Rota también el token de ntfy y saca el VPS de la tailnet desde la consola si el compromiso es serio.

## Reinicio

- Agentes: herdr restaura la sesión, no los procesos. Relánzalos.
- ssh-agent y teamclaude vuelven solos (servicios de usuario + linger).
- Comprobar: `systemctl --user status ssh-agent`, `ssh -T git@github.com`.

## Llenó el disco

Los worktrees y `node_modules` crecen rápido:

```bash
dua i ~/Projects                    # dua viene en los dotfiles (mise)
~/.claude/hooks/cleanup-wt.mjs      # dry run de la limpieza de worktrees mergeados
```
