# Tailscale

Una tailnet, cuatro dispositivos: `cigua`, `andrea`, `songbird` y el teléfono.
Todo el SSH (y por tanto herdr) pasa por ella.

## Reglas

- La política vive en `tailscale/policy.hujson`. Edítala aquí y pégala en la consola: el repo es la fuente.
- `cigua` lleva `tag:server`. Los equipos con tag no caducan su llave.
- ANDREA: en la consola, desactiva *Key expiry* (hace de host y no debe caerse a los 180 días).
- MagicDNS activo: los nombres cortos resuelven a la IP 100.x.
- Sin Tailscale SSH: el SSH sigue con las llaves por máquina (igual que en dotfiles).

## Qué permite la política

| Desde | Hacia | Permitido |
|---|---|---|
| Tus dispositivos | Tus dispositivos | Todo (SSH, Taildrop) |
| Tus dispositivos | `cigua` | Solo puerto 22 |
| `cigua` | Cualquiera | Nada |

Si el VPS cae en manos de otro, no tiene camino a tus PCs.
Para exponer algo más del VPS por la tailnet (un relay, una web interna), añade su puerto a la segunda regla.

## Si falla con `requested tags [tag:server] are invalid or not permitted`

La política de la tailnet no define `tag:server`. La política por defecto de Tailscale trae `tagOwners` comentado, así que un tailnet nuevo siempre cae aquí.

1. Pega `tailscale/policy.hujson` en *Access controls* y guarda.
2. Si usas una auth key, créala de nuevo con el tag `tag:server`: una llave anterior a la política, o sin tags, da el mismo error.
3. Quien ejecuta `tailscale up` debe ser dueño del tag (`autogroup:admin` cubre a los Admin y Owner de la tailnet).

## SSH config (en dotfiles)

En `ssh/.ssh/config` de tus dotfiles:

```
Host cigua andrea songbird
    User cigua
    IdentityFile ~/.ssh/github.pub
    IdentitiesOnly yes
    ServerAliveInterval 30
    ServerAliveCountMax 4
```

- `github.pub` apunta a la llave de la máquina donde estás, así que el bloque sirve en las tres.
- Sin `HostName`: MagicDNS resuelve el nombre corto.

## ANDREA como host

ANDREA también recibe conexiones (`herdr --remote andrea` desde Songbird):

```bash
sudo systemctl enable --now sshd
sudo ufw allow in on tailscale0 to any port 22 proto tcp
```

Y en su `~/.ssh/authorized_keys`, la llave de Songbird (`ssh/.ssh/songbird.pub` de dotfiles).

## Teléfono

- App de Tailscale con la misma cuenta.
- Cliente SSH (Moshi, Termius, Sherpr): genera una llave en la app y añádela a `AUTHORIZED_KEYS_URLS`
  (o a mano fuera del bloque gestionado de `authorized_keys`).

## Comprobar

```bash
tailscale status          # los 4 equipos
ssh cigua hostname        # desde ANDREA y Songbird
```
