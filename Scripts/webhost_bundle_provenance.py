#!/usr/bin/env python3
"""Create and verify the selected browser bundle's immutable input/resource record."""
import argparse
import datetime
import hashlib
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BUNDLE = ROOT / 'Platforms/WebHost/Sources/SwiftTUIWebHost/Resources/browser'
STAMP = 'bundle-provenance.json'
INPUTS = ('bun.lock', 'package.json', 'packages/web/package.json', 'packages/build/package.json',
          'packages/web/contract-profile.json', 'packages/web/cli.ts', 'packages/build/index.ts',
          'packages/build/src/build/buildBrowserBundle.ts', 'packages/build/src/build/copyDomFontAssets.ts',
          'packages/build/src/build/runCommand.ts')
BUILDERS = ('Scripts/update_webhost_bundle.sh', 'Scripts/webhost_bundle_provenance.py')
COMMANDS = [['bun', 'install', '--frozen-lockfile'], ['bun', 'run', 'build:packages'],
            ['bun', 'run', 'cli.ts', 'build:web', '--renderer', 'canvas', '--dist', '<fresh-output>']]
BUNDLE_PATHS = ['packages/web', 'packages/build/index.ts', 'packages/build/src/build/buildBrowserBundle.ts',
                'packages/build/src/build/copyDomFontAssets.ts', 'packages/build/src/build/runCommand.ts', 'bun.lock',
                ':(exclude)packages/web/**/*.test.ts', ':(exclude)packages/web/**/*.test.tsx',
                ':(exclude)packages/web/e2e', ':(exclude)packages/web/test-support']


def require(condition, message):
    if not condition:
        raise ValueError(message)


def read_json(data):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            require(key not in result, f'duplicate field: {key}')
            result[key] = value
        return result
    return json.loads(data, object_pairs_hook=unique)


def run(command):
    return subprocess.check_output(command, stderr=subprocess.PIPE)


def git(repo, *args):
    return run(['git', '-C', str(repo), *args]).decode().strip()


def sha(data):
    return hashlib.sha256(data).hexdigest()


def files(bundle):
    result = {}
    for path in sorted(bundle.rglob('*')):
        require(not path.is_symlink(), 'bundle resources must not contain symlinks')
        relative = str(path.relative_to(bundle))
        if path.is_file() and relative != STAMP:
            result[relative] = sha(path.read_bytes())
    require('index.html' in result and any(p.endswith('.js') for p in result), 'missing HTML/JavaScript bundle resources')
    return result


def source_inputs(web, revision):
    return {path: sha(run(['git', '-C', str(web), 'show', f'{revision}:{path}'])) for path in INPUTS}


def create(bundle, web, tag, candidate, allow_dirty, bun, framework=ROOT):
    require(bool(tag) != candidate, 'choose --web-tag VERSION or --candidate')
    dirty = bool(git(web, 'status', '--porcelain'))
    require(not dirty or (candidate and allow_dirty), 'dirty web checkout is only allowed for an explicit local candidate')
    revision = git(web, 'rev-parse', 'HEAD')
    if tag:
        require(re.fullmatch(r'0\.(0|[1-9]\d*)\.(0|[1-9]\d*)', tag), 'invalid stable pre-1.0 web tag')
        require(git(web, 'rev-parse', f'refs/tags/{tag}^{{commit}}') == revision, 'selected tag does not name the build checkout')
        for path in ('package.json', 'packages/web/package.json', 'packages/build/package.json'):
            require(read_json((web / path).read_bytes())['version'] == tag, 'selected web tag/package versions disagree')
    profile = read_json((web / 'packages/web/contract-profile.json').read_bytes())
    require('swifttui.host-wire/1' in profile['profiles'] and 'swifttui.companion/1' in profile['profiles'], 'missing bundled companion profiles')
    record = {
        'formatVersion': 2, 'selection': 'dirty-candidate' if dirty else 'candidate' if candidate else 'release',
        'webTag': tag, 'webRevision': revision, 'webTree': git(web, 'rev-parse', 'HEAD^{tree}'),
        'webDescribe': git(web, 'describe', '--tags', '--always', '--dirty'),
        'builtAt': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'build': {'bunVersion': bun, 'commands': COMMANDS,
                  'inputs': {path: sha((web / path).read_bytes()) for path in INPUTS},
                  'builders': {path: sha((framework / path).read_bytes()) for path in BUILDERS},
                  'profiles': profile['profiles']},
        'resources': files(bundle),
    }
    (bundle / STAMP).write_text(json.dumps(record, indent=2, sort_keys=True) + '\n')
    return record


