# Gestionado por el repo cigua (modules/coolify.sh). __TAILNET_IP__ se sustituye al instalar.
# El panel (8000) solo en la IP de la tailnet: Docker publicaría 0.0.0.0 y se saltaría ufw.
# El realtime (6001) y la terminal web (6002) no se publican en el host: se sirven por el proxy
# de Coolify cuando la instancia tiene dominio (Settings → Instance's Domain).
services:
  coolify:
    ports: !override
      - "__TAILNET_IP__:8000:8080"
  soketi:
    ports: !override []
