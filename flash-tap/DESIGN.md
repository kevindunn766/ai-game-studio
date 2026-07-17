# Flash Tap — Single-Target Reflex Game

## Concept
A pure reflex reaction game: one panel in a 3x3 grid lights up at a time —
tap it before it fades. Tapping any dark panel while another one is lit
costs a strike, and letting the lit panel fade untapped also costs a
strike. Speed ramps up with score. The only game in the studio built
around raw single-target reflex speed rather than timing-a-moving-element
(Pulse Tap) or aim/power (Target Throw).

## Aesthetic
- Flat 2D, dark background, 3x3 grid of dark gray panels that flash
  bright yellow when lit.

## Mechanics (LOCKED - do NOT add more)
1. Exactly one panel is lit at a time, for a duration that shrinks as
   score grows (1.0s down to a floor of 0.35s).
2. Tapping the lit panel scores a point and starts a short gap before the
   next panel lights.
3. Tapping a dark panel while another is lit, OR letting the lit panel's
   timer run out untapped, costs a strike. Taps during the gap (nothing
   lit) are ignored.
4. 3 strikes ends the run. Score = panels correctly tapped. High score
   via config.

## Non-negotiable constraints
- ONE scene only: `res://scenes/Main.tscn`
- One script: `main.gd`. No external art imports — `ColorRect`/`Label` only.
- `Color(r,g,b,a)` always 4 arguments.
- Godot 4.7 compatible, mobile portrait viewport (540x960).

## What NOT to do
- NO power-ups, NO menus, NO sounds/particles (yet), NO multiplayer, NO IAP.

## Verification
Project must open in Godot 4.7 without errors. Press F5, tap the lit
panel repeatedly as it speeds up.
