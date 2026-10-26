@echo off
setlocal
set "BLUEMOTH_ACTION=Menu"
if "%~1"=="" goto action_ready
if /I "%~1"=="menu" goto action_ready
if /I "%~1"=="preview" set "BLUEMOTH_ACTION=Preview"
if /I "%~1"=="diagnose" set "BLUEMOTH_ACTION=Diagnose"
if /I "%~1"=="install" set "BLUEMOTH_ACTION=Install"
if /I "%~1"=="uninstall" set "BLUEMOTH_ACTION=Uninstall"
if "%BLUEMOTH_ACTION%"=="Menu" (
  echo Uso: bluemoth32.cmd [menu^|preview^|diagnose^|install^|uninstall]
  exit /b 2
)
:action_ready
set "BLUEMOTH_SETUP=%~dp0Setup.ps1"
if exist "%~dp0manifest.json" goto launch
set "BLUEMOTH_SETUP=%~dp0windows-driver\out\BlueMoth32\Setup.ps1"
if exist "%~dp0windows-driver\out\BlueMoth32\manifest.json" goto launch
if /I "%BLUEMOTH_ACTION%"=="Preview" (
  set "BLUEMOTH_SETUP=%~dp0windows-driver\installer\Setup.ps1"
  goto launch
)
echo BlueMoth32: falta el paquete compilado para esta interfaz USB.
echo Consulta windows-driver\installer\LEEME.md para prepararlo.
echo Un clon del codigo fuente no incluye automaticamente el driver firmado.
exit /b 2
:launch
set "BLUEMOTH_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "BLUEMOTH_PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
"%BLUEMOTH_PS%" -NoProfile -ExecutionPolicy Bypass -File "%BLUEMOTH_SETUP%" -Action %BLUEMOTH_ACTION%
exit /b %errorlevel%
