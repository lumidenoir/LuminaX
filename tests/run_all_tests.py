#!/usr/bin/env python3
"""
Unified Test Runner for LuminaX Test Suite:
Discovers and executes all unit, flow, state machine, and headless mpv E2E tests.
Formats a clean summary report with timing and assertion tallies.
"""

import os
import sys
import time
import subprocess

SUITES = [
    {"name": "Clean Corpus Parsing", "cmd": ["lua", "tests/test_clean_corpus.lua"]},
    {"name": "Stream Guard & Subprocess Debounce", "cmd": ["lua", "tests/test_stream_guard_debouncing.lua"]},
    {"name": "UTF-8 Editor Stepping", "cmd": ["lua", "tests/test_utf8_editor.lua"]},
    {"name": "Screensaver Robustness & Failsafes", "cmd": ["lua", "tests/test_screensaver_robustness.lua"]},
    {"name": "Tag Editor & Watermark Flows", "cmd": ["lua", "tests/test_tag_editor_flows.lua"]},
    {"name": "Player Environment & Scaling Matrix", "cmd": ["lua", "tests/test_player_environment_matrix.lua"]},
    {"name": "Headless MPV Live Runtime E2E", "cmd": ["python3", "tests/test_mpv_headless_e2e.py"]},
]

def main():
    root_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    os.chdir(root_dir)

    print("=" * 70)
    print("🌟 LuminaX Automated Test Suite Orchestrator")
    print(f"Directory: {root_dir}")
    print(f"Suites to run: {len(SUITES)}")
    print("=" * 70)

    total_start = time.time()
    results = []

    for suite in SUITES:
        name = suite["name"]
        cmd = suite["cmd"]
        print(f"\n▶ Running: {name} ({' '.join(cmd)})")
        start = time.time()
        proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        dur = time.time() - start

        lines = proc.stdout.strip().split("\n")
        pass_lines = [l for l in lines if "PASS" in l or "✓" in l]
        fail_lines = [l for l in lines if "FAIL" in l or "✗" in l]

        success = (proc.returncode == 0) and (len(fail_lines) == 0)
        results.append({
            "name": name,
            "success": success,
            "duration": dur,
            "output": proc.stdout,
            "pass_count": len(pass_lines),
            "fail_count": len(fail_lines)
        })

        if success:
            print(f"  ✓ SUCCESS in {dur:.2f}s ({len(pass_lines)} assertions passed)")
        else:
            print(f"  ✗ FAILED in {dur:.2f}s ({len(fail_lines)} failures)")
            print("-" * 50)
            print(proc.stdout)
            print("-" * 50)

    total_duration = time.time() - total_start

    print("\n" + "=" * 70)
    print("📊 Test Execution Summary")
    print("=" * 70)

    all_passed = True
    total_assertions = 0

    for r in results:
        status = "✓ PASS" if r["success"] else "✗ FAIL"
        total_assertions += r["pass_count"]
        if not r["success"]:
            all_passed = False
        print(f"  [{status}] {r['name']:<42} ({r['duration']:.2f}s, {r['pass_count']} assertions)")

    print("-" * 70)
    print(f"Total Suites:     {len(results)} | Passed: {sum(1 for r in results if r['success'])} | Failed: {sum(1 for r in results if not r['success'])}")
    print(f"Total Assertions: {total_assertions} passed")
    print(f"Total Time:       {total_duration:.2f}s")
    print("=" * 70)

    if all_passed:
        print("\n🎉 ALL TEST SUITES PASSED FLAWLESSLY!\n")
        sys.exit(0)
    else:
        print("\n❌ TEST SUITE FAILURES OCCURRED.\n")
        sys.exit(1)

if __name__ == "__main__":
    main()
