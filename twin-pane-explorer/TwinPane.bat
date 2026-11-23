@echo off
REM  Launcher for the Windows build.
REM  Put this next to TwinPane.exe (dist\) and double-click it - a plain
REM  double-click starts the app with sensible Windows defaults: UTF-8 code
REM  page, a dark-friendly theme and the phone-storage equivalent (the user
REM  profile folder) on the right.
setlocal enabledelayedexpansion
chcp 65001 >nul
cd /d "%~dp0"

set EXE=TwinPane.exe
if not exist "%EXE%" if exist dist\TwinPane.exe set EXE=dist\TwinPane.exe
if not exist "%EXE%" (
    echo  TwinPane.exe was not found.
    echo  Build it first:  build-exe.bat
    pause
    exit /b 1
)

REM  If the box-drawing characters show up as garbage, uncomment this line:
REM  set "TWINPANE_ASCII=1"

if not exist "%USERPROFILE%\Downloads" (
    start "" /wait "%EXE%" -l "%USERPROFILE%" -r "%USERPROFILE%"
) else (
    start "" /wait "%EXE%" -l "%USERPROFILE%" -r "%USERPROFILE%\Downloads"
)

REM  Keep the window open when it was double-clicked (a real terminal stays).
if "%~1"=="" pause
exit /b 0
