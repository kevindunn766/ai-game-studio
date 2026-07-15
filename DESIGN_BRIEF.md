# AI Game Studio — Design Brief

**Working directory:** `C:\Users\kevin\game-studio` (original machine) — also
worked from `C:\Users\Mr. Dunn\game-studio-work\ai-game-studio` on a second
machine; Godot binary there: `C:\Users\Mr. Dunn\Downloads\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64.exe`
(the download unpacked into a folder of the same name as the .exe — the real
binary is nested one level in).
**Engine:** Godot 4.7 (win64, GL Compatibility renderer)
**Goal:** End-to-end AI game studio — plain-English ideas → fully built games with AI supervision.
**Git remote:** `https://github.com/kevindunn766/ai-game-studio.git`

---

## Current Projects

### 1. Lemonade Stand (lemonade-stand-godot/) ✅ WORKING
- 2D idle clicker. User confirmed F5 works.
- Scene: 1 scene, user://JSON save/load, high-contrast yellow palette.
- Scripts: `Main.gd` (136 lines). No issues.
- **Status:** Complete and verified. Ready to ship or iterate on.
- **2026-07-14 color pass** (see `COLOR_SYSTEM.md`): labels had no explicit
  font color and were inheriting the theme default over the bright yellow
  background — fixed with explicit dark font colors on all static + upgrade-row labels.
- **Real bug found + fixed 2026-07-15 (QoL/error review):** idle income
  (`per_sec`) and manual click income (`_on_sell_pressed`) were never
  persisted on their own — only buying an upgrade called `save_game()`. A
  player who clicked/idled and closed the game without buying anything lost
  all of that progress. Fixed with a periodic autosave (every 5s) plus a
  save on `NOTIFICATION_WM_CLOSE_REQUEST`/`NOTIFICATION_APPLICATION_PAUSED`
  (quit/background — important for the Android export target).

### 2. Snake 3D (snake-3d/) 🔧 IN PROGRESS
- 3D snake on XZ grid,  WASD/arrows, WASD/arrows, 4-directional.
- Grid-based movement, wall = death, food = grow + score, speed increases.
- High score persisted via `user://snake3d_highscore.cfg`.
- Camera: crane-arm follow (SpringArm3D attached to snake head segment).
- Floor: procedural tile chunks with obstacle density.
- **User-verified working:** Controls register correctly.
- **Known issue — FIXED 2026-07-14:** Walls were nearly the same color as the
  floor. Root cause was missing emission (unlit albedo contrast alone washes
  out at a glancing directional-light angle); obstacles now get emission at
  the same hue plus a wider locked value/chroma gap from the floor. See
  `COLOR_SYSTEM.md`.
- **Crash found + fixed 2026-07-14:** `snake.gd::_segments_changed()` called
  `remove_child()` on the Snake node itself for a node that was actually
  parented under `Seg0` — Godot throws `"p_child->data.parent != this"` the
  first time a segment gets rebuilt after growth. Found via a headless replay
  while verifying the color pass; fixed by calling `existing_head.remove_child(child)`.
- **Serious bug found + fixed 2026-07-15 (QoL/error review):**
  `game_manager.gd::_trigger_game_over()` called `set_process_input(false)`,
  which disables ALL future `_input()` calls for that node — including the
  very same `_input()` function's `if is_game_over: restart()` branch. The
  game could never actually be restarted via keyboard after a death; it was
  a self-inflicted deadlock. Fixed by removing the `set_process_input(false)`
  call (the existing `is_game_over` check already correctly gates movement
  vs. restart, so disabling input processing entirely was never necessary).
  Also added tap/click-to-restart for parity with every other game in the
  studio, and added `billboard = 1` to all `Label3D` nodes in both snake-3d
  and stack-rush — without it, text planes don't face the camera and read
  as skewed/illegible from each game's fixed oblique angle (spiral-drop
  already had this set; the other two didn't).
