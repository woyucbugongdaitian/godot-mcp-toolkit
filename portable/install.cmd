@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" -ProjectPath "%~1" -GodotPath "%~2"
if errorlevel 1 pause
