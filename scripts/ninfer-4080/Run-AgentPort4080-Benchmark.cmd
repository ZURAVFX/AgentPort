@echo off
setlocal
title AgentPort RTX 4080 Real-World Benchmark
cd /d "%~dp0"
echo.
echo =============================================================
echo   AgentPort RTX 4080 REAL-WORLD benchmark
echo =============================================================
echo.
echo This benchmark uses different fresh tasks plus a repetitive-agent
echo workload. It does NOT repeat one deterministic prompt, so n-gram
echo speculation cannot win simply by memorising the previous answer.
echo.
echo Text-only benchmark note: any mmproj flag is temporarily removed
echo while TextGen is tested, then your original flags are restored.
echo.

wsl.exe -d Ubuntu-24.04 -- bash -lc "test -x ~/.agentport/ninfer-src/build-sm89/apps/ninfer-serve -a -s ~/.agentport/models/qwen3_8_27b_minq4.ninfer" >nul 2>nul
if errorlevel 1 (
  echo NInfer RTX 4080 is not installed yet.
  echo NInfer is required if you want the full TextGen vs NInfer comparison.
  echo.
  choice /C YN /N /M "Install NInfer now? This is a large first-time download. [Y/N] "
  if not errorlevel 2 (
    call "%~dp0Install-NInfer4080.cmd"
    if errorlevel 1 (
      echo.
      echo Continuing with TextGen-only benchmark because NInfer setup failed.
      echo.
    )
  )
)

echo.
echo Starting benchmark. Do not use DeepSeek Harness during the run.
echo AgentPort/TextGen will be restarted several times and restored at the end.
echo.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Benchmark-AgentPortMatrix.ps1"
set EXITCODE=%ERRORLEVEL%
echo.
if not "%EXITCODE%"=="0" echo Benchmark exited with code %EXITCODE%.
echo Copy the final results table back into ChatGPT for analysis.
echo.
echo Press any key to close this window.
pause >nul
exit /b %EXITCODE%
