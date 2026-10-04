#!/usr/bin/env python3
"""Audit the native architecture and dependency closure of a macOS app."""
import pathlib
import re
import subprocess
import sys


def output(*args):
    return subprocess.check_output(args, text=True, errors="replace").strip()


def system_path(path):
    return path.startswith(("/System/Library/", "/usr/lib/"))


def rpaths(binary, arch):
    return re.findall(r"cmd LC_RPATH\s+cmdsize \d+\s+path (.*?) \(offset",
                      output("otool", "-arch", arch, "-l", str(binary)))


def dependencies(load_commands):
    # Parse load commands, not otool -L's human-readable per-architecture headings
    # or LC_ID_DYLIB (a library's own install name is not a dependency).
    return re.findall(r"cmd LC_(?:LOAD_DYLIB|LOAD_WEAK_DYLIB|REEXPORT_DYLIB|LAZY_LOAD_DYLIB|LOAD_UPWARD_DYLIB)"
                      r"\s+cmdsize \d+\s+name (.*?) \(offset", load_commands)


def verify(app, arch):
    app = pathlib.Path(app).resolve()
    executable_dir = app / "Contents/MacOS"
    errors = []
    count = 0
    main = executable_dir / "Scopy"
    if not main.is_file():
        raise RuntimeError("Missing main executable: " + str(main))

    def expand(path, loader):
        return pathlib.Path(path.replace("@loader_path", str(loader.parent))
                            .replace("@executable_path", str(executable_dir)))

    main_runpaths = [expand(path, main) for path in rpaths(main, arch)]
    for binary in app.rglob("*"):
        if any(p.endswith(".dSYM") for p in binary.parts) or not binary.is_file() or binary.is_symlink():
            continue
        if "Mach-O" not in output("file", "-b", str(binary)):
            continue
        count += 1
        if arch not in output("lipo", "-archs", str(binary)).split():
            errors.append(f"{binary}: missing {arch}")
        runpaths = rpaths(binary, arch)
        if len(runpaths) != len(set(runpaths)):
            errors.append(f"{binary.relative_to(app)}: duplicate run-path")
        for path in runpaths:
            if path.startswith("/") and not system_path(path):
                errors.append(f"{binary.relative_to(app)}: external run-path {path}")

        # Plugins loaded by Scopy inherit its run-path stack. Helper executables
        # must resolve their dependencies using their own paths, not Scopy's.
        search_paths = [expand(path, binary) for path in runpaths]
        if binary.parent != executable_dir:
            search_paths += main_runpaths
        for dependency in dependencies(output("otool", "-arch", arch, "-l", str(binary))):
            if system_path(dependency):
                continue
            if dependency.startswith("@rpath/"):
                candidates = [p / dependency[len("@rpath/"):] for p in search_paths]
            else:
                candidates = [expand(dependency, binary)]
            if not any(p.is_absolute() and p.is_file() and p.resolve().is_relative_to(app) for p in candidates):
                errors.append(f"{binary.relative_to(app)}: unbundled dependency {dependency}")
    if not count:
        errors.append("No Mach-O binaries found")
    if errors:
        raise RuntimeError("\n".join(errors))
    print(f"Verified {count} Mach-O binaries: {arch}, all non-system dependencies bundled")


if __name__ == "__main__":
    verify(sys.argv[1], sys.argv[2])
