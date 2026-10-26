Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-InstallerManifest([string]$Bundle) {
    $manifest = Get-Content -LiteralPath (Join-Path $Bundle 'manifest.json') -Raw | ConvertFrom-Json
    if ($manifest.schema -ne 1 -or $manifest.hardwareId -cne 'ROOT\Esp32HciBus' -or
        $manifest.signing -cne 'local-test' -or $manifest.certificateThumbprint -notmatch '^[0-9A-Fa-f]{40}$' -or
        $manifest.device.instance_id -notmatch '^USB\\VID_10C4&PID_EA60\\[A-Za-z0-9_&+.-]+$' -or
        $manifest.device.kernel_path -notmatch '^\\\?\?\\usb#vid_10c4&pid_ea60#[A-Za-z0-9_&+.-]+#\{86e0d1e0-8089-11d0-9ce4-08003e301f73\}$') {
        throw 'Manifiesto incompatible o seleccion de dispositivo invalida.'
    }
    $expected = @('Esp32HciBus.inf','Esp32HciBus.sys','esp32hcibus.cat','Esp32HciLabTest.cer')
    $properties = @($manifest.files.PSObject.Properties)
    if ($properties.Count -ne $expected.Count) { throw 'Lista de archivos incompleta o inesperada.' }
    foreach ($property in $properties) {
        if ($property.Name -cnotin $expected -or $property.Value -notmatch '^[A-Fa-f0-9]{64}$') {
            throw 'Nombre o hash de archivo invalido.'
        }
        $path = Join-Path (Join-Path $Bundle 'package') $property.Name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
            (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $property.Value) {
            throw "Archivo ausente o alterado: $($property.Name)"
        }
    }
    $text = Get-Content -LiteralPath (Join-Path $Bundle 'package\Esp32HciBus.inf') -Raw
    $matches = [regex]::Matches($text, '(?im)^HKR,Parameters,SerialDevicePath,0x00000000,"([^"\r\n]+)"\s*$')
    if ($matches.Count -ne 1 -or $matches[0].Groups[1].Value -ine $manifest.device.kernel_path) {
        throw 'El INF no corresponde a la interfaz seleccionada.'
    }
    $interfaceInstance = ($manifest.device.kernel_path -split '#')[2]
    if (($manifest.device.instance_id -split '\\')[-1] -ine $interfaceInstance) {
        throw 'La instancia USB no coincide con la interfaz.'
    }
    return $manifest
}

function Assert-InstallerSignatures([string]$Bundle, $Manifest, [switch]$RequireTrusted) {
    $cert = New-Object Security.Cryptography.X509Certificates.X509Certificate2(
        (Join-Path $Bundle 'package\Esp32HciLabTest.cer'))
    if ($cert.Thumbprint -ne $Manifest.certificateThumbprint -or $cert.HasPrivateKey -or
        $cert.NotBefore -gt (Get-Date) -or $cert.NotAfter -le (Get-Date)) {
        throw 'Certificado distinto, caducado, aun no vigente o con clave privada.'
    }
    foreach ($file in @('Esp32HciBus.sys','esp32hcibus.cat')) {
        $signature = Get-AuthenticodeSignature -LiteralPath (Join-Path $Bundle "package\$file")
        if (-not $signature.SignerCertificate -or $signature.SignerCertificate.Thumbprint -ne $cert.Thumbprint -or
            $signature.Status -notin @('Valid','NotTrusted','UnknownError')) {
            throw "Firma ausente o incorrecta: $file ($($signature.Status))"
        }
        if ($RequireTrusted -and $signature.Status -ne 'Valid') {
            throw "Windows aun no confia en la firma de $file. Usa primero la opcion de certificado de pruebas."
        }
    }
    return $cert
}

function Select-InstallerDevice($Manifest, [object[]]$Devices) {
    $selected = @($Devices | Where-Object {
        $_.InstanceId -ieq $Manifest.device.instance_id -and
        $_.InterfacePath -and ('\??\' + $_.InterfacePath.Substring(4)) -ieq $Manifest.device.kernel_path
    })
    if ($selected.Count -ne 1) {
        throw 'El ESP32 seleccionado no esta conectado o su interfaz cambio. Conectalo o prepara otro paquete; no se elegira otro COM.'
    }
    return $selected[0]
}

function Assert-InstallerRootOwnership([object[]]$Roots, $State) {
    if ($Roots.Count -gt 1) { throw 'Hay varias instancias ESP32. Resolver duplicados antes de instalar.' }
    foreach ($root in $Roots) {
        if (-not $State -or -not $State.rootId -or $root.InstanceId -ine $State.rootId -or
            @($root.HardwareIds) -inotcontains 'ROOT\Esp32HciBus') {
            throw 'Existe una instancia ESP32 que este instalador no creo. Se conserva; revisar antes de continuar.'
        }
    }
}

function Assert-InstallerOemInf([string]$Name, [string]$ExpectedHash) {
    if ($Name -notmatch '^oem[0-9]+\.inf$' -or $ExpectedHash -notmatch '^[0-9A-Fa-f]{64}$') {
        throw 'Referencia al paquete instalado invalida.'
    }
    $path = Join-Path $env:windir "INF\$Name"
    if (-not (Test-Path -LiteralPath $path)) { return $false }
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $ExpectedHash) {
        throw 'El INF instalado cambio. No se eliminara un paquete distinto.'
    }
    return $true
}

Export-ModuleMember -Function Read-InstallerManifest, Assert-InstallerSignatures, Select-InstallerDevice, Assert-InstallerRootOwnership, Assert-InstallerOemInf
