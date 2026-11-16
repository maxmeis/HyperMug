#!/usr/bin/env python3
"""Check local documentation links and deployable website references."""
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlparse, unquote
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
WEBSITE = ROOT / "Source/Website"
DOCS = [ROOT / "README.md", ROOT / "CONTRIBUTING.md", ROOT / "Casks/README.md", *sorted((ROOT / "docs").glob("*.md"))]
LINK = re.compile(r"(?<!!)\[[^]]+\]\(([^)]+)\)")


def fragment_exists(path, fragment):
    if not fragment:
        return True
    text = path.read_text()
    # GitHub heading anchors normalize punctuation and spaces. These docs use
    # simple headings, so an explicit local heading is enough to catch drift.
    headings = re.findall(r"^#{1,6}\s+(.+)$", text, re.MULTILINE)
    slugs = [re.sub(r"[^\w -]", "", h.casefold()).strip().replace(" ", "-") for h in headings]
    return unquote(fragment).casefold() in slugs


def check_docs():
    errors = []
    for doc in DOCS:
        for target in LINK.findall(doc.read_text()):
            parsed = urlparse(target)
            if parsed.scheme or parsed.netloc:
                continue
            linked = (doc.parent / unquote(parsed.path)).resolve() if parsed.path else doc
            if not linked.is_file() or (parsed.fragment and not fragment_exists(linked, parsed.fragment)):
                errors.append(f"{doc.relative_to(ROOT)}: broken link {target}")
    return errors


class SiteParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.ids = set()
        self.refs = []

    def handle_starttag(self, tag, attrs):
        data = dict(attrs)
        if data.get("id"):
            self.ids.add(data["id"])
        if tag in {"a", "link", "script", "img"}:
            ref = data.get("href") or data.get("src")
            if ref:
                self.refs.append(ref)


def check_site():
    parser = SiteParser()
    parser.feed((WEBSITE / "index.html").read_text())
    errors = []
    for ref in parser.refs:
        parsed = urlparse(ref)
        if parsed.scheme or parsed.netloc:
            # The published site links to repository docs; keep those paths valid.
            prefix = "/maxmeis/hypermug/blob/main/"
            if parsed.netloc == "github.com" and parsed.path.startswith(prefix):
                local = ROOT / unquote(parsed.path[len(prefix):])
                if not local.is_file():
                    errors.append(f"Source/Website/index.html: missing repository document {ref}")
            continue
        if not parsed.path and parsed.fragment:
            if parsed.fragment not in parser.ids:
                errors.append(f"Source/Website/index.html: missing anchor {ref}")
            continue
        local = (WEBSITE / unquote(parsed.path)).resolve()
        if not local.is_file() or not local.is_relative_to(WEBSITE):
            errors.append(f"Source/Website/index.html: missing asset {ref}")
    return errors


if __name__ == "__main__":
    failures = check_docs() + check_site()
    if failures:
        print("\n".join(failures), file=sys.stderr)
        sys.exit(1)
    print("content links and website assets: ok")
