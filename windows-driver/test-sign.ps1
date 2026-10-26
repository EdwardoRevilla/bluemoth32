param(
    [string]$InputPackage = (Join-Path $PSScriptRoot 'package'),
    [string]$OutputPackage = (Join-Path $PSScriptRoot 'out\test-signed'),
    [ValidatePattern('^[A-Za-z0-9_,]+$')][string]$CatalogOs = '10_GE_X64',
    [ValidatePattern('^$|^[A-Fa-f0-9]{40}$')][string]$CertificateThumbprint = ''
)
# Preparation only: never enable TESTSIGNING, trust a root, install a driver,
# change Secure Boot/HVCI, export a private key, or reboot the machine.
$ErrorActionPreference = 'Stop'
$taskInput = (Resolve-Path -LiteralPath $InputPackage).Path
$taskOutput = [IO.Path]::GetFullPath($OutputPackage)
if ($taskInput.TrimEnd('\') -eq $taskOutput.TrimEnd('\')) {
    throw 'Use a separate output directory to preserve the unsigned package.'
}
if (Test-Path -LiteralPath $taskOutput) {
    throw 'Output directory already exists. Choose a new directory to preserve existing artifacts.'
}
foreach ($taskFile in @('Esp32HciBus.sys','Esp32HciBus.inf')) {
    if (-not (Test-Path -LiteralPath (Join-Path $taskInput $taskFile))) {
        throw "Required input is missing: $taskFile"
    }
}
if (Select-String -LiteralPath (Join-Path $taskInput 'Esp32HciBus.inf') -SimpleMatch '@SERIAL_DEVICE_PATH@' -Quiet) {
    throw 'Prepare a device-specific package first.'
}
$taskSignTool = Get-Command signtool.exe -ErrorAction SilentlyContinue
if ($taskSignTool) {
    $taskSignExe = $taskSignTool.Source
} else {
    $taskKits = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10'
    $taskSignFile = Get-ChildItem -Path (Join-Path $taskKits 'bin\10.*\x64\signtool.exe') -File -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending | Select-Object -First 1
    if (-not $taskSignFile) { throw 'SignTool is missing. Install the Windows SDK/WDK signing tools.' }
    $taskSignExe = $taskSignFile.FullName
}
if ($CertificateThumbprint) {
    $taskCert = Get-Item -LiteralPath "Cert:\CurrentUser\My\$CertificateThumbprint"
    if (-not $taskCert.HasPrivateKey -or $taskCert.NotAfter -le (Get-Date)) {
        throw 'The selected certificate has no private key or has expired.'
    }
} else {
    if (-not (Get-Command New-SelfSignedCertificate -ErrorAction SilentlyContinue)) {
        throw 'Run this script in Windows PowerShell with New-SelfSignedCertificate available.'
    }
    $taskCert = New-SelfSignedCertificate -Type CodeSigningCert -Subject 'CN=ESP32 HCI Lab Test Only' `
        -FriendlyName 'ESP32 HCI development test certificate' -CertStoreLocation 'Cert:\CurrentUser\My' `
        -KeyAlgorithm RSA -KeyLength 3072 -HashAlgorithm SHA256 -KeyExportPolicy NonExportable `
        -NotAfter (Get-Date).AddMonths(6)
}
New-Item -ItemType Directory -Path $taskOutput | Out-Null
foreach ($taskFile in @('Esp32HciBus.sys','Esp32HciBus.inf')) {
    Copy-Item -LiteralPath (Join-Path $taskInput $taskFile) -Destination (Join-Path $taskOutput $taskFile)
}
# The binary signature changes the SYS hash: sign SYS first, then regenerate CAT.
& $taskSignExe sign /fd SHA256 /s My /sha1 $taskCert.Thumbprint (Join-Path $taskOutput 'Esp32HciBus.sys')
if ($LASTEXITCODE -ne 0) { throw 'SYS test signature failed. The output is incomplete.' }
& (Join-Path $PSScriptRoot 'validate-package.ps1') -PackagePath $taskOutput -CatalogOs $CatalogOs
$taskCatalog = Join-Path $taskOutput 'esp32hcibus.cat'
if (-not (Test-Path -LiteralPath $taskCatalog)) { throw 'Catalog generation failed.' }
& $taskSignExe sign /fd SHA256 /s My /sha1 $taskCert.Thumbprint $taskCatalog
if ($LASTEXITCODE -ne 0) { throw 'CAT test signature failed. The output is incomplete.' }
Export-Certificate -Cert $taskCert -FilePath (Join-Path $taskOutput 'Esp32HciLabTest.cer') | Out-Null
[ordered]@{
    purpose = 'Development testing only; not Microsoft-signed'
    thumbprint = $taskCert.Thumbprint
    subject = $taskCert.Subject
    expires = $taskCert.NotAfter.ToUniversalTime().ToString('o')
    sha256_sys = (Get-FileHash -LiteralPath (Join-Path $taskOutput 'Esp32HciBus.sys') -Algorithm SHA256).Hash
    sha256_cat = (Get-FileHash -LiteralPath $taskCatalog -Algorithm SHA256).Hash
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $taskOutput 'test-signing.json') -Encoding UTF8
Write-Output "Test-signed package: $taskOutput"
Write-Output "Test certificate thumbprint: $($taskCert.Thumbprint)"
Write-Output 'Only the PUBLIC certificate is exported. Keep the private key on this development PC.'
Write-Output 'No trust-store, boot configuration, driver installation, or Windows security setting was changed.'
