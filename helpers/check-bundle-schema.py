#!/usr/bin/env python3
"""Assert that an app carries the matching editor schema before distribution."""
import json
from pathlib import Path
import plistlib
import sys

app = Path(sys.argv[1])
with (app / 'Contents/Info.plist').open('rb') as source:
    info = plistlib.load(source)
development = info['CFBundleIdentifier'] == 'com.maxmeis.hypermug.dev'
name = 'hypermug-dev.schema.json' if development else 'hypermug.schema.json'
resource = app / 'Contents/Resources' / name
schema = json.loads(resource.read_text())
assert schema['title'] == info['CFBundleName'] + ' configuration', 'Schema belongs to another app variant'
deadline = schema['properties']['shellTimeoutSeconds']
assert deadline['type'] == 'number' and deadline['default'] == 10, 'Missing default shell deadline'
assert deadline['minimum'] == 1 and deadline['maximum'] == 300, 'Missing deadline bounds'
assert schema['additionalProperties'] is False, 'Unknown settings must fail validation'
assert schema['properties']['autoUpdate']['type'] == 'boolean'
assert info['HyperMugReleaseChannel'] in ('local', 'stable', 'canary')
assert sorted(p.name for p in resource.parent.glob('*.schema.json')) == [name]
print(f'Bundled schema: {resource}')
