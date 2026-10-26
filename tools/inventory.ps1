$ErrorActionPreference = 'Stop'
Get-CimInstance Win32_OperatingSystem | Select-Object Caption, Version, OSArchitecture
Get-PnpDevice -PresentOnly | Where-Object { $_.Class -in @('Ports', 'Bluetooth') } |
    Select-Object Status, Class, FriendlyName, InstanceId
Get-Command idf.py, cmake, git, python -ErrorAction SilentlyContinue |
    Select-Object Name, Source
