# Originality & IP Policy

Several prototypes in this studio take inspiration from well-known
hyper-casual mechanics (stack-tower games, helix-descent games, one-line
chop timers, tile-merge puzzles, knife-throw target games, ball-sort
puzzles, gravity-flip runners). This is normal and low-risk for the genre —
**game mechanics themselves are not copyrightable** under US law (only the
specific *expression* is: art, audio, text, code, and a distinctive
"trade dress" look). Hyper-casual as an industry runs on rapid mechanic
iteration; the studios that get into real trouble are the ones that copy
the *specific* branded art, sounds, or name of an existing title, not the
ones that build their own take on a familiar core loop.

## What we already do right (keep doing this)
1. **No external art/audio assets, ever.** Every visual in every project
   is built procedurally from primitives (`BoxMesh`, `Polygon2D`,
   `ColorRect`, `Line2D`) inside GDScript or `.tscn` files. Nothing is
   downloaded, traced, or copied from another game's assets. This alone
   eliminates the single biggest copyright risk vector.
2. **Original palettes, not copied ones.** Every game's color scheme is
   derived from the studio's own color-systems research (`COLOR_SYSTEM.md`)
   rather than matching a specific commercial game's iconic look (e.g. our
   merge game does not use 2048's exact tan/orange ramp; our helix game
   does not use Helix Jump's black-and-white checker scheme).
3. **No copied UI chrome, fonts-as-logos, or icons.** All UI is built from
   engine primitives and the default Godot font unless a project
   explicitly says otherwise.

## What to check before naming a new game
A name is fine if it's either **generic/descriptive** (the kind of name
many unrelated clones share — "Snake", "Merge Numbers", "Color Sort",
"Lemonade Stand") or **original coined phrasing** that doesn't reuse a
specific commercial title's distinctive word ("Spiral Drop" vs. "Helix
Jump"; "Target Throw" vs. "Knife Hit"; "Gravity Flip" vs. "Gravity Guy").

A name is a risk if it **shares the distinctive root word** of a specific
existing commercial title in a way a player would recognize as "that's
just [Title] renamed." That's a real, if minor, trademark-adjacent risk
(less about copyright, more about implying an association with another
company's brand) and it's cheap to avoid.

**Renamed for this reason:** `timber-tap` → **`chop-chain`**
(`chop-chain/`). The original name shared its root word with *Timberman*
(Digital Melody) closely enough to read as a direct reference. The
mechanic (alternate-side chop, branch avoidance, golden-log bonus) is
unchanged — only the name and on-screen title text changed, along with
its save-file key (`user://chopchain_highscore.cfg`).

## Reviewed and kept as-is
All other project names were checked against this standard and judged
either generic/descriptive or already distinct coined phrasing: Lemonade
Stand, Snake 3D, Stack Rush, Spiral Drop, Merge Numbers, Chroma Mix, Tilt
Tower, Loop It, Gravity Flip, Target Throw, Pulse Tap, Color Sort,
Flashlight Maze.

## Going forward
Apply this same three-part check (no external assets, original palette,
non-derivative name) to every new prototype before it's considered done.
