# cigua

Config del VPS de agentes. Complementa a `savaf/dotfiles`: aquí solo va lo que existe en el servidor.

- Shell, herdr y config de Claude Code van en dotfiles, no aquí.
- Cada módulo en `modules/<nombre>.sh` define solo `run_<nombre>` (guiones → `_`) y es idempotente.
- Módulo nuevo: añádelo a `MODULES` y a `describe()` en `bootstrap.sh`, y a la tabla del README.
- Cambios al sistema solo con las utilidades de `lib/common.sh` (`install_if_changed`, `write_managed_block`, `as_user`).
- Cero secretos en el repo, tampoco en `host.env.example`. Los tokens van en archivos 600 del usuario o por entorno.
- Nada que pueda dejar fuera al dueño sin una guarda: ver `firewall.sh` y `ssh.sh`.
- Comentarios y docs en español.
- Antes de terminar: `bash scripts/check.sh` en verde. Un test nuevo por cada guarda o rama de decisión.
