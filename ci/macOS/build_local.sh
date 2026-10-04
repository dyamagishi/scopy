#!/bin/bash
# Incremental native macOS build without CI cleanup or global Python installs.
set -euo pipefail

if [[ ${1:-} == --help ]]; then
	echo "Usage: bash ci/macOS/build_local.sh [--deps-only | --build-only]"
	echo "Overrides: BUILDDIR, STAGING_AREA, QT, JOBS (number of parallel jobs)"
	exit 0
fi
MODE=${1:-all}
case "$MODE" in all|--deps-only|--build-only) ;; *) echo "Unknown option: $MODE" >&2; exit 1 ;; esac
[[ $(uname -s) == Darwin ]] || { echo "macOS is required" >&2; exit 1; }
ARCH=$(uname -m)
if [[ $(sysctl -in sysctl.proc_translated 2>/dev/null || true) == 1 ]]; then
	echo "Run from a native terminal, not Rosetta." >&2
	exit 1
fi
REPO_SRC=$(cd "$(dirname "$0")/../.." && pwd)
export STAGING_AREA=${STAGING_AREA:-$REPO_SRC/build-local/deps}
export BUILDDIR=${BUILDDIR:-$REPO_SRC/build-local/scopy}
JOBS=${JOBS:-8}
[[ $JOBS =~ ^[1-9][0-9]*$ ]] || { echo "JOBS must be a positive integer" >&2; exit 1; }
cd "$REPO_SRC"
# shellcheck source=ci/macOS/macos_config.sh
source "$REPO_SRC/ci/macOS/macos_config.sh"
BREW_PREFIX=$(brew --prefix)
export PATH="$STAGING_AREA/venv/bin:$BREW_PREFIX/bin:$QT_PATH:$PATH"
export PKG_CONFIG_PATH="$STAGING_AREA_DEPS/lib/pkgconfig:$BREW_PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
PREFIX_PATH="$QT;$STAGING_AREA_DEPS;$BREW_PREFIX"
QT_CXX_FLAGS=
if [[ $ARCH == arm64 ]]; then
	# Qt 6.8's qyieldcpu.h sees Clang 21's __yield builtin but lacks its declaration.
	QT_CXX_FLAGS="-include arm_acle.h"
fi

clone() {
	local name=$1 url=$2 ref=$3
	if [[ ! -d "$STAGING_AREA/src/$name" ]]; then
		git clone --depth 1 --branch "$ref" "$url" "$STAGING_AREA/src/$name"
	fi
}

configure_build() {
	local name=$1
	shift
	cmake -S "$STAGING_AREA/src/$name" -B "$STAGING_AREA/build/$name" -G Ninja \
		-DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
		-DCMAKE_OSX_ARCHITECTURES="$ARCH" -DCMAKE_PREFIX_PATH="$PREFIX_PATH" \
		-DCMAKE_PROJECT_INCLUDE="$REPO_SRC/cmake/Modules/ScopyMacOSQtCompat.cmake" \
		-DCMAKE_CXX_FLAGS="-I\"$STAGING_AREA/qt-include\"" \
		-DSCOPY_QT_INCLUDE_DIR="$STAGING_AREA/qt-include" \
		-DCMAKE_INSTALL_PREFIX="$STAGING_AREA_DEPS" "$@"
	cmake --build "$STAGING_AREA/build/$name" --parallel "$JOBS"
}

install_cmake() {
	local name=$1
	shift
	configure_build "$name" "$@"
	cmake --install "$STAGING_AREA/build/$name"
}

install_framework() {
	local name=$1 framework=$2 header=$3
	shift 3
	configure_build "$name" -DWITH_DOC=OFF -DBUILD_TESTS=OFF -DOSX_PACKAGE=OFF "$@"
	# Upstream framework install rules target /Library/Frameworks. Keep everything local.
	mkdir -p "$STAGING_AREA_DEPS/include" "$STAGING_AREA_DEPS/lib/pkgconfig"
	cp "$STAGING_AREA/src/$name/$header" "$STAGING_AREA_DEPS/include/"
	cp -R "$STAGING_AREA/build/$name/$framework.framework" "$STAGING_AREA_DEPS/lib/"
	cp "$STAGING_AREA/build/$name/lib$framework.pc" "$STAGING_AREA_DEPS/lib/pkgconfig/"
}

