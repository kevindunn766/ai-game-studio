# Kindling — Design & Implementation Notes

Source of truth for intent is `../kindling-design-brief.md`. This file tracks what's actually been *built*, mirroring snake-3d/DESIGN.md's "confirmed mechanics" convention — but unlike that file, most of the sections below were built autonomously in one long overnight session and are **pending your review**, not yet confirmed-by-use the way snake-3d's entries are. Treat "Built" here as "implemented and headlessly verified," not "locked."

## Start here for a clean restart

- **Committed to git** (local commit `a2a9032`, master branch, not pushed) — per Kevin's explicit preference, no branches/PRs until a later stage; just keep committing locally as work lands.
- **Only Band 1 has been looked at in a real running game**, and it took three follow-up bug-fix passes to actually work (see "Real-world scale system", "Band 1 fuel density fix", and "Movement speed proportional to scale" below) — all invisible to headless testing, only surfaced from actual in-editor/gameplay feedback. **Assume Bands 2-9 have similar undiscovered bugs** until someone opens the editor and looks. Don't trust "all tests pass" as evidence the game looks or plays right — it only proves the logic is internally consistent, not that anything renders or feels correct.
- **Nothing is playtested.** Every charge/grow target, hazard shrink amount, threat timing, and fuel density across all 9 bands is a placeholder number, tuned by feel/analogy, not by anyone actually playing it.
- **Milestone 3 (Power-ups & Dynamic Events) is the one deliberately unbuilt thing** — a starter roster proposal is below, waiting on your approval, not an oversight or something skipped by accident.
- **Milestone 4 (Climb/leap/delayed-mass-follow locomotion) is now built** — headless-verified only, not yet looked at in-editor, same caveat as Bands 2-9. See its own section below.
- `../kindling-design-brief.md` is Kevin's own design words only — no status/build notes belong there. This file (`DESIGN.md`) is the sole build log/status/next-steps record.

## Real-world scale system (fixed after first in-editor look, see below)

**Hard project-wide rule: 1 Godot unit = 1 meter.** `GrowthController.flame_scale` is a literal real-world size in meters, not an abstract multiplier — Band 1 (Match) is 0.02-0.08m, Band 2 (Small Fire) 0.08-0.25m, Band 3 (Small-Medium) 0.25-0.6m. `Flame.mesh.scale` is driven directly from this value, so the flame is a genuinely tiny ~2cm box at the start of a run next to an ~8m tree.

This was **not** how it originally shipped — `flame_scale` started at an abstract `1.0` against a 1×1×1 base mesh, meaning the flame began life as a literal 1-cubic-meter box (bigger than a beach ball), and the camera/LOD/reach formulas were all tuned against that same abstract 1.0-5.5 range. Caught via Kevin's first real in-editor look: flame read as already-huge with no legible size relationship to the tree, the 40m yard felt like a small box with no room to explore, particles were imperceptibly tiny, and the scorch trail was flat opaque squares that never visibly grew. Root cause was the same thing in every case — nothing in the game had ever been anchored to real-world meters. Fixed by:
- `growth_controller.gd::BAND_TABLE` scale_min/scale_max → real meters (above).
- `camera_controller.gd` completely recalibrated (`BASE_SIZE`/`SIZE_PER_SCALE_UNIT`/`MIN_SIZE`) — ortho `size` now ranges ~0.43m (tight close-up) to ~2.5m across Bands 1-3, a real ~6x zoom-out, and the 40m parcel now reads as expansive since it's ~15-90x the visible frame instead of comparable to it.
- `flame.gd` ignite/jump reach decoupled from pure mesh-scale inheritance (IgniteArea moved from a child of Mesh to a direct child of Flame) — a literal 2cm flame proportionally scaled would never reach anything, so reach now uses a base-reach-plus-growth formula (`ignite_base_reach + scale_factor * ignite_reach_growth`, same shape for jump radius/fallback distance) instead.
- `Flame.mesh.position.y` now tracks `scale_factor * 0.5` dynamically (was a fixed 0.5 assuming ~1m scale) so the flame stays grounded instead of floating/clipping as it grows.
- Every `active_while_scale_below`/`active_scale_range` threshold across `prop_manager.gd`'s four tier tables (Quick Fuel, Structure Fuel, Hazards, Dousing Threats) rescaled to match — these would never have triggered correctly against the new tiny flame_scale range otherwise. Streaming radius constants (`VIEW_SPAN_MARGIN`/`BASE_PADDING`) retuned for the new small camera sizes too.
- Movement trail's scorch mark rebuilt as an actual shader (`shaders/scorch.gdshader`, UV-distance soft-circle falloff) replacing a flat opaque `BoxMesh` — was also sized off the old abstract scale range and would have rendered as an invisible sliver under the new real-meter numbers. Ember/ignite/structure-fuel burn particles bumped in size for visibility now that the camera is properly zoomed in.
- House foundation bumped from 6×8m (shed-sized) to a more realistic 10×14m footprint.

