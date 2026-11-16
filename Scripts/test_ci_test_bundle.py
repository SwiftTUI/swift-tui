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
        for target, value in [('RECEIPT', self.receipt), ('identity', lambda kind='debug': self.identity)]:
            patcher = patch.object(bundle, target, value)
            patcher.start()
            self.addCleanup(patcher.stop)

    def verify(self, changes='', additions='', arguments=('verify',)):
        with patch('sys.argv', ['ci_test_bundle.py', *arguments]), patch.object(
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


class BundleKindTests(unittest.TestCase):
    """A debug bundle must never satisfy the release lane, or the reverse."""

    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory()
        self.addCleanup(self.scratch.cleanup)
        self.receipt = Path(self.scratch.name) / 'receipt.json'
        patcher = patch.object(bundle, 'RECEIPT', self.receipt)
        patcher.start()
        self.addCleanup(patcher.stop)

    @staticmethod
    def clean_checkout(command, **_):
        # identity() asks git for the revision and swiftly for the toolchain;
        # verify_checkout() asks git for tracked edits and for new sources.
        # pack and verify make those calls in different orders.
        if command[:2] == ['git', 'rev-parse']:
            return 'abc\n'
        if command[0] == 'swiftly':
            return 'swift 6.4.0\n'
        return ''

    def run_main(self, *arguments):
        with patch('sys.argv', ['ci_test_bundle.py', *arguments]), patch.object(
                bundle.subprocess, 'check_output', side_effect=self.clean_checkout), patch.object(
                bundle.tarfile, 'open'):
            bundle.main()

    def write_receipt(self, kind):
        with patch.object(bundle.subprocess, 'check_output', side_effect=self.clean_checkout):
            self.receipt.write_text(json.dumps(bundle.identity(kind)))

    def test_each_kind_has_its_own_build_identity(self):
        self.assertEqual(sorted(bundle.BUILD_IDENTITIES), ['debug', 'release'])
        self.assertEqual(len(set(bundle.BUILD_IDENTITIES.values())), 2)

    def test_kind_defaults_to_debug(self):
        self.assertEqual(bundle.parse_arguments(['verify']), ('verify', 'debug'))
        self.assertEqual(bundle.parse_arguments(['pack', '--kind', 'release']), ('pack', 'release'))

    def test_matching_kind_is_accepted(self):
        for kind in bundle.BUILD_IDENTITIES:
            with self.subTest(kind=kind):
                self.write_receipt(kind)
                self.run_main('verify', '--kind', kind)

    def test_a_bundle_of_the_other_kind_is_rejected(self):
        for packed, wanted in [('debug', 'release'), ('release', 'debug')]:
            with self.subTest(packed=packed, wanted=wanted):
                self.write_receipt(packed)
                with self.assertRaisesRegex(SystemExit, 'identity mismatch'):
                    self.run_main('verify', '--kind', wanted)

    def test_only_the_debug_bundle_requires_warnings_as_errors(self):
        with patch.dict(bundle.os.environ, clear=False):
            bundle.os.environ.pop('SWIFTTUI_WARNINGS_AS_ERRORS', None)
            with self.assertRaisesRegex(SystemExit, 'warnings as errors'):
                self.run_main('pack')
            self.run_main('pack', '--kind', 'release')
        self.assertEqual(json.loads(self.receipt.read_text())['build'],
                         bundle.BUILD_IDENTITIES['release'])

    def test_malformed_invocations_print_usage(self):
        for arguments in [[], ['pack', 'release'], ['verify', '--kind'], ['verify', '--kind', 'profile'],
                          ['unpack'], ['pack', '--kind', 'release', 'extra']]:
            with self.subTest(arguments=arguments):
                with self.assertRaisesRegex(SystemExit, 'usage: ci_test_bundle.py'):
                    bundle.parse_arguments(arguments)


if __name__ == '__main__':
    unittest.main()
