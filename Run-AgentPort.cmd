@echo off
start "" powershell.exe -NoLogo -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0AgentPort-runtime-v1.7.0-4080.ps1"
