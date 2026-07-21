# Studio 3D Modeling Process — Reference-Traced, Solidified, Rigged

**Mandatory before any procedural creature/prop modeling.** This is Kevin's directed workflow.
Follow it in order; do NOT hand-guess profile numbers and tweak-and-hope (that path produced
repeatedly bad results). The point is to get amateur-3D-artist-quality shapes by **tracing real
orthographic references**, not by inventing silhouettes.

Applies to every Godot 3D project in this studio. Promote refinements here (see best-practices §0).

---

## The technique — verbatim (Kevin, 2026-07-18)

> First step, use the top view then the side view then the front view to create an outline with
> the correct number of vertices needed to get an even mesh. Literally trace the photos, I've
> included an image of an isopod from the front. Do this for all of the pieces. Some best guess or
> interpolation can be used for the parts that aren't visible in the front view. But you can see
> how round it is. Add solidify modifier. Make a skeleton then link to bones appropriately. You
> can do this with nearly any simple form.

> Then for things like legs you can trace one side and rotate. I forgot to mention always use
> mirroring to get perfect symmetry.

> Okay, but trace each segment of the leg and rotate each segment separately, then rig together on
> an IK.

> Last sample the image for the object's color. Then color the object or UV maps depending on how
> detailed it should be.

**Pipeline at a glance (complete):** three-view trace (top/side/front, even vertices, per piece)
→ interpolate hidden parts → mirror for symmetry → solidify → per-segment legs (trace each segment,
rotate, IK) traced once then rotated/arrayed/mirrored into every socket → skeleton + link to bones
→ sample reference for color → flat color or UV+texture by detail level.

---

## The steps

1. **Get three orthographic reference views** of the subject: **top**, **side**, and **front**.
   (For the isopod: top = dorsal plan, side = lateral profile, front = head-on cross-section —
   the front view is what shows *how round it is*.)
2. **Trace each view to an outline**, choosing the **correct number of vertices for an even mesh**
   — enough to capture the curve, evenly spaced so the resulting quads are roughly uniform (no
   long thin slivers, no dense clusters). Trace the *actual* photo silhouette; don't invent it.
3. **Do this for every piece separately** (each carapace plate, the head, the tail, …), not one
   blob for the whole body.
4. **Interpolate the hidden parts.** Where a surface isn't visible in a given view, best-guess it
   from how round the visible views show it to be.
5. **Add a solidify modifier** — give the traced shell real thickness (armor plates are not
   zero-thickness; the edge thickness reads when plates overlap).
6. **Make a skeleton (armature) and link the pieces to bones** appropriately — one bone per piece,
   chained, so the assembled form can pose/flex/curl.

7. **Repeated/appendage parts (legs, antennae): trace ONE, then rotate/array to place the rest.**
   Model a single leg once, then duplicate-and-rotate it into each socket around the body rather
   than modeling every leg from scratch.
8. **Legs are per-segment: trace each leg SEGMENT separately** (coxa, femur, tibia, tarsus…),
   **rotate each segment into place** to form the leg pose, **then rig the segments together on an
   IK chain.** Do not model a leg as one fused piece — each segment is its own traced, solidified
   part, jointed to the next, and the whole chain is driven by IK (foot target → solved joints).
   The traced-one-then-rotate/mirror rule (step 7 + the mirror rule) still applies: build one leg's
   segment set, mirror/rotate it into all sockets.
9. **Color last: sample the reference image for the object's color, then color to the needed level
   of detail.** Pick the actual color(s) out of the reference photo (don't invent them). Then EITHER
   apply flat/solid color (simple objects) OR build UV maps + a texture (when it needs more detail).
   Detail level decides which — most grey-box/simple forms just take the sampled solid color.

> "You can do this with nearly any simple form." — the same trace→solidify→rig pipeline is the
> default for props and creatures alike.

**Rigid bones — never resize a segment after attaching it (INSTAR, 2026-07-18).** Build each bone
mesh at its TRUE length once; then only **rotate/position** it to its joints. Do NOT non-uniformly
scale the mesh each frame to stretch it between IK joints — that stretches/squashes the segment as
the target moves and reads clearly wrong. Keep bone lengths fixed; the IK moves joints, the meshes
only rotate. If an IK target is out of reach, clamp the drawn segment to its length (leg extends,
never stretches). In code: aim = `Transform3D(Basis(x, y_dir, z), joint_pos)` with **no scale**.

## Governing rule — ALWAYS mirror for perfect symmetry

Every symmetric form is built as **one half, then mirrored** across the symmetry plane (never two
independently-modeled halves). This guarantees perfect left/right symmetry. In procedural Godot:
generate the `+X` half and emit each triangle's `X`-negated twin (the order-independent `_flat_face`
in `godot-procedural-meshes.md` auto-winds the reflected half correctly). Combine with step 7 for
appendages: mirror a leg to the opposite side, and rotate/array along the body.

---

## How we execute this in procedural Godot (no Blender at runtime)

We generate meshes in code (`SurfaceTool`/`ArrayMesh`), so the Blender steps map like this:

- **Three-view trace → three profile arrays.** For each piece, define three traced polylines as
  `PackedVector2Array` constants, read straight off the reference:
  - `TOP(z)  → half_width(z)`  — the plan outline (how wide at each point along the body length Z).
  - `SIDE(z) → dorsal_y(z)` and `belly_y(z)` — the lateral profile (top curve and underside along Z).
  - `FRONT  → cross_section outline` in local X-Y (the rounded dome + hanging epimera + belly);
    trace it once, with an **even, deliberate vertex count**.
- **Loft = combine the three.** Sweep the FRONT cross-section along Z; at each Z scale its width by
  `TOP(z)` and its height by `SIDE(z)`, and offset it to sit on the `SIDE` dorsal/belly curve. This
  is the code equivalent of box-modeling to three reference planes — the shape is *traced*, not guessed.
- **Even mesh:** use one consistent ring vertex count (= the FRONT outline vertex count) and a Z-step
  count chosen so quads are ~square. Verify winding numerically (see `godot-procedural-meshes.md`).
- **Solidify:** give the shell thickness — offset a duplicate of the surface inward by a small
  `thickness` and bridge the rims, OR build the cross-section as a **closed loop with real wall
  thickness** (an outer outline + an inner outline). A single-wall zero-thickness plate is wrong.
- **Skeleton + link to bones:** build the spine as a chain of joint `Node3D`s (or a `Skeleton3D`),
  one per piece, and parent/skin each piece to its bone so joints can pose/curl the assembly.

## Why (what this fixes)

Guessing a lone side-ish profile and nudging constants can't converge — you have no ground truth
for width or roundness, so every fix trades one artifact for another. Tracing **top + side + front**
gives all three dimensions from real references, so the first build is already the right shape.
