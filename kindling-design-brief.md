# KINDLING — Design Brief v0.1
*(working title — easy to rename later, see BATTLE BOA precedent in snake-3d)*

**Genre:** Isometric 3D mobile action, single continuous escalating run
**Platform:** Mobile (Android first, matching snake-3d's pipeline), Godot 4.7
**Perspective:** Fixed isometric diorama camera, tilt-shift depth-of-field ("cute realistic miniature" look)
**Fantasy:** You ARE a fire. You start as a match-sized flame and grow, by burning fuel, all the way up to a city-consuming inferno — while the things trying to put you out escalate right alongside you.

---

## Core Loop

1. Free-roam via floating/adaptive touch joystick (same input pattern as snake-3d) — the flame moves freely across one continuous, seamless procedurally-generated world the whole run. There is no separate map per tier and no loading transition; see Continuous Growth & Camera below.
2. Touching eligible fuel burns it — see **Fuel Types** below for the two different ways this plays out. Each object type only becomes eligible once the player is big enough for it (a cardboard box needs more size than a blade of grass; a house needs far more than a fence).
3. Each tier/band has a two-part **Charge → Grow** cycle, shown as a bar in the HUD:
   - **Charge sub-phase:** burning eligible fuel makes the flame brighter and fills the current bar. No size change yet.
   - **Grow sub-phase:** once the bar is full, every further burn actually grows the flame, and the camera zooms out to keep it framed (this is what makes fixed-size world objects look smaller — see below). This continues until the player crosses into the next band's fuel-eligibility range.
   - On crossing into a new band, the bar **collapses into one larger bar** for the next band, and the Charge sub-phase begins again.
4. Hazards attack you continuously, in both sub-phases. Most hazards knock back **partial Growth Points** (shrink some, camera creeps back in a bit — never below match-flame size). Each band has exactly one **Dousing Threat** — a water-based hazard that is an **instant kill** (run over, back to menu/leaderboard) if it lands a hit. The player must learn to visually recognize the Dousing Threat for the current band and avoid/outrun it; it's the one thing size doesn't protect you from.
5. Run ends either by death (Dousing Threat hit) or, at the top, a final scripted confrontation at Massive scale.

This mirrors snake-3d's proven shape (single continuous run, escalating scale, leaderboard) rather than inventing a new loop — but unlike snake-3d's discrete biomes, there is only ever one world here; scale is what changes, not the map underneath it.

---

## Fuel Types: Quick Fuel vs. Structure Fuel

Two different burn behaviors, not one, decided per fuel object:

- **Quick Fuel** (grass, twigs, small plants, a bush): touch it, it catches, it burns down on its own and disappears, points are awarded on catching — no need to linger, nothing to defend against mid-burn. This is the original "touch and burn" feel.
- **Structure Fuel** (a shed, and by extension bigger set-pieces like trees/houses/buildings at later bands): has its **own health bar**. Touching it ignites it, but the health bar only drains while the player stays in contact — meaning the player is exposed to hazards for the whole burn-down, a real risk/reward call for stopping to conquer something big. Full points are only awarded once its health bar reaches zero.
- **Burn-down visual (shared technique, both types):** a particle system (fire, embers, light smoke) plus a shared noise-driven dissolve shader — one `burn_progress` uniform (0→1) per burning object, sampled against a procedural noise texture so the char/transparency edge advances as an organic front rather than a uniform wipe, rather than anything hand-authored per object.
- **Structure Fuel gets one extra step Quick Fuel doesn't:** a distinct, separately-modeled **burnt-down replacement mesh** spawns in as soon as the dissolve starts, so what's being revealed underneath the disappearing pristine mesh is an actual charred model, not just a blackened version of the same geometry. This burnt husk is what remains standing after the object is fully conquered — visible evidence of what's already been consumed. Quick Fuel has no separate burnt model — it just fully disappears once its (much shorter) burn finishes.
- Every Structure Fuel type therefore needs **two** grey-box stand-ins (pristine + burnt-down) logged in the Asset Registry, not one.

---

## Scale Tier System

Nine bands along one continuous Growth Points curve — **not nine separate maps**. Each band is just the range of scale where a given set of fuel becomes eligible to burn, a given set of non-lethal hazards is active, and one lethal Dousing Threat appears. The world itself doesn't change; what's reachable and relevant does. The Dousing Threat escalates in lockstep with your own scale — always roughly "the appropriately-sized thing a human would use to put this size of fire out."

| Tier | Fuel examples | Non-lethal hazards (shrink) | Dousing Threat (instant death) |
|---|---|---|---|
| 1. Match | twigs, gum wrappers, leaf litter, dry grass blades | ants (stomp/bite), flies (wing-gust blow-out) | dew drop / spittlebug spit — a single falling droplet with a brief shadow/glint tell |
| 2. Small Fire | small plants, pine needles, a nest of twigs | beetles, earthworm (smother by crawling over), moths (wing-gust) | garden snail's wet slime trail, or a kid's squirt-bottle |
| 3. Small-Medium | brush piles, dry shrubs, a cardboard box | birds (peck/stomp), a curious cat (paw swat) | sprinkler head switching on |
| 4. Medium | campfire-scale logs, a wooden fence, a shed's kindling pile | a dog (stomp/dig), a person with a blanket (smother swat) | person with a garden hose |
| 5. Medium-Large | a shed, a car, a small grove of trees | homeowner with a rake/shovel (swat) | residential fire extinguisher / bucket brigade |
| 6. Large | a house, a stand of trees | local residents, a security guard | single firefighter with hose reel (first "heavy equipment" tease) |
| 7. Extra-Large | multiple houses, a city block | first responders on foot | fire truck with pumper hose |
| 8. Extra-Extra-Large | a neighborhood, a forest section | fire crews with heavy gear | multiple trucks / ladder companies working together |
| 9. Massive | a district, a city, a forest | evacuation chaos (non-lethal set dressing, low threat) | aerial water bomber / helicopter with Bambi bucket — final confrontation |

Open for iteration: exact fuel/hazard names above are a first pass, not locked. Real-world escalation logic (bugs → household objects → firefighting equipment) is the locked design intent.

---

## Fail State

- **Shrink, don't always kill:** most hazard hits knock down partial Growth Points — the bar drains a bit and the camera creeps back in — potentially dropping back into the previous band's fuel-eligibility range if severe. This is forgiving and matches the "learn the pattern" mobile-casual feel.
- **Dousing Threat = hard death:** exactly one recognizable enemy/attack per tier is an instant-kill water hit. No partial damage, no recovery. This is the "boss pattern" the player must learn per tier, and it's the main skill expression in an otherwise fairly forgiving game.
- Death returns to menu/leaderboard (score = highest tier reached + total Growth Points), same shape as snake-3d's current run-end flow.

---

## Power-Ups

- Certain objects, when burned, grant a temporary special fire effect instead of just Growth Points — e.g., a **gas can**: burning it triggers an instant burst that ignites everything within a radius at once, rather than one object at a time.
- Following snake-3d's precedent (rainbow diamond, yellow sphere, etc. — see that project's history): once an initial roster is defined and built, treat it as **locked**. Expanding it later is a fresh approval pass, not organic growth mid-implementation.
- Exact initial roster beyond the gas-can example is an open design pass, not yet locked.
- Out of scope for the first prototype and the Bands 1–3 vertical slice — layered on once the core Charge→Grow / Quick-vs-Structure-Fuel loop is proven, same "prototype first, features after" sequencing as everything else non-essential to the core loop.

