@echo off
setlocal

set "SCRIPT=%~dp0Layout_Toolkit_RU_EN.ahk"
set "CORE=%~dp0Resolve_AutoHotkey.ps1"
set "MANAGER=%~dp0Manage_Startup.ps1"

if not exist "%MANAGER%" (
    echo Manage_Startup.ps1 was not found next to Startup_Manager.cmd.
    pause
    exit /b 1
)

:MENU
cls
echo ============================================
echo  Layout Toolkit RU-EN Startup Manager
echo ============================================
echo.
echo Script:
echo %SCRIPT%
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%MANAGER%" -Action Status -ScriptPath "%SCRIPT%"

echo.
echo 1 - Add to startup
echo 2 - Remove from startup
echo 3 - Exit
echo.

choice /c 123 /n /m "Select option: "

if errorlevel 3 exit /b 0
if errorlevel 2 goto REMOVE
if errorlevel 1 goto INSTALL


:INSTALL
cls
echo Installing startup shortcut...
echo.

if not exist "%SCRIPT%" (
    powershell -NoProfile -Command "Add-Type -AssemblyName PresentationFramework; [System.Windows.MessageBox]::Show('Layout_Toolkit_RU_EN.ahk was not found next to Startup_Manager.cmd.', 'Layout Toolkit', 'OK', 'Error')"
    pause
    goto MENU
)

if not exist "%CORE%" (
    powershell -NoProfile -Command "Add-Type -AssemblyName PresentationFramework; [System.Windows.MessageBox]::Show('Resolve_AutoHotkey.ps1 was not found next to Startup_Manager.cmd.', 'Layout Toolkit', 'OK', 'Error')"
    pause
    goto MENU
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%MANAGER%" -Action Install -ScriptPath "%SCRIPT%"
if errorlevel 2 goto MENU
if errorlevel 1 (
    powershell -NoProfile -Command "Add-Type -AssemblyName PresentationFramework; [System.Windows.MessageBox]::Show('PowerShell failed to create startup shortcut.', 'Layout Toolkit', 'OK', 'Error')"
    pause
    goto MENU
)

pause
goto MENU


:REMOVE
cls
echo Removing startup shortcut...
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%MANAGER%" -Action Remove -ScriptPath "%SCRIPT%"

pause
goto MENU
