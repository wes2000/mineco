# Mine Co. — Island v1 Design

**Date:** 2026-05-01
**Project:** Mine Co. (Godot 4.6, Jolt Physics, Forward+, D3D12)
**Status:** Approved by user, ready for implementation plan

## Goal

A walkable, low-poly island scene with realistic-feeling topography and a first-person player controller. This is the foundation for a mining game, so the terrain layer must support runtime digging (caves, tunnels, shafts, overhangs) without rework later.

## Non-goals (v1)

Trees, foliage, ambient sound, footstep audio, water shader/waves, headbob, sprint, day/night cycle, persistence of terrain edits, NPCs, mining mechanics. Each of these slots in cleanly after v1 ships; v1 is "walk around a believable island."

## Architecture overview

Three independent subsystems composed in a single main scene:

1. **Terrain** — voxel SDF terrain (Zylann's `godot_voxel` GDExtension) with a custom GDScript generator that builds an island shape from layered noise + radial falloff. Smooth shading via Transvoxel mesher. Biome (sand/grass) coloring via a small `ShaderMaterial` that picks albedo from world-space Y (no per-voxel color storage — Transvoxel does not emit vertex colors). Built-in collision that updates per chunk — required for digging later.
2. **Player** — `CharacterBody3D` with WASD movement, jump, mouse-look first-person camera. Pure GDScript, no addons.
3. **Scene composition** — sky/sun via `WorldEnvironment` + `DirectionalLight3D`, flat translucent water plane at y=0, terrain at origin, player spawned above the island.

These are independent: the player works with any collidable world, the terrain works with any controller, the scene wires them together.

## Project structure

```
res://
  addons/
    godot_voxel/                 # Voxel Tools 1.6 GDExtension (drop-in)
    godot_ai/                    # already present
  scenes/
    main.tscn                    # entrypoint scene
    player.tscn
  scripts/
    player.gd
    island_voxel_generator.gd    # extends VoxelGeneratorScript
  docs/
    superpowers/specs/           # this doc lives here
```

`project.godot` updates:
- `application/run/main_scene = "res://scenes/main.tscn"`
- Input map adds these actions with these defaults:
  - `move_forward` → W (`KEY_W`)
  - `move_back` → S (`KEY_S`)
  - `move_left` → A (`KEY_A`)
  - `move_right` → D (`KEY_D`)
  - `jump` → Space (`KEY_SPACE`)
  - (`ui_cancel` already exists for releasing mouse capture.)

## Component: Voxel terrain

### Dependency

**Voxel Tools 1.6 GDExtension** (Feb 2026 release), Windows precompiled, supports Godot 4.5+. Installed by unzipping into `res://addons/zylann.voxel/`. Maintainer marks the GDExtension build as "not extensively tested" — known risk. Fallback if blocked: switch to the precompiled Godot 4.6 binary that has the module built in (Tokisan Games / Zylann release).

### Node setup (in `main.tscn`)

`VoxelTerrain` node (single-LOD; not `VoxelLodTerrain`) configured with:
- `mesher`: `VoxelMesherTransvoxel` — smooth SDF surface, suitable for Firewatch aesthetic
- `generator`: assigned in inspector to `res://scenes/island_generator.tres` (a `.tres` instance of `IslandVoxelGenerator`)
- `generate_collisions = true` — `CharacterBody3D` interacts via Godot physics; collider regenerates per chunk
- Voxels are **1m** at LOD0 (`VoxelTerrain` does not expose `voxel_size`; that property lives on `VoxelLodTerrain`). All sizes in this spec are stated in meters/world units, which equal voxel units at 1:1.
- `bounds`: an `AABB` covering `x:[-200,200], y:[-100,100], z:[-200,200]`. Godot's `AABB` constructor is `AABB(position, size)`, so this is `AABB(Vector3(-200, -100, -200), Vector3(400, 200, 400))`. The horizontal extent matches the water plane footprint so there is always seabed under visible water.
- `material_override`: a `ShaderMaterial` with a small `world_y_biome.gdshader` that computes albedo from the fragment's world-space Y. Sand at/below `water_level + sand_band`, lerped to grass above. Roughness 0.9, metallic 0. (Transvoxel's documented texturing pipeline uses `CHANNEL_INDICES`/`CHANNEL_WEIGHTS` for per-voxel texture splatting — overkill for v1's two visible biomes. World-Y in a shader is the simplest thing that works and matches Firewatch's "color by elevation" feel.)
- No `stream` set — v1 has no persistence (added when digging lands)

### Generator: `island_voxel_generator.gd`

`extends VoxelGeneratorScript`. Saved as `res://scripts/island_voxel_generator.gd`. A resource instance is saved at `res://scenes/island_generator.tres` and assigned to the `VoxelTerrain.generator` slot in `main.tscn`. Tunables on the `.tres` are editable in the inspector without touching code.

