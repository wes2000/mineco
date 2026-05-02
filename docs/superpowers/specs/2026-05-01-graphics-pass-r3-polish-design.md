# Mine Co. — Graphics Pass Round 3: Polish

**Date:** 2026-05-01
**Project:** Mine Co. (Godot 4.6 module build with Voxel Tools 1.6, Forward+, D3D12)
**Status:** Approved by user, ready for implementation plan

## Goal

Add three small visual refinements that turn the shipped scene from "static photo" into "living place," entirely via shader edits to existing files. No new nodes, no new resources beyond the materials we already maintain.

1. **Foliage wind** — grass and tree leaves sway with a gentle breeze. Trunks stay anchored.
2. **Shoreline foam** — soft white band where the water plane meets shallow seabed.
3. **Per-grass color variation** — break the uniform-green look by hue-shifting individual grass instances based on their world position.

These compose: each adds movement OR breaks uniformity, so together they make the scene feel inhabited.

## Non-goals

- Wind affecting tree trunks or rocks (rocks have `wind_strength = 0`; tree trunks masked by vertex-Y stiffness)
- Wind affecting water (Gerstner waves are already moving; redundant layer)
- Distance-based wind gusts traveling across the field
- Foam as particles / sprites — purely shader fragment color
- Per-instance scale variation beyond what generators already do
- Color variation on rocks/trees (their shape diversity already handles uniformity)
- Footstep effects, swaying tree branches as separate animation, day/night-driven wind direction

## Architecture overview

Three shader modifications, no new files:

1. **`shaders/nature_tint.gdshader`** gains:
   - Wind vertex displacement (vertex stage)
   - Per-instance color variation via world-position hash (fragment stage)
   - Two new uniforms: `wind_strength`, `color_variation_amount` — both default 0.0 so the shader behavior is opt-in per material.

2. **`scenes/water_waves.gdshader`** gains:
   - Foam color blend in the fragment stage, gated by underwater_distance (the depth-band metric the shader already computes).
   - **Note:** the current water shader does NOT have a `world_pos` varying — it computes its depth math from view-space `VERTEX.z` directly. Foam noise needs world coordinates, so we add `varying vec3 world_pos;` in this round.

3. **Per-item `*_mat.tres` files** set the new uniforms appropriately:
   - Grass: wind on, color variation on
   - Trees: wind on (gentler than grass), color variation off
   - Rocks: both off (they sit still and rely on shape variety)

## Project structure changes

```
res://
  shaders/
    nature_tint.gdshader        — modified: add wind + color variation
    water_waves.gdshader        — modified: add foam
  assets/nature/
    grass_tuft_mat.tres         — set wind_strength=0.18, color_variation_amount=1.0
    rock_small_mat.tres         — unchanged (uniforms default to 0)
    rock_medium_mat.tres        — unchanged
    tree_pine_mat.tres          — set wind_strength=0.10
    tree_oak_mat.tres           — set wind_strength=0.12
```

No node changes, no scene changes, no scripts.

## Component: Foliage wind

Extends `nature_tint.gdshader`. Adds:

```glsl
uniform float wind_strength : hint_range(0.0, 1.0) = 0.0;
uniform float wind_speed : hint_range(0.0, 5.0) = 1.5;
uniform vec2 wind_direction = vec2(1.0, 0.0);
uniform float wind_stiffness_height : hint_range(0.5, 5.0) = 2.0;
```

Vertex stage adds (purely additive — fragment behavior unchanged):

```glsl
void vertex() {
	if (wind_strength > 0.0) {
		// Use the INSTANCE pivot world position (NOT per-vertex world_pos) so all vertices
		// of one instance share one phase. Per-vertex world_pos would warp the mesh internally
		// (especially for trees where vertices span 1-2m, producing visible distortion).
		vec3 instance_origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
		float gust = 0.7 + 0.3 * sin(TIME * 0.3);
		float phase = dot(instance_origin.xz, wind_direction) * 0.3 + TIME * wind_speed;
		float stiffness = smoothstep(0.0, wind_stiffness_height, VERTEX.y);
		float sway = sin(phase) * stiffness * wind_strength * gust;
		VERTEX.x += sway * wind_direction.x;
		VERTEX.z += sway * wind_direction.y;
	}
}
```

