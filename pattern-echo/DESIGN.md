# Pattern Echo — Memory Sequence Game

## Concept
A pure short-term-memory game (Simon-style): watch an escalating sequence
of panel flashes, then repeat it back by tapping in the same order. No
reflex or timing pressure exists during the watch phase at all — the only
game in the studio built around memorize-then-recall rather than reaction
speed or planning-under-a-timer.

## Aesthetic
- Flat 2D, dark background, 4 large jewel-toned panels in a 2x2 grid.
  Each panel brightens sharply when "lit" during playback.

## Mechanics (LOCKED - do NOT add more)
1. Each round appends one random panel to the sequence, then plays the
   whole sequence back (flash each panel in order).
2. After watching, tap the panels in the same order to repeat it.
3. A correct full repeat grows the sequence by one and starts the next
   round automatically.
4. A wrong tap costs a strike and replays the SAME sequence (it doesn't
   reset to length 1) — 3 strikes ends the run.
5. Score = longest sequence successfully repeated. High score via config.

## Non-negotiable constraints
- ONE scene only: `res://scenes/Main.tscn`
- One script: `main.gd`. No external art imports — `ColorRect`/`Label` only.
- `Color(r,g,b,a)` always 4 arguments.
- Godot 4.7 compatible, mobile portrait viewport (540x960).

## What NOT to do
- NO power-ups, NO menus, NO sounds/particles (yet), NO multiplayer, NO IAP.

## Verification
Project must open in Godot 4.7 without errors. Press F5, watch the
sequence, then tap it back.
