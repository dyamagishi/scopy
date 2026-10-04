# Native macOS build (Apple Silicon / Intel)

Use a native terminal (not Rosetta) with Xcode Command Line Tools, Homebrew,
and Python 3 installed. From the repository root:

```sh
bash ci/macOS/build_local.sh
```

This installs only missing Homebrew formulae, downloads Qt 6.8.3 (universal)
via aqtinstall in a local Python virtual environment, and builds dependencies
and Scopy for the host architecture (`arm64` on Apple Silicon). It does not
uninstall Homebrew packages, install into `/Library/Frameworks`, reset Git
checkouts, or remove existing build directories. Repeated runs are incremental.
On ARM64, Qt consumers preinclude `arm_acle.h` to work around Qt 6.8.3's
missing `__yield` declaration with Apple Clang 21; the Qt SDK is not modified.
The build also avoids Qt 6.8's legacy AGL link flag when the selected SDK no
longer provides AGL, while retaining OpenGL support.
Local Qt6 header aliases prevent globally linked Homebrew Qt5 headers from
being picked up accidentally; there is no need to unlink or uninstall Qt5.

The resulting app is `build-local/scopy/Scopy.app`:

```sh
open build-local/scopy/Scopy.app
QT_QPA_PLATFORM=offscreen ctest --test-dir build-local/scopy \
  -E 'pluginloader|scopy-iioutil_test_connectionprovider' --output-on-failure --timeout 60
```

The app uses local dependencies, so keep `build-local/deps` and the Qt install
in place. This is a development build, not a self-contained distribution.

To rebuild Scopy without rebuilding dependencies:

```sh
bash ci/macOS/build_local.sh --build-only
```

Use `--deps-only` to build just dependencies. `JOBS` is a positive integer
(default `8`); `BUILDDIR`, `STAGING_AREA`, and `QT` can also be overridden.
Dependency refs match `ci/macOS/macos_config.sh`. Existing dependency checkouts
are reused without fetching updates automatically; use a new `STAGING_AREA`
to test a fresh dependency snapshot.

## Experimental M2K opt-in

Build the legacy ADALM2000 instruments and their additional dependencies:

```sh
ENABLE_M2K=ON bash ci/macOS/build_local.sh
```

Keep `ENABLE_M2K=ON` when using `--build-only` too. This builds the Scopy
GNU Radio fork, gr-scopy, gr-m2k, libm2k, and libsigrokdecode natively. Python
3.11 is used for embedded protocol decoders; Python packages stay in a local
virtual environment. This is experimental on the Qt6/device-controller branch;
building or loading M2K is not proof that all instruments work with hardware.

M2K detection and the information page use the device-controller component
tree. The plugin, identification/temperature tasks, and instrument connection
share controller-owned contexts; connection-loss monitoring belongs to the
controller. The libm2k/GNU Radio instruments still use the libiio v0 API via a
borrowed native handle, not a second USB connection. A v1 handle is rejected
at this bridge. This does not replace the instrument DSP/streaming code with
device-controller stream capabilities.

Test that the built M2K library loads and exposes the plugin interface (no
device connection or output generation):

```sh
QT_QPA_PLATFORM=offscreen ctest --test-dir build-local/scopy \
  -R '^scopy-m2k_test_pluginloader$' --output-on-failure --timeout 60
```

With an ADALM2000 attached, verify discovery and M2K classification without
connecting instruments, calibrating, or enabling waveform outputs:

```sh
QT_QPA_PLATFORM=offscreen build-local/scopy/Scopy.app/Contents/MacOS/Scopy \
  --accept-license --script="$PWD/js/testAutomations/m2k/controllerRecognition.js"
```

Quit other running Scopy instances before connecting an ADALM2000; concurrent
instances may prevent libusb from claiming the device. To return to a build
without M2K, use a fresh `BUILDDIR`, since old package artifacts are retained.

## Current upstream limitations

The `main` branch is Scopy 2.3 development with Qt 6 and the new
device-controller. This fork permits explicitly opting into the legacy M2K
package instead of forcing it off. EXTPROC and TEST-PLUGINS remain disabled;
ADC and debugger plugins remain off by default. Without the M2K opt-in,
Python/sigrok and ADALM2000 instruments are disabled like upstream macOS CI.
The Qt 5-based `v2.2.x-maint` branch is a separate, established M2K build target.

The test command above runs the macOS-compatible hardware-free tests. The
full CTest suite also contains plugin-loader tests with hardcoded Linux `.so`
paths and a connection-provider test requiring `ip:192.168.2.1`; those are not
currently portable hardware-free macOS tests.
