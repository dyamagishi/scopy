#!/bin/bash
# Incremental native Scopy and IIO-Emulator build for CI and developers.
set -euo pipefail
if [[ ${1:-} == --help ]]; then
	echo "Usage: bash ci/macOS/build_macos.sh"
	echo "Overrides: BUILDDIR, STAGING_AREA, QT, JOBS, ENABLE_TESTING (ON/OFF)"
	exit 0
fi
[[ $# == 0 ]] || { echo "Unexpected argument: $1" >&2; exit 1; }
# shellcheck source=ci/macOS/macos_common.sh
source "$(dirname "$0")/macos_common.sh"
require_native_macos
setup_build_environment
ENABLE_TESTING=${ENABLE_TESTING:-OFF}
[[ $ENABLE_TESTING == ON || $ENABLE_TESTING == OFF ]] || { echo "ENABLE_TESTING must be ON or OFF" >&2; exit 1; }
clone iio-emu https://github.com/analogdevicesinc/iio-emu.git main
configure_build iio-emu
cmake -S "$REPO_SRC" -B "$BUILDDIR" -G Ninja \
	-DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
	-DCMAKE_OSX_DEPLOYMENT_TARGET="$MACOSX_DEPLOYMENT_TARGET" \
	-DCMAKE_CXX_FLAGS="-I\"$QT_INCLUDE_DIR\"" -DSCOPY_QT_INCLUDE_DIR="$QT_INCLUDE_DIR" \
	-DCMAKE_PREFIX_PATH="$PREFIX_PATH" -DCMAKE_INSTALL_PREFIX="$STAGING_AREA/scopy-install" \
	-DPython3_EXECUTABLE="$STAGING_AREA/venv/bin/python3" \
	-DCMAKE_BUILD_WITH_INSTALL_RPATH=OFF \
	-DCMAKE_INSTALL_RPATH="$STAGING_AREA_DEPS/lib;$QT/lib;@executable_path/../Frameworks" \
	-DENABLE_TESTING="$ENABLE_TESTING" -DENABLE_ALL_PACKAGES=ON -DENABLE_PACKAGE_M2K=OFF \
	-DENABLE_PLUGIN_ADC=OFF -DWITH_SIGROK=OFF -DWITH_PYTHON=OFF
cmake --build "$BUILDDIR" --parallel "$JOBS"
file "$BUILDDIR/Scopy.app/Contents/MacOS/Scopy"
echo "Built: $BUILDDIR/Scopy.app (run package_darwin.sh for a standalone app)"
