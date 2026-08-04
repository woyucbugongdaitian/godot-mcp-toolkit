@echo off
if not exist "%~dp0build\index.mjs" (
  echo Build output is missing. Run: npm.cmd run build
  exit /b 1
)
node "%~dp0build\index.mjs"
