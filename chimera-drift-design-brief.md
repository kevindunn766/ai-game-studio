# Chimera Drift — Design Brief

**Status:** APPROVED as a living document — prototyping has started. Sections will be updated/appended as the build reveals what works; still no scope creep without flagging it here first. Title is a placeholder; swap freely.
**Genre:** Perspective-shifting procedural space shooter
**Engine:** Godot 4.7

---

## Governing Rules (Never Broken)

1. Design brief before code — this doc must be approved before any scene/script work starts.
2. Prototype first, no polish — grey-box primitives (CSGBox/CSGCylinder/MeshInstance placeholders) prove the perspective-switch and attachment systems feel good before any shader or particle work happens.
3. Lock the feature list below once approved — no scope creep without an explicit new approval, same as every other project in this studio.
4. Polish (shaders, particles, SFX/music, beauty-shot cameras) is a separate phase scheduled only after the grey-box prototype is fun.
5. Playtest before export.
6. **Camera safety (hard-learned rule from snake-3d):** the ship's visual root scales up over a run. The camera rig must never be parented under any node that gets scaled/rotated/repositioned as part of that growth — camera zoom/distance is driven by code reading an explicit `ship_scale` value and adjusting camera parameters (orthographic size / spring-arm length / FOV) directly. Never let camera framing happen "for free" via inherited parent transforms.

---

## Prototype Status (as of 2026-07-12, overnight session)

Built and verified via actual rendered screenshots (not just no-crash checks), in `chimera-drift/`:
- All five perspectives (third-person, side-scrolling, isometric, top-down, 3/4) exist as camera rigs under `Ship/CameraRigs`, all scaling off a single `ship_visual_radius` value per Governing Rule 6.
- **Implementation note on Rule 6:** the robust way to build a camera that must track a growing/moving target turned out to be script-driven `position` + `camera.look_at(target, up)` every frame, not hand-derived pivot rotation math — the latter produced a camera at the numerically-correct position but pointed at nothing useful, and the bug wasn't obvious without an actual render to look at. All non-third-person rigs use this pattern now.
- Word-seed roller (`level_seed.gd`, autoload `LevelSeed`) implementing the shape → viewpoint → feature-words pipeline described below, verified correct across multiple seeds (rolled viewpoint is always in the rolled shape's eligible set).
- All three shape families now have real grey-box generators: **Corridor** (`level_corridor.gd`, a full floor+walls+ceiling tunnel with per-viewpoint surface omission — see below), **Surface** (`level_surface.gd`, ground plane + colored feature props), and **Open Volume** (`level_open_volume.gd`, feature props scattered as a full 3D ring/disk around the flight path — no ground, no walls). `LevelDirector` picks the right one off the rolled shape family; no fallback needed anymore.
- **Superseded (2026-07-13):** isometric used to render as an occluded mess against a Corridor level (camera's diagonal sightline blocked by the flanking wall/ceiling), and this was treated as a validated shape/viewpoint eligibility restriction rather than a bug. Kevin corrected that framing — viewpoint is the primary attribute, so Corridor should adapt to fit the viewpoint rather than being excluded from it. Corridor now dynamically omits whichever surface is in the way per rolled viewpoint (see "Fine-Tooth-Comb Review Pass" section and the updated eligibility table below); all 5 viewpoints are eligible for all 3 shape families now.
- Power-up pickups exist (`power_up.gd`): an Area3D the ship's own `PickupDetector` Area3D triggers on. Every pickup grows the ship via a real mount-point attachment system (see below); one type (`speed_boost`) additionally grants a temporary forward-speed multiplier. Only these two power-up *behaviors* exist so far — the full functional roster (spread shot, homing, shields, etc.) and the large procedurally-varied cosmetic pool are not yet built, just the one working example of each tier.
- **Ship growth is now real attachments, not uniform scaling.** `Ship/Mounts` holds 6 fixed `Marker3D` points (front, rear, left, right, top, bottom) around the hull. Each `grow_ship()` call fills the next empty mount with a small distinct-colored box and only then recomputes `ship_visual_radius` from the fill count — so the ship's silhouette actually changes shape per pickup (the "cosplay" hook), rather than one placeholder box scaling uniformly. Growth naturally caps once all 6 mounts are full (confirmed: 8 pickups in a row only filled 6 and stopped, no separate cap needed anymore). Mount count/positions are placeholder-simple — real mount layout is still an open question.
- **Hazards now have real crash consequence.** First playtest feedback ("didn't seem fun") traced to zero stakes — nothing could be lost. Corridor walls and all Surface/Open-Volume feature props are now solid: hitting one crashes the ship (`Ship.crashed` signal) and stops movement. Distance traveled is the score, shown live plus on the crash/win screen. A minimal HUD (`game_hud.gd`) also now displays the current level's rolled shape word + viewpoint name, directly answering "I don't know which map type it was."
- **Notable Godot gotcha, worth remembering:** `CSGShape3D.use_collision = true` did not produce a body that `Area3D.get_overlapping_bodies()`/`body_entered` ever detected, even with correct layer/mask and confirmed via an isolated side-by-side test against a plain `StaticBody3D` (which worked immediately). Root cause not fully identified; workaround adopted instead of debugging further — every hazard generator now pairs its visual CSG shape with an explicit sibling `StaticBody3D` + `CollisionShape3D` (matching size/position) purely for collision. Also hit a second gotcha on the ship's own hazard-detection Area3D: setting `monitorable = false` (since nothing needs to detect the ship back) silently broke its ability to detect others too — removing that override (leaving it at the default `true`) fixed it. Both are now the established pattern for any future hazard/trigger volume in this project.
- **Superseded (2026-07-16):** the surface ground used to be non-lethal — a workaround for the ship spawning *inside* it. That was backwards. The ground is now **lethal** and, as of the terrain pass below, a **streamed parabolic landscape** rather than a flat plane. The real fix for the spawn problem was to spawn the ship in clear air above it (`flight_spawn_y = 3.0` for Surface); the terrain ramps in over the safe start so spawn is always over flat ground. With free flight nothing hugs the ground, so there are no constant-boundary-touch crashes — you only die if you fly into it.

## Surface Terrain — Parabolic Landscape (2026-07-16)

The flat ground plane is gone. Surface "floors" are now a **streamed heightmap**: a **parabolic valley** cross-section (walls rise toward the lane edges, framing the play area) plus **rolling hills + finer bumps** (two noise octaves). It's a pure function `_terrain_height(x,z)` so adjacent tiles share edges seamlessly; ramped in over the safe start so the ship spawns over flat ground.

- **Scaled to the level:** amplitude/character come from the **structure type** (`flat` gentle → `mountains` tall peaks, plus `hills`/`forest`/`sun_surface`/`pillared`), multiplied by the per-level `feature_scale` state and the biome `floor` color. So each surface level's landscape differs.
- **Lethal collision:** one `MeshInstance3D` + `StaticBody3D` **trimesh** per segment, on the hazard layer — verified: hovering above is safe, touching the surface crashes. (Trimesh-as-hazard already worked for holed asteroids.)
- **Everything sits on the terrain:** foliage, feature props, structure features, and enemies all sample `_terrain_height` for their Y, so nothing floats or sinks. Vertex-color height shading (valleys darker, peaks catch light) adds depth.
- Tuning: `terrain_res_x/z` (mesh density), `terrain_width_mult` (how far the valley walls sit past the lane), and the per-structure amplitude table in `_setup_terrain`.
- **Game flow now matches the Game Progression Cycle above, verified through several consecutive cycles at runtime:** `LevelDirector` rolls once per level, and death vs. win are handled differently — death (`retry_level()`) rebuilds the *same* `rolled_level` from scratch (ship and all three generators fully reset/cleared first, so no geometry survives from the failed attempt); a win (`_win_level()`, currently a placeholder distance threshold) shows a brief "LEVEL CLEAR" pause then rolls a genuinely new level. All three level generators got a `clear()`/`start()` split specifically to make this safe — `clear()` is called on *all three* generators (not just the previously-active one) before every rebuild, so a shape-family change between levels can't leave stale walls/props/ground behind from whichever shape was previously active. The earlier hardcoded-alternation script (`perspective_switcher.gd`) didn't apply to this corrected model and has been deleted rather than left parked.
- **Level generation is already streaming, not bulk-built** — each generator only spawns segments a fixed distance ahead of the ship and frees ones that fall behind, confirmed by design since the first Corridor generator. Distance-fade/pop-in mitigation (called out as a requirement, especially for third-person where geometry appears closer to camera) is **not yet implemented** — deliberately deferred as a polish-phase item per Governing Rule 2/4, not because it was overlooked.

Not yet built: distance-fade/pop-in mitigation, the real beauty-shot cinematic (current one is a 2-second freeze + text). **Updated 2026-07-17:** power-ups now stream through the whole level and attachments have real per-kind greeble variety + level-themed color (see "Streaming Power-Up Economy" section) — the remaining power-up gaps are the *functional offense/defense roster* (blocked on no weapon/health system) and *slot-typed mounts*, not the economy or cosmetic variety.

---

## Core Hook

One continuous run, one ship, five perspectives:

- **Isometric** — fixed-angle orthographic camera, classic angled top-down.
- **Top-down** — straight overhead orthographic camera.
- **3/4 view** — angled perspective camera between top-down and third-person, shallower angle than isometric.
- **Side-scrolling (2.5D)** — corridor/canyon sections, camera locked to a lateral track.
- **Third-person chase** — spring-arm camera behind the ship, full 3D framing.

**Correction (2026-07-12): a level *is* the segment.** Perspective is rolled once per level, not switched mid-level — there is no sub-level "segment chaining" concept. One level = one shape family = one viewpoint = one set of feature words, for its entire duration. Which perspectives are eligible for a given level is driven by that level's **shape family** — see Procedural Environments below.

The ship flies forward automatically at a constant base speed. The player steers within whatever degrees of freedom the current perspective allows (iso: 2D plane; side-scroll: up/down + limited depth; third-person: full 3D within a flight corridor). Speed itself is only changed by specific **boost-class power-ups** (temporary), not by player input — this keeps the "flies itself, you steer and choose upgrades" pacing from the pitch.

---

## Game Progression Cycle

1. **Game Start**
2. **Level Attributes Randomly Rolled** — the word-seed roll (shape, viewpoint, feature words), once for the whole level.
3. **Level Procedurally Established** — the matching generator builds/streams the level (see Scaling to the Ship / streaming note below).
4. **Player Plays Through**
5. **Player Wins** — reaches the level's completion condition.
6. **Ship Beauty Shots** — cinematic showcase of the current ship cosplay (see Level Transition section).
7. **Next Level** — loop back to step 2 with a fresh roll.

**Death is not step 2.** If the player dies during step 4, the level does not reroll — it restarts at step 3/4 with the exact same rolled attributes (same shape, viewpoint, feature words). Only a win advances to a newly-rolled level. This is implemented now: `LevelDirector` holds `rolled_level` across a death/retry, only calling `LevelSeed.roll_new_level()` again after a win.

Current prototype's win condition is a placeholder judgment call, not reviewed yet: reaching a flat distance threshold (`level_target_distance`, currently 200 units) ends the level as a win. The beauty shot is also currently a placeholder — a brief freeze + "LEVEL CLEAR" HUD text, not the real cinematic flythrough described later in this doc.

---

## Fine-Tooth-Comb Review Pass (2026-07-13)

Kevin asked for a close pass over view types, level structure, and the primitives used to procedurally build obstacles/enemies, picking up where the prior session left off. Findings:

- **View types (`camera_rig_controller.gd`): reviewed, no bugs found.** All four non-third-person rigs correctly use the established script-driven `position` + `look_at()` pattern (see Governing Rule 6 / the camera-in-code exception), scaling consistently off `ship_visual_radius`. Confirmed clean across multiple headless runs hitting all three shape families.
- **Real bug found and fixed — Corridor generator silently ignored feature words.** `level_corridor.gd` never implemented `configure()` at all; only Surface and Open Volume ever received rolled feature words, despite this doc explicitly describing "crystals embedded in tunnel walls" as a Corridor behavior. Fixed: Corridor now embeds feature props jutting in from either wall face at varied height, using the same color/prop-scale conventions as the other two shapes.
- **Real bug found and fixed — the ship could never fly below y=0, even in Open Volume.** `ship.gd`'s steering unconditionally clamped vertical position to `[0, limit*2]`. Open Volume's own prop generator scatters features in a full ring both above *and* below center (`y` from `-radius` to `+radius`), so roughly half of everything it spawns was permanently out of reach — undercutting the "full 3D, no ground plane" premise for that shape family. Fixed via a new `ship.allow_full_vertical` flag, set by `LevelDirector` per rolled shape family (`true` only for Open Volume), which switches the vertical clamp to a symmetric `[-limit, limit]` range matching the x-axis. Corridor/Surface behavior is unchanged.
- **Found, not fixed this pass — power-ups are static one-time scene nodes, not part of level streaming.** The three `PowerUp` nodes in `Main.tscn` are hand-placed at fixed z positions in the original scene and are never regenerated; once collected (or once the level has scrolled past them), no more power-ups ever spawn for the rest of the run, defeating the ship-growth system after the first ~45 units. This is a real gap in the pickup economy, distinct from the enemy/obstacle work this pass targeted — flagged here rather than fixed, since it needs its own design pass (spawn rate, functional-vs-cosmetic mix per level, whether density should scale like hazards do).
- **Real bug found and fixed — floor planes were sinking the ship.** The ship's visual box is centered on `position`, so its bottom half sat below `y=0` whenever the ship was at the steering floor — and every ground plane's top surface was also at `y=0`, so the floor visually swallowed the ship's lower half. Fixed with `ship.SHIP_HALF_HEIGHT` (0.5): the non-full-vertical steering clamp's minimum is now `0.5` instead of `0.0`, and `reset()` starts the ship there, so it sits on top of the floor instead of inside it.
- **Viewpoint is the primary attribute, not shape family — Corridor reworked to fit any viewpoint instead of being excluded from most of them.** Corridor previously only spawned two flanking walls and was hard-restricted to side-scroll/third-person in `ELIGIBLE_VIEWPOINTS`, since the other 3 viewpoints' cameras would be occluded by geometry. Fixed properly instead of leaving the restriction in place: Corridor now builds a real 4-surface tunnel (floor + left wall + right wall + ceiling), and `LevelDirector` tells the active generator which viewpoint was rolled (`configure_viewpoint()`); Corridor uses that to only build the surfaces that don't sit between that viewpoint's camera and the ship:

  | Viewpoint | Surfaces built |
  |---|---|
  | Third-person | floor, left, right, ceiling (all 4 — native "inside the tube" view) |
  | Side-scrolling | floor, left, ceiling (drops the near/right wall, camera sits at +X) |
  | Top-down | floor, left, right (drops the ceiling) |
  | 3/4 view | floor, left, right (drops the ceiling — no lateral camera offset) |
  | Isometric | floor, left (drops the ceiling and the near/right wall — camera is diagonal on +X, +Y, +Z) |

  `ELIGIBLE_VIEWPOINTS[CORRIDOR]` now lists all 5 viewpoints. Verified via headless runs hitting Corridor with all 5 viewpoints, no runtime errors.
- **Duplication noted, not refactored:** all three shape generators (and now `enemy.gd`) independently duplicate `_make_hazard_body()` and the `FEATURE_COLORS` map. Left as-is to avoid touching working code beyond what this pass required (existing project convention already accepted this duplication across the three generators) — worth a shared base/helper if a fourth shape family or another prop-owning system gets added.

---

## Enemies (new concept, 2026-07-13) — SUPERSEDED 2026-07-18

**Superseded by "Combat System — Enemies, Shooting, Health (2026-07-18)" below.** The
WEAVER/PULSER/HOMER "moving obstacle" roster (and the earlier HOMER-removal notes)
was torn out at Kevin's direction and replaced by a real combat system: two
categories of flying enemy (dumb/smart) plus player shooting, a health bar, and
enemy drops. The old text is kept for history only.

Previously the only hazards were static environment props (walls, scattered rocks/crystals/etc.). This pass adds real **moving** hazards — a small curated roster of enemy archetypes, in the same "small curated set" spirit as the functional power-ups (rather than a large atomic word pool, since each entry needs real behavior code, not just a color). Rolled as a new independent word category (`enemy_words`) alongside feature words: 0-2 enemy types per level, each with its own independent density (0.05-0.35), from a fixed 3-entry roster in `level_seed.gd`:

| Enemy Word | Behavior | Feel |
|---|---|---|
| **Drifting Sentries** | Weaver — slow lateral sine-wave patrol | Neutral, telegraphed, dodge-by-timing |
| **Hunting Wisps** | Homer — creeps toward the ship's current position, leashed to its spawn point | The real threat — actively closes the gap rather than waiting to be run into |
| **Pulse Mines** | Pulser — stationary, hazard radius pulses in/out over time | Timing-based dodge, danger telegraphed by visible pulse |

Implementation (`enemy.gd`), matching this project's established hazard-collision pattern but adapted for movement:
- Visual is a distinct CSG primitive per behavior (cylinder for Weaver, sphere for Homer, torus for Pulser) in a red/orange/magenta "danger" palette, distinguishing enemies from neutral feature props at a glance.
- Collision uses `AnimatableBody3D` rather than the existing `StaticBody3D` hazard pattern — `StaticBody3D` has never needed to move before in this project, and `AnimatableBody3D` is Godot 4's purpose-built node for a kinematically-moved static-type body. `Area3D` overlap detection (the ship's `HazardDetector`) works on it identically to the existing `StaticBody3D` hazards, confirmed via headless runs hitting all 3 enemy types with no detection issues.
- Each shape generator spawns/recycles enemies through the same streaming pattern already used for props (`configure_enemies()` + a `spawned_enemies` array with segment-z-based recycling), positioned per-shape: within the lane for Corridor/Surface, within the ring for Open Volume.
- Homer's leash has a floor-aware minimum (won't chase the ship below y≈0.2 in Corridor/Surface, since those shapes have a real floor/walls) versus fully unclamped in Open Volume (`has_floor: false` passed at spawn) — this follows directly from the y-clamp fix above.

