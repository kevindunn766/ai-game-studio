# Stack Rush — Minimal Hyper-Casual Game

## Aesthetic
- Flat-color low-poly blocks, palette cycles per layer (warm to cool).
- Dark-neutral background, soft ambient + directional light.
- Minimal UI: score as large Label3D floating above the tower.

## Mechanics (LOCKED - do NOT add more)
1. One block moves back and forth on the X or Z axis (alternating per layer).
2. One input (tap / click / space) drops the block onto the stack.
3. Overlap with the block below becomes the new block; overhang is sliced off and falls away.
4. Zero overlap = game over.
5. Camera rises smoothly as the tower grows.
6. Drop speed increases gradually with score.
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
