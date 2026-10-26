# Registro de validación

Última actualización: 2026-10-25. Actualizar únicamente con evidencia de ejecución.

| Comprobación | Resultado |
|---|---|
| Sistema | Windows 11 Pro x64, 10.0.26200 |
| USB serie | CP210x COM3, VID 10C4 PID EA60, estado OK |
| Chip (esptool flash_id) | ESP32-D0WD-V3 rev. 3.1, cristal 40 MHz, flash 4 MB |
| Entrada bootloader | Reset automático falló (0x13); BOOT + EN manual funcionó |
| Decoder y comandos PC | 11 tests unittest aprobados |
| Firmware compilado | ESP-IDF v5.5.1, GCC esp-14.2.0_20241119; build correcto; imagen 0x60f90 bytes |
| Respaldo completo | Cancelado a petición del usuario por demora; no existe copia completa válida |
| Flash HCI | Falló a 230400: Packet content transfer stopped (received 8 bytes), al escribir bootloader |
| Reintento 115200 | No conectó; siguiente reset automático devolvió boot mode 0x13 |
| Alternativa Arduino | Captura del usuario confirma compilación/carga: 485952 bytes, hash verificado y reset RTS |
| Diagnóstico tras cerrar IDE | COM3 abre; HCI Reset sin respuesta (timeout) |
| Corrección Arduino | Usa btStart() para enlazar HAL y conservar memoria BT antes de setup; compiló con core 3.3.3 (485707 bytes) |
| Carga de corrección | Usuario cargó Esp32HciBridgev2 desde Arduino IDE: 486064 bytes y hash verificado según captura |
| Reset / versión / funciones LE | Aprobados en COM3, 115200; todos con status 0 |
| Escaneo HCI | Aprobado: 3 eventos LE Advertising Report en 10 segundos; desactivación con status 0; proceso terminó con código 0 |
| Driver Windows (fuentes) | Prototipo KMDF/BTHX implementado; proyecto WDK e INF específico |
| Selección driver SetupAPI | Verificada con COM3 y USB VID_10C4 PID_EA60, instancia 0001 |
| Tests de selección/paquete | 13 tests Python aprobados |
| Compilación driver | Aprobada el 2026-10-25: x64 Debug, KMDF 1.15; 0 errores, 0 advertencias |
| Test C nativo | Compiló con MSVC /W4 /WX y pasó |
| Paquete driver | InfVerif /w e Inf2Cat /os:10_GE_X64 aprobados; INF, SYS y CAT generados sin firma |
| Instalador de laboratorio | ZIP generado con lanzador CMD, PowerShell 5.1, SetupAPI y PnPUtil; sin WDK/Python en destino |
| Pruebas del instalador | 18 pruebas aprobadas: hashes, seleccion exacta, duplicados, propiedad de instancia y referencias OEM |
| Firma de copia | SYS/CAT firmados con certificado local de desarrollo en CurrentUser/My; clave privada no exportable; CER publico incluido |
| Diagnostico del instalador | Ejecutado sin elevacion: Windows 26200 x64, TESTSIGNING inactivo, sin confianza local ni instancia ESP32; ningun CP210x presente en esa consulta |
| Radio nativo Windows | No cargado ni probado |
| BLE mediante APIs Windows | No probado |
| Passkeys con iPhone | No probado |

El instalador se preparo sin ejecutar sus acciones de confianza, cambio de arranque,
instalacion ni desinstalacion. El certificado de desarrollo creado tiene huella
`C57AA3417C7C89ECEB7F987C310E1ED78686E481`. El ZIP exporta solamente su parte publica.
No hay validacion de las rutas de instalacion/retirada en kernel: las pruebas
automatizadas ejercitan las condiciones de seleccion e integridad sin mutar Windows.

ESP-IDF instalado en `%USERPROFILE%\esp\esp-idf-v5.5.1`, commit
`fcae32885b0296b32044cb99ecbdc50d98dddb83`; herramientas en `.espressif`.
`build.log` conserva la salida local. La configuración generada confirma H4,
UART1, 115200, sin control de flujo UART, sin host ni consola.

Una lectura de flash a 460800 quedó bloqueada y se canceló sin escribir flash.
Una lectura de 4096 bytes a 230400 terminó y verificó su digest en esptool.
La lectura completa también demoró; el usuario autorizó continuar sin respaldo.
`backups/probe-4k.bin` es solamente una muestra de 4 KB, no una imagen restaurable.
La carga ESP-IDF dejó un estado potencialmente parcial; posteriormente el usuario
cargó la variante Arduino y aportó captura de hash verificado. Tras cerrar el IDE se pudo abrir COM3, pero la
primera versión no respondió a HCI Reset. Se verificó arranque por UART y se
inspeccionó el core Arduino local: sin enlazar esp32-hal-bt.c, btInUse() débil
devuelve false y initArduino() libera la memoria BT. La corrección enlaza ese HAL
mediante btStart(); el mapa de enlace confirma su inclusión. La prueba física
posterior del 2026-10-24 aprobó los comandos HCI y la recepción de anuncios BLE.

## Prueba física aprobada — 2026-10-24

