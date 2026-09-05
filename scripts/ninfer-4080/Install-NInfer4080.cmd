@echo off
setlocal
title AgentPort NInfer RTX 4080 Setup
cd /d "%~dp0"
echo.
echo =============================================================
echo   AgentPort NInfer setup for RTX 4080 / 4080 SUPER 16 GB
echo =============================================================
echo.
echo This builds the sm_89 NInfer engine inside Ubuntu-24.04 WSL2
echo and downloads the Qwen3.8-27B min-Q4 NInfer artifact.
echo.
echo Expect a large download: CUDA toolkit plus about 13 GB of model
echo data. The first setup can take a while depending on your connection.
echo.
choice /C YN /N /M "Continue with NInfer installation? [Y/N] "
if errorlevel 2 exit /b 0
echo.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-NInfer4080.ps1" -Mode BuildAndDownload
if errorlevel 1 (
  echo.
  echo NInfer installation failed. Read the error above.
  echo If Ubuntu-24.04 is missing, run: wsl --install -d Ubuntu-24.04
  echo Then reboot if Windows asks you to and run this installer again.
  echo.
  pause
  exit /b 1
)
echo.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Set-AgentPortBackend.ps1" -Backend Auto
if errorlevel 1 (
  echo NInfer installed, but AgentPort backend preference could not be set automatically.
  echo The benchmark can still launch NInfer directly.
)
echo.
echo NInfer setup complete.
echo The RTX 4080 AgentPort build will now use NInfer automatically for
echo Qwen3.8-27B-Ridge-3.7bpw when the backend is healthy, with TextGen fallback.
echo.
pause
exit /b 0
