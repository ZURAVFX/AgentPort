@echo off
setlocal EnableExtensions
set "AEDEST=%APPDATA%\Adobe\CEP\extensions\Web2AE"
set "OLD_AEDEST=%APPDATA%\Adobe\CEP\extensions\Screenshot2AE"
set "APPROOT=%LOCALAPPDATA%\Web2AE"
set "BROWSERDEST=%APPROOT%\Browser Extension"

echo.
echo Web2AE Companion v1.0.0
echo Created by Elliot Mckenzie / zura
echo Free and open source
echo.

echo Installing After Effects extension...
for %%V in (11 12 13 14 15) do reg add "HKCU\Software\Adobe\CSXS.%%V" /v PlayerDebugMode /t REG_SZ /d 1 /f >nul 2>&1
if exist "%OLD_AEDEST%" rmdir /s /q "%OLD_AEDEST%"
if exist "%AEDEST%" rmdir /s /q "%AEDEST%"
mkdir "%AEDEST%" >nul 2>&1
xcopy "%~dp0after-effects\*" "%AEDEST%\" /E /I /Y >nul
if errorlevel 1 goto :fail

echo.
echo After Effects companion installed.
echo Restart After Effects and open Window ^> Extensions ^> Web2AE.
echo Install the Web2AE browser extension separately from Chrome Web Store or Firefox Add-ons.
echo.
echo Installation complete.
echo.
echo IMPORTANT: If Web2AE is already loaded in Chrome/Edge, open chrome://extensions and click Reload on Web2AE.
echo Firefox temporary add-ons must be reloaded from about:debugging.
echo.
pause
exit /b 0

:fail
echo.
echo ERROR: Installation failed while copying files.
echo.
echo IMPORTANT: If Web2AE is already loaded in Chrome/Edge, open chrome://extensions and click Reload on Web2AE.
echo Firefox temporary add-ons must be reloaded from about:debugging.
echo.
pause
exit /b 1
