# Qt 6.8 compatibility with newer Apple toolchains. Do not modify the Qt SDK.
include_guard(GLOBAL)
if(NOT APPLE)
	return()
endif()

if(SCOPY_QT_INCLUDE_DIR)
	# Normal -I paths are searched before -iframework paths, even for Qt's own
	# <QtCore/...> includes. Prefer the selected SDK over globally linked Qt5.
	include_directories(BEFORE "${SCOPY_QT_INCLUDE_DIR}")
endif()

# Only the selected Qt 6.8 SDK needs the toolchain workarounds below.
if(NOT SCOPY_MACOS_QT_VERSION MATCHES "^6\\.8\\.")
	return()
endif()

# Clang 21 recognizes __yield as a builtin, which Qt 6.8 calls without first
# including the header that declares it. Older Clang versions use Qt's asm path.
if(CMAKE_CXX_COMPILER_ID STREQUAL "AppleClang" AND CMAKE_CXX_COMPILER_VERSION VERSION_GREATER_EQUAL 21
   AND (CMAKE_SYSTEM_PROCESSOR MATCHES "^(arm64|aarch64)$" OR "arm64" IN_LIST CMAKE_OSX_ARCHITECTURES))
	add_compile_options("$<$<COMPILE_LANGUAGE:CXX>:-include>" "$<$<COMPILE_LANGUAGE:CXX>:arm_acle.h>")
endif()

# New SDKs no longer ship AGL. Wait for Qt to create its own imported target,
# then remove only its obsolete AGL link entry; do not replace Qt's target.
function(scopy_macos_qt_opengl_compat)
	if(NOT TARGET WrapOpenGL::WrapOpenGL)
		return()
	endif()
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
		get_target_property(_scopy_gl_libraries WrapOpenGL::WrapOpenGL INTERFACE_LINK_LIBRARIES)
		if(_scopy_gl_libraries)
			list(FILTER _scopy_gl_libraries EXCLUDE REGEX "(^-framework AGL$|/AGL\\.framework(/|$))")
			set_property(TARGET WrapOpenGL::WrapOpenGL PROPERTY INTERFACE_LINK_LIBRARIES "${_scopy_gl_libraries}")
		endif()
	endif()
endfunction()

# Qt dependencies are discovered after project(), including in dependency builds.
if(CMAKE_VERSION VERSION_GREATER_EQUAL 3.19)
	cmake_language(DEFER CALL scopy_macos_qt_opengl_compat)
endif()
