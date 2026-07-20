# Tilt Tower — Real-Physics Balance Game

## Concept
The studio's first game built on an actual physics simulation
(`RigidBody2D` + `AnimatableBody2D`) instead of scripted/deterministic
logic. Blocks fall, rest, slide, and topple emergently — nothing about the
stacking behavior is scripted. Tilt the platform to keep them on.

## Aesthetic
- Flat 2D, dark neutral background so falling blocks (bright palette
  cycle) read clearly against it and the platform.
- Minimal UI: seconds-survived score, strike counter (3 blocks lost = out).

## Mechanics (LOCKED - do NOT add more)
1. Blocks spawn from the top at a shrinking interval and fall under gravity.
2. Tilt the platform with A/D, arrow keys, or the horizontal component of
   a click/touch-drag (clamped to +-35 degrees) to keep blocks from
   sliding off either edge.
3. Structural twist: the platform can also translate left/right — W/S or
   Up/Down keys, or the vertical component of the same drag gesture
   (clamped to +-160px either side of center) — so the player can
   physically reposition the platform under a falling block instead of
   only ever rotating to slide things toward center.
4. A block falling past the bottom of the screen costs a strike.
4b. 3 strikes and the run ends.
5. Score is seconds survived.
6. High score persisted via config file.
7. Novel element: Heavy Blocks. A rare falling block is bigger, denser
   (real `RigidBody2D` mass, not just a bigger sprite), and tinted dark
   slate — real emergent physics variety fitting this game's identity as
   the studio's real-physics sandbox.

## Non-negotiable constraints
- ONE scene only: `res://scenes/Main.tscn`
- One script: `main.gd`. No external art imports — `Polygon2D`/`Label` only.
- `Color(r,g,b,a)` always 4 arguments.
- Godot 4.7 compatible, mobile portrait viewport (540x960).
- Platform movement happens in `_physics_process` (required for
  `AnimatableBody2D`'s `sync_to_physics` to carry resting bodies correctly).

## What NOT to do
- NO power-ups, NO menus, NO sounds/particles (yet), NO multiplayer, NO IAP.

## Verification
Project must open in Godot 4.7 without errors. Press F5, tilt the platform
to keep blocks from falling off.
