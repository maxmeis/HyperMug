#!/usr/bin/env python3
"""Check this skill's local Markdown links and one-hop reference routing."""

from __future__ import annotations

import argparse
from pathlib import Path
import re
from urllib.parse import unquote, urlsplit


LINK = re.compile(r"(?<!!)\[[^\]]+\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")


def check(root: Path) -> list[str]:
    root = root.resolve()
    entry = root / "SKILL.md"
    if not entry.is_file():
        return [f"missing entrypoint: {entry}"]

    errors: list[str] = []
    routes: set[Path] = set()
    markdown_files = [entry, *sorted((root / "references").glob("*.md"))]
    for source in markdown_files:
        content = source.read_text(encoding="utf-8")
        for match in LINK.finditer(content):
            target = match.group(1)
            parsed = urlsplit(target)
            if parsed.scheme or parsed.netloc or not parsed.path:
                continue
            line = content.count("\n", 0, match.start()) + 1
            path = (source.parent / unquote(parsed.path)).resolve()
            try:
                path.relative_to(root)
            except ValueError:
                errors.append(f"{source.relative_to(root)}:{line}: link escapes skill: {target}")
                continue
            if not path.is_file():
                errors.append(f"{source.relative_to(root)}:{line}: missing file: {target}")
            if source == entry:
                routes.add(path)

    for reference in sorted((root / "references").glob("*.md")):
        if reference.resolve() not in routes:
            errors.append(f"SKILL.md: no direct route to {reference.relative_to(root)}")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("skill", nargs="?", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    errors = check(args.skill)
    if errors:
        print("\n".join(errors))
        return 1
    print("Local links and direct reference routes are valid.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
