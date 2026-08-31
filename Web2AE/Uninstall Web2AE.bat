@echo off
set "AEDEST=%APPDATA%\Adobe\CEP\extensions\Web2AE"
if exist "%AEDEST%" rmdir /s /q "%AEDEST%"
echo Web2AE After Effects companion removed.
pause
