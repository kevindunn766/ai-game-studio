# PlantGen — Geometry Nodes Tree/Plant Generator: Build Request

**Requesting agent:** Claude (game-studio, Kindling project)
**Date:** 2026-07-23
**For:** whoever has The Grove and/or strong Geometry Nodes skill and can build me a node group.

---

## 0. TL;DR

I need an **original, self-contained Blender 4.5 Geometry Nodes node group** that grows a
**game-ready, low-poly, vertex-colored tree/plant** with real botanical structure (pipe-model
thickness, apical dominance, gravity bending, self-pruning). You may use **The Grove** (or your
own botany knowledge) as a **technique reference**, but the deliverable must be **your own node
group with no runtime dependency on any paid add-on** — I have to be able to evaluate and bake it
with a stock Blender 4.5 and no add-ons enabled. Do **not** send me The Grove's proprietary node
trees or the add-on itself.

The single most important thing my current build **cannot** do and I most need from you:
**tip→root thickness accumulation on a connected branch graph** (see §4.3).

---

## 1. Context (so the design fits my pipeline)

- **Engine target:** mobile game (endless isometric zoom-out), plus reuse across future projects.
- **Authoring:** I drive Blender **4.5 LTS headless** via `bpy`. I prefer node groups I can
  **rebuild from a Python script** and version-control.
- **Runtime path:** the tree is **baked to a 2-triangle impostor card** from a fixed isometric
  angle for the game — BUT the source mesh must also stand on its own as a **low-poly game asset**
  (other projects will use the mesh directly). So: heavy-ish is tolerable as bake source, but I
  want a real LOD path (see §3).
- **Coloring:** my entire pipeline is **vertex-color GLB → Godot**. No textures, no UV work.

---

## 2. Deliverable (what to hand back)

1. **A Blender 4.5 `.blend`** containing **one** Geometry Nodes node group named **`PlantGen`**,
   applied to a single mesh object, with **all controls exposed on the modifier interface** (§5).
2. **Strongly preferred, in addition:** a **headless `bpy` Python script** that builds that node
   group from scratch (so I can regenerate/modify and keep it in git). If you can only provide one
   artifact, provide the `.blend`.
3. A short **README**: parameter list + sensible ranges + 2–3 example presets (values).
4. *(Optional bonus)* 2–3 example **GLB exports** so I have reference targets.

---

## 3. Hard constraints (non-negotiable)

- **Blender 4.5**, Geometry Nodes. Must evaluate with **zero add-ons enabled**.
- **No external image textures. No alpha / transparency. No UV requirement.**
- Output is **ONE mesh, ONE material**. **All color comes from a single `POINT` domain
  `FLOAT_COLOR` vertex attribute named `Col`** (store **linear** color values). The material is
  literally `Attribute("Col") → Base Color` on a Principled BSDF. That's it.
- Must **export cleanly** via `bpy.ops.export_scene.gltf(..., export_format='GLB', ...)` with the
  `Col` colors intact (I read them in Godot with `vertex_color_use_as_albedo`).
- **Origin at the trunk base = world (0,0,0)**, tree grows **+Z** (Blender up). Roughly unit scale
  (a tree ≈ **1.5–3.0 Blender units** tall). I rescale downstream, so exact size isn't critical,
  but keep it consistent and centered on the base.
- **Self-contained**: no linked libraries, no add-on nodes, no drivers referencing external data.

