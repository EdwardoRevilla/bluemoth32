# Procedencia

Base: [Microsoft Windows-driver-samples, bluetooth/serialhcibus](https://github.com/microsoft/Windows-driver-samples/tree/d5569c08aa2818c6240744bb47a00f67f20fdb54/bluetooth/serialhcibus).
Revisión congelada: `d5569c08aa2818c6240744bb47a00f67f20fdb54`.
Licencia: [Microsoft Public License](LICENSE.MS-PL). Se conservan los avisos originales.

Se importaron Fdo.c, driver.c/h, io.c/Io.h, pdo.c, public.h y los archivos WDK
de compilación, tracing y personalización. Sus modificaciones permanecen bajo MS-PL.
El proyecto adaptado es Esp32HciBus: GUID de tracing propio, INF raíz por dispositivo,
puerto USB seleccionado, configuración/handshake, límites y errores de transporte,
caché limitada, validación de buffers y ausencia de reset físico/wake.

Adiciones independientes: port.c/h, hci_packet.h, herramientas, tests y scripts,
bajo [licencia MIT](LICENSE.ADDITIONS.MIT). La adaptación no implica certificación
ni soporte de Microsoft o Silicon Labs.
