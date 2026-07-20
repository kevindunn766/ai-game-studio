# Pulse Tap — Visual Rhythm Timing Game

## Concept
A sound-free rhythm game: a ring shrinks continuously toward a fixed
target ring, and the player must tap the instant the two align. No other
game in the studio is built around "wait for the right moment in a
repeating cycle" — Spiral Drop is rotational alignment, Timber Tap and
Target Throw are single-shot reaction/timing, Gravity Flip is a binary
state. This one is a continuous, looping timing window.

## Aesthetic
- Flat 2D, dark background. Gold ring = fixed target. Blue ring = the
  shrinking pulse the player is tracking.

## Mechanics (LOCKED - do NOT add more)
1. Structural twist: TWO pulse rings (blue and green) shrink concurrently
   instead of one, started out of phase. Each respawns independently the
   instant IT resolves (hit or timeout) rather than the whole game
   resetting together, so the two rings drift in and out of sync on
   their own — tracking two independent timing windows at once.
2. Tap when either ring matches the target ring's radius (within a small
   tolerance) to score a point; that ring alone respawns and speeds up
   slightly (shared speed ramp, both rings get faster together).
3. Tapping when neither ring is in tolerance costs a strike, without
   disturbing either ring's progress.
4. Letting a ring reach zero without ever tapping it also costs a strike
   and respawns just that ring.
5. 3 strikes ends the run. Score = number of successful hits.
6. High score persisted via config file.
7. Novel element: Reverse Ring. A rare pulse grows outward from the
   center instead of shrinking inward from the edge — same
   tolerance-window resolution, but the player has to read a ring
   approaching from the opposite direction. Orthogonal to the
   double-score twist (a ring can be both at once).

## Non-negotiable constraints
- ONE scene only: `res://scenes/Main.tscn`
- One script: `main.gd`. No external art imports — `Line2D`/`Label` only.
- `Color(r,g,b,a)` always 4 arguments.
- Godot 4.7 compatible, mobile portrait viewport (540x960).

## What NOT to do
- NO power-ups, NO menus, NO sounds/particles (yet), NO multiplayer, NO IAP.

## Verification
Project must open in Godot 4.7 without errors. Press F5 and tap when the
rings align.