### Known 4.5 gotcha to save you time
`Set Curve Radius` is **ignored by `Curve to Mesh` when a custom profile curve is supplied**
(Blender bug #149611). Use the **`Scale` input on `Curve to Mesh`** (per-control-point field) to
drive branch thickness instead.

---

## 4. Botanical realism I want (the important part)

Please build on a **connected branch graph (vertices welded at forks / shared at joints)** so that
thickness and bending are **gap-free** and can be traversed tip↔root. My current version fails
exactly because it's disjoint per-segment tubes.

1. **Apical dominance** — a continuing **leader** (long, thick, ~straight) plus a few **laterals**
   per node. Not symmetric dichotomous forking.
2. **Laterals distributed ALONG the boughs** (branches come off the sides of a bough, not only at
   tip-forks), with **phyllotactic azimuth** (~137.5° golden angle) around the parent axis.
3. **Pipe-model thickness (TOP PRIORITY)** — branches start **thin at the growing tips** and
   thickness **accumulates tip→root** so a branch is exactly as thick as the crown it actually
   supports; **smooth blend/gain at forks**. (This is *The Grove's* model, explicitly not da
   Vinci's rule. It is the #1 thing I can't do in a forward build.)
4. **Cantilever gravity bending, base→tip** (Euler-Bernoulli style): side-spreading branches sag
   most, **thickness resists bending**, cumulative down the branch, **gap-free** (must not tear
   joints — this is why it needs the connected graph).
5. **Self-pruning by shade/weakness**, not pure randomness — keep the crown "airy." A few dead
   stubs / broken tips for character are welcome.
6. **Gnarl** — organic bends along branches, pinned at joints so nothing opens up.
7. **Root flare** at the trunk base (buttressing swell).
8. **Bark color via `Col`** — dark→light gradient with a fine **noise "crevice" darkening**
   (fake AO baked into vertex color).
9. **Canopy** — instanced **low-poly leaf clusters** massed on the **outer branch shell** forming
   a **cohesive irregular crown** (NOT a smooth ball, NOT isolated tip-blobs, NOT high-subdiv
   spheres). Per-cluster **color variation** (value + a warm sun-touched highlight), slight
   **downward droop**, green **ombre by height**. Must read cleanly at a distance (it bakes to a
   card). Leaf clusters can be tiny instanced meshes or cards — your call, keep them cheap.

---

## 5. Parameters to expose on the modifier interface

- **Seed** (int)
- **Height / overall scale**
- **Age / iterations** (number of growth cycles)
- **Trunk base thickness** + **taper / pipe gain**
- **Laterals per node**, **branch angle**, **internode length**, **length decay**
- **Phyllotaxis angle**
- **Gravity / droop strength**
- **Shed amount** (how aggressively it self-prunes)
- **Canopy** on/off, **fullness/density**, **cluster size**, **leaf color A/B**, **bark color A/B**
- **Stylization / "cuteness" dial 0→1** — 0 = realistic proportions; 1 = chunky (shorter fatter
  trunk, bigger rounder canopy) for less-realistic projects. One dial that remaps several params.
- **LOD / quality level** — drives adaptive ring resolution + canopy density (see §3).

---

## 6. Tri budget / LOD (game-ready)

- **LOD0 hero tree ≤ ~8,000 tris.** Provide a quality input that scales down to **~1–2k**.
- **Adaptive meshing**: branch **ring resolution drops as the branch thins** (Grove-style), and the
  canopy is instanced low-poly clusters, not subdivided spheres.
- For reference, my current tree is ~13k tris and reads fine as a bake source; I want the LOD knob
  for direct in-engine use.

---

## 7. Nice-to-have

- Same node group should also make **shrubs/bushes** (short, no dominant leader) via the params.
- Preset configs: **oak-like**, **young sapling**, **bush**.

---

## 8. Reference: my current attempt (in this repo)

`tools/blender/plant_gn.py` builds my current **forward L-system** version headlessly. It already
does: apical dominance (leader + laterals), phyllotaxis, gravity droop, continuous taper (via the
`Curve to Mesh` **Scale** field), gnarl, root flare, bark crevice shading, and a branch-distributed
canopy — all **vertex-color `Col`, single material, GLB export**, ~13k tris.

**Its architectural limitation:** it accumulates the tree as **disjoint per-segment tubes**, so it
**cannot** do true pipe-model thickness or cumulative cantilever bending (per-point sag would tear
the joints). Please use it to match my **conventions** (the `Col` attribute, single material, +Z /
origin-at-base, GLB-clean output) — but feel free to **architect the growth differently** (a
connected, weldable graph is what I want).

Thanks — this becomes a core, reusable tool, so correctness and clean parameters matter more than
speed of delivery.
