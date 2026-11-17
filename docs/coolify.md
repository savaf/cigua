# Coolify en este VPS

Coolify controla Docker: equivale a root en la máquina. Por eso se instala con límites.

## Qué hace el módulo

- Solo con `COOLIFY=1` en el archivo de config del host. Si no, se omite.
- Panel (8000) y realtime (6001, 6002) **solo en la IP de la tailnet**, con un
  `docker-compose.custom.yml` escrito antes de instalar. Docker se salta ufw, por eso no basta el firewall.
- 80 y 443 (proxy) por `PUBLIC_TCP_PORTS="80 443"`. Nada más público.
- Corre bajo su propio usuario, `coolify` (`COOLIFY_USER`), distinto de `VPS_USER`: los agentes
  no comparten usuario, home ni llaves con Coolify. Sin contraseña, solo entra por llave, con
  sudo sin contraseña (`/etc/sudoers.d/90-cigua-coolify`) porque administra Docker y el host.
- Root sigue sin poder entrar por SSH. El usuario `coolify` solo entra desde localhost y la red
  de Docker (`files/sshd/90-cigua-coolify.conf`); desde cualquier otro origen se le niega.
- El admin se crea al instalar desde el entorno: así nadie se registra primero.
- `VPS_USER` no puede estar en el grupo `docker` ni ser el mismo usuario que `COOLIFY_USER`; el módulo se niega.

## Instalar

Con el instalador de una línea basta responder **s** a "¿Instalar Coolify?" (o `COOLIFY=1` por entorno):
pide el correo y la contraseña del admin (sin eco, no se guardan), abre 80/443 y lo instala. Todas las
preguntas del instalador tienen defecto: Enter las acepta (Coolify, por defecto, no).

A mano:

```bash
# config del host: COOLIFY=1 y PUBLIC_TCP_PORTS="80 443"
sudo COOLIFY_ADMIN_EMAIL=tu@correo COOLIFY_ADMIN_PASSWORD='…' ./bootstrap.sh firewall hardening coolify
```

Panel: `http://cigua:8000` desde un equipo de la tailnet. La ACL (`tailscale/policy.hujson`) ya permite
los puertos 8000, 6001 y 6002 hacia `tag:server`; si usas una política antigua, pega la actual en la consola de Tailscale.

## Verificar (tras instalar)

```bash
ss -tlnp | grep -E ':(8000|6001|6002)'   # solo la IP 100.x, nunca 0.0.0.0
```

Desde fuera de la tailnet, `curl http://<ip-publica>:8000` debe fallar.

## Puertos

| Puerto | Qué | Dónde |
|---|---|---|
| 22 | SSH y validación del servidor localhost | `SSH_PUBLIC` (por defecto abierto) y los rangos de Docker (regla `cigua: docker a host`) |
| 80, 443 | Proxy y certificados | Públicos (`PUBLIC_TCP_PORTS="80 443"`) |
| 8000, 6001, 6002 | Panel, tiempo real y terminal web | Solo la IP de la tailnet (override del compose + ACL). No se abren a internet |

## Diagnóstico: "Server is not reachable"

Mira `sudo journalctl -u ssh -f` mientras pulsas *Check Again*:

- `Connection refused` al conectar al host: `ufw` o `sshd` no escuchan para esa red. Comprueba la regla
  `cigua: docker a host` en `ufw status` y que `docker_cidrs` coincida con la red del contenedor
  (`docker network inspect coolify`).
- `User coolify from 10.x.x.x not allowed`: el `Match` de `/etc/ssh/sshd_config.d/90-cigua-coolify.conf`
  no exime el rango del contenedor. Revisa `default-address-pools` y vuelve a correr `sudo ./bootstrap.sh coolify`.
- `Connection closed by authenticating user root`: el servidor localhost del panel sigue con usuario
  `root`. En el panel (Servidores → localhost) cámbialo a `coolify` y valida.
- `Failed publickey` o `no matching key`: la llave del panel ("Current Public Key") no está en
  `~coolify/.ssh/authorized_keys`. El módulo avisa si el archivo no tiene ninguna llave.

## Supuestos a confirmar

- El servicio realtime se llama `soketi` en el compose de Coolify.
- El instalador lanzado como usuario no root coloca la llave de Coolify en `~coolify/.ssh/authorized_keys`. Si no, añádela a mano y registra el servidor con el usuario `coolify` en el panel.
- El contenedor entra al host desde los rangos de `default-address-pools` de `/etc/docker/daemon.json`
  (o `172.16.0.0/12` si no hay): `docker_cidrs` en `lib/common.sh` es la única fuente, y de ella salen el
  `Match` de sshd y las reglas de ufw. Si Coolify no valida el servidor localhost, mira el diagnóstico.
- El instalador no permite fijar versión; el módulo muestra su sha256 al descargarlo.

## Riesgo que queda

Un agente comprometido en este VPS ya no comparte usuario con Coolify, pero sigue en la misma
máquina (kernel, red de Docker, sudo si lo tuviera). Si el VPS aloja apps de clientes, mejor separarlos.
