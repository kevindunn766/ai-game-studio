# Spiral Drop — Minimal Hyper-Casual Game

## Aesthetic
- Neon-on-dark low-poly. Each gate ring cycles through a warm/cool palette.
- Ball: warm glowing sphere, constant fall down the shaft's central radius.
- Minimal UI: score as a billboard Label3D, game-over overlay only.

## Mechanics (LOCKED - do NOT add more)
1. Ball falls continuously down a fixed vertical line.
2. Every gate ring has one gap (2 of 10 teeth removed); rest are solid.
3. Player rotates the whole tower (A/D, arrow keys, or click-drag / touch-drag)
   so the gap lines up with the ball before it reaches that ring's height.
4. Missing the gap = game over.
5. Passing a gate = +1 score; fall speed ramps up slightly with score.
6. Gates generate endlessly ahead of the ball.
7. High score persisted via config file.

## Non-negotiable constraints
- ONE scene only: `res://scenes/Main.tscn`
- One script: `main.gd`. No external art imports.
- All meshes built procedurally (`BoxMesh`, `SphereMesh` + `StandardMaterial3D`).
- `Color(r,g,b,a)` always 4 arguments.
- Godot 4.7 compatible, GL Compatibility renderer.

## What NOT to do
- NO power-ups, NO menus, NO sounds/particles (yet), NO multiplayer, NO IAP.

## Verification
Project must open in Godot 4.7 without errors. Press F5, hold A/D or drag to
rotate, and let the ball fall through the gaps.
