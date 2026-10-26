# Esp32HciBus — prototipo KMDF/BTHX

**El `.sys` x64 Debug compilo el 2026-10-25; sigue sin prueba kernel.**
La copia original permanece sin firma. Una copia para el [instalador de pruebas](installer/LEEME.md)
ya tiene SYS/CAT firmados con certificado local; no se instalo ni se configuro confianza/arranque.
El puente Arduino ya pasó HCI y escaneo BLE. Esta etapa implementa el transporte
kernel que falta para presentar el controlador a la pila Bluetooth de Windows.

## Arquitectura

```text
WebAuthn / APIs Bluetooth Windows -> Bthport/Bthmini
    -> hijo PDO compatible MS_BTHX_BTHMINI
    -> Esp32HciBus.sys (bus KMDF ROOT\Esp32HciBus, IOCTL_BTHX_*, H4)
    -> interfaz COM CP210x seleccionada -> driver Silicon Labs -> USB-UART -> ESP32
```

El bus raíz se instala como dispositivo independiente de clase System. El driver
Silicon Labs permanece. La selección usa la interfaz exacta del dispositivo: no el
primer COM ni todos los CP210x. Admite una instancia raíz por PC y un ESP32 seleccionado.
La apertura es exclusiva; Arduino y Python deberán
liberar ese puerto durante las pruebas kernel.

Base: ejemplo Microsoft serialhcibus, commit
`d5569c08aa2818c6240744bb47a00f67f20fdb54`. Se conserva su contrato BTHX,
enumeración PDO, reensamblado H4 y coordinación de cancelación de escrituras.
Véase [procedencia](THIRD_PARTY.md).

## Implementación

- `src/port.c`: lee `SerialDevicePath` de `Services/Esp32HciBus/Parameters`, exige una interfaz
  presente de `GUID_DEVINTERFACE_COMPORT` y prefijo USB VID_10C4 PID_EA60.
- Configura 115200, 8N1, sin control de flujo. Al abrir por primera vez espera dos
  segundos, purga texto de arranque y exige una respuesta HCI Reset con status 0
  antes de publicar el hijo Bluetooth. Los eventos posteriores provienen del ESP32.
- Configura el puerto al regresar a D0, arrancando antes su I/O target. No purga
  una sesión HCI al reanudar ni intenta un reset físico inexistente.
- Registra query-remove, remove-complete y remove-canceled. Detiene el dispositivo
  ante extracción o cancelación de extracción; no reabre otro puerto automáticamente.
- Valida tamaños y longitud interna de comandos, eventos y ACL antes de acceder
  a los parámetros; comprueba límites de entrada BTHX y escrituras serie completas.
- Limita cada caché entrante a 64 paquetes y falla ante pérdida de framing/caché
  agotada. Evita resincronización arbitraria y memoria no paginada ilimitada.
- Desactiva idle S0 y wake. Conserva `ScoSupportHCIBypass` y `MaxScoChannels=1`
  porque los exige BTHX; **no implementa una ruta de audio SCO**.

## Seleccionar el ESP32

Desde la raíz del repositorio:

```powershell
.\.venv\Scripts\python.exe windows-driver/tools/serial_device.py
.\.venv\Scripts\python.exe windows-driver/tools/serial_device.py --port COM3 --instance 'USB\VID_10C4&PID_EA60\0001' --output windows-driver/device.local.json
.\.venv\Scripts\python.exe -m unittest discover -s windows-driver/tests -p 'test_*.py' -v
```

La herramienta inventaría SetupAPI en modo de lectura: no abre COM ni modifica
registro o hardware. El manifiesto local contiene la ruta exacta del dispositivo.
Si cambia el dispositivo, volver a seleccionarlo y generar un paquete específico.

## Compilar

