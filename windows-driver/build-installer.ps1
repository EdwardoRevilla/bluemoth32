param(
    [string]$InputPackage = (Join-Path $PSScriptRoot 'package'),
    [string]$DeviceManifest = (Join-Path $PSScriptRoot 'device.local.json'),
    [string]$OutputDirectory = (Join-Path $PSScriptRoot ('out\BlueMoth32-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))),
    [string]$CertificateThumbprint = ''
)
$ErrorActionPreference = 'Stop'
$output = [IO.Path]::GetFullPath($OutputDirectory)
if ((Test-Path -LiteralPath $output) -or (Test-Path -LiteralPath ($output + '.zip'))) { throw 'La salida ya existe; elige otra carpeta.' }
$device = Get-Content -LiteralPath $DeviceManifest -Raw | ConvertFrom-Json
if ($device.schema -ne 1 -or $device.baud -ne 115200) { throw 'Seleccion de dispositivo incompatible.' }
New-Item -ItemType Directory -Path $output | Out-Null
& (Join-Path $PSScriptRoot 'test-sign.ps1') -InputPackage $InputPackage -OutputPackage (Join-Path $output 'package') -CertificateThumbprint $CertificateThumbprint
foreach ($file in @('Setup.ps1','Installer.psm1','Terminal.psm1','Native.cs','Abrir-instalador.cmd','bluemoth32.cmd','LEEME.md')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot "installer\$file") -Destination $output
}
$signing = Get-Content -LiteralPath (Join-Path $output 'package\test-signing.json') -Raw | ConvertFrom-Json
$hashes = [ordered]@{}
foreach ($file in @('Esp32HciBus.inf','Esp32HciBus.sys','esp32hcibus.cat','Esp32HciLabTest.cer')) {
    $hashes[$file] = (Get-FileHash -LiteralPath (Join-Path $output "package\$file") -Algorithm SHA256).Hash
}
[ordered]@{
    schema = 1; hardwareId = 'ROOT\Esp32HciBus'; signing = 'local-test'
    certificateThumbprint = $signing.thumbprint; device = $device; files = $hashes
} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $output 'manifest.json') -Encoding UTF8
foreach ($license in @('LICENSE.MS-PL','LICENSE.ADDITIONS.MIT','THIRD_PARTY.md')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $license) -Destination $output
}
Import-Module (Join-Path $output 'Installer.psm1') -Force
$manifest = Read-InstallerManifest $output
$null = Assert-InstallerSignatures $output $manifest
Compress-Archive -Path (Join-Path $output '*') -DestinationPath ($output + '.zip')
Write-Output "Instalador preparado: $output.zip"
Write-Output 'Se creo/utilizo un certificado en CurrentUser/My para firmar la copia. No se importo confianza ni se modifico el arranque; no se instalo ningun driver.'
