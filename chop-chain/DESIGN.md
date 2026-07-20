# Chop Chain — Minimal Hyper-Casual Game

## Aesthetic
- Flat 2D, bright sky background, green ground strip.
- Trunk: alternating brown ColorRect segments. Branches: green rects
  protruding left/right. Player: a simple red block beside the trunk.
- Minimal UI: score top-left, shrinking timer bar, game-over overlay only.

## Mechanics (LOCKED - do NOT add more)
1. Tap left half of screen / A / Left-Arrow to chop from the left.
2. Tap right half of screen / D / Right-Arrow to chop from the right.
3. Each trunk segment has a branch on at most one side (or none).
4. Tapping the side with the branch on the current bottom segment = game over.
5. Tapping the clear side chops the segment away and moves the player there.
6. Structural twist: some hazardous segments come back reinforced
   (visibly tinted, with a crack line after the first hit). Tapping the
   branch side still kills instantly, but the safe side has to be tapped
   TWICE — a clean hit only cracks it — before it actually falls away.
7. A shrinking timer forces a tap each round; running out = game over.
7b. Timer duration shortens slightly as score increases (difficulty ramp).
8. High score persisted via config file.
9. Novel element: Combo Multiplier. Chaining full clears in a row builds
   a score multiplier (every 3 clears, up to x4); stumbling on a
   reinforced segment's first hit breaks the streak back to x1 — added
   stakes on top of the reinforced-segment mechanic.

## Non-negotiable constraints
- ONE scene only: `res://scenes/Main.tscn`
- One script: `main.gd`. No external art imports — `ColorRect` only.
- `Color(r,g,b,a)` always 4 arguments.
- Godot 4.7 compatible, mobile portrait viewport (540x960).

## What NOT to do
- NO power-ups, NO menus, NO sounds/particles (yet), NO multiplayer, NO IAP.

## Verification
Project must open in Godot 4.7 without errors. Press F5 and tap left/right
(or A/D, arrow keys) to chop.
