# Перенос под Windows: план работ

Этап 5 из [GNUstep-plan.md](GNUstep-plan.md). Работа идёт в ветке `windows` (от `gnustep`): часть изменений затрагивает общий с macOS код, а проверить их на macOS оперативно нельзя.

## Путь сборки: MSYS2, окружение CLANG64

| | tools-windows-msvc (официальный, ABI MSVC) | **MSYS2 CLANG64 (выбран)** |
|---|---|---|
| Окна на экране | **нет**: libs-back собран с `--enable-graphics=headless --enable-server=headless`, поддержка win32 — открытая задача ([issue #36](https://github.com/gnustep/tools-windows-msvc/issues/36)) | **да**: libs-back с cairo и сервером win32 |
| Версии | разные коммиты | gnustep-make 2.9.3, base 1.31.1, gui/back 0.32.0, libobjc2 2.2.1 — почти как в сборке под Linux |
| Установка | бэкенд с окнами пришлось бы собирать самим | пакеты `pacman`, GNUstep собирать не нужно |
| Особенности | — | gnustep-make: `ng-gnu-gnu`, ABI `gnustep-2.0` (CMake берёт ABI из `gnustep-config`); **libs-base собран без libdispatch** |

OpenGL в сервере win32 есть (`libs-back/Source/win32/w32_GLcontext.m`: дочернее окно с контекстом WGL для `NSOpenGLView`), поэтому отдельный прототип OpenGL не нужен — проверкой станет сама сборка эмулятора.

### Установка

1. MSYS2 (`winget install MSYS2.MSYS2` или установщик с msys2.org). Место: 3–5 ГБ. Установлен в `D:\msys64`.
2. В оболочке **MSYS2 CLANG64**:

```sh
pacman -S --needed git \
  mingw-w64-clang-x86_64-{clang,lld,cmake,ninja} \
  mingw-w64-clang-x86_64-{gnustep-make,gnustep-base,gnustep-gui,gnustep-back,libobjc2}
```

**Без `libdispatch`:** пакет тянет `libblocksruntime-swift`, чей `Block.h` конфликтует с `libobjc2` (в libobjc2 свой рантайм блоков). Ставить с `--overwrite` не стоит — в программе оказались бы две реализации `_Block_copy` и др. libdispatch на Windows и не нужен: gnustep-base в MSYS2 собран без него, `dispatch_async` на главную очередь заменяется (п. 1), а `dispatch_once` в `ComputerFactory.m` — обычной инициализацией.

Возможно, понадобится `mingw-w64-clang-x86_64-libepoxy` (см. п. 2 ниже).

Visual Studio, NASM и прочее для tools-windows-msvc на этом пути не нужны.

## Изменения в коде

1. **`dispatch_async(dispatch_get_main_queue(), …)`** — `Display.m`, `Micro80Screen.m`, `Orion128Screen.m`, `SpecialistScreen.m`, `GNUstep-Sound.m` (и `Sound.m` на macOS). Блоки главной очереди libdispatch выполняются, только если libs-base собран с libdispatch; в MSYS2 это не так, и экран, вероятно, не будет обновляться. **Решение:** заменить на главную очередь Foundation (`NSOperationQueue.mainQueue` / `performSelectorOnMainThread`). Это общий с macOS код — проверить на macOS до слияния в основную ветку. `dispatch_once` (`ComputerFactory.m`) заменить обычной инициализацией (например, в `+initialize`), чтобы под Windows не нужен был libdispatch; в CMake не линковать `dispatch` на Windows.
2. **OpenGL.** В Windows `GL/gl.h` описывает только OpenGL 1.1, а `Display.m` использует ~20 функций новее (`glCreateShader`, `glShaderSource`, `glCompileShader`, `glGetShaderiv`, `glGetShaderInfoLog`, `glCreateProgram`, `glAttachShader`, `glLinkProgram`, `glGetProgramiv`, `glGetProgramInfoLog`, `glUseProgram`, `glDeleteShader`, `glDeleteProgram`, `glGetUniformLocation`, `glUniform1i/1f/2f`, `glActiveTexture`). Загрузка через `wglGetProcAddress` небольшим кодом в `Display.m` или через libepoxy. Риск: чёрно-белый режим без шейдера использует `glMatrixMode(GL_COLOR)` (ARB_imaging), драйверы Windows могут его не поддерживать.
3. **`CMakeLists.txt`:** `opengl32` вместо `GL GLU` (GLU код не использует); для miniaudio без `dl pthread m`; копирование нужных DLL к `Retro80.exe` для запуска вне оболочки MSYS2.
4. **Клавиатура:** сервер win32 отдаёт в `keyCode` коды виртуальных клавиш (VK, `wParam`) — вторая таблица в `macKeyCode()` (`RKKeyboard.m`). VK букв от раскладки не зависят, VK знаков препинания могут зависеть — проверить на русской раскладке.
5. **Модификаторы** в сервере win32 (`mask_for_keystate` в `WIN32Server.m`) по умолчанию не такие, как в X11:
   - любой Alt — ⌥ (РУС/ЛАТ);
   - левый Ctrl и правый Win — ⌘ (сочетания как в Windows: Ctrl+S, Ctrl+R); клавиша [УС] эмулятора остаётся только на правом Ctrl;
   - **Caps Lock выдаётся как Shift**: РУС/ЛАТ через Caps Lock на Микро-80/ЮТ-88 сломается, возможен постоянный верхний регистр. Возможно, отслеживать Caps Lock самим (`GetKeyState`);
   - подписи сочетаний в меню (`main.m`, `GS*KeyString`) для Windows свои: `Ctrl+` для ⌘ и т.п.
6. **Звук:** miniaudio через WASAPI, код не меняется; проверить сборку и тактирование эмуляции от звука.
7. **86RKSD и диалоги:** NTFS не учитывает регистр — поиск без учёта регистра не мешает; проверить, что пути приходят с `/`.
8. **Распространение (потом):** приложению GNUstep нужны DLL и ресурсы GNUstep (бандл бэкенда, ресурсы gui). Варианты: `windows-package` из [tools-scripts](https://github.com/gnustep/tools-scripts), CPack (ZIP).

## Порядок и объём

| Шаг | Содержание | Объём |
|---|---|---|
| 1 | MSYS2 и пакеты, первая сборка как есть | полдня |
| 2 | Пп. 1–3: главная очередь, OpenGL, CMake — до работающего экрана | 1–2 дня |
| 3 | Пп. 4–6: клавиатура, модификаторы, звук | 1–2 дня |
| 4 | Распространение, README, позже CI | 1–2 дня |

Главные риски: зрелость GUI и OpenGL в сервере win32 GNUstep (выяснится на шаге 1–2) и поведение Caps Lock.

## Состояние

Сборка и запуск (из оболочки MSYS2 CLANG64):

```sh
cmake -B build-win -G Ninja -DCMAKE_BUILD_TYPE=Debug
cmake --build build-win
./build-win/Retro80.app/Retro80.exe
```

Без оболочки MSYS2 — `scripts\run-windows.cmd` (добавляет `<MSYS2>\clang64\bin` в `PATH`; каталог MSYS2 — `MSYS2_ROOT`, иначе `C:\msys64` или `D:\msys64`).

- **Сделано и проверено:** пп. 1–3 (главная очередь, OpenGL, CMake). Окна, экран, шейдеры, звук (WASAPI), магнитофон, перехват ленты, «Файл → Открыть» и открытие из командной строки, сохранение, меню и «Открыть недавние» работают. Сочетания клавиш — с левым Ctrl.
- **Найдено по ходу:**
  - GNUstep в MSYS2 собран с `-DSTRICT_APPLE_COMPATIBILITY=1` (`BOOL` — `signed char`); libobjc2 ищет методы по имени и типам, поэтому определения берутся из `gnustep-config --objc-flags`, иначе GNUstep не видит переопределённых методов с `BOOL` (`readFromData:ofType:error:` и др.);
  - `gnustep-config` — shell-скрипт: CMake запускает его через `sh`, пути переводит `cygpath -m`; для флагов ему нужен `make` (пакет `make`);
  - `fileSystemRepresentation` под Windows — UTF-16, для miniaudio — функции `*_w`;
  - в MinGW нет `random()`, `long` 32-битный (форматы `%lu` для `NSUInteger`).
- **Сделано и проверено:** пп. 4–5. Позиционный режим клавиатуры (таблица кодов VK в `RKKeyboard.m`); модификаторы: ⌘ — Alt, Control — левый Ctrl ([УС]), ⌥ — правый Ctrl (РУС/ЛАТ), заданы в `main.m` через `GSFirst*Key`; Caps Lock (РУС/ЛАТ на Микро-80/ЮТ-88) — состояние через `GetKeyState`, т.к. сервер win32 выдаёт его как Shift. Ограничение: Enter на цифровой клавиатуре в Windows неотличим от Return, [ПС] в позиционном режиме недоступна.
- **Дальше:** п. 8 (распространение без MSYS2), README; проверка общего с macOS кода до слияния.
