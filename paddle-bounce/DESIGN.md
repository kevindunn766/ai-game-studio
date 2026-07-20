# Paddle Bounce — Breakout-Style Brick Clearer

## Concept
The studio's first game built around a controlled paddle deflecting a
bouncing ball. Distinct input grammar (continuous paddle positioning via
drag or keys) and distinct objective (clear a shrinking field of bricks
by ricochet) from every other game in the studio. Uses a deterministic
kinematic ball rather than `RigidBody2D` — Tilt Tower already owns "real
emergent physics" in this studio; here the exact reflection angle off the
paddle needs to be precise and testable, not emergent.

## Aesthetic
- Flat 2D, dark background. Bricks rotate through an even hue ramp by
  row (Studio Palette v1 style). Cyan paddle, gold ball.

## Mechanics (LOCKED - do NOT add more)
1. Move the paddle with a drag, or A/D/arrow keys.
2. Tap to launch the ball from the paddle; it flies up and bounces off
   walls, the paddle, and bricks.
3. Where the ball hits the paddle changes its outgoing angle (up to 60
   degrees off straight-up, based on offset from paddle center).
4. Hitting a brick destroys it (+1 score) and reflects the ball vertically.
5. The ball falling below the paddle costs a strike and reattaches the
   ball to the paddle for the next launch; 3 strikes ends the run.
6. Clearing every brick advances a round: a fresh, denser brick field
   generates and ball speed increases.
7. High score persisted via config file.

## Non-negotiable constraints
- ONE scene only: `res://scenes/Main.tscn`
- One script: `main.gd`. No external art imports — `ColorRect`/`Polygon2D`/`Label` only.
- `Color(r,g,b,a)` always 4 arguments.
- Godot 4.7 compatible, mobile portrait viewport (540x960).

## What NOT to do
- NO power-ups, NO menus, NO sounds/particles (yet), NO multiplayer, NO IAP.

## Verification
Project must open in Godot 4.7 without errors. Press F5, move the paddle,
and clear the bricks.