def verify(bundle, web=None, require_release=False, public_tag=False, forward_current=False, framework=ROOT):
    record = read_json((bundle / STAMP).read_bytes())
    require(set(record) == {'formatVersion', 'selection', 'webTag', 'webRevision', 'webTree', 'webDescribe', 'builtAt', 'build', 'resources'}, 'unsupported provenance fields')
    require(record['formatVersion'] == 2, 'expected provenance format 2')
    require(record['selection'] in {'candidate', 'release'}, 'dirty or unknown bundle selection')
    require(not require_release or record['selection'] == 'release', 'release acceptance requires a selected public web tag')
    for key in ('webRevision', 'webTree'):
        require(re.fullmatch(r'[0-9a-f]{40}', record[key]), f'invalid {key}')
    tag = record['webTag']
    require((record['selection'] == 'candidate' and tag is None) or
            (record['selection'] == 'release' and isinstance(tag, str) and re.fullmatch(r'0\.(0|[1-9]\d*)\.(0|[1-9]\d*)', tag)), 'selection/tag mismatch')
    require(isinstance(record['webDescribe'], str) and record['webDescribe'] and '-dirty' not in record['webDescribe'], 'dirty or missing web describe')
    require(datetime.datetime.fromisoformat(record['builtAt']).tzinfo is not None, 'missing build timestamp timezone')
    build = record['build']
    require(set(build) == {'bunVersion', 'commands', 'inputs', 'builders', 'profiles'}, 'unsupported build metadata')
    require(re.fullmatch(r'\d+\.\d+\.\d+', build['bunVersion']), 'missing Bun toolchain version')
    require(build['commands'] == COMMANDS and set(build['inputs']) == set(INPUTS), 'build inputs/commands differ')
    require(build['builders'] == {path: sha((framework / path).read_bytes()) for path in BUILDERS}, 'framework bundle builder differs')
    require(all(re.fullmatch(r'[a-f0-9]{64}', value) for value in build['inputs'].values()), 'invalid build input digest')
    require(isinstance(build['profiles'], list) and len(build['profiles']) == len(set(build['profiles'])) and
            {'swifttui.host-wire/1', 'swifttui.companion/1'} <= set(build['profiles']), 'missing/duplicate bundle profiles')
    require(record['resources'] == files(bundle), 'bundle resource membership or digest differs')
    if web:
        revision = record['webRevision']
        require(git(web, 'rev-parse', f'{revision}^{{tree}}') == record['webTree'], 'selected source tree differs')
        require(source_inputs(web, revision) == build['inputs'], 'selected build input digest differs')
        profile = read_json(run(['git', '-C', str(web), 'show', f'{revision}:packages/web/contract-profile.json']))
        require(profile['profiles'] == build['profiles'], 'selected source profiles differ')
        if tag:
            require(git(web, 'rev-parse', f'refs/tags/{tag}^{{commit}}') == revision, 'selected tag/revision differs')
        if forward_current:
            changed = git(web, 'diff', '--name-only', revision, 'HEAD', '--', *BUNDLE_PATHS)
            require(not changed, f'forward-current bundle inputs differ:\n{changed}')
    else:
        require(not forward_current, '--forward-current requires --web-checkout')
    if public_tag:
        require(tag, 'public verification requires a selected release tag')
        refs = dict(line.split()[::-1] for line in run(['git', 'ls-remote', 'https://github.com/SwiftTUI/swift-tui-web.git',
                    f'refs/tags/{tag}', f'refs/tags/{tag}^{{}}']).decode().splitlines())
        require(refs.get(f'refs/tags/{tag}^{{}}', refs.get(f'refs/tags/{tag}')) == record['webRevision'], 'public web tag/revision differs')
    return record


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('operation', choices=['create', 'verify'])
    parser.add_argument('--bundle', type=Path, default=BUNDLE)
    parser.add_argument('--web-checkout', type=Path)
    parser.add_argument('--web-tag')
    parser.add_argument('--candidate', action='store_true')
    parser.add_argument('--allow-dirty', action='store_true')
    parser.add_argument('--bun-version')
    parser.add_argument('--require-release', action='store_true')
    parser.add_argument('--public-tag', action='store_true')
    parser.add_argument('--forward-current', action='store_true')
    args = parser.parse_args()
    try:
        if args.operation == 'create':
            require(args.web_checkout and args.bun_version, 'creation requires a web checkout and Bun version')
            record = create(args.bundle, args.web_checkout, args.web_tag, args.candidate, args.allow_dirty, args.bun_version)
        else:
            record = verify(args.bundle, args.web_checkout, args.require_release, args.public_tag, args.forward_current)
        print(f"[webhost provenance] {record['selection']} {record['webTag'] or record['webRevision']}: {len(record['resources'])} resources verified")
    except (ValueError, KeyError, TypeError, OSError, subprocess.CalledProcessError) as error:
        parser.exit(1, f'[webhost provenance] {error}\n')


if __name__ == '__main__':
    main()
