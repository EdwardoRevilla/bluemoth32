# BlueMoth32

![BlueMoth32, una polilla ASCII con antenas de radio y cuerpo ESP32](assets/brand/bluemoth32.svg?v=2)

**ESP32 Bluetooth HCI para Windows. Un puente para desplegar tus conexiones.**

La mascota es una polilla de radio: sus antenas representan el enlace inalambrico,
su cuerpo es un ESP32 y las dos alas representan los extremos del puente. **Blue**
alude a Bluetooth, **Moth** significa polilla y **32** identifica el ESP32.
Repositorio: [EdwardoRevilla/bluemoth32](https://github.com/EdwardoRevilla/bluemoth32).

La interfaz de terminal utiliza una polilla ASCII propia y verde sobre negro.
Consulta la [identidad visual](docs/identidad.md) y la [vista previa](assets/brand/terminal-preview.svg).

```cmd
bluemoth32.cmd preview
bluemoth32.cmd diagnose
bluemoth32.cmd
```

El menu completo requiere el paquete preparado en `windows-driver/out/BlueMoth32`
o ejecutar el comando dentro del ZIP extraido. El comando `preview` tambien funciona
desde el codigo fuente. Los binarios y certificados de pruebas locales se excluyen
del repositorio: clonar el codigo no instala automaticamente el driver.

```cmd
git clone https://github.com/EdwardoRevilla/bluemoth32.git
cd bluemoth32
bluemoth32.cmd preview
```

Este repositorio prepara un ESP32-WROOM-32 como controlador HCI por serie y permite
comprobar comandos y escaneo BLE. **Incluye un prototipo de controlador Windows
compilado, pendiente de cargar y validar como adaptador Bluetooth nativo.**

La viabilidad del firmware es distinta de la integración de Windows. Consulta
[la investigación](docs/arquitectura.md), [el estado del driver](windows-driver/README.md)
y [el registro de validación](docs/validacion.md) antes de interpretar los resultados.

Para cargar desde Arduino IDE, se incluye un [sketch alternativo VHCI](arduino/Esp32HciBridge/Esp32HciBridgev2/Esp32HciBridgev2.ino)
y [sus instrucciones](arduino/README.md). La corrección Arduino compiló con core 3.3.3,
fue cargada por el usuario y pasó la prueba física el 2026-10-24: Reset, versión local,
funciones LE y 3 eventos de anuncios BLE en 10 segundos. La primera versión no
respondió a Reset; la carga ESP-IDF falló y fue reemplazada por la carga Arduino.

## Hardware y transporte

DevKit V1 con ESP32 original; el USB pertenece al CP210x (detectado en COM3).
UART1 se enruta a GPIO1 TX y GPIO3 RX, conectados al conversor integrado.
H4, 115200 baudios, 8N1, sin RTS/CTS. El controlador de Espressif procesa H4;
la aplicación no implementa otra pila Bluetooth. Dual mode, sin Bluedroid/NimBLE.

La consola y logs normales se desactivan para proteger el canal binario. La ROM
todavía puede emitir texto al reiniciar. El diagnóstico espera dos segundos y
descarta los bytes iniciales. Si el ESP32 se reinicia después, abortar y reiniciar
la prueba: H4 no tiene CRC ni resincronización fiable después de perder bytes.
No usar `idf.py monitor` simultáneamente con el diagnóstico.

## Dependencias y preparación

- Firmware: **ESP-IDF v5.5.1**, target `esp32`. No asumir compatibilidad con 6.x.
- Herramientas PC: Python 3.12, pyserial 3.5; esptool 4.10.0 para respaldo.
- Driver Windows: prototipo KMDF/BTHX compilado con Visual Studio/WDK. Hay un
  [instalador de laboratorio](windows-driver/installer/LEEME.md) con firma local,
  diagnostico y desinstalacion; el destino no necesita herramientas de desarrollo.

Desde la raíz del proyecto:

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r tools/requirements.txt
.\.venv\Scripts\python.exe tools/diagnose.py --list
.\.venv\Scripts\python.exe -m unittest discover -s tests -v
```

Instalación manual de ESP-IDF si no está preparado (ocupa varios GB):

```powershell
git clone --branch v5.5.1 --depth 1 --recursive --shallow-submodules https://github.com/espressif/esp-idf.git "$env:USERPROFILE\esp\esp-idf-v5.5.1"
# En una consola con Python real y Git disponibles:
& "$env:USERPROFILE\esp\esp-idf-v5.5.1\install.ps1" esp32
. "$env:USERPROFILE\esp\esp-idf-v5.5.1\export.ps1"
```

## Compilar, respaldar y flashear

**En esta sesión se canceló el respaldo completo por petición del usuario. No hay
una imagen del firmware anterior para restaurar. `probe-4k.bin` no es un respaldo.**

Confirmar COM y chip; no elegir COM1 automáticamente. Antes de reemplazar firmware,
leer la capacidad con esptool y guardar una copia completa con `read_flash`.
El respaldo puede contener configuración privada: no incorporarlo a Git.

```powershell
cd firmware
idf.py set-target esp32
idf.py build
idf.py -p COM3 -b 230400 flash
cd ..
.\.venv\Scripts\python.exe tools/diagnose.py --port COM3
.\.venv\Scripts\python.exe tools/diagnose.py --port COM3 --scan-seconds 10
```

Reset transmite `01 03 0c 00`; la respuesta esperada es
`04 0e 04 01 03 0c 00`. El script comprueba opcode y status, luego versión local
y funciones LE. El escaneo es pasivo y temporal, y registra eventos HCI en hex.
Un informe de publicidad BLE no prueba conexión GATT, integración Windows ni passkeys.
El iPhone no tiene por qué anunciarse continuamente ni identificarse por su nombre.

En este PC, `tools/build.ps1` prepara el entorno instalado y recompila.
Para obtener un respaldo manual completo de esta placa de 4 MB:

```powershell
.\.venv\Scripts\python.exe -m esptool --chip esp32 --port COM3 --baud 230400 read_flash 0 0x400000 backups/original-2026-10-22.bin
```

Si falla con `Wrong boot mode (0x13)`, mantener BOOT, pulsar y soltar EN, soltar
BOOT y usar `--before no_reset` antes de `read_flash` o `write_flash`.
Restaurar la copia reemplaza el contenido actual completo de flash:

```powershell
.\.venv\Scripts\python.exe -m esptool --chip esp32 --port COM3 --baud 230400 write_flash 0 backups/original-2026-10-22.bin
```

La partición por defecto del prototipo usa los primeros 2 MB de los 4 MB físicos;
no necesita cambiar la tabla para este firmware de unos 397 KB.

## Limitaciones conocidas

- Sin control de flujo físico pueden perderse bytes bajo carga. No apto para audio
  ni tráfico sostenido sin medir estabilidad. 115200 es una velocidad conservadora.
- DTR/RTS pueden reiniciar algunas DevKit al abrir el puerto; el script reduce ese
  efecto pero no puede garantizar el comportamiento de todos los conversores.
- `ESP_ERROR_CHECK` puede producir salida de error ante fallos fatales. Esa sesión
  HCI deja de ser válida. Para depuración persistente usar JTAG u otro UART/pines.
- Un fallo NVS detiene el arranque: no borramos memoria automáticamente.
- El decodificador PC cubre Command, ACL, SCO y Event; no ISO (el ESP32 es BT 4.2).
- No instalar un INF genérico sobre todos los dispositivos CP210x. Compartir VID/PID
  no significa que todos contengan este firmware.
- El acceso COM es exclusivo. Cerrar monitores serie y otros programas antes de probar.

Se implementó un [prototipo de transporte BTHX en kernel](windows-driver/DRIVER.md),
con proyecto WDK, selección CP210x, configuración serie y handshake HCI. El 2026-10-25
compiló x64 Debug sin errores ni advertencias; el test C nativo y la validación
INF/CAT pasaron. El paquete en `windows-driver/package` sigue sin firma y sin carga:
falta validar el radio nativo en Windows.

## Licencias

Las adiciones originales del proyecto se publican bajo [MIT](LICENSE). Los archivos
derivados del ejemplo de controladores de Microsoft conservan su licencia
[MS-PL](windows-driver/LICENSE.MS-PL). Consulta la [procedencia de los componentes](windows-driver/THIRD_PARTY.md).
