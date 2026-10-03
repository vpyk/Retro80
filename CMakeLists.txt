cmake_minimum_required(VERSION 3.20)
set(CMAKE_OSX_ARCHITECTURES "arm64;x86_64" CACHE STRING "" FORCE)

# GNUstep с libobjc2 собирается только clang
if(NOT CMAKE_HOST_APPLE AND NOT CMAKE_OBJC_COMPILER AND NOT DEFINED ENV{OBJC})
	set(CMAKE_OBJC_COMPILER clang)
endif()

if(NOT CMAKE_HOST_APPLE AND NOT CMAKE_C_COMPILER AND NOT DEFINED ENV{CC})
	set(CMAKE_C_COMPILER clang)
endif()

project(Retro80 VERSION 0.92 LANGUAGES OBJC)

set(CMAKE_OBJC_STANDARD 99)

if(APPLE)
	add_compile_options(-Werror -fobjc-arc -fmodules)
endif()

if(NOT APPLE)

	# Под GNUstep есть код на C (miniaudio), флаги Objective-C ему не подходят
	enable_language(C)

	find_program(GNUSTEP_CONFIG gnustep-config
			HINTS ENV GNUSTEP_SYSTEM_TOOLS
			PATHS /usr/GNUstep/System/Tools /usr/GNUstep/Local/Tools
			REQUIRED)

	function(gnustep_variable name)
		execute_process(
				COMMAND ${GNUSTEP_CONFIG} --variable=${name}
				OUTPUT_VARIABLE value
				OUTPUT_STRIP_TRAILING_WHITESPACE
				COMMAND_ERROR_IS_FATAL ANY)
		set(${name} ${value} PARENT_SCOPE)
	endfunction()

	gnustep_variable(GNUSTEP_SYSTEM_HEADERS)
	gnustep_variable(GNUSTEP_LOCAL_HEADERS)
	gnustep_variable(GNUSTEP_SYSTEM_LIBRARIES)
	gnustep_variable(GNUSTEP_LOCAL_LIBRARIES)
	gnustep_variable(GNUSTEP_SYSTEM_TOOLS)
	gnustep_variable(GNUSTEP_LOCAL_APPS)

	include_directories(${GNUSTEP_LOCAL_HEADERS} ${GNUSTEP_SYSTEM_HEADERS})
	link_directories(${GNUSTEP_LOCAL_LIBRARIES} ${GNUSTEP_SYSTEM_LIBRARIES})

	# ABI рантайма берётся из настроек gnustep-make, чтобы совпадать с собранными библиотеками
	execute_process(
			COMMAND ${GNUSTEP_CONFIG} --objc-flags
			OUTPUT_VARIABLE GNUSTEP_OBJC_FLAGS
			COMMAND_ERROR_IS_FATAL ANY)

	if(GNUSTEP_OBJC_FLAGS MATCHES "-fobjc-runtime=([^ \n]+)")
		set(GNUSTEP_RUNTIME_ABI ${CMAKE_MATCH_1})
	else()
		set(GNUSTEP_RUNTIME_ABI gnustep-2.2)
	endif()

	message(STATUS "GNUstep: ${GNUSTEP_CONFIG}, runtime ${GNUSTEP_RUNTIME_ABI}")

	add_compile_options("$<$<COMPILE_LANGUAGE:OBJC>:-Werror;-fobjc-arc;-fmodules;-fobjc-runtime=${GNUSTEP_RUNTIME_ABI};-fblocks>")
	add_compile_definitions(GNUSTEP)

	# Новый ABI libobjc2 надёжнее всего линкуется lld
	find_program(LLD_LINKER ld.lld)

	if(LLD_LINKER)
		add_link_options(-fuse-ld=lld)
	endif()

	find_program(PLMERGE plmerge HINTS ${GNUSTEP_SYSTEM_TOOLS} REQUIRED)

	# Звук и WAV: miniaudio (https://miniaud.io), библиотека на C из одного файла.
	# Берутся только исходники: SOURCE_SUBDIR без CMakeLists.txt не подключается к сборке.
	include(FetchContent)

	FetchContent_Declare(miniaudio
			GIT_REPOSITORY https://github.com/mackron/miniaudio.git
			GIT_TAG 0.11.25
			GIT_SHALLOW TRUE
			SOURCE_SUBDIR none)

	FetchContent_MakeAvailable(miniaudio)

	add_library(miniaudio STATIC ${miniaudio_SOURCE_DIR}/miniaudio.c)
	target_include_directories(miniaudio PUBLIC ${miniaudio_SOURCE_DIR})
	target_compile_definitions(miniaudio PUBLIC
			MA_NO_ENGINE MA_NO_NODE_GRAPH MA_NO_RESOURCE_MANAGER MA_NO_GENERATION MA_NO_MP3 MA_NO_FLAC)
	target_link_libraries(miniaudio PUBLIC dl pthread m)

