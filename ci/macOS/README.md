# macOS CI Directory

## Overview

This directory contains scripts for building Scopy on macOS. The build process uses Homebrew for dependency management and creates a DMG installer for distribution.

### Scripts

#### `macos_config.sh`- Configuration file for macOS builds

#### `build_macos.sh`- Builds Scopy and IIO-Emulator

#### `install_macos_deps.sh`- Installs macOS build dependencies

#### `package_darwin.sh`- Creates the macOS DMG installer

#### `verify_bundle.py`- Checks architectures and dependency paths without modifying the bundle

#### `smoke.js`- Starts and exits Scopy without connecting to hardware

## Build Process

### Prerequisites

- **Homebrew**: See [Homebrew Installation](https://docs.brew.sh/Installation).
- Xcode or the Xcode Command Line Tools, Git, and Python 3.9 or later.
- A native Intel or Apple Silicon terminal.

### Build Steps

Run from the repository root:

1. **Setup the environment and install the dependencies**:

   ```bash
   ./ci/macOS/install_macos_deps.sh
   ```

   This installs required Homebrew packages and builds other dependencies from source. Qt and Python build tools are installed using a staging-directory virtual environment.

2. **Build Scopy**:

   ```bash
   ./ci/macOS/build_macos.sh
   ```

3. **Create Installer**:

   ```bash
   ./ci/macOS/package_darwin.sh
   ```

   Packaging links and bundles dependencies in `build/Scopy.app`. Open it using `open build/Scopy.app` or Finder. Packaging modifies the build bundle; rebuild before packaging again.

See [macOS Build Instructions](../../docs/user_guide/build_instructions/macosBuild.rst) for the user-facing build instructions.

## Output

- **Scopy.app**: macOS application bundle
- **Scopy.dmg**: Distributable disk image installer
- **ScopyApp.zip**: Zipped application bundle
- **build-status**: Dependency versions included in the application About page

## CI Integration

- **GitHub Actions**: `.github/workflows/macosbuild.yml`, native ARM64 and Intel runners.
- The same scripts are used locally and in CI. CI builds with `ENABLE_TESTING=ON`, runs hardware-free tests, checks dependency paths and signing, and starts a relocated packaged application.
- Most tests matching `pluginloader` are excluded because they assume Linux `.so` names. The M2K plugin-loader/controller tests use the built target's path and run separately in the M2K matrix. `scopy-iioutil_test_connectionprovider` requires `ip:192.168.2.1` and is also excluded.
- Existing Homebrew, Git, and built-dependency caches use `CACHING_ENABLED`, `HOMEBREW_PACKAGES_CACHE`, `GIT_REPOS_CACHE`, `BUILT_DEPS_CACHE`, and `PIPELINE_WORKSPACE`. Cache cleanup is restricted to that explicitly configured cache workspace.

## Notes

- Native x86_64 and arm64 builds are supported; all dependencies must use the same architecture.
- Configuration is in `macos_config.sh`. Path overrides must be used consistently for all steps. `JOBS` accepts `-j8` or `8`.
- Repeated builds do not reset dependency checkouts or delete build directories. Use a new staging directory when changing dependency refs or architectures.
- Ad-hoc signing is not Developer ID signing or notarization.
- Set `ENABLE_PACKAGE_M2K=ON` consistently for dependency installation, application build, and packaging to include ADALM2000 instruments. This adds GNU Radio and sigrok; Scopy and sigrok use the same Python 3.11 interpreter. Default builds keep M2K/Python/sigrok disabled. ADC remains disabled.
- The M2K branch's ARM64/Intel Actions matrix builds this optional configuration. Hardware operation is not covered by the CI startup test; `js/testAutomations/m2k/controllerRecognition.js` checks recognition without connecting to hardware or enabling outputs.
