#!/usr/bin/env python3
"""Authenticate immutable HyperMug release bytes before Cask promotion on macOS."""
import hashlib
import os
import plistlib
import re
import stat
import unicodedata
import subprocess
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

from release_metadata import asset_url, bundle_identity

# Reviewed channel keys. Changing either key requires a source review and release plan.
PUBLIC_KEYS = {
    "stable": "i4JZLmEK2ZHdkahkxo6caKtUP6zzCnCyh3oNNzC7ODE=",
    "canary": "VivuebCoPtoKfulPO1UeosVODFAHNH0rMWLi/voaXAc=",
}
SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
MAX_FILES = 10000
MAX_UNCOMPRESSED = 1024 * 1024 * 1024


def safe_members(archive):
    """Validate the complete ZIP tree, including links, before extraction."""
    members = {}
    folded = set()
    total = 0
    for info in archive.infolist():
        name = info.filename.rstrip("/")
        parts = name.split("/")
        if (not name or name.startswith("/") or "\\" in name or "\x00" in name
                or any(part in ("", ".", "..") or ":" in part for part in parts)
                or parts[0] != "HyperMug.app"):
            raise ValueError("unsafe ZIP path")
        key = "/".join(parts)
        normalized = unicodedata.normalize("NFD", key).casefold()
        if key in members or normalized in folded:
            raise ValueError("duplicate ZIP path")
        folded.add(normalized)
        mode = info.external_attr >> 16
        kind = stat.S_IFMT(mode)
        if kind not in (0, stat.S_IFREG, stat.S_IFDIR, stat.S_IFLNK):
            raise ValueError("unsupported ZIP entry type")
        if stat.S_ISLNK(mode) and (info.file_size > 4096 or info.is_dir()):
            raise ValueError("invalid ZIP symlink")
        total += info.file_size
        if len(members) >= MAX_FILES or total > MAX_UNCOMPRESSED:
            raise ValueError("ZIP extraction limit exceeded")
        members[key] = (info, kind)
    if "HyperMug.app" not in members or not members["HyperMug.app"][0].is_dir():
        raise ValueError("ZIP must contain one HyperMug app")
    for name, (info, kind) in members.items():
        parts = name.split("/")
        for index in range(1, len(parts)):
            parent = "/".join(parts[:index])
            if parent in members and members[parent][1] == stat.S_IFLNK:
                raise ValueError("ZIP entry descends through a symlink")
        if kind == stat.S_IFLNK:
            target = archive.read(info).decode("utf-8", "strict")
            if not target or target.startswith("/") or "\\" in target or "\x00" in target:
                raise ValueError("unsafe ZIP symlink")
            # Resolve links lexically, following chains while staying inside the app.
            pending = parts[:-1] + target.split("/")
            seen = {name}
            resolved = []
            while pending:
                part = pending.pop(0)
                if part in ("", "."):
                    continue
                if part == "..":
                    if len(resolved) <= 1:
                        raise ValueError("ZIP symlink escapes app")
                    resolved.pop()
                    continue
                resolved.append(part)
                if resolved[0] != "HyperMug.app":
                    raise ValueError("ZIP symlink escapes app")
                joined = "/".join(resolved)
                if joined in members and members[joined][1] == stat.S_IFLNK:
                    if joined in seen:
                        raise ValueError("ZIP symlink cycle")
                    seen.add(joined)
                    link = archive.read(members[joined][0]).decode("utf-8", "strict")
                    if link.startswith("/") or "\\" in link or "\x00" in link:
                        raise ValueError("unsafe ZIP symlink")
                    resolved.pop()
                    pending = link.split("/") + pending
    return members


def extract_safe(zip_path, destination):
    with zipfile.ZipFile(zip_path) as archive:
        members = safe_members(archive)
        destination.mkdir(parents=True, exist_ok=False)
        for name, (info, kind) in members.items():
            if kind == stat.S_IFLNK:
                continue
            path = destination / name
            if info.is_dir() or kind == stat.S_IFDIR:
                path.mkdir(parents=True, exist_ok=True)
            else:
                path.parent.mkdir(parents=True, exist_ok=True)
                with archive.open(info) as source, path.open("xb") as target:
                    while chunk := source.read(1024 * 1024):
                        target.write(chunk)
                os.chmod(path, (info.external_attr >> 16) & 0o777 or 0o644)
        for name, (info, kind) in members.items():
            if kind == stat.S_IFLNK:
                (destination / name).symlink_to(archive.read(info).decode("utf-8"))
    return destination / "HyperMug.app"


