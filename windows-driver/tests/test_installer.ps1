# Offline safety tests: no certificate, registry, boot, PnP or COM mutations.
#requires -Version 5.1
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot '..\installer\Installer.psm1') -Force
$script:passed = 0
function Check([string]$Name, [scriptblock]$Test) {
    & $Test
    $script:passed++
    Write-Output "PASS $Name"
}
function Reject([scriptblock]$Test) {
    $rejected = $false
    try { & $Test | Out-Null } catch { $rejected = $true }
    if (-not $rejected) { throw 'Expected rejection' }
}
$temp = Join-Path ([IO.Path]::GetTempPath()) ('Esp32HciInstaller-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $temp 'package') -Force | Out-Null
try {
    $device = [pscustomobject]@{
        instance_id = 'USB\VID_10C4&PID_EA60\0001'
        kernel_path = '\??\usb#vid_10c4&pid_ea60#0001#{86e0d1e0-8089-11d0-9ce4-08003e301f73}'
    }
    $files = [ordered]@{}
    foreach ($name in @('Esp32HciBus.inf','Esp32HciBus.sys','esp32hcibus.cat','Esp32HciLabTest.cer')) {
        $path = Join-Path $temp "package\$name"
        $content = 'Test fixture, never installed.'
        if ($name -eq 'Esp32HciBus.inf') { $content = 'HKR,Parameters,SerialDevicePath,0x00000000,"' + $device.kernel_path + '"' }
        [IO.File]::WriteAllText($path, $content)
        $files[$name] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    }
    $manifest = [pscustomobject]@{
        schema=1; hardwareId='ROOT\Esp32HciBus'; signing='local-test'
        certificateThumbprint=('A'*40); device=$device; files=$files
    }
    function Save-Manifest { $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $temp 'manifest.json') -Encoding UTF8 }
    Save-Manifest
    Check 'Accept matching package hashes and exact INF interface' { $null = Read-InstallerManifest $temp }
    Check 'Reject changed driver bytes' {
        $path = Join-Path $temp 'package\Esp32HciBus.sys'
        $original = [IO.File]::ReadAllBytes($path)
        [IO.File]::WriteAllText($path, 'Changed')
        Reject { Read-InstallerManifest $temp }
        [IO.File]::WriteAllBytes($path,$original)
    }
    Check 'Reject missing catalog' {
        $path = Join-Path $temp 'package\esp32hcibus.cat'; $original = [IO.File]::ReadAllBytes($path)
        [IO.File]::Delete($path); Reject { Read-InstallerManifest $temp }; [IO.File]::WriteAllBytes($path,$original)
    }
    Check 'Reject wrong CP210x instance' {
        $manifest.device.instance_id = 'USB\VID_10C4&PID_EA60\OTHER'; Save-Manifest
        Reject { Read-InstallerManifest $temp }
        $manifest.device.instance_id = 'USB\VID_10C4&PID_EA60\0001'; Save-Manifest
    }
    Check 'Reject wrong USB vendor' {
        $manifest.device.instance_id = 'USB\VID_0000&PID_EA60\0001'; Save-Manifest
        Reject { Read-InstallerManifest $temp }
        $manifest.device.instance_id = 'USB\VID_10C4&PID_EA60\0001'; Save-Manifest
    }
    Check 'Reject additional file/path traversal' {
        $manifest.files['..\other.sys'] = 'B'*64; Save-Manifest
        Reject { Read-InstallerManifest $temp }
        $manifest.files.Remove('..\other.sys'); Save-Manifest
    }
    Check 'Reject altered interface even when manifest hash updated' {
        $path = Join-Path $temp 'package\Esp32HciBus.inf'; $original = [IO.File]::ReadAllBytes($path)
        [IO.File]::WriteAllText($path, 'HKR,Parameters,SerialDevicePath,0x00000000,"\??\COM3"')
        $manifest.files['Esp32HciBus.inf'] = (Get-FileHash -LiteralPath $path).Hash; Save-Manifest
        Reject { Read-InstallerManifest $temp }
        [IO.File]::WriteAllBytes($path,$original)
        $manifest.files['Esp32HciBus.inf'] = (Get-FileHash -LiteralPath $path).Hash; Save-Manifest
    }
    $present = [pscustomobject]@{ InstanceId=$device.instance_id; InterfacePath=('\\?\' + $device.kernel_path.Substring(4)); Description='CP210x (COM19)' }
    Check 'COM renumbering keeps the exact interface selected' {
        $selected = Select-InstallerDevice $manifest @($present)
        if ($selected.Description -ne 'CP210x (COM19)') { throw 'Wrong device selected' }
    }
    Check 'Absent ESP32 never falls back to another port' { Reject { Select-InstallerDevice $manifest @() } }
    Check 'Reject ambiguous duplicate interfaces' { Reject { Select-InstallerDevice $manifest @($present,$present) } }
    Check 'Allow no root without taking another root' { Assert-InstallerRootOwnership @() $null }
    $root = [pscustomobject]@{ InstanceId='ROOT\ESP32HCIBUS\0000'; HardwareIds=@('ROOT\Esp32HciBus') }
    $state = [pscustomobject]@{ rootId=$root.InstanceId }
    Check 'Reject unowned existing root' { Reject { Assert-InstallerRootOwnership @($root) $null } }
    Check 'Reuse exactly the recorded root' { Assert-InstallerRootOwnership @($root) $state }
    Check 'Reject duplicate roots even if one belongs to setup' { Reject { Assert-InstallerRootOwnership @($root,$root) $state } }
    Check 'Reject changed hardware ID before removal' {
        $wrong = [pscustomobject]@{ InstanceId=$root.InstanceId; HardwareIds=@('USB\VID_10C4&PID_EA60') }
        Reject { Assert-InstallerRootOwnership @($wrong) $state }
    }
    Check 'Reject broad or injected OEM removal target' { Reject { Assert-InstallerOemInf '..\cp210x.inf' ('A'*64) } }
    Check 'Reject arbitrary service INF removal' { Reject { Assert-InstallerOemInf 'silabser.inf' ('A'*64) } }
    Check 'Parse installer and builder in Windows PowerShell' {
        foreach ($relative in @('..\installer\Setup.ps1','..\installer\Installer.psm1','..\installer\Terminal.psm1','..\build-installer.ps1')) {
            $tokens=$null; $errors=$null
            [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $relative),[ref]$tokens,[ref]$errors) | Out-Null
            if (@($errors).Count -gt 0) { throw ($errors | Out-String) }
        }
    }
    Write-Output "Installer safety tests: $script:passed passed. No system settings were changed."
} finally {
    # Verify the exact absolute test directory before recursive deletion.
    $resolved = [IO.Path]::GetFullPath($temp)
    $parent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not $resolved.StartsWith($parent,[StringComparison]::OrdinalIgnoreCase) -or
        [IO.Path]::GetFileName($resolved) -notmatch '^Esp32HciInstaller-test-[0-9a-f]{32}$') { throw 'Unsafe test cleanup path' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
