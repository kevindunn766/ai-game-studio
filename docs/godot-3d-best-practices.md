# Studio Best Practices — Godot 4 (3D)

Applies to every Godot 3D project in this studio (chimera-drift, cragling-3d, kindling-3d,
snake-3d, instar, procedural-3d-godot, …). Everything here is **verified working in a shipped
project**, not theory. Do not add to this file unless you have proven it in-engine — a faulty
"best practice" propagates to every project.

---

## 0. Promote findings to these studio docs (standing rule)

Any reusable engine finding proven in a single project — a gotcha, a corrected helper, a
verified pattern — must be **moved up into these studio-wide docs** (this file or
`godot-procedural-meshes.md`) so future sessions on any project inherit it, not left buried in
one project's notes. Prove it in-engine first (numeric check where correctness is involved),
then write it here with the project + date it was verified. A fix that stays project-local is a
trap the next project re-discovers the hard way.

---

## 1. Procedural meshes / normals

See **[`godot-3d-modeling-process.md`](godot-3d-modeling-process.md)** — mandatory before modeling
any creature/prop: the reference-traced (top/side/front) → solidify → rig workflow. Do NOT
hand-guess profile numbers and tweak-and-hope.

See **[`godot-procedural-meshes.md`](godot-procedural-meshes.md)** — mandatory before any
`SurfaceTool`/`ArrayMesh` work. One-line summary: outward normal *vectors* are not enough; the
triangle **winding must match Godot's convention** — verify a generated mesh against
`BoxMesh`/`SphereMesh` (`cross(v1-v0,v2-v0) · normal < 0` per face) or objects render inside-out.

- **If you flip a face normal to force a direction (e.g. inward for a tube interior), you MUST
  flip the WINDING to match** (verified, chimera-drift 2026-07-19). A loft/ribbon helper that
  points the normal inward but keeps one fixed vertex order leaves half its faces with
  `cross(emitted)·normal > 0` — they render inside-out, and reaching for a `double_sided` material
  to hide it is the anti-pattern. Choose the emit order per face: `cross(v1-v0,v2-v0)` is `raw`;
  emit `(v0,v1,v2)` when `raw·n < 0` else `(v0,v2,v1)`, so the stored normal stays anti-parallel to
  the emitted cross. Then a single-sided `cull_back` material renders the interior correctly.

---

## 2. Camera that tracks / scales with a growing target (verified)

The problem: a ship/character whose effective size grows over a run, framed from multiple
viewpoints. The proven pattern:

- **Drive framing off one explicit scalar in code** (e.g. `ship_visual_radius`), adjusting each
  camera's distance / orthographic `size` / spring-arm length directly every frame. NEVER let
  framing happen "for free" via an inherited *scaled* parent transform.
- **Never parent the camera rig under a node that gets scaled or rotated** as part of that
  growth. Parenting under a node that only **translates** (to track position) is fine — the rig
  inherits position but you set framing yourself.
- **Position + `look_at()` every frame beats hand-derived pivot rotation math.** Set
  `camera.position = <direction> * base_distance * radius` then `camera.look_at(target_global,
  up)`. Hand-rolled rotation math once produced a camera at the numerically-correct position
  pointed at nothing useful — a bug invisible without an actual render.
- **`look_at` up-vector gotcha:** for a straight top-down camera the up vector cannot be `UP`
  (parallel to the look direction) — use `Vector3.FORWARD` (or any non-parallel axis).

Reference implementation: `chimera-drift/scripts/camera_rig_controller.gd` (third-person via
`SpringArm3D` length; side-scroll / isometric / top-down / 3-4 via `position` + `look_at`, all
scaled off `ship_visual_radius`).

---

## 3. CSG shapes do NOT register with `Area3D` detection (verified gotcha)

`CSGShape3D.use_collision = true` does **not** produce a body that `Area3D.body_entered` /
`get_overlapping_bodies()` ever detects (confirmed against a plain `StaticBody3D`, which works
immediately). Root cause unresolved; the established workaround:

