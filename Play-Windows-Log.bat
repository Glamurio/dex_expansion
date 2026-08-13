@echo off
rem ---------------------------------------------------------------------
rem  Run gen1recomp and capture its output.
rem
rem  gen1recomp.exe is a fused LOVE build, i.e. a GUI-subsystem binary, so
rem  it has no console of its own.  src/core/Logger.lua only ever calls
rem  print(), so without redirection every log line is thrown away.
rem
rem  Redirecting stdout the way this script does usually captures it anyway
rem  (Windows hands a GUI app a valid stdout handle when one is supplied).
rem  If log.txt still comes out empty, that is a LOVE build quirk and NOT a
rem  problem with the game -- use dex_expansion_report.txt instead, which
rem  the mod writes itself and needs no console at all:
rem
rem    %APPDATA%\LOVE\pokemon-love2d\dex_expansion_report.txt
rem
rem  Put this file next to gen1recomp.exe and double-click it.
rem ---------------------------------------------------------------------
setlocal enabledelayedexpansion
cd /d "%~dp0"

if not exist "gen1recomp.exe" (
  echo gen1recomp.exe not found in:
  echo   %CD%
  echo Put this script in the same folder as gen1recomp.exe.
  pause
  exit /b 1
)

set LOGFILE=log.txt
echo Writing output to "%CD%\%LOGFILE%"
echo Close the game window when you are done.
echo.

rem 2^>^&1 folds stderr in too, so a Lua error is captured alongside the log.
rem --console asks LOVE for a console; harmless on builds that ignore it.
gen1recomp.exe --console > "%LOGFILE%" 2>&1

echo.
echo Game exited.
set SIZE=0
for %%A in ("%LOGFILE%") do set SIZE=%%~zA
if "!SIZE!"=="0" (
  echo %LOGFILE% is EMPTY -- this build does not forward stdout.
  echo Use the mod's own report instead:
  echo   %APPDATA%\LOVE\pokemon-love2d\dex_expansion_report.txt
) else (
  echo Wrote %LOGFILE% ^(!SIZE! bytes^).
  echo.
  echo --- dex_expansion lines ---
  findstr /C:"dex_expansion" /C:"wild reconcile" /C:"registered" /C:"starters" /C:"assigned" /C:"retargeted" "%LOGFILE%"
)
echo.
echo The mod also always writes a full report to:
echo   %APPDATA%\LOVE\pokemon-love2d\dex_expansion_report.txt
echo.
pause
