# Orb Burst — Aim-and-Launch Match Game

## Concept
An aim-and-launch match game: tap where you want to shoot and the orb
flies straight there (bouncing off side walls), snapping into the
nearest open slot in a staggered grid above. 3+ connected same-color
orbs pop; anything left disconnected from the ceiling afterward drops
away as a bonus. Distinct control (aim + commit a shot) and distinct
objective (clear a shrinking-headroom cluster before it reaches the
bottom) from every other game in the studio.

## Aesthetic
- Flat 2D, dark background. Orbs cycle through an even hue rotation
  (Studio Palette v1 style), 5 colors. Neutral gray launcher.

## Mechanics (LOCKED - do NOT add more)
1. Tap anywhere above the launcher to fire the loaded orb straight
   toward that point (clamped to an upward cone so it can't fire
   sideways or down); it bounces off the left/right walls in flight.
2. On hitting the grid (or the ceiling), the orb snaps into the nearest
   open slot in the staggered grid.
3. If 3 or more orbs of the same color end up connected, they pop
   (+10 score each). Any remaining orbs left disconnected from the
   ceiling afterward also drop away (+15 score each bonus).
4. Every 5 shots fired, the whole cluster shifts down one row and a new
   random row appears at the top — the grid gets more dangerous over time
   regardless of skill.
5. If any orb ever sits at or past the danger row near the bottom, the
   run ends.
6. High score persisted via config file.

## Non-negotiable constraints
- ONE scene only: `res://scenes/Main.tscn`
- One script: `main.gd`. No external art imports — `Polygon2D`/`Label` only.
- `Color(r,g,b,a)` always 4 arguments.
- Godot 4.7 compatible, mobile portrait viewport (540x960).

## What NOT to do
- NO power-ups, NO menus, NO sounds/particles (yet), NO multiplayer, NO IAP.

## Verification
Project must open in Godot 4.7 without errors. Press F5 and tap to shoot
orbs into the cluster.
