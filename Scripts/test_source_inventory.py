#!/usr/bin/env python3
"""Independent fixture census and base/head change-detection checks."""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from source_inventory import census, compare, render


class InventoryTests(unittest.TestCase):
    def test_container_setup_allows_reporting_from_a_differently_owned_checkout(self):
        scripts = Path(__file__).resolve().parent
        with tempfile.TemporaryDirectory() as directory:
            fixture = Path(directory).resolve()
            root = fixture / "checkout with spaces"
            (root / "Scripts/data").mkdir(parents=True)
            for name in ("prepare_ci_container.sh", "source_inventory.py"):
                shutil.copyfile(scripts / name, root / "Scripts" / name)
            shutil.copyfile(scripts.parent / ".swift-version", root / ".swift-version")
            (root / "Scripts/data/test-ownership.json").write_text('{"files": {}}')
            (root / "baseline.json").write_text('{"files": []}')
            (root / "Example.swift").write_text("let example = 1\n")
            manifest = {"targets": [{"name": "Example", "type": "library",
                                     "path": ".", "sources": ["Example.swift"]}]}
            (root / "manifest.json").write_text(json.dumps(manifest))
            toolchain = fixture / "toolchain"
            toolchain.mkdir()
            (toolchain / "env.sh").write_text(":\n")
            stubs = {
                "swiftly": '#!/bin/sh\ncase "$*" in\n'
                           '  "run swift --version") printf "Swift version %s\\n" "$(cat .swift-version)" ;;\n'
                           '  "run swift package describe --type json") cat manifest.json ;;\n'
                           '  *) exit 1 ;;\nesac\n',
                "bun": '#!/bin/sh\nprintf "fixture\\n"\n',
            }
            for name, contents in stubs.items():
                path = toolchain / name
                path.write_text(contents)
                path.chmod(0o755)
            env = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
            env.update(GIT_CONFIG_GLOBAL=str(fixture / "gitconfig"), GIT_CONFIG_NOSYSTEM="1",
                       SWIFTLY_HOME_DIR=str(toolchain), SWIFTLY_BIN_DIR=str(toolchain),
                       BUN_INSTALL=str(fixture), GITHUB_PATH=str(fixture / "github-path"),
                       GITHUB_ENV=str(fixture / "github-env"),
                       PATH=str(toolchain) + os.pathsep + env["PATH"])

            def run(*command, cwd=root):
                return subprocess.run(command, cwd=cwd, env=env, text=True, capture_output=True)

            def succeeds(*command, cwd=root):
                result = run(*command, cwd=cwd)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                return result.stdout.strip()

            succeeds("git", "init", "--quiet")
            succeeds("git", "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
                     "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null",
                     "commit", "--quiet", "--allow-empty", "-m", "Fixture")
            revision = succeeds("git", "rev-parse", "HEAD")
            unrelated = fixture / "unrelated"
            unrelated.mkdir()
            succeeds("git", "init", "--quiet", cwd=unrelated)
            # Exercise Git's real ownership guard without requiring root/chown.
            env["GIT_TEST_ASSUME_DIFFERENT_OWNER"] = "1"
            output = root / ".build/source-observations/census.json"
            inventory = (sys.executable, "Scripts/source_inventory.py", "--compare", "baseline.json",
                         "--output", str(output))
            rejected = run(*inventory)
            self.assertNotEqual(rejected.returncode, 0)
            self.assertIn("detected dubious ownership", rejected.stderr)
            self.assertFalse(output.exists())

            succeeds("bash", "Scripts/prepare_ci_container.sh")
            # A separate process models the later workflow reporting step.
            succeeds(*inventory)
            data = json.loads(output.read_text())
            self.assertEqual(data["sourceRevision"], revision)
            self.assertEqual(data["files"][0]["path"], "Example.swift")
            self.assertIn(revision, output.with_suffix(".md").read_text())
            self.assertEqual(json.loads(output.with_suffix(".diff.json").read_text())[0]["change"], "added")
            rejected = run("git", "rev-parse", "--show-toplevel", cwd=unrelated)
            self.assertNotEqual(rejected.returncode, 0)
            self.assertIn("detected dubious ownership", rejected.stderr)

    def test_manifest_ownership_and_exclusions(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            sources = {"Tests/Support/Helper.swift": "// comment\n\nlet x = 1\n",
                       "Custom/Case.swift": "@Test func example() {}\n",
                       "Vendor/V.swift": "let vendored = 1\n",
                       "Custom/Generated.swift": "// Generated by fixture\nlet x = 2\n"}
            for name, content in sources.items():
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(content)
            manifest = {"targets": [
                {"name": "Support", "type": "library", "path": "Tests/Support", "sources": ["Helper.swift"]},
                {"name": "Cases", "type": "test", "path": "Custom", "sources": ["Case.swift", "Generated.swift"]},
                {"name": "Vendor", "type": "library", "path": "Vendor", "sources": ["V.swift"]}]}
            result = census(root, manifest, {}, "fixture")
            self.assertEqual(len(result["files"]), 2)
            self.assertEqual(len(result["excluded"]), 2)
            helper = next(r for r in result["files"] if r["target"] == "Support")
            self.assertEqual((helper["kind"], helper["lines"]), ("library", 3))
            self.assertIn("1 unclassified", render(result))
            self.assertEqual(result, census(root, manifest, {}, "fixture"))

    def test_add_delete_rename_target_move_and_edit(self):
        def row(path, target="A", digest="same", lines=1):
            return dict(path=path, target=target, sha256=digest, lines=lines)
        before = {"files": [row("old"), row("deleted", digest="delete"), row("moved", digest="move"), row("edited", digest="before")]}
        after = {"files": [row("renamed"), row("added", digest="add"), row("moved", target="B", digest="changed"), row("edited", digest="after", lines=2)]}
        self.assertEqual({r["change"] for r in compare(before, after)}, {"rename", "deleted", "added", "target-move", "modified"})

    def test_duplicate_content_is_not_guessed_as_a_rename(self):
        before = {"files": [dict(path="a", target="A", sha256="x"), dict(path="b", target="A", sha256="x")]}
        after = {"files": [dict(path="c", target="A", sha256="x")]}
        self.assertEqual([r["change"] for r in compare(before, after)].count("rename"), 0)


if __name__ == "__main__":
    unittest.main()
