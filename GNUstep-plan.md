# Доработка сборки под GNUstep: анализ и план работ

Все четыре ограничения GNUstep-сборки из README актуальны, но ни одно не упирается в GNUstep принципиально, все обходятся. Сборка под Windows возможна через официальный Windows-тулчейн GNUstep, но с одним серьёзным риском — OpenGL.

## 1. Ограничения из README

| Ограничение | Причина в коде | Можно ли обойти |
|---|---|---|
| **Нет звука и WAV** (снято на этапе 3) | `Sound.m` целиком построен на AudioToolbox (AudioQueue, AudioFile, AudioConverter). Под GNUstep вместо него заглушка `GNUstep-Sound.m`, а `WindowController.awakeFromNib` обнуляет `sound`. Эмуляция при этом тактируется таймером на 20 мс (`Computer.m:63`), а не аудиокаллбэком, как на macOS. | Да. Логика фильтра и заполнения буфера от AudioToolbox почти не зависит. Предлагается перевести звук на **miniaudio** — однофайловую C-библиотеку под публичной лицензией. Она работает через ALSA, PulseAudio, PipeWire, WASAPI и CoreAudio, умеет читать и писать WAV и пересчитывать частоту. Это решает и звук, и WAV, в том числе для Windows. |
| **Клавиатура только в режиме QWERTY** (снято на этапе 2) | Таблицы `kbdmap` во всех `*Keyboard.m` заданы в виртуальных кодах клавиш macOS (49 = пробел, 36 = Return, 123 = ←…). На X11 `NSEvent.keyCode` возвращает код X11/evdev, поэтому позиционный режим не находит клавиш. | Да. Нужна одна функция, которая переводит код клавиши платформы в код macOS, с таблицами для X11 (evdev) и Win32, и один вызов в месте обработки событий. `kbdmap` при этом остаются как есть. Какие именно коды отдаёт бэкенд win32 в libs-back, нужно проверить на практике. |
| **Меню выглядит плохо** | Логика меню построена на `menuItem.hidden`: около 30 вызовов в `validateMenuItem:`, одно общее меню, в котором для каждой машины скрываются чужие пункты. В `libs-gui` 0.32 (последний релиз) `setHidden:` отсутствует, заглушка в `GNUstep-Stub.m` ничего не делает, поэтому видны все пункты сразу. `alternate` в заголовках объявлен, но переключения по Option не ожидается. **Проверено на Manjaro:** почти везде скрытый пункт одновременно отключается (`return NO`), поэтому лишние пункты видны, но серые, выбрать их нельзя. Альтернативные пункты («Старт с F800», «Старт с 0000», «Системный ROM-диск») видны сразу и работают как обычные. Ограничение косметическое. | Да, без правки всех машин. Под GNUstep категория запоминает флаг `hidden` (associated object), а делегат меню в `menuNeedsUpdate:` пересобирает видимые пункты из шаблона. Альтернативные пункты под GNUstep показываются как обычные. |
| **Имена файлов 86RKSD только заглавными** (снято на этапе 2) | `RKSDCard.m` строит путь из имени, которое запросила эмулируемая программа, а оно всегда в верхнем регистре. На macOS файловая система нечувствительна к регистру, на Linux чувствительна. | Да, просто. Разрешать путь покомпонентно без учёта регистра: перебрать каталог и сравнить через `caseInsensitiveCompare`. На Windows (NTFS) проблемы нет вовсе. |

Попутно стоит поправить:

- `#ifdef` в перечислении каталогов (`RKSDCard.m:269–330`) полагается на то, что `enumeratorAtURL:` в GNUstep возвращает строки, а не `NSURL`. Это хрупко: после обновления libs-base может сломаться. Если использовать `contentsOfDirectoryAtPath:` и `attributesOfItemAtPath:` на обеих платформах, `#ifdef` уходят совсем.
- Ручная раскладка в `windowDidResize:` (`WindowController.m:321`, `Debug.m:118`) и заглушка `NSLayoutConstraint.setConstant:`. В libs-gui 0.29–0.31 заметно улучшили поддержку constraints, стоит проверить, нужна ли ещё ручная раскладка.
- Если категории из `GNUstep-Stub.m` когда-нибудь совпадут с настоящей реализацией в libs-gui, они молча её перекроют. Их лучше подключать только когда метода нет: `class_addMethod` вместо категории.

## 2. Сборка под Windows

