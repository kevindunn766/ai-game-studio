# Hyper-Casual Game Research — 2026

## Market signal
Quick scan of 2026 casual-games coverage confirms the genre is still built on
single, instantly-readable mechanics, even as the top of the market drifts
toward "hybrid-casual" (simple core loop + light meta-progression). Recurring
signals worth designing around:
- **Merge mechanics** remain one of the highest-retention loops in casual (drag-to-merge, instant gratification).
- **One-mechanic, one-thumb control** is still the baseline test for hyper-casual — if it needs a tutorial, it's not hyper-casual.
- **Mini-games as permanent modes** — short, replayable, high-score-chasing loops outperform longer content for UA and retention alike.
- Sources: [Casual Games Market in 2026](https://www.blog.udonis.co/mobile-marketing/mobile-games/casual-games), [Top 10 Hyper-Casual Mobile Games of 2026](https://vexillogic.com/blog-top-10-hyper-casual-2026.html), [State of Mobile 2026 — Deconstructor of Fun](https://www.deconstructoroffun.com/blog/2026/2/2/state-of-mobile-2026)

## Already in this studio (do not duplicate)
| Project | Mechanic |
|---|---|
| lemonade-stand-godot | Idle clicker / incremental |
| snake-3d | Grid-based endless navigation, 4-directional |
| procedural-3d-godot | Endless runner, lane-switch + jump/slide |
| arcadia-clash | Card battler (not hyper-casual — deep meta) |

## Candidates considered
| Concept | Mechanic | Verdict |
|---|---|---|
| Flappy-style | Single tap to hop through gaps | Skipped — too close to procedural-3d-godot's lane runner in feel |
| Crossy-road style | Lane-hopping traffic dodge | Skipped — overlaps snake-3d's grid navigation |
| Fruit-slice | Drag to slice falling objects | Good candidate, deferred to next batch |
| **Stack Tower** | Tap to drop a moving block, stack precisely, tower rises | **Selected** — pure timing/precision, zero tutorial |
| **Helix/Spiral Drop** | Drag to rotate a tower of rings, ball falls through gaps | **Selected** — classic hyper-casual "fall" genre, one-axis control |
| **Timber Chop** | Alternate tap left/right before the trunk reaches you | **Selected** — pure reaction-speed, simplest possible input |
| **Merge Numbers** | Drag matching tiles together to merge, 2048-style | **Selected** — directly rides the 2026 merge-mechanic trend, 2D so it diversifies the studio away from all-3D |

## Chosen for this batch (4 prototypes)
1. **Stack Rush** (`stack-rush/`) — 3D stack-tower precision game.
2. **Spiral Drop** (`spiral-drop/`) — 3D helix-descent avoidance game.
3. **Timber Tap** (`timber-tap/`) — 3D reaction-timing chop game.
4. **Merge Numbers** (`merge-numbers/`) — 2D drag-and-merge puzzle.

Each follows the studio's locked production rules: one scene, GDScript only,
primitive meshes / ColorRect UI (no external art imports), `Color(r,g,b,a)`
always 4-argument, high score persisted via `user://*.cfg`, prototype-quality
only (no menus/sound/particles/IAP in this pass).

---

## 2026-07-15 — Round 2: playtest feedback and 4 new concepts

User playtest verdict on the first batch: Spiral Drop was actually broken
(a real rotation-sign bug, fixed — see `DESIGN_BRIEF.md`), Timber Tap had
zero onboarding so the mechanic wasn't legible, and Stack Rush / Merge
Numbers read as "generic, nothing new." Response was two-pronged:

1. **Added a genuine novelty twist to each of the 4 existing prototypes**
   instead of just polish (Stack Rush's Combo Rebuild, Spiral Drop's bug
   fix, Timber Tap's Golden Log + onboarding, Merge Numbers' Star wildcard)
   — see each project's `DESIGN_BRIEF.md` entry for specifics.
2. **Picked 4 new concepts that are different genres, not reskins.** The
   first batch all sit in the same broad "reaction/precision" bucket
   (tap-to-drop, rotate-to-align, alternate-tap, grid-slide) — same input
   grammar, different dressing. This batch was chosen specifically to break
   that pattern:

| Game | Genre | Why it's not a reskin |
|---|---|---|
| **Chroma Mix** | Matching puzzle | Grown directly from `COLOR_SYSTEM.md`'s own research (Itten's RYB wheel) instead of a generic template — the studio's research fed back into a game concept instead of just decorating existing ones. |
| **Tilt Tower** | Physics sandbox | First game in the studio built on a *real* physics simulation (`RigidBody2D`); stacking/toppling is emergent, not scripted. Every other game (including Stack Rush) is deterministic logic wearing a 3D skin. |
| **Loop It** | Planning puzzle | Drag-to-trace input (continuous stroke, plan-then-execute) instead of tap/swipe-direction/drag-to-rotate. No reaction-speed component at all — success is about seeing the path, not reacting fast. |
| **Gravity Flip** | One-button endless runner | Binary state (gravity up/down) with an instant single-hit fail, landscape orientation — deliberately different fail-state convention (3-strike is the house default for the others) and viewport orientation. |

