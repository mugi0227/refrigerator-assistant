"""Prefer the iOS 26.2 ARM simulator used by the original image proof.

iOS 26.5 has intermittently stalled even the unmodified public control at the
first Apple image. Keep all test assertions; make the chosen runtime explicit.
"""
import json
import sys

devices = json.load(sys.stdin)['devices']
phones = [(tuple(int(n) for n in runtime.split('iOS-')[1].split('-')), d['name'], d['udid'])
          for runtime, items in devices.items() if 'iOS-' in runtime
          for d in items if d['name'].startswith('iPhone')]
choice = max([p for p in phones if p[0] == (26, 2)] or phones)
print(f'Test simulator: iOS {choice[0]}, {choice[1]}', file=sys.stderr)
print(choice[2])
