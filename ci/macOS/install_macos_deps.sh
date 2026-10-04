#!/bin/bash
# Install and incrementally build macOS dependencies (same entry point in CI).
set -euo pipefail
if [[ ${1:-} == --help ]]; then
	echo "Usage: bash ci/macOS/install_macos_deps.sh"
	echo "Overrides: STAGING_AREA, STAGING_AREA_DEPS, QT, QT_VERSION, JOBS"
	exit 0
fi
[[ $# == 0 ]] || { echo "Unexpected argument: $1" >&2; exit 1; }
# shellcheck source=ci/macOS/macos_common.sh
source "$(dirname "$0")/macos_common.sh"
require_native_macos
mkdir -p "$STAGING_AREA/src" "$STAGING_AREA_DEPS"
BREW_PREFIX=$(brew --prefix)
export PATH="$STAGING_AREA/venv/bin:$BREW_PREFIX/bin:$PATH"
for formula in cmake ninja pkg-config libusb libserialport libxml2 fftw zstd; do
	brew list --versions "$formula" >/dev/null 2>&1 || brew install "$formula"
done
if [[ ! -x "$STAGING_AREA/venv/bin/python3" ]]; then
	python3 -m venv "$STAGING_AREA/venv"
fi
"$STAGING_AREA/venv/bin/python3" -m pip install 'aqtinstall==3.3.0' mako
QT_MODULES=()
QT_INSTALL_ARGS=(--outputdir "$QT_INSTALL_LOCATION" mac desktop "$QT_VERSION" clang_64)
if [[ -x $QMAKE_BIN ]]; then
	QT_INSTALL_ARGS+=(--noarchives)
	[[ -d "$QT/lib/Qt3DCore.framework" ]] || QT_MODULES+=(qt3d)
	[[ -d "$QT/lib/QtScxml.framework" ]] || QT_MODULES+=(qtscxml)
	[[ -d "$QT/lib/QtShaderTools.framework" ]] || QT_MODULES+=(qtshadertools)
else
	QT_MODULES=(qt3d qtscxml qtshadertools)
fi
if [[ ${#QT_MODULES[@]} -gt 0 ]]; then
	# Do not silently install somewhere else when the user specifies a custom QT.
	[[ $QT == "$QT_INSTALL_LOCATION/$QT_VERSION/macos" ]] || {
		echo "Custom QT directory is incomplete: $QT; install qt3d, qtscxml, and qtshadertools." >&2; exit 1;
	}
	aqt install-qt "${QT_INSTALL_ARGS[@]}" -m "${QT_MODULES[@]}"
fi
setup_build_environment
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
	-DWITH_TESTS=OFF -DWITH_MATLAB_BINDINGS=OFF -DCSHARP_BINDINGS=OFF \
	-DPYTHON_BINDINGS=OFF -DINSTALL_UDEV_RULE=OFF -DWITH_SERIAL_BACKEND=ON \
	-DWITH_USB_BACKEND=ON -DWITH_NETWORK_BACKEND=ON
install_framework libad9361 ad9361 ad9361.h
install_framework libad9166 ad9166 ad9166.h
# Qwt's qmake build needs a prefix/library-name patch. Work on a generated
# source copy so the dependency checkout, including user edits, stays intact.
QWT_SOURCE="$STAGING_AREA/build/qwt-source"
mkdir -p "$QWT_SOURCE"
rsync -a --exclude=.git "$STAGING_AREA/src/qwt/" "$QWT_SOURCE/"
python3 - "$QWT_SOURCE" "$STAGING_AREA_DEPS" <<'PY'
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
QT_CXX_FLAGS=
if [[ $ARCH == arm64 ]]; then
	QT_CXX_FLAGS="-include arm_acle.h"
fi
mkdir -p "$STAGING_AREA/build/qwt"
(
	cd "$STAGING_AREA/build/qwt" || exit 1
	"$QMAKE_BIN" -recursive "$QWT_SOURCE/qwt.pro" "QMAKE_APPLE_DEVICE_ARCHS=$ARCH" \
		"QMAKE_MACOSX_DEPLOYMENT_TARGET=$MACOSX_DEPLOYMENT_TARGET" \
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
# Record exactly which reused source snapshots produced the dependencies.
{
	brew list --versions cmake ninja libusb libserialport libxml2 fftw zstd
	for source_dir in "$STAGING_AREA/src/"*; do
		[[ -d $source_dir/.git ]] || continue
		printf '%s %s' "$(basename "$source_dir")" "$(git -C "$source_dir" rev-parse HEAD)"
		if [[ -n $(git -C "$source_dir" status --porcelain) ]]; then
			printf ' (dirty checkout)'
		fi
		printf '\n'
	done
} > "$STAGING_AREA/build-status"
echo "Dependencies built for $ARCH in $STAGING_AREA_DEPS"
