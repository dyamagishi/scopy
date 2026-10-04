# Qt 6.8 compatibility with newer Apple toolchains. Do not modify the Qt SDK.
include_guard(GLOBAL)
if(NOT APPLE)
	return()
endif()

if(SCOPY_QT_INCLUDE_DIR)
	# Normal -I paths are searched before -iframework paths, even for Qt's own
	# <QtCore/...> includes. Prefer the selected SDK over globally linked Qt5.
	# A compiler probe may have classified our -I flag as an implicit path;
	# keep it explicit so target include paths cannot take precedence over it.
	list(REMOVE_ITEM CMAKE_CXX_IMPLICIT_INCLUDE_DIRECTORIES "${SCOPY_QT_INCLUDE_DIR}")
	include_directories(BEFORE "${SCOPY_QT_INCLUDE_DIR}")
endif()

# Clang 21 recognizes __yield as a builtin, which Qt 6.8 calls without first
# including the header that declares it. Older Clang versions use Qt's asm path.
if(CMAKE_CXX_COMPILER_ID STREQUAL "AppleClang" AND CMAKE_CXX_COMPILER_VERSION VERSION_GREATER_EQUAL 21
   AND (CMAKE_SYSTEM_PROCESSOR MATCHES "^(arm64|aarch64)$" OR "arm64" IN_LIST CMAKE_OSX_ARCHITECTURES))
	add_compile_options("$<$<COMPILE_LANGUAGE:CXX>:-include>" "$<$<COMPILE_LANGUAGE:CXX>:arm_acle.h>")
endif()

# New SDKs no longer ship AGL (the legacy Carbon OpenGL framework). Qt's
# FindWrapOpenGL in 6.8 still adds -framework AGL even when it cannot be found.
if(NOT TARGET WrapOpenGL::WrapOpenGL)
	if(IS_DIRECTORY "${CMAKE_OSX_SYSROOT}")
		set(_scopy_sdk "${CMAKE_OSX_SYSROOT}")
	else()
		set(_scopy_sdk_name "${CMAKE_OSX_SYSROOT}")
		if(NOT _scopy_sdk_name)
			set(_scopy_sdk_name macosx)
		endif()
		execute_process(COMMAND xcrun --sdk "${_scopy_sdk_name}" --show-sdk-path
				OUTPUT_VARIABLE _scopy_sdk OUTPUT_STRIP_TRAILING_WHITESPACE)
	endif()
	# The running OS may still have AGL, but the linker needs it in the SDK.
	if(_scopy_sdk AND NOT EXISTS "${_scopy_sdk}/System/Library/Frameworks/AGL.framework")
		find_package(OpenGL QUIET)
		if(TARGET OpenGL::GL)
			add_library(WrapOpenGL::WrapOpenGL INTERFACE IMPORTED GLOBAL)
			target_link_libraries(WrapOpenGL::WrapOpenGL INTERFACE OpenGL::GL)
		endif()
	endif()
endif()
