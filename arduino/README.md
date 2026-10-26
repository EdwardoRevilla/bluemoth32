# Carga alternativa con Arduino IDE

**Estado: versión corregida compilada con Arduino-ESP32 3.3.3, cargada por el usuario
y validada físicamente el 2026-10-24.** Reset, versión local y funciones LE respondieron
correctamente; se recibieron 3 eventos de anuncios BLE en 10 segundos. La versión
anterior cargó pero no respondió a Reset. Véase `../docs/validacion.md`.
Se corrigió el inicio mediante `btStart()` para enlazar el HAL Bluetooth y evitar
que `initArduino()` libere su memoria antes de `setup()`.
El firmware ESP-IDF del directorio `firmware/` sí compiló; su carga se interrumpió.

1. Instalar el paquete **esp32 by Espressif Systems** (familia 3.x) en el gestor
   de placas. El sketch usa VHCI del ESP32 original; no seleccionar S2/S3/C3.
2. Abrir `Esp32HciBridge/Esp32HciBridgev2/Esp32HciBridgev2.ino` (ruta renombrada por el usuario).
3. Elegir **ESP32 Dev Module**, puerto **COM3**, velocidad de carga **115200**,
   **Core Debug Level: None**. Compilar primero.
4. Pulsar Subir. Si no conecta: mantener BOOT, pulsar y soltar EN, mantener BOOT
   hasta que la herramienta conecte y soltarlo. No pulsar EN durante la escritura.
5. Cerrar el monitor serie. El programa intercambia datos binarios HCI, no texto.
6. Desde la raíz del repositorio:

```powershell
.\.venv\Scripts\python.exe tools/diagnose.py --port COM3
.\.venv\Scripts\python.exe tools/diagnose.py --port COM3 --scan-seconds 10
```

Esta variante usa UART0 mediante `Serial` y callbacks VHCI, porque Arduino ya
incluye una configuración del controlador. La variante ESP-IDF usa H4 directamente
en UART1: no son el mismo binario. No usar BluetoothSerial, BLEDevice o NimBLE
simultáneamente con este sketch.

El buffer del callback es limitado y la transferencia no tiene RTS/CTS. Ante
desbordamiento, tipo de paquete inválido o paquete incompleto el puente se detiene;
el PC obtiene timeout. Reiniciar la placa para recuperar y reducir tráfico.
No apto para audio, ni certificado para tráfico ACL sostenido. No sustituye el
driver Windows pendiente ni habilita passkeys por sí mismo.

Si la carga falla con cortes de paquetes incluso a 115200, probar otro cable USB
de datos corto y un puerto directo del PC, sin hub. El cargador ROM del ESP32
permite reintentar la programación aunque el bootloader de flash esté incompleto.

Referencias oficiales:
- https://docs.espressif.com/projects/arduino-esp32/en/latest/installing.html
- https://docs.espressif.com/projects/esptool/en/latest/esp32/troubleshooting.html
- https://docs.espressif.com/projects/esp-idf/en/v5.5.1/esp32/api-reference/bluetooth/controller_vhci.html
