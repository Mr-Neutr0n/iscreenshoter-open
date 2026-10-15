#!/usr/bin/env python3
"""Record the local source revision and toolchain. Never include environment secrets."""
import datetime
import hashlib
import json
import pathlib
import subprocess
import sys


def output(*args):
    return subprocess.check_output(args, text=True).strip()


root = pathlib.Path(__file__).resolve().parent.parent
source_files = [pathlib.Path(p) for p in output('git', 'ls-files').splitlines()
                if p.startswith(('Sources/', 'Resources/', 'scripts/')) or p in ('build.sh', 'Info.plist')]
manifest = {
    'schema_version': 1,
    'source_commit': output('git', 'rev-parse', 'HEAD'),
    'source_dirty': bool(output('git', 'status', '--porcelain', '--untracked-files=normal')),
    'built_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'xcode': output('xcodebuild', '-version'),
    'sdk': output('xcrun', '--sdk', 'macosx', '--show-sdk-version'),
    'swift': output('xcrun', 'swiftc', '--version'),
    'macos': output('sw_vers', '-productVersion'),
    'architecture': output('uname', '-m'),
    'deployment_target': '14.0',
    'signing_identity_type': 'ad-hoc',
    'source_file_sha256': {str(p): hashlib.sha256((root / p).read_bytes()).hexdigest()
                           for p in source_files if (root / p).is_file()},
}
import os
if os.environ.get('SCREENSHOTER_SIGNING_IDENTITY', '-') != '-':
    manifest['signing_identity_type'] = 'developer-id'
pathlib.Path(sys.argv[1]).write_text(json.dumps(manifest, indent=2, sort_keys=True) + '\n')
