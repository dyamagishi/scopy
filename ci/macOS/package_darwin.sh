#!/bin/bash
# Package a separate copy; leave the incremental development bundle untouched.
set -euo pipefail
if [[ ${1:-} == --help ]]; then
	echo "Usage: bash ci/macOS/package_darwin.sh"
	echo "Outputs: BUILDDIR/package/Scopy.app, BUILDDIR/ScopyApp.zip, BUILDDIR/Scopy.dmg"
	exit 0
fi
[[ $# == 0 ]] || { echo "Unexpected argument: $1" >&2; exit 1; }
# shellcheck source=ci/macOS/macos_common.sh
source "$(dirname "$0")/macos_common.sh"
require_native_macos
setup_build_environment
[[ -d "$BUILDDIR/Scopy.app" ]] || { echo "Run build_macos.sh first." >&2; exit 1; }
[[ -x "$STAGING_AREA/build/iio-emu/iio-emu" ]] || { echo "IIO-Emulator has not been built." >&2; exit 1; }
APP="$BUILDDIR/package/Scopy.app"
# ditto merges directories; reject reusing a packaged bundle to avoid stale files.
[[ ! -e $APP ]] || { echo "Package destination exists: $APP; move it aside before repackaging." >&2; exit 1; }
mkdir -p "$BUILDDIR/package"
ditto "$BUILDDIR/Scopy.app" "$APP"
cp "$STAGING_AREA/build/iio-emu/iio-emu" "$APP/Contents/MacOS/"
mkdir -p "$APP/Contents/PlugIns"
for plugin_dir in renderers sceneparsers; do
	if [[ -d "$QT/plugins/$plugin_dir" ]]; then
		mkdir -p "$APP/Contents/PlugIns/$plugin_dir"
		while IFS= read -r -d '' plugin; do
			cp "$plugin" "$APP/Contents/PlugIns/$plugin_dir/"
		done < <(find "$QT/plugins/$plugin_dir" -maxdepth 1 -name '*.dylib' -type f -print0)
	fi
done
# macdeployqt follows non-Qt dependencies too. Tell it about every plugin and
# helper executable, not only the main executable (plugins are loaded dynamically).
DEPLOY_ARGS=(-always-overwrite -verbose=2)
while IFS= read -r -d '' library; do
	DEPLOY_ARGS+=("-executable=$library")
done < <(find "$APP/Contents/Frameworks" "$APP/Contents/Resources/packages" "$APP/Contents/PlugIns" -name '*.dylib' -type f -print0)
DEPLOY_ARGS+=("-executable=$APP/Contents/MacOS/iio-emu")
"$QT/bin/macdeployqt" "$APP" "${DEPLOY_ARGS[@]}"
# Any missing/unbundled dependency fails packaging, rather than producing an app
# that happens to work because Qt/Homebrew exists on the build machine.
python3 "$REPO_SRC/ci/macOS/verify_bundle.py" "$APP" "$ARCH" --sanitize-rpaths
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
ditto -c -k --keepParent "$APP" "$BUILDDIR/ScopyApp.zip"
hdiutil create -ov -format UDZO -volname Scopy -srcfolder "$BUILDDIR/package" "$BUILDDIR/Scopy.dmg"
