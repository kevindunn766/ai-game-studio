# Loop It — Single-Stroke Connect Puzzle

## Concept
A genuinely different genre for this studio: a drag-to-trace planning
puzzle (in the spirit of "one-line" / Hamiltonian-path puzzles) instead of
a reaction or timing game. No other prototype in the studio uses
continuous-drag path tracing as its core input.

## Aesthetic
- Flat 2D, warm paper background, dots in a neutral slate color that turn
  blue once visited; the drawn path is a single thick blue Line2D stroke.
- Minimal UI: score, strike counter, shrinking timer bar.

## Mechanics (LOCKED - do NOT add more)
1. Drag from any dot; the line extends to the next dot only if it's
   directly up/down/left/right of the current end and hasn't been visited.
2. Visit every PLAYABLE dot on the grid in one continuous stroke to win.
3. Structural twist: some rounds wall off a chunk of the grid (rust-colored
   square markers, not draggable/traceable) instead of using the full
   rectangle. Solvability is guaranteed by construction: a full zigzag
   Hamiltonian ordering of the grid is generated, then a random-length
   suffix of it is walled off — the remaining prefix is always itself
   traceable in one line.
4. Releasing before the playable dots are complete clears the current stroke (no
   penalty beyond the lost time) — the round timer keeps running.
4. Letting the timer reach zero costs a strike; 3 strikes ends the run.
5. Grid grows (3x3 up to 6x6) as score climbs; timer scales with dot count.
6. High score persisted via config file.

## Non-negotiable constraints
- ONE scene only: `res://scenes/Main.tscn`
- One script: `main.gd`. No external art imports — `Polygon2D`/`Line2D`/`Label` only.
- `Color(r,g,b,a)` always 4 arguments.
- Godot 4.7 compatible, mobile portrait viewport (540x960).

## What NOT to do
- NO power-ups, NO menus, NO sounds/particles (yet), NO multiplayer, NO IAP,
  NO diagonal moves.

## Verification
Project must open in Godot 4.7 without errors. Press F5 and drag through
every dot in one stroke.
