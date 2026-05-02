# Graphics Pass Round 2 (Decoration) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Populate the island with grass, rocks, and trees from the Kenney Nature Kit (CC0) using Voxel Tools' built-in `VoxelInstancer` for chunked-streaming scatter, harmonized to the R1 hazy palette via a small tint shader.

**Architecture:** User manually downloads the Kenney pack zip; PowerShell extracts five specific `.glb` files into `res://assets/nature/`. A one-shot editor tool script extracts each `.glb`'s `Mesh` resource to a `.mesh.tres` file (so the library can reference meshes by stable path). A single `VoxelInstanceLibrary` resource contains five items, each with a per-item `ShaderMaterial` (using one shared `nature_tint.gdshader` with a `base_color` uniform) and a per-item `VoxelInstanceGenerator` sub-resource holding density / slope / height filters. A `VoxelInstancer` node added under `/Main/VoxelTerrain` references the library and streams instances per chunk.

**Tech Stack:** Godot 4.6 module build (custom binary at `C:\Users\whann\Tools\godot-voxel-1.6\godot.windows.editor.x86_64.exe`), GDScript, GLSL (Godot 4 spatial shader). Uses `VoxelInstancer`, `VoxelInstanceLibrary`, `VoxelInstanceLibraryMultiMeshItem`, `VoxelInstanceGenerator` from Voxel Tools 1.6.

**Spec:** `docs/superpowers/specs/2026-05-01-graphics-pass-r2-decoration-design.md`

**Project root:** `C:\Users\whann\Documents\mine-co\` (Windows). All `res://` paths resolve under this root.

---

## Validation philosophy

Each task has an in-editor or runtime visual check via `mcp__godot-ai__project_run` (with `autosave: false`) + `editor_screenshot source="game"`. Wait at least 8 seconds after `project_run` for chunks to mesh and the player spawn-gate's raycast to fire — the previous round's subagent learned a 5s wait was insufficient on this build. No unit tests; this is scene/resource configuration plus one shader.

When the editor is in play mode, MCP file-system operations error with `EDITOR_NOT_READY`. Always `project_manage op="stop"` before edits, then re-run for verification.

---

## File structure (final state)

```
res://
  assets/nature/
    grass_tuft.glb              — NEW (Kenney)
    grass_tuft.mesh.tres        — NEW (extracted Mesh)
    grass_tuft_mat.tres         — NEW (per-item ShaderMaterial)
    rock_small.glb              — NEW
    rock_small.mesh.tres        — NEW
    rock_small_mat.tres         — NEW
    rock_medium.glb             — NEW
    rock_medium.mesh.tres       — NEW
    rock_medium_mat.tres        — NEW
    tree_pine.glb               — NEW
    tree_pine.mesh.tres         — NEW
    tree_pine_mat.tres          — NEW
    tree_oak.glb                — NEW
    tree_oak.mesh.tres          — NEW
    tree_oak_mat.tres           — NEW
  scenes/
    main.tscn                   — modified: add VoxelInstancer node under VoxelTerrain
    nature_library.tres         — NEW: VoxelInstanceLibrary with 5 entries
  shaders/
    nature_tint.gdshader        — NEW (top-level shaders/ folder created this round)
  scripts/
    extract_meshes.gd           — NEW (one-shot @tool EditorScript; deleted after use)
```

`scripts/extract_meshes.gd` is a transient tool — created in T2, run once, deleted. Doesn't ship.

## Task dependency graph

```
T1 (pack files in place) ─> T2 (mesh.tres extracted) ─┐
T3 (tint shader) ─> T4 (per-item materials) ─────────┤
                                                       └─> T5 (library) ─> T6 (instancer in scene) ─> T7 (walkthrough)
```

T3 and T1 are independent and can run in parallel; T4 needs T3 done. The implementer should do T1+T3 first since each is self-contained, then T2, T4, T5, T6, T7 in order.

---

### Task 1: Acquire and extract the Kenney pack

**Files (created):**
- `res://assets/nature/grass_tuft.glb`
- `res://assets/nature/rock_small.glb`
- `res://assets/nature/rock_medium.glb`
- `res://assets/nature/tree_pine.glb`
- `res://assets/nature/tree_oak.glb`

