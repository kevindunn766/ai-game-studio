# Anchor Drop — Rope-Cut Physics Puzzle

## Concept
An order-of-operations physics puzzle. A weight hangs from 3-5 ropes; cutting
a rope pulls the weight toward the average X of whichever ropes remain. The
puzzle is choosing WHICH rope to leave for last — it must be the one above
the green target zone, since cutting the final rope releases real gravity
and drops the weight straight down from wherever it was left hanging.

## Aesthetic
- Flat 2D, dark background, pink diamond weight, tan rope lines, dark
  "CUT" buttons above each rope, green target zone vs. red hazard zones
  on the ground.

## Mechanics (LOCKED - do NOT add more)
1. Each round has 3-5 ropes (grows with score), each anchored above a
   ground zone; exactly one zone is green (target), the rest are red.
2. While held, the weight lerps toward the average X of all uncut ropes.
3. Tapping a CUT button removes that rope. Cutting the last rope releases
   gravity and the weight falls straight down from its current position.
4. Landing in the green zone scores a point and starts a new round.
   Landing in a red zone costs a strike. 3 strikes ends the run.
5. Score = rounds survived. High score via config.
6. Novel element: Reinforced Rope. A rare thicker, amber-tinted rope
   takes two cuts instead of one — the first cut just cracks it (visible
   tint change) without severing, so it still counts as "remaining" for
   the weight's repositioning average.

## Non-negotiable constraints
- ONE scene only: `res://scenes/Main.tscn`
- One script: `main.gd`. No external art imports — `ColorRect`/`Polygon2D`/
  `Line2D`/`Label` only.
- `Color(r,g,b,a)` always 4 arguments.
- Godot 4.7 compatible, mobile portrait viewport (540x960).

## What NOT to do
- NO power-ups, NO menus, NO sounds/particles (yet), NO multiplayer, NO IAP.

## Verification
Project must open in Godot 4.7 without errors. Press F5, cut ropes in an
order that leaves the rope above the green zone for last.
