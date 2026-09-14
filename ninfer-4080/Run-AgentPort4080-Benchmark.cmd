@echo off
setlocal
title AgentPort NInfer Benchmark
powershell.exe -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File "%~dp0Benchmark-NInfer.ps1" %*
set RESULT=%ERRORLEVEL%
pause
exit /b %RESULT%
