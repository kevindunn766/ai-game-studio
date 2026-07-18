# Kindling — Asset Registry

Living document, per `../kindling-design-brief.md`'s Asset Registry section. Every stand-in asset gets a row the moment it's created, one per asset, no batching. Columns are locked; final art direction is an explicit later decision, deferred until gameplay is polished.

| ID | Tier | Role | Stand-in (pristine) | Stand-in (burnt-down, Structure Fuel only) | Intended final look (notes for future art pass) | Status |
|---|---|---|---|---|---|---|
| FLAME_01 | player (all tiers) | player | Fire + smoke `GPUParticles3D` (`fire_effect.gd`): additive billboarded soft-round particles (radial `GradientTexture2D`, no texture asset), blackbody cooling color ramp, buoyant +Y gravity, turbulence flicker (Froude-scaled: fast at match, slow at inferno), plus an alpha smoke plume. Leading `Mesh` core + smaller trailing `Body/BodyMesh` bulk (mass-follow). Scales with `GrowthController.flame_scale` via node transform | n/a | Volumetric/shader-driven flame body, licking tongues of fire, brightens during Charge | Built (headless-verified structure only — actual look needs an in-editor look) |
| GROUND_01 | n/a | prop (yard parcel backdrop) | 40x40 `PlaneMesh`, flat green-brown `StandardMaterial3D` | n/a | Textured lawn/dirt with patchy detail | Built |
| PROP_TREETRUNK_01 | landmark (future Structure Fuel, later band) | prop | `CylinderMesh` trunk + `SphereMesh` canopy, fixed position, non-burnable in M1 | n/a | Detailed bark-textured trunk, leafy canopy | Built |
| PROP_HOUSEFOUNDATION_01 | landmark (future Structure Fuel, much later band) | prop | Flat grey `BoxMesh` slab, fixed position, non-burnable in M1 | n/a | Concrete foundation with visible texture/cracks | Built |
| FUEL_DRYGRASS_01 | 1 | Quick Fuel | Upside-down green `CylinderMesh` cone (wide top, pointed base) as a stylized tuft, `dry_grass` tier in `prop_manager.gd` | n/a | Individual grass blade clusters, wind sway | Built |
| FUEL_TWIG_01 | 1 | Quick Fuel | Thin brown `CylinderMesh`, `twig` tier | n/a | Bark-textured stick with snapped ends | Built |
| FUEL_WRAPPER_01 | 1 | Quick Fuel | Flat silver `BoxMesh`, `wrapper` tier, slight metallic | n/a | Crumpled foil/plastic wrapper | Built |
| FUEL_LEAF_01 | 1 | Quick Fuel | Flat brown `BoxMesh`, `leaf_litter` tier | n/a | Dried curled leaf litter | Built |
| FUEL_PLANT_01 | 2 | Quick Fuel | Small green `SphereMesh`, `small_plant` tier | n/a | Small leafy shrub/sprout | Built |
| FUEL_PINE_01 | 2 | Quick Fuel | Dark green cone `CylinderMesh`, `pine_needle` tier | n/a | Fanned pine needle cluster | Built |
| FUEL_TWIGNEST_01 | 2 | Quick Fuel | Brown `TorusMesh`, `twig_nest` tier | n/a | Woven nest of dry twigs | Built |
| FX_SCORCH_DECAL_01 | n/a | movement trail | Flattened dark `BoxMesh` decal, alpha-fades over ~25s, `movement_trail.gd` | n/a | Baked scorch texture decal on ground material | Built |
| FX_EMBER_TRAIL_01 | n/a | movement trail | Two world-space (`local_coords=false`) `GPUParticles3D` in `movement_trail.gd`: additive fire embers + alpha smoke, soft-round particles shared with `fire_effect.gd`, emit while moving so the trail diminishes when stopped, sized/velocity-scaled by `flame_scale` each frame | n/a | Textured ember sprite sheet, glow shader | Built (headless-verified structure only) |
| FX_BURN_PARTICLES_01 | n/a | Quick Fuel ignite feedback | `GPUParticles3D` one-shot burst on `Fuel.ignite()`, orange `QuadMesh` billboards | n/a | Fire/ember/smoke sprite burst | Built |
| HUD_CHARGEGROW_BAR_01 | n/a | HUD | `ColorRect` bar (`hud_bar.gd`): brightness pulse during Charge, fill during Grow, squash-pop on band change | n/a | Stylized HUD chrome matching final UI theme | Built |
| FUEL_BRUSHPILE_01 | 3 | Quick Fuel | Squashed brown `SphereMesh`, `brush_pile` tier | n/a | Tangled cluster of dry branches | Built |
| FUEL_DRYSHRUB_01 | 3 | Quick Fuel | Olive `SphereMesh`, `dry_shrub` tier | n/a | Dried-out bush with sparse leaves | Built |
| STRUCT_CARDBOARDBOX_01 | 3 | Structure Fuel | Tan `BoxMesh`, `structure_fuel.gd` + shared dissolve shader (`shaders/dissolve.gdshader`) | Flattened black `BoxMesh`, spawned by `_spawn_burnt_husk()` | Cardboard box with visible flaps/creases; husk = collapsed charred cardboard | Built |
| HAZARD_ANT_01 | 1 | non-lethal hazard | Tiny dark `CapsuleMesh`, `hazard.gd` wander AI | n/a | Segmented ant body, antennae | Built |
| HAZARD_FLY_01 | 1 | non-lethal hazard | Tiny dark `SphereMesh`, hovers, faster wander | n/a | Translucent wings, buzzing animation | Built |
| HAZARD_BEETLE_01 | 2 | non-lethal hazard | Small squashed green `SphereMesh`, metallic | n/a | Shelled carapace with sheen | Built |
| HAZARD_EARTHWORM_01 | 2 | non-lethal hazard | Thin pink `CapsuleMesh`, slow wander, ground-hugging | n/a | Segmented worm body | Built |
| HAZARD_MOTH_01 | 2 | non-lethal hazard | Small pale `BoxMesh`, hovers, erratic-fast wander | n/a | Dusty patterned wings | Built |
| HAZARD_BIRD_01 | 3 | non-lethal hazard | Tan `SphereMesh` (elongated), hovers | n/a | Feathered body, beak, hopping gait | Built |
| HAZARD_CAT_01 | 3 | non-lethal hazard | Tan-grey `CapsuleMesh`, largest hazard | n/a | Full cat model, tail, ears | Built |
| DOUSING_DEWDROP_01 | 1 | Dousing Threat (instant-kill) | Small translucent blue `SphereMesh` hanging overhead + glowing ground ring telegraph, `dousing_threat.gd` | n/a | Glistening droplet with a real shadow/glint tell (brief's specific language, not yet matched) | Built |
| DOUSING_SQUIRTBOTTLE_01 | 2 | Dousing Threat (instant-kill) | Red `CylinderMesh` bottle + glowing ground ring telegraph | n/a | Detailed toy squirt-bottle, aimed spray cone instead of a radial zone | Built |
| DOUSING_SPRINKLER_01 | 3 | Dousing Threat (instant-kill) | Grey metallic `CylinderMesh` head + glowing ground ring telegraph | n/a | Rotating spray-head sprinkler with a real radial spray pattern | Built |
| FUEL_CAMPFIRELOG_01 | 4 | Quick Fuel | Brown `CylinderMesh` log, `campfire_log` tier | n/a | Bark-textured log with char marks | Built |
| FUEL_KINDLINGPILE_01 | 4 | Quick Fuel | Squashed brown `SphereMesh`, `kindling_pile` tier | n/a | Stacked kindling sticks | Built |
| STRUCT_WOODENFENCE_01 | 4 | Structure Fuel | Flat brown `BoxMesh` panel + dissolve shader | Flattened black `BoxMesh` husk | Weathered wood-plank fence panel | Built |
| HAZARD_DOG_01 | 4 | non-lethal hazard | Brown `CapsuleMesh`, ground-hugging wander | n/a | Full dog model, fur, tail | Built |
| HAZARD_PERSONBLANKET_01 | 4 | non-lethal hazard | Blue-grey upright `CapsuleMesh` | n/a | Person figure holding a blanket, swatting animation | Built |
| DOUSING_GARDENHOSE_01 | 4 | Dousing Threat (instant-kill) | Green upright `CapsuleMesh` + ring telegraph | n/a | Person figure holding/aiming a garden hose | Built |
| FUEL_TREEGROVE_01 | 5 | Quick Fuel | Dark green `SphereMesh` clump, `tree_grove` tier | n/a | Small cluster of distinct tree models | Built |
| STRUCT_SHED_01 | 5 | Structure Fuel | Grey-tan `BoxMesh` + dissolve shader | Flattened black `BoxMesh` husk | Backyard storage shed, door/window detail | Built |
| STRUCT_CAR_01 | 5 | Structure Fuel | Red metallic `BoxMesh` + dissolve shader | Flattened black `BoxMesh` husk | Sedan silhouette, windows/wheels | Built |
| HAZARD_HOMEOWNER_01 | 5 | non-lethal hazard | Tan upright `CapsuleMesh` | n/a | Person figure with rake/shovel | Built |
| DOUSING_FIREEXTINGUISHER_01 | 5 | Dousing Threat (instant-kill) | Red metallic `CylinderMesh` + ring telegraph | n/a | Handheld fire extinguisher with nozzle/hose detail | Built |
| FUEL_TREESTAND_01 | 6 | Quick Fuel | Larger dark green `SphereMesh` clump, `tree_stand` tier | n/a | Denser cluster of mature trees | Built |
| STRUCT_HOUSE_01 | 6 | Structure Fuel | Beige `BoxMesh` + dissolve shader | Flattened black `BoxMesh` husk | Full house model, roof/windows/siding | Built |
| HAZARD_RESIDENT_01 | 6 | non-lethal hazard | Purple upright `CapsuleMesh` | n/a | Varied civilian person models | Built |
| HAZARD_SECURITYGUARD_01 | 6 | non-lethal hazard | Dark navy upright `CapsuleMesh` | n/a | Uniformed guard figure | Built |
| DOUSING_HOSEREELFIREFIGHTER_01 | 6 | Dousing Threat (instant-kill) | Yellow upright `CapsuleMesh` + ring telegraph | n/a | Firefighter figure with hose reel gear ("first heavy equipment tease" per the brief) | Built |
| STRUCT_CITYBLOCK_01 | 7 | Structure Fuel | Grey `BoxMesh` cluster + dissolve shader | Flattened black `BoxMesh` husk | Multiple connected building facades | Built |
| HAZARD_FIRSTRESPONDER_01 | 7 | non-lethal hazard | High-vis orange upright `CapsuleMesh`, emissive | n/a | EMT/police figure, radio/gear detail | Built |
| DOUSING_FIRETRUCKPUMPER_01 | 7 | Dousing Threat (instant-kill) | Red metallic `BoxMesh` vehicle + ring telegraph | n/a | Full pumper fire truck model, hose reel/ladder detail | Built |
| FUEL_FORESTSECTION_01 | 8 | Quick Fuel | Large dark green `SphereMesh`, `forest_section` tier | n/a | Dense forest canopy chunk | Built |
| STRUCT_NEIGHBORHOODBLOCK_01 | 8 | Structure Fuel | Muted grey `BoxMesh` + dissolve shader | Flattened black `BoxMesh` husk | Multiple houses/streets, aerial-readable layout | Built |
| HAZARD_FIRECREW_01 | 8 | non-lethal hazard | Red upright `CapsuleMesh`, turnout-gear color | n/a | Firefighter crew figure, full gear | Built |
| DOUSING_LADDERCOMPANY_01 | 8 | Dousing Threat (instant-kill) | Red metallic `BoxMesh` vehicle (bigger than the pumper) + ring telegraph | n/a | Ladder truck with extended aerial ladder | Built |
| STRUCT_DISTRICT_01 | 9 | Structure Fuel | Dark grey `BoxMesh` + dissolve shader (largest Structure Fuel, final band) | Flattened black `BoxMesh` husk | Skyline/district silhouette | Built |
| HAZARD_EVACUEE_01 | 9 | non-lethal hazard (explicitly low-threat per the brief) | Neutral grey-beige upright `CapsuleMesh` | n/a | Crowd of fleeing civilians, "evacuation chaos" set dressing | Built |
| DOUSING_WATERBOMBER_01 | 9 | Dousing Threat (instant-kill, "final confrontation" per the brief) | Yellow-tan `BoxMesh` (airborne, no scripted end-of-run sequence built yet) + ring telegraph | n/a | Aerial firefighting aircraft/helicopter with Bambi bucket | Built |
| FLAME_BODY_01 | player (all tiers) | player (Milestone 4: delayed mass-follow) | Dimmer orange emissive `BoxMesh` cube, sibling `Body`/`BodyMesh` under `Flame`, trails `FLAME_01`'s position via a recorded position-history buffer (`flame.gd::sample_history()`) | n/a | Same volumetric flame material as the leading edge, visually one continuous body with a hot tip | Built |
| FROND_SYSTEM | n/a | foliage generator (shared tech) | `scripts/frond.gd` — procedural plant-geometry generator ported from chimera-drift's `LevelGeo.frond` and retooled. Flat-shaded 3D, real-world metres, vertex-COLOR albedo (per-instance tint + dry-tip gradient), sway weight baked into UV.y, `thickness` param → near (solid triangular-prism blade) / far (flat) LOD paired by `grass_lod()`. Stem-length-0 rule ⇒ grass. Renders with `vertex_color_use_as_albedo` | n/a | Higher-poly variants; wiggle shader animating the baked UV.y sway | Built (in-editor verified via renders) |
| FOLIAGE_GRASS_01 | 1–2 (phase 1) | Quick Fuel / ground foliage | `Frond.build(scale, seed, 0.0, thickness)` — grass clump: main tuft + 2–5 dispersed child tufts, dome splay (rim blades tip down & out), 4 species (fresh lawn / tall meadow / dry olive / broad lush), per-instance tint, random dry-ochre blade tips | n/a | Textured grass blades, animated wind sway | Built |
| FOLIAGE_CLOVER_01 | 1–2 (phase 1) | Quick Fuel / ground foliage | `Frond.build_clover(scale, seed, thickness)` — domed clump of petioles topped with rounded (obovate) trefoil leaflets; 3 species tints, rare 4-leaf, occasional white→faint-pink globular flower heads | n/a | Textured clover leaves w/ pale chevron, real flower detail | Built |
| FOLIAGE_DANDELION_01 | 1–2 (phase 1) | Quick Fuel / ground foliage | `Frond.build_dandelion(scale, seed, thickness, kind)` — basal leaf rosette + scape; three forms: wide/dense yellow→orange flower (short scape), white seed puff (tall scape), green unopened bud | n/a | Toothed dandelion leaves, real floret + pappus detail | Built |

Hazard/Dousing-Threat visuals are all placeholder "same ring/glow" telegraph treatment (see `DESIGN.md`'s Milestone 2 section) — per-type tells (falling shadow, aimed squirt, rotating sprinkler spray, aircraft flight path) are a later art/feel pass, not yet built. Bands 4-9's fuel/structure/hazard/threat content follows the same grey-box-primitive pattern as Bands 1-3 — colored `BoxMesh`/`CapsuleMesh`/`SphereMesh` shapes sized to real-world dimensions, no unique modeling per object.