**Путь:** официальный тулчейн [gnustep/tools-windows-msvc](https://github.com/gnustep/tools-windows-msvc). Это clang, ABI MSVC, libobjc2 и libdispatch; есть готовые релизы (распаковываются в `C:\GNUstep`), поддерживаются x64 и arm64. Нужны Windows 10 1903+ и clang 16+ (штатный, не из MSYS2). У MSYS2/MinGW есть свои пакеты, но clang из MSYS2 официально не поддерживается, поэтому ориентироваться лучше на MSVC-вариант.

**Риски, по убыванию:**

1. **GUI на Windows в этом тулчейне экспериментальный** (включается флагом `--with-gui`). На практике придётся обходить баги libs-gui/libs-back.
2. **OpenGL.** Под Windows `GL/gl.h` описывает только OpenGL 1.1. `GL_GLEXT_PROTOTYPES` там не работает: `glCreateShader` и прочие функции для шейдеров `tvnoise` нужно загружать через загрузчик (glad или libepoxy). Работает ли `NSOpenGLView` в бэкенде win32 и насколько надёжно, подтвердить не удалось — это надо проверить прототипом **до** основной работы. Если не заработает, запасной вариант — показывать кадр через `NSImage`/`NSBitmapImageRep` без шейдера, ценой эффекта «ТВ-шума».
3. Звук на Windows закрывается тем же miniaudio (WASAPI).
4. Клавиатура: понадобится таблица для кодов Win32.

**Альтернатива, если GNUstep GUI на Windows окажется непригодным:** оставить ядро (CPU, микросхемы, машины) на Objective-C с Foundation и сделать тонкий интерфейс на SDL. Это большая работа: ядро сейчас сильно привязано к AppKit (`Computer` наследуется от `NSResponder`, клавиатуры работают с `NSEvent`, меню проверяются через `validateMenuItem:`). Рассматривать только после провала прототипа.

## 3. Упрощение сборки

1. **Одна система сборки вместо трёх.** Сейчас каждый файл приходится добавлять в CMake, GNUmakefile и Xcode. Предлагается:
   - удалить `Retro80/GNUmakefile`, раз CMake уже умеет собирать под GNUstep;
   - Xcode-проект получать из CMake (`cmake -G Xcode`).
   - Мешает этому только `QLRetro80` — плагин Quick Look в формате `.qlgenerator`, которого нет в CMake. Такие плагины в macOS 15 больше не загружаются, так что его всё равно придётся либо выбросить, либо переписать как Quick Look extension.
2. **Искать GNUstep через `gnustep-config`**, а не по списку зашитых путей: `--objc-flags` для флагов компиляции, `--gui-libs` для библиотек.
3. **Ресурсы подключать по маске** (`file(GLOB …ROM/*)`), а не перечислять по одному.
4. **Скрипт установки зависимостей.** Сейчас это ручная сборка шести репозиториев. Варианты:
   - обёртка над [gnustep/tools-scripts](https://github.com/gnustep/tools-scripts), где `clang-build` собирает libobjc2, base, gui и back через clang;
   - Dockerfile или devcontainer с уже собранным GNUstep. Для Linux это самый короткий путь: `docker build` и `cmake`.
5. **CI на GitHub Actions** для macOS, Linux (в контейнере) и Windows (готовый релиз tools-windows-msvc). Без этого поддержка GNUstep будет незаметно ломаться.
6. **Пакеты:** AppImage для Linux; для Windows — скрипт `windows-package` из tools-scripts или CPack (ZIP/NSIS).

## 4. План работ

| Этап | Содержание | Объём |
|---|---|---|
| **0. Прототипы (снимают риски)** | a) пустой `NSOpenGLView` с шейдером под tools-windows-msvc + `--with-gui`; ~~b) пересборка меню в `menuNeedsUpdate:` под GNUstep на Linux~~ — не нужен, см. этап 4 | 1–2 дня |
| **1. Сборка** | удалить GNUmakefile; CMake через `gnustep-config`; ресурсы по маске; Dockerfile для Linux; CI для macOS и Linux | 1–2 дня |
| **2. Мелкие ограничения** | регистр имён в 86RKSD; перечисление каталогов без `#ifdef`; перевод кодов клавиш X11 и полноценный позиционный режим. **Сделано, проверено на Manjaro:** 86RKSD — загрузка, список файлов, запуск, создание и удаление файлов и каталогов с именами в любом регистре; позиционный режим клавиатуры и РУС/ЛАТ. Под GNUstep РУС/ЛАТ (Option) — правый Alt, левый Alt занят под Command; переназначается через `GSFirstAlternateKey`/`GSFirstCommandKey` | 1–2 дня |
| **3. Звук** | общий `Sound` на miniaudio: вывод, тактирование эмуляции от аудио, чтение и запись WAV. Сначала только для GNUstep, при успехе можно заменить и AudioToolbox на macOS, чтобы остался один код. **Реализовано для GNUstep (`GNUstep-Sound.m`, miniaudio 0.11.25 через `FetchContent`), проверено на Manjaro:** звук, воспроизведение и запись WAV, пауза, перемотка, счётчик, сброс и закрытие окон. Замена AudioToolbox на macOS не делалась | 3–5 дней |
| **4. Меню** (низкий приоритет) | ограничение оказалось косметическим: лишние пункты отключены. Убрать их из меню (механизм скрытия через `menuNeedsUpdate:`), решить судьбу альтернативных пунктов, убрать заглушки из `GNUstep-Stub.m`. Сочетания клавиш со стрелками (перемотка магнитофона, ⌘←/⌘→) GNUstep в меню не показывает, хотя они работают; запись магнитофона (⌥⌘R) под GNUstep — оба Alt + R | 2–3 дня |
| **5. Windows** | GL-загрузчик в `Display.m`; таблица клавиш Win32; сборка в CI; упаковка | 3–7 дней, сильно зависит от итогов этапа 0a |
| **6. Документация** | README (обновить раздел ограничений, инструкция для Windows), CLAUDE.md | меньше дня |

