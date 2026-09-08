@echo off
setlocal
if "%~1"=="" goto usage
if "%~2"=="" goto usage
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Convert-OctopusJsonToCsv.ps1" "%~1" "%~2"
if errorlevel 1 (
    echo Conversion failed.
    exit /b 1
)
echo Conversion completed.
endlocal
goto :eof

:usage
echo Usage: Convert-OctopusJsonToCsv.bat input.json output.csv
exit /b 1