- **New user request (2026-07-01):** Remove box walls. Replace with endless generating grid of 105%-sized planes within camera view, each with 25% chance of pastel-colored kill block. Camera crane arm 25% closer to snake. Endless obstacle navigation in all directions.
- Blockers: Python not installed blocks ad-hoc runtime verification.

### 3. Procedural 3D Runner (procedural-3d-godot/) 🔧 BROKEN — NEEDS REWORK or FIX
- Originally a 3D endless runner: auto-forward, lane switching, jump, slide, procedurally generated platforms.
- **Current state: heavily broken, user halted overengineering.**

#### Problems Encountered (do not repeat these mistakes):
1. **Camera override conflict**: Script code kept forcing `look_at()` even though user manually rotated camera in editor to face downward. User mandate: NEVER touch camera in code — let editor setting persist.
2. **Inline `.new()` in .tscn**: Godot 4.7 refuses inline `SphereMesh.new()` in scene files. Must use named `SubResource("...")` references instead.
3. **Node path `$../`**: Godot 4 doesn't parse `$../Parent` syntax. Use `get_node("../Parent")` in GDScript.
4. **Duplicate `add_child()`**: Adding the same collision shape to two parents crashes. Only one parent per node.
5. **Missing scene nodes**: `World.gd` references `TubeParent` and `BlockParent` that don't exist in the scene. Runtime `null instance` errors cascade from this.
6. **Stale Godot cache**: After fixes, old error output persists in editor Output tab. Must close and reopen project to see fresh state.
7. **Godot Output auto-clear**: Editor Output panel can auto-clear on play. Turn off in Editor Settings → Interface → Editor → Output → "Clear output on play". Use dedicated Errors tab for persistent logs.
8. **`Color()` alpha requirement**: Godot 4 `Color()` always takes 4 args `(r,g,b,a)`. Missing alpha throws parse error in .tscn and .gd.
9. **No local Python**: Windows machine has no Python interpreter. `python3` is missing. All ad-hoc verification scripts fail. Must use Godot F5 directly, or install Python.
10. **Git push timeouts**: `git push origin master` times out at 30s on this machine. Use background process with `notify_on_complete=true` for pushes.

#### User Constraints for This Project:
- Use the existing template as base. Do NOT rebuild files from scratch.
- Keep it simple — Godot is a game engine, not a coding environment.
- Camera faces downward along negative Z axis (set in editor, not overridden in code).
- Core features to retain if rebuilt: distance scoring, 3-crack death system, boundary walls, periodic section color shifts, procedural background.
- **Pending decision:** Simplify/fix existing code vs. rebuild from locked design brief.

### 4. Stack Rush (stack-rush/) ✅ PROTOTYPE COMPLETE
- Hyper-casual stack-tower game. Tap/click/space drops a moving block; overlap
  becomes the new block, overhang slices off and falls.
- Zero overlap = game over. Camera rises with the tower. High score via
  `user://stackrush_highscore.cfg`.
- Headless-verified: clean load (no script/parse errors) + scripted self-test
  exercising drop, slice, game-over, and restart paths — all passed.
- **2026-07-14 color pass** (see `COLOR_SYSTEM.md`): layer palette rebuilt as
  an evenly-stepped hue rotation at fixed saturation/value instead of 7
  hand-picked RGB triples.
- **2026-07-15 user playtest feedback:** "just like another studio's with
  nothing new." Added a **Combo Rebuild** twist: standard stack clones only
  ever shrink the tower; here, chaining 3 near-perfect (>=92% overlap) drops
  in a row widens the block back out (up to base size) instead — a
  skill-driven comeback path. Verified via self-test forcing a shrink then a
  3-drop streak and confirming the width grows back.
- **QoL fix 2026-07-15 (review pass):** none of the 5 `Label3D` nodes had
  `billboard` set — against this game's fixed isometric camera angle text
  planes don't face the camera by default and read as skewed/illegible.
  Added `billboard = 1` to all of them (spiral-drop already had this).
- **Not yet playtested by user in the Godot editor (F5) since this change.**