Considered and rejected as too close to existing mechanics: a top-down
rhythm/pulse-dodge game (too similar to Spiral Drop's "find the gap"
loop) and a lane-based color-runner (too similar to the shelved
procedural-3d-godot lane runner).

---

## 2026-07-16 — Round 3: full-repo QoL/error review, then 4 more new concepts

User asked for two things: (1) review every game in the studio (not just
the newest batch) for quality-of-life GUI issues and potential errors, and
(2) build 4 more completely new games. Findings from (1) are recorded in
each project's `DESIGN_BRIEF.md` entry; the short version is 5 real bugs
across the 2 original pre-existing games and 2 of round 2's new games (a
restart deadlock, a data-loss autosave gap, missing `Label3D` billboarding
in two 3D games, and physics continuing to run after game over), plus 3
deliberate QoL additions (miss-feedback flashes, a gravity-direction
indicator).

For (2), the studio now has 12 hyper-casual prototypes spanning: idle
clicker, grid-snake navigation, precision-drop stacking, rotate-to-align
falling, alternate-tap timing, grid-slide merging, select-and-submit
matching, physics-balance sandbox, drag-trace planning, and one-button
binary-state running. Round 3 picked genres/input paradigms still missing:

| Game | Genre | Why it's not a reskin |
|---|---|---|
| **Target Throw** | Aim/timing (Knife Hit style) | The target rotates on its own — the player only controls *when* to throw, never the rotation itself. Spiral Drop is the opposite: the player rotates, an external element (the ball) just falls at a constant rate. Same "rotation" surface, inverted control. |
| **Pulse Tap** | Visual rhythm | The only game built around a continuously *repeating* timing window ("wait for the right moment in a cycle"). Every other timing-based game in the studio is single-shot (Timber Tap, Target Throw) or a binary state (Gravity Flip), not a loop you have to read and predict. |
| **Color Sort** | Stack-sorting logic puzzle | Zero reflex or timing component at all — no other game in the studio has that pacing. A shared move-budget economy stands in for a fail-state/timer. |
| **Flashlight Maze** | Fog-of-war exploration | Partial information. Snake 3D and Loop It are both fully-visible grids; this is the only game where the map itself has to be discovered and remembered, not just reacted to. |

Target Throw's knife-placement logic deliberately uses `Node2D.to_local()`
on a fixed world contact point instead of hand-derived rotation trig —
directly applying the lesson from Spiral Drop's rotation-sign bug (see
`DESIGN_BRIEF.md`'s pending-tasks lesson-learned entries).

---

## 2026-07-16 — Round 4: novelty everywhere, IP check, graphics, bug review

User asked for novelty improvements across *every* game in the studio (not
just new ones), an explicit check against aesthetic/copyright risk, a
graphics pass, and another bug-fix pass. Full detail is in
`DESIGN_BRIEF.md`'s 2026-07-16 update section and `IP_POLICY.md`; the
research-relevant takeaways:

**On copyright/trade dress**: mechanics aren't copyrightable, but a game's
*name* can still read as a direct reference to a specific commercial
title even when the mechanic-inspiration itself is fine. `timber-tap` was
renamed to `chop-chain` for exactly this reason (see `IP_POLICY.md` for
the full check performed against all 14 names — historical mentions of
"Timber Tap" elsewhere in this file predate the rename and are left as
accurate-at-the-time notes rather than rewritten).

