# cigua

Configuración del VPS donde viven mis agentes de código 24/7.
Complementa a [savaf/dotfiles](https://github.com/savaf/dotfiles); no lo duplica.

| Repo | Qué gestiona |
|---|---|
| `dotfiles` | Lo que es igual en todas las máquinas: zsh, mise, herdr, Claude Code (settings, agentes, hooks, skills) |
| `cigua` | Lo que solo existe en el servidor: usuario, Tailscale, firewall, sshd, swap, llave de la máquina, avisos, repos a clonar |

El bootstrap de `cigua` llama al de `dotfiles` (módulo `dotfiles`). Nada de shell ni de Claude se configura aquí dos veces.

## Arquitectura

```
 Songbird ──┐                         ┌── herdr (servidor persistente)
            ├── tailnet ── ssh ──> cigua ── Claude Code / agentes en worktrees
 ANDREA ────┤   (100.x)               └── ssh-agent con la llave de la máquina
 teléfono ──┘                               │
                                            └─> ntfy (avisos al teléfono)
```

- Los agentes corren en el VPS y sobreviven a que cierres la laptop.
- ANDREA y Songbird son clientes: `herdr --remote cigua`.
- El SSH solo escucha por la tailnet. El VPS no puede iniciar conexiones hacia las PCs (ver `tailscale/policy.hujson`).

## Uso

```bash
git clone <este repo> ~/cigua && cd ~/cigua
cp host.env.example host.env   # ajusta hostname, usuario, puertos
sudo ./bootstrap.sh            # todos los módulos
sudo ./bootstrap.sh firewall   # uno solo
./bootstrap.sh --list          # qué hace cada módulo
```

Primer arranque, paso a paso: [docs/primer-arranque.md](docs/primer-arranque.md).

## Módulos

En orden. Todos son idempotentes.

| Módulo | Qué hace |
|---|---|
| `base` | Paquetes base, hostname, zona horaria, parches de seguridad automáticos (sin reinicio) |
| `swap` | Swapfile de `SWAP_GB`, `swappiness=10` |
| `user` | `VPS_USER` con sudo y linger, sin grupo `docker`; `authorized_keys` con las llaves de las PCs |
| `tailscale` | Une el VPS con `tag:server` y `--accept-dns=false` |
| `ssh` | Drop-in de sshd: solo llaves, sin root. No actúa si `VPS_USER` no tiene llaves |
| `firewall` | ufw: SSH solo por `tailscale0`. Guarda anti-bloqueo: no cierra el 22 público si entraste desde fuera de la tailnet |
| `dotfiles` | Clona `savaf/dotfiles` y corre su bootstrap como `VPS_USER` |
| `git-key` | Llave SSH propia del VPS + ssh-agent de usuario; te dice qué commitear en dotfiles |
| `claude-managed` | Hook de avisos a ntfy en `/etc/claude-code/managed-settings.d/`, solo en este VPS |
| `agents` | Instala Claude Code si falta y clona los repos de `repos.txt` |

## Estructura

```
bootstrap.sh          entrada única
host.env.example      config no secreta (copiar a host.env, ignorado)
repos.txt             repos a clonar en el VPS
lib/common.sh         utilidades compartidas
modules/*.sh          un paso por archivo; cada uno define run_<módulo>
files/                lo que se instala tal cual (sshd, systemd, hook, managed settings)
tailscale/            política de la tailnet (se pega en la consola)
tests/                tests con comandos falsos; no tocan el sistema
docs/                 primer arranque, Tailscale, agentes, recuperación
```

## Secretos

- Ninguno en el repo. `host.env` está ignorado y aun así no lleva secretos.
- Token de ntfy: `~/.config/cigua/notify.env` (600).
- Auth key de Tailscale: solo por entorno, `sudo TS_AUTHKEY=… ./bootstrap.sh tailscale`.
- La llave privada del VPS vive en `~/.ssh/<hostname>_ed25519` y nunca sale de la máquina.

## Chequeos

```bash
bash scripts/check.sh   # bash -n, shellcheck, JSON y tests; lo mismo que corre CI
```
