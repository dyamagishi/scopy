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


def rpaths(binary):
    return re.findall(r"cmd LC_RPATH\s+cmdsize \d+\s+path (.*?) \(offset",
                      output("otool", "-l", str(binary)))


def dependencies(load_commands):
    # Parse load commands, not otool -L's human-readable per-architecture headings
    # or LC_ID_DYLIB (a library's own install name is not a dependency).
    return re.findall(r"cmd LC_(?:LOAD_DYLIB|LOAD_WEAK_DYLIB|REEXPORT_DYLIB|LAZY_LOAD_DYLIB|LOAD_UPWARD_DYLIB)"
                      r"\s+cmdsize \d+\s+name (.*?) \(offset", load_commands)


def sanitize_rpaths(app):
    """Remove build-machine paths from the generated package, before signing."""
    app = pathlib.Path(app).resolve()
    for binary in app.rglob("*"):
        if any(p.endswith(".dSYM") for p in binary.parts) or not binary.is_file() or binary.is_symlink() or "Mach-O" not in output("file", "-b", str(binary)):
            continue
        seen = set()
        for path in rpaths(binary):
            if (path.startswith("/") and not system_path(path)) or path in seen:
                subprocess.run(["install_name_tool", "-delete_rpath", path, str(binary)], check=True)
            else:
                seen.add(path)
        if binary.parent == app / "Contents/MacOS" and "@executable_path/../Frameworks" not in rpaths(binary):
            subprocess.run(["install_name_tool", "-add_rpath", "@executable_path/../Frameworks", str(binary)], check=True)


def verify(app, arch):
    app = pathlib.Path(app).resolve()
    executable_dir = app / "Contents/MacOS"
    errors = []
    count = 0
    for binary in app.rglob("*"):
        if any(p.endswith(".dSYM") for p in binary.parts) or not binary.is_file() or binary.is_symlink():
            continue
        if "Mach-O" not in output("file", "-b", str(binary)):
            continue
        count += 1
        if arch not in output("lipo", "-archs", str(binary)).split():
            errors.append(f"{binary}: missing {arch}")
        runpaths = rpaths(binary)
        for path in runpaths:
            if path.startswith("/") and not system_path(path):
                errors.append(f"{binary.relative_to(app)}: external run-path {path}")

        def expand(path):
            return pathlib.Path(path.replace("@loader_path", str(binary.parent))
                                .replace("@executable_path", str(executable_dir)))

        for dependency in dependencies(output("otool", "-arch", arch, "-l", str(binary))):
            if system_path(dependency):
                continue
            if dependency.startswith("@rpath/"):
                candidates = [expand(p) / dependency[len("@rpath/"):] for p in runpaths]
                # dyld also uses the executable's run-path stack.
                candidates.append(app / "Contents/Frameworks" / dependency[len("@rpath/"):])
            else:
                candidates = [expand(dependency)]
            if not any(p.exists() and p.resolve().is_relative_to(app) for p in candidates):
                errors.append(f"{binary.relative_to(app)}: unbundled dependency {dependency}")
    if not count:
        errors.append("No Mach-O binaries found")
    if errors:
        raise RuntimeError("\n".join(errors))
    print(f"Verified {count} Mach-O binaries: {arch}, all non-system dependencies bundled")


if __name__ == "__main__":
    if "--sanitize-rpaths" in sys.argv[3:]:
        sanitize_rpaths(sys.argv[1])
    verify(sys.argv[1], sys.argv[2])
