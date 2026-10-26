#requires -Version 5.1
param(
    [ValidateSet('Menu','Preview','Diagnose','TrustCertificate','EnableTestMode','Install','Uninstall','RemoveTrust','DisableTestMode')]
    [string]$Action = 'Menu',
    [switch]$Interactive,
    [switch]$Json
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# CMD may inherit PowerShell 7's PSModulePath. Load inbox Windows PowerShell
# modules explicitly so hashing, signatures and certificate providers stay available.
foreach ($systemModule in @('Microsoft.PowerShell.Utility','Microsoft.PowerShell.Management','Microsoft.PowerShell.Security')) {
    Import-Module (Join-Path $PSHOME "Modules\$systemModule\$systemModule.psd1") -Global -ErrorAction Stop
}
$stateKey = 'HKLM:\SOFTWARE\Esp32HciLab'
Import-Module (Join-Path $PSScriptRoot 'Terminal.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Installer.psm1') -Force
if ($Action -ne 'Preview' -and -not ('Esp32HciInstaller.Native' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'Native.cs') }
$previousTheme = $null

function Is-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    return (New-Object Security.Principal.WindowsPrincipal($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Read-State {
    $property = Get-ItemProperty -LiteralPath $stateKey -Name InstallerState -ErrorAction SilentlyContinue
    if ($property) {
        $value = $property.InstallerState | ConvertFrom-Json
        if ($value.schema -ne 1) { throw 'Estado guardado incompatible.' }
        return $value
    }
    return $null
}
function Write-State($Value) {
    if (-not (Is-Admin)) { throw 'Guardar el estado requiere administrador.' }
    if (-not (Test-Path -LiteralPath $stateKey)) { New-Item -Path $stateKey -Force | Out-Null }
    New-ItemProperty -LiteralPath $stateKey -Name InstallerState -PropertyType String -Value ($Value | ConvertTo-Json -Depth 8 -Compress) -Force | Out-Null
}
function Get-State($Manifest) {
    $value = Read-State
    if ($value -and ($value.devicePath -ine $Manifest.device.kernel_path -or
        $value.thumbprint -ine $Manifest.certificateThumbprint)) {
        if ($value.rootId -or $value.oemInf -or @($value.addedTrust).Count -ne 0 -or $value.testModeRequested) {
            throw 'Hay otro paquete de laboratorio registrado. Desinstalar, retirar su confianza y desactivar su modo de pruebas con su instalador antes de cambiar de paquete.'
        }
        $value = $null
    }
    if (-not $value) {
        $value = [pscustomobject]@{
            schema = 1; devicePath = $Manifest.device.kernel_path; thumbprint = $Manifest.certificateThumbprint
            rootId = ''; oemInf = ''; infHash = ''; addedTrust = @(); testModeRequested = $false
        }
    }
    return $value
}
function Confirm-Action([string]$Message, [string]$Phrase) {
    Write-Host "`n$Message" -ForegroundColor Yellow
    $answer = Read-Host "Escribe $Phrase para continuar (Enter cancela)"
    if ($answer -cne $Phrase) { throw 'Operacion cancelada; no se realizaron los cambios solicitados.' }
}
function Invoke-SystemTool([string]$File, [string[]]$Arguments) {
    & (Join-Path $env:windir "System32\$File") @Arguments | Out-Host
    $code = $LASTEXITCODE
    if ($code -notin @(0,3010)) { throw "$File termino con codigo $code. Conserva esta salida y revisa setupapi.dev.log." }
    if ($code -eq 3010) { Write-Host 'Windows solicita reinicio. El instalador no reinicia automaticamente.' -ForegroundColor Yellow }
}
function Get-Diagnosis {
    $manifest = Read-InstallerManifest $PSScriptRoot
    $cert = Assert-InstallerSignatures $PSScriptRoot $manifest
    $devices = @([Esp32HciInstaller.Native]::SerialPorts())
    $match = $null; $deviceError = $null
    try { $match = Select-InstallerDevice $manifest $devices } catch { $deviceError = $_.Exception.Message }
    $secureBoot = 'Desconocido (puede requerir administrador)'
    try {
        Import-Module (Join-Path $PSHOME 'Modules\SecureBoot\SecureBoot.psd1') -ErrorAction Stop
        $secureBoot = [string](Confirm-SecureBootUEFI -ErrorAction Stop)
    } catch { }
    $roots = @([Esp32HciInstaller.Native]::Roots())
    [pscustomobject]@{
        package = 'BlueMoth32 / Esp32HciBus experimental, firma local de pruebas'
        osBuild = [Environment]::OSVersion.Version.Build
        x64Process = [Environment]::Is64BitProcess
        architecture = $env:PROCESSOR_ARCHITECTURE
        administrator = (Is-Admin)
        testSigningActive = [Esp32HciInstaller.Native]::TestSigningActive()
        secureBoot = $secureBoot
        certificate = $cert.Thumbprint
        certificateExpires = $cert.NotAfter.ToString('o')
        trustedRoot = (Test-Path -LiteralPath "Cert:\LocalMachine\Root\$($cert.Thumbprint)")
        trustedPublisher = (Test-Path -LiteralPath "Cert:\LocalMachine\TrustedPublisher\$($cert.Thumbprint)")
        selectedDevice = $match
        deviceError = $deviceError
        cp210xDevices = $devices
        esp32Roots = $roots
        nextStep = 'Certificado -> modo de pruebas -> reinicio manual -> instalar -> comprobar Bluetooth nativo.'
    }
}
function Run-Action([string]$SelectedAction) {
    if ($SelectedAction -eq 'Diagnose') {
        $report = Get-Diagnosis
        if ($Json) { $report | ConvertTo-Json -Depth 8 } else { Show-BlueMothDiagnosis $report }
        return
    }
    if (-not (Is-Admin)) {
        # Only a specifically selected mutation requests UAC. Diagnosis never elevates.
        $arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -Action {1} -Interactive' -f $PSCommandPath, $SelectedAction
        $process = Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $arguments -Verb RunAs -Wait -PassThru
        if ($process.ExitCode -ne 0) { throw 'La operacion elevada no se completo. Revisa el mensaje de esa ventana.' }
        return
    }
    $mutex = New-Object Threading.Mutex($false, 'Global\Esp32HciLabInstaller')
    $locked = $false
    try {
        try { $locked = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $locked = $true }
        if (-not $locked) { throw 'Otra instancia del instalador esta realizando cambios.' }
        $manifest = Read-InstallerManifest $PSScriptRoot
        $state = Get-State $manifest
        switch ($SelectedAction) {
            'TrustCertificate' {
                Import-Module (Join-Path $PSHOME 'Modules\PKI\PKI.psd1') -ErrorAction Stop
                $cert = Assert-InstallerSignatures $PSScriptRoot $manifest
                Confirm-Action ("Se agregara SOLO el certificado local de este paquete a Root y TrustedPublisher del equipo. Esto amplia la confianza de Windows. Huella: " + $cert.Thumbprint) 'CONFIAR'
                foreach ($store in @('Root','TrustedPublisher')) {
                    $path = "Cert:\LocalMachine\$store\$($cert.Thumbprint)"
                    if (-not (Test-Path -LiteralPath $path)) {
                        # Persist ownership intent first, so a partially completed action is recoverable.
                        if ($state.addedTrust -notcontains $store) { $state.addedTrust = @($state.addedTrust) + $store }
                        Write-State $state
                        Import-Certificate -FilePath (Join-Path $PSScriptRoot 'package\Esp32HciLabTest.cer') -CertStoreLocation "Cert:\LocalMachine\$store" | Out-Null
                    }
                }
                $null = Assert-InstallerSignatures $PSScriptRoot $manifest -RequireTrusted
                Write-Host 'Certificado de pruebas importado. El driver aun no se instalo.'
            }
            'EnableTestMode' {
                if ([Esp32HciInstaller.Native]::TestSigningActive()) { Write-Host 'El modo de pruebas ya esta activo.'; return }
                $secureBoot = $null
                try {
                    Import-Module (Join-Path $PSHOME 'Modules\SecureBoot\SecureBoot.psd1') -ErrorAction Stop
                    $secureBoot = Confirm-SecureBootUEFI -ErrorAction Stop
                } catch { }
                if ($secureBoot -eq $true) {
                    throw 'Secure Boot esta activo y puede bloquear TESTSIGNING. Usa un Windows de laboratorio preparado. No se modificara el firmware ni BitLocker.'
                }
                Confirm-Action 'TESTSIGNING permite cargar drivers con firma de desarrollo y reduce las restricciones normales de confianza. Este prototipo puede bloquear Windows. Usa un entorno de laboratorio. Si usas BitLocker, ten disponible su clave de recuperacion. Se requiere reinicio manual; no se cambian Secure Boot ni integridad de memoria.' 'ACTIVAR PRUEBAS'
                Write-State $state
                Invoke-SystemTool 'bcdedit.exe' @('/set','{current}','testsigning','on')
                $state.testModeRequested = $true; Write-State $state
                Write-Host 'Reinicia manualmente y vuelve a abrir el instalador. Todavia no se instalo el driver.'
            }
            'Install' {
                if ($env:PROCESSOR_ARCHITECTURE -ne 'AMD64' -or -not [Environment]::Is64BitProcess -or [Environment]::OSVersion.Version.Build -lt 19041) {
                    throw 'Este paquete requiere Windows x64 AMD64 build 19041 o posterior.'
                }
                if (-not [Esp32HciInstaller.Native]::TestSigningActive()) { throw 'El modo de pruebas no esta activo en este arranque. Preparalo y reinicia antes de instalar.' }
                $null = Assert-InstallerSignatures $PSScriptRoot $manifest -RequireTrusted
                $device = Select-InstallerDevice $manifest @([Esp32HciInstaller.Native]::SerialPorts())
                $roots = @([Esp32HciInstaller.Native]::Roots())
                Assert-InstallerRootOwnership $roots $state
                if ($state.rootId -and $roots.Count -eq 0) { throw 'La instancia registrada ya no existe. Usa Desinstalar para limpiar el estado antes de reinstalar.' }
                Confirm-Action ("Se instalara y cargara Esp32HciBus.sys experimental sobre " + $device.Description + '. Cierra Arduino IDE y cualquier monitor serie. Puede producir un bloqueo o pantalla azul; su funcionamiento nativo aun no esta validado. Se conserva el controlador CP210x.') 'INSTALAR'
                $inf = Join-Path $PSScriptRoot 'package\Esp32HciBus.inf'
                if (-not $state.oemInf) {
                    $state.oemInf = [Esp32HciInstaller.Native]::StageInf($inf)
                    if ($state.oemInf -notmatch '^oem[0-9]+\.inf$') { throw 'Windows no devolvio un nombre OEM valido. No se creara una instancia.' }
                    $state.infHash = $manifest.files.'Esp32HciBus.inf'
                    Write-State $state
                } elseif (-not (Assert-InstallerOemInf $state.oemInf $state.infHash)) {
                    throw 'El paquete OEM registrado ya no existe. Usa Desinstalar para limpiar el estado antes de reinstalar.'
                }
                if ($roots.Count -eq 0) {
                    $state.rootId = [Esp32HciInstaller.Native]::CreateRoot()
                    Write-State $state
                }
                Invoke-SystemTool 'pnputil.exe' @('/add-driver',$inf,'/install')
                Start-Sleep -Seconds 3
                $roots = @([Esp32HciInstaller.Native]::Roots())
                $root = @($roots | Where-Object InstanceId -IEQ $state.rootId)
                if ($root.Count -ne 1 -or -not $root[0].Present -or $root[0].Problem -ne 0 -or $root[0].Service -ine 'Esp32HciBus' -or ($root[0].Status -band 8) -eq 0) {
                    $roots | Format-List | Out-Host
                    throw 'El paquete se proceso, pero el bus no esta iniciado sin errores. No se considera exito. Revisa Diagnostico y C:\Windows\INF\setupapi.dev.log; Desinstalar permite retirarlo.'
                }
                Write-Host 'Bus Esp32HciBus iniciado. Falta comprobar el radio Bluetooth hijo, escaneo BLE nativo y acceso con iPhone.' -ForegroundColor Green
                Write-Host 'Puedes abrir Configuracion > Bluetooth y dispositivos para continuar las pruebas.'
            }
            'Uninstall' {
                $roots = @([Esp32HciInstaller.Native]::Roots())
                Assert-InstallerRootOwnership $roots $state
                if (-not $state.rootId -and -not $state.oemInf) { Write-Host 'No hay una instalacion registrada para retirar.'; return }
                if ($state.oemInf) { $null = Assert-InstallerOemInf $state.oemInf $state.infHash }
                Confirm-Action 'Se retirara exclusivamente la instancia ESP32 y el paquete OEM registrados por este instalador. El controlador CP210x se conserva. La confianza y el modo de pruebas se restauran por separado.' 'DESINSTALAR'
                if ($roots.Count -eq 1) { Invoke-SystemTool 'pnputil.exe' @('/remove-device',$state.rootId) }
                if (@([Esp32HciInstaller.Native]::Roots()).Count -ne 0) { throw 'La instancia aun existe; no se eliminara el paquete.' }
                $state.rootId = ''; Write-State $state
                if ($state.oemInf -and (Assert-InstallerOemInf $state.oemInf $state.infHash)) {
                    Invoke-SystemTool 'pnputil.exe' @('/delete-driver',$state.oemInf)
                }
                $state.oemInf = ''; $state.infHash = ''; Write-State $state
                Write-Host 'Instancia y paquete retirados. Puedes retirar el certificado y desactivar TESTSIGNING con las opciones separadas.'
            }
            'RemoveTrust' {
                if (@([Esp32HciInstaller.Native]::Roots()).Count -ne 0 -or $state.oemInf) { throw 'Desinstala primero el driver.' }
                if (@($state.addedTrust).Count -eq 0) { Write-Host 'No hay certificados agregados por este instalador para retirar.'; return }
                Confirm-Action 'Se retirara SOLO este certificado de los almacenes donde lo agrego este instalador. Las confianzas que ya existian se conservan.' 'RETIRAR CONFIANZA'
                foreach ($store in @($state.addedTrust)) {
                    if ($store -cnotin @('Root','TrustedPublisher')) { throw 'Almacen guardado invalido.' }
                    $path = "Cert:\LocalMachine\$store\$($state.thumbprint)"
                    if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path }
                }
                $state.addedTrust = @(); Write-State $state
                Write-Host 'Confianza de pruebas retirada.'
            }
            'DisableTestMode' {
                if (@([Esp32HciInstaller.Native]::Roots()).Count -ne 0 -or $state.oemInf) { throw 'Desinstala primero el driver.' }
                Confirm-Action 'Se desactivara TESTSIGNING para el siguiente arranque. Otros drivers de desarrollo pueden dejar de cargar. Se requiere reinicio manual.' 'DESACTIVAR PRUEBAS'
                Invoke-SystemTool 'bcdedit.exe' @('/set','{current}','testsigning','off')
                $state.testModeRequested = $false; Write-State $state
                Write-Host 'Reinicia manualmente para completar la restauracion del arranque.'
            }
        }
    } finally { if ($locked) { $mutex.ReleaseMutex() }; $mutex.Dispose() }
}

try {
    if (-not $Json) { $previousTheme = Enter-BlueMothTheme }
    if ($Action -eq 'Preview') {
        Show-BlueMothHeader -Preview
        Show-BlueMothMenu
        Write-Host '  bluemoth32 > _' -ForegroundColor Green
    } elseif ($Action -eq 'Menu') {
        Show-BlueMothHeader -Administrator:(Is-Admin)
        $actions = @('Diagnose','TrustCertificate','EnableTestMode','Install','Uninstall','RemoveTrust','DisableTestMode')
        do {
            Show-BlueMothMenu
            $choice = Read-Host '  bluemoth32 >'
            if ($choice -match '^[1-7]$') {
                try { Run-Action $actions[([int]$choice)-1] } catch { Write-Host $_.Exception.Message -ForegroundColor Red }
            }
        } while ($choice -ne '0')
    } else { Run-Action $Action }
    if ($Interactive) { $null = Read-Host 'Pulsa Enter para cerrar' }
    exit 0
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    if ($Interactive) { $null = Read-Host 'Pulsa Enter para cerrar' }
    exit 1
} finally { Exit-BlueMothTheme $previousTheme }
