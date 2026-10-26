param(
    [ValidateSet('Debug','Release')][string]$Configuration = 'Debug',
    [string]$SdkVersion = '',
    [switch]$NativeTests
)
$ErrorActionPreference = 'Stop'
$taskMSBuild = Get-Command MSBuild.exe -ErrorAction SilentlyContinue
if (-not $taskMSBuild) {
    $taskVswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path -LiteralPath $taskVswhere) {
        $taskPath = & $taskVswhere -latest -products '*' -requires Microsoft.Component.MSBuild -find 'MSBuild\**\Bin\MSBuild.exe' | Select-Object -First 1
        if ($taskPath) { $taskMSBuild = Get-Item -LiteralPath $taskPath }
    }
}
if (-not $taskMSBuild) {
    throw 'MSBuild/MSVC are missing. Use Visual Studio C++ Build Tools and a compatible WDK/SDK, or an EWDK build console. No driver was compiled.'
}
Push-Location $PSScriptRoot
try {
    if ($NativeTests) {
        if (-not (Get-Command cl.exe -ErrorAction SilentlyContinue)) {
            throw 'Native tests require a VS x64 Native Tools / EWDK console with cl.exe.'
        }
        New-Item -ItemType Directory -Force out | Out-Null
        & cl.exe /nologo /W4 /WX tests\test_hci_packet.c /Fe:out\test_hci_packet.exe /Fo:out\test_hci_packet.obj
        if ($LASTEXITCODE -ne 0) { throw 'Native packet test compilation failed' }
        & .\out\test_hci_packet.exe
        if ($LASTEXITCODE -ne 0) { throw 'Native packet test failed' }
    }
    $taskArgs = @('src\WDK\Esp32HciBus.vcxproj','/m',"/p:Configuration=$Configuration",'/p:Platform=x64','/p:SignMode=Off','/p:EnableInf2cat=false')
    if ($SdkVersion) { $taskArgs += "/p:WindowsTargetPlatformVersion=$SdkVersion" }
    $taskBuildExe = if ($taskMSBuild.Source) { $taskMSBuild.Source } else { $taskMSBuild.FullName }
    & $taskBuildExe @taskArgs
    if ($LASTEXITCODE -ne 0) { throw 'WDK driver build failed; inspect the first compiler/INF error.' }
    Write-Output 'Driver build completed. The package is unsigned and has not been loaded.'
} finally { Pop-Location }