**Goal:** Five `.glb` files (mesh + bundled material) imported into the project. We don't pick which specific Kenney files at plan-write time — the implementer eyeballs the unzipped pack and picks reasonable ones.

- [ ] **Step 1: Ask the user to download the Kenney Nature Kit zip**

Tell the user:
> "Please download Kenney Nature Kit from https://kenney.nl/assets/nature-kit (click the orange Download button). Save the zip to `C:\Users\whann\Downloads\` (or anywhere). Tell me the path when done."

Wait for their reply with the zip path. Don't try direct PowerShell download — Kenney's URLs aren't stable and 403 on programmatic requests.

- [ ] **Step 2: Extract the zip and inspect the layout**

Once the user provides the zip path (e.g., `C:\Users\whann\Downloads\kenney_nature-kit.zip`):

```powershell
$zipPath = "<USER-PROVIDED PATH>"
$tmp = Join-Path $env:TEMP "kenney_nature_extract"
if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
Expand-Archive -Path $zipPath -DestinationPath $tmp -Force
Get-ChildItem -Path $tmp -Filter "*.glb" -Recurse | Select-Object Name, Directory | Format-Table -AutoSize
```

Expected: dozens of `.glb` files listed across subfolders (typically a `Models/GLB format/` folder). Note the directory; in Kenney's recent packs it's usually `kenney_nature-kit/Models/GLB format/`.

- [ ] **Step 3: Pick five specific files**

From the listing, pick:
- a single grass tuft (something like `grass.glb`, `grass_long.glb`, or `plant_bushDetailed.glb`)
- two rocks of different sizes (e.g., `stone_smallA.glb`, `stone_largeA.glb`)
- a pine-style tree (e.g., `tree_pineDefaultA.glb`, `tree_pineSmall.glb`)
- a deciduous tree (e.g., `tree_default.glb`, `tree_oak.glb`)

Don't agonize — the spec calls for "single grass / two rocks / two trees" and any reasonable picks work. We can swap individual files later by re-running this task with a different choice.

- [ ] **Step 4: Copy to the project**

Replace the source filenames below with what you picked in Step 3:

```powershell
$src = "C:\Users\whann\AppData\Local\Temp\kenney_nature_extract\<subfolder with .glb files>"
$dst = "C:\Users\whann\Documents\mine-co\assets\nature"
New-Item -ItemType Directory -Path $dst -Force | Out-Null
Copy-Item -Path (Join-Path $src "grass.glb") -Destination (Join-Path $dst "grass_tuft.glb") -Force
Copy-Item -Path (Join-Path $src "stone_smallA.glb") -Destination (Join-Path $dst "rock_small.glb") -Force
Copy-Item -Path (Join-Path $src "stone_largeA.glb") -Destination (Join-Path $dst "rock_medium.glb") -Force
Copy-Item -Path (Join-Path $src "tree_pineDefaultA.glb") -Destination (Join-Path $dst "tree_pine.glb") -Force
Copy-Item -Path (Join-Path $src "tree_default.glb") -Destination (Join-Path $dst "tree_oak.glb") -Force
Get-ChildItem -Path $dst | Select-Object Name | Out-String
```

Expected: 5 files listed.

- [ ] **Step 5: Trigger Godot to import the .glb files**

```
mcp__godot-ai__filesystem_manage op="reimport" params={"paths": ["res://assets/nature/grass_tuft.glb", "res://assets/nature/rock_small.glb", "res://assets/nature/rock_medium.glb", "res://assets/nature/tree_pine.glb", "res://assets/nature/tree_oak.glb"]}
mcp__godot-ai__logs_read source="editor"
```

Expected: no import errors. Godot creates `.import` cache files alongside each `.glb` automatically.

- [ ] **Step 6 (optional): Commit**

```bash
git add assets/nature
git commit -m "feat(graphics-r2): import Kenney Nature Kit subset"
```

---

### Task 2: Extract Mesh resources from .glb files

