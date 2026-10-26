param(
    [string]$IdfPath = "$env:USERPROFILE\esp\esp-idf-v5.5.1"
)
$ErrorActionPreference = 'Stop'
$taskPython = "$env:USERPROFILE\.espressif\python_env\idf5.5_py3.12_env\Scripts"
if (-not (Test-Path -LiteralPath "$taskPython\python.exe")) {
    throw 'Prepare ESP-IDF v5.5.1 with Python 3.12 first (see README).'
}
$taskOldPath = $env:PATH
try {
    $env:PATH = "$taskPython;$env:PATH"
    . "$IdfPath\export.ps1"
    if (-not $env:IDF_PATH) { throw 'ESP-IDF export failed' }
    Push-Location (Join-Path $PSScriptRoot '..\firmware')
    try {
        & python "$IdfPath\tools\idf.py" build
        if ($LASTEXITCODE -ne 0) { throw 'Firmware build failed' }
    } finally { Pop-Location }
} finally { $env:PATH = $taskOldPath }