**Method signature (pin this — easy to get wrong):**

```gdscript
func _generate_block(out_buffer: VoxelBuffer, origin_in_voxels: Vector3i, lod: int) -> void
```

`origin_in_voxels` is a `Vector3i` in voxels (not world meters). At LOD0 with our 1m voxels they are equal; the implementer must still treat the parameter as `Vector3i` and not assume floats. `lod` will always be 0 for our setup.

**Required `_init` setup:**
- Configure SDF channel as 32-bit float to avoid the default 16-bit fixed-point clipping our height-difference values: `out_buffer.set_channel_depth(VoxelBuffer.CHANNEL_SDF, VoxelBuffer.DEPTH_32_BIT)`. (Done per-buffer inside `_generate_block` since `out_buffer` is provided by the engine; depth must be set before any writes to that channel.)
- Construct the `FastNoiseLite` instance from exported params; propagate seed.

**SDF sign convention:** negative = solid, positive = air. We write `world_y - h(x,z)`.

**Exported tunables (on the resource):**
- `seed: int = 0`
- `size: float = 300.0` — island diameter (square footprint, centered on origin)
- `max_height: float = 18.0`
- `water_level: float = 0.0`
- `noise_frequency: float = 0.008`, `noise_octaves: int = 4`, `noise_lacunarity: float = 2.0`, `noise_gain: float = 0.5`
- `falloff_inner: float = 0.45`, `falloff_outer: float = 0.95` — radial smoothstep, fractions of `size/2`
- `edge_bias: float = 5.0` — subtracted from height so the entire falloff ring sits at or below water level. Tuned so even max-noise samples in the outer ring (≈ `max_height * (1 - falloff_value) - edge_bias`) end up ≤ 0.

