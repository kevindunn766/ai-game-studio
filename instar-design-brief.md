# INSTAR — Design Brief

**Status:** DRAFT — foundation only. This is a living document we build **together, bit by bit, one task at a time**. Nothing below is locked except the Governing Rules and the three Signature Hooks; every other section is a scaffold to be filled in collaboratively and must not be expanded, paraphrased, or auto-implemented ahead of an explicit instruction.
**Working Title:** `INSTAR` — an *instar* is the developmental stage an arthropod occupies between molts. It fits a battler where bugs grow, molt, and evolve between fights; it is a short, original, ownable word using no trademarked or branded name. Title is a placeholder; swap freely.
**Genre:** Isometric procedural bug-battling game.
**Engine:** Godot 4.x (align to the studio's other 3D projects unless we decide otherwise).
**One-line pitch:** Fully procedurally *constructed* and procedurally *animated* bugs do battle on an isometric arena, filmed through a depth-map tilt-shift lens so the whole fight reads like a living tabletop miniature diorama.

---

## Governing Rules (Never Broken)

These inherit from the studio's `DESIGN_BRIEF.md` and `CLAUDE.md`, plus rules specific to how Kevin wants THIS session run.

1. **Design brief before code.** This document is the single source of truth. No scene/script/asset work runs ahead of what the brief (and Kevin) has authorized.
2. **One task at a time. No paraphrasing.** Kevin gives instructions bit by bit; each is executed exactly as written, one at a time. No batching, no running ahead, no reinterpreting intent. When in doubt, ask.
3. **Record everything.** Every instruction and every action is logged word-by-word in `instar-progress-notes.md` as we go (see that file).
4. **Prototype first, no premature polish.** Grey-box / primitive-driven proof that the core hooks feel right comes before shaders, particles, SFX, or beauty passes — except where a hook *is* the visual (the tilt-shift camera), which is itself proven in grey-box.
5. **Lock the feature list once approved.** No scope creep without an explicit new approval.
6. **Camera safety (hard-learned studio rule).** Any node that scales/rotates/moves as part of gameplay (a growing bug, a molting creature) must never have the camera rig parented under it. Camera framing is driven by code reading explicit values (e.g. arena bounds, subject scale) and setting camera parameters directly — never inherited "for free" via a scaled parent transform.
7. **Procedural mesh correctness (studio non-negotiable).** Any generated mesh must match Godot's triangle winding convention (verify against `BoxMesh`/`SphereMesh`: every face `cross(v1-v0, v2-v0) · outward_normal < 0`). Flat per-face normals set explicitly; no hiding reversed winding behind double-sided materials. Read `docs/godot-3d-best-practices.md` and `docs/godot-procedural-meshes.md` before any mesh work.
8. **Original names only.** No trademarked/branded names for the game, creatures, or mechanics.

---

## Signature Hooks (the three things that define INSTAR — LOCKED)

These are the reasons the game exists. Everything else serves them.

### 1. 100% Procedurally *Constructed* bugs
No hand-authored creature meshes. Every bug's body — segments, legs, wings, antennae, mandibles, carapace plating — is assembled at runtime from procedural parts driven by a seed/genome. Two bugs are never identical. (Design of the genome → body pipeline is TBD, developed together.)

### 2. 100% Procedurally *Animated* bugs
No baked animation clips. Locomotion, attacks, idle twitches, flinches, and death are all generated procedurally — think procedural leg IK / gait, spring-driven bodies, physically-reactive parts — so animation emerges from the constructed body rather than being keyframed onto it. (Animation system design is TBD, developed together.)

### 3. Depth-map tilt-shift camera (the "look")
The signature visual: an isometric camera whose image is post-processed using a **depth map** to drive a tilt-shift photography effect (a narrow in-focus band with falloff to blur above and below it), making the arena read like a tiny real-world model / macro-photography diorama. (Exact pipeline — Godot depth texture, focal-band shader, whether it's a post-process on the viewport — is TBD, developed together.)

---

## Perspective & Camera

- **Isometric** viewpoint (fixed-angle). Details — orthographic vs. shallow-perspective, angle, whether it rotates — TBD together.
- Tilt-shift is a post effect layered on top of the iso render (Hook 3). Framing obeys Governing Rule 6.

---

## To Be Developed Together (open — do not fill in ahead of instruction)

Each of these is a deliberate blank we fill collaboratively, in whatever order Kevin directs:

- **Core loop / battle format** — 1v1? arena survival? tournament ladder? player-controlled vs. auto-battler vs. tactics? Unknown until we decide it together.
- **Player agency** — do you directly control a bug, draft/build a bug, command a team, or spectate-and-tune? Unknown.
- **The bug genome** — what parameters define a bug; how a seed maps to body parts, stats, and abilities.
- **Procedural construction pipeline** — part library, assembly rules, mesh generation approach.
- **Procedural animation system** — gait/IK model, attack motion, reactions, death.
- **Combat model** — stats, damage, initiative, win/lose conditions.
- **Progression** — molting/growth/evolution between fights (the "instar" fantasy), and how it ties to construction/animation.
- **Arena** — procedural construction of the battlefield itself, hazards, scale.
- **Tilt-shift pipeline specifics** — depth source, focal band control, blur method, tuning knobs.
- **Art / palette / mood**, audio, UI, and win/meta screens.
- **Milestone plan** — the ordered build steps, once the above is decided.

---

## Core Concept (decided 2026-07-18, Session 1)

INSTAR is a **"tank-lite," bug-themed** game. The player moves a bug around the screen and
**collects minor companion bugs** along the way (the "tank-lite" hook — the player bug is the
tank, gathering a following/entourage). **Bugs are categorized by natural variety and, within
that, by number of legs** (e.g. isopod = 14 legs; the leg count is a real taxonomy axis, not
just flavor). Combat/tank specifics and how companions fight or attach are still open — developed
together.

## Build Log

### Milestone 0 — Procedural isopod + tilt-shift test bed (2026-07-18)
First creature to prove the procedural-construction workflow and the leg IK. In `instar/`:
- **Renderer = Forward+** (chosen over the studio-default `gl_compatibility`) so the tilt-shift
  hook can sample scene depth reliably.
- **Isopod** (`scripts/isopod.gd` + `scripts/mesh_builder.gd`): 100% procedurally constructed —
  9 tapered flat-shaded dome plates (head + 7 leg segments + tail), 14 legs. 100% procedurally
  animated — per-leg 2-bone IK + metachronal-wave gait (swing/stance, foot plant + lift +
  anticipation). Drives itself in a circle (no controls yet).
- **Camera** (`scripts/iso_camera.gd`): orthographic isometric SpringArm3D boom, follows the bug,
  obeys Governing Rule 6.
- **Tilt-shift** (`shaders/tilt_shift.gdshader`): full-screen depth-driven focus band + disk blur;
  focus plane fed per-frame from the subject's view-space depth. Verified working on-GPU.
- Brown floor + scattered pebbles (pebbles are removable depth-reference dressing).
- **Open refinement:** legs bend above the carapace (ribcage look from iso) — next IK-tuning pass.
- Dev aid: `main.gd` has a flag-gated `--capture` screenshot helper (`godot --path instar --capture`).

## Notes / Conventions

- Progress and the word-by-word session log live in `instar-progress-notes.md`.
- Project folder (once we start building) will be `instar/`, matching the studio's per-game folder convention (`snake-3d/`, `chimera-drift/`, `cragling-3d/`).
- This brief will be updated/appended as decisions are made — additive, dated, never silently rewritten.
