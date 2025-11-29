@echo off
REM rebuild_complete_infrastructure_windows.bat
REM Script batch pour lancer le rebuild complet depuis Windows

cd /d "%~dp0\..\.."
powershell.exe -ExecutionPolicy Bypass -File "Infra\scripts\rebuild_complete_infrastructure_windows.ps1"

pause


