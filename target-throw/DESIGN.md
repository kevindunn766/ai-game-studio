# Target Throw — Rotating-Target Precision Game

## Concept
A Knife Hit-style precision game. Unlike Spiral Drop (where the player
rotates the tower to line up a fall path), here the target spins entirely
on its own — the player only controls *when* to throw, not the rotation.
Timing, not alignment, is the skill.

## Aesthetic
- Flat 2D, dark background, a wood-brown circular target, steel-gray
  knives that stick and rotate along with it once thrown.

## Mechanics (LOCKED - do NOT add more)
1. The target spins continuously, speeding up every round.
2. Structural twist: a second, independently-rotating inner ring (usually
   spinning the opposite way) sits between the thrower and the target,
   with a fixed narrow gap. Every throw must ALSO clear that gap — lining
   up a throw means tracking two independently rotating references at
   once, not just avoiding your own past knives.
3. Tap / click / space throws a knife straight into the target from below.
4. If the inner ring blocks the throw, or the target spot already has a
   stuck knife (within a small angular tolerance), the throw fails —
   game over. Otherwise the knife sticks and rotates with the target.
5. Every 6 successful throws advances a round: knives clear, rotation
   speeds up.
6. Score = total knives successfully stuck. High score persisted via config.

## Non-negotiable constraints
- ONE scene only: `res://scenes/Main.tscn`
- One script: `main.gd`. No external art imports — `Polygon2D`/`Label` only.
- `Color(r,g,b,a)` always 4 arguments.
- Godot 4.7 compatible, mobile portrait viewport (540x960).
- Knife placement/collision uses `Node2D.to_local()` on a fixed world
  contact point rather than hand-derived rotation trig — see
  `COLOR_SYSTEM.md`-adjacent lesson in `DESIGN_BRIEF.md` about Spiral
  Drop's rotation-sign bug; this sidesteps that whole class of mistake by
  letting Godot's own transform system compute the angle.

## What NOT to do
- NO power-ups, NO menus, NO sounds/particles (yet), NO multiplayer, NO IAP.

## Verification
Project must open in Godot 4.7 without errors. Press F5 and tap to throw.
