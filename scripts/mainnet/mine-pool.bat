@echo off

title BLOZ Pool Mining (BlockZero)

cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0mine-mainnet.ps1" -Pool %*

if errorlevel 1 pause