Оценки грубые: ориентир в днях работы одного разработчика, знакомого с кодом.

Этапы 1 и 2 полезны сами по себе и почти без риска — с них разумно начать. Этап 5 стоит делать только если прототип 0a покажет, что OpenGL работает на Windows.

## 5. Среда сборки

### Выбор платформы

Работа начинается под **Linux**: там GNUstep-сборка уже работает, и ошибки будут в коде проекта, а не в тулчейне. Этапы 1–4 делаются и проверяются под Linux. Windows нужна только для прототипа 0a (OpenGL), его делаем после того, как заработает Linux-сборка.

### Основной вариант: Manjaro на отдельной машине

**Почему:**
- настоящее железо: звук, OpenGL с шейдерами и коды клавиш X11 проверяются без искажений от виртуализации;
- свежие clang, CMake и библиотеки;
- машина уже есть, ничего не нужно поднимать.

**Минус:** rolling-обновления могут сломать самосборный GNUstep. Чаще всего это смена версии ICU, после которой нужно пересобрать libs-base. Поэтому все команды сборки нужно сразу записывать в скрипт (`scripts/build-gnustep.sh`). Позже он станет основой для Dockerfile и CI, а повторяемость проверим на Ubuntu LTS.

**1. Проверить, нет ли пакетов GNUstep из репозиториев.** Они собраны gcc со старым рантаймом, без ARC и блоков, и конфликтуют со своей сборкой. Если найдутся, удалить:

```sh
pacman -Qs gnustep
```

Пакет `libobjc` (рантайм Objective-C из gcc) удалять не нужно, да и нельзя: это зависимость `gcc-libs`. Он не мешает: его soname `libobjc.so.4`, а у libobjc2 — `libobjc.so.4.6`, и библиотеки GNUstep линкуются с libobjc2 из `/usr/GNUstep/System/Library/Libraries`. В конце сборки скрипт проверяет это через `ldd`.

**2. Зависимости:**

```sh
sudo pacman -S --needed base-devel clang lld cmake ninja git autoconf automake libtool pkgconf \
  libffi libxml2 libxslt gnutls icu curl \
  libjpeg-turbo libpng libtiff giflib cairo \
  libx11 libxt libxft libxrandr libxcursor \
  mesa glu mesa-utils \
  alsa-lib libpulse
```

`alsa-lib` и `libpulse` нужны для звука (этап 3).

**3. Сборка GNUstep.** Порядок: libobjc2 → libdispatch → tools-make → libs-base → libs-gui → libs-back. Всё с `export CC=clang CXX=clang++`.

