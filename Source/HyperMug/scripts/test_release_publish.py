"""Integration coverage for publish_release.sh using local git and a fake gh."""
import hashlib
import json
import os
import shutil
import subprocess
import tempfile
import unittest
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SHA_A = "a" * 40
SHA_B = "b" * 40


FAKE_GH = r'''#!/usr/bin/env python3
import json, os, shutil, sys
from pathlib import Path

root = Path(os.environ["FAKE_GH_STATE"])
state_file = root / "state.json"
state = json.loads(state_file.read_text())
args = sys.argv[1:]
def save(): state_file.write_text(json.dumps(state))
def repo_arg(args): return args[args.index("--repo") + 1]
def tag_key(repo, tag): return repo + "|" + tag
def fail_once(name):
    marker = root / ("failed-" + name)
    if os.environ.get("FAKE_FAIL_ONCE") == name and not marker.exists():
        marker.touch()
        print("injected " + name + " failure", file=sys.stderr)
        sys.exit(1)

if args[0] == "api":
    post = "-X" in args and args[args.index("-X") + 1] == "POST"
    if "meta" in args:
        if os.environ.get("GH_TOKEN") != os.environ.get("RELEASE_TOKEN"):
            sys.exit("meta used wrong token")
        print("ssh-ed25519 TEST_PUBLIC_HOST_KEY")
        sys.exit(0)
    endpoint = next(x for x in args if x.startswith("repos/"))
    bits = endpoint.split("/")
    repo = bits[1] + "/" + bits[2]
    if endpoint == "repos/" + repo:
        archived = state.get("archived", {}).get(repo, False)
        print("true" if archived else "false")
    elif "/git/ref/tags/" in endpoint:
        tag = endpoint.rsplit("/", 1)[1]
        entry = state["tags"].get(tag_key(repo, tag))
        if not entry: sys.exit(1)
        if ".object.sha" in args: print(entry["object"])
        else: print(json.dumps({"object": {"sha": entry["object"]}}))
    elif "/check-runs" in endpoint:
        sha = endpoint.split("/commits/", 1)[1].split("/check-runs", 1)[0]
        print(json.dumps({"check_runs": state.get("checks", {}).get(repo + "|" + sha, [])}))
    elif "/commits/" in endpoint:
        ref = endpoint.split("/commits/", 1)[1]
        if ref == "HEAD": print(state["heads"].get(repo, "c" * 40))
        else:
            entry = state["tags"].get(tag_key(repo, ref))
            if not entry: sys.exit(1)
            print(entry["target"])
    elif "/git/tags/" in endpoint:
        obj = endpoint.rsplit("/", 1)[1]
        match = next((v for v in state["tags"].values() if v["object"] == obj), None)
        if not match: sys.exit(1)
        print(json.dumps({"message": match["message"]}))
    elif endpoint.endswith("/git/tags") and post:
        tag = args[args.index("-f") + 1].split("=", 1)[1]
        message = next(x.split("=", 1)[1] for x in args if x.startswith("message="))
        target = next(x.split("=", 1)[1] for x in args if x.startswith("object="))
        obj = "tag-object-" + str(len(state["tags"]) + 1)
        state["pending_tags"][repo + "|" + tag] = {"object": obj, "target": target, "message": message}
        save()
        if ".sha" in args: print(obj)
        else: print(json.dumps({"sha": obj}))
    elif endpoint.endswith("/git/refs") and post:
        ref = next(x.split("=", 1)[1] for x in args if x.startswith("ref="))
        obj = next(x.split("=", 1)[1] for x in args if x.startswith("sha="))
        tag = ref.rsplit("/", 1)[1]
        entry = state["pending_tags"].pop(repo + "|" + tag)
        if entry["object"] != obj: sys.exit(3)
        state["tags"][repo + "|" + tag] = entry
        state["events"].append(["ref", repo, tag, entry["target"]]); save()
        print("{}")
    elif "/releases?" in endpoint:
        names = [k.split("|", 1)[1] for k in state["releases"] if k.startswith(repo + "|")]
        print("\n".join(names))
    else: sys.exit(2)
elif args[0] == "release" and args[1] == "view":
    tag = args[2]; repo = repo_arg(args)
    release = state["releases"].get(tag_key(repo, tag))
    if not release: sys.exit(1)
    if ".body" in args: print(release["body"])
    elif ".isDraft" in args: print("true" if release["draft"] else "false")
    elif ".isLatest" in args: print("true" if release.get("latest") else "false")
    elif ".assets[].name" in args: print("\n".join(release["assets"]))
    else: print(json.dumps(release))
elif args[0] == "release" and args[1] == "create":
    tag = args[2]; repo = repo_arg(args)
    fail_once("release-create")
    assets = {}
    for value in args[3:]:
        if value.startswith("-"): break
        path = Path(value); assets[path.name] = path.read_bytes().hex()
    body = args[args.index("--notes") + 1]
    release = {"body": body, "draft": "--draft" in args, "assets": assets,
               "prerelease": "--prerelease" in args}
    state["releases"][tag_key(repo, tag)] = release
    state["events"].append(["release-create", repo, tag]); save()
elif args[0] == "release" and args[1] == "edit":
    tag = args[2]; repo = repo_arg(args)
    fail_once("release-publish")
    release = state["releases"][tag_key(repo, tag)]
    if "--draft=false" in args or "--draft" in args:
        release["draft"] = "--draft=false" not in args
    if "--latest" in args or "--latest=false" in args:
        release["latest"] = "--latest" in args and "--latest=false" not in args
    if "--prerelease" in args: release["prerelease"] = True
    if "--notes" in args: release["body"] = args[args.index("--notes") + 1]
    state["events"].append(["release-publish", repo, tag]); save()
elif args[0] == "release" and args[1] == "upload":
    tag = args[2]; repo = repo_arg(args)
    release = state["releases"][tag_key(repo, tag)]
    if not release["draft"]: sys.exit("cannot upload to published release")
    for value in args[3:]:
        if value.startswith("-"): break
        path = Path(value)
        if path.name in release["assets"]: sys.exit("asset already exists")
        release["assets"][path.name] = path.read_bytes().hex()
        state["events"].append(["release-upload", repo, tag, path.name]); save()
        fail_once("release-upload")
elif args[0] == "release" and args[1] == "delete":
    tag = args[2]; repo = repo_arg(args)
    key = tag_key(repo, tag)
    if not state["releases"][key]["draft"]: sys.exit(4)
    del state["releases"][key]
    state["events"].append(["release-delete-draft", repo, tag]); save()
elif args[0] == "release" and args[1] == "download":
    tag = args[2]; repo = repo_arg(args)
    release = state["releases"].get(tag_key(repo, tag))
    name = args[args.index("--pattern") + 1]
    out = Path(args[args.index("--dir") + 1]) / name
    if not release or name not in release["assets"]: sys.exit(1)
    out.write_bytes(bytes.fromhex(release["assets"][name]))
elif args[:2] == ["pr", "list"]:
    repo = repo_arg(args); head = args[args.index("--head") + 1]
    entry = state.setdefault("prs", {}).get(repo + "|" + head)
    print(json.dumps([entry] if entry else []))
elif args[:2] in (["pr", "create"], ["pr", "edit"]):
    fail_once("pr-write")
    repo = repo_arg(args)
    head = args[args.index("--head") + 1] if args[1] == "create" else "release-casks/" + os.environ["CHANNEL"]
    key = repo + "|" + head
    entry = state.setdefault("prs", {}).get(key)
    if args[1] == "create" and entry: sys.exit("duplicate PR")
    number = entry["number"] if entry else len(state["prs"]) + 1
    state["prs"][key] = {"number": number, "title": args[args.index("--title") + 1],
                         "body": Path(args[args.index("--body-file") + 1]).read_text()}
    state["events"].append(["pr-" + args[1], repo, head, number]); save()
elif args[:3] == ["workflow", "run", "ci.yml"]:
    fail_once("ci-dispatch")
    repo = repo_arg(args); branch = args[args.index("--ref") + 1]
    sha = state["branch_heads"][repo + "|" + branch]
    state.setdefault("checks", {}).setdefault(repo + "|" + sha, []).append(
        {"name": "ci", "app": {"slug": "github-actions"}})
    state["events"].append(["ci-dispatch", repo, branch, sha]); save()
else:
    print("unsupported fake gh: " + repr(args), file=sys.stderr); sys.exit(2)
'''


