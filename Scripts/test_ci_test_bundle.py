#!/usr/bin/env python3
"""Fail closed on stale binaries, foreign toolchains and edited sources."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import ci_test_bundle as bundle


class BundleIdentityTests(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory()
        self.addCleanup(self.scratch.cleanup)
        self.receipt = Path(self.scratch.name) / 'receipt.json'
        self.identity = dict(revision='abc', toolchain='swift 6.4.0', platform='Linux',
                             arch='aarch64', workspace='/work/src', build='native-v1')
        self.receipt.write_text(json.dumps(self.identity))
        for target, value in [('RECEIPT', self.receipt), ('identity', lambda: self.identity)]:
            patcher = patch.object(bundle, target, value)
            patcher.start()
            self.addCleanup(patcher.stop)

    def verify(self, changes='', additions=''):
        with patch('sys.argv', ['ci_test_bundle.py', 'verify']), patch.object(
                bundle.subprocess, 'check_output', side_effect=[changes, additions]):
            bundle.main()

    def test_exact_identity_is_accepted(self):
        self.verify()

    def test_each_identity_boundary_rejects_a_foreign_bundle(self):
        for field in self.identity:
            with self.subTest(field=field):
                self.receipt.write_text(json.dumps({**self.identity, field: 'other'}))
                with self.assertRaisesRegex(SystemExit, 'identity mismatch'):
                    self.verify()

    def test_tracked_edits_cannot_run_stale_tests(self):
        with self.assertRaisesRegex(SystemExit, r'unchanged checkout; changed files:\nSources/Changed.swift'):
            self.verify(changes='Sources/Changed.swift\n')

    def test_pack_rejects_setup_mutations_before_publishing_a_bundle(self):
        with patch('sys.argv', ['ci_test_bundle.py', 'pack']), patch.dict(
                bundle.os.environ, SWIFTTUI_WARNINGS_AS_ERRORS='1'), patch.object(
                bundle.subprocess, 'check_output', return_value='.swift-version\n'):
            with self.assertRaisesRegex(SystemExit, r'changed files:\n.swift-version'):
                bundle.main()

    def test_new_sources_cannot_be_omitted_from_tests(self):
        with self.assertRaisesRegex(SystemExit, 'unbuilt source'):
            self.verify(additions='Tests/NewTests.swift\n')

    def test_absent_receipt_fails(self):
        self.receipt.unlink()
        with self.assertRaises(FileNotFoundError):
            self.verify()


if __name__ == '__main__':
    unittest.main()