if [[ $MODE != --build-only ]]; then
	mkdir -p "$STAGING_AREA/src" "$STAGING_AREA_DEPS"
	# Only install missing formulae; never uninstall, overwrite, or upgrade unrelated packages.
	for formula in cmake ninja pkg-config libusb libserialport libxml2 fftw zstd; do
		brew list --versions "$formula" >/dev/null 2>&1 || brew install "$formula"
	done
	if [[ ! -x "$STAGING_AREA/venv/bin/python3" ]]; then
		python3 -m venv "$STAGING_AREA/venv"
	fi
	"$STAGING_AREA/venv/bin/python3" -m pip install 'aqtinstall==3.3.0' mako
	if [[ ! -x "$QT/bin/qmake6" ]]; then
		aqt install-qt --outputdir "$QT_INSTALL_LOCATION" mac desktop 6.8.3 clang_64 -m qt3d qtscxml
	fi
	# Clang searches normal include paths before framework paths. Homebrew's
	# Qt5 headers must not shadow the selected Qt6 when another library adds
	# /opt/homebrew/include. Provide local aliases, without relinking Homebrew.
	mkdir -p "$STAGING_AREA/qt-include"
	for framework in "$QT"/lib/*.framework; do
		name=$(basename "$framework" .framework)
		if [[ ! -e "$STAGING_AREA/qt-include/$name" ]]; then
			ln -s "$framework/Headers" "$STAGING_AREA/qt-include/$name"
		fi
	done
	clone libiio https://github.com/analogdevicesinc/libiio.git "$LIBIIO_VERSION"
	clone libad9361 https://github.com/analogdevicesinc/libad9361-iio.git "$LIBAD9361_BRANCH"
	clone libad9166 https://github.com/analogdevicesinc/libad9166-iio.git "$LIBAD9166_BRANCH"
	clone qwt https://github.com/cseci/qwt.git "$QWT_BRANCH"
	clone libtinyiiod https://github.com/analogdevicesinc/libtinyiiod.git "$LIBTINYIIOD_BRANCH"
	clone KDDockWidgets https://github.com/KDAB/KDDockWidgets.git "$KDDOCK_BRANCH"
	clone extra-cmake-modules https://github.com/KDE/extra-cmake-modules.git "$ECM_BRANCH"
	clone karchive https://github.com/KDE/karchive.git "$KARCHIVE_BRANCH"
	clone genalyzer https://github.com/analogdevicesinc/genalyzer.git "$GENALYZER_BRANCH"
	clone qcoro https://github.com/qcoro/qcoro.git "$QCORO_BRANCH"
	install_framework libiio iio iio.h \
		-DWITH_TESTS=OFF -DWITH_DOC=OFF -DWITH_MATLAB_BINDINGS=OFF \
		-DCSHARP_BINDINGS=OFF -DPYTHON_BINDINGS=OFF -DINSTALL_UDEV_RULE=OFF \
		-DWITH_SERIAL_BACKEND=ON -DWITH_USB_BACKEND=ON -DWITH_NETWORK_BACKEND=ON
	install_framework libad9361 ad9361 ad9361.h
	install_framework libad9166 ad9166 ad9166.h
	# Patch only the dependency checkout we created. Replacements are idempotent.
	python3 - "$STAGING_AREA/src/qwt" "$STAGING_AREA_DEPS" <<'PY'
import pathlib, re, sys
root, prefix = pathlib.Path(sys.argv[1]), sys.argv[2]
path = root / 'qwtconfig.pri'
text = path.read_text().replace('/usr/local/qwt-$$QWT_VERSION-ma', prefix)
for option in ('QwtDesigner', 'QwtExamples', 'QwtPlayground', 'QwtTests', 'QwtFramework'):
    text = re.sub(r'^(\s*)(QWT_CONFIG\s*\+=\s*' + option + r')\s*$',
                  r'\1# \2', text, flags=re.MULTILINE)
path.write_text(text)
path = root / 'src/src.pro'
text = path.read_text().replace('qwtLibraryTarget(qwt)', 'qwtLibraryTarget(qwt_scopy)')
text = re.sub(r'^macx: QWT_SONAME=.*\n?', '', text, flags=re.MULTILINE)
if 'macx: QMAKE_SONAME_PREFIX' not in text:
    text += '\nmacx: QMAKE_SONAME_PREFIX = @rpath\n'
path.write_text(text)
PY
	mkdir -p "$STAGING_AREA/build/qwt"
	(
		cd "$STAGING_AREA/build/qwt"
		"$QMAKE_BIN" -recursive "$STAGING_AREA/src/qwt/qwt.pro" "QMAKE_APPLE_DEVICE_ARCHS=$ARCH" \
			"QMAKE_CXXFLAGS+=$QT_CXX_FLAGS" -after \
			"CONFIG-=link_prl" "QMAKE_LIBS_OPENGL=-framework OpenGL"
		make -j"$JOBS"
		make install
	)
	install_cmake libtinyiiod -DBUILD_EXAMPLES=OFF
	install_cmake KDDockWidgets -DKDDockWidgets_QT6=ON -DKDDockWidgets_FRONTENDS=qtwidgets
	install_cmake extra-cmake-modules -DBUILD_TESTING=OFF -DBUILD_HTML_DOCS=OFF -DBUILD_MAN_DOCS=OFF
	install_cmake karchive -DBUILD_TESTING=OFF
	install_cmake genalyzer -DBUILD_TESTING=OFF -DBUILD_SHARED_LIBS=ON
	install_cmake qcoro -DQCORO_BUILD_EXAMPLES=OFF -DQCORO_BUILD_TESTING=OFF \
		-DBUILD_TESTING=OFF -DQCORO_WITH_QTWEBSOCKETS=OFF -DQCORO_WITH_QTQUICK=OFF \
		-DQCORO_WITH_QML=OFF -DBUILD_SHARED_LIBS=ON
fi

if [[ $MODE != --deps-only ]]; then
	cmake -S "$REPO_SRC" -B "$BUILDDIR" -G Ninja \
		-DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
		-DCMAKE_CXX_FLAGS="-I\"$STAGING_AREA/qt-include\"" \
		-DSCOPY_QT_INCLUDE_DIR="$STAGING_AREA/qt-include" \
		-DCMAKE_PREFIX_PATH="$PREFIX_PATH" -DCMAKE_INSTALL_PREFIX="$STAGING_AREA/scopy-install" \
		-DPython3_EXECUTABLE="$STAGING_AREA/venv/bin/python3" \
		-DCMAKE_BUILD_WITH_INSTALL_RPATH=OFF \
		-DCMAKE_INSTALL_RPATH="$STAGING_AREA_DEPS/lib;$QT/lib;@executable_path/../Frameworks" \
		-DENABLE_TESTING=ON -DENABLE_ALL_PACKAGES=ON -DENABLE_PLUGIN_ADC=OFF \
		-DWITH_SIGROK=OFF -DWITH_PYTHON=OFF
	cmake --build "$BUILDDIR" --parallel "$JOBS"
	file "$BUILDDIR/Scopy.app/Contents/MacOS/Scopy"
	echo "Built: $BUILDDIR/Scopy.app (local dependencies must remain in place)"
fi
