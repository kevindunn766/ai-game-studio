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