- Pair every visual CSG shape with an explicit **sibling `StaticBody3D` + `CollisionShape3D`**
  (matching size/position) purely for collision.
- Watch the detector too: setting `monitorable = false` on the *detecting* `Area3D` (thinking
  nothing needs to detect it back) **silently breaks its ability to detect others**. Leave it at
  the default `true`.

If you build detailed procedural meshes yourself (`ArrayMesh`), the same applies — give them a
primitive `CollisionShape3D` sibling; don't rely on the visual mesh for collision.

---

## 4. Kinematically-moved hazards → `AnimatableBody3D` (verified)

For a "static-type" body that you move every frame in code (a patrolling/homing obstacle), use
**`AnimatableBody3D`**, not `StaticBody3D`. It is Godot 4's purpose-built node for a
kinematically-moved static body, and `Area3D` overlap detection works on it identically to a
`StaticBody3D`.

---

## 5. Streaming generation (verified)

For endless/large levels, stream in segments a fixed distance ahead of the player and free ones
that fall behind (never bulk-build). Throttle instantiation with a **per-frame cap** (spawn at
most N segments/props per frame from a pending queue) so a dense level can't spike a frame.

- **Build only to the fogged horizon, and derive the fog end from the ACTUAL build distance —
  never hardcode it** (verified, chimera-drift 2026-07-19). Stream a world-unit window
  (`build_ahead`/`build_behind`), not a segment count, so the frontier sits just past what the
  camera sees. If a perf profile scales the build distance (e.g. `view_distance_scale` ×0.5 on
  low tiers), a *hardcoded* `fog_depth_end` will sit **beyond** the reduced frontier and geometry
  pops into clear view. Compute `fog_depth_end = build_ahead × view_distance_scale − margin`
  (and `fog_depth_begin` as a fraction of it) so the frontier is always fully fogged on every
  tier. Objects that can't be fogged (e.g. in orthographic views where distant things don't
  recede) instead **scale 0→1 in at the frontier and 1→0 out as they recede**, shrinking to
  nothing before they're built/freed, so the window edge never pops.
- **Endless-in-all-directions ground = a 2D tile grid off a pure height function** (verified,
  chimera-drift 2026-07-19). A fixed-width forward *strip* centered on the player has a hard
  lateral cull edge that shows the moment the camera looks sideways (top-down / iso / ¾) —
  don't patch it per-view. Instead key tiles by integer cell `(ix,iz)`, and each frame spawn
  every cell inside the window (ahead **and** laterally) and free every cell that leaves it in
  **any** direction. Tiles seam automatically iff height is a **pure function** `h(x,z)` (adjacent
  tiles sample identical shared-edge verts). When the per-frame cap bites, build **nearest-to-
  player first** so no hole opens underfoot. Keep the same vertex/index winding the strip used
  so per-face normals still point the right way (verify: avg tile normal `.y > 0`).
- **Collision LOD: give streamed ground a trimesh body only near the player** (verified,
  chimera-drift 2026-07-19). A moving character can only ever hit the tile it is over, so a
  visual grid of ~40 tiles needs only a ~3x3 block of lethal trimesh bodies around it — the
  rest are mesh-only. Reconcile each frame: a cell gains its `StaticBody3D` while the player is
  still a full cell away and drops it once the player leaves. Trimesh bodies are the expensive
  part (meshes are cheap and mostly fogged); this is the real low-end-device win and it's
  gameplay-invisible.
- **Own the scenery with the ground tiles, not a separate lane** (verified, chimera-drift
  2026-07-19). If the terrain streams in all directions but the props/detail are scattered in a
  forward lane, they visibly *stop at the lane edge* when the player steers wide while the ground
  keeps going. Scatter each tile's props as part of that tile (seeded per-cell so it's stable
  across re-entry; freed with the tile) so scenery fills wherever the ground is. Keep the count
  bounded — and the gameplay path as dense as before — with a **lateral density falloff**: full
  density within a corridor around the player's path, tapering quadratically (`1/(1+e²)`, floored
  so it never hits zero → no hard edge) toward the streamed horizon, since far lateral rings hold
  many more tiles than near ones. Apply the same collision-LOD (body only near the player) to the
  scenery bodies. Moving threats (enemies) can stay lane-based — they're gameplay, not scenery.
