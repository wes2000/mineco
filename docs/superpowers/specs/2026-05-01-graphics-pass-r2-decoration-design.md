# Mine Co. — Graphics Pass Round 2: Decoration

**Date:** 2026-05-01
**Project:** Mine Co. (Godot 4.6 module build with Voxel Tools 1.6, Forward+, D3D12)
**Status:** Approved by user, ready for implementation plan
**Reference:** Death Stranding screenshot — vibrant grass, scattered rocks of varied sizes, occasional iconic trees on hilltops

## Goal

Populate the v1+R1 island with grass, rocks, and trees so it reads as a living place rather than a bare-terrain test. The atmosphere from R1 (hazy / muted / Death-Stranding-y) is in place; this round adds the "stuff on the ground" without disturbing it. Trees specifically appear as solo / small-cluster placements on hilltops — not a forest.

## Non-goals (this round)

- Wind animation on grass or trees
- Bushes / flowers / mushrooms / debris (the pack has them; we're choosing only grass + rocks + trees)
- Per-instance color variation
- Foliage destruction tied to mining
- Footstep sounds matching biome
- Ambient creature movement / wildlife

All explicitly parked. R2 is a static-decoration pass.

## Architecture overview

Three coupled pieces, all leveraging Voxel Tools' built-in scatter system:

1. **Asset source.** Kenney Nature Kit (CC0). User downloads the pack; we extract a small subset of `.glb` files into `res://assets/nature/`. We pick one grass mesh, two rock variants (small/medium), two tree types (pine + oak/deciduous).
2. **`VoxelInstancer` + `VoxelInstanceLibrary`.** A single `VoxelInstancer` node is added under the existing `/Main/VoxelTerrain`. It references a `VoxelInstanceLibrary` resource (`scenes/nature_library.tres`) listing one entry per asset variant. The library entries declare density, slope tolerance, world-Y range, and the mesh. The instancer evaluates these rules per voxel chunk as chunks stream in via the existing `VoxelViewer` on the player.
3. **Tint shader.** A small spatial shader (`shaders/nature_tint.gdshader`) overrides the imported material on each library item, desaturating Kenney's saturated palette and mixing slightly toward `Atmosphere.HAZE_COLOR` so the foliage doesn't clash with the hazy R1 atmosphere.

Each piece has a clear responsibility: the asset folder is purely files, the library is purely scattering rules, the shader is purely color. Tweak any one independently.

## Project structure changes

```
res://
  assets/nature/
    tree_pine.glb              — NEW (Kenney)
    tree_pine.mesh.tres        — NEW (extracted Mesh resource for library use)
    tree_oak.glb               — NEW
    tree_oak.mesh.tres         — NEW
    rock_small.glb             — NEW
    rock_small.mesh.tres       — NEW
    rock_medium.glb            — NEW
    rock_medium.mesh.tres      — NEW
    grass_tuft.glb             — NEW
    grass_tuft.mesh.tres       — NEW
    grass_tuft_mat.tres        — NEW: per-item ShaderMaterial with base_color uniform
    rock_small_mat.tres        — NEW
    rock_medium_mat.tres       — NEW
    tree_pine_mat.tres         — NEW
    tree_oak_mat.tres          — NEW
  scenes/
    main.tscn                  — modified: add VoxelInstancer node under VoxelTerrain
    nature_library.tres        — NEW: VoxelInstanceLibrary with 5 entries (each entry references its mesh + material + a VoxelInstanceGenerator sub-resource)
  shaders/
    nature_tint.gdshader       — NEW: spatial shader, base_color uniform, desaturates + haze-tints
  scripts/                     — no changes
  project.godot                — no changes
```

(`rock_large` cut from earlier draft per spec review — too few instances to be worth the asset import.)

The shader path follows R1's pattern (`shaders/world_y_biome.gdshader` is in `scenes/`; we'll put R2's shader in a new top-level `shaders/` folder to start migrating shaders out of `scenes/`. This is a small targeted improvement — no broader refactor).

## Component: Asset source — Kenney Nature Kit

**Source:** https://kenney.nl/assets/nature-kit (CC0, no attribution required).

**Download workflow:** Manual download by the user, NOT a PowerShell direct fetch. Kenney's site uses per-pack download endpoints that 403 on direct GETs and rotate URLs. The implementer asks the user to:
1. Visit https://kenney.nl/assets/nature-kit
2. Click "Download" → save the .zip somewhere local (e.g., `C:\Users\whann\Downloads\`)
3. Tell the implementer the path; PowerShell extracts the zip and copies the .glb files we need.

**What we use** (5 files; verify exact source filenames during install — Kenney's nature kit ships hundreds of meshes):
- One grass tuft model → renamed `grass_tuft.glb` in our project
- A small rock → `rock_small.glb`
- A medium rock → `rock_medium.glb`
- A pine-style tree → `tree_pine.glb`
- A deciduous (oak-style) tree → `tree_oak.glb`

We rename to drop pack-specific naming.

**Mesh-resource extraction (Godot 4.6 import workflow):** Godot imports a `.glb` as a `PackedScene`. The actual `Mesh` resource lives inside a `MeshInstance3D` node within that scene. To get a usable `Mesh` resource for `VoxelInstanceLibraryMultiMeshItem.mesh`:

1. In the FileSystem dock, right-click the imported `.glb` → **Open in Inspector** (or instantiate it into a temp scene).
2. Drill down to the `MeshInstance3D` whose `mesh` property holds the geometry.
3. Right-click the `mesh` value → **Save As...** → save to `res://assets/nature/<name>.mesh.tres` (or `.res`).
4. Reference that `.mesh.tres` from the library item, not the original `.glb`.

(Alternative: at runtime, `var mesh = load("res://assets/nature/grass_tuft.glb").instantiate().get_child(0).mesh` — but the .tres-extraction approach keeps it inspector-friendly and avoids a runtime instantiate.)

**License compliance:** CC0 — no attribution required. Optional credit in a future README.

## Component: VoxelInstancer + VoxelInstanceLibrary

A `VoxelInstancer` node is added under `/Main/VoxelTerrain` (it requires this parent — it queries the parent terrain's voxel data to decide where to place instances).

The instancer references a single shared library resource saved at `res://scenes/nature_library.tres` (a `VoxelInstanceLibrary`). The library is a collection of indexed items; each item is a `VoxelInstanceLibraryMultiMeshItem`. **Important data-model note (caught in spec review):** the scatter rules (density, slope, height, scale, rotation, alignment) do NOT live directly on the library item — they live on a `VoxelInstanceGenerator` resource that the item's `generator` property references. Each library item gets its own `VoxelInstanceGenerator`.

**Library item (`VoxelInstanceLibraryMultiMeshItem`) fields used per row:**
- `mesh`: the imported mesh resource (extraction process below)
- `material_override`: our `nature_tint.gdshader` ShaderMaterial (with per-item base color uniforms)
- `cast_shadow`: `OFF` (0) for grass to save perf; default for rocks/trees
- `collision_shapes`: empty for grass; simple capsule auto-fit for trees (optional v1; can defer)
- `generator`: the `VoxelInstanceGenerator` sub-resource (see below)

**Generator (`VoxelInstanceGenerator`) fields used per row:**
- `density`: instances per m² (along surface)
- `min_scale`, `max_scale`: uniform random scale
- `random_rotation`: bool
- `min_slope_degrees`, `max_slope_degrees`: actual property names — angle from terrain up
- `min_height`, `max_height`: world-Y band (this DOES exist on the generator — earlier risk about "Y filter may not exist" is resolved)
- `vertical_alignment`: float in [0.0, 1.0]. 0.0 = align fully to terrain normal (rocks settle into slopes); 1.0 = always vertical regardless of terrain (grass, trees).
- `offset_along_normal`: tweak to push instance up/down along the terrain normal — use this if Kenney pivots are off-center.

The 6 library entries:

| ID | Name        | Mesh                | Density | Scale     | Slope° | Height m | vertical_alignment | cast_shadow |
|----|-------------|---------------------|---------|-----------|--------|----------|--------------------|-------------|
| 0  | grass_tuft  | grass_tuft.glb      | 1.5     | 0.8–1.2   | 0–30   | 1.2–99   | 1.0                | OFF         |
| 1  | rock_small  | rock_small.glb      | 0.05    | 0.5–1.2   | 0–60   | 0–99     | 0.3                | default     |
| 2  | rock_medium | rock_medium.glb     | 0.01    | 0.7–1.3   | 0–25   | 0.5–99   | 0.3                | default     |
| 3  | tree_pine   | tree_pine.glb       | 0.02    | 0.85–1.2  | 0–15   | 6–99     | 1.0                | default     |
| 4  | tree_oak    | tree_oak.glb        | 0.015   | 0.85–1.2  | 0–12   | 7–99     | 1.0                | default     |

**Note on entry count:** spec review pointed out `rock_large` at density 0.002 over ~15k m² gives ~30 instances total — a marginal count for a meaningful visual contribution per asset import. **Cut from R2.** We can add a hand-placed hero boulder later if needed (much better visual than 30 sprinkled). 5 entries instead of 6.

**Density math (recomputed after spec review):** the grass band on a 300m radial-falloff island covers roughly π·90²·0.6 ≈ 15k m² of land above the sand band. At density 1.5/m² → ~22k grass instances total. View-distance limited working set is much smaller (~3–5k visible at once). Forward+ handles this comfortably as one draw call via the multimesh batching. Earlier spec's 0.8 density / 56k claim was wrong.

**Tree count expectation:** trees with `min_height ≥ 6m` cover roughly the central 30% of the grass band (~5k m²). At density 0.02 → ~100 pines, density 0.015 → ~75 oaks. That's a believable forested-hilltop look, not "solo iconic" — if the user wants very sparse, drop densities to 0.005/0.003 (yields ~25/~15 trees, "iconic" feel).

**Y-range filter:** `min_height = 1.2` selects "above sand band → grass biome" (matches `sand_band` from R1's biome shader). Trees use higher floors (6–7m) to keep them on raised terrain. Rocks have no upper bound (`max_height = 99`); `min_height = 0` for small rocks lets them spawn on the sand.

## Component: Tint shader

**Important note from spec review:** setting `material_override` on the library item replaces the entire imported material. If Kenney encodes per-asset color in the material's albedo (likely — Nature Kit uses MaterialColor blocks, not vertex colors, in most assets), our shader gets no color information and renders everything as a single grayish tint. To preserve per-asset color identity, the shader takes a `base_color` uniform per ShaderMaterial instance, which we set to the asset's representative tint (sampled from the original Kenney material).

`shaders/nature_tint.gdshader`:

```glsl
shader_type spatial;
render_mode cull_disabled, diffuse_lambert;

uniform vec4 base_color : source_color = vec4(0.5, 0.6, 0.3, 1.0); // per-instance asset color (overridden per library item)
uniform float saturation : hint_range(0.0, 1.0) = 0.7;
uniform float haze_mix_strength : hint_range(0.0, 1.0) = 0.15;
uniform vec3 haze_color : source_color = vec3(0.85, 0.87, 0.90);

void fragment() {
	vec3 c = base_color.rgb;
	float l = dot(c, vec3(0.3, 0.59, 0.11));
	c = mix(vec3(l), c, saturation);            // desaturate slightly
	c = mix(c, haze_color, haze_mix_strength);  // tiny haze mix
	ALBEDO = c;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
}
```

**Per-item ShaderMaterial setup:** each library item gets its own `ShaderMaterial` (saved as `.tres`) referencing the same `nature_tint.gdshader`. The per-item `.tres` files differ only in the `base_color` parameter value:

| Item        | base_color (sampled from Kenney pack)             |
|-------------|---------------------------------------------------|
| grass_tuft  | `Color(0.45, 0.65, 0.30, 1)` — fresh green        |
| rock_small  | `Color(0.55, 0.55, 0.55, 1)` — neutral gray       |
| rock_medium | `Color(0.50, 0.50, 0.52, 1)` — slightly cooler    |
| tree_pine   | trunk + foliage handled together; tint averages a darker green `Color(0.30, 0.45, 0.25, 1)` (foliage dominates the visible silhouette) |
| tree_oak    | `Color(0.40, 0.55, 0.25, 1)` — brighter leafy green |

Trees pose a subproblem: a tree mesh has both trunk (brown) and foliage (green) surfaces, but our shader produces ONE color per item. The simplest v1 approach is to pick a single "averaged" color biased toward the visible canopy. **Acceptable risk:** trunks lose their brown identity. If this looks bad in playtest, the polish path is either (a) keep imported material on trunks (use a sub-resource per-surface override on the library item) or (b) add a `trunk_color` uniform and a vertical-Y-based blend in the shader. Park both for a polish round.

`cull_disabled` for grass thin geometry; safe across all asset types.

**Why not just push `Atmosphere.HAZE_COLOR` via init script (like R1's water):** for static decoration the haze color rarely changes; embedding the literal in the shader uniform default is fine and avoids one more runtime script.

## Component: Scene composition (main.tscn)

One node added: `VoxelInstancer` as a child of `VoxelTerrain`.

```
[node name="VoxelInstancer" type="VoxelInstancer" parent="VoxelTerrain"]
library = ExtResource("library_ref")
up_mode = 0
```

`up_mode = 0` means "use parent terrain's gravity-up direction" — terrain is flat in y so this just means +Y up. (Other modes are for spherical voxel worlds.)

That's the entire main.tscn change for R2.

## Risks and open questions

1. **Pack download is manual.** Kenney's per-pack download URLs aren't stable for direct fetch; user downloads the .zip via the website's button. PowerShell handles unzip + file extraction once the .zip is local. (Resolved from earlier "try direct first" guidance — direct doesn't work.)

2. **Imported material vs vertex-color.** Kenney Nature Kit assets use materials with embedded albedo color (NOT vertex colors). Spec assumes this and works around it via per-item `base_color` shader uniforms. If any specific asset turns out to use vertex colors after all, we have an embarrassment of options (the shader can be extended trivially), but no blocking risk.

3. **Trunk-vs-foliage color on trees.** Single-color tint loses the trunk's brown. Acceptable for v1; polish path documented in the Tint Shader section.

4. **Density tuning.** The numbers above use recomputed area math, but first playtest will likely require 2–3 retunes per asset. The plan includes a tuning task at the end.

5. **Imported mesh y-pivot.** Use `offset_along_normal` on the `VoxelInstanceGenerator` if assets float or sink. (`mesh_pivot_offset` is not a real property — earlier guidance was wrong.)

6. **Chunk-edge instance pop-in.** With 256m view distance and 16m chunks, the player WILL see grass/rocks/trees pop into existence at the visible edge. Mitigation: set `fading_enabled = true` on the `VoxelInstancer` (default `false`); fade duration default 0.3s is fine. Costs some perf but kills the pop.

7. **VoxelInstanceGenerator API verified.** Property names (`min_slope_degrees`/`max_slope_degrees`, `min_height`/`max_height`, `vertical_alignment` as 0–1 float, `density`, `min_scale`/`max_scale`, `random_rotation`, `offset_along_normal`) verified against Voxel Tools 1.6 docs during spec review. Earlier uncertainty resolved.

## Out of scope (parked for later rounds)

- Wind animation (grass sway, leaf rustle)
- Swaying tree trunks
- Foliage cards / impostor billboards for far instances
- Per-instance color variation (different shades of green grass)
- Foliage destruction tied to mining
- Distance-based fade-in/fade-out for instances
- Sound design (footsteps on grass/sand, leaves rustling)
- Bushes, flowers, mushrooms, fallen logs (Kenney pack has these — we're not using them this round)

## Success criteria

When this round ships:

- Walking onto the island, the player sees clumps of grass on grass-band terrain, scattered rocks across grass and sand bands, and occasional trees on hilltops.
- Grass and rocks DO NOT spawn underwater (below water_level) or in the sand-only ring.
- Trees DO NOT spawn on flat lowland — only on raised hilltops.
- The whole composition reads as a unified palette — no neon-saturated Kenney pieces standing out against the muted R1 atmosphere.
- Walking the perimeter does not cause noticeable instance pop-in (chunks pre-mesh enough ahead of the camera).
- Frame rate stays solid; no chugging.
