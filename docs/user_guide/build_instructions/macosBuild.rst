.. _macos_build_instructions:

macOS Build Instructions
========================

Scopy uses the same build scripts for developers and CI, on native Apple
Silicon (arm64) and Intel (x86_64) machines. Cross-compilation and Rosetta
builds are not supported by these scripts. The default deployment target is
macOS 11; runtime compatibility with older systems still requires testing.

Prerequisites
-------------

Install Xcode or the Xcode Command Line Tools, Homebrew, Git, and Python 3
(3.9 or later). Run the scripts from a native terminal. They install only
missing required Homebrew formulae and use a Python virtual environment under
the staging directory for aqtinstall and Mako. Qt 6.8.3's universal macOS SDK
is downloaded when it is missing. Required ``qt3d``, ``qtscxml``, and
``qtshadertools`` modules are also checked and installed if missing.

The scripts do not uninstall Homebrew packages, patch Qt headers/libraries, install
frameworks into ``/Library/Frameworks``, reset source checkouts, or delete
existing build directories. Repeated runs are incremental.

Building Scopy
--------------

From the repository root:

.. code-block:: sh

   bash ci/macOS/install_macos_deps.sh
   bash ci/macOS/build_macos.sh
   open build/Scopy.app

Dependencies are built under ``staging/build`` from ``staging/src`` and
installed into ``staging/dependencies``. Source checkouts are reused without
automatic fetch/reset; their exact commits are recorded in
``staging/build-status``; modified checkouts are marked dirty. Use a new staging
directory for a fresh dependency snapshot. Qwt patches are applied to a
generated source copy, not the checkout.

``build/Scopy.app`` is a development bundle: keep the staging directory, Qt,
and required Homebrew libraries in place. To rebuild only the application and
IIO-Emulator, rerun ``build_macos.sh`` without the dependency-install step.

Configuration
-------------

``ci/macOS/macos_config.sh`` provides defaults shared by all three scripts.
Environment overrides must be passed consistently to installation, build,
and packaging:

* ``STAGING_AREA``: default ``<repository>/staging``.
* ``STAGING_AREA_DEPS``: default ``<staging>/dependencies``.
* ``BUILDDIR``: default ``<repository>/build``.
* ``QT_INSTALL_LOCATION``: default ``$HOME/Qt``.
* ``QT_VERSION``: default ``6.8.3``.
* ``QT``: default ``<Qt install location>/<Qt version>/macos``. A custom path
  must already contain a Qt installation.
* ``JOBS``: positive integer, default ``8`` (legacy ``-j8`` is also accepted).
* ``ARCH``: default host architecture; only native ``arm64`` or ``x86_64``.
* ``MACOSX_DEPLOYMENT_TARGET``: default ``11.0``, used for dependencies and Scopy.
* ``ENABLE_TESTING``: ``ON`` or ``OFF``, default ``OFF``; set ``ON`` for tests.

Use absolute override paths. For example, ``export STAGING_AREA="$PWD/staging-arm64"``
before running the three standard scripts.

The build selects the configured Qt headers even when Homebrew Qt5 headers
are globally linked. Qt 6.8's Apple Clang 21 ``__yield`` declaration and legacy
AGL SDK compatibility are handled without modifying the Qt installation.

Tests
-----

.. code-block:: sh

   ENABLE_TESTING=ON bash ci/macOS/build_macos.sh
   QT_QPA_PLATFORM=offscreen ctest --test-dir build \
     -E 'pluginloader|scopy-iioutil_test_connectionprovider' --output-on-failure --timeout 60

This subset runs the macOS-compatible hardware-free tests, including
device-controller tests. The excluded plugin-loader tests still assume Linux
``.so`` names, and the connection-provider test requires ``ip:192.168.2.1``.
Passing this subset does not establish instrument operation with hardware.

Packaging for distribution
--------------------------

.. code-block:: sh

   bash ci/macOS/package_darwin.sh
   open build/package/Scopy.app

Packaging works on a separate copy, leaving the development bundle intact.
It bundles Qt and non-system libraries, includes IIO-Emulator, verifies native
architectures and dependency closure, and applies an ad-hoc signature. Outputs:

* ``build/package/Scopy.app``: standalone application.
* ``build/ScopyApp.zip``: zipped application.
* ``build/Scopy.dmg``: disk image.

The package destination must not already exist. Move a previous
``build/package/Scopy.app`` aside before packaging again. Ad-hoc signing is not
Developer ID signing or notarization; downloaded builds may still be subject
to Gatekeeper restrictions.

The ARM64/Intel GitHub Actions matrix uses these same scripts, runs the test
subset, and audits and starts the packaged application after moving it outside
the build directory. A successful build alone is not a packaging test.

Current upstream limitations
----------------------------

On the device-controller development branch, M2K, EXTPROC, and TEST-PLUGINS
remain disabled; ADC is explicitly disabled by the macOS build script.
Python/sigrok integration is also disabled. This build does not provide the
legacy ADALM2000 instruments. M2K integration is maintained separately.
