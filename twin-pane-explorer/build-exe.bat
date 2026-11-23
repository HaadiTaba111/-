@echo off
REM ===========================================================================
REM  Twin-Pane Explorer - build TwinPane.exe on a Windows machine
REM
REM  Requirements: Python 3.9+ from python.org (with "tcl/tk and IDLE" is not
REM  needed, but "Add python.exe to PATH" is).  No other installs required -
REM  this script creates .build-venv, installs pyinstaller + windows-curses
REM  there, and drops TwinPane.exe next to this file.
REM
REM  Usage:  build-exe.bat            (build)
REM          build-exe.bat --test     (build + run the unit tests)
REM ===========================================================================
setlocal enabledelayedexpansion
cd /d "%~dp0"

echo.
echo  Twin-Pane Explorer - Windows build
echo  ----------------------------------
where python >nul 2>nul
if errorlevel 1 (
    echo  [X] Python was not found on PATH.
    echo      Install it from https://www.python.org/downloads/windows/
    echo      and tick "Add python.exe to PATH".
    exit /b 1
)
for /f "delims=" %%v in ('python -c "import sys;print(sys.version.split()[0])"') do set PYVER=%%v
echo  Python !PYVER!

if not exist .build-venv (
    echo  [1/4] Creating .build-venv ...
    python -m venv .build-venv || goto :fail
) else (
    echo  [1/4] Reusing .build-venv
)

echo  [2/4] Installing build tools ...
call .build-venv\Scripts\python.exe -m pip install --upgrade --quiet pip || goto :fail
call .build-venv\Scripts\python.exe -m pip install --quiet pyinstaller windows-curses pytest || goto :fail

if /i "%~1"=="--test" (
    echo  [3/4] Running unit tests ...
    call .build-venv\Scripts\python.exe -m pytest -q tests\test_fsops.py tests\test_archive.py tests\test_core_phase3.py
    if errorlevel 1 goto :fail
) else (
    echo  [3/4] Skipping tests (pass --test to run them)
)

echo  [4/4] Building TwinPane.exe ...
call .build-venv\Scripts\python.exe -m PyInstaller ^
    --onefile --name TwinPane --console --clean --noconfirm ^
    --add-data "twinpane;twinpane" ^
    --hidden-import curses --hidden-import curses.ascii --hidden-import curses.has_key ^
    --collect-submodules twinpane ^
    run.py || goto :fail

if not exist dist\TwinPane.exe goto :fail
copy /y TwinPane.bat dist\ >nul 2>nul
if exist README.md copy /y README.md dist\ >nul 2>nul

echo.
for %%F in (dist\TwinPane.exe) do echo  [OK] dist\%%~nxF  (%%~zF bytes)
echo.
echo  Run it with:  dist\TwinPane.exe
echo  Tip: on Windows 10/11 use Windows Terminal for proper UTF-8 box drawing
echo       and mouse support. Right-click the title bar -^> Properties to
echo       pick a font such as "Cascadia Mono".
echo.
if /i not "%~1"=="--no-pause" pause
exit /b 0

:fail
echo.
echo  [X] Build failed - see the messages above.
if /i not "%~1"=="--no-pause" pause
exit /b 1