- **Deep perspective views: scale objects down + render-cull them before the fogged horizon**
  (verified, chimera-drift 2026-07-19). Streaming bounds the *geometry* but a field of props still
  *renders* out to the fog in third-person/¾ views where the world runs far back. Per streamed
  object, ramp a scale factor from 1→0 over a distance-from-camera band (e.g. 0.5→0.82 × the build
  distance) and set `visible=false` once it hits ~0 — a real render cull, cheaper than a 0-scale
  draw, and it reads as "shrink into the distance and vanish" rather than a hard pop (the fog
  covers the last bit). Gate it on the view: no-op for orthographic/side views (bounded frame) and
  for the ground mesh (scaling tears seams) and rigid-body debris (scaling mid-sim misbehaves).
- **Never scale a node to EXACTLY 0 — floor it** (verified, chimera-drift 2026-07-20). A
  `Vector3.ZERO` scale (or a single 0 axis) is a **singular basis**, and Godot spams
  `ERROR: Condition "det == 0" is true.` when it inverts the transform (normal matrix / physics /
  culling), even with `visible=false`. It's intermittent — only fires the frames an object sits at
  the fade edge (scale hit 0) before it's freed — so it hides in "works most of the time." The
  scale-cull ramp above must clamp: `node.scale = base * max(f, 0.0015)` (the node is already
  hidden below the visible threshold, so the tiny floor is never seen). Same trap for
  collider-owning nodes — prefer hiding (`visible=false`) over scaling them at all.

---

## 6. GDScript style (this studio's projects)

- **Fully typed, warnings-as-errors.** Every `var` has an explicit type or a `:=` inferred from
  a *typed* value. Common trip-ups that are errors here: `var x := lerp(...)` (lerp returns
  `Variant` → type it `var x: float = lerp(...)`); `var d := dict.duplicate()` (→ `: Dictionary`);
  untyped loop vars used in typed math; integer division of int literals.
- Prefix intentionally-unused params with `_`.

---

## 7. Verify correctness NUMERICALLY / in-engine, not by screenshot

Screenshots are for judging *look*, not *correctness* — a wrong mesh/normal can look plausible.
For anything with a right/wrong answer, write a small headless check (`godot --headless --script
res://…`) that reads back the data and asserts (e.g. per-face `cross·normal` sign vs a primitive;
spawn positions; no start-crash across many random rolls). Godot's CSG and mesh generation run on
the CPU, so these validate headless without a GPU.

---

## 8. Scale-adaptive ground/surface detail across extreme zoom (verified)

For a game whose camera zooms across orders of magnitude (kindling-3d: a ~0.7 m match-scale view
out to a ~500 m inferno view over one continuous run), you want a surface that looks *equally
detailed* at every zoom — never a flat untextured plane up close, never aliased mush far out.
Proven approach (verified in-engine via renders at camera.size 0.7 / 4.0 / 40.0, kindling-3d
2026-07-19):

- **Godot 4 has NO hardware tessellation or geometry-shader stage** (Godot 3 did; removed in 4 —
  the shading language is vertex/fragment/light/compute only). Do not plan around a tessellation
  shader. Get the "denser geometry up close" behaviour a different way ↓.
- **Fixed-vertex patch scaled by camera zoom = the tessellation substitute.** Keep ONE
  subdivided mesh (e.g. 129×129) centred under the player and set its XZ scale to
  `camera_size × margin` each frame. Fixed vertex count over a patch that resizes with zoom ⇒
  **on-screen triangle density stays ~constant at every zoom** — world vertex spacing shrinks to
  sub-cm up close and grows to metres far out, so relief resolves finer exactly when the camera
  is close. Displace vertices in the shader (sampling world XZ via `MODEL_MATRIX`), so recentre/
  rescale needs no CPU mesh rebuild — just move + scale the node.