| Компонент | Сборка |
|---|---|
| [libobjc2](https://github.com/gnustep/libobjc2) | CMake |
| [libdispatch](https://github.com/swiftlang/swift-corelibs-libdispatch) | CMake |
| [tools-make](https://github.com/gnustep/tools-make) | `--with-runtime-abi=gnustep-2.2 --enable-objc-arc --with-layout=gnustep --prefix=/usr/GNUstep` |
| [libs-base](https://github.com/gnustep/libs-base) | configure/make |
| [libs-gui](https://github.com/gnustep/libs-gui) | configure/make |
| [libs-back](https://github.com/gnustep/libs-back) | configure/make, бэкенд по умолчанию (X11 + cairo) |

`CMakeLists.txt` находит GNUstep через `gnustep-config`: в `PATH`, в `$GNUSTEP_SYSTEM_TOOLS` или в `/usr/GNUstep/{System,Local}/Tools`. Префикс `/usr/GNUstep` удобен тем, что подключать `GNUstep.sh` перед сборкой проекта не нужно.

Всё это делает `scripts/build-gnustep.sh`: `scripts/build-gnustep.sh --deps` ставит зависимости и собирает GNUstep целиком, а `scripts/build-gnustep.sh base` пересобирает только libs-base. Версии компонентов зафиксированы на релизных тегах и меняются переменными окружения (`LIBS_GUI_REF=master` и т. п.). Порядок и флаги взяты из проверенного рецепта [plaurent/gnustep-build](https://github.com/plaurent/gnustep-build) (Ubuntu 24.04, раскладка gnustep); отличие — вместо ld.gold используется lld.

**4. Окружение.** В Wayland-сессии (по умолчанию в KDE Plasma 6) приложение GNUstep работает через XWayland, коды клавиш там такие же, как в X11. Если появятся проблемы с окнами или вводом, проверить в X11-сессии.

По умолчанию GNUstep показывает меню в стиле NeXTSTEP — вертикальным списком в отдельном окне. Меню внутри окна эмулятора включается так (проверено на Manjaro, раскладка окна не ломается):

```sh
defaults write Retro80 NSMenuInterfaceStyle NSWindows95InterfaceStyle
```

Разово: `./Retro80 -NSMenuInterfaceStyle NSWindows95InterfaceStyle`; для всех GNUstep-приложений — `NSGlobalDomain` вместо `Retro80`.

**5. Проект:**

```sh
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Debug
cmake --build build
./build/Retro80.app/Retro80
```

CMake сам находит GNUstep через `gnustep-config`, выбирает clang и lld; подключать `GNUstep.sh` не нужно. Установка в `GNUSTEP_LOCAL_APPS` (обычно `/usr/GNUstep/Local/Applications`): `sudo cmake --install build`. Проверено на Manjaro (clang/lld 22.1.8): GNUstep собирается скриптом, Retro80 собирается и запускается.

Проверить OpenGL: `glxinfo | grep "OpenGL version"`.

### Перенос проекта на Linux-машину

`origin` указывает на чужой репозиторий `chicherov/Retro80`. Варианты:
- **форк на GitHub** (рекомендуется): работа в ветке форка, синхронизация через `push`/`pull`; этот же форк нужен для CI на GitHub Actions;
- **без GitHub:** `git clone` по SSH напрямую между машинами или `git bundle` на флешке.

### Запасной вариант: виртуальная машина

- **Гипервизор: VirtualBox 7.** Hyper-V на основной машине выключен, конфликтов не будет. Hyper-V к тому же не даёт нормального звука и 3D в госте.
- **Дистрибутив: Ubuntu 24.04 LTS.** Совпадает с раннерами GitHub Actions.
- **Параметры ВМ:** 4 ядра, 8 ГБ памяти, 40 ГБ диска, видео VMSVGA с 3D, звук включён, установлены Guest Additions.
- **Ограничение:** OpenGL будет через llvmpipe или эмуляцию VMSVGA. Для шейдеров этого хватит, но звук и производительность лучше проверять на реальном железе.

Зависимости для Ubuntu (пакеты `gnustep-*` из репозитория не ставить):

```sh
sudo apt install clang lld cmake ninja-build git make autoconf automake libtool pkg-config \
  libffi-dev libxml2-dev libxslt1-dev libgnutls28-dev libicu-dev libcurl4-gnutls-dev \
  libjpeg-dev libpng-dev libtiff-dev libgif-dev libcairo2-dev \
  libx11-dev libxt-dev libxft-dev libxrandr-dev libxcursor-dev \
  libgl-dev libglu1-mesa-dev mesa-utils \
  libasound2-dev libpulse-dev
```

Дальше та же сборка GNUstep и проекта, что и на Manjaro.

### Позже: Windows для прототипа 0a

Сейчас ставить не нужно. На основной машине уже есть CMake, Git и VS Code; clang, Visual Studio, MSYS2 и Docker отсутствуют.

- Visual Studio 2022 Build Tools (компонент «Разработка классических приложений на C++»);
- LLVM/clang 16+: `winget install LLVM.LLVM`;
- Ninja: `winget install Ninja-build.Ninja` (сейчас установлен через pip);
- MSYS2 и NASM — только если собирать тулчейн самим (`build.bat --with-gui`).

Перед этим проверить, есть ли GUI в готовом релизе [tools-windows-msvc](https://github.com/gnustep/tools-windows-msvc). Если нет, тулчейн придётся собирать самим.

## Источники

- [gnustep/tools-windows-msvc](https://github.com/gnustep/tools-windows-msvc)
- [gnustep/tools-scripts](https://github.com/gnustep/tools-scripts)
- [libs-gui NSMenuItem.h](https://github.com/gnustep/libs-gui/blob/master/Headers/AppKit/NSMenuItem.h)
- [libs-gui releases](https://github.com/gnustep/libs-gui/releases)
- [GNUstep Wiki: Installation MSYS2](https://mediawiki.gnustep.org/index.php/Installation_MSYS2)
- [GNUstep: Building on Windows](http://developer.gnustep.org/Guides/Setup/Windows/building-windows-msvc.html)
- [libs-back releases](https://github.com/gnustep/libs-back/releases)
