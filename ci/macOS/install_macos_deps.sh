#!/bin/bash

# macOS Qt6 Build Script
# =====================================
# Build and install all the dependencies needed for Scopy Qt6 on macOS
# Usage: ./install_macos_deps.sh

set -ex
REPO_SRC=$(git rev-parse --show-toplevel)
source "$REPO_SRC/ci/macOS/macos_config.sh"

# Cache configuration
CACHE_BASE_DIR="${PIPELINE_WORKSPACE}"
GIT_CACHE_DIR="${CACHE_BASE_DIR}/.git-cache"
HOMEBREW_CACHE_DIR="${CACHE_BASE_DIR}/.homebrew-cache"
CACHE_SIZE_WARNING_GB=8

# Cache size monitoring
check_cache_sizes() {
    if [ -d "$CACHE_BASE_DIR" ]; then
        local total_size_gb=$(du -sg "$CACHE_BASE_DIR" 2>/dev/null | cut -f1 || echo "0")
        echo "Total cache size: ${total_size_gb}GB"

        if [ "$total_size_gb" -gt "$CACHE_SIZE_WARNING_GB" ]; then
            echo "WARNING: Cache size (${total_size_gb}GB) approaching Azure DevOps limits"
        fi
    fi
}


# Cache cleanup function
cleanup_old_caches() {
    echo "Cleaning up old cache directories..."

    # Only operate inside an explicitly configured cache workspace.
    if [ "${CACHING_ENABLED}" == "true" ] && [ -n "$CACHE_BASE_DIR" ] && [ -d "$CACHE_BASE_DIR" ]; then
        find "$CACHE_BASE_DIR" -name "*.tmp" -type d -mtime +7 -exec rm -rf {} + 2>/dev/null || true
        find "$CACHE_BASE_DIR" -name "*.old" -type d -mtime +7 -exec rm -rf {} + 2>/dev/null || true
    fi
}

setup_homebrew_cache() {
	if [ "${CACHING_ENABLED}" == "true" ]; then
		echo "Setting up Homebrew cache..."
        mkdir -p "$HOMEBREW_CACHE_DIR"

        if [ "${HOMEBREW_PACKAGES_CACHE}" == "true" ]; then
                echo "Homebrew cache found, restoring cached packages"
                # Validate cache isn't corrupted
                if [ -d "$HOMEBREW_CACHE_DIR" ] && [ "$(ls -A "$HOMEBREW_CACHE_DIR" 2>/dev/null)" ]; then
                        echo "Found cached Homebrew packages in $HOMEBREW_CACHE_DIR"
                        export HOMEBREW_CACHE_ENABLED=true
                        export HOMEBREW_NO_AUTO_UPDATE=1
                else
                        echo "Homebrew cache directory empty - downloading fresh packages"
                        export HOMEBREW_CACHE_ENABLED=false
                fi
        else
                echo "No Homebrew cache - downloading fresh packages"
                export HOMEBREW_CACHE_ENABLED=false
        fi

        export HOMEBREW_CACHE="$HOMEBREW_CACHE_DIR"
	fi
}

setup_git_cache() {
	if [ "${CACHING_ENABLED}" == "true" ]; then
		echo "Setting up Git cache..."
		mkdir -p "$GIT_CACHE_DIR"

		if [ "${GIT_REPOS_CACHE}" == "true" ]; then
			echo "Git repositories cache found, restoring cached repositories"
			# Validate cache isn't corrupted
			if [ -d "$GIT_CACHE_DIR" ] && [ "$(ls -A "$GIT_CACHE_DIR" 2>/dev/null)" ]; then
				export GIT_CACHE_ENABLED=true
			else
				echo "Git cache directory empty - cloning fresh"
				export GIT_CACHE_ENABLED=false
			fi
		else
			echo "No Git cache - cloning fresh repositories"
			export GIT_CACHE_ENABLED=false
		fi
	fi
}

setup_dependencies_cache() {
    if [ "${CACHING_ENABLED}" == "true" ] && [ "${BUILT_DEPS_CACHE}" == "true" ]; then
        echo "Built dependencies cache found, restoring cached dependencies"
        if [ -d "$STAGING_AREA_DEPS" ] && [ "$(ls -A "$STAGING_AREA_DEPS" 2>/dev/null)" ]; then
            echo "Found cached dependencies in $STAGING_AREA_DEPS"
            export DEPENDENCIES_CACHED=true
        else
            echo "Dependencies cache directory empty - building fresh"
            export DEPENDENCIES_CACHED=false
        fi
    else
        echo "No dependencies cache - building fresh"
        export DEPENDENCIES_CACHED=false
    fi
}