### 5. Spiral Drop (spiral-drop/) ✅ PROTOTYPE COMPLETE
- Hyper-casual helix-descent game. Ball falls down a fixed vertical line;
  rotate the tower (A/D, arrows, or click/touch-drag) so each gate's gap
  lines up with the ball before it arrives.
- Endless gate generation. High score via `user://spiraldrop_highscore.cfg`.
- Headless-verified: clean load + scripted self-test covering forced-pass,
  forced-miss (game over), and restart — all passed.
- **2026-07-14 color pass** (see `COLOR_SYSTEM.md`): gate teeth de-saturated
  and the ball's chroma raised, so the ball (the thing you track) reads
  clearly above the tower instead of competing with it (Itten's contrast of
  saturation used as a legibility cue).
- **Real bug found + fixed 2026-07-15** (user playtest: "the ball collides
  with the rings" no matter how you rotate). Root cause: `_resolve_gate()`
  computed the slot under the ball as `-tower_rotation / SLOT_ANGLE`
  instead of `+tower_rotation / SLOT_ANGLE` — a sign error that checked the
  mirror-image slot, so the tower could never actually be rotated to a
  working position. The original self-test hadn't caught it because it
  re-derived the *same* (wrong) formula instead of checking against
  independent ground truth. Fixed, and re-verified against the actual
  rendered tooth transforms (`global_transform.origin` angle), not just the
  game's own math, specifically to catch this class of bug.
- **Not yet playtested by user in the Godot editor (F5) since this fix.**

### 6. Timber Tap (timber-tap/) ✅ PROTOTYPE COMPLETE
- Hyper-casual Timberman-style chopper (2D, portrait). Tap left/right half of
  screen (or A/D, arrow keys) to chop from that side; a branch on the tapped
  side ends the run. Shrinking timer forces the pace.
- High score via `user://timbertap_highscore.cfg`.
- Headless-verified: clean load + scripted self-test covering safe chops,
  forced hit (game over), timeout, and restart — all passed.
- **2026-07-14 color pass** (see `COLOR_SYSTEM.md`): **found a real signal
  bug** — the hazard branch was green, the universal "safe" color, fighting
  the player's split-second read. Recolored to red-orange (danger family);
  player token moved to magenta so it never shares a hue family with trunk,
  branch, ground, or sky. Also added explicit label font colors (score/game
  over text had no override and was inheriting a low-contrast theme default).
- **2026-07-15 user playtest feedback:** "I don't even know what that is
  doing or what I'm supposed to do" — zero onboarding. Added a `ReadyOverlay`
  shown before the first tap explaining the branch/chop rule and the gold
  bonus, gated behind an explicit first-tap-to-start (matches the pattern
  now used in all 4 new prototypes below). Also added a novelty twist:
  **Golden Log** segments (no branch, ~18% of branch-free segments) that
  refill part of the timer and give bonus score — a comeback mechanic
  standard Timberman clones don't have.
- **Not yet playtested by user in the Godot editor (F5) since these changes.**

### 7. Merge Numbers (merge-numbers/) ✅ PROTOTYPE COMPLETE
- Hyper-casual 2048-style merge puzzle (2D, portrait), riding the 2026
  merge-mechanic trend (see `RESEARCH.md`). Swipe or arrow keys slide the
  4x4 grid; equal tiles merge; game over when the board is full and no
  merges remain.
- High score via `user://mergenumbers_highscore.cfg`.
- Headless-verified: clean load + scripted self-test covering line-merge
  math, a live grid move, full-board game-over detection, and restart —
  all passed.
- **2026-07-14 color pass** (see `COLOR_SYSTEM.md`): tile ramp rebuilt as one
  continuous Munsell-style hue/saturation/value progression (the original
  was a hand-copied 2048 palette that jumped color families partway
  through). Also **found a real contrast bug**: tile number labels had no
  explicit font color and were inheriting a light theme default over
  light/cream tile backgrounds — fixed with a luminance-based black/white
  text picker per tile.
- **2026-07-15 user playtest feedback:** "very much generic too." Added a
  novelty twist: a rare **Star wildcard tile** (~8% of spawns) that merges
  with *any* adjacent tile it touches (doubling that tile's value) instead
  of only equal values — a controlled-chaos escape valve standard 2048
  clones don't have. Game-over detection updated: a wildcard on a full
  board always means a move is still available.
- **Not yet playtested by user in the Godot editor (F5) since this change.**

### 8. Chroma Mix (chroma-mix/) ✅ PROTOTYPE COMPLETE — NEW 2026-07-15
- Color-theory matching puzzle grown directly out of `COLOR_SYSTEM.md`'s
  research rather than a generic hyper-casual template. Tap 1-3 primary
  paints (Red/Yellow/Blue) to mix them, then hit MIX to match the target
  swatch. Follows Itten's real RYB pigment wheel: R+Y=Orange, Y+B=Green,
  B+R=Purple, all three=Brown (true pigment-mixing lore, not an invented
  rule).
- 3 strikes (wrong mix or timeout) end the run; round timer shortens as
  score climbs. High score via `user://chromamix_highscore.cfg`.
- Onboarding `ReadyOverlay` explains the mix table before the first round.
- Headless-verified: clean load + scripted self-test covering all 7 mix
  results, a correct submit, a wrong submit (strike loss), draining all
  strikes to game over, and restart — all passed.
- **QoL added 2026-07-15 (review pass):** a wrong mix or a timeout looked
  identical to a correct submit (both just silently redrew the round) —
  added a transient "WRONG MIX!" / "TOO SLOW!" flash label so a strike is
  unmistakable in the moment it happens.
- **Not yet playtested by user in the Godot editor (F5).**

### 9. Tilt Tower (tilt-tower/) ✅ PROTOTYPE COMPLETE — NEW 2026-07-15
- The studio's first game built on a real physics simulation
  (`RigidBody2D` + `AnimatableBody2D`) instead of scripted/deterministic
  logic — stacking, sliding, and toppling are emergent, not scripted.
  Tilt the platform (A/D, arrows, or click/touch-drag) to keep falling
  blocks from sliding off; 3 lost blocks end the run. Score = seconds
  survived.
- High score via `user://tilttower_highscore.cfg`.
- Headless-verified: clean load + a self-test that let real physics run
  (flat-platform phase confirmed no blocks fall when centered and level;
  forced-hard-tilt phase confirmed a block eventually falls and ends the
  run) plus restart — all passed. Note: verifying this one required
  time-based (simulated-seconds) checks rather than counting
  `_physics_process` calls against `--quit-after`, since headless idle-loop
  iterations and physics ticks don't run 1:1.
- **Real issue found + fixed 2026-07-15 (review pass):**
  `_physics_process` stops tracking/pruning shapes once `game_over` is
  true, but the Godot physics engine itself keeps simulating every
  `RigidBody2D` on screen regardless of my script — any blocks still
  falling at the moment of game over would fall forever in the background,
  off-screen, for as long as the game-over overlay stayed up. Fixed by
  setting `freeze = true` on all remaining shapes in `_trigger_game_over()`
  (also reads better — the tower visibly freezes instead of silently
  vanishing). Also added `continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE`
  to spawned blocks to reduce tunneling through the platform at high speed.
- **Not yet playtested by user in the Godot editor (F5).**

### 10. Loop It (loop-it/) ✅ PROTOTYPE COMPLETE — NEW 2026-07-15
- A genuinely different genre for this studio: a drag-to-trace planning
  puzzle (one-line / Hamiltonian-path style) instead of a reaction/timing
  game. Drag through every dot on the grid in one continuous stroke
  (up/down/left/right only, no revisiting a dot) before the timer runs out.
  Releasing early just clears the stroke (no penalty beyond lost time);
  letting the timer hit zero costs a strike. Grid grows 3x3 -> 6x6 with
  score.
- High score via `user://loopit_highscore.cfg`.
- Headless-verified: clean load + scripted self-test covering adjacency
  logic, a full valid path completing a round, an early release clearing
  the stroke without penalty, draining strikes via timeout to game over,
  and restart — all passed.
- **QoL added 2026-07-15 (review pass):** added a transient "TIME UP!"
  flash on a timeout strike, matching the miss-feedback pattern added to
  Chroma Mix. (Checked for a suspected `dragging`-not-reset bug reported
  in an earlier draft of this review — re-read the actual shipped code and
  confirmed `_new_round()` already resets it; no bug was actually present.)
- **Not yet playtested by user in the Godot editor (F5).**

### 11. Gravity Flip (gravity-flip/) ✅ PROTOTYPE COMPLETE — NEW 2026-07-15
- One-button endless dodge runner (Gravity Guy / Impossible Game genre).
  The world auto-scrolls; tap/space flips which way gravity pulls the
  player (with an instant velocity kick for a snappy feel). Each obstacle
  blocks either the upper or lower half of the corridor — be on the open
  half when it arrives. One hit ends the run (the genre's defining
  instant-fail convention, deliberately different from the 3-strike
  pattern used by the other three new prototypes). Landscape viewport
  (960x540) — also deliberately different from the portrait layout used
  everywhere else in the studio.
- High score via `user://gravityflip_highscore.cfg`.
- Headless-verified: clean load + scripted self-test covering the
  collision math directly (all 4 side/half combinations, plus an
  out-of-range obstacle) and a full integration run (never flipping lets
  gravity pull the player to the floor, which reliably collides with a
  floor-blocking obstacle), and restart — all passed.
- **QoL added 2026-07-15 (review pass):** added a small arrow indicator on
  the player that always points the direction gravity is currently
  pulling, so a flip reads instantly instead of only being inferable from
  motion a moment later.
- **Not yet playtested by user in the Godot editor (F5).**

### 12. Target Throw (target-throw/) ✅ PROTOTYPE COMPLETE — NEW 2026-07-15
- A Knife Hit-style precision game — the target spins entirely on its own
  (unlike Spiral Drop, where the player rotates the tower); the player only
  controls *when* to throw. Tap to throw a knife into the spinning target;
  an empty spot sticks and rotates with the target from then on, a spot
  that already has a knife (within a small angular tolerance) ends the run.
  Every 6 successful throws advances a round and speeds up the spin.
- High score via `user://targetthrow_highscore.cfg`.
- Knife placement/collision uses `Node2D.to_local()` on a fixed world
  contact point rather than hand-derived rotation trig, specifically to
  avoid the class of sign-error bug Spiral Drop had (see its entry above).
- Headless-verified: clean load + scripted self-test covering a first
  throw always sticking, a second throw at unchanged rotation always
  hitting the same spot (game over), a throw past the tolerance window
  sticking cleanly, round advancement after 6 throws, and restart — all
  passed.
- **Not yet playtested by user in the Godot editor (F5).**

### 13. Pulse Tap (pulse-tap/) ✅ PROTOTYPE COMPLETE — NEW 2026-07-15
- A sound-free rhythm game: a ring shrinks continuously toward a fixed
  target ring; tap the instant they align. No other game in the studio is
  built around "wait for the right moment in a repeating cycle" — tapping
  early/late, or letting a cycle run out untapped, all cost a strike (3
  strikes ends the run); a successful hit immediately starts the next,
  slightly faster cycle.
- High score via `user://pulsetap_highscore.cfg`.
- Headless-verified: clean load + scripted self-test covering a
  well-timed tap scoring without costing a strike, an early tap costing
  exactly one strike (and not stacking penalties from spam-tapping the
  same already-resolved cycle), an untapped cycle timing out into an
  auto-miss, draining strikes to game over, and restart — all passed.
- **Not yet playtested by user in the Godot editor (F5).**

### 14. Color Sort (color-sort/) ✅ PROTOTYPE COMPLETE — NEW 2026-07-15
- A Ball Sort Puzzle style stacking game — the only prototype in the
  studio with zero reflex/timing component at all. Tap a tube to pick up
  its top color, tap another to pour it in (legal only onto an empty tube
  or a matching top color). Sorting every tube to a single color solves
  the puzzle. A shared move budget across the whole session (not a
  per-puzzle timer or strikes) is the twist: solving refills moves, so
  efficient play is what keeps the run going.
- High score (puzzles solved) via `user://colorsort_highscore.cfg`.
- Puzzles are generated by randomly distributing colors into tubes with 2
  empty tubes for maneuvering room — the standard approach for this genre.
  Solvability isn't formally proven for every deal (same caveat real
  mobile ball-sort games have); noted explicitly in `DESIGN.md` as a
  known scope boundary rather than something to hide.
- Headless-verified: clean load + scripted self-test covering the
  generator's ball-count invariant (each color appears exactly CAPACITY
  times across all tubes), top-run counting, pour legality, solve
  detection, a move costing exactly 1 from the shared budget, running out
  of moves ending the run, and restart — all passed.
