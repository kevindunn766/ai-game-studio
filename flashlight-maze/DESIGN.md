# Flashlight Maze — Fog-of-War Exploration

## Concept
A partial-information exploration puzzle. Unlike Snake 3D (fully visible
grid, continuous auto-move) or Loop It (fully visible dot grid), only a
small radius around the player is ever revealed here — and it stays
revealed once seen, so the challenge is genuinely about exploring and
remembering the maze's layout under time pressure, not reacting fast.

## Aesthetic
- Flat 2D top-down. Unexplored cells are solid black (fog). Explored
  floor is a light neutral gray; the exit cell is green once revealed.
  Walls are drawn as thin dark-slate bars between cells.

## Mechanics (LOCKED - do NOT add more)
1. A perfect maze (recursive-backtracker generation — guaranteed a single
   connected path between any two cells) is generated fresh each round.
2. Move with WASD, arrows, or a swipe — one cell per input, blocked by walls.
3. Only cells within a small radius of the player are ever revealed;
   revealed cells stay revealed (an "explored map," not a moving spotlight).
4. Structural twist: a roaming guard (always visible, even through fog)
   wanders the maze's corridors in real time on its own schedule. Unlike
   the timer, it's an active hazard — if it ever shares your cell (either
   of you moves into the other), that's a strike immediately, regardless
   of time remaining.
5. Reach the exit cell before the timer runs out to solve the maze: score
   +1, a new (occasionally larger) maze generates.
6. Running out of time, or getting caught by a guard, costs a strike;
   3 strikes ends the run.
6b. Grid size grows every 2 solves (7x7 up to 11x11); timer scales with cell
   count. High score persisted via config file.
7. Novel element: Second Guard. Once the maze grows past 9x9 (later in a
   run), a second guard also roams independently — doubling the
   real-time hazard pressure instead of just making the one guard faster.

## Non-negotiable constraints
- ONE scene only: `res://scenes/Main.tscn`
- One script: `main.gd`. No external art imports — `ColorRect`/`Polygon2D`/`Label` only.
- `Color(r,g,b,a)` always 4 arguments.
- Godot 4.7 compatible, mobile portrait viewport (540x960).

## What NOT to do
- NO power-ups, NO menus, NO sounds/particles (yet), NO multiplayer, NO IAP,
  NO diagonal movement.

## Verification
Project must open in Godot 4.7 without errors. Press F5 and navigate to
the green exit.
