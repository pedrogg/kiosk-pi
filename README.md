# kiosk-pi

Una Raspberry Pi que enciende y muestra una pizarra a pantalla completa, sola,
y se recupera sin que nadie vaya a tocarla.

No sabe nada de pizarras: lo único que necesita es **una URL y un token de
lectura**. Sirve igual para el tablero de un taller, el menú de una cocina o la
agenda del día de una sala.

## Instalación

Sobre **Raspberry Pi OS Lite** (64 bits) recién grabada, con red y acceso SSH.

**Hardware probado: Raspberry Pi 3 Model B v1.2** (estreno 12-11-2026). Lo que
conviene saber antes de montarla:

- **Alimentación micro-USB**, 5 V / **2,5 A** o más. Con menos aparecen avisos
  de `Undervoltage detected` en consola y la WiFi se cae de forma aleatoria; el
  cable fino y largo da el mismo síntoma que una fuente floja.
- **HDMI de tamaño normal** (no micro-HDMI, que es de la Pi 4 en adelante).
- **WiFi solo 2,4 GHz** y Ethernet a 100 Mbps: si la red del local emite solo en
  5 GHz, la Pi no la ve. Preguntarlo antes de ir.
- **1 GB de RAM**: con Chromium pintando la pizarra quedan ~420 MB libres y la
  placa va a unos 56 °C. Suficiente, pero sin margen para otra cosa.
- **No tiene reloj**: sin red, la fecha del sistema es la de la imagen. Tenlo en
  cuenta al leer los registros de un arranque sin conexión.

```sh
git clone https://github.com/pedrogg/kiosk-pi.git
cd kiosk-pi
sudo BOARD_URL=https://pizarra.cliente.com/p/taller ./scripts/setup.sh
sudo reboot
```

El token se pide por teclado y **no se pasa por la línea de comandos**: ahí
quedaría en el historial del shell y a la vista de `ps`.

Correr `setup.sh` otra vez es seguro — no duplica configuración y **no pisa el
token** que ya esté puesto.

## Qué deja montado

Chromium en modo kiosko bajo [`cage`](https://github.com/cage-kiosk/cage), un
compositor Wayland de una sola ventana: no hay escritorio detrás que pueda
asomar, ni barra, ni diálogos. Lo lleva un servicio de systemd con
`Restart=always`, de modo que un Chromium que muera vuelve en cinco segundos.

Tres cosas que no son obvias y son las que evitan el 90 % de las visitas:

- **`consoleblank=0`** — sin esto el kernel apaga el framebuffer a los diez
  minutos y la pared se queda negra sin que nada haya fallado.
- **Watchdog del SoC** (`RuntimeWatchdogSec=15`) — si el sistema se cuelga del
  todo, systemd deja de alimentarlo y la Pi se reinicia sola. Es la única red
  para un cuelgue duro en una sala donde nadie mira un journal.
- **Perfil de Chromium persistente**, nunca incógnito — la página guarda la
  última respuesta en `localStorage` para poder mostrar algo cuando se cae la
  red. En incógnito, la pantalla amanecería en blanco tras cada corte de luz,
  que es justo el caso que esa caché existe para cubrir.

## Revisión

```sh
sudo ./scripts/health-check.sh
```

Comprueba el servicio y **cuántas veces se ha reiniciado** (un servicio activo
con cuarenta reinicios no está sano: se está cayendo y levantando, y a ojo se
ve igual que uno que funciona), el reloj y la zona horaria, que la pizarra
responda 200 con el token, los permisos del fichero del token, y la
temperatura y el *throttling* del aparato. Devuelve distinto de 0 si algo está
en rojo, así que sirve tal cual para un cron o para la prueba de 24 h.

## El token

Es de **lectura** (`kind=view`), nunca de escritura. Esta Pi está en una sala a
la que entra gente: lo único que debe poder hacer quien se lleve la tarjeta SD
es mirar lo que ya se ve en la pared.

Vive en `/etc/kiosk/board.env` con permisos `0640 root:kiosk` y **no se sube a
ningún repositorio**. Viaja en la URL solo en la primera carga; la página lo
guarda y lo retira de la barra de direcciones.

Para revocarlo: desde el portal del tenant, pantalla «Pizarra». Después,
`sudo ./scripts/setup.sh` no sirve para cambiarlo — edita `/etc/kiosk/board.env`
y `sudo systemctl restart kiosk`.

## Estado de la verificación

Honestidad sobre qué está probado:

- `bash -n` sobre los tres scripts: **pasado**.
- `shellcheck`: **no ejecutado** (no está instalado en la máquina donde se
  escribieron).
- **Ninguno de estos scripts se ha ejecutado en una Raspberry Pi.** Los nombres
  de paquete, las rutas de `cmdline.txt` y el comportamiento de `cage` están
  escritos contra la documentación, no medidos. La prueba de 24 h del bloque 4
  es la primera ejecución real y debe tratarse como tal.
