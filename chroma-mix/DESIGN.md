# Chroma Mix — Color-Theory Puzzle

## Concept
Grown directly out of the studio's color-systems research
(`COLOR_SYSTEM.md`): a hyper-casual puzzle built on Itten's actual RYB
pigment wheel instead of an arbitrary matching mechanic. Primary paints
(Red/Yellow/Blue) combine into the real secondaries (Orange/Green/Purple),
and mixing all three gives a neutral brown — true pigment-mixing lore, not
an invented rule.

## Aesthetic
- Flat 2D, warm neutral paper background so the paints read clearly.
- Target swatch + live "your mix" preview well, both large flat color
  blocks — no gradients, no ambiguity about what's being compared.
- Minimal UI: score, strike counter, shrinking timer bar.

## Mechanics (LOCKED - do NOT add more)
1. Tap 1-3 of the Red/Yellow/Blue paint swatches to select them (toggle).
2. Tap MIX to submit. The mix table is fixed:
   R=Red, Y=Yellow, B=Blue, R+Y=Orange, Y+B=Green, B+R=Purple, R+Y+B=Brown.
3. Correct match = +1 score, new target, timer resets.
4. Structural twist: a progressive unlock curve. A run starts with only
   the three primaries as possible targets; secondaries unlock at a score
   milestone, and brown (the hardest read) unlocks after that. The pool
   of things you're asked to mix actually grows over a run.
4b. Novel element: Fading Target. A rare round hides the target's name
    and starts its swatch washed out, sharpening to full clarity over
    just over a second — reacting instantly means guessing at a muddy
    hue, waiting costs round time. Mutually exclusive with the wildcard
    round.
5. Wrong match or letting the timer run out = lose a strike.
5. 3 strikes and the run ends.
6. Round timer shortens slightly as score climbs.
7. High score persisted via config file.

## Non-negotiable constraints
- ONE scene only: `res://scenes/Main.tscn`
- One script: `main.gd`. No external art imports — `ColorRect`/`Label` only.
- `Color(r,g,b,a)` always 4 arguments.
- Godot 4.7 compatible, mobile portrait viewport (540x960).

## What NOT to do
- NO power-ups, NO menus, NO sounds/particles (yet), NO multiplayer, NO IAP.

## Verification
Project must open in Godot 4.7 without errors. Press F5, tap the paint
swatches to mix, then tap MIX to submit.
