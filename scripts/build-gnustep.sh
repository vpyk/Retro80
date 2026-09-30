#!/usr/bin/env bash
#
# Сборка GNUstep (libobjc2 + libdispatch + ARC) из исходников для Retro80.
#
# Раскладка gnustep в /usr/GNUstep, все библиотеки ставятся в домен SYSTEM:
# именно там их ищет CMakeLists.txt проекта.
#
# Использование:
#   scripts/build-gnustep.sh [--deps] [--prefix DIR] [--src DIR] [-j N] [компонент...]
#
# Компоненты (по умолчанию все, в этом порядке):
#   libdispatch libobjc2 make base gui back
#
# Примеры:
#   scripts/build-gnustep.sh --deps     # зависимости + полная сборка
#   scripts/build-gnustep.sh base       # пересобрать libs-base (например, после обновления ICU)
#
# Версии задаются переменными окружения, например LIBS_GUI_REF=master.
#

set -euo pipefail

LIBDISPATCH_REF=${LIBDISPATCH_REF:-swift-6.4.0-RELEASE}
LIBOBJC2_REF=${LIBOBJC2_REF:-v2.3}
TOOLS_MAKE_REF=${TOOLS_MAKE_REF:-make-2_9_3}
LIBS_BASE_REF=${LIBS_BASE_REF:-base-1_31_1}
LIBS_GUI_REF=${LIBS_GUI_REF:-gui-0_32_0}
LIBS_BACK_REF=${LIBS_BACK_REF:-back-0_32_0}

RUNTIME_ABI=gnustep-2.2

PREFIX=/usr/GNUstep
SRC="$HOME/src/gnustep"
JOBS=$(nproc)
DEPS=no
COMPONENTS=()

usage()
{
	sed -n '3,19p' "$0" | sed 's/^# \{0,1\}//'
	exit "${1:-0}"
}

while [ $# -gt 0 ]; do
	case "$1" in
		--deps)    DEPS=yes ;;
		--prefix)  PREFIX=$2; shift ;;
		--src)     SRC=$2; shift ;;
		-j)        JOBS=$2; shift ;;
		-j*)       JOBS=${1#-j} ;;
		-h|--help) usage ;;
		libdispatch|libobjc2|make|base|gui|back) COMPONENTS+=("$1") ;;
		*) echo "Неизвестный параметр: $1" >&2; usage 1 ;;
	esac
	shift
done

[ ${#COMPONENTS[@]} -eq 0 ] && COMPONENTS=(libdispatch libobjc2 make base gui back)

HEADERS="$PREFIX/System/Library/Headers"
LIBRARIES="$PREFIX/System/Library/Libraries"

export CC=clang
export CXX=clang++
export LDFLAGS="-fuse-ld=lld${LDFLAGS:+ $LDFLAGS}"
export PATH="$PREFIX/System/Tools:$PATH"

# ---------------------------------------------------------------------------------------------------------------------

step()
{
	printf '\n\033[1;32m==> %s\033[0m\n' "$*"
}

die()
{
	printf '\033[1;31mОшибка: %s\033[0m\n' "$*" >&2
	exit 1
}

as_root()
{
	if [ "$(id -u)" -eq 0 ]; then
		"$@"
	else
		sudo -E env "PATH=$PATH:/usr/sbin:/sbin" "$@"
	fi
}

distro()
{
	# shellcheck disable=SC1091
	. /etc/os-release
	case " ${ID:-} ${ID_LIKE:-} " in
		*" arch "*)   echo arch ;;
		*" debian "*|*" ubuntu "*) echo debian ;;
		*) echo unknown ;;
	esac
}

install_deps()
{
	step "Установка зависимостей"

	case "$(distro)" in
		arch)
			as_root pacman -S --needed --noconfirm \
				base-devel clang lld cmake ninja git autoconf automake libtool pkgconf \
				libffi libxml2 libxslt gnutls icu curl \
				libjpeg-turbo libpng libtiff giflib cairo \
				libx11 libxt libxft libxrandr libxcursor \
				mesa glu mesa-utils \
				alsa-lib libpulse
			;;
		debian)
			as_root apt-get update
			as_root apt-get install -y \
				clang lld cmake ninja-build git make autoconf automake libtool pkg-config \
				libffi-dev libxml2-dev libxslt1-dev libgnutls28-dev libicu-dev libcurl4-gnutls-dev \
				libjpeg-dev libpng-dev libtiff-dev libgif-dev libcairo2-dev \
				libx11-dev libxt-dev libxft-dev libxrandr-dev libxcursor-dev \
				libgl-dev libglu1-mesa-dev mesa-utils \
				libasound2-dev libpulse-dev
			;;
		*)
			die "Дистрибутив не распознан, установите зависимости вручную (см. GNUstep-plan.md)"
			;;
	esac
}

# Пакеты GNUstep из репозиториев собраны gcc со старым рантаймом и конфликтуют с этой сборкой
check_conflicts()
{
	local found=""

	case "$(distro)" in
		arch)   found=$(pacman -Qq 2>/dev/null | grep -E '^(gnustep|libobjc)' || true) ;;
		debian) found=$(dpkg-query -W -f '${db:Status-Abbrev} ${Package}\n' 2>/dev/null \
					| awk '$1 == "ii" && $2 ~ /^(gnustep|libgnustep|libobjc)/ {print $2}' || true) ;;
	esac

	[ -z "$found" ] || die "Удалите пакеты GNUstep из репозиториев дистрибутива:"$'\n'"$found"
}

check_tools()
{
	local tool

	for tool in clang clang++ ld.lld cmake git make autoconf pkg-config; do
		command -v "$tool" >/dev/null || die "Не найден $tool, запустите скрипт с --deps"
	done
}

