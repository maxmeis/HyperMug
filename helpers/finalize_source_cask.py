#!/usr/bin/env python3
"""Publish only verified, CI-passing release cask metadata without a release PR."""
import argparse
import hashlib
import os
import json
import re
import subprocess
import tempfile
from pathlib import Path

from publish_source_cask import publish, run, version_of
from release_metadata import REPO, SHA, asset_url, cask


def api(endpoint):
    return json.loads(run("gh", "api", endpoint, capture=True))


def is_ancestor(older, newer, work):
    return subprocess.run(("git", "merge-base", "--is-ancestor", older, newer),
                          cwd=work, stdout=subprocess.DEVNULL,
                          stderr=subprocess.DEVNULL).returncode == 0


def verified_asset(repository, releases_repository, channel, content, directory):
    parsed = version_of(content, channel)
    version = f"0.0.0-canary.{parsed[0]}" if channel == "canary" else ".".join(map(str, parsed))
    tag = "v" + version
    release = api(f"repos/{releases_repository}/releases/tags/{tag}")
    if (release.get("tag_name") != tag or release.get("draft") is not False
            or release.get("immutable") is not True
            or release.get("prerelease") is not (channel == "canary")
            or "source-only" in release.get("body", "")):
        raise ValueError("a published immutable binary release is required")
    source = api(f"repos/{repository}/commits/{tag}").get("sha", "")
    if not SHA.fullmatch(source) or not re.search(
            rf"\bsource {re.escape(source)}(?![0-9a-f])", release.get("body", "")):
        raise ValueError("release source does not match the source tag")
    token = "hypermug@canary" if channel == "canary" else "hypermug"
    assets = {asset["name"]: asset for asset in release.get("assets", [])}
    name = token + ".rb"
    archive = f"HyperMug-{version}.zip"
    if name not in assets or archive not in assets:
        raise ValueError("binary and cask release assets are required")
    digest = assets[archive].get("digest", "")
    if not re.fullmatch(r"sha256:[0-9a-f]{64}", digest):
        raise ValueError("published binary requires a GitHub SHA256 digest")
    directory.mkdir(parents=True)
    run("gh", "release", "download", tag, "--repo", releases_repository,
        "--pattern", name, "--dir", str(directory))
    asset = directory / name
    data = asset.read_bytes()
    if assets[name].get("digest") != "sha256:" + hashlib.sha256(data).hexdigest():
        raise ValueError("downloaded cask digest does not match its immutable asset")
    expected = cask(channel, version, asset_url(releases_repository, tag, archive), digest[7:])
    if data != expected.encode() or content != expected:
        raise ValueError("only the exact rendered immutable release cask may be published")
    return version, source, asset