OS_VERSION=${1:-$(sw_vers -productVersion)}
echo "MacOS version $OS_VERSION"

# Qt6 via aqtinstall -- no Homebrew Qt package needed
# ghr is deliberately absent: it was never invoked (releases use actions/upload-artifact)
# and it has no x86_64 bottle, so on Intel it source-builds its `go` build dependency.
PACKAGES="pkg-config cmake fftw bison gettext autoconf automake libzip libusb doxygen wget gnu-sed dylibbundler libxml2"

install_packages() {
	# Do not remove global Python symlinks or uninstall the user's CMake.
	macos_version=$(sw_vers -productVersion)
	major_version=$(echo "$macos_version" | cut -d '.' -f 1)
	if [ "${CACHING_ENABLED}" = "true" ] && [ "${HOMEBREW_CACHE_ENABLED}" = "true" ]; then
		export HOMEBREW_NO_AUTO_UPDATE=1
	fi
	if [ "$major_version" -gt 12 ]; then
		PACKAGES="$PACKAGES libtool"
	fi
	for package in $PACKAGES; do
		brew list --versions "$package" >/dev/null 2>&1 || brew install "$package"
	done
	mkdir -p "$STAGING_AREA"
	if [ ! -x "$STAGING_AREA/venv/bin/python3" ]; then
		python3 -m venv "$STAGING_AREA/venv"
	fi
	export PATH="$STAGING_AREA/venv/bin:$PATH"
	python3 -m pip install mako 'aqtinstall==3.3.0'
}

