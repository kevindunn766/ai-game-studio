# Godot Game Development Rules

## Project Overview
This is a Godot 4.7 project. All code must be valid GDScript for Godot 4.x. All .tscn files must be valid Godot 4 scene format.

## GDScript Rules
- Use GDScript ONLY. No C#, no C++.
- Use `class_name` for autoload singletons and player scripts.
- All signals and methods must match node names exactly (e.g. `$MyNode`, `%MyUniqueNode`).
- Use `@onready` for node references, NOT `onready var` (wrong in Godot 4).
- Use `extends Node` / `extends Node3D` / `extends Control` etc.
- Do NOT use `.connect("signal", self, "method")` - use `connect` with Callable: `node.connect("signal", Callable(self, "method"))`.

## Scene Rules
- Every scene must have a unique filename matching its root node type when possible.
- Use `Anchors/Pivot` style: Control nodes start with `%`命名 for unique paths.
- Physics layers: use collision layers/masks consistently.
- 3D scenes: use Node3D root, MeshInstance3D for visuals. NEVER use Sprite2D in 3D.
- All materials must use `StandardMaterial3D` or `ORMMaterial3D`.

## Color Rules - CRITICAL
GDScript Color() MUST include alpha, or Godot 4 throws "Expected 4 arguments for constructor":
```gdscript
# WRONG - will crash
var red = Color(1, 0, 0)
# RIGHT
var red = Color(1, 0, 0, 1)

# RIGHT
var half_transparent = Color(1, 0, 0, 0.5)
```

## Input Rules
- Define input map actions in `project.godot` under `[input]` section.
- Use `Input.get_vector("left", "right", "forward", "back")` for movement.
- Touch controls: use `_input(event)` for `InputEventScreenDrag` / `InputEventScreenTouch`.

## Testing Rules
1. After every script/scene change, load the project in Godot editor and press Play.
2. If an error appears in the Output panel, STOP and fix it before continuing.
3. Test touch input by simulating in editor (Project > Project Settings > Input Map > device simulation).
4. Test desktop input using keyboard arrows/WASD.

## Export Targets
- **Primary**: Android (APK via Godot export)
- **Secondary**: Windows desktop
- Export templates must be installed in Godot (Editor > Manage Export Templates).
- For Android, APK signing: use debug keystore for testing, release keystore for shipping.

## Project Structure
```
procedural-3d-godot/
├── project.godot
├── scenes/
│   ├── MainMenu.tscn
│   ├── Game.tscn
│   ├── PauseMenu.tscn
│   └── SettingsMenu.tscn
├── scripts/
│   ├── MainMenu.gd
│   ├── Game.gd
│   ├── Player.gd
│   ├── Platform.gd
│   ├── Obstacle.gd
│   ├── Collectible.gd
│   ├── SettingsManager.gd
│   └── InputManager.gd
└── assets/
    ├── audio/
    └── fonts/
```

## Game Design (3D Endless Runner)
- Player: simple 3D shape (capsule or box) moving forward automatically.
- Controls: left/right lane switching, jump, slide.
- Camera: follows behind player at a fixed height.
- Platforms: generated procedurally as player moves.
- Obstacles: spawned randomly, avoidable via lane switching.
- Collectibles: coins/gems for score.
- Score/High Score: saved to `user://scores.cfg` via ConfigFile.
- Polish: simple particle effects, sound effects, smooth camera follow.

## Anti-Patterns (DON'T DO THESE)
- Don't use `yield()` - use await with signal.
- Don't use `tree.get_root().get_node("/root/...")` - use `get_tree().root`.
- Don't rename files referenced in other files without updating references.
- Don't hardcode Android export paths - use `OS.get_executable_path()`.
- Don't use `print()` liberally - use `printerr()` for errors only in final build.

## CMake / Build Rules
- Godot godot does not use CMake.
- Use `scons` for engine compile, but we only use editor + export.
- Verify build with: `godot --version` returns 4.7.x

## AUTONOMY BOUNDARY
- This project MUST follow Godot 4.x engine rules exactly.
- If unclear about Godot API, check https://docs.godotengine.org/en/stable/.
- Never guess at API calls - if unsure, state assumption then proceed.
