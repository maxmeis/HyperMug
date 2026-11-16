#!/usr/bin/env python3
"""Propose a published cask asset in the protected source repository."""
import argparse
import json
import os
import re
import subprocess
from pathlib import Path
from release_metadata import bundle_identity


def run(*args, cwd=None, capture=False):
    result = subprocess.run(args, cwd=cwd, check=True, text=True,
                            stdout=subprocess.PIPE if capture else None)
    return result.stdout.strip() if capture else None


def version_of(content, channel):
    if content is None:
        return None
    match = re.search(r'^\s*version "([^"]+)"\s*$', content, re.M)
    if not match:
        raise ValueError("existing source cask has no literal version")
    value = match.group(1)
    if channel == "stable" and re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", value):
        return tuple(map(int, value.split(".")))
    if channel == "canary" and re.fullmatch(r"0\.0\.[1-9][0-9]*", value):
        return (int(value.rsplit(".", 1)[1]),)
    raise ValueError("unexpected release cask version")


def publish(channel, version, repository, asset, work):
    token = "hypermug@canary" if channel == "canary" else "hypermug"
    path = f"Casks/{token}.rb"
    branch = f"release-casks/{channel}"
    desired = asset.read_text()
    expected_version, _ = bundle_identity(channel, version)
    expected = ((int(expected_version.rsplit(".", 1)[1]),) if channel == "canary"
                else tuple(map(int, expected_version.split("."))))
    if version_of(desired, channel) != expected:
        raise ValueError("published cask version does not match release")
    if not re.search(r'^\s*sha256 "[0-9a-f]{64}"\s*$', desired, re.M):
        raise ValueError("published cask lacks a SHA256 digest")
    auth = os.environ["RELEASE_TOKEN"]
    run("git", "clone", f"https://x-access-token:{auth}@github.com/{repository}.git", str(work))
    main_file = work / path
    main_content = main_file.read_text() if main_file.exists() else None
    requested = version_of(desired, channel)
    current = version_of(main_content, channel)
    if current is not None and current > requested:
        print(f"Source {path} is newer; skipping {version}")
        return
    if main_content == desired:
        print(f"Source {path} already contains {version}")
        return
    refs = run("git", "ls-remote", "--heads", "origin", branch, cwd=work, capture=True)
    if refs:
        run("git", "fetch", "origin", branch, cwd=work)
        found = subprocess.run(("git", "show", f"FETCH_HEAD:{path}"), cwd=work,
                               text=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        previous = found.stdout if found.returncode == 0 else None
        if previous is not None and version_of(previous, channel) > requested:
            print(f"Managed branch {branch} is newer; skipping {version}")
            return
        previous_sha = run("git", "rev-parse", "FETCH_HEAD", cwd=work, capture=True)
    else:
        previous_sha = None
    prs = json.loads(run("gh", "pr", "list", "--repo", repository, "--state", "open",
                         "--head", branch, "--base", "main", "--json", "number,title,body", cwd=work, capture=True))
    if len(prs) > 1:
        raise ValueError("multiple open PRs for managed cask branch")
    branch_current = previous_sha and subprocess.run(
        ("git", "merge-base", "--is-ancestor", "origin/main", previous_sha),
        cwd=work, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    ).returncode == 0
    if previous_sha and previous == desired and branch_current:
        head_sha = previous_sha
    else:
        run("git", "checkout", "-B", branch, "origin/main", cwd=work)
        main_file.parent.mkdir(parents=True, exist_ok=True)
        main_file.write_text(desired)
        run("git", "add", "--", path, cwd=work)
        run("git", "-c", "user.name=HyperMug release bot",
            "-c", "user.email=actions@users.noreply.github.com", "commit",
            "-m", f"chore: update {token} cask to {version}", cwd=work)
        head_sha = run("git", "rev-parse", "HEAD", cwd=work, capture=True)
        refspec = f"HEAD:refs/heads/{branch}"
        if previous_sha:
            run("git", "push", f"--force-with-lease=refs/heads/{branch}:{previous_sha}", "origin", refspec, cwd=work)
        else:
            run("git", "push", "origin", refspec, cwd=work)
    body = work / "cask-pr-body.md"
    body.write_text(f"Updates `{path}` to published {channel} release `{version}`.\n\n"
                    "The cask is copied from the release asset, including its published SHA256. "
                    "Review and merge to make this version available from the source repository tap.\n")
    title = f"chore: update {token} cask to {version}"
    if prs:
        if prs[0]["title"] != title or prs[0]["body"] != body.read_text():
            run("gh", "pr", "edit", str(prs[0]["number"]), "--repo", repository,
                "--title", title, "--body-file", str(body), cwd=work)
    else:
        run("gh", "pr", "create", "--repo", repository, "--base", "main", "--head", branch,
            "--title", title, "--body-file", str(body), cwd=work)
    checks = json.loads(run("gh", "api", f"repos/{repository}/commits/{head_sha}/check-runs",
                            cwd=work, capture=True))
    if not any(check.get("name") == "ci" and check.get("app", {}).get("slug") == "github-actions"
               for check in checks["check_runs"]):
        run("gh", "workflow", "run", "ci.yml", "--repo", repository, "--ref", branch, cwd=work)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    for key in ("channel", "version", "repository", "asset", "work"):
        parser.add_argument("--" + key, required=True)
    args = parser.parse_args()
    publish(args.channel, args.version, args.repository, Path(args.asset), Path(args.work))
