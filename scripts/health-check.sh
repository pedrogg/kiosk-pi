#!/usr/bin/env bash
# Revision de la Pi. Pensado para la prueba de 24 h y para la visita: dice QUE
# esta mal, no solo que algo lo esta. Salida distinta de 0 si hay algun fallo.
set -uo pipefail

FALLOS=0
ok()   { printf '  ✔ %s\n' "$*"; }
mal()  { printf '  ✘ %s\n' "$*"; FALLOS=$((FALLOS+1)); }
aviso(){ printf '  ! %s\n' "$*"; }

echo "== Servicio =="
if systemctl is-active --quiet kiosk; then
  ok "kiosk activo desde $(systemctl show kiosk -p ActiveEnterTimestamp --value)"
else
  mal "kiosk NO esta activo: $(systemctl is-active kiosk)"
fi
# Un servicio activo que lleva 40 reinicios no esta sano: esta cayendose y
# levantandose, y a ojo se ve igual que uno que funciona.
REINICIOS=$(systemctl show kiosk -p NRestarts --value 2>/dev/null || echo 0)
if [ "${REINICIOS:-0}" -gt 3 ]; then
  mal "$REINICIOS reinicios desde el arranque (mira: journalctl -u kiosk)"
else
  ok "$REINICIOS reinicios"
fi

echo "== Hora =="
if timedatectl show -p NTPSynchronized --value | grep -q yes; then
  ok "reloj sincronizado — $(date '+%d-%m-%Y %H:%M %Z')"
else
  mal "reloj SIN sincronizar: la pizarra mostrara la semana equivocada"
fi
[ "$(timedatectl show -p Timezone --value)" = "Europe/Madrid" ] \
  && ok "zona Europe/Madrid" || mal "zona horaria: $(timedatectl show -p Timezone --value)"

echo "== Pizarra =="
if [ -r /etc/kiosk/board.env ]; then
  # shellcheck disable=SC1091
  . /etc/kiosk/board.env
  COD=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 \
        -H "Authorization: Bearer ${BOARD_TOKEN}" "${BOARD_URL}/items" || echo 000)
  case "$COD" in
    200) ok "la pizarra responde 200" ;;
    401) mal "401: el token no vale (revocado o de otro tablero)" ;;
    000) mal "sin respuesta: red caida o DNS" ;;
    *)   mal "respuesta $COD" ;;
  esac
  PERM=$(stat -c '%a %U:%G' /etc/kiosk/board.env)
  case "$PERM" in
    "640 root:kiosk"|"600 root:root") ok "permisos del token: $PERM" ;;
    *) mal "permisos del token flojos: $PERM (esperado 640 root:kiosk)" ;;
  esac
else
  mal "no puedo leer /etc/kiosk/board.env (ejecuta esto con sudo)"
fi

echo "== Aparato =="
if command -v vcgencmd >/dev/null 2>&1; then
  T=$(vcgencmd measure_temp 2>/dev/null | tr -d "temp='C")
  # En un taller hay polvo y calor: por encima de 80 el SoC baja la frecuencia
  # y la pagina empieza a ir a tirones sin que nada aparezca "roto".
  awk -v t="${T:-0}" 'BEGIN{exit !(t>80)}' && aviso "temperatura ${T}°C: sobre 80, va a limitar" || ok "temperatura ${T}°C"
  TH=$(vcgencmd get_throttled 2>/dev/null | cut -d= -f2)
  [ "$TH" = "0x0" ] && ok "sin limitaciones (throttled $TH)" \
    || aviso "throttled $TH — suele ser la fuente de alimentacion, no el calor"
fi
USO=$(df --output=pcent / | tail -1 | tr -dc '0-9')
[ "${USO:-0}" -lt 85 ] && ok "disco al ${USO}%" || mal "disco al ${USO}%"

echo
[ "$FALLOS" -eq 0 ] && echo "Todo correcto." || echo "$FALLOS comprobacion(es) en rojo."
exit $((FALLOS > 0))
