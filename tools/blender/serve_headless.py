"""Run the Studio Bridge in a headless Blender for testing (no GUI event loop,
so we pump the main-thread queue manually). In the real GUI, bpy.app.timers
does this automatically and you don't need this file.

Run: blender --background --python serve_headless.py -- --seconds 25
"""
import sys
import os
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "addon"))
import studio_bridge as sb

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
seconds = 25
if "--seconds" in argv:
    seconds = int(argv[argv.index("--seconds") + 1])

sb.start_server()
print(f"[serve_headless] pumping queue for {seconds}s")
end = time.time() + seconds
while time.time() < end:
    sb._drain_queue()   # main-thread execution of any queued requests
    time.sleep(0.03)
sb.stop_server()
print("[serve_headless] exit")