---

## Dynamic Events & Push Hazards

A category distinct from the fixed per-band hazard table (Scale Tier System above): scripted/random NPC encounters that disrupt the player without following either of the two existing hazard rules (partial-shrink, instant-kill).

- **Example: leaf-blower NPC** — a house's occupant comes out and blasts the player with a leaf blower, pushing/displacing them. Confirmed **purely positional** — no direct Growth Point loss from the push itself. Danger is entirely indirect: getting shoved into an actual hazard, into a Dousing Threat, or (once climbing exists) off a structure.
- This is a third, distinct hazard *flavor* (displacement) alongside the two already established (partial-shrink, instant-kill) — keep it distinct in implementation rather than folding it into the existing per-band hazard table, since its consequences work differently.
- "Plus other events like that" (Kevin's phrasing) — intentionally open-ended for now, but per this studio's anti-creep rule needs a first concrete locked list before wide implementation, same as Power-Ups above.
- Out of scope for the first prototype; layered on after the core loop and Power-Ups are proven.

---

## Camera, Art Direction & Continuous Growth

**Look:** isometric diorama camera, tilt-shift shader for shallow-focus "miniature" effect. Snake-3d already has a working tilt-shift shader — port and adapt rather than rebuild.

**The system is simpler than v0.1's first draft, and that's deliberate.** The original idea (two coexisting world-layers cross-fading scale during a transition state) is scrapped in favor of something that falls naturally out of Kevin's own walkthrough of the game:

- **World geometry is fixed, real-world-consistent absolute scale, always.** A blade of grass is grass-sized in world units forever. A tree trunk is tree-sized forever. Nothing about any prop's own scale ever changes.
- **Only the player's flame scales up**, continuously, as Growth Points increase within a band's Grow sub-phase. One node, one animated property. No swap, no second world, no cross-fade.
- **The camera zooms out to keep the growing flame framed.** Pulling the camera back is what makes fixed-size grass/trees/houses look smaller on screen — it's the same object at the same size, just farther from a camera that has to be farther away to fit a bigger flame in frame. This is the entire trick behind "the world shrinks as you grow" — no object ever actually shrinks.
- **It's one continuous procedurally-generated world, not per-tier maps — generated by zone, not by uniform random scatter.** Per Kevin: the shipped game has many more objects than a single tree and a single house per yard, and placement is contextual — some objects are only valid in a house's front/back yard, others only in a driveway, others only along a road edge. So generation works off real-world-like parcels (yard, driveway, street edge, etc.), each with its own spawn table and density, rather than one flat noise field. The v0.1 "one tree, one house" description was an oversimplification for illustration, not the actual spawn model — the zone/parcel spawn tables themselves are a later design pass, not needed for the first prototype (a single yard parcel is enough to prove the growth+zoom system).
- **Scale-gated spawn LOD:** once a fuel type is far below the player's current scale (no longer worth burning, and too small to read at the current camera distance), the generator stops placing new instances of it. Existing tiny objects don't need to be tracked or rendered at giant scale — confirmed simplification, avoids simulating irrelevant detail.
- Camera rig still follows the studio's standing anti-pattern rule: never scale/reposition the node the camera rig is parented under directly — animate the camera's own zoom/distance property, not a parent transform.

**This is still the highest-risk system in the brief**, even though it's simpler than v0.1 — continuous procedural generation that must seamlessly cover many orders of magnitude of scale (grass blade to skyscraper) in one world is a real technical challenge, particularly for noise-seeded placement and streaming radius (which now must key off camera zoom level, not just player XZ position like snake-3d's fixed-scale streaming does). Still the first thing to prototype, standalone, before tier content — see Build Milestones.

