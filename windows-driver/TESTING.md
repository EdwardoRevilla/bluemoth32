# Prueba gratuita del driver

Estado: el binario Debug compiló, pero el driver todavía no se ha cargado ni probado
en kernel. Los pasos siguientes son un procedimiento pendiente, no resultados obtenidos.

Ya existe un [asistente de instalacion](installer/LEEME.md) que automatiza los pasos
con confirmaciones separadas. `build-installer.ps1` genera un ZIP especifico del
dispositivo con firma local. Se genero y diagnostico un paquete el 2026-10-25, sin
instalar el driver, confiar en el certificado ni cambiar el arranque.

La opción recomendada es un Windows 11 de laboratorio o una máquina virtual que
pueda recibir el USB del ESP32 por passthrough. El Windows invitado debe reconocer
el CP210x; para probar el radio, el dispositivo serie debe pertenecer al invitado.
Una instantánea permite recuperar el entorno si el driver provoca un bloqueo.

## 1. Preparar el paquete en el PC de desarrollo

Ya hay un paquete para la instancia CP210x seleccionada. Si el Windows de pruebas
enumera otra ruta de interfaz, volver a generar el manifiesto y el INF con las
herramientas de selección y empaquetado **antes de firmar**. No editar el INF después.

El script siguiente copia SYS/INF a una carpeta nueva, crea un certificado de
pruebas en CurrentUser/My, firma el SYS, regenera el catálogo y lo firma. Exporta
solamente el certificado público; su clave privada queda no exportable en el PC.

```powershell
.\windows-driver\test-sign.ps1
```

Salida por defecto: `windows-driver/out/test-signed`. El script no cambia los
almacenes de confianza, el arranque, Secure Boot ni HVCI; tampoco instala drivers.
El generador del instalador ya ejecuto este paso sobre una copia, creando un
certificado local de desarrollo y firmando SYS/CAT. Esto no habilita su carga en Windows.
Si se repite, usar otra carpeta de salida o pasar un certificado existente con
`-CertificateThumbprint`. La carpeta de salida existente se conserva.

Copiar al Windows de pruebas el directorio completo con SYS, INF, CAT, CER y el
manifiesto `test-signing.json`. No se necesita ni se debe copiar la clave privada.

## 2. Configurar solamente el Windows de pruebas

Abrir PowerShell como administrador en ese Windows. En la carpeta copiada:

```powershell
Import-Certificate -FilePath .\Esp32HciLabTest.cer -CertStoreLocation Cert:\LocalMachine\Root
Import-Certificate -FilePath .\Esp32HciLabTest.cer -CertStoreLocation Cert:\LocalMachine\TrustedPublisher
bcdedit /set testsigning on
```

Reiniciar manualmente el Windows de pruebas. Habilitar TESTSIGNING permite cargar
código kernel firmado para desarrollo y reduce las restricciones de confianza del
arranque normal; no convierte el certificado local en una firma Microsoft.

Secure Boot puede impedir activar TESTSIGNING. En ese caso, usar un entorno de
laboratorio preparado para ello; en una VM el ajuste pertenece al firmware virtual
del invitado. No es necesario modificar Secure Boot del anfitrión. Si se elige
hacer cambios en un PC físico con BitLocker, disponer primero de su clave de
recuperación. No desactivar integridad de memoria como solución automática:
Microsoft indica que con HVCI el binario debe tener firma de pruebas, por eso
se firma tanto el SYS como el catálogo.

## 3. Instalar una única instancia del driver en el laboratorio

Cerrar Arduino IDE y monitores serie en el sistema que controle el ESP32.
Comprobar primero que no exista una instancia anterior de Esp32HciBus.
Con DevGen del WDK y PnPUtil, en consola de administrador:

```powershell
devgen /add /bus ROOT /hardwareid ROOT\Esp32HciBus
pnputil /add-driver .\Esp32HciBus.inf /install
```

Guardar el instance ID creado y el nombre `oemNN.inf` asignado. No repetir DevGen
para actualizar: crearía otro dispositivo raíz. El driver original del CP210x se
conserva. La firma no asegura que el driver funcione o sea compatible con HVCI.

## 4. Verificar el resultado progresivamente

1. Administrador de dispositivos: bus ESP32 y radio Bluetooth, ambos sin error.
2. Si aparece código 10, 31, 39 o 52, registrar el código y revisar
   `%SystemRoot%/INF/setupapi.dev.log` y los eventos CodeIntegrity/Operational.
3. Capturar WPP del proveedor `797aa8bd-c98b-4f97-9f14-f0fb878be73e` y comprobar
   apertura CP210x, configuración, handshake Reset y solicitudes BTHX.
4. Descubrir BLE usando APIs o herramientas de Windows. El diagnóstico Python usa
   el COM directamente y no es una prueba del radio nativo; además compite por él.
5. Probar conexión/desconexión y cancelación. Después, probar passkeys con iPhone.
   Si se usa una VM, también debe permitir que su Windows/navegador acceda al radio
   y a Internet. El éxito del firmware por sí solo no valida ese flujo.

## 5. Revertir el entorno de pruebas

Retirar exclusivamente el instance ID y paquete anotados:

```powershell
pnputil /remove-device "<instance ID creado>"
pnputil /delete-driver oemNN.inf
bcdedit /set testsigning off
```

Eliminar solamente el certificado de pruebas, por el thumbprint exacto del
manifiesto, de LocalMachine/Root y LocalMachine/TrustedPublisher en el laboratorio.
Reiniciar y restaurar los ajustes de firmware virtual que se hayan cambiado.
La instantánea es otra opción para restaurar íntegramente una VM de pruebas.

Fuentes oficiales:
- [Carga de código firmado para pruebas](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/the-testsigning-boot-configuration-option)
- [Procedimiento de test signing](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/test-signing)
- [Creación del dispositivo raíz con DevGen y PnPUtil](https://learn.microsoft.com/en-us/windows-hardware/drivers/devtest/devcon-install)
