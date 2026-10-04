.. _macos_build_instructions:

MacOS Build Instructions
==========================

.. caution::

    Building and linking the application and its dependencies takes time.
    The scripts below build natively on Intel x86_64 and Apple Silicon arm64.
    Use a native terminal; Rosetta and cross-compilation are not tested.

Building Scopy
-----------------------

1. Clone the Scopy repository:

   .. code-block:: zsh

      % cd ~
      % git clone https://github.com/analogdevicesinc/scopy.git
      % cd scopy

2. Set up dependencies.

   Install Xcode or the Xcode Command Line Tools, Python 3.9 or later, and
   Homebrew using its `install instructions <https://docs.brew.sh/Installation>`_.
   Then run:

   .. code-block:: zsh

      % ./ci/macOS/install_macos_deps.sh

   This installs the required Homebrew packages and builds the remaining
   dependencies from source under ``staging``. Qt 6.8.3 and its ``qt3d``,
   ``qtscxml``, and ``qtshadertools`` modules are installed with aqtinstall.
   Python build tools are installed in a virtual environment, not globally.

3. Build the application.

   .. code-block:: zsh

      % ./ci/macOS/build_macos.sh

   This uses the dependencies from Step 2 to compile Scopy and IIO-Emulator.
   Repeated runs reuse the build directory. ``build/Scopy.app`` is a development
   bundle and still depends on the installed Qt and dependency libraries.

4. Package the application.

   .. code-block:: zsh

      % ./ci/macOS/package_darwin.sh

   This links and bundles the dependencies so the operating system can locate
   them at runtime. The resulting **Scopy.app**, **Scopy.dmg**, and
   **ScopyApp.zip** are in the build folder. Open the application with
   ``open build/Scopy.app`` or double-click it in Finder.

   The application is ad-hoc signed, not Developer ID signed or notarized.
   Gatekeeper restrictions may therefore apply to downloaded builds.

.. note::

    Run all three scripts from the repository root. ``QT``, ``STAGING_AREA``,
    ``STAGING_AREA_DEPS``, ``BUILDDIR``, and ``JOBS`` can be overridden through
    environment variables; use the same paths for each step. For example,
    ``export QT="$HOME/Qt/6.8.3/macos"`` selects an existing Qt installation.
    See ``ci/macOS/README.md`` for CI and test details.

    ADC remains disabled in the macOS configuration.

Building with ADALM2000 support
------------------------------

To include the M2K package, set the existing package option before running
the same build steps:

.. code-block:: zsh

   % export ENABLE_PACKAGE_M2K=ON
   % ./ci/macOS/install_macos_deps.sh
   % ./ci/macOS/build_macos.sh
   % ./ci/macOS/package_darwin.sh

This adds GNU Radio, gr-scopy, gr-m2k, and libsigrokdecode dependencies.
Scopy and libsigrokdecode both use Python 3.11; the packaged application
includes that interpreter and the protocol decoders. M2K is disabled by
default, so existing builds without GNU Radio remain available.

M2K discovery and connection use device-controller's shared context.
The DSP implementation still requires its borrowed libiio v0 handle;
libiio v1 contexts are not supported by the M2K instruments.
The CI startup test does not verify measurements, waveform output, or calibration.
