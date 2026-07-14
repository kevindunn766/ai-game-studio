# Color Systems Research — Studio Palette Method

Researched at the user's request: review Color-aid and other well-established
color systems, then use the findings to redesign the palettes of every game
the studio has actually built so far.

## 1. Color-aid / Josef Albers — *Interaction of Color*
Color-aid Corp has made colored paper since 1948 (originally photo
backdrops); Josef Albers adopted it as the paper stock for his color classes
at Yale, and it's been the standard teaching material for *Interaction of
Color* (1963) ever since. The set grew from its original run to 220/314
standardized colors in 1990. ([coloraid.com](https://coloraid.com/), [Yale University Press](https://yalebooks.yale.edu/book/9780300179354/interaction-of-color/))

Albers' central claim, and the one most worth stealing: **color is
relational, not absolute.** A color's perceived hue, value, and even
identity change depending on what surrounds it ("simultaneous contrast") —
the same gray reads warm next to blue and cool next to orange. He taught
almost entirely through constrained exercises: make one color look like two,
make two colors look like one, using only 3-4 paper swatches at a time. He
also directly critiqued rigid systems (he presented Munsell, Ostwald, and
Faber Birren to students specifically to show their limits for real design
work, where relationships matter more than any single color's "correct"
placement in a chart). ([Albers Foundation](https://www.albersfoundation.org/alberses/teaching/interaction-of-color), [Medium — Kira Straub](https://medium.com/@straubkira/interaction-of-color-the-importance-of-joseph-albers-to-color-theory-575b6d3fad10))

**Takeaway for us:** never pick a color in isolation (a hex value in a
palette generator). Judge it against the actual background/lighting it will
render on in Godot, and keep each game's palette *small* — a handful of
colors doing clear relational work beats a big "nice looking" swatch set.

## 2. Munsell Color System
Describes any color as **Hue, Value, Chroma** (`H V/C`) — three
independent, perceptually-spaced dimensions: hue (red/yellow/green/etc.),
value (lightness, 0=black to 10=white), chroma (distance from neutral gray).
It's a *perceptual* system (built from human matching experiments), not a
mixing/ink system. ([Britannica](https://www.britannica.com/science/Munsell-color-system), [munsell.com](https://munsell.com/color-blog/a-grammar-of-color-definition-hue-value-chroma/))

**Takeaway:** stop picking colors by eyeballing RGB sliders. Fix a target
value and chroma for a *role* (e.g., "background = value 2, low chroma";
"danger accent = value 5, high chroma") and only vary hue between games.
This is exactly what HSV lets us do directly in GDScript
(`Color.from_hsv(hue, chroma, value, alpha)`).

## 3. NCS — Natural Color System
Sweden's standard, built around six elementary percepts (white, black,
yellow, red, blue, green) rather than physical mixing; a color is notated as
blackness + chromaticness + hue. It's the default in European architecture
and interiors. Functionally similar goal to Munsell (perceptual, not
mixing-based) but organized around how strongly a color resembles pure white
vs. pure black vs. a saturated hue — a useful third lens on the same idea:
**describe colors by role/resemblance, not by recipe.** ([Ideal Work](https://www.idealwork.com/lets-discover-the-natural-color-system/), [ColorArchive](https://colorarchive.me/notes/sep-2027-color-naming-systems/))

## 4. Pantone
A physical ink-matching standard (15 base pigments mixed to spec) —
optimized for print/manufacturing reproducibility, not perceptual harmony.
Not directly useful for on-screen game palettes, but the *discipline* it
enforces — a brand locks a small numbered set of colors and never deviates —
is worth borrowing: each game should have one locked, numbered palette, not
an ad hoc color picked per-object as we add features. ([ColorArchive](https://colorarchive.me/notes/sep-2027-color-naming-systems/))

## 5. Itten's 12-hue wheel & Seven Contrasts
Johannes Itten (Bauhaus) systematized how colors interact into seven named
contrasts: hue, complementary, light-dark (value), warm-cool (temperature),
simultaneous, saturation, and **extension** (proportion of area). ([worqx.com](https://www.worqx.com/color/itten.htm), [Painting and Artists](https://www.paintingandartists.com/7-colors-contrast-by-johannes-itten))

Two of these map directly onto game UI/UX problems we already have:
- **Contrast of extension** — the color covering the *most screen area*
  should be the least saturated; save high chroma for small, important
  elements. A hyper-casual game where the background is as saturated as the
  hazard reads as visual noise and buries the thing the player must react to.
- **Contrast of saturation/warm-cool as a gameplay signal** — if "safe" and
  "danger" don't get a clearly different hue *and* saturation, players will
  misread them under time pressure. (This turned out to be a real bug — see
  Timber Tap below.)

## House method we're adopting
1. **Pick value/chroma by role, hue by game.** Every game uses the same
   value+chroma targets for the same role (background, neutral surface,
   player/agent accent, reward accent, danger accent) so contrast is
   consistent across the whole studio; only the hue rotates per game for
   variety. Built with `Color.from_hsv(h, s, v, 1.0)` so the numbers are
   explicit and reviewable, not guessed RGB triples.
2. **Danger = warm + saturated, always.** Never reuse a "safe/positive" hue
   family (green) for a hazard. Reserve red/amber/orange for anything that
   ends the run.
3. **Small locked sets.** Each game keeps one named palette block at the top
   of its script (Albers' "3-4 swatches" discipline) instead of scattering
   `Color(...)` literals through the file.
4. **Background always loses the saturation contest.** Whatever covers the
   most pixels gets the lowest chroma so the small, important, high-chroma
   shapes (the ball, the block, the branch, the tile) stay legible
   (Itten's contrast of extension).
5. **Emission for gameplay-critical shapes**, not just décor — a value/hue
   difference on paper can wash out under one directional light; emission
   makes the contrast robust to lighting angle. This is what actually fixes
   snake-3d's long-standing "wall barely visible against floor" bug (see
   below) — the pastel walls had good value contrast in theory but no
   emission, so directional lighting was flattening the difference.

## Studio Palette v1 (concrete roles)
All values as `Color.from_hsv(hue_deg/360.0, S, V, 1.0)` — hue in degrees
for readability here, S/V fixed per role, hue chosen per game below.

| Role | S (chroma) | V (value) | Notes |
|---|---|---|---|
| `bg-deep` | 0.35–0.45 | 0.08–0.12 | Darkest surface, biggest area — must stay low-chroma |
| `bg-mid` | 0.3–0.4 | 0.16–0.22 | Secondary surface (ground, grid lines) |
| `neutral-surface` | 0.05–0.1 | 0.85–0.92 | Base/UI neutral — Albers' "gray" for others to react against |
| `accent-primary` | 0.65–0.8 | 0.75–0.9 | The thing the player controls |
| `accent-reward` | 0.6–0.75 | 0.75–0.85 | Score/positive — hue ≥90° from primary and danger |
| `accent-danger` | 0.75–0.9 | 0.55–0.65 | Hazard/lose-condition — always warm (0–45° or 340–360°) |
| `outline` | 0 | 0.03 | Near-black outline/text, unchanged across all games |

## Per-game palette assignments
| Game | Key hue (primary) | What changed |
|---|---|---|
| **stack-rush** | Rotates fully around the wheel per layer | Was 7 hand-picked RGB triples of inconsistent S/V (some looked neon, some muddy). Replaced with evenly-stepped `Color.from_hsv(i/7.0, 0.62, 0.88)` so every layer reads at the same brightness — a tower that gets visually *noisier* with height, never dimmer. |
| **spiral-drop** | Cool blues/violets for gates, warm gold for the ball | Gate teeth were as saturated as the ball, so the ball (the thing you track) didn't stand out. Dropped gate chroma to ~0.5 and kept the ball at ~0.85 — Itten's contrast-of-saturation used as a gameplay legibility cue. |
| **timber-tap** | Brown trunk, warm-amber branch (was green), cool blue player | **Real bug found:** the branch — a hazard — was green, the universal "safe/go" color, fighting the player's split-second read. Recolored the branch to amber/orange (danger family) and gave the player a blue that shares no hue family with trunk, branch, or ground, so all four read as distinct at a glance. |
| **merge-numbers** | Warm cream → gold ramp (kept the concept) | The original ramp was a hand-copied 2048 palette with uneven jumps. Rebuilt as a controlled Munsell-style ramp: value and chroma both climb smoothly with tile power, hue drifts red-ward at the high end, so the progression *reads* as "getting more intense" rather than jumping between arbitrary swatches. |
| **snake-3d** | Green snake (unchanged), neon pastel obstacles | **Fixes the long-standing "walls invisible against floor" bug** in `DESIGN_BRIEF.md`. Floor stays `bg-deep`; obstacles now get emission added (they had none) plus a wider, locked value gap — contrast that survives any lighting angle instead of relying on unlit albedo alone. |
| **lemonade-stand-godot** | Yellow background (unchanged, already high-contrast per design brief) | **Fix:** labels had no explicit font color, so they were inheriting Godot's default (near-white) over a bright yellow background — low value contrast, borderline unreadable. Set an explicit dark, near-black font color + light outline on all labels. |

`procedural-3d-godot` (currently broken, does not run) and `arcadia-clash`
(design doc + asset folders only, no implemented scene yet) are excluded —
there's no running render to apply a palette to yet.
