"""Exercise the trusted finalizer against actual local Git histories."""
import copy
import hashlib
import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import finalize_source_cask as subject
import publish_source_cask
from release_metadata import asset_url, cask


REPOSITORY = "maxmeis/hypermug"


class CaskFinalizerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="cask-finalizer-test-")
        self.root = Path(self.temp.name)
        self.bare = self.root / "remote.git"
        self.seed = self.root / "seed"
        self.git("init", "--bare", str(self.bare))
        self.git("--git-dir", str(self.bare), "symbolic-ref", "HEAD", "refs/heads/main")
        self.git("init", "-b", "main", str(self.seed))
        self.git("config", "user.name", "Fixture", cwd=self.seed)
        self.git("config", "user.email", "fixture@example.invalid", cwd=self.seed)
        (self.seed / "README.md").write_text("approved source\n")
        self.git("add", ".", cwd=self.seed)
        self.git("commit", "-m", "feat: approved app source", cwd=self.seed)
        self.source = self.git("rev-parse", "HEAD", cwd=self.seed)
        self.git("remote", "add", "origin", str(self.bare), cwd=self.seed)
        self.git("push", "origin", "main", cwd=self.seed)
        self.channel = "canary"
        self.version = "0.0.0-canary.2"
        self.path = "Casks/hypermug@canary.rb"
        self.branch = "release-casks/canary"
        self.content = cask(self.channel, self.version,
                            asset_url(REPOSITORY, "v" + self.version,
                                      "HyperMug-" + self.version + ".zip"), "a" * 64)
        self.git("checkout", "-b", self.branch, cwd=self.seed)
        dest = self.seed / self.path
        dest.parent.mkdir()
        dest.write_text(self.content)
        self.git("add", self.path, cwd=self.seed)
        self.git("commit", "-m", "chore: update published cask", cwd=self.seed)
        self.head = self.git("rev-parse", "HEAD", cwd=self.seed)
        self.git("push", "origin", self.branch, cwd=self.seed)
        self.ci = dict(event="push", actor={"login": "maxmeisreleasebot[bot]", "id": 357859028}, status="completed", conclusion="success",
                       path=".github/workflows/ci.yml", head_repository={"full_name": REPOSITORY},
                       head_branch=self.branch, head_sha=self.head)
        self.check = dict(name="ci", app={"id": 15368}, head_sha=self.head,
                          status="completed", conclusion="success",
                          details_url=f"https://github.com/{REPOSITORY}/actions/runs/42/job/9")
        self.release = dict(tag_name="v" + self.version, draft=False, immutable=True,
                            prerelease=True, body="HyperMug canary; source " + self.source,
                            assets=[dict(name="hypermug@canary.rb", digest="sha256:" + hashlib.sha256(self.content.encode()).hexdigest()),
                                    dict(name="HyperMug-" + self.version + ".zip", id=22, size=3, digest="sha256:" + "a" * 64),
                                    dict(name="appcast-canary.xml", id=23, size=3, digest="sha256:" + "b" * 64)])
        self.asset_data = self.content.encode()
        self.publisher = {"total_count": 1, "repositories": [{"full_name": REPOSITORY}]}
        self.immutable = {"enabled": True}
        self.actions = {"total_count": 1, "workflow_runs": [{}]}
        self.api_calls = []
        self.archive_verified = False
        self.reject_archive = False

    def tearDown(self):
        self.temp.cleanup()

    def git(self, *args, cwd=None):
        return subprocess.check_output(("git", *args), cwd=cwd, text=True,
                                       stderr=subprocess.DEVNULL).strip()

    def main_head(self):
        return self.git("--git-dir", str(self.bare), "rev-parse", "main")

    def update_candidate_head(self):
        self.head = self.git("rev-parse", "HEAD", cwd=self.seed)
        self.ci["head_sha"] = self.check["head_sha"] = self.head
        self.git("push", "--force", "origin", self.branch, cwd=self.seed)

    def fake_api(self, endpoint):
        self.api_calls.append(endpoint)
        if endpoint == "installation/repositories?per_page=100&page=1":
            return copy.deepcopy(self.publisher)
        if endpoint == f"repos/{REPOSITORY}/immutable-releases":
            return copy.deepcopy(self.immutable)
        if endpoint == f"repos/{REPOSITORY}/actions/runs?per_page=1":
            return copy.deepcopy(self.actions)
        if "/actions/runs/" in endpoint:
            return copy.deepcopy(self.ci)
        if "/check-runs" in endpoint:
            return {"check_runs": [copy.deepcopy(self.check)]}
        if "/releases/tags/" in endpoint:
            return copy.deepcopy(self.release)
        if "/commits/v" in endpoint:
            return {"sha": self.source}
        raise AssertionError("unexpected API request " + endpoint)

    def fake_download_asset(self, repository, asset, target):
        target.write_bytes(b"zip" if target.suffix == ".zip" else b"feed")

    def fake_verify(self, *args):
        if self.reject_archive:
            raise ValueError("forged app archive")
        self.archive_verified = True

    def fake_run(self, *args, cwd=None, capture=False):
        if args[:2] == ("git", "push") and "refs/heads/main" in args[-1]:
            self.assertTrue(self.archive_verified, "archive must be verified before main push")
        if args[:2] == ("git", "clone"):
            args = ("git", "clone", str(self.bare), args[-1])
        if args[:3] == ("gh", "release", "download"):
            name = args[args.index("--pattern") + 1]
            directory = Path(args[args.index("--dir") + 1])
            (directory / name).write_bytes(self.asset_data)
            return None
        if args[0] == "gh":
            raise AssertionError("no PR API or other gh write is allowed: " + repr(args))
        result = subprocess.run(args, cwd=cwd, check=True, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        return result.stdout.strip() if capture else None

    def invoke(self):
        work = Path(tempfile.mkdtemp(prefix="finalize-", dir=self.root))
        with patch.dict(os.environ, PUBLISHER_TOKEN="fixture", PUBLISHER_REPOSITORY=REPOSITORY,
                        PUBLISHER_APP_ID="5801152", PUBLISHER_APP_SLUG="maxmeisreleasebot", PUBLISHER_BOT_USER_ID="357859028",
                        PUBLISHER_INSTALLATION_ID="182962225"), \
             patch.object(subject, "api", side_effect=self.fake_api), \
             patch.object(subject, "run", side_effect=self.fake_run), \
             patch.object(subject, "download_asset", side_effect=self.fake_download_asset), \
             patch.object(subject, "verify", side_effect=self.fake_verify):
            return subject.finalize(REPOSITORY, REPOSITORY, 42, work)

    def assert_rejected(self):
        before = self.main_head()
        with self.assertRaises(ValueError):
            self.invoke()
        self.assertEqual(self.main_head(), before)

    def test_forged_archive_blocks_main_publication(self):
        self.reject_archive = True
        self.assert_rejected()
        self.assertFalse(self.archive_verified)

    def test_passing_metadata_fast_forwards_main_without_a_pull_request(self):
        self.assertEqual(self.invoke(), "published")
        self.assertEqual(self.main_head(), self.head)
        actual = self.git("--git-dir", str(self.bare), "show", f"main:{self.path}")
        self.assertEqual(actual, self.content.strip())
        self.assertEqual(self.invoke(), "already published")
        self.assertEqual(self.main_head(), self.head)

    def test_installation_scope_must_be_exactly_this_repository(self):
        self.publisher["total_count"] = 2
        self.publisher["repositories"].append({"full_name": "maxmeis/other"})
        self.assert_rejected()

    def test_installation_scope_rejects_wrong_repository(self):
        self.publisher["repositories"] = [{"full_name": "maxmeis/other"}]
        self.assert_rejected()

    def test_stable_metadata_uses_its_own_release_asset_and_cask(self):
        self.channel, self.branch, self.version = "stable", "release-casks/stable", "1.2.3"
        self.path = "Casks/hypermug.rb"
        self.content = cask("stable", self.version, asset_url(REPOSITORY, "v1.2.3", "HyperMug-1.2.3.zip"), "a" * 64)
        self.git("checkout", "-b", self.branch, "main", cwd=self.seed)
        target = self.seed / self.path
        target.parent.mkdir(exist_ok=True); target.write_text(self.content)
        self.git("add", self.path, cwd=self.seed)
        self.git("commit", "-m", "chore: publish stable cask", cwd=self.seed)
        self.update_candidate_head()
        self.ci["head_branch"] = self.branch
        self.asset_data = self.content.encode()
        self.release.update(tag_name="v1.2.3", prerelease=False, assets=[
            dict(name="hypermug.rb", digest="sha256:" + hashlib.sha256(self.asset_data).hexdigest()),
            dict(name="HyperMug-1.2.3.zip", id=22, size=3, digest="sha256:" + "a" * 64),
            dict(name="appcast-stable.xml", id=23, size=3, digest="sha256:" + "b" * 64)])
        self.assertEqual(self.invoke(), "published")
        self.assertEqual(self.main_head(), self.head)
        self.assertNotIn("hypermug@canary.rb", self.git("--git-dir", str(self.bare), "ls-tree", "-r", "main"))

    def test_app_token_push_ci_can_publish_without_an_extra_dispatch(self):
        self.ci["event"] = "push"
        self.assertEqual(self.invoke(), "published")
        self.assertEqual(self.main_head(), self.head)

    def test_rejects_fork_and_untrusted_events_or_workflow(self):
        original = copy.deepcopy(self.ci)
        for field, value in [("event", "pull_request"), ("status", "in_progress"),
                             ("conclusion", "failure"), ("path", ".github/workflows/other.yml"),
                             ("head_repository", {"full_name": "outsider/HyperMug"}),
                             ("head_branch", "untrusted")]:
            with self.subTest(field=field):
                self.ci = copy.deepcopy(original); self.ci[field] = value
                self.assert_rejected()

    def test_wrong_publisher_proof_fails_before_api_access(self):
        with patch.dict(os.environ, PUBLISHER_REPOSITORY=REPOSITORY,
                        PUBLISHER_APP_ID="wrong", PUBLISHER_APP_SLUG="maxmeisreleasebot",
                        PUBLISHER_BOT_USER_ID="357859028", PUBLISHER_INSTALLATION_ID="182962225"), \
             patch.object(subject, "api", side_effect=self.fake_api):
            with self.assertRaisesRegex(ValueError, "verified release-bot action output"):
                subject.verify_publisher(REPOSITORY)
        self.assertEqual(self.api_calls, [])

    def test_each_pinned_publisher_output_is_required(self):
        proof = dict(PUBLISHER_REPOSITORY=REPOSITORY, PUBLISHER_APP_ID="5801152",
                     PUBLISHER_APP_SLUG="maxmeisreleasebot", PUBLISHER_BOT_USER_ID="357859028",
                     PUBLISHER_INSTALLATION_ID="182962225")
        wrong = dict(PUBLISHER_REPOSITORY="maxmeis/other", PUBLISHER_APP_ID="5801153",
                     PUBLISHER_APP_SLUG="other-app", PUBLISHER_BOT_USER_ID="357859029",
                     PUBLISHER_INSTALLATION_ID="182962226")
        for field, value in wrong.items():
            with self.subTest(field=field), patch.dict(os.environ, dict(proof, **{field: value})), \
                 patch.object(subject, "api", side_effect=self.fake_api):
                with self.assertRaisesRegex(ValueError, "verified release-bot action output"):
                    subject.verify_publisher(REPOSITORY)
        self.assertEqual(self.api_calls, [])

    def test_consumer_preflight_reads_exact_scope_immutability_and_actions(self):
        with patch.dict(os.environ, PUBLISHER_REPOSITORY=REPOSITORY,
                        PUBLISHER_APP_ID="5801152", PUBLISHER_APP_SLUG="maxmeisreleasebot",
                        PUBLISHER_BOT_USER_ID="357859028", PUBLISHER_INSTALLATION_ID="182962225"), \
             patch.object(subject, "api", side_effect=self.fake_api):
            subject.verify_publisher(REPOSITORY)
        self.assertEqual(self.api_calls, [
            "installation/repositories?per_page=100&page=1",
            f"repos/{REPOSITORY}/immutable-releases",
            f"repos/{REPOSITORY}/actions/runs?per_page=1",
        ])
        self.assertNotIn("user", self.api_calls)

    def test_consumer_preflight_rejects_missing_immutable_or_actions_access(self):
        self.immutable["enabled"] = False
        self.assert_rejected()
        self.immutable["enabled"] = True
        self.actions = {"message": "Resource not accessible by integration"}
        self.assert_rejected()

    def test_required_check_must_belong_to_this_exact_run_head_and_actions_app(self):
        original = copy.deepcopy(self.check)
        for field, value in [("app", {"id": 123}), ("head_sha", "b" * 40),
                             ("name", "other"), ("conclusion", "failure"),
                             ("status", "in_progress"), ("details_url", "https://example.invalid/")]:
            with self.subTest(field=field):
                self.check = copy.deepcopy(original); self.check[field] = value
                self.assert_rejected()

    def test_superseded_branch_does_not_publish_an_old_ci_run(self):
        self.git("commit", "--allow-empty", "-m", "chore: replace candidate", cwd=self.seed)
        self.git("push", "origin", self.branch, cwd=self.seed)
        self.assertEqual(self.invoke(), "superseded")
        self.assertEqual(self.main_head(), self.source)

    def test_rejects_code_changes_hidden_next_to_a_valid_cask(self):
        self.git("reset", "--soft", "HEAD^", cwd=self.seed)
        (self.seed / "README.md").write_text("unreviewed code\n")
        self.git("add", ".", cwd=self.seed)
        self.git("commit", "-m", "chore: malicious metadata", cwd=self.seed)
        self.head = self.git("rev-parse", "HEAD", cwd=self.seed)
        self.ci["head_sha"] = self.check["head_sha"] = self.head
        self.git("push", "--force", "origin", self.branch, cwd=self.seed)
        self.assert_rejected()

    def test_rejects_unreviewed_code_in_the_candidate_parent(self):
        self.git("reset", "--hard", "main", cwd=self.seed)
        (self.seed / "README.md").write_text("unapproved parent\n")
        self.git("add", ".", cwd=self.seed)
        self.git("commit", "-m", "feat: unapproved parent", cwd=self.seed)
        target = self.seed / self.path
        target.parent.mkdir(exist_ok=True); target.write_text(self.content)
        self.git("add", self.path, cwd=self.seed)
        self.git("commit", "-m", "chore: cask hiding parent", cwd=self.seed)
        self.update_candidate_head()
        self.assert_rejected()

    def test_exact_asset_comparison_preserves_trailing_bytes(self):
        (self.seed / self.path).write_text(self.content + "\n")
        self.git("commit", "-am", "chore: change trailing bytes", cwd=self.seed)
        # Keep one metadata commit, so the byte check is the rejecting boundary.
        self.git("reset", "--soft", "main", cwd=self.seed)
        self.git("commit", "-m", "chore: changed cask bytes", cwd=self.seed)
        self.update_candidate_head()
        self.assert_rejected()

    def test_cask_must_not_be_executable(self):
        self.git("update-index", "--chmod=+x", self.path, cwd=self.seed)
        self.git("commit", "--amend", "--no-edit", cwd=self.seed)
        self.update_candidate_head()
        self.assert_rejected()

    def test_rejects_unpublished_mutable_source_only_or_wrong_channel_releases(self):
        original = copy.deepcopy(self.release)
        for field, value in [("draft", True), ("immutable", False), ("prerelease", False),
                             ("body", "source-only; source " + self.source),
                             ("body", "source " + "b" * 40), ("assets", [])]:
            with self.subTest(field=field):
                self.release = copy.deepcopy(original); self.release[field] = value
                self.assert_rejected()

    def test_rejects_mismatched_download_and_cask_not_equal_to_renderer(self):
        self.asset_data += b"\n"
        self.assert_rejected()

    def test_rejects_tampered_asset_even_when_its_digest_matches(self):
        self.asset_data = self.content.replace('  app "HyperMug.app"', '  system_command "evil"').encode()
        self.release["assets"][0]["digest"] = "sha256:" + hashlib.sha256(self.asset_data).hexdigest()
        self.assert_rejected()

    def test_main_advance_schedules_fresh_ci_instead_of_pushing_old_head(self):
        self.git("checkout", "main", cwd=self.seed)
        (self.seed / "README.md").write_text("new approved source\n")
        self.git("add", ".", cwd=self.seed)
        self.git("commit", "-m", "feat: main advances during CI", cwd=self.seed)
        current = self.git("rev-parse", "HEAD", cwd=self.seed)
        self.git("push", "origin", "main", cwd=self.seed)
        with patch.object(subject, "publish") as prepare:
            self.assertEqual(self.invoke(), "rebased; awaiting fresh CI")
            self.assertEqual(prepare.call_args.args[:3], ("canary", self.version, REPOSITORY))
        self.assertEqual(self.main_head(), current)

    def test_older_cask_cannot_replace_a_newer_published_main_cask(self):
        self.git("checkout", "main", cwd=self.seed)
        target = self.seed / self.path
        target.parent.mkdir(exist_ok=True)
        target.write_text(cask("canary", "0.0.0-canary.3",
                               asset_url(REPOSITORY, "v0.0.0-canary.3", "HyperMug-0.0.0-canary.3.zip"), "b" * 64))
        self.git("add", self.path, cwd=self.seed)
        self.git("commit", "-m", "chore: newer published cask", cwd=self.seed)
        self.git("push", "origin", "main", cwd=self.seed)
        current = self.main_head()
        self.assertEqual(self.invoke(), "superseded")
        self.assertEqual(self.main_head(), current)

    def test_push_error_without_main_advance_is_not_reported_as_success(self):
        def reject_push(*args, **kwargs):
            if args[:2] == ("git", "push"):
                raise subprocess.CalledProcessError(1, args)
            return self.fake_run(*args, **kwargs)
        with patch.dict(os.environ, PUBLISHER_TOKEN="fixture", PUBLISHER_REPOSITORY=REPOSITORY,
                        PUBLISHER_APP_ID="5801152", PUBLISHER_APP_SLUG="maxmeisreleasebot", PUBLISHER_BOT_USER_ID="357859028",
                        PUBLISHER_INSTALLATION_ID="182962225"), \
             patch.object(subject, "api", side_effect=self.fake_api), \
             patch.object(subject, "run", side_effect=reject_push), \
             patch.object(subject, "download_asset", side_effect=self.fake_download_asset), \
             patch.object(subject, "verify", side_effect=self.fake_verify), \
             patch.object(subject, "publish") as prepare:
            with self.assertRaises(subprocess.CalledProcessError):
                subject.finalize(REPOSITORY, REPOSITORY, 42, self.root / "reject-push")
            prepare.assert_not_called()
        self.assertEqual(self.main_head(), self.source)

    def test_push_race_rebuilds_metadata_and_requires_new_ci(self):
        def racing_push(*args, **kwargs):
            if args[:2] == ("git", "push"):
                self.git("checkout", "main", cwd=self.seed)
                (self.seed / "README.md").write_text("concurrent owner merge\n")
                self.git("commit", "-am", "feat: concurrent approved source", cwd=self.seed)
                self.git("push", "origin", "main", cwd=self.seed)
                raise subprocess.CalledProcessError(1, args)
            return self.fake_run(*args, **kwargs)
        with patch.dict(os.environ, PUBLISHER_TOKEN="fixture", PUBLISHER_REPOSITORY=REPOSITORY,
                        PUBLISHER_APP_ID="5801152", PUBLISHER_APP_SLUG="maxmeisreleasebot", PUBLISHER_BOT_USER_ID="357859028",
                        PUBLISHER_INSTALLATION_ID="182962225"), \
             patch.object(subject, "api", side_effect=self.fake_api), \
             patch.object(subject, "run", side_effect=racing_push), \
             patch.object(subject, "download_asset", side_effect=self.fake_download_asset), \
             patch.object(subject, "verify", side_effect=self.fake_verify), \
             patch.object(subject, "publish") as prepare:
            self.assertEqual(subject.finalize(REPOSITORY, REPOSITORY, 42, self.root / "race"),
                             "rebased; awaiting fresh CI")
            prepare.assert_called_once()
        self.assertNotEqual(self.main_head(), self.head)


class ReleaseAssetDownloadTests(unittest.TestCase):
    def test_exact_asset_id_and_digest_are_required(self):
        with tempfile.TemporaryDirectory() as temp:
            target = Path(temp) / "app.zip"
            data = b"final archive"
            asset = dict(id=12345, size=len(data), digest="sha256:" + hashlib.sha256(data).hexdigest())
            def download(command, **kwargs):
                self.assertEqual(command[:3], ["gh", "api", "repos/maxmeis/hypermug/releases/assets/12345"])
                self.assertEqual(command[-2:], ["-H", "Accept: application/octet-stream"])
                kwargs["stdout"].write(data)
                return subprocess.CompletedProcess(command, 0)
            with patch.object(subject.subprocess, "run", side_effect=download):
                subject.download_asset(REPOSITORY, asset, target)
            self.assertEqual(target.read_bytes(), data)
            target.unlink()
            with patch.object(subject.subprocess, "run", side_effect=download):
                with self.assertRaisesRegex(ValueError, "identity mismatch"):
                    subject.download_asset(REPOSITORY, dict(asset, digest="sha256:" + "0" * 64), target)
            with self.assertRaisesRegex(ValueError, "identity is incomplete"):
                subject.download_asset(REPOSITORY, dict(asset, id=0), target)


class GitCredentialTests(unittest.TestCase):
    def test_token_stays_out_of_git_arguments_and_remote_urls(self):
        result = subprocess.CompletedProcess([], 0, stdout="ok\n")
        with patch.dict(os.environ, PUBLISHER_TOKEN="private-fixture-token", GIT_CONFIG_COUNT="0"), \
             patch.object(subprocess, "run", return_value=result) as execute:
            self.assertEqual(publish_source_cask.run("git", "clone",
                             "https://github.com/maxmeis/hypermug.git", "checkout", capture=True), "ok")
        args, kwargs = execute.call_args
        self.assertNotIn("private-fixture-token", repr(args))
        self.assertEqual(kwargs["env"]["GIT_CONFIG_KEY_0"], "http.https://github.com/.extraheader")
        self.assertTrue(kwargs["env"]["GIT_CONFIG_VALUE_0"].startswith("AUTHORIZATION: basic "))


if __name__ == "__main__":
    unittest.main()
