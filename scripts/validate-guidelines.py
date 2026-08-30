#!/usr/bin/env python3

from __future__ import annotations

import os
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
GUIDELINES = sorted((ROOT / "guidelines").glob("*.md"))
MARKDOWN_FILES = [
    ROOT / "README.md",
    ROOT / "CHANGELOG.md",
    ROOT / "RELEASING.md",
    ROOT / "general.md",
    ROOT / "preferences.md",
    ROOT / "ignores" / "README.md",
    *GUIDELINES,
]


def report(errors: list[str], path: Path, message: str) -> None:
    errors.append(f"{path.relative_to(ROOT)}: {message}")


def validate_markdown(errors: list[str]) -> None:
    local_link = re.compile(r"\[[^]]+\]\(([^)]+)\)")
    section = re.compile(r"^## (\d+)\.", re.MULTILINE)

    for path in MARKDOWN_FILES:
        if not path.is_file():
            report(errors, path, "missing Markdown file")
            continue

        text = path.read_text(encoding="utf-8")
        if "\r" in text:
            report(errors, path, "contains CRLF content")
        if text.count("```") % 2:
            report(errors, path, "contains unbalanced fenced code blocks")
        for line_number, line in enumerate(text.splitlines(), start=1):
            if line.endswith((" ", "\t")):
                report(errors, path, f"line {line_number} has trailing whitespace")
        if re.search(r"/(?:Users|home)/[^/\s]+/", text):
            report(errors, path, "contains an executor-local absolute path")

        numbers = [int(value) for value in section.findall(text)]
        if numbers and numbers != list(range(1, len(numbers) + 1)):
            report(errors, path, f"level-two numbered sections are not sequential: {numbers}")

        for target in local_link.findall(text):
            if "://" in target or target.startswith("mailto:"):
                continue
            local_target = target.split("#", 1)[0]
            if local_target and not (path.parent / local_target).resolve().exists():
                report(errors, path, f"local link target does not exist: {target}")


def validate_catalog(errors: list[str]) -> None:
    readme = (ROOT / "README.md").read_text(encoding="utf-8")
    installer = (ROOT / "install.sh").read_text(encoding="utf-8")
    for path in GUIDELINES:
        relative = path.relative_to(ROOT).as_posix()
        if relative not in readme:
            report(errors, path, "is not linked from README.md")
        if relative not in installer:
            report(errors, path, "is not present in the installer allowlist")


def validate_version(errors: list[str]) -> None:
    version_path = ROOT / "VERSION"
    version = version_path.read_text(encoding="utf-8").strip()
    number = r"(?:0|[1-9]\d*)"
    if not re.fullmatch(rf"{number}\.{number}\.{number}", version):
        report(errors, version_path, f"invalid semantic version: {version!r}")

    installer = (ROOT / "install.sh").read_text(encoding="utf-8")
    match = re.search(r"readonly INSTALLER_VERSION='([^']+)'", installer)
    if match is None or match.group(1) != version:
        report(errors, ROOT / "install.sh", "embedded installer version does not match VERSION")

    changelog = (ROOT / "CHANGELOG.md").read_text(encoding="utf-8")
    if f"## [{version}]" not in changelog:
        report(errors, ROOT / "CHANGELOG.md", f"does not contain release {version}")


def validate_managed_template(errors: list[str]) -> None:
    path = ROOT / "ignores" / "agent.ignore"
    text = path.read_text(encoding="utf-8")
    for marker in (
        "# AI-GUIDELINES-IGNORE:BEGIN",
        "# AI-GUIDELINES-IGNORE:END",
    ):
        if text.splitlines().count(marker) != 1:
            report(errors, path, f"must contain exactly one {marker}")


def validate_executables(errors: list[str]) -> None:
    for relative in (
        "install.sh",
        "tests/install.sh",
        "scripts/generate-checksums.sh",
        "scripts/validate-guidelines.py",
    ):
        path = ROOT / relative
        if not os.access(path, os.X_OK):
            report(errors, path, "must be executable")


def main() -> int:
    errors: list[str] = []
    validate_markdown(errors)
    validate_catalog(errors)
    validate_version(errors)
    validate_managed_template(errors)
    validate_executables(errors)
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print(f"PASS: repository validation ({len(MARKDOWN_FILES)} Markdown files)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