The mechanism:
- `instance_origin` is the per-instance pivot world position (read from MODEL_MATRIX). Each MultiMesh instance gets its own MODEL_MATRIX → its own phase → wind ripples across the field as a wave, not in lockstep.
- All vertices of one instance share that phase, so the blade/tree sways as a coherent unit (no internal warping).
- `stiffness` ramps from 0 at the mesh's local-Y zero (base) to 1 at `wind_stiffness_height` (a per-asset estimate of where the swayable part starts). For grass (mesh ~1m tall), stiffness saturates near the tip. For trees (mesh ~2-4m before instance scale), the trunk stays stationary up to `wind_stiffness_height` and foliage above sways.
- `gust` is the slow secondary modulation — periods of stronger and lighter wind.
- VERTEX is in MODEL space; we add to its X and Z (horizontal sway only, no vertical lift).
- `wind_strength` is in **model-space units** (meters at instance scale 1.0). Grass at strength 0.18 → 18cm tip displacement at peak gust on a 1m blade — enough to read but not exaggerated.

Per-material settings (starting points — tune in playtest):
- `grass_tuft_mat.tres`: `wind_strength = 0.18`, `wind_stiffness_height = 1.0` (full grass mesh sways above its base)
- `tree_pine_mat.tres`: `wind_strength = 0.10`, `wind_stiffness_height = 2.5` (trunk stays put up to 2.5m, then leaves sway)
- `tree_oak_mat.tres`: `wind_strength = 0.12`, `wind_stiffness_height = 2.5`
- `rock_small_mat.tres` / `rock_medium_mat.tres`: leave defaults (`wind_strength = 0` → branch never executes).

> Note: tree `wind_stiffness_height` of 2.5m may anchor too much of a 1.5–2m Kenney tree mesh, leaving little to sway. After import, the implementer should inspect actual mesh extents and tune. If the tree is shorter than 2.5m, drop `wind_stiffness_height` to ~50% of mesh height.

## Component: Per-grass color variation

Same shader (`nature_tint.gdshader`). Adds:

```glsl
uniform float color_variation_amount : hint_range(0.0, 1.0) = 0.0;

float hash12(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}
```

In `fragment()`, after computing the existing tinted color into a variable `c`:

```glsl
if (color_variation_amount > 0.0) {
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float v = hash12(floor(world_pos.xz * 4.0)); // quantize so a single instance shares the value
	c.g += (v - 0.5) * 0.20 * color_variation_amount;
	c.r += (v - 0.5) * 0.10 * color_variation_amount;
	c = clamp(c, vec3(0.0), vec3(1.0));
}
```

Notes:
- `world_pos` recomputed via INV_VIEW_MATRIX * VERTEX in fragment (VERTEX in fragment stage is view-space). Slight redundancy with vertex-stage world_pos but cheap.
- `floor(world_pos.xz * 4.0)` quantizes to ~25cm grid — neighboring fragments of the same grass blade get the same hash value (so the blade is uniformly tinted), but two grass blades at different world positions get different hashes. Adjust the multiplier if grass blade size differs from estimate.
- Variation gated to `color_variation_amount = 1.0` only on grass (in `grass_tuft_mat.tres`). At 1.0, ±10% green / ±5% red is the full effect — visibly varied without going wild.
- The bias toward green (`±10%`) over red (`±5%`) keeps grass reading as "various greens" rather than "various random colors."

## Component: Shoreline foam

Extends `scenes/water_waves.gdshader`. Adds uniforms:

```glsl
uniform vec3 foam_color : source_color = vec3(0.95, 0.97, 1.0);
uniform float foam_distance = 1.5;
uniform float foam_softness = 0.5;
uniform float foam_max_strength : hint_range(0.0, 1.0) = 0.7;
```

**Sequencing note:** the foam term must be applied AFTER the existing `ALBEDO = mix(base, sky_color, fresnel)` line, NOT before. At grazing-angle shore views, fresnel is near 1.0 → if foam is mixed into `base` first, the subsequent fresnel mix overwrites it with sky color. Apply foam to `ALBEDO` directly after fresnel so it survives.

**Required varying addition:** the current water shader has no `world_pos` varying. Add `varying vec3 world_pos;` and write it in `vertex()` after the displacement is applied:

```glsl
varying vec3 world_pos;  // declare at top of shader

void vertex() {
	// ... existing Gerstner displacement ...
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;  // add at end of vertex()
}
```

Then in `fragment()` after the existing `ALBEDO = mix(base, sky_color, fresnel);` line:

```glsl
// Foam where seabed is close to water surface (shoreline)
float foam_t = smoothstep(foam_distance, foam_distance - foam_softness, underwater_distance);
// Two octaves of cheap noise so the foam edge has small + larger ripples
float n1 = sin(world_pos.x * 1.3 + TIME * 0.5) * sin(world_pos.z * 1.3 + TIME * 0.4);
float n2 = sin(world_pos.x * 0.4 + TIME * 0.2) * sin(world_pos.z * 0.4 + TIME * 0.3);
float foam_noise = (n1 * 0.6 + n2 * 0.4) * 0.5 + 0.5;
foam_t *= mix(0.6, 1.0, foam_noise);
ALBEDO = mix(ALBEDO, foam_color, foam_t * foam_max_strength);
```

