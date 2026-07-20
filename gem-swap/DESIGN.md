# Gem Swap — Tap-Swap Match-3 Puzzle

## Concept
A classic match-3: tap a gem, tap an adjacent gem to swap them. The swap
only sticks if it lines up 3+ of a color somewhere on the board;
otherwise it silently reverts. A tap-swap-adjacent input grammar distinct
from every other grid game in the studio — Merge Numbers slides the
whole board in one direction, Color Sort pours between tubes, Number
Slide only moves a tile into the single empty slot. This is the only
game where you pick exactly two cells and trade their contents.

## Aesthetic
- Flat 2D, dark background, 7x7 grid. Gems cycle through an even hue
  rotation (Studio Palette v1 style), 5 colors. A selected gem flashes
  near-white.

## Mechanics (LOCKED - do NOT add more)
1. Tap a gem to select it, tap an adjacent gem to attempt a swap.
2. The swap only commits if it creates a run of 3+ same-colored gems
   (row or column) somewhere on the board; otherwise it reverts with no
   penalty. A committed swap costs 1 move from a shared budget and
   refills a few moves back as a bonus.
3. Matched gems clear (+10 score each); gems above fall to fill the gap
   and new random gems spawn at the top. Cascades (a fall creating a new
   match) keep clearing and scoring, but don't cost or refill moves.
4. Running out of moves ends the run.
5. High score persisted via config file.

## Non-negotiable constraints
- ONE scene only: `res://scenes/Main.tscn`
- One script: `main.gd`. No external art imports — `ColorRect`/`Label` only.
- `Color(r,g,b,a)` always 4 arguments.
- Godot 4.7 compatible, mobile portrait viewport (540x960).

## What NOT to do
- NO power-ups, NO menus, NO sounds/particles (yet), NO multiplayer, NO IAP,
  NO formal deadlock (no-legal-move) detection/board reshuffle — boards
  are generated to avoid any match already present, the standard approach
  for this genre, but a full "is there still a legal move anywhere"
  solver isn't implemented. Same documented scope boundary as Color
  Sort's unproven puzzle solvability; rare in practice on a 7x7/5-color
  board.

## Verification
Project must open in Godot 4.7 without errors. Press F5 and tap-swap
adjacent gems to make matches.
