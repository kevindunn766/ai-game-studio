# Stack Rush — Minimal Hyper-Casual Game

## Aesthetic
- Flat-color low-poly blocks, palette cycles per layer (warm to cool).
- Dark-neutral background, soft ambient + directional light.
- Minimal UI: score as large Label3D floating above the tower.

## Mechanics (LOCKED - do NOT add more)
1. The block sweeps BOTH the X and Z axis at once (a Lissajous drift, Z
   riding a fixed frequency ratio on top of X) instead of alternating a
   single axis per layer — every drop has to line up in two dimensions.
2. One input (tap / click / space) drops the block onto the stack.
3. Overlap with the block below is clipped independently on each axis (X
   first, then Z against the already-clipped X extent); overhang on
   either axis is sliced off and falls away.
4. Zero overlap on EITHER axis = game over.
5. Camera rises smoothly as the tower grows.
6. Drop speed increases gradually with score, which also widens the gap
   between the X and Z sweep frequencies — the two axes drift further out
   of sync as a run goes on.
7. High score persisted via config file.

## Non-negotiable constraints
- ONE scene only: `res://scenes/Main.tscn`
- One script: `main.gd`. No external art imports.
- All meshes built procedurally (`BoxMesh` + `StandardMaterial3D`), never inline `.new()` in `.tscn`.
- `Color(r,g,b,a)` always 4 arguments.
- Godot 4.7 compatible, GL Compatibility renderer.

## What NOT to do
- NO power-ups, NO menus, NO sounds/particles (yet), NO multiplayer, NO IAP.

## Verification
Project must open in Godot 4.7 without errors. Press F5 (or tap/click/space) to play.