Landmark props (tree trunk, Quick Fuel dimensions like a 4cm grass blade or 30cm twig) were already built in sensible real-world meters from the start and didn't need changing — it was specifically the flame's own scale progression and everything derived from it that was wrong.

**Grass tuft visual**: `dry_grass` (Band 1 Quick Fuel) is an upside-down `CylinderMesh` cone — `top_radius` wide, `bottom_radius` 0, so the point sits at the ground and the "leaves" flare out at the top (opposite orientation from `pine_needle`'s normal point-up cone below it).

## Band 1 fuel density fix (second in-editor look — Kevin reported an empty-looking view)

Even after the scale fix above, Band 1 read as empty in the editor: "just a box on a green background, nothing moving because there aren't any items." The fuel *was* there in `BAND_TABLE`/`PROP_TIERS` (`twig`, `wrapper`, `leaf_litter`, `dry_grass`, all correctly gated), but three compounding problems meant almost none of it was ever actually visible:

1. `dry_grass`'s density/cell_size (0.6 density, 0.5m cells) was carried over unchanged from before the real-world-meters fix. Against the tiny ~0.43×0.24m camera view at match-scale, that math works out to well under 1 expected blade anywhere on screen at any moment. Fixed: cell_size 0.5→0.07m, density 0.6→0.85 (same treatment for `leaf_litter`, `twig`). Since cell placement is a deterministic hash of position (not randomized per run), this wasn't occasional bad luck — it was the exact same empty patch every single time the game launched, confirmed via a headless check before and after (0 instances within the visible radius → dozens).
2. That density increase then revealed a second problem: the flame's passive ignite radius sweeping through such dense grass while merely walking pumped in far more Growth Points than intended — a headless walk test showed the flame rocketing from Band 1 to Band 8 (scale 81.8m) within about 90 frames of normal movement. Fixed by decoupling visual density from growth economy: `dry_grass`/`leaf_litter` `charge_value` dropped an order of magnitude (0.6→0.08, 0.5→0.06) so the grass field is dense to look at but any single blade is nearly worthless as fuel, matching real-world intuition (a lawn looks like a lot of grass; burning one blade barely does anything). Re-verified: a full walk now lands at scale ≈0.07m, still inside Band 1, not blown through to Band 8.
3. Even at fixed density, the flame's own ignite radius (~0.11-0.14m at match-scale) auto-consumes anything that spawns that close almost the instant it appears — a small permanent "dead zone" right at the flame. The old camera view (`MIN_SIZE`/`BASE_SIZE` 0.4/0.35) left almost no margin beyond that dead zone, so most of what was visible *was* the cleared void. `camera_controller.gd` widened to 0.7/0.6 so there's a real ring of dense, un-eaten fuel visible outside the dead zone. Confirmed via headless check: 44 `dry_grass` + 28 `leaf_litter` instances now inside the visible radius at match-scale, up from 0.

**Known tradeoff, not yet addressed**: the density increase means ~3,200 individual Fuel nodes active at the top of Band 1's range (each with its own `Area3D`/`CollisionShape3D`/`MeshInstance3D`, so ~13,000 real scene nodes). This is what actually fixes the reported bug and hasn't caused a headless timeout/crash in testing, but it's a real performance concern for a mobile target — grass at this density is a textbook case for `MultiMeshInstance3D` batching instead of one node per blade. Flagging for a follow-up pass rather than solving now, since the immediate bug (nothing visible) is more urgent than a performance optimization that hasn't been proven to actually cause problems on-device yet.

## Movement speed proportional to scale (RESTORED — this is the current, confirmed model)

**History:** proportional speed → briefly flipped to inverse (small=fast) "per instruction," which also triggered a prop-streaming freeze → then flattened to a `2.0 m/s` constant → now **restored to proportional**, which is what Kevin actually wants: the flame should *feel* like it moves at the same speed at every scale. The inverse-change freeze was never the speed formula's fault — it was PropManager respawning its whole footprint every frame under fast small-scale movement, and that's independently fixed with a per-frame spawn-throttle queue that's still in place. So restoring proportional speed does **not** reintroduce the freeze.

**The math (perceived speed):** what the eye reads as speed is `world_speed / camera_view_span` (fraction of screen crossed per second). Deriving `world_speed` from the *same* size value that frames the flame holds that ratio constant *by construction*, regardless of the camera's size curve. Current formula, `flame.gd::current_move_speed()`:

`speed = CameraController.target_size_for_scale(scale_factor) / view_crossing_seconds`  (`view_crossing_seconds = 3.0`)

Verified via headless sweep across all 9 bands: crossing time holds at exactly **3.0s** at both ends of every band, world speed scaling from **0.233 m/s** at match-scale to **186.9 m/s** at Band 9's endpoint. `view_crossing_seconds` is the single knob that sets the felt speed (larger = more stately) — 3.0 is a first pass, not playtested. Acceleration (`accel_ramp_time`) is kept a flat constant on purpose, *not* scale-derived, so controls feel equally responsive at every size even though the top speed they ramp to varies by three orders of magnitude.

**Known follow-up (not fixed here, flagged):** `movement_trail.gd` thresholds `flame.velocity.length()` against a flat `move_speed_threshold = 0.15`, but proportional speed makes match-scale top speed only ~0.23 m/s — so embers kick in only near full-stick at tiny scale. Trail-system work; make the threshold scale-relative when that system is revisited.

## Fire particle system — replaces the grey-box cube player visual (built, headless structure only)

The player's two orange `BoxMesh` cubes (`Flame/Mesh` leading edge + `Flame/Body/BodyMesh` mass-follow bulk) are replaced by a reusable fire+smoke particle effect, `scripts/fire_effect.gd` (`class_name FireEffect`). Both scene nodes now run that script; `flame.gd` scales their node transform exactly as it scaled the cubes, so all existing growth/mass-follow machinery is reused unchanged.

**Fire physics modeled** (researched first — see the fire-physics report; sources: Katamari-adjacent particle work, GPU fire sim papers):
- **Buoyancy** — `ParticleProcessMaterial.gravity` is *positive* Y, so particles accelerate upward and the flame tapers.
- **Blackbody cooling gradient** — `color_ramp` runs hot white-yellow core → orange → red → transparent, so particles visually cool as they rise. Additive blend means the cool (dark) end fades to nothing for free.
- **Turbulence** — built-in `turbulence_*` noise gives the flicker/lick.
- **Froude-scaled flicker** — real flames flicker at f≈1.5/√D, so `set_flicker_for_scale()` drives `speed_scale` inversely with the flame's real size (clamped): a 2cm match shimmers ~2×, a 100m inferno billows ~0.6×. Called from `flame.gd::set_scale_factor()`.
- **Smoke** — a separate, slower, longer-lived, *expanding* (`scale_curve` grows), alpha-blended dark plume above the fire.

**Not big squares:** particles are billboarded (`BILLBOARD_PARTICLES`) soft-round dots — a **procedural radial `GradientTexture2D`** (white center → transparent edge), *no external texture asset*, matching the studio's procedural rule. `scale_min`/`scale_max` give a real spread of small sizes.

**Scaling:** `fire_effect.gd` is authored for a ~1m reference fire with `local_coords=true` particles, so scaling the node transform scales the whole sim (positions AND velocities) proportionally across 2cm→140m. No `position.y` offset anymore (the old centered cube needed one; fire emits upward from its ground-level origin).

**Trail (`movement_trail.gd`, reworked):** now two **world-space** (`local_coords=false`) systems — additive fire embers + alpha smoke — sharing `fire_effect.gd`'s soft-round particle material. World-space means emitted particles stay behind and fade where dropped, so a moving flame leaves a diminishing trail of fire + smoke that thins to nothing when it stops. Draw-mesh size, velocity and buoyancy are multiplied by `flame_scale` each frame (node scale doesn't reliably scale world-space particles). The scorch decal is unchanged.