Se requieren MSVC, MSBuild, SDK y WDK compatibles. Microsoft documenta el kit
26100.6584 para VS 2022 y versiones posteriores para VS 2026: comprobar su
[tabla de compatibilidad](https://learn.microsoft.com/en-us/windows-hardware/drivers/download-the-wdk).
También sirve una consola EWDK oficial que incluya las herramientas.

El reintento autorizado del 2026-10-25 instaló Build Tools 2022 17.14.42,
MSVC 14.44.35207, SDK 10.0.26100.0 y WDK 26100.6584. Se añadieron los componentes
`Component.Microsoft.Windows.DriverKit.BuildTools` y
`Microsoft.VisualStudio.Component.VC.Runtimes.x86.x64.Spectre` para completar la
integración. Todos los instaladores terminaron con código 0.

Desde una consola x64 Native Tools/EWDK:

```powershell
.\windows-driver\build.ps1 -Configuration Debug -NativeTests
```

Proyecto: `src/WDK/Esp32HciBus.vcxproj`, x64, KMDF 1.15, Desktop. `-SdkVersion`
permite elegir la versión instalada del kit. El INF restringe la instalación a
Windows 10 build 19041 o posterior: **no implica compatibilidad ya probada**.
Se generan binarios sin firma en `out/x64/Debug`. El test C comprueba el mismo
validador que usa el driver; compiló con /W4 /WX y pasó en este entorno.
El build kernel Debug también terminó con 0 errores y 0 advertencias.

## Paquete específico del dispositivo

Después de una compilación correcta:

```powershell
.\.venv\Scripts\python.exe windows-driver/tools/prepare_package.py --device windows-driver/device.local.json --sys windows-driver/out/x64/Debug/Esp32HciBus.sys --output windows-driver/package
.\windows-driver\validate-package.ps1 -PackagePath windows-driver/package
# Catálogo para el identificador comprobado con Inf2Cat de este kit:
.\windows-driver\validate-package.ps1 -PackagePath windows-driver/package -CatalogOs 10_GE_X64
```

El generador exige un `.sys` real y sustituye el marcador de ruta del INF. No
crea catálogos ficticios; elimina un catálogo anterior en el directorio de salida
porque cambiar el INF invalida su firma. Después de validar el INF, ejecutar
Inf2Cat con identificadores de SO aceptados por el kit (`Inf2Cat /?`) y realizar
el proceso de firma. La plantilla `.inx` con `@SERIAL_DEVICE_PATH@` no es un
paquete listo para usar.

## Carga y reversión — pendientes

El build y la validación INF/CAT pasaron. Falta una firma aceptada por el equipo de
prueba. No se modifican Secure Boot, integridad de memoria ni políticas de firma.
La [política Microsoft](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/kernel-mode-code-signing-policy--windows-vista-and-later-)
describe los requisitos de los drivers kernel modernos.

Solamente después de esos requisitos, DevCon del WDK puede crear el devnode raíz
en la máquina de laboratorio, como administrador:

```powershell
devcon install <ruta-paquete-validado>\Esp32HciBus.inf 'ROOT\Esp32HciBus'
```

PnPUtil `/add-driver ... /install` por sí solo no crea un dispositivo raíz nuevo.
No repetir `devcon install` si ya existe: puede crear instancias duplicadas.
Registrar el instance ID creado para deshabilitar/retirar exclusivamente esa
instancia con Administrador de dispositivos o PnPUtil. Luego puede eliminarse su
paquete `oemNN.inf` específico. El controlador CP210x original permanece.

En esta versión, después de estabilizar una desconexión o cambiar firmware,
deshabilitar/habilitar la instancia raíz específica. No hay recuperación automática
del firmware ni GPIO de reset. Driver Verifier y depuración corresponden al equipo
de laboratorio. No se cargó ningún driver kernel durante este trabajo.

## Validación pendiente

1. Build Debug y test C nativo: aprobados; ampliar con análisis estático del driver.
2. InfVerif e Inf2Cat: aprobados para 10_GE_X64; falta el proceso de firma aceptado.
3. Cargar y confirmar interfaz correcta, Reset y radio sin error en Administrador
   de dispositivos. Capturar WPP: `797aa8bd-c98b-4f97-9f14-f0fb878be73e`.
4. Probar BTHX y BLE con APIs Windows: Python no valida ese recorrido kernel.
5. Probar ACL, límites, cancelación, caché llena, puerto ocupado, unplug durante
   I/O, reanudación, reinicio del ESP32 y reinstalación/reversión.
6. Con BLE nativo operativo, probar passkeys con iPhone y navegador.

Estado: selección real SetupAPI de COM3 verificada y 13 tests Python aprobados.
Compilación kernel y test C nativo aprobados; carga, radio nativo y passkeys pendientes. La comprobación
HCI adicional de esta etapa encontró COM3 ocupado; la prueba física anterior
aprobada continúa registrada por separado.
