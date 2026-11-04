#!/usr/bin/env bash
# Deja una Raspberry Pi mostrando una pizarra a pantalla completa y sola.
# IDEMPOTENTE: correrlo dos veces no duplica nada ni pisa el token ya puesto.
#
#   sudo BOARD_URL=https://pizarra.cliente.com/p/taller ./scripts/setup.sh
#
# El token NO se pasa por linea de comandos a proposito: quedaria en el
# historial del shell y en `ps`. Se pide por teclado, o se pone a mano en
# /etc/kiosk/board.env antes de ejecutar esto.
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "Ejecutalo con sudo." >&2; exit 1; }

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KIOSK_USER=kiosk
ENV_FILE=/etc/kiosk/board.env

say() { printf '\n▶ %s\n' "$*"; }

# ---------------------------------------------------------------------------
say "Paquetes"
# cage es el compositor Wayland minimo: una sola ventana, siempre a pantalla
# completa, sin escritorio detras que pueda asomar.
apt-get update -qq
apt-get install -y --no-install-recommends cage seatd ca-certificates
# El nombre del paquete de Chromium cambia entre versiones de Pi OS.
if ! command -v chromium >/dev/null 2>&1 && ! command -v chromium-browser >/dev/null 2>&1; then
  apt-get install -y --no-install-recommends chromium || apt-get install -y --no-install-recommends chromium-browser
fi
systemctl enable --now seatd.service

# ---------------------------------------------------------------------------
say "Usuario $KIOSK_USER"
# Sin shell de login y sin contrasena: esta cuenta existe para pintar una
# pantalla, no para entrar por ella.
if ! id -u "$KIOSK_USER" >/dev/null 2>&1; then
  useradd --system --create-home --home-dir /var/lib/kiosk --shell /usr/sbin/nologin "$KIOSK_USER"
fi
usermod -aG video,input,render,tty "$KIOSK_USER"
install -d -o "$KIOSK_USER" -g "$KIOSK_USER" -m 0755 /var/lib/kiosk/chromium

# ---------------------------------------------------------------------------
say "Hora y zona horaria"
# Una pizarra semanal que no sabe que dia es muestra la semana equivocada; y el
# reloj de la cabecera sale del aparato, no del servidor.
timedatectl set-timezone Europe/Madrid
timedatectl set-ntp true

# ---------------------------------------------------------------------------
say "La pantalla no se apaga"
# Sin esto el kernel apaga el framebuffer a los 10 minutos y la pared se queda
# negra sin que nada haya fallado.
for CMDLINE in /boot/firmware/cmdline.txt /boot/cmdline.txt; do
  [ -f "$CMDLINE" ] || continue
  if ! grep -q 'consoleblank=0' "$CMDLINE"; then
    sed -i '1s/$/ consoleblank=0/' "$CMDLINE"
    echo "  consoleblank=0 anadido a $CMDLINE (efectivo tras reiniciar)"
  else
    echo "  $CMDLINE ya lo tiene"
  fi
  break
done

# ---------------------------------------------------------------------------
say "Watchdog"
# Si el sistema se cuelga del todo, systemd deja de dar de comer al watchdog
# del SoC y la Pi se reinicia sola. Es la unica red para un cuelgue duro en una
# sala donde nadie va a mirar un journal.
if ! grep -qE '^RuntimeWatchdogSec=' /etc/systemd/system.conf; then
  printf 'RuntimeWatchdogSec=15\nRebootWatchdogSec=2min\n' >> /etc/systemd/system.conf
  echo "  watchdog configurado (efectivo tras reiniciar)"
else
  echo "  watchdog ya configurado"
fi

# ---------------------------------------------------------------------------
say "Configuracion de la pizarra"
install -d -m 0750 -o root -g "$KIOSK_USER" /etc/kiosk
if [ -f "$ENV_FILE" ]; then
  echo "  $ENV_FILE ya existe; NO lo toco (ahi esta el token)."
else
  URL="${BOARD_URL:-}"
  if [ -z "$URL" ]; then read -r -p "  URL de la pizarra (sin token): " URL; fi
  # -s: el token no se queda en pantalla ni en el historial.
  read -r -s -p "  Token de LECTURA del tablero: " TOKEN; echo
  [ -n "$URL" ] && [ -n "$TOKEN" ] || { echo "URL y token son obligatorios." >&2; exit 1; }
  umask 077
  printf 'BOARD_URL=%s\nBOARD_TOKEN=%s\n' "$URL" "$TOKEN" > "$ENV_FILE"
  chown root:"$KIOSK_USER" "$ENV_FILE"
  chmod 0640 "$ENV_FILE"
  echo "  escrito $ENV_FILE (0640 root:$KIOSK_USER)"
fi

# ---------------------------------------------------------------------------
say "Servicio"
install -m 0755 "$REPO/scripts/kiosk-run.sh" /usr/local/bin/kiosk-run.sh
install -m 0644 "$REPO/systemd/kiosk.service" /etc/systemd/system/kiosk.service
systemctl daemon-reload
systemctl enable kiosk.service
systemctl restart kiosk.service

say "Listo"
cat <<FIN
  Estado:   systemctl status kiosk
  Registro: journalctl -u kiosk -f
  Revision: $REPO/scripts/health-check.sh

  consoleblank y watchdog necesitan un reinicio para entrar en vigor:
    sudo reboot
FIN
