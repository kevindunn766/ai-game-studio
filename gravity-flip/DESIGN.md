# Gravity Flip — One-Button Dodge Runner

## Concept
A one-button endless runner (Gravity Guy / Impossible Game genre) — the
last of the four "completely new" prototypes, and the studio's first game
using a landscape viewport and an instant-single-hit fail state, both
deliberately different from the portrait/3-strike pattern used by the
other new prototypes.

## Aesthetic
- Flat 2D, dark corridor, ceiling/floor bars marking the play space.
- Player: small teal square. Obstacles: red-orange blocks (danger-accent,
  per `COLOR_SYSTEM.md`) attached to the ceiling or floor.

## Mechanics (LOCKED - do NOT add more)
1. The world auto-scrolls; the player sits at a fixed screen X.
2. Tap / Space flips which way gravity pulls the player (with an instant
   velocity kick in the new direction for a snappy, arcade feel).
3. Each obstacle blocks either the upper half or lower half of the
   corridor — be on the open half when it reaches the player.
4. One hit ends the run (the genre's defining fail state).
5. Scroll speed ramps up and obstacle spacing tightens as score climbs.
6. Score = obstacles successfully passed. High score persisted via config.

## Non-negotiable constraints
- ONE scene only: `res://scenes/Main.tscn`
- One script: `main.gd`. No external art imports — `ColorRect`/`Label` only.
- `Color(r,g,b,a)` always 4 arguments.
- Godot 4.7 compatible, landscape viewport (960x540).
- Player/gravity simulation is custom kinematic code (not `RigidBody2D`) —
  precise, deterministic dodge-timing needs exact control, unlike Tilt
  Tower's deliberately emergent physics.

## What NOT to do
- NO power-ups, NO menus, NO sounds/particles (yet), NO multiplayer, NO IAP.

## Verification
Project must open in Godot 4.7 without errors. Press F5 and tap/space to
flip gravity through the gaps.
