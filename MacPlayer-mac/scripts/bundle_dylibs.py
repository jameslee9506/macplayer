#!/usr/bin/env python3
"""Bundle the installed mpv, FFmpeg and SQLite dependency closure for macOS."""

import argparse
import datetime
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


APP_DIR = Path(__file__).resolve().parent.parent / "MacPlayer"
SYSTEM_PREFIXES = ("/usr/lib/", "/System/Library/")
FFMPEG_COMPONENTS = ("libavformat", "libavcodec", "libswscale", "libavutil")


def run(*args):
    result = subprocess.run([str(arg) for arg in args], capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError(f"{' '.join(map(str, args))}\n{result.stderr.strip()}")
    return result.stdout.strip()


def linked_libraries(binary):
    return [line.strip().split(" (compatibility version", 1)[0]
            for line in run("otool", "-L", binary).splitlines()[1:] if line.strip()]


def rpaths(binary):
    return re.findall(r"cmd LC_RPATH\s+cmdsize \d+\s+path (.*?) \(offset",
                      run("otool", "-l", binary))


def verify(deps):
    manifest = json.loads((deps / "manifest.json").read_text())
    lib_dir = deps / "lib"
    for name, info in manifest["libraries"].items():
        binary = lib_dir / name
        if hashlib.sha256(binary.read_bytes()).hexdigest() != info["sha256"]:
            raise RuntimeError(f"Bundled library changed: {name}")
        run("codesign", "--verify", "--strict", binary)
        for dep in linked_libraries(binary):
            if dep.startswith(SYSTEM_PREFIXES):
                continue
            if not dep.startswith(("@loader_path/", "@rpath/")):
                raise RuntimeError(f"Unbundled dependency in {name}: {dep}")
            if not (lib_dir / dep.split("/", 1)[1]).is_file():
                raise RuntimeError(f"Missing dependency in {name}: {dep}")
    for name in manifest["linker_aliases"]:
        if not (lib_dir / name).is_file():
            raise RuntimeError(f"Missing linker alias: {name}")
    print(f"Verified {len(manifest['libraries'])} signed libraries.")


def bundle():
    brew_prefix = Path(run("brew", "--prefix")).resolve()
    cellar = Path(run("brew", "--cellar")).resolve()
    prefixes = {name: Path(run("brew", "--prefix", name))
                for name in ("mpv", "ffmpeg", "sqlite")}
    roots = [prefixes["mpv"] / "lib/libmpv.dylib",
             prefixes["sqlite"] / "lib/libsqlite3.dylib"]
    roots += [prefixes["ffmpeg"] / f"lib/{name}.dylib" for name in FFMPEG_COMPONENTS]

    # Build the whole dependency graph before touching the existing bundle.
    graph = {}
    names = {}

    def resolve(dep, owner):
        if dep.startswith("@loader_path/"):
            candidates = [owner.parent / dep[len("@loader_path/"):]]
        elif dep.startswith("@rpath/"):
            suffix = dep[len("@rpath/"):]
            candidates = [Path(entry.replace("@loader_path", str(owner.parent))) / suffix
                          for entry in rpaths(owner)]
            candidates += [owner.parent / suffix, brew_prefix / "lib" / suffix]
        else:
            candidates = [Path(dep)]
        for candidate in candidates:
            if candidate.is_file():
                return candidate.resolve()
        raise RuntimeError(f"Cannot resolve {dep} referenced by {owner}")

    def collect(source):
        source = source.resolve(strict=True)
        if source in graph:
            return
        if brew_prefix not in source.parents:
            raise RuntimeError(f"Unexpected non-Homebrew dependency: {source}")
        if source.name in names and names[source.name] != source:
            raise RuntimeError(f"Library filename collision: {source.name}")
        names[source.name] = source
        graph[source] = {}
        for dep in linked_libraries(source):
            if dep.startswith(SYSTEM_PREFIXES):
                continue
            target = resolve(dep, source)
            if target != source:
                graph[source][dep] = target
                collect(target)

    for root in roots:
        collect(root)

    with tempfile.TemporaryDirectory(prefix=".deps-stage-", dir=APP_DIR) as work:
        stage = Path(work) / "deps"
        lib_dir = stage / "lib"
        include_dir = stage / "include"
        lib_dir.mkdir(parents=True)
        include_dir.mkdir()
        shutil.copytree(prefixes["mpv"] / "include/mpv", include_dir / "mpv")
        for name in FFMPEG_COMPONENTS:
            shutil.copytree(prefixes["ffmpeg"] / "include" / name, include_dir / name)
        sqlite_include = include_dir / "MacPlayerSQLite"
        sqlite_include.mkdir()
        shutil.copy2(prefixes["sqlite"] / "include/sqlite3.h", sqlite_include)
        (sqlite_include / "module.modulemap").write_text(
            'module MacPlayerSQLite [system] {\n'
            '  header "sqlite3.h"\n'
            '  link "sqlite3"\n'
            '  export *\n'
            '}\n')

        manifest = {
            "generated_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "formulae": {}, "libraries": {}, "linker_aliases": {},
        }
        for source, dependencies in sorted(graph.items()):
            target = lib_dir / source.name
            shutil.copy2(source, target)
            target.chmod(0o755)
            changes = ["install_name_tool", "-id", f"@rpath/{source.name}"]
            for old, dependency in dependencies.items():
                changes += ["-change", old, f"@loader_path/{dependency.name}"]
            for entry in dict.fromkeys(rpaths(source)):
                changes += ["-delete_rpath", entry]
            run(*changes, target)
            # Editing Mach-O load commands invalidates Homebrew's signature.
            run("codesign", "--force", "--sign", "-", "--timestamp=none", target)
            formula, version = source.relative_to(cellar).parts[:2]
            previous = manifest["formulae"].setdefault(formula, version)
            if previous != version:
                raise RuntimeError(f"Mixed versions of {formula}: {previous}, {version}")
            manifest["libraries"][source.name] = {
                "formula": formula,
                "version": version,
                "sha256": hashlib.sha256(target.read_bytes()).hexdigest(),
            }

        for root in roots:
            name = root.resolve().name
            if root.name != name:
                (lib_dir / root.name).symlink_to(name)
                manifest["linker_aliases"][root.name] = name
        (stage / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
        verify(stage)

        # Commit headers and libraries together; preserve the old bundle on failure.
        destination = APP_DIR / "deps"
        backup = Path(work) / "previous"
        if destination.exists():
            destination.rename(backup)
        try:
            stage.rename(destination)
        except BaseException:
            if backup.exists():
                backup.rename(destination)
            raise
        print(f"Bundled {len(graph)} libraries from {len(manifest['formulae'])} formulae.")
        for name, version in sorted(manifest["formulae"].items()):
            print(f"  {name}: {version}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verify", action="store_true", help="Verify the existing bundle only")
    args = parser.parse_args()
    try:
        verify(APP_DIR / "deps") if args.verify else bundle()
    except (OSError, ValueError, RuntimeError) as error:
        parser.exit(1, f"Bundling failed: {error}\n")