def finalize(repository, releases_repository, run_id, work):
    if repository != "maxmeis/hypermug" or not REPO.fullmatch(releases_repository):
        raise ValueError("unexpected publication repository")
    if not re.fullmatch(r"[1-9][0-9]*", str(run_id)):
        raise ValueError("a CI workflow run ID is required")
    if (os.environ.get("PUBLISHER_REPOSITORY") != repository
            or os.environ.get("PUBLISHER_APP_SLUG") != "maxmeisreleasebot"
            or os.environ.get("PUBLISHER_BOT_USER_ID") != "357859028"
            or not re.fullmatch(r"[1-9][0-9]*", os.environ.get("PUBLISHER_INSTALLATION_ID", ""))):
        raise ValueError("verified release-bot action output is required")
    scope = api("installation/repositories?per_page=100&page=1")
    repositories = scope.get("repositories")
    if (scope.get("total_count") != 1 or not isinstance(repositories, list)
            or len(repositories) != 1 or not isinstance(repositories[0], dict)
            or repositories[0].get("full_name", "").lower() != repository.lower()):
        raise ValueError("publisher token must access exactly this repository")
    work.mkdir(parents=True, exist_ok=True)
    ci = api(f"repos/{repository}/actions/runs/{run_id}")
    branch = ci.get("head_branch", "")
    if (ci.get("event") != "push" or ci.get("status") != "completed"
            or ci.get("conclusion") != "success"
            or ci.get("path") != ".github/workflows/ci.yml"
            or (ci.get("actor") or {}).get("login") != "maxmeisreleasebot[bot]"
            or (ci.get("actor") or {}).get("id") != 357859028
            or (ci.get("head_repository") or {}).get("full_name", "").lower() != repository.lower()
            or branch not in ("release-casks/stable", "release-casks/canary")):
        raise ValueError("only successful same-repository release metadata CI is accepted")
    head = ci.get("head_sha", "")
    if not SHA.fullmatch(head):
        raise ValueError("CI head must be a full commit SHA")
    checks = api(f"repos/{repository}/commits/{head}/check-runs?per_page=100")
    run_url = f"https://github.com/{repository}/actions/runs/{run_id}/job/"
    if not any(check.get("name") == "ci" and check.get("app", {}).get("id") == 15368
               and check.get("head_sha") == head and check.get("status") == "completed"
               and check.get("conclusion") == "success"
               and check.get("details_url", "").startswith(run_url)
               for check in checks.get("check_runs", [])):
        raise ValueError("the required GitHub Actions ci check must pass in this run")
    channel = branch.rsplit("/", 1)[1]
    path = "Casks/" + ("hypermug@canary.rb" if channel == "canary" else "hypermug.rb")
    checkout = work / "repository"
    run("git", "clone", f"https://github.com/{repository}.git", str(checkout))
    run("git", "fetch", "origin", f"refs/heads/{branch}", cwd=checkout)
    if run("git", "rev-parse", "FETCH_HEAD", cwd=checkout, capture=True) != head:
        return "superseded"
    parents = run("git", "rev-list", "--parents", "-n", "1", head, cwd=checkout, capture=True).split()
    if len(parents) != 2:
        raise ValueError("metadata publication must be a single-parent commit")
    parent = parents[1]
    current_main = run("git", "rev-parse", "origin/main", cwd=checkout, capture=True)
    if not is_ancestor(parent, current_main, checkout):
        raise ValueError("metadata must be based on approved main history")
    changed = run("git", "diff", "--name-only", parent, head, cwd=checkout, capture=True).splitlines()
    if changed != [path]:
        raise ValueError("metadata commit must change only its channel cask")
    if run("git", "ls-tree", head, "--", path, cwd=checkout, capture=True).split()[0] != "100644":
        raise ValueError("the release cask must be a regular, non-executable file")
    content = subprocess.check_output(("git", "show", f"{head}:{path}"), cwd=checkout).decode("utf-8")
    version, source, asset = verified_asset(repository, releases_repository, channel, content, work / "assets")
    if not is_ancestor(source, current_main, checkout):
        raise ValueError("release source is not approved main history")
    current_file = checkout / path
    current_content = current_file.read_text() if current_file.exists() else None
    if current_content == content:
        return "already published"
    if current_content is not None and version_of(current_content, channel) > version_of(content, channel):
        return "superseded"
    if parent != current_main:
        # Main advanced during CI. Rebuild only the metadata branch and let its
        # new CI completion re-enter this trusted workflow; never force main.
        publish(channel, version, repository, asset, work / "rebased")
        return "rebased; awaiting fresh CI"
    try:
        run("git", "push", "origin", f"{head}:refs/heads/main", cwd=checkout)
    except subprocess.CalledProcessError:
        # A concurrent code merge can invalidate strict CI after our fetch.
        # Rebuild and redispatch only when main actually advanced; permission
        # or other errors must remain visible instead of becoming a false success.
        run("git", "fetch", "origin", "main", cwd=checkout)
        if run("git", "rev-parse", "origin/main", cwd=checkout, capture=True) == current_main:
            raise
        publish(channel, version, repository, asset, work / "rebased")
        return "rebased; awaiting fresh CI"
    return "published"


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--repository", required=True)
    parser.add_argument("--releases-repository", required=True)
    parser.add_argument("--run-id", required=True)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="hypermug-cask-finalize-") as directory:
        print(finalize(args.repository, args.releases_repository, args.run_id, Path(directory)))