install_qt() {
	echo "### Installing Qt $QT_VERSION via aqtinstall"
	local modules=() args=(--outputdir "$QT_INSTALL_LOCATION" mac desktop "$QT_VERSION" clang_64)
	if [ -x "$QMAKE_BIN" ]; then
		args+=(--noarchives)
		[ -d "$QT/lib/Qt3DCore.framework" ] || modules+=(qt3d)
		[ -d "$QT/lib/QtScxml.framework" ] || modules+=(qtscxml)
		[ -d "$QT/lib/QtShaderTools.framework" ] || modules+=(qtshadertools)
	else
		modules=(qt3d qtscxml qtshadertools)
	fi
	if [ ${#modules[@]} -gt 0 ]; then
		[ "$QT" = "$QT_INSTALL_LOCATION/$QT_VERSION/macos" ] || {
			echo "Install qt3d, qtscxml and qtshadertools into the custom QT path: $QT" >&2; exit 1;
		}
		aqt install-qt "${args[@]}" -m "${modules[@]}"
	fi
}

export_paths(){
	BREW_PREFIX="$(brew --prefix)"
	export PATH="$BREW_PREFIX/bin:$PATH"
	export PATH="$BREW_PREFIX/opt/bison/bin:$PATH"
	export PATH="${QT_PATH}:$PATH"
	export PKG_CONFIG_PATH="$PKG_CONFIG_PATH:$BREW_PREFIX/opt/libzip/lib/pkgconfig"
	export PKG_CONFIG_PATH="$PKG_CONFIG_PATH:$BREW_PREFIX/opt/libffi/lib/pkgconfig"
	export PKG_CONFIG_PATH="$PKG_CONFIG_PATH:$STAGING_AREA_DEPS/lib/pkgconfig"

	# Refresh generated header aliases after Qt installation.
	mkdir -p "$SCOPY_QT_INCLUDE_DIR"
	for framework in "$QT"/lib/*.framework; do
		[ -d "$framework" ] || continue
		ln -sfn "$framework/Headers" "$SCOPY_QT_INCLUDE_DIR/$(basename "$framework" .framework)"
	done
	QMAKE="$QMAKE_BIN"
	CMAKE_BIN="$(command -v cmake)"
	CMAKE_OPTS="-DCMAKE_PREFIX_PATH=$STAGING_AREA_DEPS -DCMAKE_INSTALL_PREFIX=$STAGING_AREA_DEPS -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DCMAKE_OSX_ARCHITECTURES=$ARCH -DCMAKE_OSX_DEPLOYMENT_TARGET=$MACOSX_DEPLOYMENT_TARGET"
	CMAKE="$CMAKE_BIN ${CMAKE_OPTS[*]}"

	echo -- USING CMAKE COMMAND:
	echo $CMAKE
	echo -- USING QT: $QT_PATH
	echo -- USING QMAKE: $QMAKE
	echo -- PATH: $PATH
	echo -- PKG_CONFIG_PATH: $PKG_CONFIG_PATH
}

clone_repository() {
	local url=$1 ref=$2 directory=$3
	if [ ! -d "$directory" ]; then
		git clone --recursive "$url" -b "$ref" "$directory"
	fi
	# Reuse existing checkouts without resetting user changes.
	git -C "$directory" rev-parse HEAD
}

clone() {
	echo "#######CLONE#######"
	mkdir -p "$STAGING_AREA"
	pushd "$STAGING_AREA"

	if [ "${CACHING_ENABLED}" == "true" ] && [ "$GIT_CACHE_ENABLED" == "true" ]; then
		echo "Using cached repositories..."
		if [ -d "$GIT_CACHE_DIR" ] && [ "$(ls -A "$GIT_CACHE_DIR" 2>/dev/null)" ]; then
			for cached_repo in "$GIT_CACHE_DIR"/*; do
				[ -d "$cached_repo" ] || continue
				[ -e "$(basename "$cached_repo")" ] || cp -R "$cached_repo" .
			done
		else
			export GIT_CACHE_ENABLED=false
		fi
	else
		export GIT_CACHE_ENABLED=false
	fi

	clone_repository https://github.com/sigrokproject/libserialport "$LIBSERIALPORT_BRANCH" libserialport
	clone_repository https://github.com/analogdevicesinc/libiio.git "$LIBIIO_VERSION" libiio
	clone_repository https://github.com/analogdevicesinc/libad9361-iio.git "$LIBAD9361_BRANCH" libad9361
	clone_repository https://github.com/analogdevicesinc/libad9166-iio.git "$LIBAD9166_BRANCH" libad9166
	clone_repository https://github.com/analogdevicesinc/libm2k.git "$LIBM2K_BRANCH" libm2k
	clone_repository https://github.com/cseci/qwt.git "$QWT_BRANCH" qwt
	clone_repository https://github.com/analogdevicesinc/libtinyiiod.git "$LIBTINYIIOD_BRANCH" libtinyiiod
	clone_repository https://github.com/KDAB/KDDockWidgets.git "$KDDOCK_BRANCH" KDDockWidgets
	clone_repository https://github.com/KDE/extra-cmake-modules.git "$ECM_BRANCH" extra-cmake-modules
	clone_repository https://github.com/KDE/karchive.git "$KARCHIVE_BRANCH" karchive
	clone_repository https://github.com/analogdevicesinc/genalyzer.git "$GENALYZER_BRANCH" genalyzer
	clone_repository https://github.com/qcoro/qcoro.git "$QCORO_BRANCH" qcoro

	DEPENDENCY_REPOS="libserialport libiio libad9361 libad9166 libm2k qwt libtinyiiod KDDockWidgets extra-cmake-modules karchive genalyzer qcoro"
	if [ "${CACHING_ENABLED}" == "true" ]; then
		mkdir -p "$GIT_CACHE_DIR"
		for repo in $DEPENDENCY_REPOS; do
			[ -e "$GIT_CACHE_DIR/$repo" ] || cp -R "$repo" "$GIT_CACHE_DIR/"
		done
	fi
	popd
}

generate_status_file(){
	# Generate build status info for the about page
	BUILD_STATUS_FILE=${REPO_SRC}/build-status
	brew list --versions $PACKAGES > "$BUILD_STATUS_FILE"
}

save_version_info() {
	echo "$(basename -a "$(git config --get remote.origin.url)") - $(git rev-parse --abbrev-ref HEAD) - $(git rev-parse --short HEAD)" \
	>> "$BUILD_STATUS_FILE"
}

build_with_cmake() {
	echo $PWD
	BUILD_FOLDER=$PWD/build
	mkdir -p "$BUILD_FOLDER"
	cd "$BUILD_FOLDER"
	# Keep the existing Makefiles generator and dependency-local build directory.
	$CMAKE $CURRENT_BUILD_CMAKE_OPTS ../
	make $JOBS
	CURRENT_BUILD_CMAKE_OPTS=""
}

build_libserialport(){
	CURRENT_BUILD=libserialport
	pushd "$STAGING_AREA/$CURRENT_BUILD"
	save_version_info
	./autogen.sh
	./configure --prefix "$STAGING_AREA_DEPS"
	make $JOBS
	make install
	popd
}

build_libiio() {
	echo "### Building libiio - version $LIBIIO_VERSION"
	CURRENT_BUILD=libiio
	pushd $STAGING_AREA/libiio
	save_version_info
	CURRENT_BUILD_CMAKE_OPTS="\
		-DWITH_TESTS:BOOL=OFF \
		-DWITH_DOC:BOOL=OFF \
		-DHAVE_DNS_SD:BOOL=ON \
		-DENABLE_DNS_SD:BOOL=ON \
		-DWITH_MATLAB_BINDINGS:BOOL=OFF \
		-DCSHARP_BINDINGS:BOOL=OFF \
		-DPYTHON_BINDINGS:BOOL=OFF \
		-DINSTALL_UDEV_RULE:BOOL=OFF \
		-DWITH_SERIAL_BACKEND:BOOL=ON \
		-DWITH_NETWORK_BACKEND=ON \
		-DENABLE_IPV6:BOOL=OFF \
		"
	build_with_cmake

	# manually install framework
	mkdir -p $STAGING_AREA_DEPS/include
	mkdir -p $STAGING_AREA_DEPS/lib/pkgconfig
	cp -v $STAGING_AREA/libiio/iio.h $STAGING_AREA_DEPS/include
	cp -avR $STAGING_AREA/libiio/build/iio.framework $STAGING_AREA_DEPS/lib
	cp -v $STAGING_AREA/libiio/build/libiio.pc $STAGING_AREA_DEPS/lib/pkgconfig
	popd
}


build_libad9361() {
	echo "### Building libad9361 - branch $LIBAD9361_BRANCH"
	CURRENT_BUILD=libad9361-iio
	pushd $STAGING_AREA/libad9361
	save_version_info
	build_with_cmake

	# manually install framework
	mkdir -p $STAGING_AREA_DEPS/include
	mkdir -p $STAGING_AREA_DEPS/lib/pkgconfig
	cp -v $STAGING_AREA/libad9361/ad9361.h $STAGING_AREA_DEPS/include
	cp -avR $STAGING_AREA/libad9361/build/ad9361.framework $STAGING_AREA_DEPS/lib
	cp -v $STAGING_AREA/libad9361/build/libad9361.pc $STAGING_AREA_DEPS/lib/pkgconfig
	popd
}

build_libad9166() {
	echo "### Building libad9166 - branch $LIBAD9166_BRANCH"
	CURRENT_BUILD=libad9166-iio
	pushd $STAGING_AREA/libad9166
	save_version_info
	build_with_cmake

	# manually install framework (OSX_FRAMEWORK installs to /Library/Frameworks, not CMAKE_INSTALL_PREFIX)
	mkdir -p $STAGING_AREA_DEPS/include
	mkdir -p $STAGING_AREA_DEPS/lib/pkgconfig
	cp -v $STAGING_AREA/libad9166/ad9166.h $STAGING_AREA_DEPS/include
	cp -avR $STAGING_AREA/libad9166/build/ad9166.framework $STAGING_AREA_DEPS/lib
	cp -v $STAGING_AREA/libad9166/build/libad9166.pc $STAGING_AREA_DEPS/lib/pkgconfig
	popd
}


patch_qwt() {
	patch -p1 <<-EOF
--- a/qwtconfig.pri
+++ b/qwtconfig.pri
@@ -19,7 +19,7 @@ QWT_VERSION      = \$\${QWT_VER_MAJ}.\$\${QWT_VER_MIN}.\$\${QWT_VER_PAT}
 QWT_INSTALL_PREFIX = \$\$[QT_INSTALL_PREFIX]

 unix {
-    QWT_INSTALL_PREFIX    = /usr/local/qwt-\$\$QWT_VERSION-ma
+    QWT_INSTALL_PREFIX    = $STAGING_AREA_DEPS
     # QWT_INSTALL_PREFIX = /usr/local/qwt-\$\$QWT_VERSION-ma-qt-\$\$QT_VERSION
 }

@@ -42,7 +42,7 @@ QWT_INSTALL_LIBS      = \$\${QWT_INSTALL_PREFIX}/lib
 # runtime environment of designer/creator.
 ######################################################################

-QWT_INSTALL_PLUGINS   = \$\${QWT_INSTALL_PREFIX}/plugins/designer
+#QWT_INSTALL_PLUGINS   = \$\${QWT_INSTALL_PREFIX}/plugins/designer

 # linux distributors often organize the Qt installation
 # their way and QT_INSTALL_PREFIX doesn't offer a good
@@ -164,7 +164,7 @@ QWT_CONFIG     += QwtTests

 macx:!static:CONFIG(qt_framework, qt_framework|qt_no_framework) {

-    QWT_CONFIG += QwtFramework
+#    QWT_CONFIG += QwtFramework
 }

 ######################################################################
EOF
}


build_libm2k() {
	echo "### Building libm2k - branch $LIBM2K_BRANCH"
	pushd "$STAGING_AREA/libm2k"
	CURRENT_BUILD=libm2k
	save_version_info

	# libm2k hardcodes x86_64; patch a generated copy, not the checkout.
	mkdir -p "$STAGING_AREA/libm2k-source"
	rsync -a --exclude=.git --exclude=build "$STAGING_AREA/libm2k/" "$STAGING_AREA/libm2k-source/"
	popd
	pushd "$STAGING_AREA/libm2k-source"
	sed -i '' "s/set(CMAKE_OSX_ARCHITECTURES \"x86_64\")/set(CMAKE_OSX_ARCHITECTURES \"$ARCH\")/" src/CMakeLists.txt

	CURRENT_BUILD_CMAKE_OPTS="\
		-DENABLE_PYTHON=OFF \
		-DENABLE_CSHARP=OFF \
		-DBUILD_EXAMPLES=OFF \
		-DENABLE_TOOLS=OFF \
		-DINSTALL_UDEV_RULES=OFF \
		-DENABLE_LOG=OFF\
		"
	build_with_cmake
	make install
	popd
}

build_qwt() {
	echo "### Building qwt - branch qwt-multiaxes"
	CURRENT_BUILD=qwt
	pushd "$STAGING_AREA/qwt"
	save_version_info
	# Apply the existing patch only to a generated copy to preserve local edits.
	mkdir -p "$STAGING_AREA/qwt-source"
	rsync -a --exclude=.git --exclude=build "$STAGING_AREA/qwt/" "$STAGING_AREA/qwt-source/"
	popd
	pushd "$STAGING_AREA/qwt-source"
	patch_qwt
	sed -i '' 's|qwtLibraryTarget(qwt)|qwtLibraryTarget(qwt_scopy)|' src/src.pro
	sed -i '' 's|qwtAddLibrary($${QWT_OUT_ROOT}/lib, qwt)|qwtAddLibrary($${QWT_OUT_ROOT}/lib, qwt_scopy)|' \
		designer/designer.pro examples/examples.pri playground/playground.pri tests/tests.pri
	# Qt 6.8 still links legacy AGL on newer SDKs. Qwt needs only OpenGL.
	local qt_cxx_flags=""
	[ "$ARCH" != arm64 ] || qt_cxx_flags="-include arm_acle.h"
	$QMAKE_BIN INCLUDEPATH="$STAGING_AREA_DEPS/include" LIBS="-L$STAGING_AREA_DEPS/lib" \
		"QMAKE_APPLE_DEVICE_ARCHS=$ARCH" "QMAKE_MACOSX_DEPLOYMENT_TARGET=$MACOSX_DEPLOYMENT_TARGET" \
		"QMAKE_CXXFLAGS+=$qt_cxx_flags" qwt.pro -after \
		"CONFIG-=link_prl" "QMAKE_LIBS_OPENGL=-framework OpenGL" "QMAKE_SONAME_PREFIX=@rpath"
	make $JOBS
	make install
	popd
}

build_libtinyiiod() {
	echo "### Building libtinyiiod - branch $LIBTINYIIOD_BRANCH"
	CURRENT_BUILD=libtinyiiod
	pushd $STAGING_AREA/libtinyiiod
	save_version_info
	CURRENT_BUILD_CMAKE_OPTS="-DBUILD_EXAMPLES=OFF"
	build_with_cmake
	make install
	popd
}

build_kddock () {
	echo "### Building KDDockWidgets - version $KDDOCK_BRANCH"
	pushd $STAGING_AREA/KDDockWidgets
	CURRENT_BUILD_CMAKE_OPTS="-DCMAKE_PREFIX_PATH=$QT -DCMAKE_INSTALL_PREFIX=$STAGING_AREA_DEPS -DKDDockWidgets_QT6=ON -DKDDockWidgets_FRONTENDS=qtwidgets"
	CURRENT_BUILD_CMAKE_OPTS="$CURRENT_BUILD_CMAKE_OPTS -DCMAKE_PROJECT_INCLUDE=$REPO_SRC/cmake/Modules/ScopyMacOSQtCompat.cmake -DSCOPY_QT_INCLUDE_DIR=$SCOPY_QT_INCLUDE_DIR -DSCOPY_MACOS_QT_VERSION=$QT_VERSION"
	build_with_cmake
	make install
	popd
}

build_ecm() {
	echo "### Building extra-cmake-modules (ECM) - branch $ECM_BRANCH"
	pushd $STAGING_AREA/extra-cmake-modules
	CURRENT_BUILD_CMAKE_OPTS="-DCMAKE_INSTALL_PREFIX=$STAGING_AREA_DEPS -DBUILD_TESTING=OFF -DBUILD_HTML_DOCS=OFF -DBUILD_MAN_DOCS=OFF -DBUILD_QTHELP_DOCS=OFF"
	build_with_cmake
	make install
	popd
}

build_karchive () {
	echo "### Building karchive - version $KARCHIVE_BRANCH"
	pushd $STAGING_AREA/karchive
	CURRENT_BUILD_CMAKE_OPTS="-DCMAKE_PREFIX_PATH=$QT -DCMAKE_INSTALL_PREFIX=$STAGING_AREA_DEPS -DBUILD_TESTING=OFF"
	CURRENT_BUILD_CMAKE_OPTS="$CURRENT_BUILD_CMAKE_OPTS -DCMAKE_PROJECT_INCLUDE=$REPO_SRC/cmake/Modules/ScopyMacOSQtCompat.cmake -DSCOPY_QT_INCLUDE_DIR=$SCOPY_QT_INCLUDE_DIR -DSCOPY_MACOS_QT_VERSION=$QT_VERSION"
	build_with_cmake
	make install
	popd
}

build_genalyzer() {
	echo "### Building genalyzer - branch $GENALYZER_BRANCH"
	CURRENT_BUILD=genalyzer
	pushd $STAGING_AREA/genalyzer
	save_version_info
	CURRENT_BUILD_CMAKE_OPTS="\
		-DBUILD_TESTING=OFF \
		-DBUILD_SHARED_LIBS=ON \
		"
	build_with_cmake
	make install
	popd
}

build_qcoro() {
	echo "### Building qcoro - version $QCORO_BRANCH"
	CURRENT_BUILD=qcoro
	pushd $STAGING_AREA/qcoro
	# QtDBus auto-disabled on APPLE; Network via qtbase. Qt found via $QT (aqt install), like build_kddock.
	CURRENT_BUILD_CMAKE_OPTS="\
		-DCMAKE_PREFIX_PATH=$QT \
		-DCMAKE_INSTALL_PREFIX=$STAGING_AREA_DEPS \
		-DQCORO_BUILD_EXAMPLES=OFF \
		-DQCORO_BUILD_TESTING=OFF \
		-DBUILD_TESTING=OFF \
		-DQCORO_WITH_QTWEBSOCKETS=OFF \
		-DQCORO_WITH_QTQUICK=OFF \
		-DQCORO_WITH_QML=OFF \
		-DBUILD_SHARED_LIBS=ON \
		"
	CURRENT_BUILD_CMAKE_OPTS="$CURRENT_BUILD_CMAKE_OPTS -DCMAKE_PROJECT_INCLUDE=$REPO_SRC/cmake/Modules/ScopyMacOSQtCompat.cmake -DSCOPY_QT_INCLUDE_DIR=$SCOPY_QT_INCLUDE_DIR -DSCOPY_MACOS_QT_VERSION=$QT_VERSION"
	build_with_cmake
	make install
	popd
}

build_deps(){
	if [ "${CACHING_ENABLED}" == "true" ] && [ "$DEPENDENCIES_CACHED" == "true" ]; then
		echo "Found cached dependencies in $STAGING_AREA_DEPS"
		return 0
	fi

	echo "Building all dependencies from source..."
	build_libserialport
	build_libiio
	build_libad9361
	build_libad9166
	build_libm2k
	build_qwt
	build_libtinyiiod
	build_kddock
	build_ecm
	build_karchive
	build_genalyzer
	build_qcoro
}

# Setup cache management
if [ "${CACHING_ENABLED}" == "true" ] && [ -z "$CACHE_BASE_DIR" ]; then
	echo "CACHING_ENABLED requires PIPELINE_WORKSPACE" >&2
	exit 1
fi
cleanup_old_caches
setup_homebrew_cache
setup_git_cache
setup_dependencies_cache
check_cache_sizes

# Install Qt6 via aqtinstall, install dependencies, clone repositories, and build all dependencies
install_packages
install_qt
export_paths
clone
generate_status_file
build_deps