**Files (created):**
- `res://scripts/extract_meshes.gd` — transient @tool EditorScript
- `res://assets/nature/grass_tuft.mesh.tres`
- `res://assets/nature/rock_small.mesh.tres`
- `res://assets/nature/rock_medium.mesh.tres`
- `res://assets/nature/tree_pine.mesh.tres`
- `res://assets/nature/tree_oak.mesh.tres`

**Goal:** Each `.glb` is a `PackedScene`. The actual `Mesh` resource lives inside a `MeshInstance3D` child. We pull each Mesh out and save as a `.mesh.tres` so the library item can reference it via a stable resource path.

- [ ] **Step 1: Write the extraction tool script**

**Important:** `.glb` imports produce `ImporterMesh` resources, not `ArrayMesh`. `ImporterMesh` is the import-time intermediary — `VoxelInstanceLibraryMultiMeshItem.mesh` (typed `Mesh`) won't accept it directly in a way that survives serialization. We convert via `ImporterMesh.get_mesh()` before saving.

Create `C:\Users\whann\Documents\mine-co\scripts\extract_meshes.gd`:

```gdscript
@tool
extends EditorScript

const ASSETS := [
	"grass_tuft",
	"rock_small",
	"rock_medium",
	"tree_pine",
	"tree_oak",
]

func _run() -> void:
	for name in ASSETS:
		var glb_path := "res://assets/nature/%s.glb" % name
		var out_path := "res://assets/nature/%s.mesh.tres" % name
		var packed: PackedScene = load(glb_path) as PackedScene
		if packed == null:
			push_error("Could not load %s" % glb_path)
			continue
		var inst: Node = packed.instantiate()
		var mi: MeshInstance3D = _find_first_mesh_instance(inst)
		if mi == null:
			push_error("No MeshInstance3D in %s" % glb_path)
			inst.queue_free()
			continue
		print("Picked MeshInstance3D at %s for %s" % [mi.get_path(), name])
		var mesh = mi.mesh
		if mesh == null:
			push_error("MeshInstance3D in %s has null mesh" % glb_path)
			inst.queue_free()
			continue
		# Convert ImporterMesh → ArrayMesh if needed (Godot 4 .glb default)
		if mesh is ImporterMesh:
			mesh = (mesh as ImporterMesh).get_mesh()
		if not (mesh is Mesh):
			push_error("Could not extract a usable Mesh from %s (got %s)" % [glb_path, mesh.get_class()])
			inst.queue_free()
			continue
		var err := ResourceSaver.save(mesh, out_path)
		if err != OK:
			push_error("Failed to save %s: error %d" % [out_path, err])
		else:
			print("Saved %s (type=%s)" % [out_path, mesh.get_class()])
		inst.queue_free()

func _find_first_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var found := _find_first_mesh_instance(child)
		if found != null:
			return found
	return null
```

> Note: the `print("Picked MeshInstance3D at ...")` line tells the implementer which sub-node was selected per asset. Some Kenney .glbs have multiple MeshInstance3D nodes (e.g., trunk + foliage as separate surfaces); the script picks the first found via depth-first traversal. If the wrong one is picked for a tree (e.g., just the trunk), the implementer can swap the asset for a different .glb in T1 or hand-edit this script to filter by name.

- [ ] **Step 2: Reimport so the editor sees the script**

```
mcp__godot-ai__filesystem_manage op="reimport" params={"paths": ["res://scripts/extract_meshes.gd"]}
```

- [ ] **Step 3: Run the tool script**