endif()

set(CMAKE_OBJC_FLAGS_DEBUG "${CMAKE_OBJC_FLAGS_DEBUG} -DDEBUG")
set(CMAKE_OSX_DEPLOYMENT_TARGET 10.13)

##
## Retro80 Files
##

set(RETRO80_BASE_SOURCES
		Retro80/Document.h
		Retro80/Document.m
		Retro80/DocumentController.h
		Retro80/DocumentController.m
		Retro80/WindowController.h
		Retro80/WindowController.m
		Retro80/Application.h
		Retro80/Application.m
		Retro80/ComputerFactory.h
		Retro80/ComputerFactory.m
		Retro80/Computer.h
		Retro80/Computer.m
		Retro80/Display.h
		Retro80/Display.m
		Retro80/Digit.h
		Retro80/Digit.m
		Retro80/Debug.h
		Retro80/Debug.m
		Retro80/Sound.h)

if(APPLE)
	set(RETRO80_BASE_SOURCES
			${RETRO80_BASE_SOURCES}
			Retro80/Sound.m)
else()
	set(RETRO80_BASE_SOURCES
			${RETRO80_BASE_SOURCES}
			Retro80/GNUstep-Sound.m
			Retro80/GNUstep-Stub.m)
endif()

set(RETRO80_X8080_SOURCES
		Retro80/Retro80.h
		Retro80/Retro80.m
		Retro80/x8080.h
		Retro80/x8080.m
		Retro80/Dbg80.h
		Retro80/Dbg80.m
		Retro80/x8253.h
		Retro80/x8253.m
		Retro80/x8257.h
		Retro80/x8257.m
		Retro80/x8275.h
		Retro80/x8275.m
		Retro80/x8255.h
		Retro80/x8255.m
		Retro80/mem.h
		Retro80/mem.m
		Retro80/vg93.h
		Retro80/vg93.m
)

set(RETRO80_RADIO86RK_SOURCES
		Retro80/Radio86RKFactory.h
		Retro80/Radio86RKFactory.m
		Retro80/RKKeyboard.h
		Retro80/RKKeyboard.m
		Retro80/RKRecorder.h
		Retro80/RKRecorder.m
		Retro80/RK86Base.h
		Retro80/RK86Base.m
		Retro80/Radio86RK.h
		Retro80/Radio86RK.m
		Retro80/Microsha.h
		Retro80/Microsha.m
		Retro80/MicroshaKeyboard.m
		Retro80/Apogeo.h
		Retro80/Apogeo.m
		Retro80/Partner.h
		Retro80/Partner.m
		Retro80/ROMDisk.h
		Retro80/ROMDisk.m
		Retro80/RKSDCard.h
		Retro80/RKSDCard.m
		Retro80/RKFloppy.h
		Retro80/RKFloppy.m)

set(RETRO80_MICRO80_SOURCES
		Retro80/Micro80Factory.h
		Retro80/Micro80Factory.m
		Retro80/Micro80.h
		Retro80/Micro80.m
		Retro80/Micro80Keyboard.h
		Retro80/Micro80Keyboard.m
		Retro80/Micro80Recorder.h
		Retro80/Micro80Recorder.m
		Retro80/Micro80Screen.h
		Retro80/Micro80Screen.m
		Retro80/UT88.h
		Retro80/UT88.m
		Retro80/UT88Keyboard.h
		Retro80/UT88Keyboard.m
		Retro80/UT88Screen.h
		Retro80/UT88Screen.m
		Retro80/UT88System.h
		Retro80/UT88System.m)

set(RETRO80_SPECIALIST_SOURCES
		Retro80/SpecialistFactory.h
		Retro80/SpecialistFactory.m
		Retro80/Specialist.h
		Retro80/Specialist.m
		Retro80/SpecialistKeyboard.h
		Retro80/SpecialistKeyboard.m
		Retro80/SpecialistScreen.h
		Retro80/SpecialistScreen.m
		Retro80/SpecialistSDCard.h
		Retro80/SpecialistSDCard.m
		Retro80/SpecialistSP580.h
		Retro80/SpecialistSP580.m
		Retro80/SpecialistMX.h
		Retro80/SpecialistMX.m
		Retro80/SpecialistMXKeyboard.h
		Retro80/SpecialistMXKeyboard.m
		Retro80/SpecialistMXSystem.m
		Retro80/SpecialistMX2Flash.h
		Retro80/SpecialistMX2Flash.m)

