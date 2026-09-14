#!/usr/bin/env python3
"""Static checks that need no Yocto host.

A full layer check is `yocto-check-layer`, which needs poky and an hour.
This runs in a second and catches the mistakes that actually happen while
editing a layer: a file listed in SRC_URI that was never added, a unit in
SYSTEMD_SERVICE that do_install does not install, a kas file that stopped
being valid YAML, a non-ASCII character that breaks a recipe on a host with
a different locale.

    python3 scripts/lint.py

Exit status is non-zero if anything failed, so CI can use it directly.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROBLEMS: list[str] = []

# Em dash and en dash, spelled as code points.
DASHES = (chr(0x2014), chr(0x2013))


def fail(path: Path, message: str) -> None:
    PROBLEMS.append(f"{path.relative_to(ROOT).as_posix()}: {message}")


def text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def check_ascii() -> None:
    """Recipes and shell scripts stay ASCII; prose may use whatever it needs."""
    patterns = ("*.bb", "*.bbappend", "*.conf", "*.c", "*.cfg", "*.yml", "*.sh")
    for pattern in patterns:
        for path in ROOT.rglob(pattern):
            if ".git" in path.parts:
                continue
            for number, line in enumerate(text(path).splitlines(), 1):
                bad = [c for c in line if ord(c) > 127]
                if bad:
                    fail(path, f"line {number}: non-ASCII {bad!r}")


def check_dashes() -> None:
    """House rule: no em or en dashes anywhere in the repository."""
    for path in ROOT.rglob("*"):
        if not path.is_file() or ".git" in path.parts:
            continue
        if path.suffix in {".png", ".jpg", ".pdf"}:
            continue
        try:
            content = text(path)
        except (UnicodeDecodeError, OSError):
            continue
        for number, line in enumerate(content.splitlines(), 1):
            # Spelled as escapes so that this file passes its own check.
            # Built with chr() so that this file passes its own check.
            if DASHES[0] in line or DASHES[1] in line:
                fail(path, f"line {number}: em or en dash")


def recipe_files(recipe: Path) -> tuple[set[str], str]:
    body = text(recipe)
    wanted = set(re.findall(r'file://([^\s"]+)', body))
    return wanted, body


def check_src_uri() -> None:
    """Every file:// entry must exist, and every file must be referenced."""
    for recipe in list(ROOT.rglob("*.bb")) + list(ROOT.rglob("*.bbappend")):
        if ".git" in recipe.parts:
            continue
        wanted, _ = recipe_files(recipe)
        files_dir = recipe.parent / "files"
        for name in sorted(wanted):
            if name.startswith("${"):
                continue
            if not (files_dir / name).exists():
                fail(recipe, f"SRC_URI names {name}, which is not in files/")
        if files_dir.is_dir():
            present = {p.name for p in files_dir.iterdir() if p.is_file()}
            for name in sorted(present - wanted):
                fail(recipe, f"files/{name} is not in SRC_URI")


def check_systemd_units() -> None:
    """A unit in SYSTEMD_SERVICE that do_install misses fails late and loudly."""
    for recipe in ROOT.rglob("*.bb"):
        if ".git" in recipe.parts:
            continue
        body = text(recipe)
        match = re.search(r'SYSTEMD_SERVICE:\$\{PN\}\s*=\s*"([^"]*)"', body)
        if not match:
            continue
        for unit in match.group(1).split():
            if unit not in body:
                fail(recipe, f"SYSTEMD_SERVICE lists {unit}, never installed")
            if not (recipe.parent / "files" / unit).exists():
                fail(recipe, f"SYSTEMD_SERVICE lists {unit}, not in files/")


def check_license_headers() -> None:
    for path in list(ROOT.rglob("*.c")) + list(ROOT.rglob("*.sh")):
        if ".git" in path.parts:
            continue
        if "SPDX-License-Identifier" not in text(path):
            fail(path, "no SPDX-License-Identifier")


def check_kas() -> None:
    try:
        import yaml
    except ImportError:
        print("note: PyYAML absent, kas files parsed as text only")
        yaml = None

    for path in (ROOT / "kas").glob("*.yml"):
        content = text(path)
        if yaml is not None:
            try:
                document = yaml.safe_load(content)
            except yaml.YAMLError as error:
                fail(path, f"invalid YAML: {error}")
                continue
            if not isinstance(document, dict) or "header" not in document:
                fail(path, "no header section")
                continue
            version = document["header"].get("version")
            if version is None:
                fail(path, "header has no version")
        if "\t" in content:
            fail(path, "tab character in YAML")


def check_layer_conf() -> None:
    path = ROOT / "conf" / "layer.conf"
    body = text(path)
    collection = re.search(r'BBFILE_COLLECTIONS\s*\+=\s*"([^"]+)"', body)
    if not collection:
        fail(path, "no BBFILE_COLLECTIONS")
        return
    name = collection.group(1).strip()
    for variable in ("BBFILE_PATTERN", "BBFILE_PRIORITY", "LAYERSERIES_COMPAT"):
        if f"{variable}_{name}" not in body:
            fail(path, f"{variable}_{name} is missing")


def check_line_length() -> None:
    for path in list(ROOT.rglob("*.c")) + list(ROOT.rglob("*.bb")):
        if ".git" in path.parts:
            continue
        for number, line in enumerate(text(path).splitlines(), 1):
            if len(line.expandtabs(8)) > 88:
                fail(path, f"line {number}: longer than 88 columns")


def main() -> int:
    for check in (
        check_ascii,
        check_dashes,
        check_src_uri,
        check_systemd_units,
        check_license_headers,
        check_kas,
        check_layer_conf,
        check_line_length,
    ):
        check()

    if PROBLEMS:
        for problem in PROBLEMS:
            print(problem)
        print(f"\n{len(PROBLEMS)} problem(s)")
        return 1

    print("lint: clean")
    return 0


if __name__ == "__main__":
    sys.exit(main())