FAKE_GIT = r'''#!/usr/bin/env python3
import json, os, subprocess, sys
from pathlib import Path

args = sys.argv[1:]
real = os.environ["REAL_GIT"]
if args and args[0] == "clone":
    rest = args[1:]
    url = next((x for x in rest if "github.com/" in x or x.startswith("git@github.com:")), None)
    if url and url.startswith("git@github.com:"):
        command = os.environ.get("GIT_SSH_COMMAND", "")
        import shlex, stat
        parts = shlex.split(command)
        key = Path(parts[parts.index("-i") + 1])
        hosts = Path(next(x.split("=", 1)[1] for x in parts if x.startswith("UserKnownHostsFile=")))
        if not key.exists() or stat.S_IMODE(key.stat().st_mode) != 0o600:
            sys.exit("SSH key missing or wrong permissions")
        if key.read_text() != os.environ["TAP_SSH_PRIVATE_KEY"] + "\n":
            sys.exit("SSH key contents incorrect")
        if "StrictHostKeyChecking=yes" not in command or "IdentitiesOnly=yes" not in command or "-F /dev/null" not in command:
            sys.exit("SSH restrictions absent")
        if hosts.read_text() != "github.com ssh-ed25519 TEST_PUBLIC_HOST_KEY\n":
            sys.exit("GitHub host keys absent")
        (Path(os.environ["FAKE_GH_STATE"]) / "ssh-work-path").write_text(str(key.parent))
    if url:
        if "homebrew-formulae" in url:
            (Path(os.environ["FAKE_GH_STATE"]) / "tap-url").write_text(url)
        repo = url.split("github.com" + (":" if url.startswith("git@") else "/"), 1)[1].removesuffix(".git")
        remotes = os.environ["LOCAL_GIT_REPOS"].split(os.pathsep)
        target = next((x.split("=", 1)[1] for x in remotes if x.startswith(repo + "=")), None)
        if target is None: sys.exit("unmapped fake git repository " + repo)
        args = ["clone"] + [target if x == url else x for x in rest]
if args and args[0] == "push":
    remote = next((value for value in args[1:] if not value.startswith("-")), "")
    try:
        url = subprocess.check_output([real, "remote", "get-url", remote], text=True).strip()
    except Exception: url = ""
    root = Path(os.environ["FAKE_GH_STATE"])
    mappings = os.environ["LOCAL_GIT_REPOS"].split(os.pathsep)
    repo = next((x.split("=", 1)[0] for x in mappings if x.split("=", 1)[1] == url), url.rsplit("github.com/", 1)[-1].removesuffix(".git"))
    marker = root / "failed-push-" / repo
    if os.environ.get("FAKE_FAIL_PUSH_REPO") == repo and not marker.exists():
        marker.parent.mkdir(exist_ok=True); marker.touch()
        print("injected git push failure for " + repo, file=sys.stderr); sys.exit(1)
    result = subprocess.run([real] + args)
    if result.returncode == 0:
        if repo == "maxmeis/homebrew-formulae" and os.environ.get("TAP_SSH_PRIVATE_KEY") and not os.environ.get("GIT_SSH_COMMAND"):
            sys.exit("SSH command absent from tap push")
        state_file = root / "state.json"
        state = json.loads(state_file.read_text()); state["events"].append(["git-push", repo])
        refspec = next((x for x in args[2:] if x.startswith("HEAD:refs/heads/")), None)
        if refspec:
            branch = refspec.split("HEAD:refs/heads/", 1)[1]
            sha = subprocess.check_output([real, "rev-parse", "HEAD"], text=True).strip()
            state.setdefault("branch_heads", {})[repo + "|" + branch] = sha
        state_file.write_text(json.dumps(state))
    sys.exit(result.returncode)
os.execv(real, [real] + args)
'''


class PublishReleaseIntegrationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="release-publish-test-")
        self.root = Path(self.temp.name)
        self.project = self.root / "project"
        (self.project / "scripts").mkdir(parents=True)
        (self.project / "build/release").mkdir(parents=True)
        shutil.copy2(ROOT / "scripts/publish_release.sh", self.project / "scripts/publish_release.sh")
        shutil.copy2(ROOT / "scripts/release_metadata.py", self.project / "scripts/release_metadata.py")
        shutil.copy2(ROOT / "scripts/publish_source_cask.py", self.project / "scripts/publish_source_cask.py")
        self.state_dir = self.root / "gh-state"
        self.state_dir.mkdir()
        self.state_file = self.state_dir / "state.json"
        self.state_file.write_text(json.dumps({"tags": {}, "pending_tags": {}, "releases": {}, "heads": {}, "events": []}))
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.gh = self.bin / "gh"
        self.gh.write_text(FAKE_GH); self.gh.chmod(0o755)
        self.real_git = shutil.which("git")
        self.git = self.bin / "git"
        self.git.write_text(FAKE_GIT); self.git.chmod(0o755)
        self.releases_repo = "maxmeis/HyperMug"
        self.tap_repo = "maxmeis/homebrew-formulae"
        self.releases_bare = self._bare(self.releases_repo)
        self.tap_bare = self._bare(self.tap_repo)
        for bare in (self.releases_bare, self.tap_bare):
            subprocess.run([self.real_git, "--git-dir", str(bare), "symbolic-ref", "HEAD", "refs/heads/main"], check=True)
        self.repositories = [self.releases_bare, self.tap_bare]
        self.seed_index = 0
        self.read_index = 0
        # The production releases repository has content and an updates branch;
        # an empty local bare repo would make the publisher's orphan-branch path
        # exercise git rm against an empty index instead of the release flow.
        self._commit_initial(self.releases_bare, {"README.md": "fixture\n"})
        self.env = os.environ.copy()
        self.env.update({
            "PATH": str(self.bin) + os.pathsep + os.environ["PATH"],
            "REAL_GIT": self.real_git,
            "LOCAL_GIT_REPOS": os.pathsep.join(f"{name}={path}" for name, path in zip((self.releases_repo, self.tap_repo), self.repositories)),
            "FAKE_GH_STATE": str(self.state_dir),
            "CHANNEL": "stable", "VERSION": "1.2.3", "BUILD_NUMBER": "1.2.3",
            "BUILD_APP": "true",
            "PUBLISH_EXTERNAL_TAP": "true",
            "SOURCE_REPOSITORY": self.releases_repo, "RELEASES_REPOSITORY": self.releases_repo,
            "TAP_REPOSITORY": self.tap_repo, "RELEASE_TOKEN": "release-token", "TAP_TOKEN": "tap-token",
            "GITHUB_ACTOR": "maxmeis", "GITHUB_TRIGGERING_ACTOR": "maxmeis",
            "GITHUB_REF": "refs/tags/v1.2.3", "GITHUB_SHA": SHA_A,
        })
        self._seed_tag(self.releases_repo, "v1.2.3", SHA_A)

    def tearDown(self):
        self.temp.cleanup()

    def _bare(self, repo):
        path = self.root / (repo.replace("/", "-") + ".git")
        subprocess.run([self.real_git, "init", "--bare", str(path)], check=True, stdout=subprocess.DEVNULL)
        return path

    def _state(self):
        return json.loads(self.state_file.read_text())

    def _save_state(self, state):
        self.state_file.write_text(json.dumps(state))

    def _build(self, channel=None, version=None, build_number=None, content=b"build one"):
        channel = channel or self.env["CHANNEL"]
        version = version or self.env["VERSION"]
        build_number = build_number or self.env["BUILD_NUMBER"]
        token = "hypermug@canary" if channel == "canary" else "hypermug"
        out = self.project / "build/release"
        archive = out / f"HyperMug-{version}.zip"
        with zipfile.ZipFile(archive, "w") as zf:
            zf.writestr("HyperMug.app/build.txt", content)
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        (out / f"appcast-{channel}.xml").write_text(
            '<?xml version="1.0"?><rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>'
            f"<title>HyperMug {version}</title><sparkle:version>{build_number}</sparkle:version>"
            f"<sparkle:shortVersionString>{version}</sparkle:shortVersionString>"
            f'<enclosure url="https://example.invalid/{archive.name}" sparkle:edSignature="sig" length="{archive.stat().st_size}" />'
            "</item></channel></rss>"
        )
        cask_version = version
        (out / f"{token}.rb").write_text(f'cask "{token}" do\n  version "{cask_version}"\n  sha256 "{digest}"\nend\n')
        (out / "sha256.txt").write_text(digest + "\n")

    def _run(self, **overrides):
        env = self.env.copy(); env.update({k: str(v) for k, v in overrides.items()})
        return subprocess.run(["bash", str(self.project / "scripts/publish_release.sh")], env=env,
                              text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    def _seed_tag(self, repo, tag, target, message="seed"):
        state = self._state()
        state["tags"][repo + "|" + tag] = {"object": "seed-object-" + tag, "target": target, "message": message}
        self._save_state(state)

    def _commit_initial(self, bare, files):
        self.seed_index += 1
        work = self.root / (bare.name + f"-seed-{self.seed_index}")
        existing_branch = bare == self.releases_bare and subprocess.run([self.real_git, "--git-dir", str(bare), "show-ref", "--verify", "--quiet", "refs/heads/updates"]).returncode == 0
        if existing_branch:
            subprocess.run([self.real_git, "clone", "--branch", "updates", str(bare), str(work)], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        else:
            work.mkdir()
            subprocess.run([self.real_git, "init", str(work)], check=True, stdout=subprocess.DEVNULL)
        subprocess.run([self.real_git, "-C", str(work), "config", "user.name", "Fixture"], check=True)
        subprocess.run([self.real_git, "-C", str(work), "config", "user.email", "fixture@example.test"], check=True)
        for name, content in files.items():
            dest = work / name; dest.parent.mkdir(parents=True, exist_ok=True); dest.write_text(content)
        subprocess.run([self.real_git, "-C", str(work), "add", "."], check=True)
        subprocess.run([self.real_git, "-C", str(work), "commit", "-m", "fixture"], check=True, stdout=subprocess.DEVNULL)
        subprocess.run([self.real_git, "-C", str(work), "branch", "-M", "updates"], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if not existing_branch:
            subprocess.run([self.real_git, "-C", str(work), "remote", "add", "origin", str(bare)], check=True)
        subprocess.run([self.real_git, "-C", str(work), "push", "--force", "origin", "HEAD:main", "HEAD:updates"], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def _remote_file(self, bare, path, branch=None):
        self.read_index += 1
        work = self.root / (bare.name + f"-read-{self.read_index}")
        branch = branch or ("updates" if bare == self.releases_bare else "main")
        result = subprocess.run([self.real_git, "clone", "--branch", branch, str(bare), str(work)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if result.returncode:
            return None
        return (work / path).read_text() if (work / path).exists() else None

    def _advance_main(self):
        work = self.root / "advance-main"
        subprocess.run([self.real_git, "clone", "--branch", "main", str(self.releases_bare), str(work)], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        (work / "README.md").write_text("main advanced after release PR\n")
        subprocess.run([self.real_git, "-C", str(work), "add", "README.md"], check=True)
        subprocess.run([self.real_git, "-C", str(work), "-c", "user.name=Fixture", "-c", "user.email=fixture@example.test", "commit", "-m", "advance main"], check=True, stdout=subprocess.DEVNULL)
        subprocess.run([self.real_git, "-C", str(work), "push", "origin", "HEAD:main"], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return subprocess.check_output([self.real_git, "-C", str(work), "rev-parse", "HEAD"], text=True).strip()

    def _release(self, tag="v1.2.3"):
        return self._state()["releases"].get(self.releases_repo + "|" + tag)

    def test_source_only_release_has_no_installable_assets_or_pointer_changes(self):
        first = self._run(BUILD_APP="false", TAP_TOKEN="")
        self.assertEqual(first.returncode, 0, first.stderr)
        release = self._release()
        self.assertFalse(release["draft"])
        self.assertFalse(release["latest"])
        self.assertEqual(release["assets"], {})
        self.assertIn("source-only", release["body"])
        self.assertIn(SHA_A, release["body"])
        self.assertIsNone(self._remote_file(self.releases_bare, "appcast-stable.xml"))
        self.assertIsNone(self._remote_file(self.tap_bare, "Casks/hypermug.rb"))
        self.assertFalse(any(e[0] == "git-push" for e in self._state()["events"]))
        events = list(self._state()["events"])
        repeat = self._run(BUILD_APP="false", TAP_TOKEN="")
        self.assertEqual(repeat.returncode, 0, repeat.stderr)
        self.assertEqual(self._state()["events"], events)

    def test_source_only_draft_retry_and_binary_same_tag_refusal(self):
        failed = self._run(BUILD_APP="false", TAP_TOKEN="", FAKE_FAIL_ONCE="release-publish")
        self.assertNotEqual(failed.returncode, 0)
        self.assertTrue(self._release()["draft"])
        retry = self._run(BUILD_APP="false", TAP_TOKEN="")
        self.assertEqual(retry.returncode, 0, retry.stderr)
        self.assertFalse(self._release()["draft"])
        self._build()
        events = list(self._state()["events"])
        binary = self._run()
        self.assertNotEqual(binary.returncode, 0)
        self.assertIn("use a new version", binary.stderr)
        self.assertEqual(self._state()["events"], events)
        self.assertEqual(self._release()["assets"], {})

    def test_source_only_version_counts_for_ordering_but_not_feed(self):
        first = self._run(BUILD_APP="false", TAP_TOKEN="")
        self.assertEqual(first.returncode, 0, first.stderr)
        self._seed_tag(self.releases_repo, "v1.2.2", SHA_B)
        self._build(version="1.2.2")
        older = self._run(VERSION="1.2.2", BUILD_NUMBER="1.2.2", GITHUB_REF="refs/tags/v1.2.2", GITHUB_SHA=SHA_B)
        self.assertNotEqual(older.returncode, 0)
        self.assertIsNone(self._release("v1.2.2"))
        self._seed_tag(self.releases_repo, "v1.2.4", SHA_B)
        self._build(version="1.2.4", build_number="1.2.4")
        newer = self._run(VERSION="1.2.4", BUILD_NUMBER="1.2.4", GITHUB_REF="refs/tags/v1.2.4", GITHUB_SHA=SHA_B)
        self.assertEqual(newer.returncode, 0, newer.stderr)
        self.assertIn("1.2.4", self._remote_file(self.releases_bare, "appcast-stable.xml"))
        self.assertEqual(self._release()["assets"], {})

    def test_ssh_tap_uses_ephemeral_key_and_original_release_token(self):
        self._build()
        result = self._run(TAP_SSH_PRIVATE_KEY="test-private-key", TAP_TOKEN="")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.state_dir / "tap-url").read_text(), "git@github.com:maxmeis/homebrew-formulae.git")
        self.assertIn('cask "hypermug"', self._remote_file(self.tap_bare, "Casks/hypermug.rb"))
        work = Path((self.state_dir / "ssh-work-path").read_text())
        self.assertFalse(work.exists(), "publisher must remove ephemeral credentials")

    def test_missing_tap_credentials_fails_before_api_writes(self):
        self._build()
        result = self._run(TAP_TOKEN="", TAP_SSH_PRIVATE_KEY="")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("TAP_SSH_PRIVATE_KEY or TAP_TOKEN is required", result.stderr)
        self.assertEqual(self._state()["events"], [])
        self.assertIsNone(self._release())

    def test_default_in_repo_publication_needs_no_external_tap_or_credentials(self):
        self._build()
        result = self._run(PUBLISH_EXTERNAL_TAP="", TAP_TOKEN="", TAP_SSH_PRIVATE_KEY="")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self._release()["draft"])
        self.assertIn("1.2.3", self._remote_file(self.releases_bare, "appcast-stable.xml"))
        self.assertIsNone(self._remote_file(self.tap_bare, "Casks/hypermug.rb"))
        self.assertEqual(len(self._state()["prs"]), 1)

    def test_explicit_archived_external_tap_fails_before_release_writes(self):
        self._build()
        state = self._state()
        state["archived"] = {self.tap_repo: True}
        self._save_state(state)
        result = self._run()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("External tap is archived", result.stderr)
        self.assertEqual(self._state()["events"], [])
        self.assertIsNone(self._release())

    def test_canary_publishes_separate_feed_and_cask_without_external_tap(self):
        version = "0.0.0-canary.12"
        self._seed_tag(self.releases_repo, "v" + version, SHA_A)
        self._build(channel="canary", version=version, build_number="1200")
        result = self._run(CHANNEL="canary", VERSION=version, BUILD_NUMBER="1200",
                           GITHUB_REF="refs/heads/main", PUBLISH_EXTERNAL_TAP="",
                           TAP_TOKEN="", TAP_SSH_PRIVATE_KEY="")
        self.assertEqual(result.returncode, 0, result.stderr)
        release = self._release("v" + version)
        self.assertFalse(release["draft"])
        self.assertTrue(release["prerelease"])
        self.assertFalse(release["latest"])
        self.assertIn("HyperMug-" + version + ".zip", release["assets"])
        self.assertIn(version, self._remote_file(self.releases_bare, "appcast-canary.xml"))
        self.assertIsNone(self._remote_file(self.releases_bare, "appcast-stable.xml"))
        self.assertIsNone(self._remote_file(self.tap_bare, "Casks/hypermug@canary.rb"))
        self.assertIn(version, self._remote_file(self.releases_bare, "Casks/hypermug@canary.rb", "release-casks/canary"))
        self.assertEqual(len(self._state()["prs"]), 1)

        old = "0.0.0-canary.11"
        self._seed_tag(self.releases_repo, "v" + old, SHA_B)
        self._build(channel="canary", version=old, build_number="1100")
        events = list(self._state()["events"])
        outdated = self._run(CHANNEL="canary", VERSION=old, BUILD_NUMBER="1100",
                             GITHUB_REF="refs/heads/main", GITHUB_SHA=SHA_B,
                             PUBLISH_EXTERNAL_TAP="", TAP_TOKEN="")
        self.assertNotEqual(outdated.returncode, 0)
        self.assertIn("newer canary release already exists", outdated.stderr)
        self.assertEqual(self._state()["events"], events)
        self.assertIsNone(self._release("v" + old))

    def test_first_stable_success_publishes_assets_and_pointers_once(self):
        self._build()
        result = self._run()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.state_dir / "tap-url").read_text(), "https://x-access-token:tap-token@github.com/maxmeis/homebrew-formulae.git")
        state = self._state()
        self.assertEqual(state["tags"][self.releases_repo + "|v1.2.3"]["target"], SHA_A)
        self.assertEqual([e for e in state["events"] if e[0] == "ref"], [])
        release = self._release()
        self.assertFalse(release["draft"])
        self.assertTrue(release["latest"])
        self.assertEqual(set(release["assets"]), {"HyperMug-1.2.3.zip", "appcast-stable.xml", "hypermug.rb", "sha256.txt"})
        self.assertIn("source " + SHA_A, release["body"])
        self.assertIn("1.2.3", self._remote_file(self.releases_bare, "appcast-stable.xml"))
        self.assertIn('cask "hypermug"', self._remote_file(self.tap_bare, "Casks/hypermug.rb"))
        self.assertEqual(self._remote_file(self.releases_bare, "Casks/hypermug.rb", "release-casks/stable"),
                         bytes.fromhex(release["assets"]["hypermug.rb"]).decode())
        self.assertIsNone(self._remote_file(self.releases_bare, "Casks/hypermug.rb", "main"))
        self.assertEqual(len(self._state()["prs"]), 1)
        self.assertEqual(len([e for e in self._state()["events"] if e[0] == "ci-dispatch"]), 1)

    def test_first_release_creates_updates_branch(self):
        subprocess.run([self.real_git, "--git-dir", str(self.releases_bare),
                        "update-ref", "-d", "refs/heads/updates"], check=True)
        self._build()
        result = self._run()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("1.2.3", self._remote_file(self.releases_bare, "appcast-stable.xml"))
        self.assertIn('cask "hypermug"', self._remote_file(self.tap_bare, "Casks/hypermug.rb"))

    def test_retry_after_release_feed_success_and_tap_failure(self):
        self._build()
        first = self._run(FAKE_FAIL_PUSH_REPO=self.tap_repo)
        self.assertNotEqual(first.returncode, 0)
        self.assertFalse(self._release()["draft"])
        self.assertIn("1.2.3", self._remote_file(self.releases_bare, "appcast-stable.xml"))
        self.assertIsNone(self._remote_file(self.tap_bare, "Casks/hypermug.rb"))
        # A new build is deliberately different; a published release must win on retry.
        self._build(content=b"different rebuilt archive")
        retry = self._run()
        self.assertEqual(retry.returncode, 0, retry.stderr)
        release = self._release()
        self.assertFalse(release["draft"])
        published_zip = bytes.fromhex(release["assets"]["HyperMug-1.2.3.zip"])
        self.assertIn(b"build one", published_zip)
        self.assertNotIn(b"different rebuilt archive", published_zip)
        self.assertIn('cask "hypermug"', self._remote_file(self.tap_bare, "Casks/hypermug.rb"))

    def test_retry_after_source_pr_failure_keeps_external_tap_and_published_asset(self):
        self._build()
        failed = self._run(FAKE_FAIL_ONCE="pr-write")
        self.assertNotEqual(failed.returncode, 0)
        self.assertIn('cask "hypermug"', self._remote_file(self.tap_bare, "Casks/hypermug.rb"))
        self.assertEqual(self._state().get("prs", {}), {})
        self._build(content=b"different retry build")
        retry = self._run()
        self.assertEqual(retry.returncode, 0, retry.stderr)
        self.assertEqual(len(self._state()["prs"]), 1)
        published = bytes.fromhex(self._release()["assets"]["hypermug.rb"]).decode()
        self.assertEqual(self._remote_file(self.releases_bare, "Casks/hypermug.rb", "release-casks/stable"), published)
        again = self._run()
        self.assertEqual(again.returncode, 0, again.stderr)
        self.assertEqual(len([e for e in self._state()["events"] if e[0] == "pr-create"]), 1)

    def test_managed_cask_branch_rebases_on_advanced_main_and_dispatches_fresh_ci(self):
        self._build()
        first = self._run()
        self.assertEqual(first.returncode, 0, first.stderr)
        old_head = self._state()["branch_heads"][self.releases_repo + "|release-casks/stable"]
        main_head = self._advance_main()
        self.assertIn("main advanced", self._remote_file(self.releases_bare, "README.md", "main"))
        self.assertNotEqual(subprocess.run([self.real_git, "--git-dir", str(self.releases_bare), "merge-base", "--is-ancestor", main_head, old_head]).returncode, 0)
        again = self._run()
        self.assertEqual(again.returncode, 0, again.stderr)
        state = self._state()
        new_head = state["branch_heads"][self.releases_repo + "|release-casks/stable"]
        self.assertNotEqual(new_head, old_head)
        self.assertEqual(len([e for e in state["events"] if e[0] == "ci-dispatch"]), 2)
        ancestor = subprocess.run([self.real_git, "--git-dir", str(self.releases_bare), "merge-base", "--is-ancestor", main_head, new_head])
        self.assertEqual(ancestor.returncode, 0)
        self.assertIn("main advanced", self._remote_file(self.releases_bare, "README.md", "release-casks/stable"))

    def test_dispatch_failure_retries_without_duplicate_pr_or_ci(self):
        self._build()
        failed = self._run(FAKE_FAIL_ONCE="ci-dispatch")
        self.assertNotEqual(failed.returncode, 0)
        self.assertEqual(len(self._state()["prs"]), 1)
        self.assertEqual(len([e for e in self._state()["events"] if e[0] == "ci-dispatch"]), 0)
        retry = self._run()
        self.assertEqual(retry.returncode, 0, retry.stderr)
        again = self._run()
        self.assertEqual(again.returncode, 0, again.stderr)
        events = self._state()["events"]
        self.assertEqual(len([e for e in events if e[0] == "pr-create"]), 1)
        self.assertEqual(len([e for e in events if e[0] == "ci-dispatch"]), 1)
        self.assertEqual(events[-1][0], "ci-dispatch")

    def test_retry_after_release_success_and_feed_push_failure(self):
        self._build()
        failed = self._run(FAKE_FAIL_PUSH_REPO=self.releases_repo)
        self.assertNotEqual(failed.returncode, 0)
        self.assertFalse(self._release()["draft"])
        original_zip = self._release()["assets"]["HyperMug-1.2.3.zip"]
        self.assertIsNone(self._remote_file(self.releases_bare, "appcast-stable.xml"))
        self.assertIsNone(self._remote_file(self.tap_bare, "Casks/hypermug.rb"))
        self._build(content=b"new local contents")
        retry = self._run()
        self.assertEqual(retry.returncode, 0, retry.stderr)
        self.assertEqual(self._release()["assets"]["HyperMug-1.2.3.zip"], original_zip)
        self.assertIn("1.2.3", self._remote_file(self.releases_bare, "appcast-stable.xml"))
        self.assertIn('cask "hypermug"', self._remote_file(self.tap_bare, "Casks/hypermug.rb"))

    def test_publish_failure_leaves_draft_and_retry_publishes_before_pointers(self):
        self._build()
        failed = self._run(FAKE_FAIL_ONCE="release-publish")
        self.assertNotEqual(failed.returncode, 0)
        draft = self._release()
        self.assertTrue(draft["draft"])
        self.assertIsNone(self._remote_file(self.releases_bare, "appcast-stable.xml"))
        self.assertIsNone(self._remote_file(self.tap_bare, "Casks/hypermug.rb"))
        # Asset contents must be reused from the full draft even if local output changed.
        original_zip = draft["assets"]["HyperMug-1.2.3.zip"]
        self._build(content=b"new local contents")
        retry = self._run()
        self.assertEqual(retry.returncode, 0, retry.stderr)
        state = self._state()
        self.assertFalse(self._release()["draft"])
        self.assertEqual(self._release()["assets"]["HyperMug-1.2.3.zip"], original_zip)
        events = state["events"]
        published_at = next(i for i, event in enumerate(events) if event[0] == "release-publish")
        pointer_pushes = [i for i, event in enumerate(events) if event[0] == "git-push"]
        self.assertTrue(pointer_pushes)
        self.assertTrue(all(i > published_at for i in pointer_pushes))

    def test_stable_downgrade_and_wrong_source_tag_sha_fail_before_writes(self):
        self._build()
        self._seed_tag(self.releases_repo, "v2.0.0", SHA_B)
        state = self._state()
        state["releases"][self.releases_repo + "|v2.0.0"] = {
            "body": "HyperMug stable 2.0.0; source " + SHA_B,
            "draft": False, "prerelease": False, "assets": {},
        }
        self._save_state(state)
        down = self._run(VERSION="1.9.9", BUILD_NUMBER="1.9.9")
        self.assertNotEqual(down.returncode, 0)
        self.assertEqual(self._state()["events"], [])
        state = self._state()
        state["tags"].pop(self.releases_repo + "|v2.0.0")
        state["releases"].pop(self.releases_repo + "|v2.0.0")
        self._save_state(state)
        self._seed_tag(self.releases_repo, "v1.2.3", SHA_B)
        wrong_sha = self._run()
        self.assertNotEqual(wrong_sha.returncode, 0)
        self.assertIn("Existing source tag points elsewhere", wrong_sha.stderr)
        self.assertEqual(self._state()["events"], [])

    def test_stable_actor_and_triggering_actor_gate_runs_before_gh(self):
        self._build()
        for key, value in (("GITHUB_ACTOR", "someone"), ("GITHUB_TRIGGERING_ACTOR", "someone")):
            result = self._run(**{key: value})
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("production requires both actor", result.stderr)
            self.assertEqual(self._state()["events"], [])


if __name__ == "__main__":
    unittest.main()
