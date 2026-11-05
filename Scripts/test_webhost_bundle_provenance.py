#!/usr/bin/env python3
"""Selection-based browser provenance, including forward and tamper controls."""
import json
import subprocess
import tempfile
import unittest
from pathlib import Path

import webhost_bundle_provenance as provenance


class ProvenanceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        root = Path(self.temporary.name)
        self.web, self.bundle, self.framework = root / 'web', root / 'bundle', root / 'framework'
        self.web.mkdir(); self.bundle.mkdir()
        for path in provenance.INPUTS:
            target = self.web / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text('fixture source\n')
        for path in ['package.json', 'packages/web/package.json', 'packages/build/package.json']:
            (self.web / path).write_text('{"version":"0.21.0"}\n')
        (self.web / 'packages/web/contract-profile.json').write_text(json.dumps({'profiles': ['swifttui.host-wire/1', 'swifttui.companion/1']}))
        for path in provenance.BUILDERS:
            target = self.framework / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text('fixture builder\n')
        (self.bundle / 'index.html').write_text('<script src="bundle.js"></script>')
        (self.bundle / 'bundle.js').write_text('console.log("selected release");')
        self.git('init', '-q')
        self.git('config', 'user.name', 'Fixture')
        self.git('config', 'user.email', 'fixture@example.invalid')
        self.git('config', 'core.hooksPath', '/dev/null')
        self.git('config', 'commit.gpgsign', 'false')
        self.commit('release')
        self.git('tag', '0.21.0')
        self.create()

    def git(self, *args):
        return provenance.git(self.web, *args)

    def commit(self, message):
        self.git('add', '.')
        self.git('commit', '-qm', message)

    def create(self, *, candidate=False, allow_dirty=False):
        return provenance.create(self.bundle, self.web, None if candidate else '0.21.0', candidate, allow_dirty, '1.3.14', self.framework)

    def verify(self, **options):
        return provenance.verify(self.bundle, self.web, framework=self.framework, **options)

    def alter(self, change):
        path = self.bundle / provenance.STAMP
        record = json.loads(path.read_text())
        change(record)
        path.write_text(json.dumps(record))

    def test_new_web_development_does_not_change_selected_bundle(self):
        revision = self.verify(require_release=True)['webRevision']
        (self.web / 'packages/web/runtime.ts').write_text('new incompatible runtime')
        self.commit('new web development')
        self.assertNotEqual(self.git('rev-parse', 'HEAD'), revision)
        self.assertEqual(self.verify(require_release=True)['webRevision'], revision)
        with self.assertRaisesRegex(ValueError, 'forward-current'):
            self.verify(forward_current=True)
        # An isolated public framework clone can verify resources without a sibling.
        provenance.verify(self.bundle, framework=self.framework)

    def test_resource_tamper_membership_and_builder_changes_fail(self):
        for path in [self.bundle / 'bundle.js', self.framework / provenance.BUILDERS[0]]:
            before = path.read_bytes()
            path.write_bytes(before + b'changed')
            with self.assertRaisesRegex(ValueError, 'differs'):
                self.verify()
            path.write_bytes(before)
        (self.bundle / 'unexpected.js').write_text('extra resource')
        with self.assertRaisesRegex(ValueError, 'membership'):
            self.verify()

    def test_source_tree_input_and_contract_profile_forgery_fail(self):
        path = self.bundle / provenance.STAMP
        original = path.read_text()
        for change in [lambda r: r.update(webTree='a' * 40),
                       lambda r: r['build']['inputs'].update({'bun.lock': 'a' * 64}),
                       lambda r: r['build']['profiles'].append('unadvertised-profile')]:
            self.alter(change)
            with self.assertRaises(ValueError):
                self.verify()
            path.write_text(original)

    def test_tag_motion_is_not_an_accepted_selection(self):
        (self.web / 'package.json').write_text('{"version":"0.21.1"}')
        self.commit('different release')
        self.git('tag', '-f', '0.21.0')
        with self.assertRaisesRegex(ValueError, 'tag/revision'):
            self.verify()
        with self.assertRaisesRegex(ValueError, 'package versions'):
            self.create()

    def test_candidate_is_explicit_and_cannot_certify_a_public_release(self):
        self.create(candidate=True)
        self.verify()
        with self.assertRaisesRegex(ValueError, 'requires a selected public web tag'):
            self.verify(require_release=True)
        (self.web / 'bun.lock').write_text('dirty build')
        with self.assertRaisesRegex(ValueError, 'dirty web checkout'):
            self.create(candidate=True)
        self.create(candidate=True, allow_dirty=True)
        with self.assertRaisesRegex(ValueError, 'dirty'):
            self.verify()

    def test_duplicate_provenance_fields_and_symlinked_assets_fail(self):
        path = self.bundle / provenance.STAMP
        path.write_text('{"formatVersion":2,"formatVersion":2}')
        with self.assertRaisesRegex(ValueError, 'duplicate'):
            self.verify()
        self.create()
        (self.bundle / 'linked.js').symlink_to(self.bundle / 'bundle.js')
        with self.assertRaisesRegex(ValueError, 'symlinks'):
            self.verify()


if __name__ == '__main__':
    unittest.main()
