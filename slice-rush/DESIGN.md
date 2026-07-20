# Slice Rush — Drag-Slice Reflex Game

## Concept
Deferred back in the studio's round-1 research notes ("Fruit-slice...
good candidate, deferred to next batch") — now built. Shapes toss upward
from the bottom in a physical arc and fall back down; drag a continuous
stroke through them to slice. A free-form continuous drag through moving
targets, distinct from Loop It's drag-trace (fixed grid dots, in order)
and from every discrete-tap game in the studio.

## Aesthetic
- Flat 2D, dark background, shapes cycle through an even hue rotation
  (Studio Palette v1 style). Bombs are near-black, unmistakably different.
  The drag stroke leaves a short fading white trail.

## Mechanics (LOCKED - do NOT add more)
1. Shapes launch from the bottom in a random arc (gravity-affected
   projectile motion) and fall back down.
2. Dragging a stroke through a shape slices it: +1 score.
3. Slicing a bomb ends the run instantly.
4. Letting a normal shape fall off-screen unsliced costs a strike (bombs
   falling off untouched are fine — you're only punished for touching one).
5. 3 strikes ends the run. Spawn rate ramps up with score.
6. High score persisted via config file.

## Non-negotiable constraints
- ONE scene only: `res://scenes/Main.tscn`
- One script: `main.gd`. No external art imports — `Polygon2D`/`Line2D`/`Label` only.
- `Color(r,g,b,a)` always 4 arguments.
- Godot 4.7 compatible, mobile portrait viewport (540x960).

## What NOT to do
- NO power-ups, NO menus, NO sounds/particles (yet), NO multiplayer, NO IAP.

## Verification
Project must open in Godot 4.7 without errors. Press F5 and drag through
the shapes, avoiding bombs.
