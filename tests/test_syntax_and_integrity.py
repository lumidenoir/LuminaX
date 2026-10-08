#!/usr/bin/env python3
"""
Syntax & Integrity Suite:
Validates syntax across all Lua and Python scripts in the codebase.
Ensures zero unparsed syntax errors or byte-compilation failures.
"""

import os
import sys
import subprocess
import py_compile

def main():
    root_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    os.chdir(root_dir)

    print("=" * 65)
    print("🔍 LuminaX Syntax & Structural Integrity Validator")
    print("=" * 65)

    lua_files = []
    for dirpath, _, filenames in os.walk(os.path.join(root_dir, "scripts")):
        for f in filenames:
            if f.endswith(".lua"):
                lua_files.append(os.path.join(dirpath, f))

    for dirpath, _, filenames in os.walk(os.path.join(root_dir, "tests")):
        for f in filenames:
            if f.endswith(".lua"):
                lua_files.append(os.path.join(dirpath, f))

    lua_files.sort()
    assert len(lua_files) > 0, "No Lua files discovered to validate!"

    print(f"▶ Validating {len(lua_files)} Lua scripts with luac -p...")
    for lfile in lua_files:
        rel_path = os.path.relpath(lfile, root_dir)
        res = subprocess.run(["luac", "-p", lfile], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        assert res.returncode == 0, f"Lua syntax error in {rel_path}:\n{res.stderr}"
        print(f"  ✓ Valid: {rel_path}")

    # Python byte compilation
    py_files = []
    for d in ["tools", "tests"]:
        pdir = os.path.join(root_dir, d)
        if os.path.isdir(pdir):
            for f in os.listdir(pdir):
                if f.endswith(".py"):
                    py_files.append(os.path.join(pdir, f))

    py_files.sort()
    assert len(py_files) > 0, "No Python files discovered to validate!"

    print(f"\n▶ Byte-compiling {len(py_files)} Python toolchain and test scripts...")
    for pfile in py_files:
        rel_path = os.path.relpath(pfile, root_dir)
        try:
            py_compile.compile(pfile, doraise=True)
            print(f"  ✓ Compiled: {rel_path}")
        except py_compile.PyCompileError as e:
            assert False, f"Python syntax error in {rel_path}:\n{e}"

    print(f"\n=== Syntax & Structural Integrity Suite PASSED ({len(lua_files) + len(py_files)} files verified) ===")

if __name__ == "__main__":
    main()
