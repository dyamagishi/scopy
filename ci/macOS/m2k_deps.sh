#!/bin/bash
# Sourced by build_local.sh; uses its clone/install_cmake helpers and local prefix.
build_m2k_dependencies() {
	local formula
	for formula in boost@1.85 volk glib autoconf automake libtool bison python@3.11; do
		brew list --versions "$formula" >/dev/null 2>&1 || brew install "$formula"
	done
	local python_prefix
	python_prefix=$(brew --prefix python@3.11)
	if [[ ! -x "$STAGING_AREA/m2k-venv/bin/python3" ]]; then
		"$python_prefix/bin/python3.11" -m venv "$STAGING_AREA/m2k-venv"
	fi
	"$STAGING_AREA/m2k-venv/bin/python3" -m pip install mako
	export PKG_CONFIG_PATH="$python_prefix/lib/pkgconfig:$PKG_CONFIG_PATH"
	local boost_prefix
	boost_prefix=$(brew --prefix boost@1.85)
	local bison_prefix
	bison_prefix=$(brew --prefix bison)
	export PATH="$bison_prefix/bin:$PATH"
	clone libm2k https://github.com/analogdevicesinc/libm2k.git main
	clone gnuradio https://github.com/analogdevicesinc/gnuradio.git scopy2-maint-3.10
	clone gr-scopy https://github.com/analogdevicesinc/gr-scopy.git 3.10
	clone gr-m2k https://github.com/analogdevicesinc/gr-m2k.git main
	clone libsigrokdecode https://github.com/sigrokproject/libsigrokdecode.git master
	# libm2k's older macOS build overrides the caller's architecture with x86_64.
	python3 - "$STAGING_AREA/src/libm2k/src/CMakeLists.txt" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
path.write_text(path.read_text().replace('set(CMAKE_OSX_ARCHITECTURES "x86_64")',
    'if(NOT CMAKE_OSX_ARCHITECTURES)\nset(CMAKE_OSX_ARCHITECTURES "${CMAKE_SYSTEM_PROCESSOR}")\nendif()'))
PY
	install_cmake libm2k -DENABLE_PYTHON=OFF -DENABLE_CSHARP=OFF -DBUILD_EXAMPLES=OFF \
		-DENABLE_TOOLS=OFF -DINSTALL_UDEV_RULES=OFF -DENABLE_LOG=OFF
	install_cmake gnuradio -DENABLE_DEFAULT=OFF -DENABLE_GNURADIO_RUNTIME=ON \
		-DENABLE_GR_ANALOG=ON -DENABLE_GR_BLOCKS=ON -DENABLE_GR_FFT=ON \
		-DENABLE_GR_FILTER=ON -DENABLE_GR_IIO=ON -DENABLE_POSTINSTALL=OFF \
		-DENABLE_PYTHON=OFF -DENABLE_TESTING=OFF -DENABLE_GR_QTGUI=OFF \
		-DCMAKE_DISABLE_FIND_PACKAGE_Qt5=ON -DBOOST_ROOT="$boost_prefix"
	install_cmake gr-scopy -DWITH_PYTHON=OFF -DBOOST_ROOT="$boost_prefix" \
		-DBISON_EXECUTABLE="$(brew --prefix bison)/bin/bison" -DENABLE_DOXYGEN=OFF
	install_cmake gr-m2k -DENABLE_PYTHON=OFF -DDIGITAL=OFF -DBOOST_ROOT="$boost_prefix" \
		-DENABLE_DOXYGEN=OFF
	(
		cd "$STAGING_AREA/src/libsigrokdecode" || exit 1
		[[ -f configure ]] || ./autogen.sh
	)
	mkdir -p "$STAGING_AREA/build/libsigrokdecode"
	(
		cd "$STAGING_AREA/build/libsigrokdecode" || exit 1
		PYTHON="$python_prefix/bin/python3.11" \
			"$STAGING_AREA/src/libsigrokdecode/configure" --prefix="$STAGING_AREA_DEPS"
		make -j"$JOBS"
		make install
	)
}