- **Not yet playtested by user in the Godot editor (F5).**

### 15. Flashlight Maze (flashlight-maze/) ✅ PROTOTYPE COMPLETE — NEW 2026-07-15
- A fog-of-war exploration game. Unlike Snake 3D (fully visible grid,
  continuous auto-move) or Loop It (fully visible dot grid), only a small
  radius around the player is ever revealed here — and it stays revealed
  once seen, so the challenge is genuinely about exploring and
  remembering the maze's layout under time pressure. A fresh perfect maze
  (recursive-backtracker generation) is built each round; reach the exit
  before the timer runs out. Move with WASD/arrows/swipe.
- High score (mazes solved) via `user://flashlightmaze_highscore.cfg`.
- Headless-verified: clean load + scripted self-test that flood-fills the
  generated maze and confirms every single cell is reachable from the
  start (the generator's core correctness property — a broken maze
  generator producing disconnected regions would otherwise be a silent,
  unsolvable-puzzle bug), plus wall-bump no-ops, force-solving a round,
  draining strikes via timeout to game over, and restart — all passed.
- **Not yet playtested by user in the Godot editor (F5).**

---

## Game Production Rules (non-negotiable)
1. **Design Brief Before Code** — write the brief, get approval, then build.
2. **Prototype First, No Polish** — ugly grey box is fine. Functionality first.
3. **Lock the Feature List** — approved features only. No creep.
4. **Polish Is Separate** — after prototype works, schedule polish as its own phase.
5. **Playtest Before Export** — F5 in Godot, user confirms, then export.
6. **Quality Is Non-Negotiable** — colors must have good contrast; no broken input; no crashes.