**Verified headless:** an API-property check (turbulence, `FILL_RADIAL`, `BILLBOARD_PARTICLES`, `local_coords`, additive/mix blends, Froude flicker ordering) and a `Main.tscn` integration check (core fire+smoke emitting, body fire built, core scaled to ~0.02 at match, trail's two systems emitting while moving) both pass; all prior tests still pass. **Caveat, same as everything past Band 1: headless uses a dummy renderer, so this proves the systems instantiate/scale/emit correctly — it does NOT prove the actual on-screen look (particle shapes, colors, motion feel). That needs an in-editor look.** Used the established preload-const workaround in `movement_trail.gd` since the brand-new `FireEffect` class_name global doesn't resolve headless.

This also surfaced a real, unrelated bug in the same area: `CameraController.MAX_SIZE` was still `30.0`, a leftover from when only Bands 1-3 (max scale 0.6m) existed. Band 9 pushes `flame_scale` to 140m, which needs an uncapped view of ~560m — at the old cap the camera would've stopped zooming out around Band 6 while the flame kept growing past its own view, and (since speed is now derived from that same clamped value) movement would have silently stopped scaling too. Raised to `600.0`. Nothing yet has actually run at Band 6+ in a live game to confirm this feels right — flagged as another "headless-verified only" item alongside everything else past Band 1.

## Fuel spawn window widened, then a bad "zero points" mechanic added and reverted

Kevin's feedback: "the grass should continue to spawn everywhere. At some scale it just doesn't give points." First pass at this: widened the existing spawn-gating fields (`active_while_scale_below`/`active_scale_range`, ~4-5x wider — this part was correct and is still in place) **and** invented a second, separate mechanic on top of it — a `value_while_scale_below`/`value_scale_range` pair that made `register_burn()` skip entirely once a fuel type was judged "outgrown," even while it kept spawning.

That was wrong, and it broke the game: once dense, common fuel like grass crossed into "zero points," the only things still awarding anything were much rarer tiers (`small_plant` etc.), so a normal player just walking through mostly-grass terrain could burn constantly and never accumulate enough to grow — reported as "it just stops burning anything and stops growing." **Reverted entirely** — deleted `_has_growth_value()`, `_find_tier_by_id()`, and every `value_*` field. `_on_fuel_ignited()`/`_on_structure_fully_burned()` are back to unconditionally awarding `charge_value` for anything currently spawned, exactly as they were originally.

The brief itself (Camera, Art Direction & Continuous Growth section) already specifies the actual mechanic, in these exact words: *"once a fuel type is far below the player's current scale... the generator stops placing new instances of it. Existing tiny objects don't need to be tracked or rendered at giant scale."* That's one thing — stop spawning new ones once outgrown — not two decoupled systems. The widened spawn window (part one of the original fix) already satisfies "grass should continue to spawn everywhere" on its own; no separate points mechanic was ever called for.

Verified live: a continuous 600-frame walk through dense grass now shows charge/grow climbing every single checkpoint with no stalls, correctly crossing from Charge into Grow phase and increasing `flame_scale` throughout.

**Didn't widen this further than ~4-5x, and didn't touch Hazards/Dousing Threats at all** (the request was specifically about fuel/points, and hazards/threats don't have a "points" concept to decouple). The performance ceiling from the Band 1 density fix above still applies and compounds here: spawn count scales with `(streaming_radius / cell_size)²`, so a small-`cell_size` tier (grass, `leaf_litter`) spawning across a much larger camera view gets expensive fast — this is the same `MultiMeshInstance3D`-batching-candidate tradeoff already flagged, now a bit more pressing since the spawn window is wider. Didn't solve that now for the same reason as before: the requested behavior change is more urgent than a performance optimization that hasn't been proven to actually hurt on-device yet.

## Epoch registry — tracking which objects spawn during which scale band

`PropManager.get_epoch_registry() -> Dictionary` maps each `GrowthController` band index to the list of tier ids (Quick Fuel, Structure Fuel, Hazard, and Dousing Threat together) that are eligible to spawn once the flame reaches that band's midpoint scale. It's derived by running the same `_should_spawn_detail()` gate the real streaming logic uses — not a hand-maintained parallel table — so it can't silently drift out of sync with the actual spawn thresholds the way the scale-mismatch bug above did (that bug was exactly this failure mode: thresholds that looked right on paper but never actually triggered).

Verified in `tests/test_epoch_spawn_verification.gd`: registry structure, cross-checked against `GrowthController.BAND_TABLE`'s own `fuel_tiers` lists (so the growth-eligibility table and the world-spawn table can't disagree about which band a fuel belongs to), and a deterministic density scan (`_raw_should_spawn` across a wide synthetic cell range, not live streaming) confirming every tier the registry lists for a band is actually capable of spawning there — and that tiers *not* listed for a band actually don't. The deterministic scan is deliberate: sparse tiers (`cat`, `dew_drop`, density 0.015-0.02) may not appear in a real playthrough's short/local streaming footprint by chance, which would make a live-only check flaky without indicating a real bug.

Current registry (all nine bands, see "All 9 bands" section below):
- Band 0 (Match): `dry_grass, twig, wrapper, leaf_litter, ant, fly, dew_drop`
- Band 1 (Small Fire): `small_plant, pine_needle, twig_nest, beetle, earthworm, moth, squirt_bottle`
- Band 2 (Small-Medium): `brush_pile, dry_shrub, cardboard_box, bird, cat, sprinkler`
- Band 3 (Medium): `campfire_log, kindling_pile, wooden_fence, dog, person_blanket, garden_hose`
- Band 4 (Medium-Large): `tree_grove, shed, car, homeowner, fire_extinguisher`
- Band 5 (Large): `tree_stand, house, resident, security_guard, hose_reel_firefighter`
- Band 6 (Extra-Large): `city_block, first_responder, fire_truck_pumper`
- Band 7 (Extra-Extra-Large): `forest_section, neighborhood_block, fire_crew, ladder_company`
- Band 8 (Massive): `district, evacuee, water_bomber`

(Registry entries above are each band's *unique* tiers at its exact midpoint; adjacent bands overlap at their boundaries by design, same as Bands 1-3 already did — e.g. Band 2 and Band 3 both spawn `brush_pile`/`dry_shrub` right at their shared transition, so growth doesn't feel like a hard cutoff.)

## All 9 bands built

Per the brief's own Build Milestones ("5. Remaining bands, one at a time, each logged into the Asset Registry as built"), Bands 4-9 (Medium through Massive) are now built — same grey-box-primitive pattern as Bands 1-3, no new mechanics, just more `BAND_TABLE`/`PROP_TIERS`/`STRUCTURE_FUEL_TIERS`/`HAZARD_TIERS`/`DOUSING_THREAT_TIERS` entries and matching visual-builder cases. Real-world-meter scale progression continues Band 3's escalation:

| Band | Name | Scale range | Quick Fuel | Structure Fuel | Hazards | Dousing Threat |
|---|---|---|---|---|---|---|
| 3 | Medium | 0.6-1.6m | campfire_log, kindling_pile | wooden_fence | dog, person_blanket | garden_hose |
| 4 | Medium-Large | 1.6-4.0m | tree_grove | shed, car | homeowner | fire_extinguisher |
| 5 | Large | 4.0-9.0m | tree_stand | house | resident, security_guard | hose_reel_firefighter |
| 6 | Extra-Large | 9.0-22.0m | — | city_block | first_responder | fire_truck_pumper |
| 7 | Extra-Extra-Large | 22.0-55.0m | forest_section | neighborhood_block | fire_crew | ladder_company |
| 8 | Massive | 55.0-140.0m | — | district | evacuee (deliberately low-threat, per the brief) | water_bomber ("final confrontation," no scripted end-of-run sequence built) |

`PropManager.PARCEL_HALF_EXTENT` expanded from 20m (40m yard, enough for Bands 1-3) to 600m to physically fit Band 9's district-scale Structure Fuel in the same continuous world; `Main.tscn`'s ground `PlaneMesh` expanded to match (1200x1200) so later-band content doesn't float over void. All charge/grow targets and hazard/threat tuning (shrink amounts, zone radii, wander speeds) are placeholder numbers scaled up proportionally from Bands 1-3's own placeholders — none of this is playtested, same caveat as everything else in this document.

Verified end-to-end with `tests/test_epoch_spawn_verification.gd` (which auto-extends to however many bands `BAND_TABLE` has — no test changes were needed to cover Bands 4-9) plus a live 9-band sweep confirming no crashes, monotonic camera zoom (~0.49m to ~12.3m across the full range), and reasonable node counts throughout.

## Milestone 1 — Continuous Growth + Camera Zoom Prototype (Built, reviewed)

- World geometry is fixed scale forever; only the flame scales up (`flame.gd::scale_factor`, driven by `growth_controller.gd`). Camera zooms out to match (`camera_controller.gd`, orthogonal `Camera3D.size`), exact same `lerp` pattern as snake-3d's `camera_controller.gd`.
- Charge → Grow cycle: `growth_controller.gd::register_burn()`. Charge phase fills a bar with no size change; Grow phase scales the flame; band-to-band overflow spills forward without losing value.
- Free-roam movement via a **continuous** (not 4-way-snapped) camera-relative touch joystick (`touch_joystick.gd`) — adapted from snake-3d's discrete version since Kindling free-roams rather than moving on a grid.
- Quick Fuel touch-and-burn (`fuel.gd`): ignite on contact, scale-to-zero burn-down, no dissolve shader (that's Structure Fuel's, see M2 below).
- Movement trail (`movement_trail.gd`): scorch decal (fades ~25s, placeholder per the brief's own open question) + toggled ember particles.
- Double-tap jump (`flame.gd::jump()` + `tap_detector.gd`): physics-query nearest eligible target in a forward cone; guaranteed fallback hop if nothing qualifies.
- Charge/Grow HUD bar (`hud_bar.gd`): brightness pulse during Charge, fill during Grow, squash-pop on band change.
- Procedural streamed props (`prop_manager.gd`): per-tier independent grids, streaming radius keyed off camera zoom (not just XZ position, unlike snake-3d), scale-gated LOD stops new spawns of outgrown tiers without force-removing existing ones.
- Bands 1-2 only, single bounded yard parcel (40×40, `PropManager.PARCEL_HALF_EXTENT = 20.0`).

## Milestone 2 — Vertical Slice, Bands 1-3 (Built this session, pending review)

### Band 3 added
`growth_controller.gd::BAND_TABLE` now has a third entry ("Small-Medium", charge_target 22 / grow_target 60, scale 3.2→5.5). Fuel tiers: `brush_pile`, `dry_shrub` (Quick Fuel), `cardboard_box` (Structure Fuel, see below).

### Structure Fuel (`structure_fuel.gd`)
- Own health bar (`max_health`), only drains while the flame stays in contact (`Flame._touching_structures`, drained every physics tick via `StructureFuel.drain()`), pauses (doesn't revert) when contact breaks.
- Shared dissolve shader (`shaders/dissolve.gdshader`): procedural UV-based value noise, `burn_progress` uniform 0→1, no external texture asset.
- Full points only awarded when health reaches zero (`PropManager._on_structure_fully_burned`) — no partial credit for a stopped-short burn, per the brief.
- Distinct burnt-down husk mesh spawns in as the pristine mesh dissolves away, persists indefinitely (open question from the brief's own text — resolved here as "persist for now," revisit for pooling/cleanup if it becomes a real perf problem).
- **Judgment call**: the brief's own Scale Tier table doesn't introduce a real Structure Fuel example until Band 5 ("a shed"), but this milestone's own scope explicitly requires proving Quick-vs-Structure within Bands 1-3. Picked `cardboard_box` (already listed as Band 3 Quick Fuel-ish content in the brief's illustrative table) as the first Structure Fuel test object rather than waiting. **Flagging for your review** — may not be the object you'd have picked.

### Non-lethal hazards (`hazard.gd`)
- Grey-box wander AI (pick random point within a local radius, walk to it, pause, repeat) — same "greedy heuristic, no real pathfinding" spirit as snake-3d's enemy AI, scaled down.
- Contact applies `GrowthController.subtract_growth()` (see below), gated by a 1s invulnerability window on the flame (`Flame.hit_invuln_duration`) so standing inside one doesn't shred Growth Points every physics tick.
- Hazards persist after contact (not consumed like Fuel).
- All 7 types from the brief's table, one row each in `prop_manager.gd::HAZARD_TIERS`: ant/fly (Band 1), beetle/earthworm/moth (Band 2), bird/cat (Band 3). Shrink amounts and wander tuning are placeholder numbers, not playtested.

### subtract_growth() rewritten (`growth_controller.gd`)
The M1 stub only handled shrinking within the current band. Now mirrors `register_burn()`'s forward spillover in reverse: drains the current phase's amount, and on hitting zero, retreats a full band (landing at the previous band's Grow-phase boundary) and keeps draining any leftover — matches the brief's "potentially dropping back into the previous band's fuel-eligibility range if severe," floored at Band 1's `scale_min` ("never below match-flame size").

### Dousing Threats (`dousing_threat.gd`) + death/reset
- One unified Telegraph → Active (lethal) → Cooldown state machine for all three bands' threats, rather than bespoke mechanics per type — **judgment call**, a deliberate M2 simplification to prove "recognize the tell, avoid the zone" before any band-specific flavor (falling droplet, squirt-bottle aim, sprinkler spray shape) gets built out.
- `dew_drop` (Band 1), `squirt_bottle` (Band 2), `sprinkler` (Band 3) — per-tier zone radius/timing only; visual "tell" is a growing/glowing ground ring, not yet the brief's specific "shadow/glint" language.
- Streamed sparsely (large cell_size, low density) via the same `prop_manager.gd` mechanism as Fuel/Hazards, rather than hand-placed — **judgment call**, may want deliberate placement later instead of random scatter.
- On lethal overlap: `KindlingManager.trigger_death()` → full scene reload. **Not** the brief's actual target flow (return to menu/leaderboard, score = highest tier + total Growth Points) — no menu/leaderboard system exists yet. This is a placeholder death flow, explicitly out of scope to build fully this milestone.

## Milestone 3 — PROPOSED roster, NOT built (needs your approval first)

The brief is explicit that Power-ups and Dynamic Events each need "a first concrete locked list before wide implementation" — unlike M1/M2, this is content the brief deliberately leaves to a real design pass rather than something I should just invent and ship autonomously. Nothing below is implemented. Drafted as a starting proposal so there's something concrete to react to rather than a blank page — change, cut, or replace freely.

**Power-ups** (brief locks the pattern from snake-3d's own precedent: once a roster ships, expanding it later is a fresh approval pass, not organic growth mid-implementation):
- *Gas can* (brief's own example) — instant burst ignites everything Quick Fuel within a radius at once, no Charge/Grow distinction, straight Growth Points.
- *Rain shield* — brief 6-10s immunity specifically to Dousing Threats only (not non-lethal hazards) — gives a legitimate "learn the pattern without dying while learning it" tool, thematically ironic (water protecting a fire) which might read as confusing — flagging that tension rather than deciding it away.
- *Ember trail boost* — temporary jump-radius/movement-speed increase, cheap to build (reuses `Flame.base_jump_radius`/`move_speed` multipliers already exported), lower-impact than the other two, good "always useful, never game-changing" filler slot.

**Dynamic Events** (brief's own example: leaf-blower NPC, purely positional displacement, no direct Growth Point loss):
- *Leaf-blower NPC* (brief's own example) — as specified.
- *Garden hose drag* — a hazard-adjacent NPC drags a hose across the ground; touching the hose itself (not the water) is a displacement/trip, not lethal — gives the displacement category a second, distinct-feeling instance rather than shipping with only one example forever.

## Milestone 4 — Climb/leap/delayed-mass-follow locomotion (Built, headless-verified only)

Per the brief's own Build Milestones ("4. Climb/leap/delayed-mass-follow locomotion system — once tree- and building-scale bands are reachable; not needed before then"): now unblocked since Bands 4-9 exist. Two pieces, both reusing the existing double-tap jump rather than adding a new input:

**Climb & leap** (`flame.gd::climb_arc_height()`, static/pure): jumping onto a not-yet-fully-burned `StructureFuel` now arcs proportionally higher than a flat fuel-to-fuel hop — `base_jump_height + target.height * climb_height_fraction` (0.5 default) — so leaping onto a shed, house, or city block visibly rises toward its own height rather than a uniform bounce, reading as "crawling up the vertical surface." Added a `height` field to every `STRUCTURE_FUEL_TIERS` entry in `prop_manager.gd`, matching each tier's own pristine mesh Y size (`cardboard_box` 0.45m up to `district` 10.0m), passed onto `StructureFuel.height` at spawn time. Leaping structure-to-structure (tree to house, house to house) was already mechanically possible since `_find_jump_target()` already considers any eligible `StructureFuel` in range — this milestone's real addition is the height-aware arc, not new targeting logic.

**Judgment call, not silently decided away**: the brief also names "a tree trunk" as something the flame climbs, but trees (`tree_grove`/`tree_stand`/`forest_section`) are Quick Fuel in this project's existing tier split (instant catch-and-disappear, no persistent geometry to climb) — that assignment predates this milestone and isn't something this pass changed. Climbing only actually applies to Structure Fuel (shed/car/house/city_block/neighborhood_block/district — the "building wall" case), not trees, until/unless the fuel-type assignment itself is revisited. Flagging this gap rather than quietly reinterpreting which objects count as climbable.

**Always lands at ground level, not perched partway up**: a persistent "attached to a wall, movement plane rotates" state is a real state machine this grey-box pass didn't build — the taller arc is a visual flourish (goes up, comes back down at the target's own ground position), not an actual climbing mode change. Noting this as a real scope gap, not a bug: revisit if "hangs onto the wall until the next leap" is the actual feel wanted.

**Delayed mass-follow** (`flame.gd::sample_history()`, static/pure + a new `Body`/`BodyMesh` sibling node under `Flame` in `Main.tscn`): every physics tick, `Flame` records its own `position` into a timestamped history buffer; `Body` continuously samples that buffer `mass_follow_delay_seconds` (0.18s default) in the past and eases toward it, so the fire's "bulk" visibly trails its own leading edge — most noticeable during fast repositioning (a climb/leap arc) rather than slow ground movement, matching the brief's "gives the fire body weight and stretch during climbs/leaps" framing. Same underlying idea as snake-3d's segment-follows-head pattern per the brief's own suggestion, adapted from grid-discrete (array of past cells) to continuous (interpolated timestamped buffer) since Kindling free-roams. `Body` mirrors `Mesh`'s own scale/grounding tween in `set_scale_factor()`, just at `body_scale_fraction` (0.85) of the leading edge's scale so the two read as one fire with a hot tip rather than two identical stacked boxes.

Verified via `tests/test_flame_locomotion.gd` (pure-function coverage of both `climb_arc_height()` and `sample_history()`, including empty/before-range/after-range/interpolation cases) plus a disposable scratch integration check (deleted after use, per this studio's convention) that loaded the real `Main.tscn`, spawned a height-5.0m `StructureFuel` in jump range, called `Flame.jump()`, and let real engine frames advance: confirmed the flame actually targeted and landed exactly on the structure (not the fallback hop), and that `Body` sat ~1.5m off from `Flame`'s own position shortly after the arc — a real, measurable stretch effect, not just code that runs without crashing.

**Not yet looked at in a running game** — same caveat as Bands 2-9, this is headless-verified only.

## Frond-system foliage — phase-1 plant set (built, in-editor verified via renders)

Per the design brief's new "Procedural Asset & World Generation System" section, the frond system is the plant workhorse. Ported chimera-drift's `LevelGeo.frond` into `scripts/frond.gd` (no `class_name` — preload-const per the headless rule) and retooled it. Shared conventions across every plant: real-world metres, flat per-face normals with Godot-convention winding (CLAUDE.md mesh rule), **vertex COLOR = albedo** (per-instance tint + a green→dry-ochre tip gradient), **sway weight baked into UV.y** (moved off COLOR so COLOR can carry colour; a future wiggle shader reads UV.y), and a **`thickness` param**: 0 = flat two-sided blades (lightweight / far LOD), >0 = solid triangular-prism blades (near LOD). `grass_lod(scale, seed, mat, near_dist)` pairs a thick-near and flat-far mesh via Godot `visibility_range` (same seed ⇒ identical layout, invisible swap). Render everything with a `vertex_color_use_as_albedo` material.

**Kevin's stem-zero rule:** `Frond.build(scale, seed, stem_length, thickness)` with `stem_length == 0` makes grass (blades straight from the ground); `> 0` grows a stalked frond.

Three phase-1 foliage types, each with built-in variety so a scattered field reads naturally (all logged in `ASSET_REGISTRY.md`):
- **Grass** — clump = main tuft + 2–5 dispersed child tufts; blade origins spread across a disc; dome splay (rim blades tip down & out, parabolic in radius); **4 species** (fresh lawn / tall meadow / dry olive / broad lush) driving palette + proportions; random dry-ochre tips.
- **Clover** (`build_clover`) — domed clump of thin petioles topped with rounded (obovate) trefoil leaflets; **3 species tints**, rare **four-leaf**, occasional **white→faint-pink globular flower heads**.
- **Dandelion** (`build_dandelion`, `flower_kind` -1/0/1/2) — basal leaf rosette + scape with **three forms**: wide/dense **yellow→orange flower** (short scape), white **seed puff** (tall scape), green **unopened bud**.

These three are the **locked phase-1 foliage set** (per Kevin: "move forward with these three"). Verified by rendered screenshots (real GPU render via a non-headless `--script` scene, screenshots inspected — not just no-crash). **Not yet wired into world spawning/streaming** — that's the next step (a pool of clump variants MultiMesh-scattered, with `grass_lod` for the near ring), and the `.png` card LOD for the tiniest scum is still to come. Cards/billboards not built yet; the current `prop_manager.gd` grass (`dry_grass` one-node-per-blade) is still what runs in-game until placement swaps to this.

## Known gaps / explicitly deferred
- No menu, leaderboard, or persistent score — death just reloads the scene.
- No audio.
- Yard parcel is still a single bounded 40×40 area; Band 3's larger flame scale (up to 5.5) and jump radius make this feel tight — zone/parcel expansion is out of scope per the brief (that's a post-Vertical-Slice design pass).
- Dousing Threat visuals are placeholder rings, not the brief's specific per-type tells.
- No power-ups, no Dynamic Events (leaf-blower etc.) — both explicitly out of scope until after the vertical slice per the brief's Build Milestones.
