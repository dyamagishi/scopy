#!/bin/bash

# macOS Qt6 Build Script
# =====================================
# Build Scopy and IIO-Emulator on macOS with Qt6
# Usage: ./build_macos.sh
#
# This script can be run locally on macOS systems.
# It assumes dependencies are already installed via install_macos_deps.sh

set -ex
REPO_SRC=$(git rev-parse --show-toplevel)
# Load macOS Qt6-specific configuration
source "$REPO_SRC/ci/macOS/macos_config.sh"

# Build IIO Emulator
# =================
# Virtual IIO device for testing without hardware
build_iio-emu(){
	echo "### Clone and Build IIO-Emulator"
	pushd "$REPO_SRC"
	if [ ! -d "$REPO_SRC/iio-emu" ]; then
		git clone https://github.com/analogdevicesinc/iio-emu "$REPO_SRC/iio-emu"
	fi
	mkdir -p "$REPO_SRC/iio-emu/build"
	cd "$REPO_SRC/iio-emu/build"

	cmake \
		-DCMAKE_LIBRARY_PATH="$STAGING_AREA_DEPS" \
		-DCMAKE_INSTALL_PREFIX="$STAGING_AREA_DEPS" \
		-DCMAKE_PREFIX_PATH="${QT};${STAGING_AREA_DEPS};${STAGING_AREA_DEPS}/lib/cmake;" \
		-DCMAKE_BUILD_TYPE=RelWithDebInfo \
		-DCMAKE_VERBOSE_MAKEFILE=ON \
		-DCMAKE_STAGING_PREFIX="$STAGING_AREA_DEPS" \
		-DCMAKE_EXE_LINKER_FLAGS="-L${STAGING_AREA_DEPS}/lib" \
		-DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
		-DCMAKE_OSX_ARCHITECTURES="$ARCH" \
		-DCMAKE_OSX_DEPLOYMENT_TARGET="$MACOSX_DEPLOYMENT_TARGET" \
		../
	CFLAGS=-I${STAGING_AREA_DEPS}/include LDFLAGS=-L${STAGING_AREA_DEPS}/lib make ${JOBS}
	popd
}

build_scopy(){
	echo "### Building Scopy"
	local m2k_options=(-DENABLE_PACKAGE_M2K="$ENABLE_PACKAGE_M2K" -DWITH_SIGROK="$ENABLE_PACKAGE_M2K" -DWITH_PYTHON=OFF)
	if [ "$ENABLE_PACKAGE_M2K" = ON ]; then
		m2k_options+=(-DWITH_PYTHON=ON -DBOOST_ROOT="$(brew --prefix boost@1.85)"
			-DCMAKE_PREFIX_PATH="${QT};${STAGING_AREA_DEPS};$(brew --prefix)"
			-DPython3_ROOT_DIR="$(brew --prefix python@3.11)"
			-DPYTHON_EXECUTABLE="$STAGING_AREA/m2k-venv/bin/python3"
			-DPython3_EXECUTABLE="$STAGING_AREA/m2k-venv/bin/python3")
	fi
	pushd "$REPO_SRC"
	mkdir -p "$BUILDDIR"
	cd "$BUILDDIR"
	cmake \
		-DCMAKE_LIBRARY_PATH="$STAGING_AREA_DEPS" \
		-DCMAKE_INSTALL_PREFIX="$STAGING_AREA/scopy-install" \
		-DCMAKE_PREFIX_PATH="${QT};${STAGING_AREA_DEPS};${STAGING_AREA_DEPS}/lib/cmake;${STAGING_AREA_DEPS}/lib/pkgconfig;${STAGING_AREA_DEPS}/lib/cmake/iio" \
		-DCMAKE_BUILD_TYPE=RelWithDebInfo \
		-DCMAKE_VERBOSE_MAKEFILE=ON \
		-DCMAKE_STAGING_PREFIX="$STAGING_AREA_DEPS" \
		-DCMAKE_EXE_LINKER_FLAGS="-L${STAGING_AREA_DEPS}/lib" \
		-DCMAKE_MACOSX_RPATH=ON \
		-DCMAKE_BUILD_WITH_INSTALL_RPATH=OFF \
		-DCMAKE_BUILD_RPATH="${STAGING_AREA_DEPS}/lib;${QT}/lib" \
		-DCMAKE_INSTALL_RPATH="${STAGING_AREA_DEPS}/lib;${QT}/lib;@executable_path/../Frameworks" \
		-DCMAKE_OSX_ARCHITECTURES="$ARCH" \
		-DCMAKE_OSX_DEPLOYMENT_TARGET="$MACOSX_DEPLOYMENT_TARGET" \
		-DSCOPY_QT_INCLUDE_DIR="$SCOPY_QT_INCLUDE_DIR" \
		-DSCOPY_MACOS_QT_VERSION="$QT_VERSION" \
		-DENABLE_TESTING="${ENABLE_TESTING:-OFF}" \
		-DENABLE_ALL_PACKAGES=ON \
		-DENABLE_PLUGIN_ADC=OFF \
		"${m2k_options[@]}" \
		"$REPO_SRC"
	CFLAGS=-I${STAGING_AREA_DEPS}/include LDFLAGS=-L${STAGING_AREA_DEPS}/lib make ${JOBS}
	otool -l ./Scopy.app/Contents/MacOS/Scopy
	otool -L ./Scopy.app/Contents/MacOS/Scopy
	popd
}

build_iio-emu
build_scopy