---

## Locomotion & Fire Physics by Scale

Movement input is the **same free-roam joystick for the entire game**, plus one more input present from the very start: **double-tap to jump**, same thumb as the joystick (one-thumb control scheme throughout — no second control ever introduced). What changes with scale is what that jump actually *does*:

- **Jump is automatic, not aimed.** A double-tap launches the flame along an arc toward the nearest eligible object ahead of it, using the player's current trajectory/heading to pick direction — no manual targeting. It only reaches within a limited radius.
- **Jump radius scales with the player's own size**, consistent with the "only the player scales, world stays fixed" model above — so the same double-tap input naturally goes from a "cute little hop that doesn't do much" at match/lawn scale (working assumption, not yet confirmed: e.g. hopping over a pebble) to actually reaching the next tree, or leaping tree-to-house, house-to-house, once the flame is big enough for the radius to matter. No separate jump mechanic needs to be introduced later — it's the same button the whole game, just increasingly consequential.

**Movement trail — present at every scale, including the first prototype (not gated behind reaching trees/buildings):**

- Wherever the flame moves, it leaves behind (a) a **darkened/scorched mark** on the ground or surface it crossed, and (b) a **small diminishing trail of fire particles** (embers) along that same path that fade out over a short time. Two layers: a lasting scorch decal, and a short-lived particle flourish riding on top of it.

**Large-scale-only systems — out of scope for the early lawn-scale vertical slice, belong in their own later build milestone:**