**On novelty as a design habit, not a one-time pass**: the previous
rounds only gave a mechanical twist to the games that got specific
playtest complaints or were brand new. This round's brief made explicit
what should probably be standard practice going forward: *every*
prototype should ship with at least one twist that a generic clone
wouldn't have, from day one, rather than retrofitting twists only after
feedback calls out genericness. Two recurring twist *shapes* emerged
across the 11 games twisted this round — rare bonus objects/rounds (gems,
gold gates, double cycles, bonus food, coins) and rare wildcards that
relax a rule (chroma-mix's free pass, color-sort's any-color ball) — both
are cheap to reason about, cheap to self-test, and genre-agnostic, so
they're a reasonable default toolkit for the next batch of prototypes too.

---

## 2026-07-16/17 — Round 5: 4 more new concepts + structural redesign of all 14

User's brief this round was explicitly a step up from "add a twist": "add
novel gaming components to all games... things that structurally change
the game design... big novel changes." The distinction that mattered
going in: a rare-bonus-object twist (round 4's default toolkit above)
layers a reward on top of an unchanged rule system; a *structural* change
alters the rule system or control scheme itself. Full detail on both the
4 new games and all 14 redesigns is in `DESIGN_BRIEF.md`'s 2026-07-16/17
update section.

**4 new concepts**, chosen to fill genre/pacing gaps the studio's other
17 games (13 hyper-casual + shiftlight) didn't cover:

| Game | Genre | Why it's not a reskin |
|---|---|---|
| **Pattern Echo** | Memory sequence (Simon-style) | Memorize-then-recall pacing — zero reflex pressure during the watch phase. Loop It and Color Sort are also untimed-per-move, but neither is watch-then-repeat; this is the only game built around holding a growing sequence in short-term memory. |
| **Anchor Drop** | Rope-cut physics puzzle | Order-of-operations planning (which rope to cut last) resolved through real `RigidBody2D` physics once the last rope releases — distinct from Tilt Tower's continuous balance-under-emergent-physics and from every scripted/deterministic game in the studio. |
| **Flash Tap** | Single-target reflex | Raw "tap the one lit thing before it fades" reflex speed, no aiming/rotation/timing-a-moving-element component. Pulse Tap is timing a moving ring, Target Throw is aim-then-commit; this is neither. |
| **Number Slide** | Sliding-tile puzzle (15-puzzle) | The classic public-domain slide puzzle — pure planning, reuses the shared-move-budget fail state Color Sort established rather than inventing a new one, and reuses the solvability-by-construction generation technique (shuffle via reverse legal moves) already used by Color Sort/Flashlight Maze. |

**Structural redesign, one genuine rule/control change per original
game** (not a bonus pickup) — see `DESIGN_BRIEF.md` for the full list of
all 14. A few patterns worth naming for future rounds:
- **Reused-technique motif**: "solvability by construction" (generate a
  known-solvable state, then scramble via reversible moves) now appears
  in four different genres — Color Sort's tube distribution, Number
  Slide's reverse-shuffle, and this round's Loop It wall-dots (wall off a
  random suffix of a generated Hamiltonian ordering, so the remaining
  prefix is always traceable). A reliable pattern worth reaching for
  first whenever a new structural change risks an unsolvable state.
- **Decoupling an axis from a fixed control**: several redesigns added a
  genuinely new degree of freedom to an existing single-axis control
  scheme — Tilt Tower's platform translation riding the *other* component
  of the same drag gesture that already drove tilt, Stack Rush's block
  sweeping both X and Z instead of alternating one per layer, Gravity
  Flip's gravity axis rotating instead of only flipping sign. In each
  case the new axis was made to interact with (not just sit beside) the
  existing one, so it reads as one richer mechanic instead of a bolted-on
  second minigame.
- **Independent concurrent instances of the same mechanic**: Pulse Tap
  (two rings) and Target Throw (a second independently-rotating inner
  ring) both turned a single serial timing/aiming loop into two
  simultaneous ones — a cheap, genre-agnostic way to add real structural
  depth without inventing a new core verb.

All 18 games (14 redesigned + 4 new) were headless-verified clean, both
per-change and in a final full-repo sweep, matching the studio's
established verification discipline.

