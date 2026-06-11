@echo off
title BLOZ Pool Miner
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0mine-pool-mainnet.ps1" %*
if errorlevel 1 pause
