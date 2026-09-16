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
import subprocess
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


# LIC_FILES_CHKSUM uses file:// too, and means something else by it: a path
# inside the fetched source, not a file this layer ships. The recipes that
# name a poky licence get away with it because their path starts with
# ${COMMON_LICENSE_DIR} and is skipped as a variable, but a recipe fetching
# its own tree writes file://LICENSE;md5=..., which this check would then
# demand be added to files/. Removing the assignment before scanning is the
# fix; matching on the variable name is what makes it exact.
LIC_CHKSUM = re.compile(r'LIC_FILES_CHKSUM\s*=\s*"(?:[^"\\]|\\.)*"', re.S)


def recipe_files(recipe: Path) -> tuple[set[str], str]:
    body = text(recipe)
    wanted = set(re.findall(r'file://([^\s"]+)', LIC_CHKSUM.sub("", body)))
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


def check_src_uri_installed() -> None:
    """A file fetched but never installed is a file that is not in the image.

    This one is written from a specific failure. Two files were added to
    SRC_URI and the do_install lines that should have gone with them were
    lost in editing. The build succeeded, the layer linted clean, the image
    flashed, and the first-boot script died on a missing template with
    set -e, taking the access point down with it. Nothing between the edit
    and the board noticed.

    The check is deliberately crude: it asks whether the name appears
    anywhere after do_install begins. A recipe that installs a file under a
    different name, or through a loop, has to say so in a comment
    containing the name, which is cheap and is the sort of thing worth
    writing down anyway.

    Source is exempt. A .c or .h file is consumed by do_compile and the
    thing that gets installed is a binary with a different name, so
    demanding it appear here would be asking a recipe to lie.
    """
    compiled = {".c", ".h"}
    for recipe in list(ROOT.rglob("*.bb")) + list(ROOT.rglob("*.bbappend")):
        if ".git" in recipe.parts:
            continue
        body = text(recipe)
        start = body.find("do_install")
        if start < 0:
            continue
        install = body[start:]
        wanted, _ = recipe_files(recipe)
        for name in sorted(wanted):
            if name.startswith("${") or Path(name).suffix in compiled:
                continue
            if name not in install:
                fail(recipe, f"SRC_URI names {name}, which do_install never "
                             "mentions")


def check_image_packages() -> None:
    """An image recipe must install the drivers and firmware it talks about.

    Written from a defect that cost a build and a reflash. The recipe's
    comments explained at length why kernel-module-rtl8xxxu and
    linux-firmware-rtl8192eu were needed, and the IMAGE_INSTALL line named
    neither, because an edit was lost. BitBake cannot notice: a package
    nobody asks for is simply absent, and the image builds, flashes and
    boots without it. The board says so by not having a network interface.

    Only kernel-module-* and linux-firmware-* are checked. Those two
    prefixes are unambiguously package names, and they are the pairing that
    goes wrong: Project 1 lost two rounds to a driver without its module
    package and then to a vendor module nobody had named. Ordinary package
    names are left alone because a comment may legitimately name one it
    rejected.
    """
    pattern = re.compile(r"\b((?:kernel-module|linux-firmware)-[a-z0-9-]+)\b")

    def installs(recipe: Path, seen: set[Path]) -> set[str]:
        """What this recipe installs, plus whatever it requires.

        The variant images say "require recipes-core/images/bench-image.bb"
        and inherit its package list, so a comment in bench-ble-image about
        the radio firmware is talking about something bench-image already
        installs. Without following the require, this check would report
        every variant as broken.
        """
        if recipe in seen or not recipe.is_file():
            return set()
        seen.add(recipe)
        body = text(recipe)
        found: set[str] = set()
        for value in re.findall(r'IMAGE_INSTALL:append\s*=\s*"([^"]*)"', body):
            found |= set(value.replace(chr(92), " ").split())
        for required in re.findall(r"^require\s+(\S+)", body, re.M):
            found |= installs(ROOT / "meta-bench" / required, seen)
        return found

    images = [r for r in ROOT.rglob("*-image*.bb") if ".git" not in r.parts]

    # A comment may legitimately name a package a sibling image installs:
    # bench-hub-image explains itself by pointing at what the real-time
    # image does. So the question is not "does this recipe install it" but
    # "does anything here install it". That is weaker and it still catches
    # the case it was written for, where a driver and its firmware were
    # described in three paragraphs and named in no image at all.
    anywhere: set[str] = set()
    for recipe in images:
        anywhere |= installs(recipe, set())

    for recipe in images:
        body = text(recipe)
        if "IMAGE_INSTALL" not in body:
            continue
        comments = "\n".join(
            line for line in body.splitlines() if line.lstrip().startswith("#")
        )
        for name in sorted(set(pattern.findall(comments))):
            if name not in anywhere:
                fail(recipe, f"a comment names {name}, which no image "
                             "installs")


