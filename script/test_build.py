#!/usr/bin/env python3
"""Build an isolated, identifiable test copy without changing production state."""
import argparse
import json
from pathlib import Path
import secrets
import shutil
import subprocess

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--build-only', action='store_true')
args = parser.parse_args()
runs = root / 'build/test-runs'
runs.mkdir(parents=True, exist_ok=True)
prior = sorted(runs.glob('*/DerivedData/Build/Products/Debug/*.app'))
print('Existing test apps (preserved):', *(str(p) for p in prior), sep='\n', flush=True)
suffix = secrets.token_hex(4)
run = runs / suffix
stage = run / 'source'
stage.mkdir(parents=True)
for name in ['AllYouNeedQuickLook', 'QuickLookExtension', 'Shared', 'scripts', 'Tests']:
    shutil.copytree(root / name, stage / name)
text = (root / 'project.yml').read_text()
text = text.replace('com.yohanpark.AllYouNeedQuickLook', 'com.yohanpark.AllYouNeedQuickLook.test.' + suffix)
text = text.replace('INFOPLIST_KEY_CFBundleDisplayName: "All You Need QuickLook"',
                    'PRODUCT_NAME: AllYouNeedQuickLook-' + suffix + '\n        INFOPLIST_KEY_CFBundleDisplayName: "AYNQL Test ' + suffix + '"')
text = text.replace('NSExtension:\n', 'CFBundleDisplayName: "AYNQL Test ' + suffix + '"\n        NSExtension:\n')
config_name = 'AllYouNeedQuickLook-Test-' + suffix
text = text.replace('/Library/Application Support/AllYouNeedQuickLook/', '/Library/Application Support/' + config_name + '/')
# Tests are run against the actual checkout, not duplicated in this UI test build.
# Include test sources so the generated project remains structurally identical.
(stage / 'project.yml').write_text(text)
p = stage / 'Shared/Config/ConfigLoader.swift'
p.write_text(p.read_text().replace('Library/Application Support/AllYouNeedQuickLook"', 'Library/Application Support/' + config_name + '"'))
with (run / 'build.log').open('w') as log:
    subprocess.run(['xcodegen', 'generate'], cwd=stage, stdout=log, stderr=subprocess.STDOUT, check=True)
    subprocess.run(['xcodebuild', '-project', 'AllYouNeedQuickLook.xcodeproj', '-scheme', 'AllYouNeedQuickLook',
                    '-destination', 'platform=macOS', '-derivedDataPath', str(run / 'DerivedData'), 'build'],
                   cwd=stage, stdout=log, stderr=subprocess.STDOUT, check=True)
app = run / 'DerivedData/Build/Products/Debug' / ('AllYouNeedQuickLook-' + suffix + '.app')
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
manifest = {'suffix': suffix, 'app': str(app), 'bundle_id': 'com.yohanpark.AllYouNeedQuickLook.test.' + suffix,
            'config_directory': str(Path.home() / 'Library/Application Support' / config_name),
            'source_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip(),
            'note': 'Working-tree sources staged for this build; source_commit is the base, not a claim of a clean tree.'}
(run / 'manifest.json').write_text(json.dumps(manifest, indent=2))
(runs / 'latest.json').write_text(json.dumps(manifest, indent=2))
print(json.dumps(manifest, indent=2), flush=True)
if not args.build_only:
    subprocess.run(['open', '-n', str(app)], check=True)