---

## Agent Infrastructure

### Claude Code (Primary)
- Path: `C:\Users\kevin\AppData\Local\hermes\node\claude.cmd`
- **Active account:** kevindunn1981@gmail.com (Pro subscription)
- **Remote Control:** Active. Session URL: `https://claude.ai/code/session_01AQuEMFqunMWUqrDyHjbHtW`
- Install version: **v2.1.193** (meets v2.1.51+ requirement)

### OpenCode (Routine tasks)
- Path: `/c/Users/kevin/AppData/Local/hermes/node/opencode`
- Auth: OpenRouter, `auth.json` at `~/.local/share/opencode/auth.json`
- Working auth format: `{"openrouter": {"type": "api", "key": "..."}}`
- Tested: `openrouter/openai/gpt-4o-mini` responds "Okay!"

### Claude.json config
- Path: `C:\Users\kevin\.claude.json`
- Contains: GitHub MCP server, auth (firstParty OAuth)

### Godot
- Binary: `/c/Users/kevin/AppData/Local/Microsoft/WinGet/Links/godot.exe`
- Version: 4.7.stable.official.5b4e0cb0f

### Hermes Memory (important facts)
- GitHub email for pushes: kevindunn766@gmail.com
- Shell: Git Bash (POSIX syntax)
- Python: NOT installed (blocks ad-hoc scripts)
- No npm global installs (timeouts)
- Git push times out — use background process

