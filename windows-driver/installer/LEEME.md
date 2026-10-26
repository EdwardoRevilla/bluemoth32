# BlueMoth32 / instalador de laboratorio

Este paquete contiene un driver experimental x64 y firma local de pruebas. Compilar
y firmar no demuestra que el radio funcione en Windows. Puede provocar un bloqueo
del sistema: se recomienda un Windows de laboratorio. No es una firma Microsoft.

1. Extrae **todo el ZIP** a una carpeta local y abre `bluemoth32.cmd`.
   `Abrir-instalador.cmd` sigue disponible como acceso alternativo.
2. Elige **1 Diagnostico**. No abre COM, reinicia la placa ni cambia Windows.
3. Para probar en el equipo elegido, **2** importa el certificado publico a
   LocalMachine/Root y TrustedPublisher, previa confirmacion y UAC.
4. **3** solicita TESTSIGNING, explicando el cambio y pidiendo confirmacion.
   Secure Boot activo bloquea este paso; el instalador no cambia Secure Boot,
   BitLocker ni integridad de memoria. Si hay que preparar otro entorno, detenerse.
   Si el equipo usa BitLocker, tener disponible su clave de recuperacion antes
   de modificar el arranque. El instalador no lee ni guarda esa clave.
5. Reinicia manualmente. Abre el instalador otra vez y elige **4 Instalar**.
   Cierra Arduino IDE y los monitores serie primero. La instalacion requiere
   confirmacion explicita porque carga un driver kernel experimental.
6. Verifica el bus y el radio Bluetooth hijo en Administrador de dispositivos,
   despues un escaneo BLE nativo y finalmente el inicio de sesion con iPhone.

El driver original Silicon Labs CP210x debe seguir instalado. El paquete selecciona
una **interfaz USB exacta**, no el primer COM disponible. Un cambio de numero COM
no requiere por si solo otro paquete si la interfaz sigue siendo la misma. Si cambia
la interfaz/dispositivo, generar y firmar otro paquete; no editar el INF del ZIP.
La deteccion VID/PID identifica el puente CP210x, no demuestra que el firmware ESP32
sea el correcto. El driver exige un handshake HCI al arrancar.

El destino no necesita Python, Arduino IDE, Visual Studio, WDK ni DevGen. Usa Windows
PowerShell 5.1, .NET Framework, SetupAPI y PnPUtil incluidos en Windows. El lanzador
usa ExecutionPolicy Bypass solo para ese proceso; no cambia la politica persistente.
Las politicas de empresa/WDAC pueden impedir la ejecucion o carga.

## Retirar la prueba

- **5** retira exclusivamente la instancia y el paquete OEM registrados por este
  instalador, sin /force ni comodines. No retira el CP210x.
- **6** elimina este certificado solo de los almacenes donde el instalador lo agrego.
  Un certificado que ya existia no se considera propiedad del instalador.
- **7** desactiva TESTSIGNING despues de retirar el driver y solicita reinicio manual.
  Es una accion separada: puede afectar a otros drivers de desarrollo.

El estado para recuperar una instalacion parcial se guarda en
`HKLM\SOFTWARE\Esp32HciLab`, valor `InstallerState`. Si existe una instancia que no
creo este instalador, se conserva y se solicita revisarla. Una segunda ejecucion
reutiliza la instancia registrada; no crea duplicados ni fuerza otro driver.

## Diagnostico sin cambios

Desde CMD, en la carpeta del paquete extraido:

```cmd
bluemoth32.cmd preview
bluemoth32.cmd diagnose
bluemoth32.cmd
```

La polilla es la identidad de BlueMoth32: antenas de radio, cuerpo ESP32 y alas
como los dos extremos del puente. La vista previa no consulta hardware ni firma,
importa certificados o modifica el arranque. Los identificadores tecnicos
Esp32HciBus y el registro existente se mantienen para conservar compatibilidad.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Setup.ps1 -Action Diagnose -Json
```

La consulta muestra CP210x presentes, interfaz seleccionada, firma, confianza,
modo de pruebas **activo en este arranque**, Secure Boot (si se permite consultarlo)
y estado/codigo de problema del bus. No abre el puerto serie. Un bus iniciado aun
no confirma que BLE, el radio hijo ni las passkeys funcionen.

En caso de error, conservar la salida y revisar `C:\Windows\INF\setupapi.dev.log`
y los eventos `Microsoft-Windows-CodeIntegrity/Operational`. Si el driver provoca
un bloqueo que impida volver a abrir el instalador, usar el entorno de recuperacion,
modo seguro o la instantanea del laboratorio; la desinstalacion normal requiere
que Windows pueda arrancar.

Los hashes del manifiesto detectan alteraciones accidentales del paquete. El
manifiesto y los scripts no estan firmados por Microsoft: obtener el ZIP de una
fuente de confianza y no confundir integridad local con certificacion del driver.
