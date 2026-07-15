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
7. **User F5 playtest of all 8 hyper-casual prototypes** (stack-rush, spiral-drop, timber-tap, merge-numbers, chroma-mix, tilt-tower, loop-it, gravity-flip): all verified headlessly (clean load + scripted self-tests per project) but need a hands-on pass in the Godot editor to confirm feel, camera framing, and touch/mouse controls on this machine before calling any of them "done." Spiral Drop and Timber Tap specifically need reconfirmation since the 2026-07-15 round fixed a real rotation bug (Spiral Drop) and added onboarding (Timber Tap) in direct response to playtest feedback that the first pass hadn't caught.
8. **Polish pass** (once user picks favorites among the 8 prototypes): sound, particles, menu, tutorial-free onboarding tuning — deliberately deferred per "Prototype First, No Polish."
9. **Lesson learned 2026-07-15:** self-tests that re-derive the same formula the implementation uses (rather than checking against independent ground truth, e.g. actual rendered node transforms) can pass while the real mechanic is broken — this is exactly how Spiral Drop's rotation-sign bug slipped through the first verification pass. Future self-tests for anything involving rotation/orientation/geometry should validate against actual `global_transform` or an independently-derived expectation, not the same math path as the code under test.