Not yet built/decided: enemies currently only crash the ship on contact, identically to static props (no distinct death-by-enemy feedback, no scoring difference, no way to destroy or disable them — this prototype has no player weapons yet, so "enemy" here means "moving obstacle," not "combatant"). Whether enemies should scale in count/aggression with level number (mirroring the Hazard Density open question already logged for feature words) is open. Whether Gravity Mode's already-documented debris behavior should eventually apply to a destroyed enemy is blocked on the same thing it was before: no weapon/destruction system exists yet.

---

## Ship Cosplay / Power-Up Attachment System

This is the visual identity system: as the player collects power-ups, procedurally generated pieces fly in and physically attach to the ship, so by the end of a run the ship's silhouette is an emergent, one-of-a-kind combination of everything picked up. No two runs look alike.

To keep this scoped (per Governing Rule 3 — huge apparent variety without huge balancing/art cost), power-ups split into two tiers:

### Functional power-ups (small, curated, balanced set)
Each has a real gameplay effect and also spawns a themed attachment so its effect is visually legible on the hull (a weapon power-up's attachment looks like a barrel/emitter, a shield power-up's attachment looks like a plating/generator, etc.). Categories:
- **Offense:** spread shot, homing missiles, laser lance, nova pulse
- **Defense:** shield bubble, armor plating, damage reflect
- **Utility:** speed boost (temporary), magnet (pulls nearby pickups), perspective-lock (holds current perspective one segment longer for a tricky pass)

Exact roster size and numbers (durations, damage, cooldowns) TBD during prototyping — locked once the grey-box pass confirms feel.

### Cosmetic attachment power-ups (large, procedurally varied pool)
Purely visual greeble — fins, vents, domes, spars, thruster pods — generated with randomized parameters (scale, offset, color-per-run palette, greeble pattern) from a small set of base primitive generators. This is where "tons of power-ups" comes from cheaply: a handful of generator functions times randomized parameters produces effectively unlimited visual variety, without needing unique hand-authored art or balancing per item.

All attachments (functional and cosmetic) snap onto a fixed set of ship "mount points" defined on the base hull, so they compose predictably regardless of pickup order.

### Level-Themed Attachments (new design decision, 2026-07-13, not yet implemented)

