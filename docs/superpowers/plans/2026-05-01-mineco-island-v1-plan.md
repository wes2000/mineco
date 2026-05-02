# Mine Co. — Island v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A walkable low-poly island with voxel-SDF terrain, biome-colored water/sand/grass shading, and a first-person WASD+jump player controller in Godot 4.6.

**Architecture:** Single `main.tscn` composes (a) a `VoxelTerrain` driven by a custom `VoxelGeneratorScript` resource, (b) a flat translucent water plane at y=0, (c) sky+sun via `WorldEnvironment` + `DirectionalLight3D`, and (d) a `CharacterBody3D` first-person player. Voxel terrain (vs heightmap) is required so future mining can carve caves, tunnels, and shafts without rework.

**Tech Stack:** Godot 4.6.2-stable, GDScript, Jolt Physics, Forward+ renderer, D3D12, Voxel Tools 1.6 GDExtension (Zylann's `godot_voxel`).

**Spec:** `docs/superpowers/specs/2026-05-01-mineco-island-v1-design.md`

**Project root:** `C:\Users\whann\Documents\mine-co\` (Windows). All `res://` paths resolve under this root.

## Validation philosophy

This is a Godot scene project, not a library. Pure GDScript unit tests would require pulling in GUT or GdUnit4 just for two scripts — pure ceremony. Instead, **every task has a concrete in-editor verification step** using the `godot-ai` MCP tools (`project_run`, `editor_screenshot`, `logs_read`) or in-scene observation. The verifications are written as testable assertions ("expected: terrain visible, sand band ringing the island, player falls and lands within 2 seconds"). If a step's expected outcome doesn't match, stop and diagnose — do not proceed to the next task.

## File structure (final)

```
res://
  addons/
    godot_voxel/                          # T1 — Voxel Tools 1.6 GDExtension drop
    godot_ai/                             # already present, untouched
  scenes/
    main.tscn                             # T4-T7 — built up progressively
    player.tscn                           # T6
    island_generator.tres                 # T3
    world_y_biome.gdshader                # T4
    terrain_material.tres                 # T4 — ShaderMaterial wrapping the shader
  scripts/
    island_voxel_generator.gd             # T3
    player.gd                             # T6
    spawn_gate.gd                         # T7 — small node that gates player physics on first chunk meshed
  project.godot                           # T2 — input map + main_scene
  docs/superpowers/
    specs/2026-05-01-mineco-island-v1-design.md   # already written
    plans/2026-05-01-mineco-island-v1-plan.md     # this file
```

## Task dependency graph

```
T1 (addon) ─┬─> T3 (generator) ─┐
            └─> T4 (terrain in scene) ─> T5 (water+sky) ─> T7 (wire player) ─> T8 (walkthrough)
T2 (project setup) ─> all subsequent
T6 (player) ──────────────────────────┘
```

T3 and T6 are independent and can be parallelized across two subagents after T1+T2 complete.

---

### Task 1: Install Voxel Tools 1.6 GDExtension

**Files:**
- Create: `res://addons/zylann.voxel/` (entire folder from extracted zip)

**Goal:** Get the GDExtension loaded so `VoxelTerrain` and `VoxelGeneratorScript` classes are available in the editor.

- [ ] **Step 1: Download the GDExtension zip (manual, simplest path)**

Go to https://github.com/Zylann/godot_voxel/releases. Find the **"Voxel Tools 1.6 GDExtension"** release (Feb 2026). Download the asset whose name contains `gdextension` (a multi-platform `.zip` with Windows binaries included). Save it to `C:\Users\whann\Downloads\` (or anywhere convenient).

Then unzip into the project's `addons/` folder:

```powershell
$zipPath = "C:\Users\whann\Downloads\<filename you downloaded>.zip"
$tmp = Join-Path $env:TEMP "voxel_extract"
if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
Expand-Archive -Path $zipPath -DestinationPath $tmp -Force
# The zip extracts an `addons/zylann.voxel/` tree at the root.
Copy-Item -Path (Join-Path $tmp "addons\zylann.voxel") -Destination "C:\Users\whann\Documents\mine-co\addons\" -Recurse -Force
```

If the unzipped layout is different (e.g., the zip root IS `godot_voxel/` directly, or there's a versioned wrapper folder), inspect `$tmp` and copy the right subfolder so it lands at exactly `C:\Users\whann\Documents\mine-co\addons\zylann.voxel\`.

- [ ] **Step 2: Verify the addon files landed**

Run from project root:

```powershell
Get-ChildItem -Path "C:\Users\whann\Documents\mine-co\addons\zylann.voxel" -Filter "*.gdextension" -Recurse | Select-Object FullName
```

Expected: at least one `.gdextension` file is listed (e.g., `voxel.gdextension`). If empty, the zip layout differs and the implementer must inspect `$tmp.FullName` and copy the right subfolder manually.

- [ ] **Step 3: Reload the editor so it picks up the new GDExtension**

Use the godot-ai MCP:

```
mcp__godot-ai__editor_manage op="quit"
```

Then the user will reopen the editor manually (or relaunch via Godot's project list). After reopen, verify with:

```
mcp__godot-ai__editor_state
```

Expected: `readiness` is not "no_scene" / project loads cleanly without errors complaining about missing extensions.

> **Note:** If MCP can't quit/relaunch the editor automatically, ask the user to close and reopen Godot, and wait for confirmation before proceeding.

- [ ] **Step 4: Verify VoxelTerrain class is registered**

Use the godot-ai MCP to inspect logs after editor reload:

```
mcp__godot-ai__logs_read
```

Expected: no errors mentioning "godot_voxel", "VoxelTerrain", or "extension". If errors appear, the GDExtension build is incompatible with this Godot 4.6 version — fall back to the precompiled Godot 4.6 binary with the module built in (linked from Tokisan Games or Zylann's release page).

- [ ] **Step 5: Smoke-create a VoxelTerrain node to confirm class exists**

Via MCP, create a temporary throwaway scene:

```
mcp__godot-ai__scene_manage op="create" params={"path": "res://_addon_check.tscn", "root_type": "VoxelTerrain"}
```

Expected: succeeds without error. Then delete it:

```powershell
Remove-Item "C:\Users\whann\Documents\mine-co\_addon_check.tscn"
Remove-Item "C:\Users\whann\Documents\mine-co\_addon_check.tscn.import" -ErrorAction SilentlyContinue
```

- [ ] **Step 6 (optional, if git is initialized): Commit**

```bash
git add addons/zylann.voxel
git commit -m "feat: install Voxel Tools 1.6 GDExtension"
```

If `.git` doesn't exist (it doesn't currently), skip this step. Same applies to all later commit steps.

---

### Task 2: Project structure and input map

**Files:**
- Create: `scenes/` (folder), `scripts/` (folder)
- Modify: `project.godot`

**Goal:** Folders ready for code, input actions defined for the player controller, main scene path pointing at our (not-yet-existent) `main.tscn`.

- [ ] **Step 1: Create the folders**

```powershell
New-Item -ItemType Directory -Path "C:\Users\whann\Documents\mine-co\scenes" -Force | Out-Null
New-Item -ItemType Directory -Path "C:\Users\whann\Documents\mine-co\scripts" -Force | Out-Null
```

- [ ] **Step 2: Add input actions via the godot-ai MCP (preferred path)**

This avoids hand-editing `project.godot`'s tricky InputEventKey serialization. Run these MCP calls in sequence:

```
mcp__godot-ai__input_map_manage op="add_action" params={"action": "move_forward"}
mcp__godot-ai__input_map_manage op="bind_event" params={"action": "move_forward", "physical_keycode": 87}

mcp__godot-ai__input_map_manage op="add_action" params={"action": "move_back"}
mcp__godot-ai__input_map_manage op="bind_event" params={"action": "move_back", "physical_keycode": 83}

mcp__godot-ai__input_map_manage op="add_action" params={"action": "move_left"}
mcp__godot-ai__input_map_manage op="bind_event" params={"action": "move_left", "physical_keycode": 65}

mcp__godot-ai__input_map_manage op="add_action" params={"action": "move_right"}
mcp__godot-ai__input_map_manage op="bind_event" params={"action": "move_right", "physical_keycode": 68}

mcp__godot-ai__input_map_manage op="add_action" params={"action": "jump"}
mcp__godot-ai__input_map_manage op="bind_event" params={"action": "jump", "physical_keycode": 32}
```

Physical keycodes: W=87, A=65, S=83, D=68, Space=32. The actual rollup parameter shape may vary (`physical_keycode` vs `keycode` vs `event` object) — check the MCP tool's schema if a call fails, then adapt; the intent is "bind this physical key to this action."

- [ ] **Step 2b: Set the main scene path**

Use the MCP `project_manage` rollup if available:

```
mcp__godot-ai__project_manage op="settings_set" params={"key": "application/run/main_scene", "value": "res://scenes/main.tscn"}
```

If that op isn't supported, edit `project.godot` directly: in the `[application]` section add `run/main_scene="res://scenes/main.tscn"`. That's a single key-value, no risky serialization.

- [ ] **Step 3: Verify input actions registered**

MCP:
```
mcp__godot-ai__input_map_manage op="list"
```

Expected: output contains `move_forward`, `move_back`, `move_left`, `move_right`, `jump`, each bound to its expected key.

- [ ] **Step 4 (optional): Commit**

```bash
git add project.godot scenes scripts
git commit -m "feat: project structure and input map for player controller"
```

---

### Task 3: Island voxel generator script + resource

**Files:**
- Create: `res://scripts/island_voxel_generator.gd`
- Create: `res://scenes/island_generator.tres`

**Goal:** A `VoxelGeneratorScript` resource that produces an island-shaped SDF voxel field. Generator owns terrain shape only — surface color is the shader's job (T4). Tunable via inspector exports.

> **Important:** Transvoxel does not emit `CHANNEL_COLOR` as visible vertex colors. We do NOT write that channel here. The biome color appears via a fragment shader keyed off world-Y in T4.

- [ ] **Step 1: Write `island_voxel_generator.gd`**

Create `C:\Users\whann\Documents\mine-co\scripts\island_voxel_generator.gd`:

```gdscript
extends VoxelGeneratorScript
class_name IslandVoxelGenerator

# --- Tunables (editable on the .tres in inspector) ---

@export var seed: int = 0
@export var size: float = 300.0          # island diameter (square footprint, centered)
@export var max_height: float = 18.0
@export var water_level: float = 0.0     # used only by edge_bias math; visible water plane is in scene

@export_group("Noise")
@export var noise_frequency: float = 0.008
@export var noise_octaves: int = 4
@export var noise_lacunarity: float = 2.0
@export var noise_gain: float = 0.5

@export_group("Falloff (radial smoothstep, fractions of size/2)")
@export var falloff_inner: float = 0.45
@export var falloff_outer: float = 0.95
@export var edge_bias: float = 5.0       # pushes outer ring underwater

# --- Derived ---

const VOXEL_SIZE: float = 1.0   # plain VoxelTerrain @ LOD0

var _noise: FastNoiseLite

func _init() -> void:
	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.seed = seed
	_noise.frequency = noise_frequency
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = noise_octaves
	_noise.fractal_lacunarity = noise_lacunarity
	_noise.fractal_gain = noise_gain

# --- Math helpers ---

func _radial_falloff(world_x: float, world_z: float) -> float:
	var d: float = sqrt(world_x * world_x + world_z * world_z)
	var t: float = d / (size * 0.5)
	# 1.0 at center → 0.0 outside falloff_outer
	return 1.0 - smoothstep(falloff_inner, falloff_outer, t)

func _height(world_x: float, world_z: float) -> float:
	var n: float = _noise.get_noise_2d(world_x, world_z)         # [-1, 1]
	n = (n + 1.0) * 0.5                                          # [0, 1]
	return n * max_height * _radial_falloff(world_x, world_z) - edge_bias

# --- Generator ---

func _generate_block(out_buffer: VoxelBuffer, origin_in_voxels: Vector3i, lod: int) -> void:
	# Configure SDF channel as 32-bit float (avoid default 16-bit fixed-point clipping at large magnitudes).
	out_buffer.set_channel_depth(VoxelBuffer.CHANNEL_SDF, VoxelBuffer.DEPTH_32_BIT)

	var bsize: Vector3i = out_buffer.get_size()
	var step: float = float(1 << lod) * VOXEL_SIZE
	var origin_world: Vector3 = Vector3(origin_in_voxels) * VOXEL_SIZE

	# Block's world Y span
	var block_y_min: float = origin_world.y
	var block_y_max: float = origin_world.y + float(bsize.y) * step

	# --- Fast paths ---
	if block_y_min >= max_height:
		# Fully above any possible terrain → all air. Use a large positive value to avoid edge clipping.
		out_buffer.fill_f(10.0, VoxelBuffer.CHANNEL_SDF)
		return
	if block_y_max <= -edge_bias - 1.0:
		# Fully below any possible terrain → all solid (seabed). Large negative value.
		out_buffer.fill_f(-10.0, VoxelBuffer.CHANNEL_SDF)
		return

	# --- Surface band: per-voxel sample ---
	for z in range(bsize.z):
		var world_z: float = origin_world.z + float(z) * step
		for x in range(bsize.x):
			var world_x: float = origin_world.x + float(x) * step
			var h: float = _height(world_x, world_z)
			for y in range(bsize.y):
				var world_y: float = origin_world.y + float(y) * step
				var sdf: float = world_y - h
				out_buffer.set_voxel_f(sdf, x, y, z, VoxelBuffer.CHANNEL_SDF)
```

- [ ] **Step 2: Force the editor to parse the script**

Reading the file with `script_manage op=read` returns text but does not invoke the parser. To force a parse, instruct the editor to reimport / refresh the filesystem and then check logs:

```
mcp__godot-ai__filesystem_manage op="reimport" params={"path": "res://scripts/island_voxel_generator.gd"}
mcp__godot-ai__logs_read
```

Expected: no GDScript parse errors mentioning `island_voxel_generator.gd`. If the reimport op isn't supported for `.gd`, instead temporarily attach the script to a node in any open scene (or open the script in the editor via `script_manage`) — that forces a parse.

- [ ] **Step 3: Create `island_generator.tres`**

Write the `.tres` file directly at `C:\Users\whann\Documents\mine-co\scenes\island_generator.tres`:

```
[gd_resource type="Resource" script_class="IslandVoxelGenerator" load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/island_voxel_generator.gd" id="1_gen"]

[resource]
script = ExtResource("1_gen")
seed = 0
size = 300.0
max_height = 18.0
water_level = 0.0
noise_frequency = 0.008
noise_octaves = 4
noise_lacunarity = 2.0
noise_gain = 0.5
falloff_inner = 0.45
falloff_outer = 0.95
edge_bias = 5.0
```

> **Note:** `script_class` must match the `class_name` in the script (`IslandVoxelGenerator`). If Godot 4.6 rejects this format, drop the `script_class` attribute and rely on the script ExtResource alone.

- [ ] **Step 4: Verify the resource loads**

```
mcp__godot-ai__resource_manage op="get" params={"path": "res://scenes/island_generator.tres"}
```

(If the rollup name is different, read it back via `filesystem_manage op="read_text"`.)

Expected: resource loads without error, exports visible.

- [ ] **Step 5 (optional): Commit**

```bash
git add scripts/island_voxel_generator.gd scenes/island_generator.tres
git commit -m "feat: island voxel generator (noise + radial falloff + biome channels)"
```

---

### Task 4: `main.tscn` shell with VoxelTerrain + biome shader

**Files:**
- Create: `res://scenes/main.tscn`
- Create: `res://scenes/world_y_biome.gdshader`
- Create: `res://scenes/terrain_material.tres`

**Goal:** A minimal main scene with sky, sun, and `VoxelTerrain` rendering our island with sand/grass coloring driven by a world-Y shader. No water, no player yet — confirm the terrain renders correctly and the shape looks like an island.

- [ ] **Step 1: Create `main.tscn` with root + sky + sun + temp camera**

Use godot-ai MCP scene/node tools. Sequence:

```
mcp__godot-ai__scene_manage op="create" params={"path": "res://scenes/main.tscn", "root_type": "Node3D", "root_name": "Main"}
mcp__godot-ai__scene_open params={"path": "res://scenes/main.tscn"}

# WorldEnvironment with procedural sky
mcp__godot-ai__node_create params={"parent": "/root/Main", "type": "WorldEnvironment", "name": "WorldEnvironment"}
# (We'll set the Environment resource via node_set_property below)

# DirectionalLight3D
mcp__godot-ai__node_create params={"parent": "/root/Main", "type": "DirectionalLight3D", "name": "Sun"}
mcp__godot-ai__node_set_property params={"node_path": "/root/Main/Sun", "property": "rotation_degrees", "value": [-45, -30, 0]}
mcp__godot-ai__node_set_property params={"node_path": "/root/Main/Sun", "property": "shadow_enabled", "value": true}
mcp__godot-ai__node_set_property params={"node_path": "/root/Main/Sun", "property": "light_color", "value": [1.0, 0.96, 0.88, 1.0]}

# VoxelTerrain
mcp__godot-ai__node_create params={"parent": "/root/Main", "type": "VoxelTerrain", "name": "VoxelTerrain"}

# Temporary inspection camera up high
mcp__godot-ai__node_create params={"parent": "/root/Main", "type": "Camera3D", "name": "TempCam"}
mcp__godot-ai__node_set_property params={"node_path": "/root/Main/TempCam", "property": "position", "value": [0, 80, 220]}
mcp__godot-ai__node_set_property params={"node_path": "/root/Main/TempCam", "property": "rotation_degrees", "value": [-15, 0, 0]}
mcp__godot-ai__node_set_property params={"node_path": "/root/Main/TempCam", "property": "current", "value": true}

mcp__godot-ai__scene_save
```

- [ ] **Step 2: Configure the WorldEnvironment (inspector path is primary)**

This is one place where the inspector is faster than chaining MCP calls. Open the editor (it should already be open):

1. Select the `WorldEnvironment` node in the Main scene tree.
2. In the inspector, click on `Environment` and choose **New Environment**.
3. On the new Environment resource: set `Background → Mode` to **Sky**.
4. Click `Sky` and choose **New Sky**.
5. On the Sky resource: click `Sky Material` and choose **New ProceduralSkyMaterial**. (Defaults are fine.)
6. Back on the Environment: under `Ambient Light`, set `Source` to **Sky** and `Energy` to `0.3`.
7. Save the scene.

Expected: when the scene runs, you see a blue sky, not a black void.

If you'd rather automate this, the MCP equivalent involves creating each subresource and assigning sub-properties — viable but verbose. The inspector path is recommended.

- [ ] **Step 3: Configure the VoxelTerrain**

```
mcp__godot-ai__node_set_property params={"node_path": "/root/Main/VoxelTerrain", "property": "generate_collisions", "value": true}
mcp__godot-ai__node_set_property params={"node_path": "/root/Main/VoxelTerrain", "property": "bounds", "value": {"position": [-200, -100, -200], "size": [400, 200, 400]}}
```

> **Bounds fallback:** if the MCP rejects the AABB literal as `{position, size}`, alternative shapes to try: `[[-200,-100,-200],[400,200,400]]`, or set in two steps via separate sub-property paths. If all MCP attempts fail, set `Bounds` in the inspector — it's two Vector3 fields.

Set the mesher and generator. These are sub-resources, so they may need to be assigned via the editor inspector or via two-step resource creation:

```
# Create a VoxelMesherTransvoxel resource and assign
mcp__godot-ai__resource_manage op="create" params={"path": "res://scenes/_mesher.tres", "type": "VoxelMesherTransvoxel"}
mcp__godot-ai__node_set_property params={"node_path": "/root/Main/VoxelTerrain", "property": "mesher", "value": "res://scenes/_mesher.tres"}

# Assign our generator resource
mcp__godot-ai__node_set_property params={"node_path": "/root/Main/VoxelTerrain", "property": "generator", "value": "res://scenes/island_generator.tres"}
```

> If MCP cannot assign sub-resources by path, instruct the user to do it in the inspector, then continue.

- [ ] **Step 4: Create the world-Y biome shader**

Write `C:\Users\whann\Documents\mine-co\scenes\world_y_biome.gdshader`:

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

- [ ] **Step 5: Create the terrain ShaderMaterial and assign**

Write `C:\Users\whann\Documents\mine-co\scenes\terrain_material.tres`:

```
[gd_resource type="ShaderMaterial" load_steps=2 format=3]

[ext_resource type="Shader" path="res://scenes/world_y_biome.gdshader" id="1_shader"]

[resource]
shader = ExtResource("1_shader")
shader_parameter/water_level = 0.0
shader_parameter/sand_band = 1.2
shader_parameter/sand_color = Color(0.92, 0.85, 0.65, 1)
shader_parameter/grass_color = Color(0.35, 0.55, 0.25, 1)
```

Assign to the terrain:

```
mcp__godot-ai__node_set_property params={"node_path": "/root/Main/VoxelTerrain", "property": "material_override", "value": "res://scenes/terrain_material.tres"}
mcp__godot-ai__scene_save
```

- [ ] **Step 6: Run the scene and validate**

```
mcp__godot-ai__project_run
# Wait a couple of seconds for chunks to mesh, then capture
mcp__godot-ai__editor_screenshot
```

Expected:
- An island shape (roughly circular, ~300m wide) is visible from the temp camera at `(0, 80, 220)`.
- The terrain has visible biome coloring: tan/sand near y=0 (the shoreline ring), green on top (grass).
- Surface is smooth (Transvoxel), not blocky.

If terrain renders but colors look wrong (e.g., all sand or all grass everywhere), tune `sand_band` on the material — bigger value = wider sand-to-grass blend zone.

If terrain doesn't render at all (sky only): check logs for Voxel Tools errors via `mcp__godot-ai__logs_read`. Likely a generator or mesher binding issue. Surface to user before improvising.

- [ ] **Step 7 (optional): Commit**

```bash
git add scenes/main.tscn scenes/_mesher.tres scenes/world_y_biome.gdshader scenes/terrain_material.tres
git commit -m "feat: main scene with voxel terrain and world-Y biome shader"
```

---

### Task 5: Water plane + final lighting tune

**Files:**
- Modify: `res://scenes/main.tscn`

**Goal:** Translucent water at y=0, sky/light tuned to read as outdoor daylight.

- [ ] **Step 1: Add the water plane**

```
mcp__godot-ai__node_create params={"parent": "/root/Main", "type": "MeshInstance3D", "name": "Water"}
# Create PlaneMesh as the mesh
mcp__godot-ai__resource_manage op="create" params={"path": "res://scenes/_water_mesh.tres", "type": "PlaneMesh", "props": {"size": [400, 400]}}
mcp__godot-ai__node_set_property params={"node_path": "/root/Main/Water", "property": "mesh", "value": "res://scenes/_water_mesh.tres"}
# Translucent blue material
mcp__godot-ai__resource_manage op="create" params={"path": "res://scenes/_water_mat.tres", "type": "StandardMaterial3D", "props": {"albedo_color": [0.2, 0.45, 0.65, 0.7], "transparency": 1, "metallic": 0.1, "roughness": 0.2}}
mcp__godot-ai__node_set_property params={"node_path": "/root/Main/Water", "property": "material_override", "value": "res://scenes/_water_mat.tres"}
mcp__godot-ai__scene_save
```

> `transparency: 1` corresponds to `BaseMaterial3D.TRANSPARENCY_ALPHA` in Godot 4.

- [ ] **Step 2: Run, screenshot, validate**

Expected: Water plane visible at y=0. The sand band of the island sits at the waterline. Above water = grass-colored hills, below = water surface (and you should NOT see voids past the water — the voxel terrain extends to ±200, the water to ±200).

- [ ] **Step 3 (optional): Commit**

```bash
git add scenes/main.tscn scenes/_water_mesh.tres scenes/_water_mat.tres
git commit -m "feat: water plane and lighting tune"
```

---

### Task 6: Player scene + script (independently testable)

**Files:**
- Create: `res://scripts/player.gd`
- Create: `res://scenes/player.tscn`

**Goal:** A first-person `CharacterBody3D` with WASD movement, mouse look, and jump. Tested standalone before integration.

- [ ] **Step 1: Write `player.gd`**

Create `C:\Users\whann\Documents\mine-co\scripts\player.gd`:

```gdscript
extends CharacterBody3D

const SPEED: float = 5.0
const JUMP_VELOCITY: float = 5.0
const MOUSE_SENSITIVITY: float = 0.002
const PITCH_LIMIT: float = deg_to_rad(89.0)

@onready var _camera: Camera3D = $Camera3D

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		_camera.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		_camera.rotation.x = clamp(_camera.rotation.x, -PITCH_LIMIT, PITCH_LIMIT)
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	# Gravity
	if not is_on_floor():
		velocity.y -= _gravity * delta

	# Jump
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Horizontal movement
	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction: Vector3 = (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	if direction != Vector3.ZERO:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0.0, SPEED)
		velocity.z = move_toward(velocity.z, 0.0, SPEED)

	move_and_slide()
```

- [ ] **Step 2: Build `player.tscn`**

```
mcp__godot-ai__scene_manage op="create" params={"path": "res://scenes/player.tscn", "root_type": "CharacterBody3D", "root_name": "Player"}
mcp__godot-ai__scene_open params={"path": "res://scenes/player.tscn"}
mcp__godot-ai__script_attach params={"node_path": "/root/Player", "script_path": "res://scripts/player.gd"}

# CollisionShape3D with CapsuleShape (Godot 4 height = full end-to-end including hemispheres)
mcp__godot-ai__node_create params={"parent": "/root/Player", "type": "CollisionShape3D", "name": "CollisionShape3D"}
mcp__godot-ai__resource_manage op="create" params={"path": "res://scenes/_player_capsule.tres", "type": "CapsuleShape3D", "props": {"height": 1.8, "radius": 0.4}}
mcp__godot-ai__node_set_property params={"node_path": "/root/Player/CollisionShape3D", "property": "shape", "value": "res://scenes/_player_capsule.tres"}
# Capsule is centered on body origin: feet at body origin -0.9, head at body origin +0.9.
# Player nodes are placed at world-space spawn coordinates (e.g., y=30) and free-fall onto terrain.
# Do NOT add a +0.9 offset to the body origin; the capsule center IS the player origin.

# Camera at head height (0.7 above body origin = ~1.6m above feet)
mcp__godot-ai__node_create params={"parent": "/root/Player", "type": "Camera3D", "name": "Camera3D"}
mcp__godot-ai__node_set_property params={"node_path": "/root/Player/Camera3D", "property": "position", "value": [0, 0.7, 0]}

mcp__godot-ai__scene_save
```

- [ ] **Step 3: Quick standalone test scene**

Create `res://scenes/_player_test.tscn` with a Node3D root, a StaticBody3D + BoxShape3D (1000×1×1000 for a floor), a directional light, and the player instance at `(0, 5, 0)`. Set as temporary main scene, run.

```
mcp__godot-ai__project_run params={"scene": "res://scenes/_player_test.tscn"}
```

- [ ] **Step 4: VALIDATION — verify player controls feel correct**

Manually drive the player:
- WASD moves in the camera's facing direction (W = forward, A = strafe left, etc.).
- Mouse moves look direction (no inversion).
- Jump on space, lands cleanly.
- Esc releases mouse, Esc again recaptures.

Expected: movement is smooth, no stuck-in-air bug, no infinite-fall.

- [ ] **Step 5: Cleanup test scene**

```powershell
Remove-Item "C:\Users\whann\Documents\mine-co\scenes\_player_test.tscn"
Remove-Item "C:\Users\whann\Documents\mine-co\scenes\_player_test.tscn.import" -ErrorAction SilentlyContinue
```

- [ ] **Step 6 (optional): Commit**

```bash
git add scripts/player.gd scenes/player.tscn scenes/_player_capsule.tres
git commit -m "feat: first-person CharacterBody3D player controller"
```

---

### Task 7: Wire player into main scene with spawn safety

**Files:**
- Create: `res://scripts/spawn_gate.gd`
- Modify: `res://scenes/main.tscn`

**Goal:** Player spawns above the island and only starts physics processing once the chunk under them has meshed (so they don't fall through unloaded chunks). Remove the temp camera.

- [ ] **Step 1: Write `spawn_gate.gd`**

Two correctness notes baked into this script:
- **Callable bind + disconnect bug:** every `Callable.bind(...)` returns a NEW Callable, so `disconnect(callable.bind(x))` never matches `connect(callable.bind(x))`. We use `CONNECT_ONE_SHOT` instead, which auto-disconnects after the first fire.
- **Mesh block size source:** read `mesh_block_size` (the property the signal's coordinates are in), not `get_data_block_size()` — those can differ.

Create `C:\Users\whann\Documents\mine-co\scripts\spawn_gate.gd`:

```gdscript
extends Node

@export var voxel_terrain: NodePath
@export var player: NodePath

var _terrain: VoxelTerrain
var _player: CharacterBody3D

func _ready() -> void:
	_player = get_node(player) as CharacterBody3D
	_terrain = get_node(voxel_terrain) as VoxelTerrain
	if _player == null or _terrain == null:
		push_error("SpawnGate: voxel_terrain or player path is invalid")
		return
	# Freeze player physics until the chunk under spawn has meshed
	_player.set_physics_process(false)
	# Connect with CONNECT_ONE_SHOT so we do not need to disconnect a bound callable.
	# Signal arg: Vector3i mesh_block_position (in mesh-block coords).
	_terrain.mesh_block_entered.connect(_on_mesh_block_entered, CONNECT_ONE_SHOT)
	# Safety: also gate by raycast in case the signal does not match exactly (see Step 4).

func _on_mesh_block_entered(mesh_block_pos: Vector3i) -> void:
	# Mesh block coords are in units of mesh_block_size (default 16 voxels).
	var block_size_v: int = _terrain.mesh_block_size
	var px: int = int(floor(_player.global_position.x / float(block_size_v)))
	var pz: int = int(floor(_player.global_position.z / float(block_size_v)))
	if mesh_block_pos.x == px and mesh_block_pos.z == pz:
		_player.set_physics_process(true)
	else:
		# Wrong chunk fired first — re-arm for next chunk.
		_terrain.mesh_block_entered.connect(_on_mesh_block_entered, CONNECT_ONE_SHOT)
```

> **API drift note:** `mesh_block_size` may be exposed as a method (`get_mesh_block_size()`) or property depending on Voxel Tools version. If the property access errors, swap to method form. The `mesh_block_entered` signal's argument shape (single `Vector3i` vs Dictionary) may also vary — if logs show a signature mismatch, adapt the parameter list. The CONNECT_ONE_SHOT pattern stays the same.

- [ ] **Step 2: Instance the player into `main.tscn`**

`node_create` does not accept an "instance" type — instancing a `PackedScene` is a separate concern. Try the godot-ai MCP's scene-instancing op first:

```
mcp__godot-ai__scene_open params={"path": "res://scenes/main.tscn"}
mcp__godot-ai__scene_manage op="instantiate" params={"scene": "res://scenes/player.tscn", "parent": "/root/Main", "name": "Player"}
```

If that op doesn't exist on this MCP build, the fallback is to hand-edit `res://scenes/main.tscn` to add a `[node ... instance=ExtResource("player")]` entry. Concretely, append before the closing of the scene file:

```
[ext_resource type="PackedScene" path="res://scenes/player.tscn" id="player_inst"]

[node name="Player" parent="." instance=ExtResource("player_inst")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 30, 0)
```

(Adjust the `[ext_resource]` block to merge with existing ones if any. The `transform` line places the player at `(0, 30, 0)`.)

If neither path works, escalate to user — opening the scene in the editor and dragging `player.tscn` onto the Main node from the FileSystem dock takes 5 seconds and is failsafe.

Then set position via MCP:

```
mcp__godot-ai__node_set_property params={"node_path": "/root/Main/Player", "property": "position", "value": [0, 30, 0]}
```

- [ ] **Step 3: Add the SpawnGate node**

```
mcp__godot-ai__node_create params={"parent": "/root/Main", "type": "Node", "name": "SpawnGate"}
mcp__godot-ai__script_attach params={"node_path": "/root/Main/SpawnGate", "script_path": "res://scripts/spawn_gate.gd"}
mcp__godot-ai__node_set_property params={"node_path": "/root/Main/SpawnGate", "property": "voxel_terrain", "value": "../VoxelTerrain"}
mcp__godot-ai__node_set_property params={"node_path": "/root/Main/SpawnGate", "property": "player", "value": "../Player"}
```

- [ ] **Step 4: Remove the temp camera**

```
mcp__godot-ai__node_manage op="delete" params={"node_path": "/root/Main/TempCam"}
mcp__godot-ai__scene_save
```

- [ ] **Step 5: Run main scene and validate the integration**

```
mcp__godot-ai__project_run
```

Expected:
- Sky visible.
- Briefly hangs / shows white before chunks mesh, then terrain pops in (chunk-by-chunk is OK).
- Player drops, lands within ~2 seconds.
- No "fell through world to y=-∞" bug (catch this by checking logs or by waiting 5 seconds — if the camera shows water from below or pure void, the spawn gate didn't fire correctly).
- WASD walks across the surface.
- Walking into the shoreline shows the sand→grass transition up close.
- Walking into water keeps the player on the seabed (no swimming for v1; player just stays on solid voxel).
- Jump works.

- [ ] **Step 6: If spawn gate misfires, switch to raycast fallback**

If logs show the player falling through (player Y rapidly drops below `-100`), the signal-driven gate isn't firing for the right chunk. Replace `_ready` and remove `_on_mesh_block_entered`; use a per-frame raycast instead:

```gdscript
extends Node

@export var voxel_terrain: NodePath
@export var player: NodePath

var _player: CharacterBody3D
var _terrain: VoxelTerrain
var _enabled: bool = false

func _ready() -> void:
	_player = get_node(player) as CharacterBody3D
	_terrain = get_node(voxel_terrain) as VoxelTerrain
	_player.set_physics_process(false)

func _process(_delta: float) -> void:
	if _enabled:
		return
	var space: PhysicsDirectSpaceState3D = _player.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		Vector3(_player.global_position.x, 100.0, _player.global_position.z),
		Vector3(_player.global_position.x, -50.0, _player.global_position.z)
	)
	var hit := space.intersect_ray(query)
	if not hit.is_empty():
		_player.set_physics_process(true)
		_enabled = true
		set_process(false)
```

Re-run. Validate again.

- [ ] **Step 7 (optional): Commit**

```bash
git add scripts/spawn_gate.gd scenes/main.tscn
git commit -m "feat: wire player into main scene with chunk-aware spawn safety"
```

---

### Task 8: Walkthrough and parameter tuning

**Files:**
- Modify (potentially): `res://scenes/island_generator.tres`, `res://scenes/main.tscn`

**Goal:** Walk the island. Note any issues. Tune. Confirm success criteria.

- [ ] **Step 1: Walk the perimeter and the high points**

Run `main.tscn`. Walk around for 2–3 minutes:
- Start, walk to the shoreline. Confirm sand band is visible and the slope is gentle enough to not trap the player.
- Walk up to the highest hill. Confirm grass color, smooth shading.
- Walk into the water. Confirm the player ends up on the seabed (or is locked at water surface — either is acceptable for v1; document which).
- Try to walk off the edge of the voxel bounds (±200). Confirm the player can't fall into a void.

- [ ] **Step 2: Tune parameters as needed**

Common tunings (edit `island_generator.tres`, save, re-run):
- Island feels too small/flat → raise `max_height` to 25.
- Beach band too narrow → raise `sand_band` to 2.0.
- Edges still poking above water → raise `edge_bias` to 8.0.
- Hills too noisy → drop `noise_octaves` to 3.
- Hills too uniform → bump `noise_lacunarity` to 2.4 and `noise_gain` to 0.55.
- FPS chugs → shrink `bounds` y-range to `[-50, 50]`.

- [ ] **Step 3: Verify success criteria**

From spec:
- [ ] Open `main.tscn`, press F5, fall onto an island. ✓
- [ ] Walk with WASD, look with mouse, jump with space, release mouse with Esc. ✓
- [ ] Visible water/sand/grass biome bands as height increases from the shoreline. ✓
- [ ] Terrain reads as a smooth low-poly island, not heightmap-with-cliffs or Minecraft-blocky. ✓
- [ ] No frame drops while walking the perimeter. ✓

- [ ] **Step 4 (optional): Commit final tunings**

```bash
git add scenes/island_generator.tres scenes/main.tscn
git commit -m "feat: tune island generation parameters after playtest"
```

- [ ] **Step 5: Mark v1 complete**

Report to user: scenes/scripts created, what works, any issues found and parked, what the natural next steps are (mining, persistence, foliage).

---

## Notes for the implementer

- **MCP tool names** in this plan use the `mcp__godot-ai__<tool>` form. The exact tool name surface and parameter shape may differ slightly from what's pinned here; treat the calls as intent specifications and adapt to the actual tool schema you're given.
- **The validation gate at Task 4 Step 6** is the most likely point of unexpected work. If the StandardMaterial path doesn't show vertex colors, falling back to ShaderMaterial is described in-place — do that without escalating.
- **Voxel Tools API drift:** the addon's GDExtension build is "not extensively tested" per the maintainer. If you hit a missing API or a runtime crash inside `godot_voxel`, capture the error and surface to user before trying workarounds — could mean swapping to the precompiled custom Godot binary.
- **Don't add features not in the spec.** No trees, sprint, headbob, footstep audio, water shaders. v1 is "walk around an island."
