#!/usr/bin/env bash
#
# Сборка переносимого каталога и ZIP-архива Retro80 для Windows (запускать в оболочке MSYS2 CLANG64).
#
# В DLL gnustep-base из MSYS2 путь к конфигурации — ./GNUstep.conf относительно самой DLL,
# а пути в конфигурации, начинающиеся с ./, считаются относительно неё. Поэтому:
#
#   Retro80/
#     Retro80.exe, Resources/   эмулятор (содержимое Retro80.app)
#     LICENSE.txt               лицензия эмулятора
#     *.dll                     зависимости эмулятора и бэкенда GNUstep
#     GNUstep.conf              пути GNUstep внутри каталога
#     lib/GNUstep/              бандл бэкенда, ресурсы gnustep-base/gui, шрифты и т.п.
#
# Использование:
#   scripts/package-windows.sh [каталог сборки]     (по умолчанию build-win-release)
#

set -euo pipefail

[ "${MSYSTEM:-}" = CLANG64 ] || { echo "Запускать в оболочке MSYS2 CLANG64" >&2; exit 1; }

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUILD=${1:-$ROOT/build-win-release}
PREFIX=$MINGW_PREFIX

VERSION=$(sed -n 's/^project(Retro80 VERSION \([0-9.]*\).*/\1/p' "$ROOT/CMakeLists.txt")
NAME=Retro80-$VERSION-windows-x64
DIST=$BUILD/dist/$NAME

echo "==> Сборка ($BUILD)"
cmake -S "$ROOT" -B "$BUILD" -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build "$BUILD"

echo "==> Каталог $DIST"
rm -rf "$BUILD/dist"
mkdir -p "$DIST/lib"

cp -r "$BUILD/Retro80.app/." "$DIST/"
cp "$ROOT/LICENSE" "$DIST/LICENSE.txt"
cp -r "$PREFIX/lib/GNUstep" "$DIST/lib/"
rm -rf "$DIST/lib/GNUstep/Applications" "$DIST/lib/GNUstep/WebApplications"

# Служебные программы GNUstep (без gdnc не загружается главное меню, gpbs — буфер обмена,
# make_services строит при первом запуске кэш служб в %USERPROFILE%\GNUstep\Library\Services,
# без него не загружается Xib)
cp "$PREFIX/bin/gdnc.exe" "$PREFIX/bin/gpbs.exe" "$PREFIX/bin/gdomap.exe" "$PREFIX/bin/make_services.exe" "$DIST/"

# Настройки fontconfig (cairo): ищутся в etc/fonts рядом с DLL
mkdir -p "$DIST/etc"
cp -r "$PREFIX/etc/fonts" "$DIST/etc/"

# Конфигурация GNUstep: пути из MSYS2 переводятся в пути внутри каталога
# (относительными GNUstep считает только пути, начинающиеся с ./ или ../, но не «.»)
sed -e '/^GNUSTEP_MAKEFILES=/d' -e '/_USERS_DIR=/d' \
	-e "s|=$PREFIX/lib/GNUstep|=./lib/GNUstep|" \
	-e "s|=$PREFIX/bin|=./|" -e "s|=$PREFIX/sbin|=./|" -e "s|=$PREFIX/lib\$|=./|" \
	-e "s|=$PREFIX/include|=./include|" -e "s|=$PREFIX/share|=./share|" \
	"$PREFIX/etc/GNUstep/GNUstep.conf" > "$DIST/GNUstep.conf"

if grep -q "=$PREFIX" "$DIST/GNUstep.conf"; then
	echo "В GNUstep.conf остались пути MSYS2:" >&2
	grep "=$PREFIX" "$DIST/GNUstep.conf" >&2
	exit 1
fi

# DLL: зависимости эмулятора, служебных программ и всех DLL в lib/GNUstep (бэкенд GNUstep
# загружает сам), только из MSYS2
echo "==> DLL"
{
	for exe in "$DIST"/*.exe; do ldd "$exe"; done
	find "$DIST/lib/GNUstep" -name '*.dll' -exec ldd {} \;
} | awk -v prefix="$PREFIX/bin/" 'index($3, prefix) == 1 { print $3 }' | sort -u | while read -r dll; do
	cp "$dll" "$DIST/"
done

ls "$DIST"/*.dll | wc -l | xargs echo "DLL:"
du -sh "$DIST" | cut -f1 | xargs echo "Размер:"

echo "==> Архив"
(cd "$BUILD/dist" && cmake -E tar cf "$NAME.zip" --format=zip "$NAME")
echo "Готово: $BUILD/dist/$NAME.zip"