Ask the user to run it (the MCP doesn't have a known-real "run EditorScript" op; the canonical Godot path is keybind):
> "Please open `scripts/extract_meshes.gd` in Godot's script editor and press **Ctrl+Shift+X** (File → Run). It'll print one line per asset to the editor's Output panel. Tell me when done."

Wait for confirmation, then proceed.

- [ ] **Step 4: Verify all 5 .mesh.tres files exist**

```powershell
Get-ChildItem -Path "C:\Users\whann\Documents\mine-co\assets\nature" -Filter "*.mesh.tres" | Select-Object Name | Out-String
```

Expected: 5 files. If fewer, check editor logs (`mcp__godot-ai__logs_read source="editor"`) for `push_error` output from the script — typical issue is the .glb's first MeshInstance3D being inside a deeper-nested scene tree (the script handles recursion, but if the .glb has zero MeshInstance3D nodes, the asset structure is unusual and that file needs hand-handling).

- [ ] **Step 5: Verify each .mesh.tres loads as ArrayMesh (post-conversion)**

For a quick check on one file:

```
mcp__godot-ai__resource_manage op="load" params={"path": "res://assets/nature/grass_tuft.mesh.tres"}
```

Expected response: `"type": "ArrayMesh"`. If you see `"ImporterMesh"`, the conversion in T2 Step 1 didn't fire — the script was probably an older copy or hit an unexpected path. Re-check the script source matches the version in this plan and re-run.

- [ ] **Step 6: Delete the transient tool script**

```powershell
Remove-Item "C:\Users\whann\Documents\mine-co\scripts\extract_meshes.gd" -Force
Remove-Item "C:\Users\whann\Documents\mine-co\scripts\extract_meshes.gd.uid" -ErrorAction SilentlyContinue
```

The script was for one-time extraction; we don't ship it.

- [ ] **Step 7 (optional): Commit**

```bash
git add assets/nature/*.mesh.tres
git commit -m "feat(graphics-r2): extract Mesh resources from imported .glb files"
```

---

### Task 3: Tint shader

**Files (created):**
- `res://shaders/nature_tint.gdshader`

**Goal:** A small spatial shader that takes a per-instance `base_color` uniform, desaturates it slightly, and mixes a touch toward the R1 haze color. One shader, used by all 5 per-item materials.

- [ ] **Step 1: Create the shaders folder**

```powershell
New-Item -ItemType Directory -Path "C:\Users\whann\Documents\mine-co\shaders" -Force | Out-Null
```

- [ ] **Step 2: Write the shader**

Create `C:\Users\whann\Documents\mine-co\shaders\nature_tint.gdshader`:

```glsl
shader_type spatial;
render_mode cull_disabled, diffuse_lambert;

uniform vec4 base_color : source_color = vec4(0.5, 0.6, 0.3, 1.0);
uniform float saturation : hint_range(0.0, 1.0) = 0.7;
uniform float haze_mix_strength : hint_range(0.0, 1.0) = 0.15;
uniform vec3 haze_color : source_color = vec3(0.85, 0.87, 0.90);

void fragment() {
	vec3 c = base_color.rgb;
	float l = dot(c, vec3(0.3, 0.59, 0.11));
	c = mix(vec3(l), c, saturation);
	c = mix(c, haze_color, haze_mix_strength);
	ALBEDO = c;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
}
```

- [ ] **Step 3: Reimport and verify it compiles**

```
mcp__godot-ai__filesystem_manage op="reimport" params={"paths": ["res://shaders/nature_tint.gdshader"]}
mcp__godot-ai__logs_read source="editor"
```

Expected: no compile errors mentioning `nature_tint.gdshader`. (Warnings about unused things are fine.)

- [ ] **Step 4 (optional): Commit**

```bash
git add shaders/nature_tint.gdshader
git commit -m "feat(graphics-r2): nature tint shader"
```

---

### Task 4: Per-item ShaderMaterials

**Files (created):**
- `res://assets/nature/grass_tuft_mat.tres`
- `res://assets/nature/rock_small_mat.tres`
- `res://assets/nature/rock_medium_mat.tres`
- `res://assets/nature/tree_pine_mat.tres`
- `res://assets/nature/tree_oak_mat.tres`

**Goal:** Five `ShaderMaterial` `.tres` files, all pointing at `nature_tint.gdshader`, each with a different `base_color` uniform value.

- [ ] **Step 1: Write `grass_tuft_mat.tres`**

```
[gd_resource type="ShaderMaterial" load_steps=2 format=3]

[ext_resource type="Shader" path="res://shaders/nature_tint.gdshader" id="1_shader"]

[resource]
shader = ExtResource("1_shader")
shader_parameter/base_color = Color(0.45, 0.65, 0.30, 1.0)
shader_parameter/saturation = 0.7
shader_parameter/haze_mix_strength = 0.15
shader_parameter/haze_color = Color(0.85, 0.87, 0.90, 1.0)
```

- [ ] **Step 2: Write `rock_small_mat.tres`**

```
[gd_resource type="ShaderMaterial" load_steps=2 format=3]

[ext_resource type="Shader" path="res://shaders/nature_tint.gdshader" id="1_shader"]

[resource]
shader = ExtResource("1_shader")
shader_parameter/base_color = Color(0.55, 0.55, 0.55, 1.0)
shader_parameter/saturation = 0.7
shader_parameter/haze_mix_strength = 0.15
shader_parameter/haze_color = Color(0.85, 0.87, 0.90, 1.0)
```

- [ ] **Step 3: Write `rock_medium_mat.tres`**

```
[gd_resource type="ShaderMaterial" load_steps=2 format=3]

[ext_resource type="Shader" path="res://shaders/nature_tint.gdshader" id="1_shader"]

[resource]
shader = ExtResource("1_shader")
shader_parameter/base_color = Color(0.50, 0.50, 0.52, 1.0)
shader_parameter/saturation = 0.7
shader_parameter/haze_mix_strength = 0.15
shader_parameter/haze_color = Color(0.85, 0.87, 0.90, 1.0)
```

- [ ] **Step 4: Write `tree_pine_mat.tres`**

```
[gd_resource type="ShaderMaterial" load_steps=2 format=3]

[ext_resource type="Shader" path="res://shaders/nature_tint.gdshader" id="1_shader"]

[resource]
shader = ExtResource("1_shader")
shader_parameter/base_color = Color(0.30, 0.45, 0.25, 1.0)
shader_parameter/saturation = 0.7
shader_parameter/haze_mix_strength = 0.15
shader_parameter/haze_color = Color(0.85, 0.87, 0.90, 1.0)
```

- [ ] **Step 5: Write `tree_oak_mat.tres`**

```
[gd_resource type="ShaderMaterial" load_steps=2 format=3]

[ext_resource type="Shader" path="res://shaders/nature_tint.gdshader" id="1_shader"]

[resource]
shader = ExtResource("1_shader")
shader_parameter/base_color = Color(0.40, 0.55, 0.25, 1.0)
shader_parameter/saturation = 0.7
shader_parameter/haze_mix_strength = 0.15
shader_parameter/haze_color = Color(0.85, 0.87, 0.90, 1.0)
```

- [ ] **Step 6: Reimport all five**

```
mcp__godot-ai__filesystem_manage op="reimport" params={"paths": ["res://assets/nature/grass_tuft_mat.tres", "res://assets/nature/rock_small_mat.tres", "res://assets/nature/rock_medium_mat.tres", "res://assets/nature/tree_pine_mat.tres", "res://assets/nature/tree_oak_mat.tres"]}
mcp__godot-ai__logs_read source="editor"
```

Expected: no errors.

- [ ] **Step 7: Sanity-load one**

```
mcp__godot-ai__resource_manage op="load" params={"path": "res://assets/nature/grass_tuft_mat.tres"}
```

Expected: `"type": "ShaderMaterial"`, `shader_parameter/base_color` shows the green color.

- [ ] **Step 8 (optional): Commit**

```bash
git add assets/nature/*_mat.tres
git commit -m "feat(graphics-r2): per-item ShaderMaterials with base_color uniforms"
```

---

### Task 5: VoxelInstanceLibrary with 5 entries (built via tool script)

**Files (created):**
- `res://scripts/build_nature_library.gd` — transient @tool EditorScript (deleted after use)
- `res://scenes/nature_library.tres` — the resulting saved library

**Goal:** A `VoxelInstanceLibrary` with five items, each a `VoxelInstanceLibraryMultiMeshItem` referencing one mesh + one material + a per-item `VoxelInstanceGenerator` sub-resource.

**Critical note from spec review:** `VoxelInstanceLibrary` stores items via internal `_data` accessed through `add_item(int id, item)` — there is NO public `items: Dictionary` property settable in `.tres` syntax. We MUST construct the library programmatically via a tool script, configure each item, then `ResourceSaver.save` the assembled library. This is the same pattern as T2.

- [ ] **Step 1: Write the build tool script**

Create `C:\Users\whann\Documents\mine-co\scripts\build_nature_library.gd`:

```gdscript
@tool
extends EditorScript

const OUT_PATH := "res://scenes/nature_library.tres"

# (id, name, mesh_path, mat_path, density, min_scale, max_scale, slope_min, slope_max, h_min, h_max, vert_align, cast_shadow_off)
const ENTRIES := [
	[0, "grass_tuft",  "res://assets/nature/grass_tuft.mesh.tres",  "res://assets/nature/grass_tuft_mat.tres",   1.5,  0.80, 1.20, 0.0, 30.0, 1.2, 99.0, 1.0, true],
	[1, "rock_small",  "res://assets/nature/rock_small.mesh.tres",  "res://assets/nature/rock_small_mat.tres",   0.05, 0.50, 1.20, 0.0, 60.0, 0.0, 99.0, 0.3, false],
	[2, "rock_medium", "res://assets/nature/rock_medium.mesh.tres", "res://assets/nature/rock_medium_mat.tres",  0.01, 0.70, 1.30, 0.0, 25.0, 0.5, 99.0, 0.3, false],
	[3, "tree_pine",   "res://assets/nature/tree_pine.mesh.tres",   "res://assets/nature/tree_pine_mat.tres",    0.02, 0.85, 1.20, 0.0, 15.0, 6.0, 99.0, 1.0, false],
	[4, "tree_oak",    "res://assets/nature/tree_oak.mesh.tres",    "res://assets/nature/tree_oak_mat.tres",     0.015, 0.85, 1.20, 0.0, 12.0, 7.0, 99.0, 1.0, false],
]

func _run() -> void:
	var library := VoxelInstanceLibrary.new()
	for e in ENTRIES:
		var id: int = e[0]
		var name: String = e[1]
		var mesh: Mesh = load(e[2])
		var mat: ShaderMaterial = load(e[3])
		if mesh == null:
			push_error("Mesh not loaded: %s" % e[2])
			continue
		if mat == null:
			push_error("Material not loaded: %s" % e[3])
			continue

		var gen := VoxelInstanceGenerator.new()
		gen.density = e[4]
		gen.min_scale = e[5]
		gen.max_scale = e[6]
		gen.min_slope_degrees = e[7]
		gen.max_slope_degrees = e[8]
		gen.min_height = e[9]
		gen.max_height = e[10]
		gen.vertical_alignment = e[11]
		gen.random_rotation = true

		var item := VoxelInstanceLibraryMultiMeshItem.new()
		item.mesh = mesh
		item.material_override = mat
		item.generator = gen
		if e[12]:
			item.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		library.add_item(id, item)
		print("Added item %d (%s)" % [id, name])

	var err := ResourceSaver.save(library, OUT_PATH)
	if err != OK:
		push_error("Failed to save library: error %d" % err)
	else:
		print("Saved library to %s" % OUT_PATH)
```

> **Property-name notes:** the names used (`density`, `min_scale`, `max_scale`, `min_slope_degrees`, `max_slope_degrees`, `min_height`, `max_height`, `vertical_alignment`, `random_rotation`, `material_override`, `generator`, `cast_shadow`) are spec-review-verified. If the script errors on an unknown property when run, the implementer reads the editor Output panel for the exact bad name and adjusts. Voxel Tools occasionally renames between minor versions.

> **GeometryInstance3D enum:** `SHADOW_CASTING_SETTING_OFF` is the canonical name. If the script can't resolve it, use the integer literal `0`.

- [ ] **Step 2: Reimport the script**

```
mcp__godot-ai__filesystem_manage op="reimport" params={"paths": ["res://scripts/build_nature_library.gd"]}
mcp__godot-ai__logs_read source="editor"
```

Expected: no GDScript parse errors.

- [ ] **Step 3: Run the build script**

Ask the user:
> "Open `scripts/build_nature_library.gd` in Godot's script editor and press **Ctrl+Shift+X** to run it. Watch the Output panel — should print 5 'Added item' lines and one 'Saved library' line. Tell me when done."

Wait for confirmation.

- [ ] **Step 4: Verify the library exists and has 5 items**

```
mcp__godot-ai__resource_manage op="load" params={"path": "res://scenes/nature_library.tres"}
```

Expected: `"type": "VoxelInstanceLibrary"`. The `_data` array (or whatever the property surface exposes) should reflect 5 items. If the response shows 0 items, the script's `add_item` calls didn't take — check Output panel for errors and re-run.

- [ ] **Step 5: Delete the transient build script**

```powershell
Remove-Item "C:\Users\whann\Documents\mine-co\scripts\build_nature_library.gd" -Force
Remove-Item "C:\Users\whann\Documents\mine-co\scripts\build_nature_library.gd.uid" -ErrorAction SilentlyContinue
```

- [ ] **Step 6: Sanity check via Read on the saved .tres**

```
Read scenes/nature_library.tres
```

The saved file should contain the 5 items with embedded sub_resource blocks for VoxelInstanceLibraryMultiMeshItem and VoxelInstanceGenerator. The exact serialization format is whatever `ResourceSaver.save()` produces — that's authoritative; we don't try to predict it.

- [ ] **Step 7 (optional): Commit**

```bash
git add scenes/nature_library.tres
git commit -m "feat(graphics-r2): nature instance library with 5 entries (grass, 2 rocks, 2 trees)"
```

---

### Task 6: Add VoxelInstancer to main.tscn

**Files:**
- Modify (via MCP): `res://scenes/main.tscn`

**Goal:** Add a single `VoxelInstancer` node as a child of `/Main/VoxelTerrain`. Set its `library` to the library .tres and enable fading to soften chunk-edge pop-in.

- [ ] **Step 1: Stop any running game**

```
mcp__godot-ai__editor_state
```

If `is_playing: true`:

```
mcp__godot-ai__project_manage op="stop"
```

- [ ] **Step 2: Add the VoxelInstancer node via MCP**

```
mcp__godot-ai__node_create params={"parent_path": "/Main/VoxelTerrain", "type": "VoxelInstancer", "name": "VoxelInstancer"}
```

Expected: response confirms node created at path `/Main/VoxelTerrain/VoxelInstancer`.

- [ ] **Step 3: Assign the library**

```
mcp__godot-ai__node_set_property params={"path": "/Main/VoxelTerrain/VoxelInstancer", "property": "library", "value": "res://scenes/nature_library.tres"}
```

Expected response: `value: "res://scenes/nature_library.tres"` (NOT null). If null, the library .tres failed to load — go back to T5 fallback.

- [ ] **Step 4: Enable fading to mask chunk-edge pop-in**

```
mcp__godot-ai__node_set_property params={"path": "/Main/VoxelTerrain/VoxelInstancer", "property": "fading_enabled", "value": true}
```

Expected: `value: true`. If the property doesn't exist on this Voxel Tools version, the response will error — leave fading off and note as a known limitation; not a blocker for v1 of this round.

- [ ] **Step 5: Save the scene**

```
mcp__godot-ai__scene_save
```

- [ ] **Step 6: Verify the saved scene contains the instancer**

```
Read main.tscn
```

Look for:
```
[node name="VoxelInstancer" type="VoxelInstancer" parent="VoxelTerrain"]
library = ExtResource(...)
fading_enabled = true
```

If the node line is missing, the save dropped it (we hit this in R1 with VoxelViewer). Recovery: hand-edit `main.tscn` to add the lines manually, then ask user to **Project → Reload Current Project**.

- [ ] **Step 7: Run + visual verify**

```
mcp__godot-ai__project_run params={"autosave": false}
```

Wait 10 seconds for spawn-gate raycast + chunks + instances:

```
sleep 10
mcp__godot-ai__editor_screenshot source="game" max_resolution=1000
```

Expected: the previously bare-grass island now has visible green grass tufts on flat areas, scattered rocks across the surface, and a few trees on raised hilltops. Sand bands near the water should NOT have grass on them (height filter `min_height = 1.2`). Trees should NOT be on the beach.

If you see NO instances: library `items` dict was empty — re-run T5.
If you see grass underwater or in the sand band: height filter property name was wrong — open inspector and check actual generator property name.
If you see trees everywhere instead of just hilltops: `min_height` filter not applying — same fix.
If everything is grossly mis-colored (e.g., all neon green / all magenta / all default-checkerboard): `material_override` not applying — verify in node_get_properties.

Stop the run.

- [ ] **Step 8 (optional): Commit**

```bash
git add scenes/main.tscn
git commit -m "feat(graphics-r2): wire VoxelInstancer into main scene"
```

---

### Task 7: Walkthrough + tune

**Files (potentially):**
- `res://scenes/nature_library.tres` — density / scale / slope / height tweaks
- `res://assets/nature/*_mat.tres` — base_color or saturation tweaks if a specific asset clashes

**Goal:** Walk the island. See how the decoration reads in motion. Tune any individual asset's density / placement / color until the look matches the spec's success criteria.

- [ ] **Step 1: Run and walk**

```
mcp__godot-ai__project_run params={"autosave": false}
```

Switch to game window. Walk for 2–3 minutes. Check:
- Grass appears on flat green-grass areas, not on sand or underwater
- Rocks scatter across grass and sand bands at modest density
- Trees only on hilltops; small clusters or solo
- Color palette feels unified — nothing reads as out-of-place neon
- No visible chunk-edge popping during walking (fading should mask it)
- Frame rate stays solid

- [ ] **Step 2: Tune individual densities if needed**

Common tweaks (edit the `density` field on the relevant `VoxelInstanceGenerator` sub-resource in `scenes/nature_library.tres`, then reimport):
- Grass too sparse → density 1.5 → 2.5
- Grass too thick → 1.5 → 0.8
- Rocks barely visible → rock_small density 0.05 → 0.10
- Trees not appearing → drop pine `min_height` 6.0 → 4.0; drop oak 7.0 → 5.0
- Trees everywhere → raise pine density 0.02 → 0.005

- [ ] **Step 3: Tune colors if any asset clashes**

If a particular asset stands out (e.g., grass too vivid against the haze): edit its `_mat.tres` `shader_parameter/saturation` lower (0.5 instead of 0.7) or raise `haze_mix_strength` (0.25 instead of 0.15).

- [ ] **Step 4: Confirm success criteria**

- [ ] Grass clumps visible on grass band ✓
- [ ] Rocks scattered across grass + sand ✓
- [ ] Trees on hilltops only ✓
- [ ] No grass underwater or in sand-only ring ✓
- [ ] No neon-saturated outliers ✓
- [ ] No chunk-edge instance pop-in noticeable ✓
- [ ] Frame rate solid ✓

- [ ] **Step 5: Final commit + announce R2 done**

```bash
git commit -am "feat(graphics-r2): final tune"
```

Report to user: R2 decoration shipped. Island now has grass, rocks, and hilltop trees harmonized to the R1 hazy palette via the tint shader. Note any contingencies that fired (e.g., library inspector fallback in T5). Suggest next round candidates: wind animation on grass/leaves, foliage destruction tied to mining, color-tweaked seasonal variations, ambient creature life.

---

## Notes for the implementer

- **MCP tool names** in this plan use the `mcp__godot-ai__<tool>` form. Exact tool/parameter shapes may differ slightly from what's pinned here; treat the calls as intent specifications and adapt to actual schemas.
- **`autosave: false`** on `project_run` — always pass it. R1 had repeated bugs from the editor's autosave-on-play overwriting disk edits.
- **Editor cache trap for main.tscn** — when modifying main.tscn (T6), use MCP `node_create` / `node_set_property` followed by `scene_save`. Don't hand-edit unless the MCP path fails, in which case ask the user to do **Project → Reload Current Project** so the in-memory scene matches disk.
- **Property name uncertainty in the library** — VoxelInstanceGenerator property names are best-effort verified against Voxel Tools 1.6 docs but module-specific behavior can drift. T5 has explicit fallback to inspector-driven setup if the literal .tres syntax is rejected.
- **Don't add features not in the spec.** No wind, no per-instance color, no destruction. v1 of this round is "static decoration."
- **When the implementer hits a wall**, re-read the relevant Risk in the spec — most failure modes are anticipated with a documented mitigation.
