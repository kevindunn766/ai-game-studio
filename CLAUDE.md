# CLAUDE.md — Arcanum Clash Studio Rules

This workspace is governed by `DESIGN_BRIEF.md`. All work must follow its Governing Rules.

## Mandatory Rules
1. Always read and follow `DESIGN_BRIEF.md` before any asset or code work.
2. Final pixel art assets must be generated deterministically with `tools/pixel_art_engine.py`.
3. Transparency is `#FF00FF` only. No alpha channels. No white backgrounds for transparency.
4. Generate graphical elements one at a time; never batch image generation.
5. AI-generated images are allowed only as style drafts. Final shipped assets must come from `tools/pixel_art_engine.py`.
6. Every generated asset prompt must include exact pixel size, resolution, viewpoint, and a prohibition on text/grid.
7. Do not use trademarked/branded names in game concepts. Use fully original names only.

## Workflow
- Read `DESIGN_BRIEF.md` fully before starting.
- Use `python tools/pixel_art_engine.py tile|rect|pixel ...` for procedural output.
- Describe each asset fully before generation. Wait for user approval when required.

## Engineering Conventions (Godot 3D projects)
- Read `docs/godot-3d-best-practices.md` before engine work on any Godot 3D project — verified,
  cross-project patterns (cameras, CSG collision, moving hazards, streaming, typed GDScript,
  numeric verification), with `docs/godot-procedural-meshes.md` for mesh/normal detail.
- Before modeling ANY creature/prop, read `docs/godot-3d-modeling-process.md` and follow it:
  trace top/side/front reference views → even-vertex outlines per piece → solidify → skeleton +
  link to bones. Do not hand-guess profiles and tweak-and-hope.
- Only add to those docs what you have **proven in-engine** — a faulty "best practice" propagates
  to every project.
- **Promote findings:** any reusable engine finding proven in one project (a gotcha, a corrected
  helper, a verified pattern) must be moved up into the studio-wide docs (`docs/…`) so future
  sessions on any project inherit it — never left buried in a single project's notes. Verify
  numerically before writing it down (see the mesh non-negotiable below).
- Non-negotiable mesh summary: triangle **winding must match Godot's convention** (verify a
  generated mesh against `BoxMesh`/`SphereMesh`: every face `cross(v1-v0,v2-v0) · normal < 0`).
  Outward normal *vectors* alone are NOT enough — reversed winding renders objects inside-out.
  Set flat per-face normals explicitly (not `generate_normals()`, which smooths); interior
  surfaces (tunnels) face inward; never hide it with double-sided materials or `regen_normal_maps()`.
