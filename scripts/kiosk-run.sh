#!/usr/bin/env bash
# Arranca Chromium en kiosko bajo cage. Lo invoca kiosk.service; no se llama a mano.
set -euo pipefail

: "${BOARD_URL:?falta BOARD_URL en /etc/kiosk/board.env}"
: "${BOARD_TOKEN:?falta BOARD_TOKEN en /etc/kiosk/board.env}"

# El binario cambia de nombre segun la version de Pi OS: en Bookworm es
# `chromium`, en las anteriores `chromium-browser`. Se detecta en vez de
# suponerse, porque suponerlo falla en la mitad de las Pi y el sintoma es una
# pantalla negra sin mensaje.
CHROMIUM=""
for c in chromium chromium-browser; do
  if command -v "$c" >/dev/null 2>&1; then CHROMIUM="$c"; break; fi
done
[ -n "$CHROMIUM" ] || { echo "no encuentro chromium ni chromium-browser" >&2; exit 1; }

# El token viaja en el FRAGMENTO de la URL, que el navegador NUNCA envia al
# servidor: no aparece en los logs de Cloudflare, ni en nuestro tail, ni en
# la cabecera Referer hacia terceros (ADR-0041 enmienda 1, 10-11-2026).
# La pagina lo lee de location.hash, lo guarda y lo
# retira de la barra. Aun asi queda en el journal si alguien registra argv, por
# eso la unidad no lo pone en ExecStart y este script no hace `set -x`.
URL="${BOARD_URL}#k=${BOARD_TOKEN}"

# El perfil es PERSISTENTE a proposito: la pagina cachea la ultima respuesta en
# localStorage para poder mostrar algo cuando se cae la red. Con --incognito la
# pantalla amanece en blanco tras cada corte de luz, que es justo el caso que
# el cache existe para cubrir.
PROFILE=/var/lib/kiosk/chromium

exec cage -d -- "$CHROMIUM" \
  --kiosk \
  --user-data-dir="$PROFILE" \
  --noerrdialogs \
  --disable-infobars \
  --disable-session-crashed-bubble \
  --disable-features=TranslateUI \
  --check-for-update-interval=31536000 \
  --autoplay-policy=no-user-gesture-required \
  "$URL"
