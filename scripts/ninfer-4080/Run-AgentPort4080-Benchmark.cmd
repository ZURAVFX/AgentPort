@echo off
setlocal
title AgentPort RTX 4080 Benchmark
cd /d "%~dp0"
echo.
echo AgentPort RTX 4080 benchmark matrix
echo This will temporarily restart the local TextGen backend several times.
echo Your original TextGen flags are restored when the benchmark finishes.
echo.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Benchmark-AgentPortMatrix.ps1"
set EXITCODE=%ERRORLEVEL%
echo.
if not "%EXITCODE%"=="0" echo Benchmark exited with code %EXITCODE%.
echo Press any key to close this window.
pause >nul
exit /b %EXITCODE%
