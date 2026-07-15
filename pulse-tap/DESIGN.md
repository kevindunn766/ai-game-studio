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
1. The pulse ring shrinks steadily from off-screen-large toward zero.
2. Tap when it matches the target ring's radius (within a small tolerance)
   to score a point; the cycle immediately resets and speeds up slightly.
3. Tapping outside the tolerance window costs a strike (and the current
   cycle is spent — no second chance until it naturally resets at zero).
4. Letting a cycle reach zero without ever tapping also costs a strike.
5. 3 strikes ends the run. Score = number of successful hits.
6. High score persisted via config file.

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
