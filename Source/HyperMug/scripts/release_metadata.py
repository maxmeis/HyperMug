#!/usr/bin/env python3
"""Validate release inputs and render immutable release metadata."""
import argparse
import hashlib
import re
from pathlib import Path
from urllib.parse import quote
from xml.sax.saxutils import escape

SEMVER = re.compile(r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$")
REPO = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")
SHA = re.compile(r"^[0-9a-f]{40}$")


def validate(channel, version, actor, triggering_actor, ref, sha, source_repo, releases_repo, tap_repo):
    if channel != "stable" or not all(REPO.fullmatch(r) for r in (source_repo, releases_repo, tap_repo)):
        raise ValueError("production channel and valid repositories required")
    if ref != f"refs/tags/v{version}" or not SHA.fullmatch(sha):
        raise ValueError("release requires a version tag and full commit SHA")
    if actor != "maxmeis" or triggering_actor != "maxmeis":
        raise ValueError("production requires both actor and triggering_actor maxmeis")
    if not SEMVER.fullmatch(version):
        raise ValueError("version must be X.Y.Z")


def asset_url(repo, tag, name):
    return f"https://github.com/{repo}/releases/download/{quote(tag)}/{quote(name)}"


def appcast(channel, version, build_number, url, signature, size):
    if not re.fullmatch(r"[0-9]+(?:\.[0-9]+){0,2}", str(build_number)) or not re.fullmatch(r"[A-Za-z0-9+/=]+", signature):
        raise ValueError("invalid build number or EdDSA signature")
    short_version = version
    e = lambda s: escape(str(s), {'"': '&quot;', "'": '&apos;'})
    return f'''<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
<channel><title>HyperMug {e(channel)} updates</title><item>
<title>HyperMug {e(version)}</title>
<sparkle:version>{e(build_number)}</sparkle:version>
<sparkle:shortVersionString>{e(short_version)}</sparkle:shortVersionString>
<enclosure url="{e(url)}" sparkle:edSignature="{e(signature)}" length="{size}" type="application/zip" />
</item></channel></rss>
'''


def cask(channel, version, url, digest):
    if not re.fullmatch(r"[0-9a-f]{64}", digest):
        raise ValueError("invalid SHA256")
    token = "hypermug"
    cask_version = version
    return f'''cask "{token}" do
  version "{cask_version}"
  sha256 "{digest}"

  url "{url}"
  name "HyperMug"
  desc "Caps Lock remapping, caffeine, and mouse controls for macOS"
  homepage "https://github.com/maxmeis/HyperMug"

  livecheck do
    skip "GitHub release assets are published by production automation"
  end

  auto_updates true
  depends_on macos: ">= :sonoma"
  depends_on arch: :arm64
  app "HyperMug.app"
end
'''



def stable_order(candidate, existing, retry=False):
    """Reject a stable downgrade, including one hidden by an incomplete publication."""
    if not SEMVER.fullmatch(candidate):
        raise ValueError("invalid stable version")
    current = tuple(map(int, candidate.split(".")))
    for tag in existing:
        version = tag.removeprefix("v")
        if not SEMVER.fullmatch(version):
            continue
        prior = tuple(map(int, version.split(".")))
        if current < prior or (current == prior and not retry):
            raise ValueError(f"stable version {candidate} is not newer than {version}")


def publication_decision(channel, version, build_number, current_version, current_build):
    """Return advance, resume, or archive for a published channel pointer."""
    if not current_version:
        return "advance"
    new = tuple(map(int, version.split(".")))
    old = tuple(map(int, current_version.split(".")))
    if new < old:
        return "archive"
    if new == old:
        return "resume"
    return "advance"

def main():
    p = argparse.ArgumentParser()
    p.add_argument("command", choices=("validate", "render"))
    for name in ("channel", "version", "actor", "triggering-actor", "ref", "sha", "source-repo", "releases-repo", "tap-repo"):
        p.add_argument("--" + name, required=True)
    p.add_argument("--build-number")
    p.add_argument("--zip")
    p.add_argument("--signature")
    p.add_argument("--output")
    a = p.parse_args()
    validate(a.channel, a.version, a.actor, a.triggering_actor, a.ref, a.sha, a.source_repo, a.releases_repo, a.tap_repo)
    if a.command == "validate":
        return
    if not all((a.build_number, a.zip, a.signature, a.output)):
        p.error("render requires --build-number, --zip, --signature, --output")
    archive = Path(a.zip)
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    url = asset_url(a.releases_repo, "v" + a.version, archive.name)
    out = Path(a.output)
    out.mkdir(parents=True, exist_ok=True)
    (out / f"appcast-{a.channel}.xml").write_text(appcast(a.channel, a.version, a.build_number, url, a.signature, archive.stat().st_size))
    token = "hypermug"
    (out / f"{token}.rb").write_text(cask(a.channel, a.version, url, digest))
    (out / "sha256.txt").write_text(digest + "\n")


if __name__ == "__main__":
    main()
