#!/usr/bin/env python3
"""Version and Homebrew metadata for the single production release channel."""
import argparse
import hashlib
import re
from pathlib import Path

SEMVER = re.compile(r"^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$")
SHA = re.compile(r"^[0-9a-f]{40}$")
REPOSITORY = "maxmeis/hypermug"


def next_version(tags, source_sha, run_number):
    """Reserve v0.3.N for workflow run N, regardless of queue order.

    The migration starts after the already-published v0.3.0 release. GitHub
    keeps run_number stable across attempts, so retries retain one identity.
    """
    if not SHA.fullmatch(source_sha):
        raise ValueError("invalid source SHA")
    if not isinstance(run_number, int) or run_number < 1:
        raise ValueError("run number must be a positive integer")
    version = f"0.3.{run_number}"
    target = "v" + version
    for tag, sha in tags:
        if tag == target:
            if sha != source_sha:
                raise ValueError(f"{target} already belongs to another source commit")
            return version, True
    return version, False


def render_cask(version, digest, repository=REPOSITORY):
    if not SEMVER.fullmatch("v" + version) or not re.fullmatch(r"[0-9a-f]{64}", digest):
        raise ValueError("invalid version or archive digest")
    if repository != REPOSITORY:
        raise ValueError("release must use this repository")
    return f'''cask "hypermug" do
  version "{version}"
  sha256 "{digest}"

  url "https://github.com/{repository}/releases/download/v{version}/HyperMug-{version}.zip"
  name "HyperMug"
  desc "Caps Lock remapping, caffeine, and mouse controls for macOS"
  homepage "https://github.com/{repository}"

  livecheck do
    skip "Cask versions follow the published production artifacts"
  end

  depends_on macos: ">= :sonoma"
  depends_on arch: :arm64
  conflicts_with cask: "hypermug@canary"
  conflicts_with cask: "hypermug@nightly"
  app "HyperMug.app"
end
'''


def main():
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    version = sub.add_parser("version")
    version.add_argument("--tags", type=Path, required=True)
    version.add_argument("--source-sha", required=True)
    version.add_argument("--run-number", type=int, required=True)
    cask = sub.add_parser("cask")
    cask.add_argument("--version", required=True)
    cask.add_argument("--zip", type=Path, required=True)
    cask.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.command == "version":
        tags = []
        for line in args.tags.read_text().splitlines():
            tag, sha = line.split(" ", 1)
            tags.append((tag, sha))
        print(next_version(tags, args.source_sha, args.run_number)[0])
    else:
        digest = hashlib.sha256(args.zip.read_bytes()).hexdigest()
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(render_cask(args.version, digest))


if __name__ == "__main__":
    main()
