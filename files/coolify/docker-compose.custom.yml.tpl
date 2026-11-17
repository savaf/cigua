# Gestionado por el repo cigua (modules/coolify.sh). __TAILNET_IP__ se sustituye al instalar.
# Panel y realtime solo en la IP de la tailnet: Docker publicaría 0.0.0.0 y se saltaría ufw.
services:
  coolify:
    ports: !override
      - "__TAILNET_IP__:8000:8080"
  soketi:
    ports: !override
      - "__TAILNET_IP__:6001:6001"
      - "__TAILNET_IP__:6002:6002"
