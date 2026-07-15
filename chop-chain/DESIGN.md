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
6. A shrinking timer forces a tap each round; running out = game over.
7. Timer duration shortens slightly as score increases (difficulty ramp).
8. High score persisted via config file.

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