Power-ups and the attachments they grant should be drawn from/styled after the *current level's* rolled attributes, not from one global undifferentiated pool. If a level rolls an ice-flavored word (e.g. "Frozen" modifier, or a shape/environment word like "Glacier Fields"), the parts the player collects on that level should look ice-themed (crystalline, pale blue, spiky) rather than whatever the next level's parts would look like (e.g. molten/organic/mechanical). This directly gives the Modifier Word (and shape/environment words) a real gameplay purpose beyond flavor text, and is the strongest hook so far for what the Modifier Word should actually *drive* — stronger than the previously-proposed palette-tint-only idea, though the two connect naturally (a level's theme could drive both the environment's palette *and* that level's attachment style at once from the same roll).

Implication for the two-tier system above: cosmetic attachment *shapes/behavior* stay level-agnostic (fins are still fins), but their *material/color* (and possibly which cosmetic variants are eligible to drop at all) should be selected based on the current level's theme. Not yet designed in detail — needs a mapping from modifier/shape word to a concrete "attachment theme" (color, maybe a shape-style bias), and a decision on whether functional power-ups' effects also vary by theme or just their look.

---

## Ship & Camera Scaling

The ship's overall bounding size grows as attachments accumulate over a run (more mounts filled = bigger effective ship). Camera framing must track this without ever inheriting a scaled transform (see Governing Rule 6):

- **Isometric:** orthographic `size` increases as a function of current ship bounding radius.
- **Side-scroll:** camera distance/FOV increases the same way.
- **Third-person:** spring-arm length increases the same way.

All three read the same single source of truth (a `ship_visual_radius` value recomputed whenever an attachment is added), so the three rigs stay consistent with each other when a perspective-switch cut happens mid-run.

---

## Movement Feel — Game-Feel Pass (2026-07-16, APPROVED)

The grey-box levels are full of stuff to navigate; this pass makes flying them *feel* good. Before it, steering was an instant position-slap (fixed rate, no momentum), the hull never banked, and cameras tracked rigidly with no anticipation or crash feedback. Approved feature list (locked per Governing Rule 3 — additions beyond these need a new approval):

1. **Hull banking + pitch** — the hull visual (and its mount cluster) rolls into lateral turns and pitches with vertical steering, eased in/out off the ship's actual steer momentum. Purely cosmetic: the `PickupDetector`/`HazardDetector` Area3Ds are separate siblings and stay axis-aligned, so the **collision hitbox never tilts** — only the visual does. Respects Governing Rule 6 (camera rigs are siblings of the hull, unaffected by the tilt).
2. **Steering inertia** — steering drives a `steer_velocity` that accelerates toward the input target and coasts on release (`move_toward` with a tunable `steer_accel`), instead of teleporting `position`. Momentum bleeds to zero at the flight-envelope boundary so the ship doesn't "press" into a wall. Locked axes (side-scroll X, top-down Y) still hard-lock, unchanged.
3. **Camera steer look-ahead + smoothing** — the four `look_at` cameras aim at a smoothed lead point offset toward the steer direction; the third-person chase pivot yaws/pitches slightly into turns. Camera *positions/framing distances are untouched* (Rule 6 intact) — only the aim leads.
4. **Crash screen-shake** — a trauma-based shake on the `crashed` signal, applied via each camera's `h_offset`/`v_offset` (frustum shake), so it works uniformly across all five rigs including the spring-arm third-person cam without fighting their positioning. Self-clears as trauma decays.
5. **WASD + gamepad steering** — new `steer_left/right/up/down` input actions (arrows + WASD physical keys + left analog stick), replacing the raw `ui_*` reads.

**Held out of this pass on purpose** (flagged, not silently folded in):
- **Player throttle** — the Core Hook locks speed to boost-class power-ups only ("flies itself, you steer and choose upgrades"). Not touched.
- **Health/damage vs. instant-crash** — still the Open Question judgment call for Kevin; not decided here.
- **Speed streaks / vignette / particles** — Governing Rule 4 polish phase, after the grey-box handling is confirmed fun.

Tuning constants (`steer_accel`, `max_bank_deg`, `max_pitch_deg`, `bank_sharpness`, `look_ahead`, `shake_max_offset`, etc.) are `@export`ed for playtest tuning; current values are first-guess placeholders.

---

## Procedural Environments

Sectors are generated per-run from a **word seed**, in the same spirit as snake-3d's biome system, but built from Godot's primitive/CSG toolkit plus shaders rather than tile art. Each level draws a small ordered list of words at random; the words' *roles* are positional:

1. **Word 1 — Viewpoint (2026-07-13: promoted to first, was previously rolled second).** Viewpoint is the primary level attribute — picked first, from all 5 perspectives. The level's *geometry* is then built to fit whichever viewpoint got rolled, rather than the geometry dictating which viewpoints are allowed. This directly reversed the original order: Shape used to be rolled first and viewpoint was picked from that shape's "eligible" subset, which meant most viewpoint/shape combinations were simply never generated (e.g. Corridor was locked out of isometric/top-down/3-4-view entirely). Corridor's generator was reworked to make this possible — see "Fine-Tooth-Comb Review Pass" below for how it now dynamically omits whichever wall/ceiling would occlude the rolled viewpoint's camera.
2. **Word 2 — Shape:** picks the level's structural archetype (see Shape Families below), from whichever shapes actually support the already-rolled viewpoint (see table below). This determines the geometry the level builder lays out — a corridor, a ground plane, or an open volume.
3. **Remaining words — Features:** a handful of dressing/hazard words (e.g. `mushrooms`, `rocks`, `crystals`), each rolled its own random density (e.g. mushrooms 10%, rocks 50%, crystals 40%) that tells the level builder how much of that feature to scatter into the generated geometry. Densities are independent per word, not a percentage split that has to sum to 100 — a level can be light on everything or crammed with several features at once.

### Eligible Shapes per Viewpoint (the actual roll order — `ELIGIBLE_SHAPES` in `level_seed.gd`)

| Viewpoint | Eligible Shape Families |
|---|---|
| Third-person | Corridor, Surface, Open Volume (all 3) |
| Side-scrolling | **Corridor only** — needs a wall to lock the camera to |
| Isometric | Corridor, Surface, Open Volume (all 3) |
| Top-down | Corridor, Surface, Open Volume (all 3) |
| 3/4 view | Corridor, Surface, Open Volume (all 3) |

### Shape Families (for reference — feel/flavor only, eligibility is driven by viewpoint above)

| Shape Family | Feel |
|---|---|
| **Corridor** (linear, walled, directional) | Tunneling/cave, canyon, biomechanical veins, cyber city streets, ship graveyard wreck-lanes, ancient ruin hallways. Dynamically omits whichever tunnel surface (wall/ceiling) would occlude the rolled viewpoint's camera — see "Fine-Tooth-Comb Review Pass" for the per-viewpoint surface table. |
| **Surface** (ground plane + horizon, traversal) | Planet surface, desert, swamp/forest, crystal mountain, ocean surface, glacier plains |
| **Open Volume** (full 3D, no ground plane) | Asteroid belt, surface of the sun, nebula storm, underwater, gas giant cloud layer, black hole accretion disk |

### Environment Word Pool (expanded 2026-07-13, all live in `level_seed.gd`)

**Corridor (20 words):** Tunneling Caves, Canyon, Biomechanical, Cyber City, Ship Graveyard, Overgrown Ancient Ruins, Crystal Caves, Frozen Ice Tunnels, Fungal Hive, Sunken Temple Ruins, Sewer Drainage Tunnels, Magma Tubes, Server Farm Corridors, Skeletal Ribcage Tunnels, Sandstone Slot Canyons, Wormhole Conduit, Derelict Submarine Corridors, Circuit Board Traces, Vertebrae Causeway, Coral Reef Tunnels

**Surface (20 words):** Planet Surface, Desert, Swamp Forest, Crystal Mountain, Ocean Surface, Volcanic Wasteland, Bioluminescent Reef Shallows, Scrapyard Dunes, Tundra Plains, Savanna Grasslands, Salt Flats, Lava Fields, Mushroom Forest Canopy, Glacier Fields, Ashen Wasteland, Meteor-Cratered Plains, Ruined Cityscape, Geothermal Vent Fields, Petrified Forest, Floating Lily-Pad Ocean

**Open Volume (18 words):** Asteroid Belt, Surface of the Sun, Underwater, Ion Storm, Derelict Megastructure Debris Field, Dyson Swarm Fragment, Gravity-Well Anomaly, Nebula Cloud Banks, Cometary Tail, Solar Flare Corona, Deep Space Void, Plasma Storm, Black Hole Event Horizon Approach, Space Station Debris Field, Jellyfish Swarm Waters, Kelp Forest Open Water, Cloud City Airspace, Ring System Transit

None of these are pruned yet — only Corridor/Surface/Open Volume have real grey-box generators, so most words are still purely descriptive/untested geometry-wise. Prune candidates will surface once more shape-specific geometry variation exists (right now every word in a shape family produces the *same* generic geometry for that family, just different feature-word dressing and color — see Open Questions).

### Feature/Dressing Word Pool (expanded, 30 words)

mushrooms, rocks, crystals, coral, wreckage, vents, spores, ice spires, bone piles, cabling, vines, kelp, barnacles, rust patches, neon signs, geysers, lava bubbles, ice shards, bioluminescent pods, egg clusters, broken machinery, space junk, micrometeorites, static discharge arcs, tentacles, webbing, moss, thorns, salt crystals, girders

Draws from a pool independent of shape family and the level builder applies whichever ones get rolled at whatever density each rolls — a Corridor level and a Surface level can both roll "crystals," they'll just get scattered differently (embedded in tunnel walls vs. jutting out of the ground plane vs. floating in open volume).

### Modifier Word (new attribute, 15 words)

A 4th roll, layered onto the shape word for multiplicative variety rather than more atomic words (e.g. "Frozen Canyon" vs. "Molten Canyon" vs. "Toxic Canyon" — one shape word × 15 modifiers = 15x apparent variety for free): Frozen, Molten, Flooded, Crumbling, Overgrown, Irradiated, Toxic, Ancient, Pristine, Storm-Wracked, Bioluminescent, Crystalline, Fungal-Infested, Petrified, Haunted.

**Currently flavor-only** — shown in the HUD (e.g. "Molten Asteroid Belt") but not yet wired to any visual or gameplay effect. See Open Questions for what it should eventually drive (palette tint, hazard density, etc.).

### Gravity Mode (new attribute, 2026-07-13, not yet implemented)

A rollable per-level attribute, independent of shape/viewpoint/features/modifier: **Zero-G** or **Standard Gravity**. Governs physics behavior for anything that becomes debris during the level — destroyed hazard props, shot-down obstacles, detached ship attachments, etc:

- **Zero-G:** debris has no gravity applied (`gravity_scale = 0` on its physics body) and drifts/tumbles weightlessly, carrying whatever velocity/spin it had at the moment of impact — matches the "floating wreckage in space" fantasy, especially for Open Volume shapes.
- **Standard Gravity:** debris falls normally (`gravity_scale = 1`), settling on a surface or falling out of the play volume, giving hits a heavier, more physical feel.

Only affects debris/physics-reactive props — the ship's own flight model is unaffected either way (this is not a "ship falls out of the sky" mechanic, the player always stays under normal perspective-based steering control).

Not yet decided: whether the roll should be fully independent of Shape Family or weighted by it (Open Volume + Zero-G and Surface + Standard Gravity are the most intuitive pairings, but a Corridor could plausibly be either — a station corridor with internal gravity vs. a zero-g maintenance shaft). Also not yet decided whether Gravity Mode should affect anything beyond debris (e.g. uncollected pickups drifting in Zero-G rather than sitting fixed in place).

### Scaling to the Ship

Every generated feature (tunnel width, rock size, canyon gap width, crystal cluster scale, obstacle spacing) is generated relative to the same `ship_visual_radius` value used for camera framing (see Ship & Camera Scaling above) — not a fixed absolute size. This keeps a level generated when the ship is small and a level generated later when the ship is huge both properly navigable and readable, since geometry is always sized as a multiple of "current ship," never a hardcoded number.

Base geometry: combine available primitives (boxes, cylinders, spheres, torus, CSG boolean shapes) per shape family. Shader effects for nebula volumes, energy-field distortion, hull glow/rim-light, warp streaks. Heavy GPUParticles3D use throughout (engine trails, debris, ambient dust/sparks, explosion bursts) — explicitly in scope for this project (unlike snake-3d's original "no particles" lock, which was later revised anyway).

### Other Proposed Level Attributes (not yet implemented — need a decision on which to build next)

Ideas for further rollable/derived attributes, beyond shape/viewpoint/features/modifier:

- **Color Palette / Mood** — a named palette (e.g. "Neon Cyberpunk," "Muted Earth Tones," "Alien Bioluminescent," "Monochrome Ash," "Toxic Green," "Ice Blue") that tints feature-prop colors and lighting per level. Right now every level uses the same fixed per-feature-word colors regardless of level — a palette roll would make the *same* feature word (e.g. "rocks") look different across levels/moods. Natural place to actually hook up the Modifier Word (e.g. "Frozen" → ice-blue palette, "Toxic" → toxic-green palette).
- **Hazard Density / Difficulty Scaling** — currently each feature word's density is independently random with no relationship to level number. Could instead scale up with how many levels the player has cleared, giving a sense of escalating difficulty (precedent: snake-3d's escalating per-level survival targets).
- **Level Length / Win Distance Variation** — currently a flat placeholder (200 units) for every level regardless of shape. Could vary by shape family (e.g. Corridor levels shorter/tighter, Open Volume levels longer/more of a "cruise"), or escalate like difficulty above.
- **Atmospheric Fog / Weather** — mood-setting (fog, drifting ash/snow/embers) that would double as the distance-fade/pop-in mitigation already flagged as a requirement, especially for third-person. Two birds, one shader.
- **Time-of-Day / Lighting Rig Presets** — e.g. "Dawn," "Midday," "Eclipse," "Aurora" — directional light color/angle presets, independent of or combined with palette.
- **Ambient Audio Theme** — matching soundscape per shape/modifier combo. Blocked on there being an audio system at all yet (none exists in this project currently).

None of these are built. Flagging them here as a menu rather than picking one, since each has real implementation cost and some (palette, fog) naturally connect to already-flagged open items (Modifier Word's real effect, pop-in mitigation) — worth deciding which to prioritize together rather than each in isolation.

---

## Level Transition — Beauty Shot Loading Screen

Between levels, the loading screen *is* the beauty shot: a cinematic camera plays a graceful automatic flythrough of the ship traversing the level just completed (current cosplay fully visible), while the next level's word seed rolls and its geometry generates in the background. This means:
- The loading screen has a real minimum duration (long enough to look graceful, not a spinner), separate from however long generation actually takes.
- Generation happening "behind" the beauty shot must be resilient to variable load time — if generation finishes early, the flythrough still plays its full length; if it's slow, the flythrough can loop/extend rather than cut awkwardly.
- This is also the natural place for milestone beauty shots (segment clears, boss kills, milestone attachment counts) called out in the section above — same camera system, reused rather than building a separate showcase rig.

---

## Free-Flight Movement (2026-07-16, APPROVED — supersedes the flight envelope)

The earlier per-view flight *envelope* (min/max Y bands, lateral clamp, isometric's limited-Y track, and the progression-widening of that envelope) is **removed**. The player now flies **anywhere on the axes a viewpoint makes usable** — the only boundary is the lethal level geometry (fly into a wall/floor/ceiling and you crash). What remains per viewpoint is a single binary **axis lock**, applied only to the axis that's pointless for that view (not a bounding box):

| Viewpoint | X (lateral/depth) | Y (height) |
|---|---|---|
| Third-person / Isometric / 3-4 | free | free |
| Top-down | free | **locked** (height is pointless overhead) |
| Side-scroll | **locked** (depth is pointless side-on) | free |

Implementation (`ship._handle_steering`): a free axis integrates `steer_velocity` with no clamp; a locked axis is pinned (X→0, Y→`flight_spawn_y`) with its steer velocity zeroed (so it also doesn't bank/pitch on the dead axis). `LevelDirector._configure_ship_steering` sets the two `bool`s per viewpoint; `_configure_ship_flight` sets only the **spawn height** per shape, chosen so the ship always starts in clear air above its lethal floor (Corridor mid-tube, Surface `y=3.0`, Open Volume center). There is no soft floor — every shape's ground/floor is lethal geometry, so descending into it crashes you. Verified headless: free axes unbounded (flew to 20/17+ where the old cap was ~7), side-scroll X pinned at 0, top-down Y pinned at spawn.

**Hitbox fit (2026-07-16):** free flight exposed a bad collision mismatch — the HazardDetector was a fat `radius=1.0` **sphere** while the hull is long and *flat* (half-height only ~0.26). You crashed on near-misses, ~0.75u off the visible ship vertically. Fixed: `ship._fit_hazard_hitbox()` replaces the hazard sphere with a **box fit to the rolled hull's normalized AABB** (× `HITBOX_FORGIVENESS = 0.85`, centered on the hull), rebuilt per run and scaled with `ship_visual_radius` as attachments grow. Only the hazard hitbox changed — the **PickupDetector keeps its generous sphere** so pickups stay easy. Verified: descending into the lethal ground now crashes at ~y=0 (touching) instead of y=0.9 (a unit early).

## Corridor Progression Widening (2026-07-16, geometry only)

Corridor tunnels still **open up as the level progresses** (most visible in side-scroll), but this is now purely level *geometry* — with free flight, wider walls simply mean more room before the lethal boundary; there's no player envelope to grow anymore. Self-contained in `level_corridor`: `_progress_widen(distance)` is a `1.0 → widen_factor` ramp (default **1.7**) over `[widen_start, widen_full]`, and `_tunnel_scale()` multiplies its half-width and height by it (visual + collision). No longer touches the ship. Verified headless earlier: tunnel half-width 5.0→7.8 and height 11.5→18.4 start-to-end.

---

## PNG Foliage System + Scatter Overhaul (2026-07-16)

Aesthetics phase (Governing Rule 4), opened at Kevin's request. Surface levels now carry a full foliage system, and the whole surface scatter was rebuilt from uniform-random to noise-based patches.

**Foliage assets (`tools/gen_foliage.gd` → `assets/textures/foliage/*.png`).** Seven procedurally-drawn plant PNGs — grass, clover, weed, fern, reed, bush, flower — each with its own silhouette (blades, leafleted fronds, cattail seed head, leaf clumps, petal blooms). A committed **tool** (`tools/GenFoliage.tscn`) regenerates them; add a draw function + catalog entry to extend the set. No external art dependency.

**Catalog + randomizer (`scripts/foliage_catalog.gd`).** Each type carries its own scatter behaviour: `density`, patch `threshold`, `edge_prob`, `scale_min/max` (scale falloff range), `aspect` (card w/h), `tint` (`green` = biome-tinted / `bloom` = keep PNG colours), `sway`. `FoliageCatalog.roll()` picks a **random 3–5 subset per level**, each with a random density multiplier — so which PNGs appear, and how thickly, varies per level.

**Shared patch scatter (`scripts/scatter.gd`).** `Scatter.patch()` is the fix for "solo items, no falloff": it samples a dense candidate field, gates candidates through a low-frequency noise field so they **clump into patches**, and within a patch makes them **both denser and larger toward the centre** (density falloff + scale falloff). Returns points with an `f` = 0-at-edge..1-at-centre used for extra shading. Used by BOTH foliage and the lethal feature-word props (which are now clustered with scale falloff instead of a few solo boxes).

**Render.** Foliage uses `shaders/grass.gdshader` on crossed quads (alpha-cut, wind sway + ship-pass gust via the shared `frond_player_pos`). One **MultiMesh per (type, segment)** — a single draw call each — streamed/recycled with segments. No collision (pure detail). Green foliage tints to the biome (`base_green.lerp(accent, 0.4)`), patch centres slightly brighter; bloom foliage keeps its PNG colours.

**Knobs:** `foliage_density_scale` / `prop_density_scale` (global multipliers on `level_surface`), plus every per-type value in the catalog. Verified via rendered surface shot: dense clumped foliage + clustered props with clear scale falloff. Loads at runtime via `Image.load_from_file` (robust for run-from-source; import or bundle the PNGs if the game is exported).

**Note:** only `class_name`-free scripts + `preload` consts are used for the new modules, because `class_name` globals aren't registered on a fresh headless run (no editor scan). Scope: Surface only for now — Corridor already patch-scatters, Open Volume still uniform (follow-up).

### Foliage Review — Findings & Action Items (2026-07-18)

A close review pass over the plant-prop system (`gen_foliage.gd` / `foliage_catalog.gd` / `scatter.gd` / `level_surface.gd` foliage path / `grass.gdshader`). The design is sound — patch scatter with density+scale falloff, viewpoint-aware rendering (crossed-quad cards in angled views, a real 3D tuft mesh in top-down where edge-on cards vanish), slope-gated normal-aligned planting, per-frame ship-gust global (verified updated in both corridor and surface `_process`), one draw call per (type, segment). No mesh-winding-rule issue: cards are `cull_disabled` by design.

Two safe fixes applied this pass, two items left as decisions:

- **FIXED — mipmaps.** `grass.gdshader` samples with `filter_linear_mipmap`, but the runtime `ImageTexture` had none, so dense/distant cards shimmer/alias. Now `img.generate_mipmaps()` runs before `ImageTexture.create_from_image()` in `level_surface._foliage_texture()`. (Headless dummy renderer reports `has_mipmaps=false` on the *texture* even though the *image* mipmaps generate correctly — verify the anti-shimmer visually in-editor.)
- **FIXED — per-level texture reload.** The 7 static foliage PNGs were re-read from disk and rebuilt into new `ImageTexture`s on every level build. Now cached once in a `static` dict (`_foliage_tex_cache`) and reused.
- **NOT a bug — `Image.load_from_file` vs `load()`.** An initial review flagged the runtime `Image.load_from_file` as an export bug and suggested `ResourceLoader.load()`. **That is wrong for this project** — the generated foliage PNGs are intentionally left un-imported, so `load()` returns `null` ("No loader found", verified 2026-07-18) and would make foliage vanish immediately, not just on export. `Image.load_from_file` is the correct choice for the run-from-source dev flow. **Kept as-is.** Export action item (for whoever ships the first build): either (a) commit `.import` files for the foliage PNGs and switch to `load()`, or (b) configure the export preset to bundle the raw `*.png` as non-resource files so `load_from_file` still finds them in the PCK. Left un-done deliberately — no export target is set up yet.
- **DECISION NEEDED — determinism.** `_build_foliage()` calls `scatter_rng.randomize()`, and terrain seeds off that same RNG, so **foliage and terrain are non-reproducible per run** even though the `LevelSeed` word-seed system exists. If seed-reproducible levels are intended (replays, sharing, retry-same-level integrity), seed `scatter_rng` from the level seed instead of `randomize()`. Left unchanged pending intent — this changes level feel, so it's Kevin's call, not a silent fix.

---

## Flat (Faceted) Shading Everywhere (2026-07-17)

Kevin: remove smooth shading from the landscape and all other objects — the game now reads as a consistent low-poly/faceted look. New helper `scripts/mesh_util.gd::flat(mesh)` un-indexes a mesh's triangles and gives each its own **face normal** (no smoothing). Winding note: Godot's outward normal is *anti-parallel* to `cross(v1-v0, v2-v0)` (per the CLAUDE.md convention), so the helper uses the **negated** cross — using the raw cross lights every face inside-out. Preserves per-vertex COLOR + UV and carries the source's surface material.

Applied to the smooth-shaded sources (the organic `LevelGeo` meshes were already flat via explicit per-face normals):
- **Terrain** (`level_surface._spawn_terrain_tile`) — the landscape is now faceted (verified: visible triangular panels, correctly lit).
- **Godot primitives** — surface structure features (sphere mounds / cone peaks / cylinders), open-volume rock props (spheres), enemies (cylinder/sphere/torus), pickups (box/prism/torus), and cosmetic attachments (`attachment_builder`). Verified close-up: sphere + cylinder greebles show flat panels.
- **Ship hull** (`ship._flatten_meshes`, recursive) — flattens the hull's round parts too (overriding the old "round parts smooth" choice in ShipHullGenerator).
- **CSG-baked girder** (`run_manager`) — the CSG bake was smooth; flattened after baking.

Collision is unaffected (trimesh uses the same vertex positions). **Not touched:** the sky's celestial bodies (gas giants / moons / rings) are drawn analytically in the sky shader, not as meshes — faceting those would be a separate sky-shader change (quantize the body normal) if wanted.

## Camera/Visibility Pass (2026-07-17)

Three related fixes to how the world reads on camera:

- **Tunnels are third-person only.** `ELIGIBLE_SHAPES` (`level_seed.gd`) now lets only `thirdperson` roll CORRIDOR; isometric, 3/4, top-down, and side-scroll get **Surface / Open Volume** only (enclosed tunnel geometry occludes the ship / reads badly from those angled/overhead/side cameras). Side-scroll — previously Corridor-*only* — now rides Surface/Open Volume with its depth axis still locked. Verified over 5000 rolls: **0** non-third-person corridors; third-person still gets them.
- **Nothing pops into frame.** Generators now stream well past the visible horizon (corridor `segments_ahead` 12→18 ≈108u, surface 8→12 ≈120u, open-volume 8→10 ≈120u), and **depth fog is on for every viewpoint** (was third-person only), ending at ~62u so geometry spawns *already fully faded* and eases in — no in-frustum pop-in even for the pulled-back iso/top-down cameras. `fog_sky_affect = 0` keeps the procedural sky crisp behind the fog; deep-space fog is darkened toward the void. (This finally implements the long-flagged distance-fade/pop-in requirement.)
- **X-ray ship outline — DISABLED (2026-07-17).** Intent was: show the ship's themed silhouette only when it passes behind geometry. Built as a fresnel-rim additive `next_pass` on the hull + attachments (`shaders/xray_outline.gdshader`), with an occlusion test (reconstruct the nearest surface's view-space Z from a `hint_depth_texture` uniform — note `DEPTH_TEXTURE` was removed in 4.7 — and draw only where that surface is in front of the whole ship, fed per-frame as `ship_front_vz`). In an isolated render it behaved (open = clean, behind-wall = silhouette), but in real gameplay it still read as a **permanent transparent/see-through pass on the ship**, and Kevin (twice, emphatically) wanted the ship solid. **Per his instruction it is now disabled**: `ship._apply_xray()` early-returns so the next_pass is never attached and the ship renders fully solid (verified). Shader + plumbing (`set_theme_color`, `_update_xray_depth`) are left dormant for a future fix — re-enable by restoring the next_pass assignment in `_apply_xray`. Likely-remaining bug if revisited: the depth→view-Z reconstruction (`ndc.z = d` vs `d*2-1`) may be off for the in-game ortho/perspective cameras, causing it to draw when it shouldn't.
- **3/4 landscape extends left/ahead (`level_surface.gd`).** The 3/4 camera sits above + right and looks down-*left*, so the surface's left-ahead corner ran off the mesh (a hard cull edge in the upper-left). Fixed for the 3/4 view only: `configure_viewpoint` is now honored on Surface, and `_setup_terrain` pushes the terrain mesh's x-min to `-_terrain_hw * three_quarter_left_extend` (3.2×) plus a few extra segments ahead — column count scales with the span so density holds, and the valley shape (`_terrain_height`) is unchanged, so the extra span reads as distant highlands fading into fog. Verified against a bright Pristine daytime 3/4 level (upper-left now fills to the fogged horizon). Note: side-scroll on Surface (new, since tunnels moved to third-person-only) could want a similar side extension if it shows the same edge — not reported yet, left as a follow-up.

## Procedural Skybox System (2026-07-17, APPROVED — all 5 phases, physically-based)

A 100%-procedural, shader-driven sky, rolled uniquely per level and themed to the level's own words. No textures — everything is seeded uniforms into one über sky shader. Built all phases in one pass at Kevin's direction (research brief delivered first; he chose "everything" + "more physically-based"). Verified via rendered shots: daytime blue atmosphere, grey overcast for grey modifiers, and deep space with themed nebula + a banded gas giant showing a real day/night terminator + stars + sun glow.

**Shader (`shaders/procedural_sky.gdshader`, `shader_type sky`).** Layers back-to-front: deep-space base (nebula + galaxy + Milky Way + stars) → **physically-based single-scattering atmosphere** (Rayleigh + Mie ray-march, ~16 primary / 6 light samples; adapted Nishita/wwwtyro model) → **celestial bodies** via analytic ray-sphere → **clouds** + in-sky god rays → **sun disk** (limb-darkened) + Mie aureole. Techniques: FBM + Inigo-Quilez domain warping (clouds, nebula, gas-giant turbulence); hash starfield with blackbody color + twinkle; log-spiral galaxy (`cos(N·θ − k·ln r)` + bulge + dust lanes); gas giants = latitude-banded domain-warped surface + a Great-Red-Spot storm oval, lit with a Lambert terminator; **ringed planets** = ray-vs-ring-plane annulus with radial bands + ring-shadow-on-planet + planet-shadow-on-ring; moons = crater FBM. The IBL **cubemap pass runs a cheaper path** (fewer scatter samples, no sharp stars/bodies), and the `Sky` uses incremental processing + 128 radiance to keep ambient/reflection affordable.

**SkyDirector (`scripts/sky_director.gd`).** Deterministic per-level seed (hash of the level's own words) drives an RNG that picks an archetype and pushes every uniform. **Gated to Surface + Open Volume** (where the horizon/background is visible); Corridor keeps its flat fog background. Reuses the rolled **`LevelTheme` palette** so the sky belongs to its level:
- **Surface** → atmosphere + a rolled time-of-day (day / sunset / night, biased by modifier — Haunted→night, Molten→sunset), themed sun color, clouds (variable cover), stars + Milky Way at night, occasional moon/ringed planet on the horizon.
- **Open Volume** → deep space: dense stars, sometimes a galaxy, nebula strength keyed to the flavor word (Nebula/Ion Storm/Corona → strong), 1-3 gas giants / ringed planets / moons, and a big bright sun for sun-flavored words.

**Integration (`level_director.gd`).** New `_configure_environment()` switches the `WorldEnvironment` to `BG_SKY` (+ sky ambient/reflection) for sky levels and orients the scene `DirectionalLight3D` to the rolled sun so the shader's `LIGHT0` and the scene lighting agree; non-sky levels restore the captured default light + flat fog. Depth fog (third-person pop-in) is kept in both.

**Open / tuning:** the surface atmosphere reads a touch pale for some palettes (a saturation lift is in; richer tuning + cloud density/lighting + body albedo are `@export`/uniform knobs for playtest feedback). This is a heavy per-pixel shader — watch cost on lower-end GPUs; the cheap-IBL-pass + incremental radiance are the main mitigations. God rays are an in-sky Mie approximation (a true screen-space light-shaft pass is a possible later add). Not yet wired into the beauty-shot loading screen (natural reuse).

## Performance Auto-Rating — First-Launch Quality Tiers (2026-07-17)

`PerfProfile` autoload (`scripts/perf_profile.gd`) runs **once on first launch**, best-guesses a hardware performance rating, caches it to `user://perf_profile.cfg`, and derives three quality knobs the game reads. Later launches just load the cache. Delete the cfg (or call `PerfProfile.rerate()` — e.g. from a future settings menu) to re-detect.

- **Rating (heuristic, not a live benchmark — instant, vsync-proof):** GPU name string classification (software → weakest; GeForce/RTX/GTX/Radeon RX/Arc/Apple M → discrete; Intel/Iris/UHD/Radeon iGPU/Vega → integrated; unknown → assume capable) + CPU core count + system RAM → a score → `LOW / MEDIUM / HIGH / ULTRA`. Under GL Compatibility the adapter *type* is unreliable, so the name is the primary signal. Bias is intentionally toward the top so capable machines top out.
- **Knobs:** `sky_quality` (0-3 → sky ray-march sample counts via a `quality` shader uniform, star layers, and `Sky.radiance_size` 32→256), `particle_scale` (procedural particle amounts; 0 on LOW), `view_distance_scale` (how many segments each generator streams ahead). Wired into: the sky shader + SkyDirector, corridor vent exhaust particles, and all three generators' stream-ahead (`_ahead`).
- **This laptop (AMD Radeon 780M iGPU) rates ULTRA** → full quality, no visible change; the tiers only scale *down* on weaker hardware. Verified on boot (`[PerfProfile] tier=ULTRA ...`).

## Deferred Work / Notes for Later (2026-07-17)

Explicitly parked, to build when their prerequisites land or the polish phase reaches them:

- **True god rays (screen-space light shafts).** The sky currently fakes crepuscular rays with an in-sky Mie approximation only. A real version needs a **post-process radial blur from the sun's screen position masked by occluders**, or a `CompositorEffect` / volumetric light-shaft pass. Deferred because it's a full-screen post pass (heavier, and GL Compatibility limits some compositor features) — worth it once the look is locked.
- **Beauty-shot loading screen** — reuse the new procedural sky + a cinematic flythrough camera showing the current ship cosplay (today it's a 2s freeze + "LEVEL CLEAR" text).
- **Volumetric clouds / volumetric fog** — the cloud layer is a 2D sky-plane projection; true volumetrics (or Godot `volumetric_fog`) would give depth and double as pop-in mitigation.
- **Surface atmosphere richness / cloud lighting / body albedo tuning** — all uniform/`@export` knobs, left first-guess for playtest feedback.
- **Sky half-res pass** for the heaviest layers (nebula/clouds) if a weaker GPU needs it (framework already branches on the IBL pass).
- **Functional offense/defense power-up roster** (spread shot, homing, shields, nova…) and **destroyable enemies/meteorites** — both blocked on there being no weapon/health system yet.
- **Slot-typed mounts** (weapon vs cosmetic) — every mount currently accepts any greeble.
- **Pickup-vs-hazard overlap dedupe** — a streamed pickup can rarely spawn inside a lethal prop.
- **Settings menu** to surface/override the perf tier and toggle effects.

## Collision Fidelity Pass — Trimesh (Mesh) Collision Everywhere (2026-07-17)

Per Kevin's directive, every **solid** item's collision is now a **trimesh of that item's own visual mesh** (`ConcavePolygonShape3D`), not a box/sphere/cylinder or convex-hull approximation — so what you see is exactly what you crash into. New shared helper `scripts/hazard.gd` (`trimesh_body(mesh, xform)` / `trimesh_shape(mesh)`) builds the collision from the visual mesh at the visual's transform. Trimesh-vs-`Area3D` detection was already proven here (streamed terrain, holed asteroids); this pass extends it to *everything*. Verified in-engine: teleport-onto-hazard crash tests pass across all 3 shape families **and all 3 enemy archetypes** (including the moving `AnimatableBody3D` enemies and the **scaled pulser torus**).

Converted (was → now):
- **Corridor** walls/ceiling/floor (straight bounding boxes → trimesh of the actual curved arch ribbons + floor strip), feature props (sphere → trimesh of the lumpy prop mesh), the spanning girder (box → trimesh of the girder mesh), pillars (cylinder → trimesh of the waisted pillar mesh).
- **Surface** feature props (`CSGBox`+box → `BoxMesh`+trimesh) and **structure features** — this fixes a real mismatch: mountain **cones** and forest/pillar **cylinders** used to collide as coarse **spheres**; they're now `CSGCylinder`→`CylinderMesh`/`SphereMesh` with an exact cone/cylinder trimesh.
- **Open Volume** props (`CSGSphere`/`CSGCombiner`+sphere → `SphereMesh` or `holed_asteroid` mesh + trimesh; the hole in a holed rock is now genuinely passable).
- **Enemies** (`enemy.gd`): CSG cylinder/sphere/torus → `CylinderMesh`/`SphereMesh`/`TorusMesh` on the `AnimatableBody3D`, collision = trimesh; the pulse mine animates by uniformly scaling the mesh + trimesh together.

**Supersedes the old CSG-collision workaround.** The project no longer pairs a CSG visual with a primitive sibling body — CSG is gone from hazards entirely, replaced by real meshes whose trimesh is the collision. (The old note about `CSGShape3D.use_collision` never registering with `Area3D` is now moot for hazards.)

**Exemptions (by design, not oversight):** foliage (already collision-free) and **fronds** — now also collision-free pass-through plant decoration (previously a lethal sphere); the ship's own hazard hitbox stays a deliberate **forgiveness box** fit to the hull (crashing on the exact hull mesh would be brutally unfair); and **meteorites** keep a primitive sphere because they're dynamic `RigidBody3D`s, which Godot forbids from using concave/trimesh shapes — and their ship-crash is a manual closing-speed distance check anyway, not the collision shape. Pickup detection stays a generous trigger sphere (it's a reach volume, not an obstacle).

**Note (behavior nuances of mesh collision):** a trimesh is a *surface*, so collision registers when the ship crosses the visible surface (correct for fly-into-it gameplay) rather than by solid-volume containment; and pulse mines now have a **passable center hole** (dodge through the ring) since the torus mesh is the collision. Both are intentional consequences of "collision = the mesh." Watch on-device perf: trimesh shapes are heavier than primitives, though the per-frame prop-spawn cap and broadphase keep narrow-phase tests local to the ship.

## Side-Scroll No Longer Spawns Homing Wisps (2026-07-17)

In side-scroll the ship's **depth (X) axis is locked**, so the HOMER enemy ("hunting wisps," a homing sphere) slides straight onto the flight line and matches the ship's height — effectively undodgeable, and it reads as a "line of spheres moving directly in front of the ship." `level_corridor._spawn_enemies` now skips HOMER when the rolled viewpoint is `sidescroll` (weavers/pulsers still spawn). Verified deterministically: side-scroll → 0 homers / other enemies intact; third-person → homers intact. (Side-scroll is Corridor-only, so this one guard covers it.)

## Streaming Power-Up Economy — Ship-Cosplay Hook Revived (2026-07-17)

The core "ship cosplay" identity hook was **dead in the running build**: the old hand-placed `PowerUp` scene nodes had been removed from `Main.tscn`, and no generator ever spawned replacements, so `grow_ship()` never fired — the ship stayed base-hull for an entire run. This pass rebuilds power-ups as a real streamed economy and delivers the "no two runs look alike" payoff. Verified in-engine (targeted Area3D-overlap integration test across all 3 shape families → ship grows to full 6/6; rendered screenshot of a grown ship confirms the greebles read as distinct themed parts).

- **`PowerUpStreamer` (`scripts/power_up_streamer.gd`).** A shape-agnostic streamer (sibling node, owned by `LevelDirector` with `clear()`/`configure()`/`start()` around every level build, exactly like the three generators). It spawns pickups ahead of the ship and recycles them behind, at a jittered `spawn_interval` (~18 units) past the shared `SAFE_START_DIST` runway. It's blind to shape geometry — it asks the **active generator** for a navigable point via a new `reachable_point(z, rng)` method each generator now implements (Corridor: inside the tube cross-section; Surface: floating a reachable height above the lethal terrain near lane center; Open Volume: within the inner half of the ring). So pickups always sit in flyable space, whatever shape rolled.
- **Pickup mix (first-guess, flagged for tuning).** Each pickup rolls cosmetic (65%) / `speed_boost` (20%) / `magnet` (15%). Those are the only two *functional* effects buildable today — the offense/defense roster (spread shot, homing, laser, nova, shield, armor, reflect) is still blocked on there being no weapon/health system, and `perspective-lock` is moot now that viewpoint is per-level. Density does **not** scale with level number yet (still an open question).
- **`magnet` functional power-up (new).** While active (`ship.magnet_active`, timed), uncollected pickups sense it and drift toward the ship once in range (`power_up.gd::_process`). Pure pull assist — no physics on the ship itself. Joins `speed_boost` as the second working functional example.
- **Attachment visual variety (`scripts/attachment_builder.gd`).** `grow_ship()` no longer bolts on an identical plain box. Each filled mount now gets a distinct greeble silhouette built from Godot **primitive** meshes (grey-box discipline; primitives carry correct built-in winding/normals so the CLAUDE.md mesh rule doesn't apply): `barrel` (thruster/emitter, granted by speed_boost), `dome` (dish, granted by magnet), and cosmetic `fin`/`pod`/`spar`/`vent`/`plate`. Each is modeled along +Y and reoriented to its mount's **outward** direction (stable 3-axis basis with a near-vertical fallback — avoids the degenerate shortest-arc case that's bitten this repo before), so parts splay away from the hull instead of all pointing up.
- **Level-Themed Attachments — implemented (was a 2026-07-13 design decision, previously not built).** Pickup glow *and* the hull greeble both take the current level's rolled **theme accent** color (with small per-pickup hue jitter), so a run's accumulated parts read as belonging to the levels they were collected on. Shapes stay level-agnostic (a fin is still a fin); only material/color is themed, exactly as the two-tier design specified.
- **`power_up.gd` is now self-contained + code-built** (the streamer instantiates it, sets `kind`/`effect`/`attach_color`/`ship`, and it builds its own collision + emissive spinning visual in `_ready`). Detection uses the established pattern: the ship's monitorable `PickupDetector` (layer 2, group `ship_pickup_detector`); the pickup monitors layer 2 and never touches the hazard layer. HUD now shows a live `Parts: X/6` counter.

**Still not built:** density/level-number scaling of pickups, functional offense/defense effects (blocked on weapons/health), and slot-type mounts (every mount still accepts any greeble — mount layout is still the placeholder 6). A rare pickup can spawn overlapping a lethal hazard prop (both scatter across the lane); acceptable for grey-box, flagged for a later reachability-vs-hazard dedupe pass.

## Level State Machine — Per-Level Personality + Anti-Repeat (2026-07-16)

Before this, `LevelSeed.roll_new_level` was a **stateless** roller: it varied the *words* (viewpoint, shape, structure, modifier, feature/enemy words + densities) but every generator's numeric scatter/geometry settings were **hardcoded constants**, so the *feel* (how dense/clumpy/big) was identical on every level of a type — and nothing stopped two consecutive levels sharing viewpoint+shape+structure. Fixed on two fronts:

**Per-level state (`LevelSeed.roll_state`).** Each roll now also produces a `state` dict of numeric knobs rolled within shape-family-appropriate ranges — common: `density` (sparse↔lush), `feature_scale` (dainty↔chunky), `clumpiness` (patch threshold: spread↔tight), `patch_freq` (big↔small patches); plus per-type: Corridor `tunnel_width`/`tunnel_breath`/`widen_factor`, Surface `lane_width`, Open Volume `ring_radius`. `LevelDirector` passes it via a new **`configure_state()`** on all three generators, which apply it to their scatter/geometry. Every value has a neutral default, so a generator still works if it isn't called. So each level now has a distinct scatter *personality*, not just different words/colors.

**Anti-repeat memory (the actual state machine).** `LevelSeed` keeps `_prev` (last level's viewpoint/shape/structure/modifier). A fresh roll is forced to differ: **viewpoint never repeats** back-to-back (most visible attribute), **modifier never repeats** (so palette/mood shifts every level), and if the **shape repeats the structure is forced to change**. Verified headless over 10 consecutive rolls: 0 consecutive viewpoint repeats, 0 modifier repeats, distinct numeric state each level, and shape-repeats always differ in structure.

Note: the `_prev` memory makes rolls history-dependent, which slightly complicates a future pure-seed "daily run" (an Open Question) — a seeded mode would reset `_prev` per run. Also this resolves the old "Modifier Word is flavor-only" note in two ways: it already drove the palette via `LevelTheme`, and now it also guarantees mood variety via anti-repeat.

---

## Combat System — Enemies, Shooting, Health (2026-07-18, APPROVED, built)

Kevin's direction, built this pass. Old enemy work (WEAVER/PULSER moving obstacles)
was removed as it didn't fit; what follows is the design, captured as given.

**Scope of this build (locked per Governing Rule 3):** flying enemies (smart + dumb),
a health bar, player shooting with a weapon-tier ladder, and enemy drops. **Stationary
turrets, mines, pushing hazards, and slow-damage hazards are the NEXT pass** ("let's
build this then we'll talk about mines, stationary turrets and hazards") and are NOT
built here.

There will be flying enemies and stationary enemies (turrets). There will also be
various hazards like pushing hazards, mines and slow damage hazards. We need a health
bar. There are two main categories of flying enemy: **smart** and **dumb**.

- **Dumb** enemies have simple moving patterns — they just move past you with some
  type of pattern or clustering and/or shooting. They are made from brightly colored
  level objects and radial in structure (e.g. a ring of mushrooms linked together at
  their bases), constructed on a level-by-level basis. They drop power-ups that
  temporarily enhance your shooting from single to double to triple then to spread.
- **Smart** enemies are constructed using the ship build pipeline but with a color
  theme that matches the level (constructed level-by-level when the level attributes
  are rolled). They are smart enough to weakly dogfight with the player. They drop
  pieces that can be picked up by the player and added to their ship; these pieces
  permanently improve the ship — shielding, rate-of-fire upgrades, and afterburners
  that give the player a short boost.

**Implementation (built + verified in-engine 2026-07-18):**

- **Collision layers (`combat.gd`).** New independent bits on top of the existing
  pickup(2)/hazard(4) scheme: enemy hurtbox = 8, player shot = 16, enemy shot = 32.
  The ship gained a `CombatDetector` Area3D (mask 8|32) that applies contact damage
  from enemy bodies and consumes enemy shots. Player shots (Area3D, mask 8) damage
  enemy hurtboxes. Environmental wall/floor crashes are unchanged (still instant via
  the HazardDetector) — the health bar governs *combat* damage.
- **Health + shield (`ship.gd`).** `MAX_HEALTH=100`, shield absorbs before health,
  `take_damage()` with a short i-frame, death routes through the existing `crash()`
  so the retry flow is unchanged. `health_changed` drives a HUD health bar + shield bar.
- **Shooting (`ship.gd`, `projectile.gd`).** Held-fire auto-shoots forward (`fire`
  action = J / Space / LMB / gamepad). Weapon tier 1→4 = single/double/triple/spread
  fan; the tier is a **temporary** buff that decays a step after a lull. Permanent
  rate-of-fire upgrades divide the fire interval. `afterburner` action (K / gamepad)
  triggers a short boost once unlocked, on a cooldown.
- **Dumb enemy (`enemy_dumb.gd`).** A bright radial ring of the level's own feature
  objects (mushroom/crystal/blob/… per the rolled feature words), linked at their
  bases by a central hub ring, spinning + bobbing as the world scrolls it past, with
  an optional shot. Drops `weapon_up` (temporary tier bump, does not consume a mount).
- **Smart enemy (`enemy_smart.gd`).** A procedural ship from `ShipHullGenerator`,
  recolored to the level accent, that holds a standoff, strafes, slowly turns to face,
  and fires loose-aimed shots (weak dogfight). Drops a **permanent** piece —
  shield / fire-rate / afterburner — which also bolts a themed greeble onto the hull.
- **Roll (`level_seed.gd`).** `ENEMY_KINDS = ["dumb","smart"]`, each rolled
  independently per level with its own density (`ENEMY_ROLL`); streamed by all three
  generators through the existing enemy-streaming path (`EnemySpawner.create`).
- **Verified:** headless boot + 2000-frame run clean across shape families; a focused
  smoke test confirms both enemy types build (incl. the smart hull), take damage, die,
  and drop; a rendered Surface shot shows the green radial dumb-rings + themed smart
  ships + health bar reading correctly.

**Still open / next pass:** stationary turrets, mines, pushing hazards, slow-damage
hazards; enemy-count/aggression scaling by level number; tuning of all combat numbers
(placeholders); slot-typed mounts. Permanent upgrades reset on a death-retry (same as
attachments), i.e. "permanent" within a single life.

## Mines + Explosion VFX (2026-07-18, APPROVED, built)

Kevin's next combat pass — mines (the first of the deferred hazard set), plus death
particles for everything. Captured as given:

The mines are just a simple disk with a glowing center on both the top and bottom
that matches the level color theme. They can randomly spawn in lines that are
vertical, horizontal, and diagonal, or in a shape like a ring or diamond. They damage
each other, enemies and the player's ship — so if you shoot one it causes the entire
ring to explode, and any enemies near it. When they explode there is a particle system
that is first a bright flash then a plume of smoke. That same explosion was added to
the death of all the other enemies too.

**Implementation (built + verified in-engine 2026-07-18):**

- **`explosion.gd`** — reusable detonation VFX from **CPUParticles3D** (chosen over
  GPUParticles for guaranteed GL Compatibility support). Self-frees; `scale_ref` sizes it.
  **Reworked to 3 particle types (2026-07-18/19, Kevin):**
  (1) **BURST** — bright RED and YELLOW bits (two coloured emitters) that radially fly out
  in all directions; (2) **SPARKS** — small bits that fling out and **fall**, then
  **flicker** at the end of the fall (a flicker alpha gradient over the last ~40% of life);
  (3) **SMOKE** — a randomly-sized plume that starts **bright + fiery**, then **cools**
  through orange/red to **dark grey and black** as it **rises** and fades (its `color_ramp`
  runs fiery -> ember -> grey -> black). All medium-to-small and randomly sized (per-particle
  `scale_amount` range + a random per-blast plume scale). Verified rendered across three
  frames: red/yellow radial burst, sparks fallen below + flickering, smoke risen and cooled
  to near-black.
- **`mine.gd`** — a flat disk (short cylinder, faces along the travel axis) with an
  emissive glowing center on each face in the level accent (gentle pulse). It's
  shootable (1 HP) and also detonates on player proximity. `explode()` plays the VFX
  and applies a blast: damages the player if in range, **destroys** enemies in range,
  and **chain-detonates** nearby mines after a short ripple delay — so one shot takes a
  whole formation. Chain radius is set to just over the formation spacing so the blast
  ripples along the formation instead of jumping between separate ones.
- **`mine_field.gd`** — lays a formation around a navigable point in the plane facing
  the player: `line_v` / `line_h` / `line_d`, `ring`, `diamond`.
- **Roll + streaming** — `level_seed` rolls a per-level `mines` density (50% present,
  0.12–0.35); each generator streams formations through the existing enemy path
  (`configure_mines` + `_spawn_mines`, per-segment chance = density, placed at a
  `reachable_point`). The three enemy recyclers were hardened to skip
  self-freed nodes (`is_instance_valid`), since enemies/mines now free themselves on
  death/detonation.
- **Verified:** headless boot + 2500-frame run clean; a smoke test builds a 12-mine
  ring, detonates one, and confirms all 12 chain-explode with VFX (and that a normal
  enemy death also bursts an explosion); rendered shots confirm the disk + glowing-
  center look (theme-tinted) and the detonation flash, with the chain correctly staying
  within a single formation.

**Still to do next (Kevin's list):** stationary turrets, pushing hazards, and slow-damage
hazards. All mine/explosion numbers are first-guess placeholders (blast/chain radii,
density, damage).

## Slow-Damage Hazards — Fields, Leeches, Graspers (2026-07-18, APPROVED, built)

Kevin's spec for the slow-damage hazards, captured as given, and built this pass.
These deal **damage-over-time** (a new `ship.take_dot()` channel — small per-frame
health bleed, shield-first, NOT gated by the combat i-frame), distinct from the
instant wall-crash and the mine burst.

The slow-damage hazards come as three types — Fields, Leeches, and Graspers.
- **Fields** are clouds of particles that either just hang out like a cloud of hot
  mist, or come from something like a volcano or hot vent.
- **Leeches** fall down from tunnels at you and latch on, or leap up at you from the
  landscape.
- **Graspers** are a tentacle / vine or something like that.

**Implementation (built + verified in-engine 2026-07-18):**

- **`hazard_field.gd`** (Node3D, not destroyable) — a CPUParticles3D cloud in one of
  two variants: `mist` (a sphere of slow-drifting haze) or `vent` (a dark cone
  vent/volcano mouth with a rising plume). Warm "hot" tint (accent pushed toward fiery
  orange, a deliberate look choice). DOT while the ship is inside the cloud radius.
- **`hazard_leech.gd`** (enemy_base creature, destroyable) — spawns dormant at a
  tunnel ceiling (`drop`) or on the landscape (`leap`); when the ship comes near it
  launches, homes on, **latches** (rides the ship) and drains DOT for a few seconds,
  then releases and pops. Shootable in its dormant/launch phase.
- **`hazard_grasper.gd`** (enemy_base creature, destroyable) — a rooted, writhing
  **tentacle/vine** built as a chain of tapering segments (traveling-sine sway); when
  the ship enters reach it leans toward the ship and grasps, draining DOT while the
  ship stays close. Its hurtbox is lifted to mid-length so shots along the body land.
- **`hazard_spawner.gd`** — factory mirroring EnemySpawner. Roll (`level_seed`):
  each type rolls its own presence + density (`HAZARD_ROLL`); generators stream them
  shape-appropriately — Fields anywhere (incl. drifting in Open Volume); Leeches +
  Graspers only on Corridor/Surface (they need a ceiling/ground to come from), with
  leeches set to `drop` in tunnels and `leap` on the landscape. `configure_hazards`
  + `_spawn_hazards` on all three generators, streamed via the shared enemy list.
- **Verified:** headless 3000-frame run clean; a smoke test confirms each type deals
  DOT, the leech reaches its latched/drain state, the grasper builds its 7-segment
  tentacle and grasps, and leech/grasper are destroyable (pop the explosion VFX) while
  the field is not; a rendered shot confirms the vine grasper, the tendrilled leech,
  and the warm mist + vent clouds.
- **Bug fixed this pass (pre-existing, from the combat build):** the smart enemy's
  per-frame `Basis.slerp` accumulated float drift and eventually failed the Quaternion
  cast; now both bases are `orthonormalized()` before the slerp.

## Turrets + Pushing Hazards — Hazard Roster Complete (2026-07-18)

The last two hazard types from Kevin's list, so the full roster is now built:

- **Stationary turret (`turret.gd`, enemy_base).** A rooted pedestal + a head/barrel
  that tracks the player (fresh `look_at` each frame -> no drift) and fires on a
  cadence via the shared projectile. Destroyable -- pops with the explosion VFX.
  Danger-tinted from the level accent. Spawns rooted on corridor floor / terrain, and
  **floating in open volume** (a gun platform needs no surface).
- **Pushing hazard (`hazard_push.gd`, environmental).** A rooted vent/geyser that
  periodically ERUPTS and shoves the ship away (up + outward) while it's in range --
  it doesn't damage, it knocks you off course (into a wall / another hazard). The
  eruption is telegraphed by a particle plume that only streams during the active
  window. Not destroyable (like the field). New `ship.apply_push()` displaces the
  ship respecting the per-view axis locks. Corridor floor / terrain (surface-rooted).
- **Roll/stream:** both added to `HAZARD_ROLL`; generators place them (open volume
  takes field + turret only). Enemy_base hazards get `.world` for their death VFX via
  an `"world" in h` check (fields/push are plain Node3D).
- **Verified:** headless 2600-frame run clean; smoke test confirms the turret aims +
  fires + is destroyable and the push shoves the ship (~2u) + is not destroyable; a
  rendered shot shows the aimed turret and the erupting vent plume.

**Full hazard/enemy roster now built:** flying enemies (dumb radial + smart
dogfighters), stationary turrets, mines, and slow-damage fields/leeches/graspers, plus
pushing hazards. All numbers (DOT/push rates, ranges, densities, fire cadence, latch
timing) are first-guess placeholders.

## Zoom-Out + Off-Center Framing for Reaction Room (2026-07-18)

Kevin: with no autopilot the ship reaches obstacles fast; give more room to react.
Fix = zoom every camera out (everything smaller) and, for side-scroll + top-down,
push the ship toward the near edge (left / bottom) so more of what's AHEAD is on
screen. Camera culling + map generation adjusted so the wider view doesn't reveal
edges or pop-in. (Reminder honored: iso zooms via orthographic `size`, not distance.)

- **`camera_rig_controller.gd`** — new `zoom_out` (1.6) multiplies every rig's pull-
  back: perspective rigs (third-person, 3/4, side-scroll) increase distance; the
  orthographic rigs (iso, top-down) increase **`size`** (distance scaled too only for
  near/far clearance). New `side_scroll_screen_shift` / `top_down_screen_shift`
  translate the camera **and its aim** toward the ship's travel direction (-Z), so the
  ship rides screen-left (side-scroll) / screen-bottom (top-down) with the framing
  angle unchanged. Governing Rule 6 intact — still script-driven position + look_at
  off `ship_visual_radius`; the shake stays on `h/v_offset`, independent of this.
- **Culling / generation follow-through so it doesn't throw things off:**
  - Fog band pushed out (`level_director`): begin 18→28, end 62→100, so the enlarged
    view isn't over-fogged while still masking pop-in.
  - Stream-ahead kept past the farther fog end: corridor 18→20, surface 12→15,
    open-volume 10→12 segments (all still spawn beyond the fog, so geometry eases in).
  - Surface terrain widened (`terrain_width_mult` 1.5→2.0) so the wider zoomed-out
    ortho views never reveal a terrain edge. Camera `far` (300) already covers.
- **Per-view ship placement (2026-07-18, extended):** Kevin refined where the ship
  sits per view. **Iso + 3/4 → lower-LEFT corner**; **third-person → centered but a
  touch below the midpoint**; side-scroll (left) and top-down (bottom) unchanged. Iso
  and 3/4 use a general 2-axis screen-space offset — `_screen_offset(fwd, up)` derives
  screen-right/up from the view direction and translates camera + aim by
  `(+right, +up)` (perpendicular to view, so framing scale is unchanged), pushing the
  ship down-left. Third-person uses a base frustum `v_offset` (`third_person_lower`),
  with crash shake added on top. All corner/offset amounts are `@export` fractions.
  **Tuned down (2026-07-18):** the first values pinned the ship to the very edge; the
  offsets were reduced (side-scroll 0.9→0.5, top-down 0.42→0.24, iso 0.6/0.34→0.36/0.22,
  3/4 0.52/0.32→0.34/0.2) so the ship sits toward the edge/corner with a clear margin.
- **Third-person pulled in close (2026-07-18):** Kevin wanted the ship big in
  third-person (~1/3 of the screen). Its spring length is now `third_person_base_distance`
  (2.15) × radius and is deliberately **not** multiplied by `zoom_out` (that global
  pull-back is only for the angled/overhead views). Still scales with `ship_visual_radius`
  so the ship holds its on-screen size as it grows.
- **Verified (rendered):** top-down → ship bottom, side-scroll → ship left, iso → ship
  lower-left, 3/4 → ship lower-left, third-person → ship just below center; all clearly
  zoomed out; a surface isometric fills edge-to-edge with no revealed terrain edge or
  pop-in. Headless runs clean.

## Biome Table Wired In + PNG Foliage Removed (2026-07-18)

Kevin: wire the whole `biome_attribute_table.csv` into the game, and get rid of the
.png-card foliage (it didn't match the low-poly style — detail will come from other
processes later). Both done.

- **PNG-card foliage removed.** The crossed-quad `.png` grass/foliage system (cards +
  top-down tufts + `grass.gdshader` + `foliage_catalog.gd` + the foliage PNG assets +
  the `GenFoliage` tool) is deleted from `level_surface`. The shared scatter RNG/patch
  noise the terrain + feature-prop scatter need was kept (moved into `_init_scatter`).
  Surfaces now read as clean faceted terrain + 3D feature props.
- **CSV is now the content source (`biome_table.gd`).** Parses all 54 biomes ->
  `{structures, views, gravity, enemies[3], objects[10]}` (FileAccess CSV, headless-safe,
  cached). `LevelSeed.roll_new_level` is rebuilt around it: pick a biome (anti-repeat),
  then a valid **(structure→family, viewpoint)** combo honoring the corridor=third-person
  camera rule, its **gravity**, a random subset of the biome's **10 objects** as the
  feature words, and its **enemy names**. The old generic word pools (SHAPE_WORDS,
  FEATURE_WORDS, STRUCTURE_TYPES, ELIGIBLE_SHAPES) are gone.
  - **Structure mapping** (`STRUCTURE_MAP`): open canyons/plains -> SURFACE (so they get
    the angled/overhead views the CSV lists); only enclosed tunnels/arches -> CORRIDOR
    (third-person only). Open Space -> asteroid_field, Cloudy -> field.
  - **Per-biome objects render** via a keyword heuristic (`LevelTheme._feature_style`):
    any of the ~540 object names maps to a supported prop shape
    (mushroom/frond/crystal/vent/girder/blob/rock) + a material color (ice=blue,
    lava=orange, bone, metal, …) falling back to the biome accent. So a Biomechanical
    level actually scatters sinew cables / bio-ducts / chitin plating, etc.
  - **Gravity mode** (`gravity`): threaded to the generators; Open Volume sets meteorite
    `gravity_scale` (Zero-G = drift, Standard = fall). Shown in the HUD.
  - **Enemy theming:** the biome's 3 enemy names ride in `enemy_names` and show in the
    HUD (Drifting Sentries / Salvage Wraiths / Reactor Mines …); the dumb swarmers are
    already built from the biome's own objects, so they read per-biome too.
- **Verified (rendered + headless):** 3500-frame run clean; rendered Ship Graveyard
  (surface, foliage-free, biome props), Derelict Submarine Corridors (corridor, correctly
  third-person), and Storm-Wracked Asteroid Belt (open volume, Zero-G drift + holed
  asteroid + mines) — all show their biome objects/enemies and correct gravity.
- **Biome drives the palette (2026-07-18, updated).** Palette is now keyword-mapped from
  the BIOME (`LevelTheme._biome_palette_key` -> a base palette family), so an ice biome
  reads icy and a lava biome molten. The MODIFIER now only applies a light ~22% secondary
  tint (`MOD_TINT`) so repeats of a biome still vary a little. Verified rendered: Tundra
  Plains = icy blue/white, Lava Fields = molten red/orange.
- **Cross-biome object swap (2026-07-18).** For endless variety, each rolled feature slot
  has a `OBJECT_SWAP_CHANCE` (0.28) to pull an object from ANY biome instead of the rolled
  one (`LevelSeed._global_objects` flat pool). The view/structure/palette stay keyed to the
  rolled biome (rules intact) -- only the object mix cross-pollinates, so a Tundra level can
  grow the odd mirror panel, an Ocean level a flux coil, etc. Verified in roll dumps.
- **Notes / still generic:** Open-volume props are spheres (space debris) rather than
  shape-varied. The CSV must be in an export build's resource filter (fine for run-from-source).

## Ship Headlight (2026-07-18)

Kevin: give the ship an underside spotlight to light the landscape, aimed 60° forward.

- **A real light node, not an emissive shader.** Answering Kevin's question: in Godot an
  `EMISSION` material only makes a surface *glow* (self-illuminate + feed glow/bloom); it
  does NOT cast light on other surfaces. Real light-casting needs a light node — and on
  this project's **GL Compatibility** renderer, realtime GI (SDFGI/VoxelGI) isn't
  available anyway, so a `SpotLight3D` is the correct tool.
- **`HeadLight` `SpotLight3D`** under `Ship` (`Main.tscn`): energy 8, range 60, spot angle
  42°, cool-white, shadows off (perf on streamed trimesh terrain — can enable later).
  `ship._aim_head_light()` sits it at the belly and aims it `head_light_forward_deg`
  (default **60**, `@export`) forward from straight-down. Parented to the Ship node (which
  never banks — only hull/mounts do), so the beam stays steady through turns, consistently
  washing the terrain ahead.
- **Verified rendered:** a night Ruined Cityscape shows a clear lit pool on the landscape
  ahead of the ship. Headless 2000-frame run clean.
- **Follow-ups built (2026-07-18, Kevin approved):**
  - *Time-of-day-aware energy.* SkyDirector now returns the rolled `tod`; `LevelDirector`
    scales the beam: surface day 2.5 / sunset 5 / night 9, corridor 6.5 (dim tunnels),
    open-volume 4 — so it's a subtle wash in daylight and a dramatic headlight at night.
  - *Theme-tinted color.* The beam is white lerped 35% toward the level accent, so a
    Frozen level throws a cool beam, a Molten one a warm beam.
  - *Shadows.* Enabled only when `PerfProfile.sky_quality >= 2` (MEDIUM+), since spot
    shadows over streamed trimesh terrain are the main cost; weak hardware skips them.
  - Wired via `ship.configure_head_light(energy, color, shadows)`, called from
    `LevelDirector._configure_head_light` after the environment is set.
  - Verified rendered: daytime beam reads subtle + cool-tinted; night beam dramatic.

## Ship Detail — Windows + Gribblies (2026-07-18)

Kevin: use shaders to put lots of tiny windows on the ship, and add small gribblies.

- **Windows shader (`shaders/ship_windows.gdshader`).** The generated hull has no UVs, so
  windows are stamped by a **triplanar grid in object-local space**: each face uses the two
  axes orthogonal to its dominant normal, giving clean rows of tiny panes on every face. A
  per-cell hash lights ~42% of them (warm cabin light, emissive); unlit panes darken so they
  still read as recessed. Lit like a normal surface, so the sun + headlight still shade the
  hull. `ship._apply_windows` swaps each hull part's material to this shader, carrying the
  part's albedo across (per-part color preserved). Density/lit-fraction/energy are uniforms.
- **Gribblies (`ship._scatter_gribbles`).** Tiny greeble boxes sampled onto vertices
  (oriented to the vertex normal, random small non-uniform scale), as one MultiMesh (one
  draw call). Adds fine surface detail without hand-authoring. **Refined (Kevin):** they now
  sit on the **BODY only** (the largest part) and take the **body's own surface colour**, so
  they read as raised detail on the hull rather than scattered dark bits (their flat-face
  normals still catch light differently, so they stay visible).
- Both run in `ship._apply_hull_detail` after the flat-shade pass, re-applied whenever the
  hull re-rolls. Verified rendered: close third-person shows dense lit/unlit windows across
  the hull + scattered greeble nubs — reads as a proper detailed ship. Headless 2000-frame
  run clean.
- **Note:** player hull only for now; the smart-enemy ships reuse the hull generator but keep
  their flat recolor (easy to extend to them later). Window density is a uniform if you want
  them even tinier.
- **Tuned (2026-07-18, Kevin):** the first pass read as speckled "spots" everywhere. Now:
  lower + rectangular density (`window_density = vec2(3.0, 5.0)`) so they read as horizontal
  windows; and drawn **only on the body's vertical lateral (X-facing) sides** — the shader
  gates on an X-dominant normal, and `ship._apply_hull_detail` applies the window material to
  the **largest part only** (the body), so no windows on top/nose/wings. Verified rendered:
  a clear row of windows along the flank; boxy bodies get a crisp grid, rounded bodies a side
  band.

## Aiming Reticle (2026-07-18)

Kevin: add a reticle; it has to work differently per view because the views work
differently.

- **One world aim point, projected per camera.** The ship always fires straight
  forward (-Z), so the aim point is a WORLD point ahead of the ship along -Z. Projecting
  it through whichever camera is current (`cam.unproject_position`) lands the reticle
  correctly in every view with no per-view drawing — the reticle sits ahead of the ship
  on the fire line in third-person, side-scroll, top-down, iso, and 3/4 alike.
- **Per-view DISTANCE is the part that differs** (`game_hud.RETICLE_DIST`). Orthographic
  views (top-down 6, iso 7) map world distance straight to screen offset, so they need a
  SHORT distance or the reticle flies off-screen; perspective views converge toward a
  vanishing point and take more (third-person 28), and the edge-pushed side-scroll (9) /
  3-4 (12) take middling values so the reticle stays on-screen ahead of the ship. Tuned
  against rendered shots of every view.
- **`reticle.gd`** (Control) draws the crosshair (ring + 4 ticks + centre dot) once at
  its origin; `game_hud._update_reticle` moves it to the projected point each frame,
  hiding it when the aim point is behind the camera or the ship is dead. Added as a HUD
  child in `Main.tscn`.
- **Verified rendered:** all five views show the reticle ahead of the ship, leading
  toward the obstacles. Headless 1800-frame run clean.
- **Possible follow-ups:** widen the ring with weapon tier (spread), or tint it to the
  theme; both are small.

### Ray-Traced Targeting Reticle for 3-4 / Isometric (2026-07-19)

Kevin: in 3-4 and isometric the reticle should be **ray-traced along the actual shot path
and land directly on enemies and mines**. In those angled views a fixed-distance aim point
doesn't read as "where my shot connects" the way it does in a straight-on view.

- **Ship casts the fire line each frame** (`ship._update_aim`): a ray from the shared
  `_fire_origin()` straight down -Z (the exact path bullets take, refactored so `_fire_shot`
  and the aim ray use the same origin), `AIM_RANGE` 120u, against `LAYER_ENEMY` (8),
  **areas-only** (enemy + mine hurtboxes are `Area3D` with `monitoring=false` — ray queries
  still detect them; the monitoring flag only governs overlap callbacks). Caches `aim_hit` +
  `aim_point`. Ignores terrain/props, exactly like the shots (which pass through them).
- **HUD lands the reticle on the hit** (`game_hud._update_reticle`): for isometric / 3-4,
  when `ship.aim_hit` the reticle projects `ship.aim_point` (sitting on the enemy/mine in the
  line of fire); with nothing in line it falls back to the fixed per-view distance (unchanged
  behaviour, and all other views keep the fixed point). Space state is queried from `_process`
  the same way the ship's existing soft-clearance ray is — no "flushing queries" errors.
- **Lock read** (`reticle.gd`): a `set_locked()` state swaps the crosshair to `locked_color`
  (warm) with a tighter inner ring + faint fill when it's on a target, so the snap is obvious.
- **Verified:** `tests/test_reticle_aim.tscn` — the ray hits `monitoring=false` layer-8 areas,
  lands on the NEAREST target's front face, is centred on the fire line, reaches the next
  target when the near one dies, and misses (falls back) with nothing in line. Real-game boots
  through isometric + 3-4 levels run clean (no space-state errors).

Kevin: expand the distance in front + to the left/right that the map spawns, and make
it follow the ship so wherever the player goes the map/enemies/objects come along.
Optimize the streaming in/out of memory.

- **Key insight:** the ship always auto-advances in -Z, so the existing Z-behind
  recycling already frees everything as the player moves — "follow" just needs new
  content spawned around the ship's CURRENT lateral position instead of a fixed x=0
  lane, plus terrain that's open (no fixed valley walls) and wide.
- **Surface — open landscape that follows.** Dropped the parabolic valley
  (`_terrain_height` is now open rolling hills + bumps, unbounded left/right). Each
  terrain strip is built centered on the ship's current x (`_spawn_terrain_tile` ->
  `_build_terrain_mesh(..., cx)`), so the ground trails the ship's lateral path.
  Widened: `lane_half_width` 12->16, `terrain_width_mult` 2->3.2 (strips reach ~±50),
  `terrain_res_x` 18->24, `segments_ahead` 15->18. All scatter (props/enemies/mines/
  hazards/pickups + `reachable_point`) now centers on the ship's x.
- **Open Volume — 3D ring follows the ship.** Every prop/meteorite/enemy/mine/hazard
  ring placement (and `reachable_point`) now centers on the ship's x AND y, so space
  content surrounds the ship wherever it flies in 3D. `volume_radius` 14->19,
  `segments_ahead` 12->14.
- **Corridor** (enclosed, inherently surrounds the ship): widened the tube
  (`base_half_width` 4->5.5, `wall_height` 10->13).
- **Optimization:** per-frame terrain-strip cap on surface (anti-hitch); recycling
  stays distance/Z-based, so memory is bounded — a 1200-frame multi-level probe peaked
  at ~404 streamed nodes and held steady (no growth).
- **Verified:** headless clean; a forced hard-steer to x=45 on a surface level keeps the
  ship over terrain the whole way (landscape follows); open-volume content surrounds the
  ship out at (40,25); node counts bounded.
- **Known limit / follow-up:** content spawns ~20s of travel ahead in Z, so under
  EXTREME sustained one-direction lateral flight the scatter can lag (you outrun it) —
  the terrain still follows. A true fix is a spatial chunk grid (spawn by cells around
  the ship's current position, no Z-lead lag); flagged for later.

## More Randomness in the Enemy Build (2026-07-18)

Kevin: add randomly-added randomness to the enemy build process.

- **Dumb swarmer (`enemy_dumb.gd`)** now rolls several independent build modifiers so
  no two build alike: petal count 5-11 (was 6-9); a random **hub style** (torus+core /
  sphere cluster / spiky core); a chance of a **second inner ring** of smaller petals;
  **per-petal jitter** on colour (hue/sat/value around the accent), size, radius, and
  out-of-plane tilt; a chance to **mix in different petal shapes**; and a random resting
  x/y tilt so they don't all face flat-on. Verified rendered: a field of clearly-distinct
  flowers (different counts, hubs, shapes, colours).
- **Smart ship (`enemy_smart.gd`)**: on top of the already-random `ShipHullGenerator`
  hull, a random per-enemy **size** (0.82-1.25×, hurtbox matched) and a gentle random
  **barrel-roll** of the hull for liveliness.
- Headless regression clean.

## Two New Shape Families — Canyon + Pillared (2026-07-19, APPROVED, built)

Kevin: increase the shape families to match those in the CSV — there should be a few
more. The CSV `Structure` column has 10 distinct tokens but `STRUCTURE_MAP` collapsed
them into only 3 families (Corridor / Surface / Open Volume); several tokens were being
*faked* inside another family's generator. Two were promoted to real families this pass
(Kevin's pick from the candidate set; Arched Planes and a Cloud/Nebula split were offered
but not chosen, so they stay as-is — Arched Planes remains a Corridor variant):

- **CANYON** (`level_canyon.gd`, `ShapeFamily.CANYON=3`) — an **open-top walled gorge**
  you fly down, distinct from the enclosed Corridor (lethal ceiling, third-person-only)
  and from open Surface (no walls). Implemented as a **subclass of `level_surface.gd`**
  that overrides only `_terrain_height`: it adds two tall lethal walls framing a fixed
  centerline (x=0, where the ship spawns), ramped in over the safe start. Because the
  terrain mesh, its trimesh collision, its normals, and every prop/enemy/pickup Y all
  dispatch through `_terrain_height` (GDScript virtual dispatch), that single override
  reshapes the whole level — **the walls ARE the terrain trimesh**, already lethal on the
  hazard layer, so no separate wall bodies. Gorge half-width scales off the inherited
  `_half_width` (so it stays navigable as the ship grows) × the per-level `gorge_width`
  state. `reachable_point` is overridden to keep pickups inside the gorge. `"Canyons"` now
  maps here (was faked as Surface/mountains). Grey-box centerline is straight; gentle
  winding is a flagged later polish. `"Aquatic Canyons"` deliberately **stays Corridor**
  (those read as enclosed submarine corridors, per their CSV name).
- **PILLARED** (`level_pillared.gd`, `ShapeFamily.PILLARED=4`) — an open plain studded
  with a **dense slalom field of tall vertical lethal pillars**, distinct from plain
  Surface (which lays at most one structure column every couple segments). Also a
  `level_surface.gd` subclass: overrides `_spawn_structure_feature` to emit a *cluster*
  of pillars (CylinderMesh + trimesh, lethal) every segment, count scaled by the rolled
  `pillar_density`/`density` state. `"Pillared Planes"` now maps here (was faked as flat
  Surface). Floor stays the gentle inherited Surface terrain.

Both new families are **surface-like** for presentation: SkyDirector now treats CANYON
and PILLARED as surface (real atmosphere/sky, not the flat Corridor fog), and they get
all the views their CSV biomes list (no camera restriction — only Corridor is pinned to
third-person). Wiring: two new enum entries appended (0/1/2 literals unchanged so
`sky_director` SURFACE=1/OPEN_VOLUME=2 and `in_space==2` stay valid), two nodes in
`Main.tscn` + director paths, `_build_level` clears all five generators and selects the
new active one, `_configure_ship_flight` spawns both at y=3 over their floor,
`roll_state` rolls per-family knobs (`gorge_width` / `pillar_density`).

**Verified (headless, real pipeline):** forced a CANYON level (biome Ruined Cityscape)
and a PILLARED level (biome Petrified Forest) through the actual `LevelDirector` and
streamed 40 frames each — CANYON floor y=0.42 vs wall y=15.87 at x=40 (**walls rise
~15.5u**), PILLARED streamed **84 pillars**; both report `active=true`, terrain
streaming, no script errors. Full-boot smoke run also clean.

**Still open / next:** canyon centerline winding; pillared/canyon numeric tuning (gorge
width, wall height, pillar thickness are first-guess placeholders); whether Arched Planes
and Cloudy Open Space also deserve their own families later.

## Craggy Cliff Backdrop + Waterfall/Lava Cliff Biomes (2026-07-19, APPROVED, built)

Kevin: in the 3/4 and isometric views, randomly opt for a second kind of landscape
construction where a **craggy cliff rises steeply behind the ship (ship's left side)**.
Add it to mountainscapes, canyons, cityscapes, etc. Add **Waterfall Cliffs** and **Lava
Flow Cliffs** biomes with particles pouring down the cliff behind the ship, and fill them
out with enemies/hazards/color themes — waterfalls are new **push** hazards, lava flows
are **damage fields + push** hazards. Built this pass.

- **Cliff construction (`level_surface.gd`).** A steep craggy cliff on the ship's LEFT
  (−X), built as a **separate streamed structure** (NOT the heightfield) so it follows
  the ship's lateral path — each segment sits at the ship's x-at-build minus an offset,
  exactly like terrain strips — reads as a backdrop in the angled cameras, and works
  identically whether the active generator is Surface, Canyon, or Pillared (all inherit
  it). The face is a per-segment grid jittered by a `craggy_noise` field (jagged relief,
  strongest mid-height), foot planted on the terrain, ramped in over the safe start so
  spawn stays open. Lethal **trimesh** on the hazard layer; `CULL_DISABLED` material to
  match the existing terrain convention. Streamed/recycled with the segments.
- **Roll gating (`level_seed._roll_cliff`).** The cliff is ON automatically for the
  dedicated cliff biomes (structure `"cliffs"`); otherwise it's a **random opt-in
  (`CLIFF_CHANCE = 0.45`) only for the isometric / 3-4 viewpoints** on eligible open
  biomes (structure mountains/canyon, or biome name containing city/mountain/canyon/
  crag/cliff). Rolled `cliff = {enabled, flow, height_mult}` rides in the level dict and
  is passed via a new `configure_cliff()` on every generator (no-op on Corridor/Open
  Volume). Generic cliffs are dry; flow only exists on the two cliff biomes.
- **Flow particles.** When `cliff.flow` is set, each cliff segment streams a CPUParticles3D
  down the face: **waterfall** = pale/blue fast-falling (high gravity), **lava** = glowing
  orange, additive, slow creep. GL-Compatibility (CPU particles), freed with its segment.
- **Two new biomes (`biome_attribute_table.csv`).** `Waterfall Cliffs` (Mist Drifters /
  Rapids Hunters / Plunge Mines; mossy/spray/reed objects) and `Lava Flow Cliffs` (Ember
  Drifters / Magma Hunters / Cinder Mines; basalt/obsidian/ember objects), both structure
  `Cliffs` (→ Surface, forces the cliff) and views `3/4, Iso` only (so the backdrop always
  shows). New `STRUCTURE_MAP["Cliffs"] = [SURFACE, "cliffs"]`.
  - **Hard rule (2026-07-19): cliff biomes are angled-view only.** The viewpoint roll now
    refuses to pair a `"cliffs"` structure with any view but iso / 3-4 (code guard, not just
    the CSV), and `_roll_cliff` also force-disables the cliff outside `CLIFF_VIEWS` — so a
    cliff can never appear in follow-behind / side / top-down. Verified 0 in 10,000 rolls.
    (A cliff seen in a third-person screenshot earlier was a test artifact that forced the
    viewpoint, not a real roll.)
- **Color themes (`level_theme.gd`).** New **Waterfall** palette (bright teal / spray-white
  / luminous cyan accent), inserted before the `Flooded` rule so waterfall doesn't get
  caught by its `water` keyword. **Lava** reuses the existing hot **Molten** palette (its
  `lava` keyword already matches). The waterfall particles pick up the theme accent (blue);
  lava particles are always molten orange regardless of theme.
- **New hazards.** **Waterfall = push** (`hazard_push.gd` new `variant = "waterfall"`): a
  continuous water cascade that shoves the ship down + away (off course), no erupt cycle.
  **Lava = damage field + push** (`hazard_field.gd` new `variant = "lava"`): a glowing
  molten pool + embers that applies DOT (`dps = 10`) AND a shove (down + away) while the
  ship is in it — both threats in one node. Wired through `hazard_spawner.create` (`"waterfall"`
  → PUSH/waterfall, `"lava"` → FIELD/lava); the roll injects the matching hazard from the
  cliff flow, and `level_surface._spawn_hazards` roots them at the **cliff base** (left
  side) when a cliff is present.
- **Verified (headless, real pipeline):** forced Surface+iso+cliff levels — 19 cliff
  meshes + 19 lethal bodies + 19 flow emitters, ~30u face height, both water and lava; a
  disabled/third-person level builds 0 cliff segments. Rolled the actual **Waterfall
  Cliffs** biome (3/4 view: cliff on, flow=water, waterfall hazard rolled, 46 cliff segs,
  7 waterfall-push nodes) and **Lava Flow Cliffs** (iso view: cliff on, flow=lava, lava
  hazard rolled, 38 cliff segs, 7 lava field+push nodes); 50-frame streams exercised the
  new push/DOT `_process` paths with no errors. Full multi-level boot smoke clean.

**Still open / next:** all cliff/hazard numbers are first-guess placeholders (cliff
height/offset/cragginess, waterfall/lava push + DOT strengths, hazard densities); the
cliff currently only spawns on the ship's LEFT (−X) — flip/side-variety is a possible
follow-up; generic (dry) cliffs don't yet vary their rock look by biome; **not yet
verified with a rendered screenshot** (headless-numeric only) — the visual read of the
craggy backdrop + pouring flow should be eyeballed in-editor.

## Multi-Gorge Zigzag Canyon (2026-07-19, APPROVED, built + render-verified)

Kevin: the single straight canyon read as a broad valley (see the prior tuning note).
Replace it with 2-3 procedurally-streamed gorge channels that ZIGZAG forward along the
flight path, with varied floor heights and a lateral gap that varies until they overlap.
And **open Godot (non-headless) to verify they exist** — not just headless numbers.

- **`level_canyon.gd` rewrite.** `_ensure_gorges()` rolls 2-3 channels, each `{amp, freq,
  phase, floor, half}`. `_terrain_height` is the **MIN over the channels** of
  `(floor + wall(dist-from-centerline)) * ramp`: near any channel you're down in its low
  floor, between channels the walls pile into a ridge. Each channel's centerline is a
  sinusoid `amp·sin(z·freq + phase)` — different rate/phase per channel, so they weave at
  different speeds, the lateral gap opens and closes, and they periodically **overlap into
  one wide basin** then split. Pure function of (x,z) → seamless tiles + lethal trimesh.
  Floors are rolled distinct per channel (varied heights). Rerolled each `start()`.
- **Spawn-safety fix (found via the render — see below).** Channel 0 is the SAFE SPINE the
  ship spawns on (x=0): its swing is clamped strictly inside its own half-width
  (`amp = half × 0.2..0.5`) so the straight-ahead line x=0 is ALWAYS in its flat floor,
  never a rising wall. The other channels swing wide (`amp 5..12`) and weave across it.
- **Verified numerically:** a rolled canyon showed 2 channels with floors −0.8 vs +2.3;
  centerlines zigzagged (channel 0: −5.0 → −3.1 → +1.9 → +5.0 over depth) and their span
  varied 12.9 → 11.8 → **6.5 (merged)** → 15.4 (split); a z=−100 cross-section showed the
  merged low basin flanked by 23-24u ridges.
- **Verified in-engine (real GPU, non-headless):** launched the game (AMD Radeon 780M,
  GL Compatibility), forced canyon levels, saved rendered screenshots. **The first render
  caught a real bug** — the ship crashed at distance 19 flying straight, because channel
  0's amp could exceed its half-width and put a wall on the spawn line; fixed as above.
  After the fix the ship survives to distance 60+ and a bright Pristine isometric shot
  clearly shows a diagonal ridge separating the ship's channel from a second channel/
  valley beyond it — the braided gorges reading as intended.

**Still open / next:** all gorge numbers are first-guess placeholders (channel count,
amp/freq ranges, wall height 24, half-width fractions); the zigzag is a smooth sinusoid
(serpentine) rather than sharp switchbacks — sharper "zigzag" would need a triangle-wave
centerline; navigability at extreme channel-swing rates vs. ship steer speed is untuned.

## Shallower Iso + 3/4 Camera Angles (2026-07-19)

Kevin: make the 3/4 and isometric views much more shallow. Both now sit at a low ~18°
elevation above the horizon (was ~35°), so they look ACROSS the landscape toward the
horizon and the cliff backdrop + gorge walls loom dramatically instead of reading flat
from above (`camera_rig_controller.gd`):
- **Isometric**: the old hardcoded `Vector3(1,1,1)` direction (a fixed ~35.26° angle) is
  replaced by a diagonal ground bearing `Vector3(1,0,1)` lifted by a new
  `isometric_elevation_degrees` (@export, default 18) — tunable, and shallow by default.
- **3/4**: `three_quarter_elevation_degrees` 35 → 18. Azimuth (over-the-shoulder swing)
  unchanged.
- Governing Rule 6 intact — still script-driven position + `look_at` off `ship_visual_radius`;
  only the camera elevation changed. Verified in a real GPU render: both views now look
  across the terrain with the craggy cliff rising steeply on the right; ship survives.
- Tuning: 18° is a first guess (both @export); fog + stream-ahead still mask the (now
  more distant) horizon — watch for pop-in if the angle goes shallower still.

## Camera Ground-Collision + Ship Soft-Stop (anti unfair crash) (2026-07-19, built + render-verified)

Kevin: the camera must not pass through the ground, and if the player keeps pushing it
into the ground the spring arm should shrink and the player should STOP before they go
through or crash — no more crashing into a closer wall they can't see, over and over.
Two coordinated pieces:

- **Cameras never clip terrain (`camera_rig_controller.gd`).** The third-person
  `SpringArm3D` collision is turned ON (`collision_mask = HAZARD_LAYER`, was 0) so it
  shrinks natively when terrain gets between it and the ship. The four scripted rigs
  (iso / 3-4 / side-scroll / top-down) get a **manual spring** `_spring_local()`: a raycast
  from the ship to the desired camera spot; if lethal terrain is in the way, the camera is
  placed on the NEAR side of it (minus a margin). So the camera never sits underground or
  behind an occluder — the ground/near wall stops hiding the ship (the root of the "can't
  see it" crashes), especially at the new shallow angles.
- **Ship stops before crashing (`ship.gd`).** The two STEERED axes (X/Y) are now
  soft-limited: `_soft_axis_move()` raycasts in the steer direction and, if hazard geometry
  is within `move + clearance`, clamps the ship to halt a `soft_clearance` (× ship radius,
  default 0.8) short of it and bleeds that steer momentum. So steering DOWN into the ground
  (or sideways into a wall) HALTS instead of crashing. **The forward auto-advance (−Z) is
  deliberately NOT limited** — obstacles directly ahead are visible and stay lethal, so the
  game keeps its stakes; only the steer-into-what-you-can't-see crashes are removed. The
  `HazardDetector` remains as a backstop. Both behaviours are `@export` (soft_stop_enabled,
  soft_clearance, camera_collision_margin).
- **Verified (headless numeric + GPU render):** held "steer down" into a canyon floor for
  150 frames — ship stayed **alive**, min height-above-terrain **0.74** (never penetrated),
  the iso camera stayed above the terrain, and forward distance kept growing (not stuck). A
  rendered shallow-iso shot shows the ship skimming the ground alive with the camera looking
  across from above ground.

**Design implication / open:** steer-axis walls (incl. the ground) are now soft boundaries
on the steered axes rather than instant death — intended per the request, but it does make
those axes non-lethal; if some levels want the ground to stay lethal on a hard dive, gate
the soft-stop (e.g. only when the camera is actually occluded/pinned). `soft_clearance`
0.8 and `camera_collision_margin` 0.5 are first-guess placeholders.

## Streaming Overhaul — Build Only What the Camera Sees (2026-07-19, built + render-verified)

Kevin (emphatic): stream ONLY what is visible to the player — do not build out the entire
~200u level. Everything outside the visible window gets destroyed and removed from memory,
with a bit of off-camera padding so the build/destruction never shows, and objects slowly
SHRINK as they move off into the distance until they leave memory.

**The problem this fixes:** every generator was building a huge distance *ahead* — corridor
`segments_ahead=20`→120u, surface 18→180u, open-volume 14→168u — while the camera only sees
to the fogged horizon (~100u). So ~half of everything built was invisible geometry sitting
in memory (effectively the whole level). Recycling only trimmed ~30u behind.

- **Tight visibility window (all generators).** Replaced the segment-count look-ahead with a
  world-unit window: `build_ahead` (default **112** ≈ fog horizon 100 + off-camera padding),
  `build_behind` (30). Initial fill and the per-frame stream loop only build within
  `build_ahead`; recycling frees everything past `build_behind`. Perf tier still scales it
  (`view_distance_scale`). Applied to `level_surface` (→ canyon/pillared inherit),
  `level_corridor`, `level_open_volume`.
- **Shrink in/out at the edges (`stream_window.gd`).** A shared `StreamWindow.scale_factor`
  ramps a scenery object's scale 0→1 as it nears the far frontier and 1→0 as it recedes past
  the ship, so it grows in / shrinks out of nothing before it's built/freed — the tight
  window never pops. Applied to scenery (feature props, structure features, pillars, space
  debris); NOT to terrain/cliff meshes (scaling would leave gaps — the fog + padding hide
  those) or to enemies/hazards/meteorites (they animate/behave; they distance-recycle).
- **Verified (headless + GPU render):** flew a surface level to z=−204 (past the whole level
  length) — streamed content stayed a **~130u window** (≤106u ahead, ≤24u behind), node count
  **bounded** (2073→1892, not growing with distance), and **114 props were actively shrinking
  OUT behind** the ship (175 scaling in at the frontier). All 5 families build clean and stay
  bounded (≤112u ahead). Third-person (sees furthest) and iso renders still fill to the fogged
  horizon with **no premature terrain edge or pop** — the reduction is invisible.

**Tuning / open:** `build_ahead` 112 is tied to the fog end (100) — to stream even tighter,
pull the fog in and lower `build_ahead` together (they must stay paired or the frontier pops
before the fog hides it). Per-view build distance (top-down/side-scroll see less than
third-person, so could build even less) is a possible refinement, left uniform for now.

### Endless-in-All-Directions + Per-Tier Fog Fix (2026-07-19, built + headless-verified)

Follow-up pass closing two gaps in the streaming model above, at Kevin's direction ("all
landscapes need to extend endlessly in all directions … make sure this happens on absolutely
all level types").

- **Fog end is now derived from the ACTUAL per-tier build distance, not hardcoded.**
  `level_director._configure_environment` was pinning `fog_depth_end = 100`, but `build_ahead`
  is scaled by `PerfProfile.view_distance_scale` (×0.75 MEDIUM, ×0.5 LOW → builds only 84u/56u
  ahead). So on the MEDIUM/LOW tiers geometry spawned *inside* the un-fogged range and popped
  in. Now `fog_end = active_generator.build_ahead × view_distance_scale − 12` (with
  `fog_depth_begin = fog_end × 0.28`), so the streamed frontier — forward *and* lateral — is
  always fully fogged before it's built, on every perf tier. (ULTRA/HIGH behaviour is
  unchanged: 112 − 12 = 100.)
- **Surface-family terrain is now a true 2D streaming GRID (endless in every direction).**
  The old terrain was a fixed-width forward *strip* centered on the ship's x-at-build — it had
  a hard lateral cull edge that had been whack-a-moled per-view (`three_quarter_left_extend`,
  etc.). Replaced with a grid of square tiles keyed by `(ix,iz)` (`level_surface._update_terrain_grid`):
  each frame it spawns every tile whose cell falls inside the window (`_ahead_dist` ahead *and*
  laterally, `build_behind` behind) and frees every tile that leaves the window in *any*
  direction — so the ground extends endlessly whichever way the player roams (top-down/iso/3-4
  strafing no longer runs off the mesh). Tiles seam automatically because `_terrain_height` is
  a pure function of `(x,z)`; when the per-frame build cap bites, nearest-to-ship tiles build
  first so no hole ever opens under the player. `terrain_tile_size` (32u) + `terrain_vertex_spacing`
  (2.0u; canyon lowers to 1.0u for crisp gorge walls) set the mesh/body budget. Canyon +
  Pillared inherit it unchanged (they only override the height field / structure scatter).
  Corridor (a bounded tube) and Open Volume (a void) are already correct — endless forward /
  no landscape edge — so they were left as-is.
- **Collision LOD — only the ship's 3x3 tile block is lethal (2026-07-19, Kevin: "run lean on
  more devices").** The grid is ~40 tile *meshes* at ULTRA, but the ship can only ever crash
  into the tile it's physically over, so distant tiles are now **visual-only**: a tile gets a
  lethal trimesh `StaticBody3D` only while its cell is within `terrain_collision_ring` (default
  1 => a 3x3 block) of the ship's cell. `_reconcile_tile_collision` runs each frame — a tile
  gains its body while the ship is still a full cell away and drops it once the ship leaves, so
  the ship never reaches a tile before it's lethal. This cut active collision bodies from ~40
  to **9** with zero gameplay change — the real leanness win on low-end hardware (trimesh bodies
  are the expensive part; meshes are cheap and mostly fogged anyway).
- **Verified headless** (`tests/test_terrain_grid.tscn`, kept as a regression): across Surface,
  Canyon, Pillared — tiles surround the ship on all sides at spawn, none build beyond the
  window, face winding stays correct (per-face normals point up, per the CLAUDE.md
  non-negotiable), the grid follows a hard forward+lateral strafe (ground still present on
  every side afterward), stale tiles free once out of window, tile count stays **bounded and
  flat (40 at ULTRA, was 40)**, and **lethal bodies stay bounded to the ring (9 of 40) and
  follow the ship**. The full game also boots a top-down Surface level (the X-free case that
  exposed the old edge) with zero errors.

**Open Volume was already fully streaming** and needed no terrain change — it has no ground
(its content is a 3D ring that follows the ship through the void, so there's no landscape edge
to make endless), and it already streamed segments ahead / recycled behind / edge-shrank props.
The per-tier fog fix above applies to it too (space fog now derives from the build distance).

### Scenery Fills the Whole Ground, Not a Lane (2026-07-19, playtest bug fix)

Kevin, from a real playtest: "the objects end when I went off the track and the track went off
way into the distance." Root cause: the endless-terrain pass above made the *ground* stream in
all directions, but the **feature props + structure features were still scattered in a narrow
forward lane** (`±_half_width ≈ ±16u`) centered on the ship's path. Steer wide and the ground
kept going while the objects stopped dead at the lane edge — a visible object boundary.

Fix — **scenery is now owned by the terrain tiles** (`level_surface._populate_tile`), so it fills
the ground in every direction and recycles with its tile, exactly like the terrain itself:
- Each terrain tile scatters its own feature props + structure features across its footprint,
  seeded per-cell (`_tile_seed`) so a tile's scatter is stable if it leaves and re-enters. The
  old per-Z-segment `_scatter_feature_props` / `_spawn_structure_feature` lane scatter is gone;
  the per-segment loop now only streams the sparse *moving* threats (enemies / mines / hazards)
  along the flight path (those stay lane-based on purpose — they're threats you fly through, not
  scenery, and filling the world with AI nodes would be wasteful).
- **Density is full along the flight path and tapers toward the horizon** (`_lane_density_mult`,
  quadratic `1/(1+e²)` past a `lane_full_width_mult` corridor, floored at `lane_edge_density`).
  So the corridor stays exactly as dense as the old lane (gameplay intact) while distant scenery
  is sparse — no hard object edge, but the object count stays bounded (~500 per feature word in
  the full window at ULTRA, vs. an unbounded ~2400 if filled uniformly).
- **Collision LOD applies to scenery too**: a prop/structure/pillar gets its lethal trimesh body
  only while its tile is in the ship's collision ring; distant scenery is visual-only. So the
  world can be visually full without a physics-body explosion (lean on low-end).
- Canyon inherits it unchanged; **Pillared** overrides `_scatter_tile_structures` to place its
  pillar cluster per tile (so the slalom field now fills the whole plain, not just a lane).
- **Verified** in `tests/test_terrain_grid.tscn`: scenery spread reaches the full ±128u window
  (was ±16u), count stays bounded, winding correct, collision bodies still ringed to the ship.
  Real-game boots across Surface (flat/iso), Canyon (topdown/¾), Pillared, plus Corridor/Open
  Volume run with zero errors.

**Tuning knobs** (`@export` on `level_surface`): `lane_full_width_mult`, `lane_edge_density`,
`struct_per_tile`, `terrain_tile_size`, `terrain_collision_ring`. Density values are still
first-guess placeholders per the brief's standing note.

### Camera-Distance Cull for the Deep Views (2026-07-19)

Kevin: "in 3rd person and 3/4 view the landscape will go quite a way back. Add a distance cull
to the camera too — scale it down then cull any objects." In those two deep perspective views a
whole field of props now draws far into the distance (geometry is bounded by streaming, but it
still *renders* out to the fogged horizon). Fix (`StreamWindow.camera_factor` + each generator's
edge-shrink / `_apply_camera_cull`): in third-person / 3-4 only, every streamed **object** (tile
scenery, structure features, pillars, corridor props, space debris, enemies) **scales down as it
recedes from the camera and is hidden — a real render cull, `visible=false`, not just a 0-scale
draw — before the fogged horizon.** Ramp is a fraction of the build distance
(`StreamWindow.CULL_BEGIN_FRAC` 0.5 → `CULL_END_FRAC` 0.82), so objects shrink over ~[0.5,0.82]×
of the stream distance from the camera and vanish just as the fog takes over — no pop, fewer
far-distance draw calls (leaner in the exact views that showed the most).

- Applies to **objects only**, not the terrain mesh (scaling terrain would tear seams; culling a
  half-fogged tile would pop) — the landscape itself stays fog-hidden as before. Physics debris
  (drifting meteorites) is also left alone (scaling a rigid body mid-sim is trouble; it fogs out).
- **No-op in the orthographic / side views** (top-down, iso, side-scroll frame a bounded area, so
  there's nothing far to cull) — gated on `current_viewpoint`.
- **Verified headless** (`tests/test_terrain_grid.tscn`): with a third-person camera, distant
  scenery is hidden while near scenery stays full-size. Real-game boots across corridor
  (third-person), pillared + open-volume (3-4), and a control top-down surface all ran clean.
- Tunable via the two `CULL_*_FRAC` consts in `stream_window.gd`.

## Engine Jets + Enemy Trails (2026-07-19)

Kevin: give the player's ship jets and the enemies a trail, with **very lightweight** particle
systems and **small** particles. Both use one shared helper (`scripts/vfx.gd::VFX.trail`) — a
single **world-space** `CPUParticles3D` (`local_coords = false`), so the emitter's own motion
draws the trail with no per-frame code. Kept cheap: small counts (~9-14 × `PerfProfile.particle_scale`,
so **nothing on the lowest tier**), small billboards (~0.11-0.16 u), no gravity, additive glow,
alpha faded to nothing over a short life.

- **Player jets** (`ship._setup_exhaust` / `_refresh_exhaust`): one emitter off the hull's rear
  (+Z) with a slight backward plume; the ship's fast forward motion streaks it into a thin jet
  trail. Nozzle offset + particle size track `ship_visual_radius`, refreshed in `grow_ship()` and
  `reset()` so the jet grows with the hull. Cyan-white (`EXHAUST_COLOR`).
- **Enemy trails** (`enemy_base._setup_trail`, gated by a new `_wants_trail()` virtual): a faint
  glowing trail themed to the enemy's `accent`. Only the **flying** enemies opt in
  (`enemy_dumb` / `enemy_smart` override `_wants_trail()` → true); **mines and stationary hazards
  keep the default false** — a world-space trail on something that doesn't move is just a puff
  cloud.
- **Verified:** `tests/test_vfx_trails.tscn` — helper builds a small, world-space, additive,
  billboarded, low-count emitter; a flying enemy gets exactly one trail, a mine/stationary hazard
  gets none. Full-game boot (ship jets + real enemy spawns) ran clean.

## Water Levels — Ocean Surface + Underwater (2026-07-19)

Kevin: top-down Ocean Surface = "just a flat plane that fakes a reflective ocean surface with
normals, super light weight." Underwater levels = tint all objects light blue, add god rays +
fake caustics, and post-process in refractive rainbows + fuzzy edges.

**Ocean (top-down Surface, `shaders/ocean.gdshader`).** Gated on an ocean biome keyword +
top-down (`level_surface._ocean_flat`): `_terrain_height` returns 0 (dead-flat plane), tile mesh
resolution drops to 2, structure features are suppressed (no mountains on open water), and tiles
get the ocean **spatial shader** instead of the vertex-colour terrain material. The shader is
deliberately cheap — a small **fractal of 5 sine octaves** at varied directions/frequencies
perturbs the `NORMAL`, a fresnel term tints the albedo toward a sky colour, a foam tint brightens
the crests, and low roughness lets the scene's sun throw sparkle off the moving normals (no
screen reflection, no heightmap). Deep/sky colours come from the level theme. All the existing
streaming/collision (flat lethal trimesh, tile grid, recycle) is reused — every other surface
biome keeps its rolling heightmap.

*Rework (2026-07-19, Kevin: "long stretched reflections, doesn't capture the wavey look"):* the
first version used 3 big near-parallel low-frequency waves, so the sun's specular smeared into
one long coherent streak. Replaced with the multi-directional higher-frequency fractal above,
which shatters the glint into scattered "sun-glitter" (reads as choppy water) and adds crest foam
so the waviness shows off-glint too. Tunables on `shaders/ocean.gdshader`: `wave_scale` (ripple
size), `wave_strength` (choppiness), `wave_speed`, `foam_amount`, `water_roughness`.

**Underwater (submerged biomes, `shaders/underwater_post.gdshader`).** Per the biome CSV the
aquatic levels (Underwater, Kelp Forest Open Water, Coral Reef Tunnels, Jellyfish Swarm Waters,
Bioluminescent Reef Shallows, Sunken Temple Ruins) are **Surface / Canyon / Corridor** families,
NOT open volume (open volume is space) — so `_is_underwater` matches on the biome word regardless
of shape family, and explicitly EXCLUDES the ocean *surface* (that's the flat reflective plane).
The director swaps the sky for a **murky blue BG_COLOR** volume with closer fog, and toggles a
full-screen **post-process overlay** (a `ColorRect` on a CanvasLayer below the HUD — HUD moved to
`layer = 10` in `Main.tscn` so the UI isn't distorted).
The single post pass (~8 screen taps) does all four asks at once: a **light-blue tint** over
everything, swaying vertical **god-ray** shafts, an animated **caustic** interference net, a
per-channel **refractive-rainbow** split that spreads toward the edges, and an edge **blur** so
the frame reads "fuzzy" at the periphery.

- **Verified (logic, headless — `tests/test_water_levels.tscn`):** top-down ocean flags flat +
  uses the water shader + suppresses structures; ocean in a non-top-down view and non-ocean
  biomes keep the heightmap; underwater detection is correct across shape family + biome. Full
  game boots clean (no errors, no `det == 0`).
- **Preview hotkeys (so you don't have to reroll for ages to find these).** `LevelDirector`
  forwards number keys to a forced roll (`LevelSeed.roll_new_level(force_biome, force_view)`):
  while the game is running press **1** = Ocean Surface top-down (the reflective water), **2** =
  Underwater, **3** = Kelp Forest underwater, **0** = back to random. The HUD's Shape/View line
  confirms which level loaded. A forced view the biome can't support falls back to a valid combo.
- **Caveat — shaders need an in-editor/GPU look.** The `--headless` dummy renderer doesn't
  compile shaders, so I could verify the GDScript wiring but NOT the shaders' compile/appearance.
  Both are written to Godot 4.7 syntax; give the ocean shimmer and the underwater post a visual
  pass in-editor and tune the uniforms (`wave_*`, `tint_strength`, `aberration`, `blur_amount`,
  `godray_strength`, `caustic_strength`) to taste.
- **Also fixed this pass:** the earlier deep-view camera cull was scaling **enemies** (which own
  a `CollisionShape3D`) toward zero, spamming Godot's `det == 0` basis-inversion error. Enemies
  now HIDE past the cull distance instead of scaling (`StreamWindow.cull`), per the studio gotcha
  — never scale a collider-owning node. Pure-visual props still scale down as before.

## Optimization Pass (2026-07-19)

Kevin: "the game really needs optimization. Is the culling clean? Reduce enemies? Bullets are big
and use lots of verts -- make them a small prism."

- **Culling is clean (no leak).** Measured with `tests/test_stream_bounded.tscn` (drives a dense
  4-word canyon 2400u forward, no rendering): the generator's live node count oscillates in a
  fixed band and never climbs -- streaming frees everything it spawns. What the probe DID reveal
  is the real cost was **object COUNT**, not a leak.
- **Bullets → small low-poly prism.** `projectile.gd` used a `SphereMesh` (~2k verts) per bullet.
  Replaced with a `BoxMesh` rectangular prism (24 verts), radius 0.22 → 0.14, elongated along and
  oriented to its velocity (`looking_at`) so it reads as a bolt from any firing direction. Enemy
  shot radius 0.26 → 0.16. ~90× fewer verts per bullet, and there can be dozens.
- **Feature-prop density cut ~69%.** The windowed tile scatter was hitting **~3,700 prop draws**
  on a dense level (~77 props per 32×32 tile per word -- absurd, perf AND clutter). Cut
  `props_per_density` 6 → 2 (surface) / 5 → 2.5 (corridor, open-volume) and `lane_edge_density`
  0.06 → 0.035. Same probe now shows **~1,150 props / ~2,000 gen nodes** (was ~3,700 / ~6,000+),
  still bounded. The flight-path lane stays a proper hazard field (~26 props/tile/word); the far
  fill just thins out. All the reduction knobs are `@export`ed for further tuning.
- **Enemies capped + thinned.** Flying enemies (esp. `enemy_smart`, which builds a full procedural
  hull each) could reach ~10-15 on a dense level. Added `max_active_enemies = 6` (checked in every
  generator's `_spawn_enemies`) and cut `enemies_per_density` 3 → 2. Concurrent flyers now bounded.
- **Still bounded / clean:** all existing streaming + collision-LOD + camera-cull tests remain
  green after the cuts.

## Cliffside Canyons, Camera Ease, Complementary Pickups, Enemies Back (2026-07-19)

Four tweaks from a play session:

- **Iso / 3-4 canyons are CONVERTED to cliff landscapes (not canyon + cliff).** The angled cameras
  sit above + to one side and clipped through the near gorge ridge. Fix in two parts: (1)
  `LevelSeed._roll_cliff` forces the craggy cliff backdrop ON for `structure_type == "canyon"` in
  iso/3-4 (was a 45% opt-in); (2) `level_canyon` now has a `_cliffside` mode (set when the view is
  iso/3-4) where `_terrain_height`/`reachable_point` defer to the flat SURFACE floor — **the gorge
  walls are dropped entirely**. So the only vertical geometry is the single cliff on the far side
  (opposite the +X camera), and there's no close wall to clip. Third-person / top-down / side-scroll
  canyons keep their gorges (they read fine there). Verified: iso canyon terrain relief < 8u (flat),
  third-person > 12u (walls).
- **Camera no longer jerks on a pickup.** Collecting a power-up steps `ship_visual_radius` up
  discretely, and every rig scales its framing off it — so the zoom snapped. `camera_rig_controller`
  frames off a smoothed `_framing_radius`. **Superseded (2026-07-19):** the first attempt used an
  exponential lerp, which still LURCHED (measured ~2.9× normal camera speed for the frames right
  after a pickup, decaying — the felt jerk). Replaced with a **constant-rate glide**
  (`move_toward`, `radius_ease_rate` 0.3 radius/s), so the reframe is a steady gentle drift with no
  initial burst. Verified with `tests/test_camera_jerk.tscn` (samples the live camera's per-frame
  move around a `grow_ship`): peak/baseline dropped from 2.9× to **1.6×** in third-person / 3-4 (the
  perspective views where it shows). Still driven off `ship_visual_radius` (Governing Rule 6 intact).
- **Pickups glow in the level's COMPLEMENTARY colour so they pop.** `ColorAid.complementary` returns
  the Itten/RYB opposite (hue + 6 on the 12-wheel) — the pairs people expect: purple→yellow,
  blue→orange, red→green (a naive HSV hue+0.5 would send purple to green, wrong). The floating
  pickup's glow is now `complementary(attach_color)` brightened; the **hull greeble it grants keeps
  `attach_color`**, so a run's parts still sit in the level palette while the collectible stands out.
- **Enemy numbers restored.** `enemies_per_density` back to 3 (from the perf-pass 2) across all
  generators; the `max_active_enemies` safety cap raised 6 → 12 (still bounds a runaway smart-hull
  spawn). The prop-density cut from the perf pass stays — that was the real cost, not enemies.
- **Verified:** `tests/test_color_cliff.tscn` (complementary pairs incl. tinted accents; iso/3-4
  canyon forces cliff, third-person doesn't). Full regression suite + clean boot.

## Tunnel Normals Fixed (2026-07-19)

Kevin: "on tunnel levels the normals are wrong." Root cause in `level_geo._flat_toward` (used by
`ribbon` + `floor_strip` for the corridor's interior surfaces): it correctly flipped each face
normal to point INWARD (toward the tube centre), but then always emitted ONE fixed winding. On the
faces where the normal got flipped, the winding no longer agreed with it — `cross(emitted)·normal`
came out **> 0**, violating Godot's convention — so those faces rendered inside-out, and the tunnel
material was `double_sided` to mask it (the exact anti-pattern CLAUDE.md warns against).

Fix: `_flat_toward` now chooses the emit order to match the inward normal
(`cross(emitted)·normal < 0`, like BoxMesh), and the corridor's wall + floor materials are now
**single-sided (`cull_back`)** — corridor is third-person-only, so you're always inside the tube
and never need the outer faces. Verified numerically (`tests/test_tunnel_normals.tscn`): the
isolated ribbon/floor meshes have correct winding AND inward normals, and a live 19-segment
corridor has 0 mis-wound faces and all `cull_back` materials.

## Soft Combat Zone (off-path leash + alarm) (2026-07-19)

Kevin: bring back a restriction so the player can't race too far off the path — but not a hard
wall; a light push-back that gives the instancing time to catch up (no stutter), with an on-screen
"Leaving Combat Zone" alarm (screen flashes red). Keep pushing and the world follows, alarm clears.

- **Mechanism (`ship._update_combat_zone`):** a rate-limited anchor `_zone_center` trails the ship.
  You roam freely within `zone_half_width` (14u) of it; past that, the OUTWARD steer velocity is
  capped to `zone_follow_speed` (4u/s — the instancing catch-up rate) plus a gentle inward spring
  (`zone_spring`). Not a wall — the anchor keeps easing toward the ship at `zone_follow_speed`, so a
  determined player keeps moving (the streamed world follows at that safe rate) and the alarm clears
  once they settle back inside. Reset per level (anchor = spawn point).
- **Per-axis, per-shape (`LevelDirector._configure_ship_zone`):** enabled only on free axes where
  the streamed world follows the ship laterally and can lag — X on open ground (surface / canyon /
  pillared), X+Y in open volume. Corridors are wall-bounded, so it's off there; locked axes are
  already pinned.
- **Alarm (`game_hud`):** a full-screen red `ColorRect` (behind the readouts) + a "⚠ LEAVING COMBAT
  ZONE ⚠" banner, both pulsing, shown while `ship.leaving_zone` and cleared otherwise / on death.
- **Verified:** `tests/test_combat_zone.tscn` (mirrors the ship math) — holding a direction stays
  bounded at ~`zone_half_width` (no runaway), sustained outward speed is capped to ~`zone_follow_speed`
  (4 vs the 6 steer speed), the alarm raises past the buffer and clears on release. Regression suite +
  clean boot green. Tunables: `zone_half_width` / `zone_follow_speed` / `zone_spring` on the ship.

## Half-Size Enemies + Slightly-Tracking Bullets (2026-07-19)

- **Enemies half size.** `EnemySpawner.create` multiplies the passed `enemy_scale` by
  `ENEMY_SCALE_MULT = 0.5` — one place, covers dumb + smart across all generators, shrinking both
  the visual (built from `enemy_scale`) and the hurtbox (`_hurt_radius`).
- **Player bullets gently home.** `projectile._home` (player team only; enemy shots stay straight)
  curves the bolt toward the nearest enemy/mine hurtbox that's within `homing_range` (45u) AND
  inside a seek cone (`HOMING_CONE`, ~45° of the bolt's heading — so it only assists shots you
  roughly aimed, never U-turns), capped at `homing_rate` (3 rad/s), speed constant, and re-aims the
  prism visual as it curves. Net: you line up in the general direction and the bolt finishes it.
- **Verified:** `tests/test_gameplay_tweaks.tscn` — enemy scale 2.0→1.0 for dumb+smart; a player
  bolt curves onto an in-cone enemy (0.32→0.00 rad) at constant speed; a target behind the cone is
  ignored. Regression suite + clean boot green. Tunables: `homing_rate` / `homing_range` on the
  projectile (lower them if the aim-assist feels too strong).

## Open Questions For Prototype Phase

- Exact win condition per level — currently a flat distance threshold (`level_target_distance`, placeholder 200 units). No sense yet of whether this should vary by shape family, escalate level-to-level (snake-3d precedent: escalating per-level survival targets), or be replaced with something more interesting than "survive N units."
- Functional power-up roster size and numeric balance (partially explored — `grow_ship()` + one `speed_boost` example proved the pattern; spread shot/homing/shields/etc. still unbuilt).
- Whether ship growth is unbounded or caps out (visual/gameplay legibility limit) — resolved for now: growth caps naturally once all 6 placeholder mount points are filled (no separate numeric cap needed). Real mount *count* is still just a placeholder guess.
- Mount-point layout on the base hull (how many, where, do they differ in size/slot-type) — 6 fixed points exist (front/rear/left/right/top/bottom) but every attachment is currently the same plain colored box regardless of pickup type; slot-type variety (e.g. weapon mounts vs. cosmetic-only mounts) not designed yet.
- Death penalty severity — currently instant-crash-on-any-hit with a full same-level retry (no damage buffer, no partial-hit forgiveness). Judgment call flagged for the user to weigh in on once there's more to actually navigate around.
- Whether procedural generation is seed-shareable (daily-run style) or purely random per run — the roller already takes an optional `RandomNumberGenerator`, so a shareable-seed mode is cheap to add later if wanted.
- How many feature words roll per level (fixed count vs. random count) and whether shape families are weighted equally or some appear more often — currently 2-4 random feature words, uniform shape-family chance; both arbitrary placeholders.
- ~~Whether corridor-shaped levels ever need a fourth "confined" viewpoint of their own~~ — moot now: Corridor supports all 5 viewpoints via dynamic surface omission (2026-07-13).
- How much the invented environment words survive first prototyping vs. get pruned/replaced — none pruned yet, only Corridor/Surface/Open Volume shapes have real generators so most invented words are still purely descriptive/untested geometry-wise.
- What form the distance-fade/pop-in mitigation effects should take (fog, fade-in shader on spawn, simply streaming further ahead than render-relevant, etc.) — explicitly called out as needed, especially for third-person, but not designed or built yet.
- What the new Modifier Word should actually *do* beyond flavor text — **now has a clear direction:** see "Level-Themed Attachments" above (drives what attachments look like on that level), possibly combined with palette tinting the environment too.
- Which of the "Other Proposed Level Attributes" (palette, hazard scaling, level-length variation, atmospheric fog, time-of-day) to build next, if any — presented as a menu, not yet prioritized.
- Whether the new Gravity Mode roll should be weighted/constrained by Shape Family or fully independent, and whether it should affect anything beyond debris (e.g. drifting uncollected pickups) — not yet implemented at all.
- ~~Power-ups are still static one-time scene nodes rather than part of level streaming~~ — **resolved 2026-07-17**: rebuilt as a streamed economy (`PowerUpStreamer`, see section above). Pickups now spawn continuously through the whole level, cosmetic/speed_boost/magnet mix, themed greeble attachments. Remaining sub-questions: pickup density-vs-level-number scaling (still flat), and the functional offense/defense roster (still blocked on no weapon/health system).
- Whether Enemies should scale in count/aggression by level number, get more archetypes, or ever be destroyable — no weapon/combat system exists yet, so for now "enemy" just means "moving obstacle."

These are intentionally left open — first pass is a grey-box prototype to test the game-flow-cycle + attachment feel before locking numbers.
