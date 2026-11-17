# Primer arranque

Orden para un VPS nuevo (Ubuntu 24.04). Asume `VPS_HOSTNAME=cigua` y `VPS_USER=cigua`.

## 0. Antes de tocar el VPS

- **Tailscale:** pega `tailscale/policy.hujson` en la consola (*Access controls*).
  Sin `tag:server` en `tagOwners`, el módulo `tailscale` falla.
- **ntfy** (opcional): crea el topic y un token de acceso.
- **Decide** si este VPS es el de Coolify. Si lo es: `PUBLIC_TCP_PORTS="80 443"` y lee `recuperacion.md` (Docker y ufw).

## 1. Clonar y configurar

Como root o tu usuario inicial, por la IP pública (Tailscale aún no está).

Repo privado en un VPS sin llaves todavía: clona por HTTPS con un token de un solo uso.

```bash
apt-get update && apt-get install -y git
git clone https://<token>@github.com/savaf/cigua.git ~/cigua
cd ~/cigua && git remote set-url origin https://github.com/savaf/cigua.git   # no dejar el token
cp host.env.example host.env && nano host.env
```

## 2. Sistema y red

```bash
sudo ./bootstrap.sh base swap user tailscale ssh firewall
```

- `user` te pide la contraseña nueva de `cigua` (la usa sudo).
- `tailscale` imprime una URL de login, o usa `TS_AUTHKEY`.
- `firewall` deja el 22 público abierto porque entraste desde fuera. Es lo esperado.
- `ssh` cierra el login de root para conexiones nuevas; tu sesión actual sigue abierta.

Si clonaste como root, pásale el repo al usuario antes de seguir:

```bash
sudo mv /root/cigua /home/cigua/ && sudo chown -R cigua: /home/cigua/cigua
```

## 3. Pasar a la tailnet

Desde Songbird o ANDREA:

```bash
ssh -t cigua@cigua 'cd ~/cigua && sudo ./bootstrap.sh firewall'
```

Ahora sí cierra el SSH público. Comprueba en una terminal nueva antes de cerrar la vieja:

```bash
ssh cigua@cigua hostname        # por Tailscale: responde
ssh cigua@<ip-publica> hostname # debe fallar (timeout)
```

## 4. Dotfiles y llave

```bash
sudo ./bootstrap.sh dotfiles git-key
```

- `dotfiles` avisa que falta `ssh/.ssh/cigua.pub`. Normal la primera vez.
- `git-key` genera la llave y te imprime la `.pub` y la línea de `allowed_signers`.

Desde una PC, en tus dotfiles:

1. Guarda la pública en `ssh/.ssh/cigua.pub`.
2. Añade la línea a `ssh/.ssh/allowed_signers`.
3. Commit + push. `scripts/test-ssh-key.sh` debe seguir en verde.
4. En GitHub → Settings → SSH keys: regístrala como *Authentication key* y como *Signing key*.
5. Añade a `ssh/.ssh/config` el bloque de hosts (ver `tailscale.md`).

De vuelta en el VPS:

```bash
sudo ./bootstrap.sh dotfiles git-key claude-managed agents
git -C ~/dotfiles remote set-url origin git@github.com:savaf/dotfiles.git
git -C ~/cigua remote set-url origin git@github.com:savaf/cigua.git
```

`git-key` debe decir `GitHub acepta la llave de cigua ✔`.

## 5. Claude y avisos

Ver [agentes.md](agentes.md): logins, teamclaude, herdr, teléfono.

```bash
nano ~/.config/cigua/notify.env   # NTFY_TOKEN=…
```

## Después

- Cualquier cambio: edita el repo, `git pull` en el VPS, `sudo ./bootstrap.sh <módulo>`.
- Todo de nuevo es seguro: `sudo ./bootstrap.sh`. El `apt upgrade` completo solo corre la primera vez
  (marcador `/var/lib/cigua/apt-upgraded`); `APT_UPGRADE=1 sudo ./bootstrap.sh base` lo fuerza.
- Los módulos corren siempre en el orden de `--list`, aunque los pidas en otro, y sin repetirse.

### SSH público o solo por la tailnet

Por defecto (`SSH_PUBLIC=1`) el 22 queda abierto también fuera de la tailnet: solo llaves, sin root,
con fail2ban. Así Coolify valida su servidor `localhost` y puedes entrar sin Tailscale. El panel de
Coolify (8000, 6001, 6002) no se abre nunca: escucha solo en la IP de la tailnet.
Con `SSH_PUBLIC=0` el SSH va solo por Tailscale y rige la guarda de abajo (pasos 3 y 4 de esta guía).

#### Cuándo el firewall cierra el SSH público (SSH_PUBLIC=0)

Solo con una prueba positiva: entraste por la tailnet (cliente y IP local en `100.64.0.0/10`),
corres desde la consola del proveedor, o pones `FORCE_FIREWALL=1`. Dentro de tmux o herdr no hay IP de
cliente ni consola, así que se deja abierto: entra por `ssh cigua@cigua` y repite
`sudo ./bootstrap.sh firewall`. Las reglas "cigua: público" que ya no estén en `PUBLIC_TCP_PORTS` se borran.
