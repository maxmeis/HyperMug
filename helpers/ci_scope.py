#!/usr/bin/env python3
"""Choose native CI conservatively; only explicitly safe paths can use Linux."""
import argparse
import os
import re
import subprocess
from pathlib import PurePosixPath


SHA = re.compile(r"[0-9a-f]{40}")
CONTENT_FILES = {"README.md", "CONTRIBUTING.md", "Casks/README.md"}
CONTENT_TREES = ("docs/", "Source/Website/", "Source/Skills/")
CASK_FILES = {"Casks/hypermug.rb", "Casks/hypermug@canary.rb"}
# Example configurations are validated by the Core tests, so they need native checks.
TESTED_CONTENT = ("docs/examples/",)


def content_only(paths):
    """Unknown files, empty diffs and noncanonical paths retain native checks."""
    if not paths:
        return False
    for path in paths:
        if str(PurePosixPath(path)) != path or ".." in PurePosixPath(path).parts:
            return False
        if path not in CONTENT_FILES | CASK_FILES and not path.startswith(CONTENT_TREES):
            return False
        if path.startswith(TESTED_CONTENT):
            return False
    return True


def native_required(event, base, head, *, cwd=None):
    if event not in {"push", "pull_request"}:
        return True
    if not all(SHA.fullmatch(value) and value != "0" * 40 for value in (base, head)):
        return True
    try:
        if event == "pull_request":
            base = subprocess.check_output(
                ["git", "merge-base", base, head], cwd=cwd, stderr=subprocess.DEVNULL,
            ).decode().strip()
        # --no-renames includes BOTH sides of a move. NUL separators preserve
        # whitespace/newlines so an odd filename cannot masquerade as a safe one.
        diff = subprocess.check_output(
            ["git", "diff", "--no-renames", "--name-only", "-z", base, head, "--"],
            cwd=cwd, stderr=subprocess.DEVNULL,
        )
        paths = [os.fsdecode(path) for path in diff.split(b"\0") if path]
        return not content_only(paths)
    except (OSError, subprocess.CalledProcessError):
        return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--event", required=True)
    parser.add_argument("--base", default="")
    parser.add_argument("--head", default="")
    args = parser.parse_args()
    native = native_required(args.event, args.base, args.head)
    value = str(native).lower()
    print(f"native={value}")
    if output := os.environ.get("GITHUB_OUTPUT"):
        with open(output, "a") as stream:
            stream.write(f"native={value}\n")


if __name__ == "__main__":
    main()