(The `sand_band`, `sand_color`, and `grass_color` tunables live on the `ShaderMaterial`'s shader uniforms, not the generator — generator only owns terrain shape, shader owns surface color. This keeps shape-vs-look concerns separable.)

**Per-block algorithm:**
1. Compute the block's world-space AABB from `origin_in_voxels * voxel_unit_size` (1m) and the buffer size.
2. **Fast path** using `out_buffer.fill_f`:
   - If `block.aabb.position.y >= max_height` → `fill_f(10.0, CHANNEL_SDF)` (all air; `10.0` rather than `1.0` to avoid edge-of-fixed-point clipping if `set_channel_depth` is skipped).
   - If `block.aabb.position.y + block.aabb.size.y <= -edge_bias - 1.0` → `fill_f(-10.0, CHANNEL_SDF)` (all solid).
3. **Surface band path** (per-voxel via `set_voxel_f`):
   - For each voxel (x,y,z) in the block, compute world position.
   - Surface height `h(x,z) = fbm(x,z) * max_height * radial_falloff(x,z) - edge_bias`, where `radial_falloff = 1.0 - smoothstep(falloff_inner, falloff_outer, distance_xz / (size/2))`.
   - Write `world_y - h(x,z)` to `CHANNEL_SDF` via `out_buffer.set_voxel_f(value, x, y, z, CHANNEL_SDF)`.

The generator does NOT write `CHANNEL_COLOR` (Transvoxel ignores it). Biome ID can optionally be written to `CHANNEL_INDICES` for future foliage/footstep queries — kept simple in v1 by skipping it; if it's needed later we re-bake (cheap, deterministic via `seed`).

**Surface color shader (`res://scenes/world_y_biome.gdshader`):**

```glsl
shader_type spatial;
render_mode cull_back, diffuse_lambert;

uniform float water_level = 0.0;
uniform float sand_band = 1.2;
uniform vec3 sand_color : source_color = vec3(0.92, 0.85, 0.65);
uniform vec3 grass_color : source_color = vec3(0.35, 0.55, 0.25);

varying vec3 world_pos;

void vertex() {
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    float t = clamp((world_pos.y - water_level) / sand_band, 0.0, 1.0);
    t = smoothstep(0.0, 1.0, t);
    ALBEDO = mix(sand_color, grass_color, t);
    ROUGHNESS = 0.9;
    METALLIC = 0.0;
}
```

The `ShaderMaterial` exposes `water_level`, `sand_band`, `sand_color`, `grass_color` as inspector tunables. (Note: `water_level` should match the generator's `water_level` so the sand band aligns with the shoreline. Single source of truth in this design is the shader; the generator just uses 0.0 for its own falloff calculation as before.)

### Why this supports digging later

Voxel data is full 3D SDF, not a 2D heightmap. When mining ships, we add (roughly):
- A `VoxelStreamSQLite` for persistence of edits across runs
- Left-click handler that calls `voxel_terrain.get_voxel_tool().do_sphere(hit_position, brush_radius)` with `MODE_REMOVE`

Caves, overhangs, tunnels, vertical shafts work because the data model already represents them. Collider updates per affected chunk on its own.

## Component: Player

### Scene: `player.tscn`

`CharacterBody3D` (root) with:
- `CollisionShape3D` — `CapsuleShape3D`, height 1.8m, radius 0.4m, centered so feet are at the body origin
- `Camera3D` — child, positioned at y=1.6 (head height), inherits yaw from body, applies pitch on itself
- No visible mesh (pure first-person)

### Script: `player.gd`

`extends CharacterBody3D`. Constants: `SPEED = 5.0`, `JUMP_VELOCITY = 5.0`, `MOUSE_SENSITIVITY = 0.002`.

- `_ready`: capture mouse (`Input.mouse_mode = Input.MOUSE_MODE_CAPTURED` — `MOUSE_MODE_CAPTURED` is enum-scoped under `Input`)
- `_unhandled_input(event)`:
  - `InputEventMouseMotion`: rotate body by `-event.relative.x * SENS` on Y; rotate camera by `-event.relative.y * SENS` on X, clamped to ±89°
  - `ui_cancel` (Esc) action: toggle mouse capture (dev convenience)
- `_physics_process(delta)`:
  - Apply gravity from `ProjectSettings.physics/3d/default_gravity`
  - `input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")`
  - `direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()`
  - Set `velocity.x` and `velocity.z` from direction × SPEED
  - Jump: if `is_on_floor()` and `Input.is_action_just_pressed("jump")` → `velocity.y = JUMP_VELOCITY`
  - `move_and_slide()`

### Spawn

Player is placed in `main.tscn` at `(0, 30, 0)` so they fall onto whatever terrain has generated.

**Spawn safety — chunks must exist before the player moves.** If physics runs while the spawn chunk is still meshing, the player tunnels through to `y = -∞`. Mitigation: in `main.tscn`, freeze the player's `physics_process` until `VoxelTerrain.mesh_block_entered` has fired for the chunk under spawn (or a downward raycast from spawn hits something). Implement as: connect to `mesh_block_entered`, on first signal where `mesh_block_position` covers spawn x/z, call `player.set_physics_process(true)` and disconnect.

## Component: Scene composition (`main.tscn`)

Root `Node3D` containing:
- `WorldEnvironment` — procedural sky (Godot's built-in `Sky` resource with `ProceduralSkyMaterial`), exposure tuned for outdoors, ambient light energy ~0.3
- `DirectionalLight3D` — sun, rotated ~45° from horizontal, soft warm tint, shadows enabled, shadow bias tuned to avoid acne on voxel surface
- `VoxelTerrain` — at origin, configured as above, generator resource assigned
- `Water` — `MeshInstance3D` with `PlaneMesh` 400m × 400m at y=0, `StandardMaterial3D` with translucent blue, no shader for v1. Footprint matches voxel terrain bounds (±200 horizontal) so the player never sees water without a seabed beneath.
- `Player` — instance of `player.tscn` at `(0, 30, 0)`. `physics_process` starts disabled; enabled via `VoxelTerrain.mesh_block_entered` per Spawn section above.

## Risks and open questions

1. **GDExtension stability** — maintainer notes 1.6 GDExtension is "not extensively tested." Mitigation: if a blocking bug surfaces, fall back to a precompiled Godot binary with the module built in. Decision deferred until blocker actually hits.
2. **First-run terrain gen perf** — voxel generators run per chunk. Chunks at spawn must finish before the player can stand; addressed by the `mesh_block_entered` gate in the Spawn section. If first-paint is still slow, shrink `bounds` height range. Tune in playtest.
3. **Voxel seam artifacts** — Transvoxel can show seams between LODs, but we use single-LOD `VoxelTerrain` (not `VoxelLodTerrain`), so this won't apply.
4. **(resolved during planning)** Transvoxel does not emit `CHANNEL_COLOR` as vertex colors — its texturing pipeline uses `CHANNEL_INDICES`/`CHANNEL_WEIGHTS` for splatmap-style blending. We avoid that path entirely by computing biome color in a small fragment shader from world-Y. Simpler than vertex-color and decouples shape from look.

## Out of scope (v1) — staged for later

- Mining: voxel brush + `VoxelStreamSQLite` persistence
- Foliage: `MultiMeshInstance3D` grass tufts and trees, sampled from biome data
- Audio: footsteps (raycast to identify biome), ambient wind, water lap
- Player polish: sprint, headbob, FOV kick, crouch, interact prompt
- Water polish: gerstner waves shader, foam at shoreline, depth-based color
- Day/night cycle, weather

## Success criteria

- Open `main.tscn`, press F5, fall onto an island.
- Walk around with WASD, look with mouse, jump with space, release mouse with Esc.
- Visible water/sand/grass biome bands as height increases from the shoreline.
- Terrain reads as a smooth low-poly island, not a heightmap-with-cliffs or a Minecraft-blocky mess.
- No frame drops while walking the perimeter.
