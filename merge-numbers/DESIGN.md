# Merge Numbers — Minimal Hyper-Casual Game

## Aesthetic
- Flat 2D, warm cream background, classic 2048-style tile palette
  (light tan at low values, ramping to orange/gold at high values).
- Minimal UI: score top, hint line bottom, game-over overlay only.

## Mechanics (LOCKED - do NOT add more)
1. 4x4 grid. Swipe (touch/mouse drag) or arrow keys slide every tile
   in that direction.
2. Colliding tiles of equal value merge into one tile of double value.
3. Each move that changes the board spawns one new tile (2, 90% / 4, 10%).
4. Structural twist: as score crosses fixed milestones (every 300 points,
   up to 3 at once), one empty cell permanently freezes — it never moves
   or merges and blocks tiles from sliding through it, splitting that
   row/column into independent segments on either side of it.
5. Game over when the board is full and no adjacent equal tiles remain
   (frozen cells never count as a valid merge with anything, including
   each other).
5. Score = running total of all merge values.
6. High score persisted via config file.

## Non-negotiable constraints
- ONE scene only: `res://scenes/Main.tscn`
- One script: `main.gd`. No external art imports — `ColorRect`/`Label` only.
- `Color(r,g,b,a)` always 4 arguments.
- Godot 4.7 compatible, mobile portrait viewport (540x960).

## What NOT to do
- NO power-ups, NO menus, NO sounds/particles (yet), NO multiplayer, NO IAP,
  NO tile-slide animation (instant snap is fine for the prototype).

## Verification
Project must open in Godot 4.7 without errors. Press F5 and swipe or use
arrow keys to merge tiles.