# fetch <каталог> <url> <ref>: клонирует или переключает исходники на нужный тег/ветку
fetch()
{
	local dir="$SRC/$1" url=$2 ref=$3

	if [ -d "$dir/.git" ]; then
		git -C "$dir" fetch --quiet --depth 1 origin "$ref"
		git -C "$dir" checkout --quiet --force --detach FETCH_HEAD
		git -C "$dir" clean --quiet -fdx
	else
		git clone --quiet --depth 1 --branch "$ref" "$url" "$dir"
	fi

	git -C "$dir" submodule update --quiet --init --recursive --depth 1
}

load_gnustep_env()
{
	local sh="$PREFIX/System/Library/Makefiles/GNUstep.sh"

	[ -f "$sh" ] || die "Не найден $sh, сначала соберите компонент make"

	set +u
	# shellcheck disable=SC1090
	. "$sh"
	set -u
}

# ---------------------------------------------------------------------------------------------------------------------

build_libdispatch()
{
	step "libdispatch ($LIBDISPATCH_REF)"
	fetch libdispatch https://github.com/swiftlang/swift-corelibs-libdispatch "$LIBDISPATCH_REF"

	cmake -S "$SRC/libdispatch" -B "$SRC/libdispatch/build" -G Ninja \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_C_COMPILER=clang \
		-DCMAKE_CXX_COMPILER=clang++ \
		-DCMAKE_SKIP_RPATH=ON \
		-DCMAKE_INSTALL_PREFIX="$PREFIX" \
		-DCMAKE_INSTALL_LIBDIR="$LIBRARIES" \
		-DCMAKE_INSTALL_MANDIR="$PREFIX/System/Library/Documentation/man" \
		-DINSTALL_DISPATCH_HEADERS_DIR="$HEADERS/dispatch" \
		-DINSTALL_BLOCK_HEADERS_DIR="$HEADERS/block" \
		-DINSTALL_OS_HEADERS_DIR="$HEADERS/os" \
		-DINSTALL_PRIVATE_HEADERS=YES

	cmake --build "$SRC/libdispatch/build" -j "$JOBS"
	as_root cmake --install "$SRC/libdispatch/build"

	# Заголовки блоков берутся из libobjc2
	as_root rm -f "$HEADERS/block/Block.h" "$HEADERS/block/Block_private.h"
	as_root ldconfig
}

build_make()
{
	step "tools-make ($TOOLS_MAKE_REF)"
	fetch tools-make https://github.com/gnustep/tools-make "$TOOLS_MAKE_REF"

	(
		cd "$SRC/tools-make"
		./configure \
			--prefix="$PREFIX" \
			--with-layout=gnustep \
			--with-library-combo=ng-gnu-gnu \
			--with-runtime-abi="$RUNTIME_ABI" \
			--enable-objc-arc \
			--enable-native-objc-exceptions \
			--enable-install-ld-so-conf \
			--disable-importing-config-file
		as_root make install
	)

	as_root ldconfig
}

build_libobjc2()
{
	step "libobjc2 ($LIBOBJC2_REF)"
	fetch libobjc2 https://github.com/gnustep/libobjc2 "$LIBOBJC2_REF"

	# gnustep-config нужен libobjc2 для выбора каталогов установки
	load_gnustep_env

	cmake -S "$SRC/libobjc2" -B "$SRC/libobjc2/build" -G Ninja \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_C_COMPILER=clang \
		-DCMAKE_CXX_COMPILER=clang++ \
		-DCMAKE_ASM_COMPILER=clang \
		-DGNUSTEP_INSTALL_TYPE=SYSTEM \
		-DTESTS=OFF

	cmake --build "$SRC/libobjc2/build" -j "$JOBS"
	as_root cmake --install "$SRC/libobjc2/build"
	as_root ldconfig
}

# build_lib <каталог> <url> <ref>: libs-base, libs-gui, libs-back
build_lib()
{
	local dir=$1 url=$2 ref=$3

	step "$dir ($ref)"
	fetch "$dir" "$url" "$ref"
	load_gnustep_env

	(
		cd "$SRC/$dir"
		./configure
		make -j "$JOBS"
		as_root make GNUSTEP_INSTALLATION_DOMAIN=SYSTEM install
	)

	as_root ldconfig
}

# ---------------------------------------------------------------------------------------------------------------------

[ "$DEPS" = yes ] && install_deps

check_conflicts
check_tools
mkdir -p "$SRC"

for component in libdispatch libobjc2 make base gui back; do
	case " ${COMPONENTS[*]} " in
		*" $component "*) ;;
		*) continue ;;
	esac

	case $component in
		libdispatch)
			build_libdispatch
			;;
		libobjc2)
			# Первый проход tools-make: libobjc2 берёт из него раскладку каталогов
			[ -f "$PREFIX/System/Library/Makefiles/GNUstep.sh" ] || build_make
			build_libobjc2
			;;
		make)
			# Второй проход (или единственный): tools-make настраивается на установленный libobjc2
			build_make
			;;
		base)
			build_lib libs-base https://github.com/gnustep/libs-base "$LIBS_BASE_REF"
			;;
		gui)
			build_lib libs-gui https://github.com/gnustep/libs-gui "$LIBS_GUI_REF"
			;;
		back)
			build_lib libs-back https://github.com/gnustep/libs-back "$LIBS_BACK_REF"
			;;
	esac
done

step "Готово"
echo "GNUstep установлен в $PREFIX."
echo "Для gnustep-make в текущей оболочке: . $PREFIX/System/Library/Makefiles/GNUstep.sh"
echo "Сборка Retro80: cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Debug && cmake --build build"
