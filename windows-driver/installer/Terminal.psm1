# BlueMoth32 identity: ASCII only, Windows PowerShell 5.1, no device access.
Set-StrictMode -Version Latest

function Get-BlueMothLogo {
    return @'
                         \       /
                          \ .-. /
                           \(o)/
           __..----.._______[===]_______..----..__
        .-'   ..---..       [   ]       ..---..   '-.
       /   .-' .---. '-.    [ESP]    .-' .---. '-.   \
      /   /   /  o  \  \   [32 ]   /  /  o  \   \   \
      \   \   \     /  /   [HCI]   \  \     /   /   /
       '._ '._ '---' .'   / [===] \   '. '---' _.' _.'
          '--..___..'  _.-' / | \ '-._  '..___..--'
                    .'  .-'  |  '-.  '.
                    '--'     V     '--'
'@
}

function Enter-BlueMothTheme {
    $previous = $null
    try {
        if (-not [Console]::IsOutputRedirected) {
            $previous = [pscustomobject]@{
                Foreground = $Host.UI.RawUI.ForegroundColor
                Background = $Host.UI.RawUI.BackgroundColor
                Title = $Host.UI.RawUI.WindowTitle
            }
            $Host.UI.RawUI.ForegroundColor = 'Green'
            $Host.UI.RawUI.BackgroundColor = 'Black'
            $Host.UI.RawUI.WindowTitle = 'BlueMoth32 | ESP32 Bluetooth lab'
            Clear-Host
        }
    } catch { }
    return $previous
}

function Exit-BlueMothTheme($Previous) {
    if ($Previous) {
        try {
            $Host.UI.RawUI.ForegroundColor = $Previous.Foreground
            $Host.UI.RawUI.BackgroundColor = $Previous.Background
            $Host.UI.RawUI.WindowTitle = $Previous.Title
        } catch { }
    }
}

function Show-BlueMothHeader([switch]$Preview, [switch]$Administrator) {
    Write-Host ''
    Write-Host '  BLUEMOTH32                                           ESP32 / HCI / WINDOWS' -ForegroundColor Green
    Write-Host ('  ' + ('-' * 73)) -ForegroundColor DarkGreen
    $logoLines = @((Get-BlueMothLogo) -split '\r?\n')
    $logoWidth = ($logoLines | Measure-Object -Property Length -Maximum).Maximum
    $inset = ' ' * [Math]::Max(0, [Math]::Floor((77 - $logoWidth) / 2))
    foreach ($line in $logoLines) { Write-Host ($inset + $line) -ForegroundColor Green }
    Write-Host ''
    $wordmark = 'B L U E M O T H 3 2'
    $tagline = 'Un puente para desplegar tus conexiones.'
    Write-Host ((' ' * [Math]::Floor((77 - $wordmark.Length) / 2)) + $wordmark) -ForegroundColor Green
    Write-Host ((' ' * [Math]::Floor((77 - $tagline.Length) / 2)) + $tagline) -ForegroundColor Gray
    Write-Host ''
    Write-Host '  USB [CP210x] ------- UART / H4 ------- [ESP32] ))) Bluetooth' -ForegroundColor DarkGreen
    Write-Host ('  ' + ('-' * 73)) -ForegroundColor DarkGreen
    $mode = if ($Administrator) { 'ADMINISTRADOR' } else { 'USUARIO' }
    if ($Preview) {
        Write-Host '  VISTA PREVIA | Sin consultas al hardware ni cambios en Windows.' -ForegroundColor Gray
    } else {
        Write-Host ("  EXPERIMENTAL | $mode | Comienza por el diagnostico.") -ForegroundColor Gray
    }
}

function Show-BlueMothMenu {
    Write-Host ''
    Write-Host '  PREPARAR E INSTALAR' -ForegroundColor Green
    Write-Host '  [1] Diagnostico              Solo lectura' -ForegroundColor Gray
    Write-Host '  [2] Confiar en certificado   Firma local de pruebas' -ForegroundColor Gray
    Write-Host '  [3] Activar modo de pruebas  Requiere reinicio manual' -ForegroundColor Gray
    Write-Host '  [4] Instalar driver          Requiere pasos anteriores' -ForegroundColor Green
    Write-Host ''
    Write-Host '  RETIRAR LA PRUEBA' -ForegroundColor DarkGreen
    Write-Host '  [5] Desinstalar driver  [6] Retirar confianza  [7] Desactivar pruebas' -ForegroundColor Gray
    Write-Host '  [0] Salir' -ForegroundColor Gray
    Write-Host ''
}

function Show-BlueMothDiagnosis($Report) {
    Write-Host ''
    Write-Host '  BLUEMOTH32 / DIAGNOSTICO' -ForegroundColor Green
    Write-Host ('  ' + ('-' * 73)) -ForegroundColor DarkGreen
    $connection = if ($Report.selectedDevice) { $Report.selectedDevice.Description } else { 'NO DETECTADO' }
    Write-Host "  ESP32          $connection" -ForegroundColor $(if ($Report.selectedDevice) {'Green'} else {'Yellow'})
    Write-Host "  WINDOWS        Build $($Report.osBuild) / $($Report.architecture)" -ForegroundColor Gray
    $testMode = if ($Report.testSigningActive) { 'ACTIVO EN ESTE ARRANQUE' } else { 'INACTIVO' }
    Write-Host "  TESTSIGNING    $testMode" -ForegroundColor Gray
    Write-Host "  SECURE BOOT    $($Report.secureBoot)" -ForegroundColor Gray
    $trust = if ($Report.trustedRoot -and $Report.trustedPublisher) { 'CONFIGURADA' } else { 'PENDIENTE' }
    Write-Host "  CONFIANZA      $trust" -ForegroundColor Gray
    Write-Host "  CERTIFICADO    $($Report.certificate)" -ForegroundColor DarkGreen
    Write-Host "  CADUCIDAD      $($Report.certificateExpires)" -ForegroundColor DarkGreen
    foreach ($root in @($Report.esp32Roots)) {
        Write-Host "  BUS ESP32      $($root.InstanceId) / problema $($root.Problem)" -ForegroundColor Gray
    }
    if (@($Report.esp32Roots).Count -eq 0) { Write-Host '  BUS ESP32      Sin instancia instalada' -ForegroundColor Gray }
    if ($Report.deviceError) { Write-Host "`n  $($Report.deviceError)" -ForegroundColor Yellow }
    Write-Host "`n  El diagnostico no abre COM ni confirma BLE nativo o passkeys." -ForegroundColor Gray
    Write-Host ''
}

Export-ModuleMember -Function Get-BlueMothLogo, Enter-BlueMothTheme, Exit-BlueMothTheme, Show-BlueMothHeader, Show-BlueMothMenu, Show-BlueMothDiagnosis
