# macOS build and packaging

CI and developers use the same scripts on native Apple Silicon (`arm64`) and
Intel (`x86_64`) machines. Use a native terminal, not Rosetta.

From the repository root:

```sh
bash ci/macOS/install_macos_deps.sh
ENABLE_TESTING=ON bash ci/macOS/build_macos.sh
QT_QPA_PLATFORM=offscreen ctest --test-dir build \
  -E 'pluginloader|scopy-iioutil_test_connectionprovider' --output-on-failure --timeout 60
bash ci/macOS/package_darwin.sh
open build/package/Scopy.app
```

See the [macOS build guide](../../docs/user_guide/build_instructions/macosBuild.rst)
for prerequisites, configuration, output locations, and test limitations.

- `macos_config.sh`: architecture, paths, Qt version, dependency refs.
- `macos_common.sh`: shared environment and build helpers.
- `install_macos_deps.sh`: incremental dependencies and Qt installation.
- `build_macos.sh`: incremental Scopy and IIO-Emulator build.
- `package_darwin.sh`: standalone, ad-hoc-signed app, ZIP, and DMG.
- `verify_bundle.py`: checks binary architectures and bundled dependency closure.

`.github/workflows/macosbuild.yml` uses these same entry points for ARM64 and
Intel. It tests the build and audits/starts a relocated packaged application.
The scripts do not reset checkouts, delete existing builds, uninstall Homebrew
packages, or install Python packages globally. CI caches may cache the staging
directory, but there is no separate cache-only build implementation.
