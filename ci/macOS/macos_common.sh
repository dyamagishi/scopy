#!/bin/bash
# Shared configuration and build helpers for CI and developer machines.
# shellcheck source=ci/macOS/macos_config.sh
source "$(dirname "${BASH_SOURCE[0]}")/macos_config.sh"

require_native_macos() {
	[[ $(uname -s) == Darwin ]] || { echo "macOS is required" >&2; return 1; }
	if [[ $(sysctl -in sysctl.proc_translated 2>/dev/null || true) == 1 ]]; then
		echo "Use a native terminal, not Rosetta." >&2
		return 1
	fi
	[[ $ARCH == "$(uname -m)" ]] || { echo "Cross-compilation is not supported; use a native $ARCH runner." >&2; return 1; }
	xcrun --find clang >/dev/null
	xcrun --sdk macosx --show-sdk-path >/dev/null
}

setup_build_environment() {
	BREW_PREFIX=$(brew --prefix)
	export PATH="$STAGING_AREA/venv/bin:$BREW_PREFIX/bin:$QT_PATH:$PATH"
	export PKG_CONFIG_PATH="$STAGING_AREA_DEPS/lib/pkgconfig:$BREW_PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
	PREFIX_PATH="$QT;$STAGING_AREA_DEPS;$BREW_PREFIX"
	QT_INCLUDE_DIR="$STAGING_AREA/qt-include"
	[[ -x $QMAKE_BIN ]] || { echo "Qt not found at $QT; run install_macos_deps.sh first." >&2; return 1; }
	local module
	for module in Qt3DCore QtScxml QtShaderTools; do
		[[ -d "$QT/lib/$module.framework" ]] || {
			echo "Missing Qt module $module; run install_macos_deps.sh first." >&2; return 1;
		}
	done
	mkdir -p "$QT_INCLUDE_DIR"
	local framework name
	for framework in "$QT"/lib/*.framework; do
		[[ -d $framework ]] || continue
		name=$(basename "$framework" .framework)
		# These aliases are generated, not SDK or Homebrew files.
		ln -sfn "$framework/Headers" "$QT_INCLUDE_DIR/$name"
	done
}

clone() {
	local name=$1 url=$2 ref=$3
	if [[ ! -d "$STAGING_AREA/src/$name" ]]; then
		git clone --depth 1 --branch "$ref" "$url" "$STAGING_AREA/src/$name"
	fi
	# Reuse checkouts without resetting, cleaning, or updating user changes.
	git -C "$STAGING_AREA/src/$name" rev-parse HEAD
}

configure_build() {
	local name=$1
	shift
	cmake -S "$STAGING_AREA/src/$name" -B "$STAGING_AREA/build/$name" -G Ninja \
		-DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
		-DCMAKE_OSX_ARCHITECTURES="$ARCH" -DCMAKE_OSX_DEPLOYMENT_TARGET="$MACOSX_DEPLOYMENT_TARGET" \
		-DCMAKE_PREFIX_PATH="$PREFIX_PATH" \
		-DCMAKE_PROJECT_INCLUDE="$REPO_SRC/cmake/Modules/ScopyMacOSQtCompat.cmake" \
		-DCMAKE_CXX_FLAGS="-I\"$QT_INCLUDE_DIR\"" -DSCOPY_QT_INCLUDE_DIR="$QT_INCLUDE_DIR" \
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
	# Upstream install rules target /Library/Frameworks; use the shared prefix.
	mkdir -p "$STAGING_AREA_DEPS/include" "$STAGING_AREA_DEPS/lib/pkgconfig"
	cp "$STAGING_AREA/src/$name/$header" "$STAGING_AREA_DEPS/include/"
	ditto "$STAGING_AREA/build/$name/$framework.framework" "$STAGING_AREA_DEPS/lib/$framework.framework"
	cp "$STAGING_AREA/build/$name/lib$framework.pc" "$STAGING_AREA_DEPS/lib/pkgconfig/"
}
