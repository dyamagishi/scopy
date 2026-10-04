#!/bin/bash

# macOS Qt6 Packaging Script
# =====================================
# After the build is complete, this script packages the Scopy.app bundle by fixing library paths and bundling dependencies.
# It also creates a DMG installer and a ZIP archive for distribution.
# Usage: ./package_darwin.sh

set -ex
REPO_SRC=$(git rev-parse --show-toplevel)
source "$REPO_SRC/ci/macOS/macos_config.sh"

pushd "$BUILDDIR"

SCOPYPLUGINS=$(find "$BUILDDIR/Scopy.app/Contents/Resources/packages" -name "*.dylib" -type f)
SCOPYLIBS=$(find "$BUILDDIR/Scopy.app/Contents/Frameworks" -name "*.dylib" -type f)

IFS=$'\n' SEARCH_PATHS=($(find "$BUILDDIR/Scopy.app/Contents/Resources/packages" -name "plugins" -type d 2>/dev/null))
SEARCH_PATHS+=($STAGING_AREA_DEPS/lib)
SEARCH_PATHS+=($BUILDDIR/Scopy.app/Contents/Frameworks/)
PREFIXED_SEARCH_PATHS=()
for p in "${SEARCH_PATHS[@]}"; do
    PREFIXED_SEARCH_PATHS+=(--search-path "$p")
done
echo "### Copy DLLs to Frameworks folder"
cp -avR $STAGING_AREA_DEPS/lib/iio.framework Scopy.app/Contents/Frameworks/
# libiio's build bundle contains an empty top-level Tools directory when
# WITH_TESTS=OFF. It is not a valid sealed framework resource; remove only if empty.
if [ -d Scopy.app/Contents/Frameworks/iio.framework/Tools ] && [ ! -L Scopy.app/Contents/Frameworks/iio.framework/Tools ]; then
	rmdir Scopy.app/Contents/Frameworks/iio.framework/Tools
fi
cp -avR $STAGING_AREA_DEPS/lib/ad9361.framework Scopy.app/Contents/Frameworks/
cp -avR $STAGING_AREA_DEPS/lib/genalyzer.framework Scopy.app/Contents/Frameworks/
mkdir -p $BUILDDIR/Scopy.app/Contents/MacOS/plugins/resources

libqwtpath=${STAGING_AREA_DEPS}/lib/libqwt_scopy.6.4.0.dylib #hardcoded
libqwtid="$(otool -D ${libqwtpath} | tail -1)"
echo "=== Fixing libqwt"
# Only modify the bundled binaries, not the installed dependency library.
otool -L ${libqwtpath}
install_name_tool -change ${libqwtid} ${libqwtpath} ./Scopy.app/Contents/MacOS/Scopy
for dylib in ${SCOPYLIBS} ${SCOPYPLUGINS}
do
	[ -z "$(otool -L ${dylib} | grep libqwt_scopy.*dylib)" ] || install_name_tool -change ${libqwtid} ${libqwtpath} ${dylib}
	otool -L $dylib
done