- **Climb & leap:** at large scale, this is how the flame crawls up vertical surfaces (a tree trunk, a building wall) and leaps across gaps to the next structure (tree to tree, tree to house, building to building), rather than only moving across flat ground.
- **Delayed mass-follow:** the bulk of the fire doesn't snap instantly onto a new surface/structure — it lags behind the leading edge and catches up over a short delay, giving the fire body weight and stretch during climbs/leaps. (Same underlying idea as snake-3d's segment-follows-head pattern — worth reusing that technique rather than inventing a new one.)
- **Burn-down destruction:** see the **Fuel Types: Quick Fuel vs. Structure Fuel** section above for the full mechanic (shared dissolve shader + particles, Structure Fuel's burnt-down replacement mesh).

**Asset pipeline (revised — no external packs):** No usable free asset pack was found that matches the target "museum diorama" look (everything free skews cartoony/toy-store); paid/scanned realistic assets are a possible future option but Kevin has decided against building on other people's assets at all. Locked approach:
- **Procedural grey-box stand-ins for everything** — fire, critters, fuel, and all diorama props/terrain/vehicles — built from Godot primitives, same technique snake-3d already uses successfully. Nothing waits on art.
- Every stand-in is logged in the **Asset Registry** (see below) as it's created, so the eventual real-art pass is a wholesale swap against a known list, not a rediscovery/rebuild effort.
- Final art direction (hand-modeled, paid packs, or something else) is an explicit later decision, made once gameplay is polished — not blocking now.

---

## Naming

**KINDLING** — confirmed. Original, no trademark conflicts, doubles as both "the act of starting a fire" and "kindling = fire-starting material," which fits the fuel-eating mechanic. Project folder: `kindling-3d/`, matching the `snake-3d/` convention.

---

## Asset Registry (living document)

Every stand-in asset gets an entry the moment it's created, so the eventual real-art pass is a lookup-and-swap, not a rediscovery effort. Move this into `kindling-3d/ASSET_REGISTRY.md` once the project folder exists; tracked here until then.

| ID | Tier | Role (Quick Fuel / Structure Fuel / non-lethal hazard / Dousing Threat / Power-up / Dynamic Event / prop) | Stand-in (pristine) | Stand-in (burnt-down, Structure Fuel only) | Intended final look (notes for future art pass) | Status |
|---|---|---|---|---|---|---|
| _(populated as each grey-box asset is built)_ | | | | | | Placeholder |

Columns are locked; rows get added during implementation, one per asset, no batching multiple assets into one row.

---

## Explicitly Out of Scope for v0.1 (avoid creep)

- Exact enemy roster/behaviors beyond the tier table above — first pass only, to be refined per tier once we're building.
- Multiplayer/PvP.
- Any non-Android export target (iOS, desktop) until Android build is solid.
- Story/dialogue beyond the implicit escalation arc.
- Any AI-generated 3D model pipeline, and any external asset packs (free or paid) — decided against; procedural stand-ins + Asset Registry instead.
- Final art pass of any kind — deferred until gameplay is polished.

---

## Build Milestones

1. **Continuous growth + camera zoom prototype** — grey-box only, lawn scale (Bands 1–2) only. Prove that flame-scales-up + camera-zooms-out actually reads as "the world getting smaller," that the Charge→Grow bar cycle feels right, and that scale-gated procedural spawn density (many grass blades, one tree trunk, one house foundation) holds together. Includes the base movement trail (scorch decal + diminishing ember particles) and the double-tap jump, both present from the start even though jump barely matters yet. This is the riskiest system in the brief; nothing else is worth building until this holds up.
2. **Vertical slice** — Bands 1–3 fully playable end to end (fuel eligibility, Quick Fuel vs. Structure Fuel, non-lethal hazards, Dousing Threat, Charge→Grow cycle) once the above is proven.
3. **Power-ups & Dynamic Events** — first concrete locked roster (gas can, leaf-blower, etc.), layered onto the vertical slice once it's proven.
4. **Climb/leap/delayed-mass-follow locomotion system** — once tree- and building-scale bands are reachable; not needed before then.
5. Remaining bands, one at a time, each logged into the Asset Registry as built.

---

## Open Questions for Kevin

- HUD bar visual treatment (segmented pips vs. continuous fill, color/brightness tie-in) — cosmetic, can default and iterate.
- Do Structure Fuel burnt-down husks (shed, house, etc.) persist in the world forever, or get cleaned up/pooled after some time for performance once a run has conquered a lot of them?
- Does jump radius scale linearly with player size, or some other curve (e.g. capped, or stepped per band)?
- Zone/parcel spawn tables (what's allowed in a front yard vs. backyard vs. driveway vs. road edge) — a real design pass needed before wide content, not before the single-parcel first prototype.
- Does the movement trail's scorch decal fade/decay over time, or persist for the whole run?
