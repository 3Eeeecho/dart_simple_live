@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup-and-build-windows.ps1"
exit /b %ERRORLEVEL%
