#!/usr/bin/env python3
"""Run every FurryOS desktop-visual verification script and summarise.

Usage:  python3 .tools/verify-all.py

Runs, in order:
  1. verify-colors.py      — FurryOS.colors format + brand-palette compliance
  2. verify-wallpaper.py   — wallpaper gradient + paw recognisability
  3. verify-consistency.py — colour scheme / /etc/skel / theme agreement,
                             click-effect merge, WCAG contrast claims

Exit code 0 only if all three pass.
"""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPTS = [
    ("colour scheme format + palette", "verify-colors.py"),
    ("wallpaper gradient + paw mark", "verify-wallpaper.py"),
    ("theme / skel / contrast agreement", "verify-consistency.py"),
]


def main():
    results = []
    for label, script in SCRIPTS:
        path = os.path.join(HERE, script)
        print("=" * 72)
        print("### %s  (%s)" % (label, script))
        print("=" * 72)
        res = subprocess.run([sys.executable, path], capture_output=True, text=True)
        sys.stdout.write(res.stdout)
        if res.stderr:
            sys.stderr.write(res.stderr)
        results.append((label, res.returncode))
        print()

    print("=" * 72)
    print("SUMMARY")
    print("=" * 72)
    failed = 0
    for label, code in results:
        print("  %-40s %s" % (label, "PASS" if code == 0 else "FAIL"))
        if code != 0:
            failed += 1
    print()
    if failed:
        print("%d of %d checks FAILED" % (failed, len(results)))
        return 1
    print("All %d checks passed." % len(results))
    return 0


if __name__ == "__main__":
    sys.exit(main())
