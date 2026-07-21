"""Studio Bridge - live control bridge for a running Blender GUI.

Install: Edit > Preferences > Add-ons > Install... -> pick this file -> enable
         "Studio Bridge". Then in the 3D viewport N-panel there's a "Studio"
         tab with Start/Stop Server buttons (default 127.0.0.1:9876).

Protocol (newline-delimited JSON over TCP, localhost only):
  request : {"code": "<python>", "id": <int optional>}
  response: {"ok": true,  "stdout": "...", "result": "<repr>", "id": ...}
            {"ok": false, "error": "<traceback>", "id": ...}

Safety: sockets run on a background thread but NEVER touch bpy. Received code is
queued and executed by a bpy.app.timers callback on Blender's main thread, which
is the only thread-safe place to call the Blender API. localhost bind only.
"""
bl_info = {
    "name": "Studio Bridge",
    "author": "Arcanum Clash Studio",
    "version": (1, 0, 0),
    "blender": (4, 5, 0),
    "location": "View3D > N-panel > Studio",
    "description": "Local socket bridge for live scripted control of Blender.",
    "category": "Development",
}

import bpy
import socket
import threading
import json
import queue
import traceback
import io
import contextlib

HOST = "127.0.0.1"
PORT = 9876

# background thread -> main thread work items: (code:str, conn:socket, req_id)
_request_q: "queue.Queue" = queue.Queue()
_server_thread = None
_server_sock = None
_running = False


def _server_loop():
    global _server_sock, _running
    _server_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    _server_sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    _server_sock.bind((HOST, PORT))
    _server_sock.listen(4)
    _server_sock.settimeout(0.5)
    print(f"[StudioBridge] listening on {HOST}:{PORT}")
    while _running:
        try:
            conn, _addr = _server_sock.accept()
        except socket.timeout:
            continue
        except OSError:
            break
        threading.Thread(target=_handle_conn, args=(conn,), daemon=True).start()
    try:
        _server_sock.close()
    except OSError:
        pass
    print("[StudioBridge] server stopped")


def _handle_conn(conn):
    """Read newline-delimited JSON requests; enqueue for main-thread execution."""
    conn.settimeout(30.0)
    buf = b""
    try:
        while _running:
            chunk = conn.recv(65536)
            if not chunk:
                break
            buf += chunk
            while b"\n" in buf:
                line, buf = buf.split(b"\n", 1)
                if not line.strip():
                    continue
                try:
                    req = json.loads(line.decode("utf-8"))
                except Exception as e:
                    _send(conn, {"ok": False, "error": f"bad json: {e}"})
                    continue
                _request_q.put((req.get("code", ""), conn, req.get("id")))
    except OSError:
        pass
    # connection stays open until client closes; do not close here so the
    # main-thread reply can still be written.


def _send(conn, obj):
    try:
        conn.sendall((json.dumps(obj) + "\n").encode("utf-8"))
    except OSError:
        pass


def _drain_queue():
    """Main-thread timer: execute queued code against bpy, reply to caller."""
    while True:
        try:
            code, conn, req_id = _request_q.get_nowait()
        except queue.Empty:
            break
        out = io.StringIO()
        ns = {"bpy": bpy, "__name__": "__studio_bridge__"}
        try:
            with contextlib.redirect_stdout(out):
                # exec the block; if the last line is an expression, capture it
                result = _exec_capture(code, ns)
            _send(conn, {
                "ok": True,
                "stdout": out.getvalue(),
                "result": repr(result) if result is not None else "",
                "id": req_id,
            })
        except Exception:
            _send(conn, {
                "ok": False,
                "error": traceback.format_exc(),
                "stdout": out.getvalue(),
                "id": req_id,
            })
    return 0.05  # reschedule every 50ms while registered


def _exec_capture(code, ns):
    """Exec a block, returning the value of a trailing expression if present."""
    import ast
    tree = ast.parse(code, mode="exec")
    if tree.body and isinstance(tree.body[-1], ast.Expr):
        last = tree.body.pop()
        exec(compile(tree, "<bridge>", "exec"), ns)
        return eval(compile(ast.Expression(last.value), "<bridge>", "eval"), ns)
    exec(compile(tree, "<bridge>", "exec"), ns)
    return None


def start_server():
    global _server_thread, _running
    if _running:
        return False
    _running = True
    _server_thread = threading.Thread(target=_server_loop, daemon=True)
    _server_thread.start()
    if not bpy.app.timers.is_registered(_drain_queue):
        bpy.app.timers.register(_drain_queue)
    return True


def stop_server():
    global _running, _server_sock
    _running = False
    if bpy.app.timers.is_registered(_drain_queue):
        bpy.app.timers.unregister(_drain_queue)
    # nudge accept() out of its loop
    try:
        if _server_sock:
            _server_sock.close()
    except OSError:
        pass


class STUDIO_OT_start(bpy.types.Operator):
    bl_idname = "studio.bridge_start"
    bl_label = "Start Server"
    bl_description = "Start the Studio Bridge socket server"

    def execute(self, context):
        if start_server():
            self.report({'INFO'}, f"Studio Bridge on {HOST}:{PORT}")
        else:
            self.report({'WARNING'}, "Already running")
        return {'FINISHED'}


class STUDIO_OT_stop(bpy.types.Operator):
    bl_idname = "studio.bridge_stop"
    bl_label = "Stop Server"
    bl_description = "Stop the Studio Bridge socket server"

    def execute(self, context):
        stop_server()
        self.report({'INFO'}, "Studio Bridge stopped")
        return {'FINISHED'}


class STUDIO_PT_panel(bpy.types.Panel):
    bl_label = "Studio Bridge"
    bl_idname = "STUDIO_PT_bridge"
    bl_space_type = 'VIEW_3D'
    bl_region_type = 'UI'
    bl_category = "Studio"

    def draw(self, context):
        col = self.layout.column(align=True)
        col.label(text=f"{HOST}:{PORT}")
        col.label(text=("● running" if _running else "○ stopped"))
        col.operator("studio.bridge_start", icon='PLAY')
        col.operator("studio.bridge_stop", icon='PAUSE')


_classes = (STUDIO_OT_start, STUDIO_OT_stop, STUDIO_PT_panel)


def register():
    for c in _classes:
        bpy.utils.register_class(c)


def unregister():
    stop_server()
    for c in reversed(_classes):
        bpy.utils.unregister_class(c)


if __name__ == "__main__":
    register()
