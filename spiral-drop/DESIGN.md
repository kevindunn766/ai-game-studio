# Spiral Drop — Minimal Hyper-Casual Game

## Aesthetic
- Neon-on-dark low-poly. Each gate ring cycles through a warm/cool palette.
- Ball: warm glowing sphere, constant fall down the shaft's central radius.
- Minimal UI: score as a billboard Label3D, game-over overlay only.

## Mechanics (LOCKED - do NOT add more)
1. Ball falls continuously down a fixed vertical line.
2. Every gate ring has one gap (2 of 10 teeth removed); rest are solid.
3. Structural twist: some gates instead open TWO separate gaps, half the
   ring apart — a normal-width safe gap and a narrower amber-marked risk
   gap worth more points. The player has to commit to a lane before the
   gate arrives. Mutually exclusive with the golden-gate twist.
3b. Novel element: Mirror Gate. A rare violet gate that, once passed
    cleanly, inverts rotation controls (A/D and drag) for a few seconds —
    a disorientation twist, mutually exclusive with both the golden and
    dual-gap twists so every gate still reads as one clear thing.
4. Player rotates the whole tower (A/D, arrow keys, or click-drag / touch-drag)
   so a gap lines up with the ball before it reaches that ring's height.
5. Missing every gap on a gate = game over.
6. Passing through the safe gap = +1 score (golden gate: +2); passing
   through a risk gap = +2 score. Fall speed ramps up slightly with score.
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
