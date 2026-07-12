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

### 2. Snake 3D (snake-3d/) 🔧 IN PROGRESS
- 3D snake on XZ grid,  WASD/arrows, WASD/arrows, 4-directional.
- Grid-based movement, wall = death, food = grow + score, speed increases.
- High score persisted via `user://snake3d_highscore.cfg`.
- Camera: crane-arm follow (SpringArm3D attached to snake head segment).
- Floor: procedural tile chunks with obstacle density.
- **User-verified working:** Controls register correctly.
- **Known issue:** Walls are nearly the same color as the floor wall collision is invisible.
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
- **Not yet playtested by user in the Godot editor (F5).**

### 5. Spiral Drop (spiral-drop/) ✅ PROTOTYPE COMPLETE
- Hyper-casual helix-descent game. Ball falls down a fixed vertical line;
  rotate the tower (A/D, arrows, or click/touch-drag) so each gate's gap
  lines up with the ball before it arrives.
- Endless gate generation. High score via `user://spiraldrop_highscore.cfg`.
- Headless-verified: clean load + scripted self-test covering forced-pass,
  forced-miss (game over), and restart — all passed.
- **Not yet playtested by user in the Godot editor (F5).**

### 6. Timber Tap (timber-tap/) ✅ PROTOTYPE COMPLETE
- Hyper-casual Timberman-style chopper (2D, portrait). Tap left/right half of
  screen (or A/D, arrow keys) to chop from that side; a branch on the tapped
  side ends the run. Shrinking timer forces the pace.
- High score via `user://timbertap_highscore.cfg`.
- Headless-verified: clean load + scripted self-test covering safe chops,
  forced hit (game over), timeout, and restart — all passed.
- **Not yet playtested by user in the Godot editor (F5).**

### 7. Merge Numbers (merge-numbers/) ✅ PROTOTYPE COMPLETE
- Hyper-casual 2048-style merge puzzle (2D, portrait), riding the 2026
  merge-mechanic trend (see `RESEARCH.md`). Swipe or arrow keys slide the
  4x4 grid; equal tiles merge; game over when the board is full and no
  merges remain.
- High score via `user://mergenumbers_highscore.cfg`.
- Headless-verified: clean load + scripted self-test covering line-merge
  math, a live grid move, full-board game-over detection, and restart —
  all passed.
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
7. **User F5 playtest of the 4 new prototypes** (stack-rush, spiral-drop, timber-tap, merge-numbers): these were verified headlessly (clean load + scripted self-tests per project) but need a hands-on pass in the Godot editor to confirm feel, camera framing, and touch/mouse controls on this machine before calling any of them "done."
8. **Polish pass** (once user picks favorites among the 4 new prototypes): sound, particles, menu, tutorial-free onboarding tuning — deliberately deferred per "Prototype First, No Polish."
