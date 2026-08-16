@echo off
:: ============================================================
:: VantaDNS — Elevated Service Setup
:: Double-click this once. Click YES on the UAC prompt.
:: A blue PowerShell window will open and complete setup.
:: ============================================================
echo Requesting Administrator privileges for VantaDNS setup...
powershell -Command "Start-Process powershell -ArgumentList '-NoProfile -ExecutionPolicy RemoteSigned -File ""%~dp0scripts\setup-services.ps1"" -RepoRoot ""%~dp0.""" -Verb RunAs -Wait"
echo.
echo Setup complete. Press any key to close.
pause > nul