The mechanism:
- `underwater_distance` is the existing seabed-to-surface depth metric (computed earlier in fragment).
- When that distance is < `foam_distance` (1.5m of shallow water), foam blends in.
- `foam_softness` (0.5m) gives a smooth fade-out at the foam's outer edge.
- Two-octave sin noise: 1.3/m frequency (period ~5m, finer ripples) + 0.4/m frequency (period ~16m, broader undulation). Combined gives a more organic, less repetitive foam edge.
- Mix applied to `ALBEDO` (post-fresnel) so foam survives the sky-tint at grazing angles.
- `foam_max_strength` (0.7) caps the foam's contribution so it never fully whitens the water — always some sky/depth color visible.

## Risks and open questions

1. **MultiMesh + per-vertex wind shader cost.** Wind adds ~10 GPU ops per vertex × 22k+ grass verts × 60 fps. Cheap on modern hardware (single-digit ms total). If perf takes a hit on weaker GPUs, the implementer can drop wind on grass (set `wind_strength = 0` on grass, keep wind on the much-fewer-vertex trees only).

2. **Wind looks too uniform / "all blades sync up" ** — risk if `wind_direction` and `phase` produce coincidental period-aligned visuals. Mitigation: the spatial-`phase` term derived from world position breaks lockstep automatically. If still synced-looking in playtest, tune `wind_speed` (try 0.7) or add a second sine wave with a different direction.

3. **Color hash producing too-bright outliers.** `hash12` returns [0,1]; ±10% green / ±5% red on top of grass color (~`Color(0.45, 0.65, 0.30)`) keeps results within a believable range. The clamp(c, 0, 1) prevents anything wild.

4. **Foam appearing on the water plane at the seabed-far-away horizon.** With `underwater_distance` very large at the deep horizon, `foam_t` should be 0. But Godot's depth texture might return values that produce a near-zero `underwater_distance` at the far clip plane in some edge cases. Mitigation: foam_distance = 1.5m means the smoothstep clamps at 0 for any underwater_distance ≥ 1.5m. If it leaks somehow, `foam_max_strength` cap means the worst-case is a pale tinge.

5. **Tree mesh vertex layout.** The `wind_stiffness_height = 2.5` assumes Kenney trees have their trunk in the lower 2.5m and foliage above. If a particular tree mesh is shorter (e.g., the imported scale × mesh height < 2.5m), the entire tree may sway because all of it has high stiffness. Mitigation: tune per-asset by inspector.

6. **Color variation hash band edges.** `floor(world_pos.xz * 4.0)` creates 25cm cells; at the edge between cells, color jumps abruptly. Within a single grass blade (~25cm wide) the cell is consistent, but if grass spawns straddling a cell boundary, half the blade reads as one color and half as another. Realistically: rarely visible at gameplay distance; if obvious in close-up, raise the multiplier (smaller cells) or use a smoother noise function.

7. **Stale normals on swaying tree foliage.** Vertex displacement moves vertices but doesn't recompute normals — Lambert lighting on a tree's foliage uses the original (un-swayed) normals. For grass with `cull_disabled` and small displacement (~18cm) this is invisible. For trees, larger sway amplitude on a static-normal silhouette may produce slightly "off" shading where lit/shadow side doesn't track the new surface orientation. Acceptable for R3 polish (tree wind strength is gentle enough to mask it); a future shader pass could recompute normals via cross-product of swayed tangent/binormal if needed.

## Out of scope (deferred to R4+)

- Wind direction varying with global wind system / Atmosphere singleton
- Wind affecting cloth/banners/ NPCs (no such things in scene)
- Distance-based wind strength roll-off
- Foam splash particles
- Wet sand near the foam line (sand getting darker near the water edge)
- Procedural ripples around the player when they wade in shallow water
- Specular highlights varying with wind direction (advanced PBR)

## Success criteria

When this round ships:

- Grass visibly sways in a gentle wind. Tips move; bases stay rooted.
- Tree foliage moves slightly; trunks are static.
- Rocks remain perfectly still.
- Shoreline shows a soft white foam band where water meets shallow seabed.
- Foam edge has a wavy, slowly-shifting boundary — not a perfect ring.
- Grass field looks naturally varied — no instance reads as identical to its neighbors.
- Frame rate stays solid.
