"""Client for the Studio Bridge addon. I use this to drive a running Blender.

Usage:
  python bridge_client.py -c "bpy.ops.mesh.primitive_cube_add()"
  python bridge_client.py -f some_script.py
  echo "len(bpy.data.objects)" | python bridge_client.py
"""
import socket
import json
import sys
import argparse

HOST = "127.0.0.1"
PORT = 9876


def send_code(code, host=HOST, port=PORT, timeout=30.0):
    s = socket.create_connection((host, port), timeout=timeout)
    try:
        s.sendall((json.dumps({"code": code}) + "\n").encode("utf-8"))
        buf = b""
        s.settimeout(timeout)
        while b"\n" not in buf:
            chunk = s.recv(65536)
            if not chunk:
                break
            buf += chunk
        line = buf.split(b"\n", 1)[0]
        return json.loads(line.decode("utf-8"))
    finally:
        s.close()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-c", "--code", help="inline python to run in Blender")
    ap.add_argument("-f", "--file", help="path to a .py file to run in Blender")
    ap.add_argument("--host", default=HOST)
    ap.add_argument("--port", type=int, default=PORT)
    args = ap.parse_args()

    if args.file:
        with open(args.file, "r", encoding="utf-8") as fh:
            code = fh.read()
    elif args.code:
        code = args.code
    else:
        code = sys.stdin.read()

    resp = send_code(code, args.host, args.port)
    if resp.get("stdout"):
        sys.stdout.write(resp["stdout"])
        if not resp["stdout"].endswith("\n"):
            sys.stdout.write("\n")
    if resp.get("ok"):
        if resp.get("result"):
            print("=>", resp["result"])
        sys.exit(0)
    else:
        sys.stderr.write(resp.get("error", "unknown error") + "\n")
        sys.exit(1)


if __name__ == "__main__":
    main()
