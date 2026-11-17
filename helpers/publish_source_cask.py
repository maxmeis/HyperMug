#!/usr/bin/env python3
"""Prepare a published cask; the authenticated owner push triggers its required CI."""
import argparse
import base64
import os
import re
import subprocess
from pathlib import Path
from release_metadata import bundle_identity


def run(*args, cwd=None, capture=False):
    env = os.environ.copy()
    if args[0] == "git" and env.get("PUBLISHER_TOKEN") and not any(
            env.get(f"GIT_CONFIG_KEY_{i}") == "http.https://github.com/.extraheader"
            for i in range(int(env.get("GIT_CONFIG_COUNT", "0")))):
        # Keep credentials out of remote URLs, process arguments, and error text.
        index = int(env.get("GIT_CONFIG_COUNT", "0"))
        env["GIT_CONFIG_COUNT"] = str(index + 1)
        env[f"GIT_CONFIG_KEY_{index}"] = "http.https://github.com/.extraheader"
        credential = base64.b64encode(("x-access-token:" + env["PUBLISHER_TOKEN"]).encode()).decode()
        env[f"GIT_CONFIG_VALUE_{index}"] = "AUTHORIZATION: basic " + credential
    result = subprocess.run(args, cwd=cwd, check=True, text=True,
                            env=env,
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
    run("git", "clone", f"https://github.com/{repository}.git", str(work))
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
    branch_current = previous_sha and subprocess.run(
        ("git", "merge-base", "--is-ancestor", "origin/main", previous_sha),
        cwd=work, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    ).returncode == 0
    if previous_sha and previous == desired and branch_current:
        print(f"Source {path} is staged; awaiting its push-triggered CI")
        return
    else:
        run("git", "checkout", "-B", branch, "origin/main", cwd=work)
        main_file.parent.mkdir(parents=True, exist_ok=True)
        main_file.write_text(desired)
        run("git", "add", "--", path, cwd=work)
        run("git", "-c", "user.name=maxmeisreleasebot[bot]",
            "-c", "user.email=357859028+maxmeisreleasebot[bot]@users.noreply.github.com", "commit",
            "-m", f"chore: update {token} cask to {version}", cwd=work)
        refspec = f"HEAD:refs/heads/{branch}"
        if previous_sha:
            run("git", "push", f"--force-with-lease=refs/heads/{branch}:{previous_sha}", "origin", refspec, cwd=work)
        else:
            run("git", "push", "origin", refspec, cwd=work)
    # PUBLISHER_TOKEN is the App publisher token. Its push already starts CI.
    # A second dispatch races check-run registration, cancels the push run,
    # and can leave GitHub's required ci context cancelled even after success.



if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    for key in ("channel", "version", "repository", "asset", "work"):
        parser.add_argument("--" + key, required=True)
    args = parser.parse_args()
    publish(args.channel, args.version, args.repository, Path(args.asset), Path(args.work))