def verify_appcast(data, repository, channel, version, archive_name, archive_size):
    try:
        root = ET.fromstring(data)
    except ET.ParseError as error:
        raise ValueError("invalid appcast XML") from error
    items = root.findall("./channel/item")
    if len(items) != 1 or items[0].findtext("title") != f"HyperMug {version}":
        raise ValueError("appcast release title mismatch")
    item = items[0]
    short, build = bundle_identity(channel, version)
    if (item.findtext(SPARKLE + "version") != build
            or item.findtext(SPARKLE + "shortVersionString") != short):
        raise ValueError("appcast bundle version mismatch")
    enclosures = item.findall("enclosure")
    if len(enclosures) != 1:
        raise ValueError("appcast enclosure mismatch")
    attrs = enclosures[0].attrib
    if (attrs.get("url") != asset_url(repository, "v" + version, archive_name)
            or attrs.get("length") != str(archive_size)
            or attrs.get("type") != "application/zip"):
        raise ValueError("appcast archive identity mismatch")
    signature = attrs.get(SPARKLE + "edSignature", "")
    if not re.fullmatch(r"[A-Za-z0-9+/]{86}==", signature):
        raise ValueError("appcast Ed25519 signature missing")
    return signature


def verify(zip_path, feed_path, repository, channel, version, digest, work):
    archive_name = f"HyperMug-{version}.zip"
    hasher = hashlib.sha256()
    with zip_path.open("rb") as source:
        while chunk := source.read(1024 * 1024):
            hasher.update(chunk)
    actual = hasher.hexdigest()
    if actual != digest:
        raise ValueError("downloaded ZIP digest mismatch")
    signature = verify_appcast(feed_path.read_bytes(), repository, channel, version,
                               archive_name, zip_path.stat().st_size)
    app = extract_safe(zip_path, work / "extracted")
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    short, build = bundle_identity(channel, version)
    if (info.get("CFBundleIdentifier") != "com.maxmeis.hypermug"
            or info.get("CFBundleShortVersionString") != short
            or info.get("CFBundleVersion") != build
            or info.get("HyperMugReleaseChannel") != channel
            or info.get("LSMinimumSystemVersion") != "14.0"
            or info.get("SUPublicEDKey") != PUBLIC_KEYS[channel]
            or info.get("CFBundleExecutable") != "HyperMug"):
        raise ValueError("distributed app bundle identity mismatch")
    executable = app / "Contents/MacOS/HyperMug"
    arches = subprocess.check_output(["lipo", "-archs", str(executable)], text=True).split()
    if "arm64" not in arches:
        raise ValueError("distributed app lacks arm64")
    subprocess.run(["codesign", "--verify", "--deep", "--strict", "--verbose=2", str(app)], check=True)
    signature_details = subprocess.run(["codesign", "-dv", "--verbose=4", str(app)],
                                       text=True, capture_output=True, check=True)
    details = signature_details.stdout + signature_details.stderr
    if ("Authority=Developer ID Application: Max Meissgeier (S5R3X22G84)" not in details
            or "TeamIdentifier=S5R3X22G84" not in details
            or not re.search(r"^CodeDirectory .*\bruntime\b", details, re.M)
            or not re.search(r"^Timestamp=.+", details, re.M)):
        raise ValueError("distributed app Developer ID signature mismatch")
    subprocess.run(["xcrun", "stapler", "validate", str(app)], check=True)
    subprocess.run(["spctl", "--assess", "--type", "execute", "--verbose=4", str(app)], check=True)
    env = dict(os.environ, SPARKLE_PUBLIC_ED_KEY=PUBLIC_KEYS[channel])
    subprocess.run(["swift", "helpers/verify-update.swift", str(zip_path), signature],
                   env=env, check=True)