Se ejecutó `tools/diagnose.py --port COM3 --scan-seconds 10` con Python del entorno
`.venv`. Intercambios observados (H4, hexadecimal):

```text
Reset TX:       01 03 0c 00
Reset RX:       04 0e 04 05 03 0c 00
Local Version:  04 0e 0c 05 01 10 00 08 0e 03 08 60 00 0e 03
LE Features:    04 0e 0c 05 03 20 00 ff 00 00 00 00 00 00 00
Scan enable:    04 0e 04 05 0c 20 00
Scan disable:   04 0e 04 05 0c 20 00
```

Se recibieron 3 eventos LE Advertising Report (evento 0x3E, subevento 0x02),
correspondientes a 2 direcciones de anunciante distintas. No se identificó ninguno
como iPhone. No se probó conexión GATT ni tráfico ACL sostenido. La prueba valida
comandos HCI, transporte bidireccional y recepción BLE mediante el puente Arduino;
la integración nativa de Windows y las passkeys continúan pendientes.

## Desarrollo del driver — 2026-10-24

Fuentes en `windows-driver/src`, basadas en Microsoft serialhcibus, commit
`d5569c08aa2818c6240744bb47a00f67f20fdb54`. La adaptación implementa apertura
exclusiva de la interfaz concreta del CP210x, configuración 115200/8N1/sin flujo,
handshake Reset antes de enumerar el hijo BTHX, callbacks de extracción USB,
límites de paquetes/caché y rechazo de escrituras parciales. Incluye proyecto,
plantilla INF y herramientas de selección/empaquetado. Véase `windows-driver/DRIVER.md`.

Se ejecutaron 13 tests Python y la selección real SetupAPI de COM3: aprobados.
El intento de compilación detectó MSBuild/MSVC ausentes. La revisión automática
rechazó ejecutar el instalador de Visual Studio Build Tools por política. No se
compiló, firmó, instaló ni cargó ningún driver. Los tests C nativos están pendientes.
Una comprobación HCI adicional encontró COM3 ocupado (PermissionError 13), sin
alterar el resultado de la prueba física anterior.

Los tests de Python cubren fragmentación en todos los puntos de corte, paquetes
concatenados, ACL/SCO, respuesta de opcode, errores de estado, longitud inválida y
timeout. Son tests de software; no simulan una validación del radio.

## Criterios para las pruebas siguientes

1. Identificar el ESP32 real con esptool y guardar respaldo antes del flash.
2. Compilar con configuración revisada y conservar la salida de compilación.
3. Enviar Reset, versión y funciones LE; guardar respuestas y status cero.
4. Escanear con un anunciante BLE conocido cerca y contar eventos válidos. La ausencia
   de anuncios del iPhone no demuestra fallo. Repetir bajo carga antes de driver.
5. Con driver adaptado: comprobar radio presente sin error y discovery mediante APIs
   Windows; probar suspensión, desconexión y reconexión.
6. Abrir el sitio Apple y elegir iPhone/passkey; ambos equipos con Bluetooth e
   Internet. El usuario escanea QR y autoriza en el iPhone. Éxito significa sesión
   iniciada, no únicamente mostrar un QR o detectar anuncios.

## Instalación de herramientas y build — 2026-10-25

El usuario autorizó reintentar Build Tools. Se descargó el instalador oficial de
Microsoft y se comprobó su firma Authenticode válida antes de ejecutarlo. Esta vez
la instalación se permitió y terminó con código 0. Se instaló:

- Visual Studio Build Tools 2022 17.14.42; MSBuild 17.14.60.
- MSVC 14.44.35207 x86/x64 y bibliotecas con mitigación Spectre.
- Windows SDK con headers/libs 10.0.26100.0.
- WDK 26100.6584, firma del instalador verificada, instalación con código 0.
- Integración `Component.Microsoft.Windows.DriverKit.BuildTools`, código 0.

El test `windows-driver/tests/test_hci_packet.c` compiló y ejecutó correctamente.
El primer build del driver detectó una etiqueta `ReadNext` sin referencias que se
había conservado al eliminar la resincronización; se retiró esa etiqueta. El build
posterior completó con 0 errores y 0 advertencias.

Binario: `windows-driver/out/x64/Debug/Esp32HciBus.sys`, 80384 bytes.
SHA256: `52FE8F4FBA0ED873C89FF871708E5DFBD864C2B83E06217724204D956427EBB9`.
Log local: `.tooling/driver-build.log`.

Se volvió a seleccionar la interfaz real de COM3 por SetupAPI, se preparó el paquete
específico y se ejecutaron InfVerif /w e Inf2Cat con el identificador 10_GE_X64
confirmado por la ayuda del kit. Ambos finalizaron correctamente; Inf2Cat informó
cero errores/advertencias y generó el catálogo. El helper actualizado también pasó
esta comprobación. ZIP: `windows-driver/out/Esp32HciBus-unsigned.zip`.

El `.sys` y el catálogo están **sin firma** (Authenticode NotSigned). No se ha
instalado ni cargado el driver, ni se ha probado BTHX/BLE a través de la pila Windows.
No se cambiaron políticas de seguridad, Secure Boot ni integridad de memoria.
