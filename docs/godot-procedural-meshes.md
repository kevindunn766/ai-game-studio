# Studio Engineering Note — Procedural Meshes in Godot 4 (3D)

Applies to every Godot 3D project in this studio (chimera-drift, cragling-3d, kindling-3d,
snake-3d, procedural-3d-godot, …). When you build meshes from scratch with `SurfaceTool` /
`ArrayMesh`, follow this or objects render **inside-out / flipped**. This cost a full session
to diagnose once — do it right up front.

---

## The one rule that matters: match Godot's winding convention

A correct normal has **two** requirements, and it is easy to get the first while silently
failing the second:

1. **The normal vector points outward** (away from the surface interior).
2. **The triangle winding matches Godot's culling convention.** With single-sided material
   (`cull_mode = CULL_BACK`, the default), Godot decides which side is the *front* (visible)
   face from the winding order, **not** from the stored normal. If the winding is reversed,
   the outer faces get culled and you see the lit **inner** surface → inside-out — even though
   the normal vectors are perfectly outward.

Godot's convention (verified from `BoxMesh`, `SphereMesh`): for every triangle,

```
cross(v1 - v0, v2 - v0) · stored_normal  <  0
```

i.e. the stored normal is the **negative** of the winding's cross product. If your generated
mesh has `> 0`, your winding is reversed — swap two vertices of every triangle (keep the same
normal).

### The diagnostic that actually finds this (do this, don't eyeball screenshots)

Build a Godot primitive and one of your meshes, and compare the sign per face:

```gdscript
func _sign_report(label: String, arrays: Array) -> void:
    var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
    var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
    var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
    var tris: int = (idx.size() / 3) if idx.size() > 0 else (v.size() / 3)
    var pos := 0; var neg := 0
    for t in range(tris):
        var a := idx[t*3] if idx.size() > 0 else t*3
        var b := idx[t*3+1] if idx.size() > 0 else t*3+1
        var c := idx[t*3+2] if idx.size() > 0 else t*3+2
        var d := (v[b]-v[a]).cross(v[c]-v[a]).dot(n[a]+n[b]+n[c])
        if d > 0.0: pos += 1
        elif d < 0.0: neg += 1
    print("%s  cross·normal>0:%d  <0:%d" % [label, pos, neg])

# _sign_report("BoxMesh", BoxMesh.new().get_mesh_arrays())
# _sign_report("mine",    my_mesh.surface_get_arrays(0))
```

A Godot primitive shows all `<0`. Yours must too. Numeric normal-direction checks (`normal ·
(face_center − centroid) > 0`) will happily pass while the winding is still backwards, so they
are **not** sufficient on their own — always compare winding against a primitive.

---

## Flat shading: set per-face normals yourself

`SurfaceTool.generate_normals()` **smooths** — it averages normals across vertices that share a
position. Flat/hard-surface shapes (boxes, crystals, faceted low-poly) come out with
non-perpendicular, "melted" normals. For grey-box / hard-surface, compute the true perpendicular
per face and set it on all three of that face's vertices:

```gdscript
static func _flat_face(st: SurfaceTool, v0: Vector3, v1: Vector3, v2: Vector3, ref_point: Vector3) -> void:
    var raw := (v1 - v0).cross(v2 - v0)
    if raw.length() < 1e-6:
        return                                   # skip degenerate (cone/tip) tris
    var n := raw.normalized()
    if n.dot((v0 + v1 + v2) / 3.0 - ref_point) < 0.0:
        n = -n                                   # orient outward from a LOCAL ref
    # Choose the emitted WINDING to match the outward normal (Godot wants
    # cross(emitted)·normal < 0), independent of the caller's input vertex order:
    if raw.dot(n) > 0.0:
        st.set_normal(n); st.add_vertex(v0)      # raw ∥ n  -> reverse winding
        st.set_normal(n); st.add_vertex(v2)
        st.set_normal(n); st.add_vertex(v1)
    else:
        st.set_normal(n); st.add_vertex(v0)      # raw ∦ n  -> keep winding
        st.set_normal(n); st.add_vertex(v1)
        st.set_normal(n); st.add_vertex(v2)
```

> **Trap this replaced (INSTAR, 2026-07-18, verified numerically).** The earlier version of
> this helper *always* emitted reversed winding (`v0, v2, v1`) and silently assumed the caller
> had already wound each triangle so `raw = cross(v1-v0, v2-v0)` points outward. It flips the
> **normal vector** against the ref point but not the **winding**, so when the ref-flip triggers
> (e.g. a `round_z = -1` quarter-sphere whose parametrization flips handedness, or any
> mirror-modifier half) the stored normal is corrected while the winding stays reversed →
> `cross·normal > 0` → inside-out, *and it still looks plausible on screen*. The version above
> is **order-independent**: it picks the winding to agree with the chosen outward normal, so it
> is correct no matter how the caller feeds vertices (and makes mirroring across an axis safe —
> the reflected half auto-winds correctly). Always confirm with the numeric check below.

- **Orient against a LOCAL reference, not the global centroid.** For a loft/revolve use the ring
  center (radial); for caps the axis direction; for a torus the nearest point on the major
  circle. A single global centroid guesses wrong on thin/elongated/non-convex shapes (a tall
  column, a wing).
- **Skip degenerate zero-area triangles** (cone/dome tip fans) or their normals are garbage.

Verify numerically: `abs(normal · edge) ≈ 0` (perpendicular), all three vertex normals of a face
identical (flat), and outward.

---

## Interior surfaces face INWARD

A tunnel / cave / pipe is viewed from the **inside**, so its wall/floor/ceiling normals must
point **toward the player** (toward the tube center), not outward toward the rock. Outward
normals on an interior surface light the whole space inside-out. Orient those faces toward the
interior center.

---

## Don't paper over normal bugs

- **`cull_mode = CULL_DISABLED` (double-sided)** hides culling but renders the inner shell too,
  so it looks flipped again. Fix the winding/normals; keep meshes single-sided.
- **`ArrayMesh.regen_normal_maps()`** does **not** regenerate normals — it regenerates *tangents*
  for normal-mapping and requires UVs (errors "UVs are required to generate tangents"). Not a fix.
- **Fake analytical/radial normals** (`Vector3(nr*cos a, ny, nr*sin a)`) only work for round
  cross-sections; they're wrong for polygonal ones (a hex crystal).

---

## Instance transforms must be right-handed

When you place a generated mesh with a hand-built `Basis`, make it a proper rotation
(determinant +1). Building `Basis(x, up, z)` with `z = up.cross(x)` is **left-handed** (a
reflection) and flips every instance's winding → inside-out at render time. Use
`z = x.cross(up)`. Non-uniform scale is fine as long as all components are positive.
```
