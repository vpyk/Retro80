@echo off
rem Сборка переносимого ZIP-архива Retro80 (scripts/package-windows.sh) без оболочки MSYS2.
rem Каталог MSYS2: переменная MSYS2_ROOT, иначе C:\msys64 или D:\msys64.
rem Аргументы передаются скрипту (каталог сборки). NOPAUSE=1 — не ждать нажатия клавиши в конце.

setlocal

if not defined MSYS2_ROOT if exist "C:\msys64\usr\bin\bash.exe" set "MSYS2_ROOT=C:\msys64"
if not defined MSYS2_ROOT if exist "D:\msys64\usr\bin\bash.exe" set "MSYS2_ROOT=D:\msys64"

if not defined MSYS2_ROOT (
	echo MSYS2 not found, set MSYS2_ROOT
	if not defined NOPAUSE pause
	exit /b 1
)

rem bash ожидает путь к скрипту с прямыми косыми чертами
set "SCRIPT=%~dp0package-windows.sh"
set "SCRIPT=%SCRIPT:\=/%"

set MSYSTEM=CLANG64
set CHERE_INVOKING=1
"%MSYS2_ROOT%\usr\bin\bash.exe" -l "%SCRIPT%" %*
set RESULT=%ERRORLEVEL%

if not defined NOPAUSE pause
exit /b %RESULT%
