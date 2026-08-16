@echo off
:: ============================================================
:: VantaDNS — Install Launcher
:: Double-click this to run the full installer as Administrator
:: ============================================================
echo VantaDNS Installer — requesting Administrator privileges...
powershell -Command "Start-Process powershell -ArgumentList '-NoProfile -ExecutionPolicy RemoteSigned -File \"%~dp0scripts\install.ps1\"' -Verb RunAs -Wait"
echo.
echo If the installer window closed, check the result in the powershell window.
pause
