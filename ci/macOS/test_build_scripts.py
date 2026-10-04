#!/usr/bin/env python3
"""Test command generation without installing packages or compiling binaries."""
import importlib.util
import os
import pathlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch

HERE = pathlib.Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("verify_bundle", HERE / "verify_bundle.py")
bundle = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bundle)


class BuildScriptTests(unittest.TestCase):
    def test_qt_module_installation(self):
        for existing in (False, True):
            with self.subTest(existing_sdk=existing), tempfile.TemporaryDirectory(prefix="scopy qt ") as directory:
                root = pathlib.Path(directory)
                tools = root / "bin"
                tools.mkdir()
                qt = root / "sdk/6.8.3/macos"
                (qt / "bin").mkdir(parents=True)
                venv = root / "staging/venv/bin"
                venv.mkdir(parents=True)
                python = venv / "python3"
                python.write_text("#!/bin/bash\nexit 0\n")
                python.chmod(0o755)
                if existing:
                    qmake = qt / "bin/qmake6"
                    qmake.write_text("#!/bin/bash\nexit 0\n")
                    qmake.chmod(0o755)
                    for module in ("Qt3DCore", "QtScxml"):
                        (qt / "lib" / f"{module}.framework/Headers").mkdir(parents=True)
                commands = {
                    "uname": 'if [[ $1 == -s ]]; then echo Darwin; else echo arm64; fi',
                    "sysctl": "echo 0",
                    "xcrun": "echo /mock/sdk",
                    "brew": 'echo "$MOCK_ROOT"',
                    # Stop after SDK setup, before any dependency build.
                    "git": "exit 23",
                    "aqt": '''printf "%s\\n" "$@" > "$MOCK_LOG"
mkdir -p "$QT/bin"
printf '#!/bin/bash\\nexit 0\\n' > "$QT/bin/qmake6"
chmod +x "$QT/bin/qmake6"
for module in Qt3DCore QtScxml QtShaderTools; do mkdir -p "$QT/lib/$module.framework/Headers"; done''',
                }
                for name, body in commands.items():
                    path = tools / name
                    path.write_text("#!/bin/bash\nset -eu\n" + body + "\n")
                    path.chmod(0o755)
                log = root / "qt-arguments"
                env = dict(os.environ, PATH=f"{tools}:{os.environ['PATH']}", MOCK_ROOT=str(root),
                           MOCK_LOG=str(log), QT=str(qt), QT_INSTALL_LOCATION=str(root / "sdk"),
                           QT_VERSION="6.8.3", STAGING_AREA=str(root / "staging"), ARCH="arm64")
                result = subprocess.run(["/bin/bash", str(HERE / "install_macos_deps.sh")], env=env,
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, 23, result.stderr)
                arguments = log.read_text().splitlines()
                self.assertIn("qtshadertools", arguments)
                self.assertEqual("--noarchives" in arguments, existing)
                self.assertEqual("qt3d" in arguments, not existing)

    def test_native_build_commands(self):
        for arch in ("arm64", "x86_64"):
            with self.subTest(arch=arch), tempfile.TemporaryDirectory(prefix="scopy build ") as directory:
                root = pathlib.Path(directory)
                tools = root / "bin"
                tools.mkdir()
                qt = root / "Qt"
                (qt / "bin").mkdir(parents=True)
                for module in ("Qt3DCore", "QtScxml", "QtShaderTools"):
                    (qt / "lib" / f"{module}.framework/Headers").mkdir(parents=True)
                log = root / "commands"
                commands = {
                    "uname": f'if [[ $1 == -s ]]; then echo Darwin; else echo {arch}; fi',
                    "sysctl": "echo 0",
                    "xcrun": "echo /mock/sdk",
                    "brew": 'echo "$MOCK_ROOT"',
                    "git": 'if [[ $1 == clone ]]; then mkdir -p "${@: -1}"; else echo mock-commit; fi',
                    "cmake": 'printf "%s\\n" "$@" >> "$MOCK_LOG"',
                    "file": "echo Mach-O",
                }
                for name, body in commands.items():
                    path = tools / name
                    path.write_text("#!/bin/bash\nset -eu\n" + body + "\n")
                    path.chmod(0o755)
                qmake = qt / "bin/qmake6"
                qmake.write_text("#!/bin/bash\nexit 0\n")
                qmake.chmod(0o755)
                env = dict(os.environ, PATH=f"{tools}:{os.environ['PATH']}",
                           MOCK_ROOT=str(root), MOCK_LOG=str(log), ARCH=arch,
                           STAGING_AREA=str(root / "staging"),
                           BUILDDIR=str(root / "build"), QT=str(qt), JOBS="-j2", ENABLE_TESTING="ON")
                subprocess.run(["bash", str(HERE / "build_macos.sh")], env=env, check=True,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                arguments = log.read_text().splitlines()
                self.assertEqual(arguments.count(f"-DCMAKE_OSX_ARCHITECTURES={arch}"), 2)
                self.assertIn("-DCMAKE_OSX_DEPLOYMENT_TARGET=11.0", arguments)
                self.assertIn("-DENABLE_TESTING=ON", arguments)
                self.assertIn(str(root / "build"), arguments)
                self.assertIn("2", arguments)

    def test_invalid_parallelism(self):
        result = subprocess.run(["bash", "-c", 'source "$1"', "test", str(HERE / "macos_config.sh")],
                                env=dict(os.environ, JOBS="invalid"), capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("JOBS must be a positive integer", result.stderr)

    def test_rosetta_rejected(self):
        result = subprocess.run(["bash", "-c", '''
source "$1"
uname() { if [[ $1 == -s ]]; then echo Darwin; else echo arm64; fi; }
sysctl() { echo 1; }
require_native_macos
''', "test", str(HERE / "macos_common.sh")],
                                env=dict(os.environ, ARCH="arm64"), capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("not Rosetta", result.stderr)

    def test_cross_compilation_rejected(self):
        result = subprocess.run(["bash", "-c", '''
source "$1"
uname() { if [[ $1 == -s ]]; then echo Darwin; else echo arm64; fi; }
sysctl() { echo 0; }
require_native_macos
''', "test", str(HERE / "macos_common.sh")],
                                env=dict(os.environ, ARCH="x86_64"), capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Cross-compilation is not supported", result.stderr)


class BundleAuditTests(unittest.TestCase):
    def audit(self, archs, dependency):
        with tempfile.TemporaryDirectory() as directory:
            app = pathlib.Path(directory) / "Scopy.app"
            binary = app / "Contents/MacOS/Scopy"
            binary.parent.mkdir(parents=True)
            binary.touch()

            def output(*args):
                return {"file": "Mach-O", "lipo": archs, "otool":
                        f"cmd LC_LOAD_DYLIB\ncmdsize 64\nname {dependency} (offset 24)"}[args[0]]

            with patch.object(bundle, "output", side_effect=output):
                bundle.verify(app, "arm64")

    def test_system_libraries_allowed(self):
        self.audit("arm64", "/usr/lib/libSystem.B.dylib")

    def test_homebrew_dependency_rejected(self):
        with self.assertRaisesRegex(RuntimeError, "unbundled dependency"):
            self.audit("arm64", "/opt/homebrew/lib/libusb.dylib")

    def test_wrong_architecture_rejected(self):
        with self.assertRaisesRegex(RuntimeError, "missing arm64"):
            self.audit("x86_64", "/usr/lib/libSystem.B.dylib")

    def test_install_name_is_not_a_dependency(self):
        commands = "cmd LC_ID_DYLIB\ncmdsize 64\nname @rpath/plugin.dylib (offset 24)"
        self.assertEqual(bundle.dependencies(commands), [])


if __name__ == "__main__":
    unittest.main()
