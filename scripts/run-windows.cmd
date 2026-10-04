@echo off
rem Запуск Retro80, собранного в MSYS2 CLANG64 (каталог build-win), без оболочки MSYS2.
rem DLL GNUstep, libobjc2, cairo и др. лежат в <MSYS2>\clang64\bin, его нужно добавить в PATH.
rem Каталог MSYS2: переменная MSYS2_ROOT, иначе C:\msys64 или D:\msys64.
rem Аргументы передаются эмулятору, например файл для открытия.

setlocal

if not defined MSYS2_ROOT if exist "C:\msys64\clang64\bin" set "MSYS2_ROOT=C:\msys64"
if not defined MSYS2_ROOT if exist "D:\msys64\clang64\bin" set "MSYS2_ROOT=D:\msys64"

if not defined MSYS2_ROOT (
    echo MSYS2 not found, set MSYS2_ROOT
    pause
    exit /b 1
)

set "PATH=%MSYS2_ROOT%\clang64\bin;%PATH%"
start "" "%~dp0..\build-win\Retro80.app\Retro80.exe"  -NSMenuInterfaceStyle NSWindows95InterfaceStyle %*