- **Tie feature sizes to the VIEW SPAN, not fixed world metres.** A fixed wavelength is flat at
  one end of the zoom range and aliased at the other (confirmed: a 6 m wavelength was
  sub-one-cycle across a 1.7 m match view → looked flat). Make displacement/colour/detail
  wavelengths (and relief amplitude) fractions of `camera_size`.
- **View-relative wavelengths "breathe"/morph as you zoom — fix with an octave-crossfade.** Sample
  the fBm at the two power-of-two WORLD wavelengths bracketing the view-relative target and
  crossfade by the fractional `log2` (`fbm_stable()`): features are then pinned to the world
  *within* a zoom-octave and only crossfade smoothly across octave boundaries (the geoclipmap/mip
  detail-fade trick). Kills the boiling while staying equally detailed near and far.
- **One fBm field drives BOTH** vertex displacement (real relief) **and** fragment albedo/normal
  (per-pixel grain), so lighting agrees with geometry. Derive the world normal from a
  finite-difference height gradient and inject it via a varying → `NORMAL = (VIEW_MATRIX * vec4(
  world_normal,0)).xyz` (patch is unrotated). **Snap the recentre to the vertex spacing**
  (`round(pos/cell)*cell`) or the displaced silhouette swims through the fixed world field.
- Camera tilt gotcha: a downward-tilted camera sees a ground trapezoid **deeper** than
  `camera_size` is wide, so the patch margin must overreach `camera_size` (≈3×) to cover the far
  edge — but larger margin spreads the fixed grid over more area (coarser near relief), so it's a
  balance.

Reference: `kindling-3d/scripts/ground_manager.gd` + `kindling-3d/shaders/ground.gdshader`.

---

## 9. Glossy / reflective materials under the GL Compatibility renderer (verified)

Some projects run `renderer/rendering_method="gl_compatibility"` (chimera-drift). What works —
and what does NOT — for glossy, sky-reflecting materials there (verified in-engine, chimera-drift
2026-07-20, beauty-shot scene):

- **Sky IBL reflections DO work.** A material with low `ROUGHNESS` + `METALLIC` mirrors the sky
  when `Environment.background_mode = BG_SKY` and `ambient_light_source = AMBIENT_SOURCE_SKY`. This
  is how "glossy hull / glass glints off the skybox" is achieved — no screen-space reflection
  needed (SSR is unavailable in compat anyway). A bright, detailed sky matters: a near-black sky
  gives the gloss nothing to reflect, so floor the sky's star/nebula strength for a hero render.
- **Glow / bloom is NOT available in compatibility.** Bright `EMISSION` reads bright but never
  blooms. Sell "glowing" with additive billboards (a soft radial core + cross flare), a fresnel
  rim, and a vignette for focus — not `Environment.glow`.
- **In-shader billboarding works** via
  `MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0..2], MODEL_MATRIX[3])` — for sparkle
  lamps and speed-streak particle quads. `INSTANCE_CUSTOM` from a `MultiMesh` (set
  `use_custom_data = true` + `set_instance_custom_data`) reaches the shader for per-instance phase.
- **Procedural surface detail on UV-less generated hulls**: stamp panel seams / rivets / grain
  from OBJECT space, triplanar-blended by the face normal (same trick as a windows shader) — no
  UVs required.
- **Tonemap ACES works in compat**; `Environment` adjustments/glow do not — keep post to tonemap +
  exposure and do "look" polish (scrims, vignette) as `CanvasLayer` overlays.

Reference: `chimera-drift/shaders/glossy_hull.gdshader`, `glossy_cockpit.gdshader`,
`sparkle_lamp.gdshader`, `speed_streak.gdshader` + `scripts/beauty_shot.gd`.