def check_systemd_units() -> None:
    """A unit in SYSTEMD_SERVICE that do_install misses fails late and loudly."""
    for recipe in ROOT.rglob("*.bb"):
        if ".git" in recipe.parts:
            continue
        body = text(recipe)
        match = re.search(r'SYSTEMD_SERVICE:\$\{PN\}\s*=\s*"([^"]*)"', body)
        if not match:
            continue
        # A multi-line SYSTEMD_SERVICE is ordinary BitBake, and its line
        # continuations are not unit names. Dropping them is not cosmetic:
        # "files" / chr(92) is a path that exists on Windows, because the
        # backslash is a separator there and it resolves to files/ itself,
        # and does not exist on Linux. So this check passed on the laptop
        # that wrote the recipe and failed in CI, which is the worst
        # possible place for a linter to disagree with itself.
        units = match.group(1).replace(chr(92), " ").split()
        for unit in units:
            if unit not in body:
                fail(recipe, f"SYSTEMD_SERVICE lists {unit}, never installed")
            if not (recipe.parent / "files" / unit).exists():
                fail(recipe, f"SYSTEMD_SERVICE lists {unit}, not in files/")


def shell_files() -> list[Path]:
    """Every file CI runs shellcheck over, found the way CI finds them.

    Two sources, because common.sh is sourced and has no shebang while
    bench-state, rt-run and their kind have a shebang and no extension.
    """
    found = {p for p in ROOT.rglob("*.sh") if ".git" not in p.parts}
    for path in ROOT.rglob("*"):
        if not path.is_file() or ".git" in path.parts:
            continue
        if path.suffix in {".md", ".png", ".jpg", ".pdf", ".pyc"}:
            continue
        try:
            with open(path, "rb") as handle:
                if handle.read(9) == b"#!/bin/sh":
                    found.add(path)
        except OSError:
            continue
    return sorted(found)


# An assignment is not subject to word splitting; an argument to a command
# is. So "VAR=$X" is safe and "export VAR=$X" is not, which is shellcheck's
# SC2086. CI runs shellcheck at its default severity, where an "info" fails
# the build exactly as an error does.
EXPORT_SPLIT = re.compile(
    r"^\s*(?:export|readonly)\s+[A-Za-z_][A-Za-z0-9_]*="
    r"(?![\"'])[^\s\"']*\$"
)


def check_shell_exports() -> None:
    """The one shellcheck finding this machine keeps shipping to CI.

    The authoring laptop has no shellcheck, so the only thing that sees
    SC2086 is the runner, and this exact pattern has now reached it twice:
    once in the rt-* tests, fixed by somebody else, and once in kas-run and
    kernel-config, four instances between them. A general reimplementation
    of shellcheck here would be foolish; one rule for the one mistake that
    structurally cannot be caught locally is not.
    """
    for path in shell_files():
        for number, line in enumerate(text(path).splitlines(), 1):
            if EXPORT_SPLIT.match(line):
                fail(path, f"line {number}: export with an unquoted "
                           f"expansion, which shellcheck rejects as SC2086")


def check_shell_unused_params() -> None:
    """The second shellcheck finding this machine keeps shipping to CI.

    A helper written as

        run() { sh "$sut" "$@" 2>&1; }

    and then called everywhere as a bare `run` is SC2120, with an SC2119 at
    every call site. It is the natural shape for a test harness wrapper and
    I have now written it twice, so it reaches the runner rather than the
    linter for the same structural reason SC2086 did: there is no
    shellcheck here.

    Deliberately narrow, and it errs towards silence:

      - only functions whose body forwards "$@"
      - only when the function is called at least once
      - only when NO call site passes anything

    So a helper used both ways is not flagged, and neither is one that is
    defined for callers elsewhere. Reimplementing shellcheck would be
    foolish; two rules for the two mistakes that cannot be caught locally
    are not.
    """
    define = re.compile(r'^\s*([A-Za-z_][A-Za-z0-9_]*)\s*\(\)\s*\{')
    for path in shell_files():
        lines = text(path).splitlines()
        bodies: dict[str, list[str]] = {}
        current = None
        for line in lines:
            match = define.match(line)
            if match:
                current = match.group(1)
                bodies[current] = []
                continue
            if current is not None:
                if line.startswith("}"):
                    current = None
                else:
                    bodies[current].append(line)

        for name, body in bodies.items():
            if not any('"$@"' in line for line in body):
                continue
            called_bare = 0
            called_with_args = 0
            call = re.compile(r'(^|[\s;(`]|\$\()' + re.escape(name) + r'(\s|$|\)|;|\|)')
            for line in lines:
                if define.match(line):
                    continue
                # Comments, and the comment half of a line, are prose. The
                # first version of this did not strip them, and the word
                # "run" in a sentence about running something counted as a
                # call with arguments, which silenced the rule on the very
                # file it was written for. Found by reintroducing the bug
                # and watching nothing happen.
                code = line.split("#", 1)[0]
                if not code.strip():
                    continue
                match = call.search(code)
                if not match:
                    continue
                rest = code[match.end(0) - len(match.group(2)):].strip()
                if rest and rest[0] not in ")|;&":
                    called_with_args += 1
                else:
                    called_bare += 1
            if called_bare and not called_with_args:
                fail(path, f"{name}() forwards \"$@\" but every call passes "
                           f"nothing, which shellcheck rejects as SC2120")


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
    path = ROOT / "meta-bench" / "conf" / "layer.conf"
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