---

## Environment Quirks (do not trip over these)
- **No Python**: `python3` not found. All `.py` verification scripts fail. Use Godot F5 for runtime checks.
- **Output auto-clears**: Godot Output panel clears on play. Disable in settings.
- **ANTHROPIC_BASE_URL**: If set to non-Anthropic host, Remote Control is disabled. Unset it.
- **CLAUDE.md**: Located at `C:\Users\kevin\game-studio\procedural-3d-godot\AGENTS.md` — Godot development rules, color requirements, anti-patterns, export targets.
- **4 agent definitions** in `C:\Users\kevin\game-studio\.claude\agents\`:
  - `game-architect.md`
  - `godot-coder.md`
  - `art-generator.md`
  - `qa-tester.md`

---

## Pending Tasks
1. **Fix snake-3d**: Replace walls with endless obstacle planes (25% spawn, pastel colors, crane camera 75% distance). Verify collision visible.
2. **Fix/build procedural-3d-godot**: Either fix existing broken files or rebuild clean from brief with user's constraints (camera downward, simple, no overengineering). User decision needed.
3. **Android SDK setup**: Export templates not yet confirmed installed. Blocking APK export.
4. **PR management workflow**: Beyond GitHub MCP — formalize PR creation, review, merge workflow.
5. **Canonical Godot verification**: No project has had a formal playtest + user confirmation since latest edits.
6. **Git push of latest commits**: Local commits exist for snake-3d scaffold but push keeps timing out.
7. **User F5 playtest of all 12 hyper-casual prototypes** (stack-rush, spiral-drop, timber-tap, merge-numbers, chroma-mix, tilt-tower, loop-it, gravity-flip, target-throw, pulse-tap, color-sort, flashlight-maze): all verified headlessly (clean load + scripted self-tests per project) but need a hands-on pass in the Godot editor to confirm feel, camera framing, and touch/mouse controls on this machine before calling any of them "done." Spiral Drop and Timber Tap specifically need reconfirmation since the 2026-07-15 round fixed a real rotation bug (Spiral Drop) and added onboarding (Timber Tap) in direct response to playtest feedback that the first pass hadn't caught. Snake 3D and Lemonade Stand also need reconfirmation after the 2026-07-15 review pass fixed a restart deadlock and an autosave data-loss bug respectively.
8. **Polish pass** (once user picks favorites among the 12 prototypes): sound, particles, menu, tutorial-free onboarding tuning — deliberately deferred per "Prototype First, No Polish."
9. **Lesson learned 2026-07-15 (round 1):** self-tests that re-derive the same formula the implementation uses (rather than checking against independent ground truth, e.g. actual rendered node transforms) can pass while the real mechanic is broken — this is exactly how Spiral Drop's rotation-sign bug slipped through the first verification pass. Future self-tests for anything involving rotation/orientation/geometry should validate against actual `global_transform` or an independently-derived expectation, not the same math path as the code under test. Target Throw's knife-placement code applies this directly (`to_local()` instead of hand-derived trig).
10. **Lesson learned 2026-07-15 (round 2, QoL/error review):** a full-repo review pass (all 10 then-existing prototypes, not just the newest ones) turned up 5 real, distinct bugs the per-game self-tests hadn't caught, because each bug was in a code path the self-tests never exercised or a cross-cutting concern no single-game test would catch: snake-3d's restart deadlock (`set_process_input(false)` disabling its own restart handler), lemonade-stand's missing autosave (only `_buy_upgrade` persisted state), stack-rush/snake-3d's missing `billboard` on `Label3D` nodes (a scene-file property, not something a GDScript self-test touches), and tilt-tower's physics continuing to simulate after game over (an engine-level behavior, not a script-state bug). Takeaway: self-tests validate the logic they're written to exercise, not the whole game — a periodic full-repo re-review (not just testing the newest additions) is worth doing, especially for scene-file properties (billboard, font colors, anchors) and cross-cutting lifecycle concerns (save/restart/pause) that no single feature's self-test happens to cover. Also confirmed a suspected Loop It bug (dragging flag not reset) was a false alarm on re-reading the actual shipped code — a reminder to verify against current code before fixing, not just from memory of what "should" be there.
