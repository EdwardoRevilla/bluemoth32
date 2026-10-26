param(
    [Parameter(Mandatory=$true)][string]$PackagePath,
    [ValidatePattern('^[A-Za-z0-9_,]*$')][string]$CatalogOs = ''
)
$ErrorActionPreference = 'Stop'
$taskPackage = (Resolve-Path -LiteralPath $PackagePath).Path
$taskInf = Join-Path $taskPackage 'Esp32HciBus.inf'
if (-not (Test-Path -LiteralPath $taskInf)) { throw 'Esp32HciBus.inf is missing' }
if (Select-String -LiteralPath $taskInf -SimpleMatch '@SERIAL_DEVICE_PATH@' -Quiet) {
    throw 'Select a device and prepare the package before validation.'
}
function Find-WdkTool([string]$Name, [string]$RelativePattern) {
    $taskCommand = Get-Command $Name -ErrorAction SilentlyContinue
    if ($taskCommand) { return $taskCommand.Source }
    $taskKits = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10'
    $taskTool = Get-ChildItem -Path (Join-Path $taskKits $RelativePattern) -File -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending | Select-Object -First 1
    if (-not $taskTool) { throw "$Name is missing; install a compatible WDK." }
    return $taskTool.FullName
}
$taskInfVerif = Find-WdkTool 'InfVerif.exe' 'Tools\10.*\x64\infverif.exe'
& $taskInfVerif /w $taskInf
if ($LASTEXITCODE -ne 0) { throw 'INF validation failed' }
if ($CatalogOs) {
    $taskInf2Cat = Find-WdkTool 'Inf2Cat.exe' 'bin\10.*\x86\Inf2Cat.exe'
    & $taskInf2Cat "/driver:$taskPackage" "/os:$CatalogOs" /uselocaltime
    if ($LASTEXITCODE -ne 0) { throw 'Catalog generation failed' }
    Write-Output 'INF validation and unsigned catalog generation passed.'
} else {
    Write-Output 'INF validation passed. Choose -CatalogOs from the installed Inf2Cat /? list to generate a catalog.'
}
Write-Output "Package: $taskPackage"
Write-Output 'Sign the catalog only after all files are final. This script installs nothing.'
