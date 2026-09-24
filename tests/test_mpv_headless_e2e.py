#!/usr/bin/env python3
"""
End-to-End Headless MPV Runtime Integration Test Suite:
Launches real mpv instance with LuminaX loaded in headless mode (--vo=null --ao=null),
connects via JSON IPC socket, sends live commands, navigates menus, exercises pause/resume,
and validates that zero crashes, script errors, or uncaught exceptions occur.
"""

import os
import sys
import time
import json
import socket
import subprocess
import tempfile

def test_mpv_headless_e2e():
    print("=== Launching Headless MPV with LuminaX ===")
    
    tmp_dir = tempfile.mkdtemp(prefix="mpv_test_")
    socket_path = os.path.join(tmp_dir, "mpv_ipc.sock")
    script_entry = os.path.abspath("scripts/LuminaX/main.lua")
    
    cmd = [
        "mpv",
        "--idle=yes",
        "--vo=null",
        "--ao=null",
        f"--input-ipc-server={socket_path}",
        f"--scripts={script_entry}",
        "--msg-level=all=warn,LuminaX=debug"
    ]
    
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    
    # Wait for IPC socket to become ready
    sock = None
    deadline = time.time() + 5.0
    while time.time() < deadline:
        if os.path.exists(socket_path):
            try:
                sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                sock.connect(socket_path)
                sock.settimeout(3.0)
                break
            except Exception:
                time.sleep(0.05)
        else:
            time.sleep(0.05)
            
    assert sock is not None, "Failed to connect to mpv IPC socket within 5 seconds"
    print("  ✓ Connected to mpv IPC socket successfully")
    
    req_id = 0
    def send_cmd(cmd_list):
        nonlocal req_id
        req_id += 1
        payload = json.dumps({"command": cmd_list, "request_id": req_id}) + "\n"
        sock.sendall(payload.encode("utf-8"))
        
        # Read until our request_id is returned
        buf = ""
        while True:
            chunk = sock.recv(4096).decode("utf-8", errors="replace")
            if not chunk:
                break
            buf += chunk
            lines = buf.split("\n")
            for line in lines[:-1]:
                line = line.strip()
                if not line:
                    continue
                try:
                    data = json.loads(line)
                    if data.get("request_id") == req_id:
                        return data
                except Exception:
                    pass
            buf = lines[-1]
        return None

    # 1. Verify player version
    res = send_cmd(["get_property", "mpv-version"])
    assert res and res.get("error") == "success", f"Failed mpv-version: {res}"
    print(f"  ✓ MPV Version: {res.get('data')}")

    # 2. Test menu script-bindings
    menus = ["menu-playlist", "menu-chapters", "menu-audio", "menu-sub", "menu-tags"]
    for m in menus:
        res = send_cmd(["script-binding", m])
        assert res and res.get("error") == "success", f"Failed script-binding {m}: {res}"
        print(f"  ✓ Triggered script-binding: {m}")
        time.sleep(0.05)

    # 3. Test tag editor toggling
    res = send_cmd(["script-binding", "toggle-tags-menu"])
    assert res and res.get("error") == "success", f"Failed toggle-tags-menu: {res}"
    print("  ✓ Triggered toggle-tags-menu")

    # 4. Test loading synthetic file and pause/unpause lifecycle
    res = send_cmd(["loadfile", "null://", "replace"])
    assert res and res.get("error") == "success", f"Failed loadfile null://: {res}"
    print("  ✓ Loaded null:// test media")
    time.sleep(0.1)

    res = send_cmd(["set_property", "pause", True])
    assert res and res.get("error") == "success", f"Failed pause: {res}"
    print("  ✓ Set pause = true (screensaver timer armed)")
    time.sleep(0.1)

    res = send_cmd(["set_property", "pause", False])
    assert res and res.get("error") == "success", f"Failed unpause: {res}"
    print("  ✓ Set pause = false (playback resumed)")
    time.sleep(0.1)

    # 5. Send quit
    send_cmd(["quit"])
    sock.close()
    
    stdout, stderr = proc.communicate(timeout=5)
    assert proc.returncode == 0, f"mpv exited with non-zero status {proc.returncode}. Stderr: {stderr}"
    print("  ✓ mpv terminated cleanly with returncode 0")
    
    # Check stderr for any Lua fatal errors or crashes
    assert "error in script" not in stderr.lower(), f"Script error detected in stderr: {stderr}"
    assert "lua error" not in stderr.lower(), f"Lua error detected in stderr: {stderr}"
    print("  ✓ Stderr verified: zero Lua script errors")
    
    # Cleanup socket and directory
    try:
        if os.path.exists(socket_path):
            os.remove(socket_path)
        os.rmdir(tmp_dir)
    except Exception:
        pass

    print("\n========================================================")
    print("Headless MPV Integration Test: ALL CHECKS PASSED (100.0%)")
    print("========================================================")

if __name__ == "__main__":
    try:
        test_mpv_headless_e2e()
        sys.exit(0)
    except Exception as e:
        print(f"\n✗ Headless MPV Test Failed: {e}", file=sys.stderr)
        sys.exit(1)
