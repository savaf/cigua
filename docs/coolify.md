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

```bash
# config del host: COOLIFY=1 y PUBLIC_TCP_PORTS="80 443"
sudo COOLIFY_ADMIN_EMAIL=tu@correo COOLIFY_ADMIN_PASSWORD='…' ./bootstrap.sh firewall hardening coolify
```

Panel: `http://cigua:8000` desde un equipo de la tailnet.

## Verificar (tras instalar)

```bash
ss -tlnp | grep -E ':(8000|6001|6002)'   # solo la IP 100.x, nunca 0.0.0.0
```

Desde fuera de la tailnet, `curl http://<ip-publica>:8000` debe fallar.

## Supuestos a confirmar

- El servicio realtime se llama `soketi` en el compose de Coolify.
- El instalador lanzado como usuario no root coloca la llave de Coolify en `~coolify/.ssh/authorized_keys`. Si no, añádela a mano y registra el servidor con el usuario `coolify` en el panel.
- El contenedor entra al host por la red `172.16.0.0/12`. Si Coolify no valida el servidor
  localhost, revisa con `journalctl -u ssh` desde qué IP llega.
- El instalador no permite fijar versión; el módulo muestra su sha256 al descargarlo.

## Riesgo que queda

Un agente comprometido en este VPS ya no comparte usuario con Coolify, pero sigue en la misma
máquina (kernel, red de Docker, sudo si lo tuviera). Si el VPS aloja apps de clientes, mejor separarlos.
