# BlueMoth32 / Esp32HciBus: prototipo de driver Windows

Código KMDF/BTHX implementado sobre el ejemplo Microsoft, con selección explícita
CP210x, configuración serie, handshake HCI y límites de transporte.

**Compilado el 2026-10-25, todavia sin carga:** Build Tools 2022 y WDK
instalados; build x64 Debug con cero errores/advertencias. El test C nativo pasó,
y el paquete de COM3 pasó InfVerif e Inf2Cat (10_GE_X64). Hay 13 tests Python aprobados.
Una copia del SYS y su catalogo ya tienen firma local de pruebas dentro del ZIP
del instalador. No se agrego confianza, activo TESTSIGNING ni instalo el driver.
El instalador tiene 18 tests de integridad/seleccion/retirada aprobados; su
diagnostico real se ejecuto en Windows PowerShell 5.1 sin cambios al sistema.

Consulta [arquitectura, compilación, paquete y validación pendiente](DRIVER.md).
Consulta [cómo probarlo con firma local en un Windows de laboratorio](TESTING.md).
Consulta [el instalador con diagnostico, confirmaciones y retirada](installer/LEEME.md).
Se prepara con `build-installer.ps1`: el destino usa herramientas incluidas en Windows,
sin Python ni WDK. El ZIP es especifico de la interfaz CP210x seleccionada.
Crear el paquete no instala el driver ni activa el modo de pruebas.
Consulta [procedencia y licencias](THIRD_PARTY.md).
