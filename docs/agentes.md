# Agentes en cigua

Los agentes viven en el servidor de herdr del VPS. Las PCs y el teléfono solo se asoman.

## Logins (una vez, interactivos)

Cada máquina hace sus propios logins: nunca copies tokens entre máquinas
(dos procesos que refrescan el mismo token se invalidan).

```bash
claude                               # /login: abre la URL en tu PC y pega el código
claude-profile work                  # solo si traes trabajo al VPS (revisa el contrato antes)
~/dotfiles/scripts/setup-teamclaude.sh
```

- Sin navegador, el script de teamclaude imprime la URL de login para abrirla a mano.
- Si teamclaude espera el login en un puerto local del VPS, abre un túnel desde la PC: `ssh -L <puerto>:localhost:<puerto> cigua`.

## herdr

Desde ANDREA o Songbird:

```bash
herdr --remote cigua
```

- La primera vez arranca el servidor de herdr en el VPS.
- En el primer panel, `hw`: crea los workspaces sin abrir herdr dentro de herdr.
- Para soltarlo: `prefix d`. Los agentes siguen.
- Pegar imágenes funciona: herdr las copia al VPS y pega la ruta.
- Alias sugeridos en dotfiles: `alias hv='herdr --remote cigua'`, `alias ha='herdr --remote andrea'`.

Reinicio del VPS: herdr restaura la forma de la sesión, pero los agentes hay que relanzarlos.
Por eso el módulo `base` no activa reinicios automáticos.

## Teléfono

Tres vías, de menos a más interactiva:

| Vía | Para qué |
|---|---|
| ntfy (hook `cigua-notify`) | Enterarte de que un agente espera respuesta o pide permiso |
| Claude app → Code (Remote Control) | Conversar con un agente. Actívalo con `/config` → *Enable Remote Control for all sessions* |
| Cliente SSH + `herdr` | Ver todo: quién está bloqueado, logs, tests |

- Remote Control: una sesión remota por instancia de Claude Code.
- Sin probar: Remote Control con sesiones que pasan por el proxy de teamclaude. Si falla, usa `command claude`.
- herdr-mobile-relay (`herdr plugin install 0cv/herdr-mobile-relay`) no usa Tailscale: va por gateway propio o de la comunidad.

## Avisos (ntfy)

- El hook vive en `/etc/claude-code/managed-settings.d/50-cigua.json`: solo existe en el VPS y se suma a tus hooks de dotfiles.
- Config y token: `~/.config/cigua/notify.env`.
- Mensaje: `<repo>: <texto de Claude>`, con el hostname como título.
- Excepción: si una cuenta tiene ajustes gestionados desde el servidor de Anthropic (típico en Enterprise/Team), esos ganan y este hook no corre para esa cuenta.
- Probar: `echo '{"cwd":"/x/prueba","message":"hola"}' | cigua-notify`.
