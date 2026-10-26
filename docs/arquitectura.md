# Viabilidad y decisiones — 22 de octubre de 2026

Actualización del 24 de octubre: el puente Arduino pasó comandos HCI y escaneo BLE.
Se añadió el [prototipo KMDF/BTHX](../windows-driver/DRIVER.md). El 25 de octubre
se instalaron las herramientas, se compiló y pasó la validación INF/CAT; sigue
sin firma ni carga. El análisis siguiente recoge
la viabilidad previa; la nueva implementación y su estado se detallan en ese documento.

## Conclusión

El controlador Bluetooth del ESP32 original puede exponerse por HCI. El USB-UART
del DevKit no enumera una interfaz USB Bluetooth: Windows lo identifica como CP210x.
Hay una ruta de ingeniería hacia la pila nativa, pero falta un controlador de
transporte adaptado al dispositivo. No se ha demostrado la autenticación con iPhone.

```text
Prototipo verificable:
diagnose.py -> pyserial -> CP210x/COM -> UART1 H4 -> controlador BT ESP32

Arquitectura nativa pendiente:
navegador/WebAuthn -> pila Bluetooth Windows -> Bthmini/BTHX
  -> driver KMDF adaptado -> driver CP210x -> UART H4 -> ESP32
```

El primer recorrido sirve para medir el hardware y protocolo; no satisface por sí
solo las APIs Bluetooth que utiliza el navegador.

## ESP-IDF y firmware

Se revisaron el ejemplo oficial y Kconfig de **v5.5.1**. Soportan controlador sin
host, H4, selección UART1/2, baudios y desactivación de control de flujo. El ejemplo
oficial habilita UART/UHCI y enruta señales antes de inicializar el controlador.
Aquí UART1 se enruta a los cables existentes del UART0 de la placa, GPIO1/3, y se
desactiva la consola. No se cambia el hardware USB ni se configura HCI UART0 fuera
del rango documentado. El controlador se habilita en modo dual.

Fuentes primarias:
- [Ejemplo v5.5.1](https://github.com/espressif/esp-idf/tree/v5.5.1/examples/bluetooth/hci/controller_hci_uart_esp32)
- [Kconfig del controlador](https://github.com/espressif/esp-idf/blob/v5.5.1/components/bt/controller/esp32/Kconfig.in)
- [API Controller y VHCI](https://docs.espressif.com/projects/esp-idf/en/v5.5.1/esp32/api-reference/bluetooth/controller_vhci.html)

La documentación de migración 6.1 describe cambios en inicialización y un ejemplo
unificado. Por tanto no prometemos compilar este prototipo con cualquier versión;
el código rechaza una versión distinta hasta revisar y probar la migración.
[Migración oficial](https://docs.espressif.com/projects/esp-idf/en/latest/esp32/migration-guides/release-6.x/6.1/bt_common.html).

## Proyecto dakhnod

Se inspeccionó el commit `4ebcbc127815b33202d2b71d5845a0363b808fb0`.
La receta de uso utiliza BlueZ y `hciattach` en Linux. La sección Windows no aporta
una implementación. Su firmware fuerza `hci_uart_no = 0`, mientras Kconfig limita
la selección a UART1/2, y usa una API privada para habilitar UHCI. Esto impide dar
por hecha la compatibilidad con nuevas versiones de IDF. No se compiló ese proyecto
ni se lo utilizó como driver Windows.
[Repositorio examinado](https://github.com/dakhnod/ESP32-Bluetooth-USB-dongle).

## Windows 10 y 11

Microsoft proporciona DDIs BTHX y un ejemplo KMDF de bus HCI serie. Es una base,
no un driver listo para este DevKit. La documentación describe recursos de plataforma
y personalización del fabricante. En el código actual, `Fdo.c` abre el UART mediante
Resource Hub; `DeviceInitialize` necesita implementación específica. El INF actual
incluye enumeración raíz de prueba: eso no conecta automáticamente un COM USB.

La adaptación propuesta deberá resolver PnP, el destino serie USB, exclusividad,
baudios, paquetes, créditos, cancelación, desconexión y energía. Un programa Python
o un servicio que lea COM no puede por sí solo registrar este radio en Bthmini.
La ruta concreta propuesta requiere un componente en kernel; sigue siendo experimental.

- [Ejemplo Microsoft](https://learn.microsoft.com/en-us/samples/microsoft/windows-driver-samples/bluetooth-serial-hci-bus-driver/)
- [Código del transporte](https://github.com/microsoft/Windows-driver-samples/blob/main/bluetooth/serialhcibus/Fdo.c)
- [Inicialización específica](https://github.com/microsoft/Windows-driver-samples/blob/main/bluetooth/serialhcibus/WDK/device.c)
- [INF de ejemplo](https://github.com/microsoft/Windows-driver-samples/blob/main/bluetooth/serialhcibus/WDK/SerialBusWdk.inx)
- [DDIs reales BTHX](https://learn.microsoft.com/en-us/windows-hardware/drivers/ddi/bthxddi/)

No se ha establecido una matriz de compatibilidad por build de Windows 10/11.
El entorno local es Windows 11 Pro x64, build 26200. La disponibilidad de BLE no
garantiza el flujo de passkeys en cada combinación de navegador y sistema.
Se deben validar ambos niveles por separado en cada sistema objetivo.

## Passkeys

FIDO usa BLE para verificar proximidad en autenticación entre dispositivos. Ese
uso no equivale a transferir la clave privada por BLE ni requiere que implementemos
un servicio GATT propio en el ESP32. El navegador/sistema debe poder utilizar el radio.
[FIDO Alliance](https://fidoalliance.org/passkeys-2/).

Microsoft pide Bluetooth habilitado, proximidad e Internet en ambos dispositivos
para resolver fallos del flujo entre dispositivos.
[Requisitos y problemas de passkeys](https://support.microsoft.com/en-us/accounts-billing/security/troubleshoot-signing-in-with-a-passkey).
Apple documenta el uso de passkeys con dispositivos ajenos a Apple cercanos y que
la clave privada no se comparte con el servidor.
[Seguridad de passkeys](https://support.apple.com/en-us/102195).

Inferencia técnica: BLE del ESP32 puede aportar la radio necesaria, pero no es una
certificación de compatibilidad con Apple. La prueba decisiva requiere el driver,
APIs BLE operativas y el flujo real del sitio. No declarar éxito por ver el QR.

## Alternativas y criterio de continuidad

Para explorar HCI con este hardware, continuar con el laboratorio. Para alcanzar
el objetivo de inicio de sesión con menor trabajo, la alternativa es un adaptador
USB Bluetooth con soporte Windows y driver firmado, verificando sus requisitos
con el fabricante. Un segundo MCU USB que implemente realmente la clase Bluetooth
también sería otro proyecto de hardware y firmware, no una capacidad del CP210x.
Linux/BlueZ permitiría explorar el controlador, pero no resuelve la pila Windows.

No iniciar un driver amplio hasta medir respuestas HCI y escaneo sin pérdidas.
Después realizar una prueba acotada BTHX en un equipo de laboratorio; si no hay una
ruta mantenible de firma e instalación, detener esa vía y conservar el prototipo.