iiorpath="$(otool -D ./Scopy.app/Contents/Frameworks/iio.framework/iio | grep @rpath)"
iioid=${iiorpath#"@rpath/"}

ad9361rpath="$(otool -D ./Scopy.app/Contents/Frameworks/ad9361.framework/ad9361 | grep @rpath)"
ad9361id=${ad9361rpath#"@rpath/"}

libusbpath="$(otool -L ./Scopy.app/Contents/Frameworks/iio.framework/iio | grep libusb | cut -d " " -f 1 | awk '{$1=$1};1')"
libusbid="$(echo ${libusbpath} | rev | cut -d "/" -f 1 | rev)"
cp ${libusbpath} ./Scopy.app/Contents/Frameworks/
chmod 755 ./Scopy.app/Contents/Frameworks/libusb*dylib

# Copy libm2k if it exists (M2K package is disabled but deps are still built)
m2kpath=${STAGING_AREA_DEPS}/lib/libm2k.?.?.?.dylib
if ls ${m2kpath} 1>/dev/null 2>&1; then
	m2krpath="$(otool -D ${m2kpath} | grep @rpath)"
	m2kid=${m2krpath#"@rpath/"}
	cp ${STAGING_AREA_DEPS}/lib/libm2k.?.?.?.dylib ./Scopy.app/Contents/Frameworks
	install_name_tool -id @executable_path/../Frameworks/${m2kid} ./Scopy.app/Contents/Frameworks/${m2kid}
fi

if ls "$STAGING_AREA_DEPS/lib/libsigrokdecode"* 1>/dev/null 2>&1; then
	echo "### Get python version"
	# Bundle the interpreter actually linked by sigrok, not Homebrew's latest
	# python3. Scopy and sigrok must use the same interpreter in one process.
	sigrok_library=$(find "$STAGING_AREA_DEPS/lib" -name 'libsigrokdecode*.dylib' -type f | head -1)
	pythonpath=$(otool -arch "$ARCH" -L "$sigrok_library" | awk '$1 ~ /Python.framework.*\/Python$/ {print $1; exit}')
	[ -f "$pythonpath" ] || { echo "Cannot resolve sigrok's Python framework: $pythonpath" >&2; exit 1; }
	pythonframework=${pythonpath%%/Python.framework/*}/Python.framework
	pyversion=${pythonpath%/Python}
	pyversion=${pyversion##*/}
	pythonidrpath="$(otool -arch "$ARCH" -D "$pythonpath" | tail -1)"

	if [ -z $pyversion ]; then
		echo "No Python paths found"
		exit 1
	fi
	echo " - Found python$pyversion at $pythonpath"
	pythonid=${pythonidrpath#*/Frameworks/}
	ditto "$pythonframework" Scopy.app/Contents/Frameworks/Python.framework
	# Homebrew omits the public framework symlinks required by codesign.
	pythonbundle="$BUILDDIR/Scopy.app/Contents/Frameworks/Python.framework"
	# Homebrew's site-packages symlink points outside the framework. Scopy needs
	# the standard library and its separately bundled decoders, not global packages.
	python_site="$pythonbundle/Versions/$pyversion/lib/python$pyversion/site-packages"
	if [ -L "$python_site" ]; then
		unlink "$python_site"
		mkdir -p "$python_site"
	fi
	ln -sfn "$pyversion" "$pythonbundle/Versions/Current"
	for entry in Python Resources Headers; do
		ln -sfn "Versions/Current/$entry" "$pythonbundle/$entry"
	done
	# Relocate the embedded Python launchers too, not only Scopy/sigrok's link.
	for executable in "$pythonbundle/Versions/$pyversion/bin/python$pyversion" \
		"$pythonbundle/Versions/$pyversion/Resources/Python.app/Contents/MacOS/Python"; do
		[ -f "$executable" ] || continue
		linked_python=$(otool -arch "$ARCH" -L "$executable" | awk '$1 ~ /Python.framework.*\/Python$/ {print $1; exit}')
		relative_python=$(python3 -c 'import os, sys; print(os.path.relpath(sys.argv[1], os.path.dirname(sys.argv[2])))' \
			"$pythonbundle/Versions/$pyversion/Python" "$executable")
		install_name_tool -change "$linked_python" "@loader_path/$relative_python" "$executable"
	done
fi

echo "=== Copying libsigrokdecode protocol decoders"
if [ -d $STAGING_AREA_DEPS/share/libsigrokdecode/decoders ]; then
	mkdir -p Scopy.app/Contents/Resources/decoders
	cp -R $STAGING_AREA_DEPS/share/libsigrokdecode/decoders/* Scopy.app/Contents/Resources/decoders/
fi

echo "### Fixing scopy libraries and plugins "
for dylib in ${SCOPYLIBS} ${SCOPYPLUGINS}
do
	echo "--- FIXING LIB: ${dylib##*/}"
	dylibbundler --no-codesign --overwrite-files --bundle-deps --create-dir \
		--fix-file $dylib \
		--dest-dir $BUILDDIR/Scopy.app/Contents/Frameworks/ \
		--install-path @executable_path/../Frameworks/ \
		"${PREFIXED_SEARCH_PATHS[@]}"
done

echo "### Fixing Genalyzer"
echo $STAGING_AREA_DEPS/lib | dylibbundler --no-codesign --overwrite-files --bundle-deps --create-dir \
	--fix-file $BUILDDIR/Scopy.app/Contents/Frameworks/genalyzer.framework/genalyzer \
	--dest-dir $BUILDDIR/Scopy.app/Contents/Frameworks/ \
	--install-path @executable_path/../Frameworks/ \
	--search-path $BUILDDIR/Scopy.app/Contents/Frameworks/

echo "### Fixing Scopy binary"
dylibbundler -ns -of -b \
	--fix-file $BUILDDIR/Scopy.app/Contents/MacOS/Scopy \
	--dest-dir $BUILDDIR/Scopy.app/Contents/Frameworks \
	--install-path @executable_path/../Frameworks \
	"${PREFIXED_SEARCH_PATHS[@]}"

echo "### Fixing the frameworks dylibbundler failed to copy"
echo "=== Fixing iio.framework"
install_name_tool -id @executable_path/../Frameworks/${iioid} ./Scopy.app/Contents/Frameworks/iio.framework/iio
install_name_tool -id @executable_path/../Frameworks/${iioid} ./Scopy.app/Contents/Frameworks/${iioid}
install_name_tool -change ${iiorpath} @executable_path/../Frameworks/${iioid} ./Scopy.app/Contents/MacOS/Scopy
for dylib in ${SCOPYLIBS} ${SCOPYPLUGINS}
do
	otool -L $dylib
	[ -z "$(otool -L ${dylib}| grep iio.framework)" ] && echo "SKIP ${dylib##*/}" || install_name_tool -change ${iiorpath} @executable_path/../Frameworks/${iioid} ${dylib}
done

echo "=== Fixing ad9361.framework"
install_name_tool -id @executable_path/../Frameworks/${ad9361id} ./Scopy.app/Contents/Frameworks/ad9361.framework/ad9361
install_name_tool -id @executable_path/../Frameworks/${ad9361id} ./Scopy.app/Contents/Frameworks/${ad9361id}
install_name_tool -change ${iiorpath} @executable_path/../Frameworks/${iioid} ./Scopy.app/Contents/Frameworks/${ad9361id}
if ls ./Scopy.app/Contents/Frameworks/libgnuradio-iio* 1>/dev/null 2>&1; then
	install_name_tool -change ${ad9361rpath} @executable_path/../Frameworks/${ad9361id} ./Scopy.app/Contents/Frameworks/libgnuradio-iio*
fi

echo "=== Fixing libusb"
install_name_tool -id @executable_path/../Frameworks/${libusbid} ./Scopy.app/Contents/Frameworks/${libusbid}
install_name_tool -change ${libusbpath} @executable_path/../Frameworks/${libusbid} ./Scopy.app/Contents/Frameworks/iio.framework/iio

if ls ./Scopy.app/Contents/Frameworks/libsigrokdecode* 1>/dev/null 2>&1; then
	echo "=== Fixing python"
	install_name_tool -id @executable_path/../Frameworks/${pythonid} ./Scopy.app/Contents/Frameworks/${pythonid}
	python_sigrokdecode=$(otool -L ./Scopy.app/Contents/Frameworks/libsigrokdecode* | grep -i python | cut -d " " -f 1 | awk '{$1=$1};1')
	[ -n "${python_sigrokdecode}" ] && install_name_tool -change ${python_sigrokdecode} @executable_path/../Frameworks/${pythonid} ./Scopy.app/Contents/Frameworks/libsigrokdecode*
	python_scopy=$(otool -L ./Scopy.app/Contents/MacOS/Scopy | grep -i python | cut -d " " -f 1 | awk '{$1=$1};1')
	[ -n "${python_scopy}" ] && install_name_tool -change ${python_scopy} @executable_path/../Frameworks/${pythonid} ./Scopy.app/Contents/MacOS/Scopy
	for dylib in ${SCOPYLIBS} ${SCOPYPLUGINS}
	do
		otool -L $dylib
		python=$(otool -L ${dylib} | grep -i python | cut -d " " -f 1 | awk '{$1=$1};1');
		[ -z "${python}" ] && echo "SKIP ${dylib##*/}" || install_name_tool -change ${python} @executable_path/../Frameworks/${pythonid} ${dylib}
	done
fi

echo "=== Fixing libserialport"
libserialportpath="$(otool -L ./Scopy.app/Contents/Frameworks/iio.framework/iio | grep libserialport | cut -d " " -f 1 | awk '{$1=$1};1')"
libserialportid="$(echo ${libserialportpath} | rev | cut -d "/" -f 1 | rev)"
install_name_tool -change ${libserialportpath} @executable_path/../Frameworks/${libserialportid} ./Scopy.app/Contents/Frameworks/iio.framework/iio

# Fix libm2k references if it was copied
if ls ./Scopy.app/Contents/Frameworks/libm2k.?.?.?.dylib 1>/dev/null 2>&1; then
	install_name_tool -change ${iiorpath} @executable_path/../Frameworks/${iioid} ./Scopy.app/Contents/Frameworks/libm2k.?.?.?.dylib
fi

if ls ./Scopy.app/Contents/Frameworks/libgnuradio-m2k* 1>/dev/null 2>&1; then
	install_name_tool -change ${iiorpath} @executable_path/../Frameworks/${iioid} ./Scopy.app/Contents/Frameworks/libgnuradio-m2k*
	if [ -n "${m2kid:-}" ]; then
		install_name_tool -change ${m2krpath} @executable_path/../Frameworks/${m2kid} ./Scopy.app/Contents/Frameworks/libgnuradio-m2k*
	fi
fi

if ls ./Scopy.app/Contents/Frameworks/libgnuradio-scopy* 1>/dev/null 2>&1; then
	install_name_tool -change ${iiorpath} @executable_path/../Frameworks/${iioid} ./Scopy.app/Contents/Frameworks/libgnuradio-scopy*
	if [ -n "${m2kid:-}" ]; then
		install_name_tool -change ${m2krpath} @executable_path/../Frameworks/${m2kid} ./Scopy.app/Contents/Frameworks/libgnuradio-scopy*
	fi
fi

echo "=== Fixing iio-emu + libtinyiiod"
cp $REPO_SRC/iio-emu/build/iio-emu ./Scopy.app/Contents/MacOS/
dylibbundler -ns -of -b \
	--fix-file $BUILDDIR/Scopy.app/Contents/MacOS/iio-emu \
	--dest-dir $BUILDDIR/Scopy.app/Contents/Frameworks/ \
	--install-path @executable_path/../Frameworks/ \
	"${PREFIXED_SEARCH_PATHS[@]}"

echo "=== Adding Qt6 3D plugins"
QT6_PLUGINS_PATH="${QT}/plugins"
for plugin_dir in renderers sceneparsers; do
	if [ -d "$QT6_PLUGINS_PATH/$plugin_dir" ]; then
		mkdir -p "$BUILDDIR/Scopy.app/Contents/PlugIns/$plugin_dir"
		# Do not copy debug symbol bundles into the runtime application.
		find "$QT6_PLUGINS_PATH/$plugin_dir" -maxdepth 1 -name '*.dylib' -type f \
			-exec cp {} "$BUILDDIR/Scopy.app/Contents/PlugIns/$plugin_dir/" \;
	fi
done

echo "=== Bundle the Qt libraries & Create Scopy.dmg"
DEPLOY_ARGS=(-verbose=3)
while IFS= read -r -d '' library; do
	DEPLOY_ARGS+=("-executable=$library")
done < <(find Scopy.app/Contents/PlugIns -name '*.dylib' -type f -print0)
macdeployqt Scopy.app "${DEPLOY_ARGS[@]}"

echo "=== Removing build-machine and duplicated LC_RPATH"
# This is a packaging transformation, not part of the read-only bundle audit.
while IFS= read -r -d '' binary; do
	file -b "$binary" | grep -q 'Mach-O' || continue
	seen_paths=()
	# Select the native slice so universal Qt binaries do not repeat entries.
	while IFS= read -r path; do
		case "$path" in
			/System/Library/*|/usr/lib/*) ;;
			/*) install_name_tool -delete_rpath "$path" "$binary" ;;
			*)
				duplicate=false
				for seen in "${seen_paths[@]}"; do
					[ "$seen" != "$path" ] || duplicate=true
				done
				if [ "$duplicate" = true ]; then
					install_name_tool -delete_rpath "$path" "$binary"
				else
					seen_paths+=("$path")
				fi
				;;
		esac
	done < <(otool -arch "$ARCH" -l "$binary" | awk '/cmd LC_RPATH/ {rpath=1} rpath && /path .*\(offset/ {sub(/^ *path /, ""); sub(/ \(offset.*$/, ""); print; rpath=0}')
done < <(find Scopy.app -type f ! -path '*.dSYM/*' -print0)

echo "=== Ad-hoc code signing"
# Python extension modules are stored as framework resources. --deep does not
# re-sign them as nested code after macdeployqt changes their library paths.
while IFS= read -r -d '' module; do
	codesign --force --sign - "$module"
done < <(find Scopy.app -name '*.so' -type f -print0)
codesign --force --deep --sign - Scopy.app
codesign --verify --deep --strict Scopy.app
while IFS= read -r -d '' module; do
	codesign --verify --strict "$module"
done < <(find Scopy.app -name '*.so' -type f -print0)
python3 "$REPO_SRC/ci/macOS/verify_bundle.py" Scopy.app "$ARCH"

echo "=== Creating ScopyApp.zip"
ditto -c -k --keepParent Scopy.app ScopyApp.zip
macdeployqt Scopy.app -dmg -verbose=3
codesign --verify --deep --strict Scopy.app
popd
