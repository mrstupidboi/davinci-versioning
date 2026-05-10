@echo off
setlocal

cd /d "%~dp0"

py -3 tools\deploy.py davinci-toggle-color-effects_v_1.lua
if errorlevel 1 (
    echo.
    echo Install failed. If Python Launcher is not installed, try:
    echo python tools\deploy.py davinci-toggle-color-effects_v_1.lua
    exit /b 1
)

echo.
echo Installed davinci-toggle-color-effects_v_1.lua.
echo Restart DaVinci Resolve if it is already open.
