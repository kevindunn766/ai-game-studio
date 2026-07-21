# INSTAR — Progress Notes & Session Play-by-Play

This file is the running, word-by-word record of the session that builds INSTAR. Kevin's
instructions are logged **verbatim** (no paraphrasing). Claude's actions are logged as they
happen. Newest entries appended at the bottom.

- **Game:** INSTAR (working title) — isometric, 100% procedurally animated & constructed bug-battling game, filmed through a depth-map tilt-shift lens.
- **Design brief:** `instar-design-brief.md`
- **Engine:** Godot 4.x
- **Working style:** one task at a time, no paraphrasing, follow instructions exactly, build bit by bit.

---

## Session 1 — 2026-07-18

### [Kevin — verbatim]
> We will use this session to develop a game in GODOT called something that you will come up with based on the following theme. It will be an isometric 100% procedurally animated and constructed "bug battling game". The camera will use a depth map to create a tilt-shift photography look. I need you to follow my instructions exactly and one task at a time. No paraphrasing. Together bit by bit we will develop this game. Got it. Make a design brief and a progress notes file where we will build record our progress and the the word by word play by play events in this session. Let me know when you are ready.

### [Claude — actions]
1. Read the governing `DESIGN_BRIEF.md` (studio rules) and reviewed the `chimera-drift-design-brief.md` format as the house style for per-game briefs.
2. Logged this work as a task.
3. Chose the working title **INSTAR** (an instar = an arthropod's developmental stage between molts; original, ownable, fits a battler where bugs grow/molt/evolve; no trademarked name).
4. Created `instar-design-brief.md` — foundation only: Governing Rules, the three LOCKED Signature Hooks (procedural construction, procedural animation, depth-map tilt-shift camera), and a "To Be Developed Together" section left deliberately blank for collaborative fill-in.
5. Created this progress-notes file with Kevin's opening instruction recorded verbatim.
6. Reported ready and awaiting the next instruction.

### [Kevin — verbatim]
> Nice, the game will be a tank lite that is bug themed. The player will move a bug around the screen and collect minor companion bugs along the way. Bugs will be categorized by the natural varieties and respectively by the number of legs. Let's first build a working procedural isopod character model to refine the procedural workflow and the IK for the bug legs. Set up a brown floor and the isometric_camera/spring_arm setup. You might as well go ahead and wire the tilt-shift photography look in that is based the depth map. No controls for now just make it move in circles so you can view it and test for the right look.

### [Claude — actions]
1. Read the mandatory `docs/godot-3d-best-practices.md` and `docs/godot-procedural-meshes.md` before engine work (winding rule, flat-face helper, camera pattern, headless quirks).
2. **Renderer decision:** INSTAR uses **Forward+** (not the studio's usual `gl_compatibility`) because the locked tilt-shift hook needs reliable scene depth-texture sampling.
3. Created the `instar/` Godot project: `project.godot`, `scenes/Main.tscn`, and scripts.
4. **`scripts/mesh_builder.gd`** — procedural flat-shaded arched "dome segment" mesh (isopod dorsal plate), using the docs' proven winding/normal helper.
5. **`scripts/isopod.gd`** — procedurally *constructs* the isopod: 7 leg-bearing segments + head + tail (9 tapered dome plates), 14 legs (7 pairs). Procedurally *animates* the legs: per-leg 2-bone IK (law-of-cosines knee, bends up-and-out) + a metachronal-wave gait (per-leg phase, swing/stance, foot planting with anticipation and lift). Auto-drives in a circle (no controls yet).
6. **`scripts/iso_camera.gd`** — SpringArm3D boom at a true-iso angle (35.264°/45°, orthographic), follows the bug; feeds the tilt-shift pass the subject's per-frame view-space depth as the focus plane (Governing Rule 6: framing is code-driven, rig never parented under the moving target).
7. **`shaders/tilt_shift.gdshader`** — full-screen spatial post pass: reconstructs linear view depth from the depth texture, keeps a band around `focus_depth` sharp, golden-angle disk-blurs the rest, small saturation lift for the miniature pop.
8. **`scripts/main.gd`** — assembles the test bed: WorldEnvironment + sun, brown floor, scattered pebbles (removable depth-reference dressing for judging focus), the bug, and the camera. Includes a flag-gated (`--capture`) dev screenshot helper.
9. Verified: headless run compiles cleanly (fixed two Variant-inference errors — this build treats them as errors — by moving legs to a typed inner `class`; fixed a shader error — `INV_PROJECTION_MATRIX` must be passed into a helper function, not referenced inside it). Rendered screenshots on the AMD 780M / Vulkan Forward+: tilt-shift depth focus confirmed working, IK legs confirmed reaching/planting, gait confirmed animating between frames.

**Milestone 0 status: DONE (viewable).** Open refinement flagged to Kevin: femurs currently bend *above* the carapace (reads like a ribcage from the iso angle) — top candidate for the next IK-tuning pass.

### [Kevin — verbatim]
> Cool take a picture of it and show me.

### [Claude — actions]
- Rendered fresh screenshots via the `--capture` helper and showed a frame.

### [Kevin — verbatim]
> Make it rounder from head to tail. more realistic. Why are the leg segments longer than the bones? They stick out really far.

### [Claude — actions]
1. Clarified the leg question: the rendered cylinders are scaled exactly joint-to-joint (no over-draw / no IK stretch, since the foot targets were within reach). The "sticking out" was long bones + wide foot placement + high hips causing the legs to splay past the shell.
2. **Legs — shorter + tucked:** femur 0.30→0.19, tibia 0.36→0.23, foot_out 0.34→0.19, ride_height 0.22→0.15, hip_y 0.05→0.04, swing anticipation 0.18→0.10×speed, and knee pole re-weighted (`UP*0.6 + outward`) so knees splay outward instead of straight up.
3. **Body — rounder head-to-tail:** replaced the near-flat height ramp with tapering profiles — width `pow(sin,0.5)` (floor 0.16, keeps rounded nose/rear girth) and height `pow(sin,0.8)` (floor 0.06, arches high mid, low at ends); overlap 1.25→1.45 and dome arc steps 8→12 for a smoother convex pill.
4. Re-rendered: body now reads as a rounded convex isopod; legs short and tucked, drawn length == bone length. Residual: far-side legs still peek slightly over the back at the iso angle (tunable).

### [Kevin — verbatim]
> [attached pillbug reference image] Instead of using cylinders create the body segments from parabolic forms. The bug should be only about twice as long as it is wide. the head should be a quarter of a sphere. Each body segment should fit under the one in front of it from the front to the back. The tail should be another snuggly fit series of quarter spheres that fit under the edge of the last body segment. I attached an image for your reference.

### [Claude — actions]
1. Added `MeshBuilder.parabolic_segment()` (cross-section `y=h·(1-u²)`) and `MeshBuilder.quarter_sphere(radius, round_z)` (flat bottom + flat back + rounded dome).
2. Rebuilt `isopod._build_body`: quarter-sphere head (rounds toward -Z), 7 overlapping parabolic pereon segments (gently tapering, each tucking under the one ahead), shrinking quarter-sphere tail; ~2:1 length:width. Legs now read hip z/width from shared `_pereon_z/_pereon_hw` arrays.

### [Kevin — verbatim]
> Did you follow the best practices from Chimera Drift?

### [Claude — actions — IMPORTANT FINDING]
- **No — I had skipped best-practice #7 / the CLAUDE.md mesh non-negotiable: verify winding NUMERICALLY vs `BoxMesh`/`SphereMesh`, not by screenshot.** Wrote `verify_winding.gd` and ran it. It caught a real fault: `parabolic_segment` 32/66 faces reversed, `quarter_sphere(-Z)` 336/350 reversed, `quarter_sphere(+Z)` 12 reversed — i.e. the meshes were largely inside-out (the see-through hollow in the render was reversed winding, not geometry gaps).
- **Root cause:** the shared `_flat_face` helper in `docs/godot-procedural-meshes.md` is **order-dependent** — it flips the normal vector outward against the ref point but always emits the same winding, assuming the caller pre-wound each tri outward. When the ref-flip triggers (e.g. the `round_z=-1` head's handedness-flipping parametrization), the normal is corrected but the winding stays reversed → `cross·normal > 0` → inside-out, while still looking plausible.
- **Fix:** rewrote `_flat_face` to be **order-independent** — choose the outward normal from the ref, then choose the emitted winding to satisfy `cross(emitted)·normal < 0` regardless of input vertex order. Re-ran `verify_winding.gd`: **ALL CORRECT** (all faces `<0`, matching Box/Sphere). Re-rendered: body is now a solid convex pill, no see-through.
- **Flagged to Kevin:** the studio doc's helper has this latent trap (propagates to every project) — offered to update `docs/godot-procedural-meshes.md` + memory with the order-independent version. Awaiting go-ahead.
- Still outstanding: legs still splay over the back; segment ridges subtle.

### [Kevin — verbatim]
> Update the doc at will. Any findings per project should be moved into the studiowide docs so future sessions can benefit. This can be a rule in and of itself. But let's keep tweaking the isopod's shell. Give each body segment a profile not just from head to toe but from side to side. Also the edges along the sides of the body are super important. Honestly the bug is a minimalist bug. All features are super important. Tweak each body segment until they are nearly perfect per the image provided l and use a mirror modifier to make sure they are symmetrical.

### [Claude — actions]
1. **Promoted the winding fix to the studio docs** (as instructed): rewrote the order-independent `_flat_face` in `docs/godot-procedural-meshes.md` with a "trap this replaced" note; added a standing **"Promote findings to studio docs"** rule to `docs/godot-3d-best-practices.md` §0 and `CLAUDE.md`; saved memory `promote_findings_to_studio_docs.md` + `instar_project.md` and indexed them.
2. Added `MeshBuilder.body_plate()` — a dorsal plate domed in BOTH axes (side-to-side parabolic arch + head-to-tail convex length profile), flat base, front/rear caps, built as one +X half and **mirrored across X=0** (mirror-modifier style; the order-independent helper auto-winds the reflected half). Added `MeshBuilder._mirror_quad()`.
3. Switched `isopod._build_body` to `body_plate` per segment (edge_floor 0.55).
4. Added a `show_legs` toggle (`--nolegs` cmdline) to judge the shell alone.
5. Verified `body_plate` winding numerically (`ALL CORRECT`) and rendered legs-off: shell now reads as a segmented pill bug — ribbed segments w/ grooves, rounded head/tail, symmetric.
6. Flagged 3 deltas vs the reference for the next tweak: (a) grooves too deep (flutes vs overlapping plates), (b) lateral side edges need definition/flare, (c) head slightly larger. Recommended doing (a)+(b) together; awaiting Kevin's go-ahead.

### [Kevin — verbatim]
> Do 1 and 2 together, then if you are moving in the wrong direction I'll prodive guidance.

### [Claude — actions]
1. Rebuilt `body_plate` to sweep an explicit half cross-section profile (`_PLATE_PROFILE`) whose last points form a **flared lateral lip (epimeron)** — bulges past x=1 then tucks to the base — giving each plate a defined side edge (delta b).
2. Raised `edge_floor` 0.55→0.8 and reduced per-segment size taper (width 0.16→0.10, height 0.34→0.14) so plates **overlap into shingled steps instead of deep flutes** (delta a).
3. Verified `body_plate` winding numerically (`ALL CORRECT`); rendered legs-off. Result now closely matches the reference: shingled armor bands with subtle grooves + defined flared side edges, symmetric, solid, ~2:1.
4. Noted two remaining construction seams (not part of 1/2): head↔plate-0 gap at the front-bottom, and the last segment's exposed rear cap that the tail quarter-spheres don't fully cover. Paused for Kevin's direction (moving in the right direction per his check-in).

### [Kevin — verbatim]
> Make the front to back profile less rounded. They aren't that round(like a pumpkin). But make the front edge of each body segment smaller than the back edge. Then tuck the front edge nearly under the back edge of the one in front of it, make them overlap. Count the pieces in the picture and actually make it have the exact number as the picture.

### [Claude — actions]
1. **Counted the reference: 11 dorsal plates** (7 large thoracic + ~4 smaller posterior tapering to the tail). Set `num_segments = 11`.
2. **Decoupled legs from shell count** — legs are the isopod's anatomy (7 pairs = 14), so added `num_leg_pairs = 7` + `leg_start_segment`; legs sit on the thoracic run, independent of the 11 plates.
3. Rebuilt `body_plate` front-to-back profile from a sine bulge (pumpkin) to a **near-linear ramp**: front edge smaller, back edge full → the small front tucks under, the back is the exposed lip. `seg_spacing 0.13 < seg_len 0.28` gives heavy overlap (front tucks nearly under the plate ahead). Overall body dome (tall mid) applied per-segment so the union still reads domed.
4. First pass over-ramped (front_h 0.42) → tall pointed sawtooth fins; softened to front_h 0.82 / front_w 0.9 → subtle overlap steps. Winding re-verified `ALL CORRECT`.
5. Rendered legs-off (11 bands visible, shingled). Flagged 2 artifacts to Kevin: top-ridge steps still a touch pronounced/pointed (reference is a thin groove line at the top, edges mainly on flanks) and small gaps open between the shrinking rear plates. Asked whether to soften steps + close gaps, or make steps more pronounced.

### [Kevin — verbatim]
> Okay closer. There are a bunch of images. Try harder while keeping the things I told in mind.
> [then, separately, 5 reference images attached: the original pillbug macro, an ISOPOD ANATOMY diagram (dorsal+ventral, labeling CEPHALOTHORAX, PEREON=pereonite 1-7, EPIMERON 1-7 / epimeral flaps, PLEON=pleomere 1-5, PLEOTELSON, UROPOD), and 3 side-view pillbug photos]

### [Claude — actions]
- The images initially didn't attach; flagged that and started from the original reference, then the 5 images arrived and I studied them.
- **Key learning from the anatomy diagram:** body = cephalothorax + PEREON (7 pereonites, each a leg pair + a hanging EPIMERON side flap) + PLEON (5 pleonites) + pleotelson. The side-view photos show each segment has a **hanging epimeral flap on the flank** (not just a plate meeting the ground) with sharp overlapping rear edges.
- **Rebuilt the plate** (`MeshBuilder.body_plate`) from a flat-bottomed arch to a **closed cross-section outline** (`_PLATE_OUTLINE`): domed top → flared shoulder → **epimeron that hangs down toward the legs** → concave belly, mirrored across X=0. Added `_mirror_tri` for the fan caps.
- **Rebuilt the body** to real anatomy: head (quarter sphere) + **7 pereonites** (`body_plate`, full epimera, one leg pair each) + a **single smooth lofted pleon+pleotelson tail** (a scaled quarter-sphere). Reason: discrete shrinking pleon rings telescoped into a screw/drill-bit; one smooth dome reads like the reference's blunt rounded rear.
- Tuned overlap heavy + gentle width-varying ramp (front_h_center 0.98 / front_h_side 0.80 / front_w 0.94) so pereon merges into a continuous carapace with thin grooves, dorsal midline smooth, flank shows the overlap. Decoupled legs → one pair per pereonite (7). `hip_y` moved to -0.04 (under the belly). Winding `ALL CORRECT` after each change.
- Result: recognizable pill bug (rounded head, grooved domed carapace, epimera, blunt tail). Remaining deltas flagged to Kevin: pereon→tail transition shows a couple separated plate edges; flank epimera a bit stair-steppy; pleon segment lines currently smoothed away (offered to etch subtle grooves back). Legs off (`--nolegs`) for shell review; leg pass still owed after the hip move.

### [Kevin — verbatim]
> Do all three. Let's see if it helps. But before you do. One question. Are the pieces of the carapace separate? It seems like you might do better going through the images and building each piece by itself. Then you can build an armature for each piece. and link them together. Right.

### [Claude — actions]
- **Answered:** pieces were already separate `MeshInstance3D`s but statically placed — no armature. Confirmed his approach is right (needed for the "100% procedurally animated" hook — pill bugs flex/curl/roll-up — and for authoring each piece independently).
- **Restructured to a spine armature:** `_build_body` now builds each piece, then chains a joint per piece (cephalothorax → 7 pereonite joints → tail), parenting each carapace mesh to its joint. Neutral now; rotating a joint later flexes everything behind it. Added `_make_mi`; `_joints` stored.
- **Item 3 (pleon grooves):** new `MeshBuilder.tail_loft` — lofts the plate cross-section from the front size to a blunt rounded tip with N shallow transverse pleonite grooves (smooth tail, no screw, pleonites read).
- **Item 2 (flank epimera):** added `epimeron_sweep` (backward flap sweep) to `body_plate`; eased the flank step (`front_h_side` 0.80→0.88).
- **Item 1 (transition):** heavier pereon overlap (`pereon_len` 0.44→0.52), softened epimeron hang (0.9), more tail overlap — front/middle pereon merges into a continuous carapace; last ~2 pereonites still separate slightly (residual).
- Winding `ALL CORRECT` on all meshes incl. `tail_loft`. Rendered legs-off: recognizable pill bug with armature. Residuals flagged: faint rear-plate separation, tail tip slightly pointy. Asked Kevin: keep tightening shell, or move to the leg pass (hang 7 leg pairs on the pereonite joints, re-tuck under the belly).

### [Kevin — verbatim]
> Let's not pat ourselves on the back at all. It looks really bad. I'm going to outline the process that I want you to use for 3d modeling. I need you to record this process into our studio best practices for future use. It will help you get the results that I would expect from an amature 3d modeling artist. Are you ready for the step by step technique?
>
> [next message, with a front-view isopod photo attached] First step, use the top view then the side view then the front view to create an outline with the correct number of vertices needed to get an even mesh. Literally trace the photos, I've included an image of an isopod from the front. Do this for all of the pieces. Some best guess or interpolation can be used for the parts that aren't visible in the front view. But you can see how round it is. Add solidify modifier. Make a skeleton then link to bones appropriately. You can do this with nearly any simple form.

### [Claude — actions]
- Took the blunt feedback: the tweak-and-hope loop was the wrong method; stopped self-congratulating.
- Recorded the technique **verbatim** into a new studio doc `docs/godot-3d-modeling-process.md` (trace top/side/front → even-vertex outline per piece → interpolate hidden parts → solidify → skeleton + link to bones), with a procedural-Godot translation (three traced polylines → loft the front cross-section along Z scaled by top-width & side-height; solidify = thick-walled section; skeleton = chained joints).
- Wired it in as mandatory: linked from `docs/godot-3d-best-practices.md` §1 and added a rule to `CLAUDE.md`; saved memory `three_view_modeling_process.md` and indexed it.
- Studied the front-view reference (shows the true rounded cross-section — the view I'd never traced). Awaiting any further steps before applying the process to rebuild the isopod.

### [Kevin — verbatim]
> Then for things like legs you can trace one side and rotate. I forgot to mention always use mirroring to get perfect symmetry.

### [Claude — actions]
- Appended both to `docs/godot-3d-modeling-process.md`: step 7 (repeated parts like legs — trace ONE, rotate/array to place the rest) and a **Governing rule: ALWAYS mirror for perfect symmetry** (build one half, mirror it; procedurally the order-independent `_flat_face` auto-winds the reflected half). Updated the memory file too.

### [Kevin — verbatim]
> Okay, but trace each segment of the leg and rotate each segment separately, then rig together on an IK.

### [Claude — actions]
- Added step 8 to `docs/godot-3d-modeling-process.md` (+ memory): legs are **per-segment** — trace each leg segment (coxa/femur/tibia/tarsus) separately, rotate each into place, then rig the segments together on an **IK chain** (not one fused leg). Trace-one + mirror/rotate into all sockets still applies.

### [Kevin — verbatim]
> Last sample the image for the object's color. Then color the object or UV maps depending on how detailed it should be.

### [Claude — actions]
- Added final step 9 (color): sample the reference image for the object's actual color, then flat-color (simple) or UV-map + texture (detailed) per needed detail level. Added a "Pipeline at a glance (complete)" summary to `docs/godot-3d-modeling-process.md` and updated memory. **The full modeling process is now recorded.** Ready to apply it to rebuild the isopod.

### [Kevin — verbatim]
> Yeah give it a try.

### [Claude — actions — BODY REBUILT via the traced process]
- **Traced the three views into profiles:** `FRONT_OUTLINE` (rounded cross-section w/ hanging epimeron + belly), `TOP_W` (half-width along body), `SIDE_H` (dorsal height along body). Added `MeshBuilder.loft_closed(outline, sx, sy, zs)` — mirrored, closed loft = the code form of the three-view trace.
- **Rebuilt the body as slices of that lofted surface:** `_body_slice(u0,u1,proud,rings)` samples FRONT×TOP×SIDE over a u-range; `_build_body` builds cephalothorax + 7 pereonite slices (proud rear edge = armor overlap) + tail slice, each conforming to the SAME surface so adjacent pieces nest cleanly. Hung on the spine armature (joint per piece).
- **Bug found via error-filtering the render:** `const FRONT_OUTLINE := PackedVector2Array([...])` is NOT a constant expression → isopod.gd failed to compile → the bug never loaded and I'd nearly analyzed STALE shots. Fixed: use `const : Array[Vector2]` / `Array[float]` (const-foldable), and `loft_closed` takes `Array`. (Lesson: always grep the render for SCRIPT ERROR before trusting a screenshot.)
- **Result:** finally a coherent rounded pill-bug carapace — clean transverse pereonite grooves (no screw), rounded head, domed back, blunt tail. The traced method fixed what tweak-and-hope couldn't. Winding `ALL CORRECT` (incl. `loft_closed`).
- **Still to do per the process:** per-segment IK legs (trace one, mirror/rotate into 14 sockets), color (sample reference); minor tail rounding. Paused for Kevin's steer.

### [Kevin — verbatim]
> Everything is perfect except one thing. Make the profile from the top capsule shaped. Make the profile from the side like the top half capsule. Rounded on the front and the back. Rounded from above too.

### [Claude — actions]
- Set `TOP_W` and `SIDE_H` to a **capsule (stadium) profile**: parallel/flat through the middle, rounded (semicircle) front and back. Body is now a clean pill — capsule from top, top-half-capsule from side, rounded cross-section — with even pereonite grooves across the flat span and rounded ends. Winding still `ALL CORRECT`. Body approved by Kevin ("everything is perfect except" the profile, now fixed). Next: legs.

### [Kevin — verbatim]
> Okay one little change make the body just a little bit rounder and less pill shaped.

### [Claude — actions]
- Softened the capsule toward an oval (curved sides, blunter ends) — subtle. Approved.

### [Kevin — verbatim]
> Perfect, now the legs.

### [Claude — actions — LEGS + COLOR via the process]
- Added `MeshBuilder.tapered_tube` (traced round leg segment). Each leg = **coxa + femur + tibia** traced tapered tubes, **IK**-driven (2-bone femur/tibia + coxa), **mirrored** to both sides, **one pair per pereonite** (14 legs) — steps 5–8.
- `_aim_bone` re-rooted to base-at-joint (segments start at y=0). Legs tucked under the body (inboard hips, feet ~under the edge, knees bend down) so the epimera overhang hides the far row from the iso angle.
- **Two real bugs fixed:** (1) `const PackedVector2Array([...])` isn't a constant expression → isopod.gd silently failed to compile and I nearly analyzed STALE shots — now grep the render for `SCRIPT ERROR` before trusting a screenshot; (2) legs starting in stance had `foot_world == (0,0,0)` and drew a stick to world-origin → init uninitialized feet to their rest position. Also fixed gait stretch (stride > leg reach) by shrinking `stride_length`.
- **Color (step 9):** sampled the reference — dark slate-brown carapace, pale grey-tan legs.
- Result: a coherent colored pill bug — capsule carapace w/ clean pereonite grooves + a pale IK leg-fringe, animating. Full modeling process now applied end-to-end. Residual: a few far-side legs peek over the top edge; legs a bit stick-like. Paused for Kevin's steer.

### [Kevin — verbatim]
> Are you resizing bones after the mesh is attached? The legs don't look right.

### [Claude — actions — RIG FIX]
- **Yes — I was.** `_aim_bone` built each segment at length 1 and then **non-uniformly scaled it (Y by joint distance) every frame** to stretch it between joints. Wrong: bones must be rigid (fixed length, rotate-only); the scaling stretched/squashed segments as the IK target moved → the bad look.
- **Fixed:** each segment mesh is now built at its TRUE length (coxa = attach→hip distance, femur = femur_len, tibia = tibia_len); `_aim_bone` is now **rotation + position only, no scale**; the tibia is drawn rigidly toward the foot (clamped to tibia_len) so it never stretches when out of reach.
- Re-tuned leg length/splay for the now-rigid bones (they'd been over-tucked, relying on the stretch to reach the ground). Legs now read as a consistent jointed fringe under the near edge, far row hidden.
- **General lesson for the modeling doc:** rigid bones — never resize a segment mesh after attaching it; build at true length, only rotate. (Candidate to add to `godot-3d-modeling-process.md`.) Added to the doc.

### [Kevin — verbatim]
> [side-view + anatomy references] Two things add the peduncles and flagellum. Then sculpt the edges of the epimerons. See how the edges are scalloped in the side/top/bottom views. See how much space is under the isopod for the legs on the side view.

### [Claude — actions]
- **Antennae (Antenna 2):** `_build_antennae` — each = jointed peduncle (3 rigid tapered segments) + thinner flagellum (2), reddish-brown `_antenna_mat`, swept forward-down-out from the cephalothorax, mirrored. Added `_aim_bone_local` (rigid, local-space) for static parts.
- **Scalloped epimera:** `loft_closed` gained per-ring `scallop` (applied to outline indices 5–8 = the epimeron); `_body_slice` feeds `scallop_amt * sin(PI*t)` so each pereonite's flap lobes out mid-plate and notches at the seams. Tuned 0.35→0.18 (0.35 read as square tabs).
- **Leg clearance:** raised `ride_height` 0.20→0.30 (body arched up, clear gap under it) and lengthened legs (femur 0.15 / tibia 0.19) so they stand down into the gap.
- Result: pill bug now has antennae, a scalloped flank, and legs standing in an under-body gap. Residual flagged: scallop lobes a bit blocky (flat-faced), antennae fairly straight. Paused for Kevin's steer.

### [Kevin — verbatim]
> Everything looks good but the scalloped edges. Remove that and spread the legs out so the fit equally from head to tail.

### [Claude — actions]
- **Removed the scallop** (`scallop_amt` → 0.0; flank smooth again).
- **Spread the legs evenly head-to-tail:** `_build_legs` now places the 7 pairs at `u = lerp(leg_u_start 0.14, leg_u_end 0.84, (k+0.5)/N)` (sampling width from the TOP trace), instead of bunching them on the 7 pereonite centers. Even row of rigid IK legs under the raised body. Model reads as a clean pill bug (smooth carapace, antennae, even legs).

### [Kevin — verbatim]
> Okay cool. Copy this alto preserve our progress. Make a second and force it to roll up into a pill like a pill bug. Research to get the details need for the animation.

### [Claude — actions]
- **Researched conglobation/volvation** (WebSearch): ventral inward curl; overlapping tergites (dorsal plates) on flexible joints rotate/slide over each other; hard shell forms the outside of a tight sphere, legs/head/antennae/soft belly sealed inside; fast defensive response.
- **Preserved** the walking version: `isopod.gd` untouched. `main.gd` spawns the roller by default; `--walker` spawns the original.
- **Created `isopod_roller.gd`** (copy + roll-up): a timed cycle (extend → curl → hold ball → unroll). `_apply_curl` rotates every spine-armature joint ventrally (`curl_per_joint_deg` ≈ 40°, ×9 joints ≈ full circle); `_place_on_circle` lifts the body onto the floor when balled; legs retract (feet → hips) and hide, antennae hide, as it closes. The armature built earlier is exactly what enables this.
- Result: recognizable conglobation into a ball, tergites out, soft parts inside. Residual: ball is slightly ovoid with a small pinch at the tail join (not yet a perfect sphere); legs are rigged to the straight body axis so they're hidden fast rather than curled in. Paused for Kevin's steer.