set(RETRO80_ORION_SOURCES
		Retro80/Orion128Factory.h
		Retro80/Orion128Factory.m
		Retro80/Orion128.h
		Retro80/Orion128.m
		Retro80/Orion128Screen.h
		Retro80/Orion128Screen.m
		Retro80/Orion128Floppy.h
		Retro80/Orion128Floppy.m)

set(RETRO80_SOURCES
		${RETRO80_BASE_SOURCES}
		${RETRO80_X8080_SOURCES}
		${RETRO80_RADIO86RK_SOURCES}
		${RETRO80_MICRO80_SOURCES}
		${RETRO80_SPECIALIST_SOURCES}
		${RETRO80_ORION_SOURCES}
        Retro80/main.m)

if(NOT APPLE)
	# Расширение .m числится и за языком C, а под GNUstep C тоже включён (miniaudio):
	# без явного указания CMake компилирует файлы .m как C, без флагов Objective-C
	set(RETRO80_OBJC_SOURCES ${RETRO80_SOURCES})
	list(FILTER RETRO80_OBJC_SOURCES INCLUDE REGEX "\\.m$")
	set_source_files_properties(${RETRO80_OBJC_SOURCES} PROPERTIES LANGUAGE OBJC)
endif()

file(GLOB RETRO80_ROM_RESOURCES CONFIGURE_DEPENDS Retro80/ROM/*)

set(RETRO80_GLOBAL_RESOURCES
        Retro80.icns
        ${RETRO80_ROM_RESOURCES}
        Retro80/digits.png
        Retro80/tvnoise.fs
        Retro80/tvnoise.vs)

set(RETRO80_RU_RESOURCES
		Retro80/ru.lproj/InfoPlist.strings
        Retro80/ru.lproj/Document.xib
        Retro80/ru.lproj/MainMenu.xib)

set(RETRO80_RESOURCES
        ${RETRO80_GLOBAL_RESOURCES}
        ${RETRO80_RU_RESOURCES})

set_source_files_properties(
		${RETRO80_RESOURCES}
		PROPERTIES MACOSX_PACKAGE_LOCATION Resources
)

##
## Retro80
##

add_executable(Retro80 MACOSX_BUNDLE
        ${RETRO80_SOURCES}
        ${RETRO80_RESOURCES})

if(APPLE)

	set_target_properties(Retro80 PROPERTIES MACOSX_BUNDLE_INFO_PLIST ${CMAKE_CURRENT_SOURCE_DIR}/Retro80/Retro80-Info.plist)
	target_precompile_headers(Retro80 PRIVATE Retro80/Retro80-Prefix.pch)

else()

	# Не target_precompile_headers: при включённом языке C CMake собирает заголовок для OBJC
	# поверх заголовка для C, а тот у цели без файлов на C не собирается
	target_compile_options(Retro80 PRIVATE
			"$<$<COMPILE_LANGUAGE:OBJC>:-include;${CMAKE_CURRENT_SOURCE_DIR}/Retro80/GNUstep-Prefix.pch>")
	target_link_libraries(Retro80 objc dispatch gnustep-base gnustep-gui GL GLU m miniaudio)

	# Бандл приложения GNUstep: Retro80.app/Retro80 + Retro80.app/Resources
	set(RETRO80_APP_DIR ${CMAKE_CURRENT_BINARY_DIR}/Retro80.app)
	set_target_properties(Retro80 PROPERTIES RUNTIME_OUTPUT_DIRECTORY ${RETRO80_APP_DIR})

	add_custom_command(
			TARGET Retro80 POST_BUILD
			WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
			COMMAND ${CMAKE_COMMAND} -E make_directory ${RETRO80_APP_DIR}/Resources
			COMMAND ${CMAKE_COMMAND} -E copy ${RETRO80_RESOURCES} ${RETRO80_APP_DIR}/Resources
			COMMAND ${PLMERGE} ${RETRO80_APP_DIR}/Resources/Info-gnustep.plist Retro80/Retro80-Info.plist
	)

	install(DIRECTORY ${RETRO80_APP_DIR} DESTINATION ${GNUSTEP_LOCAL_APPS} USE_SOURCE_PERMISSIONS)

endif()
