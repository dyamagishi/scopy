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

## Current upstream limitations

The `main` branch is Scopy 2.3 development with Qt 6 and the new
device-controller. Upstream currently forces the M2K, EXTPROC, and TEST-PLUGINS
packages off; ADC and debugger plugins are also off by default. This script
retains those restrictions and disables Python/sigrok integration like macOS
CI. A successful build does **not** mean ADALM2000 oscilloscope, signal generator,
or logic analyzer functionality is available. For the existing M2K instruments,
the Qt 5-based `v2.2.x-maint` branch is a separate build target.

The test command above runs the macOS-compatible hardware-free tests. The
full CTest suite also contains plugin-loader tests with hardcoded Linux `.so`
paths and a connection-provider test requiring `ip:192.168.2.1`; those are not
currently portable hardware-free macOS tests.