def check_exec_bits() -> None:
    """A script with a shebang must be recorded executable in the index.

    Git on Windows defaults to core.filemode=false, so a chmod on that side
    never reaches the commit and the file arrives on Linux as 644. The
    symptom is "Permission denied" after a clone, a long way from the cause,
    so the mode is checked here rather than trusted.
    """
    try:
        listing = subprocess.run(
            ["git", "ls-files", "--stage"],
            cwd=ROOT, capture_output=True, text=True, check=True,
        ).stdout
    except (subprocess.CalledProcessError, FileNotFoundError):
        print("note: not a git checkout, executable bits not checked")
        return

    for entry in listing.splitlines():
        fields = entry.split(maxsplit=3)
        if len(fields) < 4:
            continue
        mode, name = fields[0], fields[3].strip()
        path = ROOT / name
        if not path.is_file():
            continue
        try:
            with open(path, "rb") as handle:
                shebang = handle.read(2) == b"#!"
        except OSError:
            continue
        if shebang and mode != "100755":
            fail(path, f"has a shebang but is committed as {mode}, not 100755")
        if not shebang and mode == "100755":
            fail(path, "is committed executable but has no shebang")

    check_untracked_scripts()


def check_untracked_scripts() -> None:
    """A new script has no index entry, so the check above cannot see it.

    This is how tests/common-test.sh reached CI as 644. It was written,
    chmod +x'd on Windows where that changes nothing git records, linted
    while still untracked, and only then added and committed. Every step
    reported success and the mode check simply had nothing to look at.

    The check above reads "git ls-files --stage". An untracked file is not
    in that listing at all, so a brand new script is exactly the case it
    cannot cover, which is also the only case where the mode is likely to
    be wrong.

    So: name untracked shebang files, and say the command. This is a note
    rather than a failure, because an untracked file is not yet a claim
    about anything and a working tree may hold scratch scripts on purpose.
    """
    try:
        listing = subprocess.run(
            ["git", "ls-files", "--others", "--exclude-standard"],
            cwd=ROOT, capture_output=True, text=True, check=True,
        ).stdout
    except (subprocess.CalledProcessError, FileNotFoundError):
        return

    pending = []
    for name in listing.splitlines():
        path = ROOT / name.strip()
        if not path.is_file():
            continue
        try:
            with open(path, "rb") as handle:
                if handle.read(2) != b"#!":
                    continue
        except OSError:
            continue
        pending.append(name.strip())

    if not pending:
        return

    print("note: untracked scripts, whose mode is not checked until staged:")
    for name in pending:
        print(f"      {name}")
    print("      git add them, then:  git update-index --chmod=+x <file>")
    print("      and run this again. On Windows chmod alone does not do it.")


def markdown_link_targets(text: str) -> list[str]:
    """Link targets, found without a regex so the pattern stays readable."""
    out: list[str] = []
    index = 0
    while True:
        open_paren = text.find("](", index)
        if open_paren < 0:
            return out
        close = text.find(")", open_paren + 2)
        if close < 0:
            return out
        out.append(text[open_paren + 2:close])
        index = close + 1


def check_markdown() -> None:
    """Relative links must resolve, and code fences must balance.

    Twenty projects of documentation will rot their own cross-references
    unless something checks them, and a broken link in a portfolio repository
    is read as carelessness rather than as drift.
    """
    fence = "```"
    for path in ROOT.rglob("*.md"):
        if ".git" in path.parts:
            continue
        content = text(path)

        count = content.count(fence)
        if count % 2:
            fail(path, f"odd number of code fences ({count})")

        for target in markdown_link_targets(content):
            if target.startswith(("http://", "https://", "#", "mailto:")):
                continue
            anchor = target.split("#")[0]
            if not anchor:
                continue
            if not (path.parent / anchor).exists():
                fail(path, f"broken link: {target}")


def main() -> int:
    for check in (
        check_ascii,
        check_dashes,
        check_src_uri,
        check_shell_exports,
        check_shell_unused_params,
        check_src_uri_installed,
        check_image_packages,
        check_systemd_units,
        check_license_headers,
        check_kas,
        check_layer_conf,
        check_line_length,
        check_exec_bits,
        check_markdown,
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
