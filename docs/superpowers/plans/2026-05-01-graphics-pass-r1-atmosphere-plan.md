# Graphics Pass Round 1 (Atmosphere) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transform the look of the v1 island scene from "neutral test" to a hazy Death-Stranding-flavored atmosphere via tuned lighting, sky, fog, tonemap, and a Gerstner-wave water shader.

**Architecture:** Pull `Environment`, `Sky`, and `ProceduralSkyMaterial` out of `main.tscn` as standalone `.tres` files (so they can be edited via direct file writes that bypass the editor-cache trap). Add an `Atmosphere` autoload as a single source of truth for the haze color shared by sky, fog, and water. Replace the existing water StandardMaterial3D with a ShaderMaterial implementing per-vertex Gerstner waves, view-space fresnel, and depth-based color (with a documented constant-depth fallback if depth reads misbehave on Forward+ / D3D12).

**Tech Stack:** Godot 4.6 module build (custom binary at `C:\Users\whann\Tools\godot-voxel-1.6\godot.windows.editor.x86_64.exe`), GDScript, GLSL (Godot 4 spatial shader), Forward+ / D3D12. No new external dependencies.

**Spec:** `docs/superpowers/specs/2026-05-01-graphics-pass-r1-atmosphere-design.md`

**Project root:** `C:\Users\whann\Documents\mine-co\` (Windows). All `res://` paths resolve under this root.

---

## Validation philosophy

Same as the v1 plan: this is a Godot scene/shader project, not a library. Pure GDScript unit tests would require pulling in GUT or GdUnit4 just for two scripts and one shader — pure ceremony. Each task instead has a concrete in-editor verification step using `mcp__godot-ai__project_run` + `editor_screenshot` + `logs_read`. The verification asserts a specific visual or runtime check; if it fails, stop and diagnose before moving on.

`project_run` should be invoked with `autosave: false` to prevent the editor's in-memory scene state from clobbering disk edits made between tasks. (This bit us repeatedly in v1.)

---

## File structure (final state)

```
res://
  scenes/
    main.tscn                     — modified: WorldEnvironment.environment now ext_resource;
                                                Sun properties retuned;
                                                Water mesh subdivisions bumped;
                                                Water uses new ShaderMaterial.
    environment.tres              — NEW: ext-resource'd Environment; holds fog, tonemap, ambient.
    sky.tres                      — NEW: Sky resource; references sky_material.tres.
    sky_material.tres             — NEW: ProceduralSkyMaterial with hazy colors.
    water_material.tres           — REWRITTEN IN PLACE: now ShaderMaterial.
    water_mesh.tres               — modified: subdivide_w/d = 80.
    water_waves.gdshader          — NEW: Gerstner waves + fresnel + depth-based color.
  scripts/
    atmosphere.gd                 — NEW: autoload constants (HAZE_COLOR).
    water_init.gd                 — NEW: small script on Water node; pushes HAZE_COLOR to shader.
  project.godot                   — modified: register Atmosphere autoload.
```

Unchanged from v1: `island_voxel_generator.gd`, `island_generator.tres`, `terrain_material.tres`, `world_y_biome.gdshader`, `player.tscn`, `player.gd`, `spawn_gate.gd`. The terrain layer is intentionally left alone in this round.

## Task dependency graph

```
T1 (autoload + reload) ──┐
T2 (externalize env+sky) ┴──> T3 (lighting) ──┐
                              T4 (sky tweaks) ┤
                              T5 (fog)        ├──> T11 (walkthrough)
                              T6 (tonemap)    ┤
T7 (water mesh subdivide) ─> T8 (shader) ─> T9 (material) ─> T10 (init script + wire) ┘
```

T3, T4, T5, T6 all touch the externalized Environment / SkyMaterial — they could be parallel in theory but in practice they're trivial property tweaks and easier to verify sequentially. T7-T10 are the water work; T7 (mesh) is independent of T8 (shader file) but T9 references both.

A single subagent can execute the whole plan in order. T8 is the only meaty implementation task.

---

### Task 1: Atmosphere autoload

**Files:**
- Create: `res://scripts/atmosphere.gd`
- Modify: `res://project.godot` (add autoload section)

**Goal:** Single source of truth for the haze color so sky, fog, and water can't drift. Wire it as an autoload so any script can reach `Atmosphere.HAZE_COLOR`.

- [ ] **Step 1: Write `atmosphere.gd`**

Create `C:\Users\whann\Documents\mine-co\scripts\atmosphere.gd`:

```gdscript
extends Node

const HAZE_COLOR: Color = Color(0.85, 0.87, 0.90)
```

That's the entire file. It's a Node so it can be autoloaded; the constant is the contract.

- [ ] **Step 2: Add autoload entry to `project.godot`**

Read `C:\Users\whann\Documents\mine-co\project.godot`. Locate the existing `[autoload]` section (it already has `_mcp_game_helper`). Append the new autoload as a sibling line, NOT a replacement:

```ini
[autoload]

_mcp_game_helper="*res://addons/godot_ai/runtime/game_helper.gd"
Atmosphere="*res://scripts/atmosphere.gd"
```

The `*` prefix makes it auto-instantiate at scene-tree-root.

- [ ] **Step 3: Reload the project so the new autoload activates**

Editor cache will not pick up `[autoload]` changes mid-session. Tell the user to do **Project → Reload Current Project** in Godot and confirm with you when complete. Once they confirm, proceed.

> If the editor isn't running, the implementer can simply launch the editor and the autoload will load on first open.

- [ ] **Step 4: Verify the autoload registered**

Use the godot-ai MCP to confirm Godot sees the constant:

```
mcp__godot-ai__project_manage op="settings_get" params={"key": "autoload/Atmosphere"}
```

Expected: returns the autoload string `*res://scripts/atmosphere.gd` (or similar). If it returns empty, the project hasn't been reloaded — surface to user.

- [ ] **Step 5 (optional): Commit**

```bash
git add scripts/atmosphere.gd project.godot
git commit -m "feat(graphics-r1): atmosphere autoload as single source of truth for haze color"
```

(Project may not be a git repo yet; skip if so.)

---

### Task 2: Externalize Environment, Sky, and SkyMaterial as .tres files

**Files:**
- Create: `res://scenes/sky_material.tres`
- Create: `res://scenes/sky.tres`
- Create: `res://scenes/environment.tres`
- Modify: `res://scenes/main.tscn` (WorldEnvironment.environment now an ext_resource)

**Goal:** Move the inline `Env_1`, `Sky_1`, `SkyMat_1` sub_resources out of `main.tscn` into standalone `.tres` files. Subsequent tasks (lighting / sky / fog / tonemap) edit these `.tres` files directly via Write, which avoids the editor's scene-cache-clobbers-disk-edit problem we ran into repeatedly in v1.

After this task, main.tscn's `WorldEnvironment` node references `res://scenes/environment.tres`, which references `sky.tres`, which references `sky_material.tres`. The render output should be visually identical to the current state — this is a pure refactor enabling later tasks.

- [ ] **Step 1: Write `sky_material.tres`** (with v1 default values; later tasks retune)

Create `C:\Users\whann\Documents\mine-co\scenes\sky_material.tres`:

```
[gd_resource type="ProceduralSkyMaterial" format=3]

[resource]
```

Empty `[resource]` section uses all Godot defaults (which is what main.tscn currently has — `[sub_resource type="ProceduralSkyMaterial" id="SkyMat_1"]` with no body).

- [ ] **Step 2: Write `sky.tres`**

Create `C:\Users\whann\Documents\mine-co\scenes\sky.tres`:

```
[gd_resource type="Sky" load_steps=2 format=3]

[ext_resource type="Material" path="res://scenes/sky_material.tres" id="1_skymat"]

[resource]
sky_material = ExtResource("1_skymat")
```

- [ ] **Step 3: Write `environment.tres`** (mirroring the v1 inline `Env_1` settings byte-for-byte)

Create `C:\Users\whann\Documents\mine-co\scenes\environment.tres`:

```
[gd_resource type="Environment" load_steps=2 format=3]

[ext_resource type="Sky" path="res://scenes/sky.tres" id="1_sky"]

[resource]
background_mode = 2
sky = ExtResource("1_sky")
ambient_light_source = 2
ambient_light_energy = 0.3
```

This preserves v1's exact inline `Env_1` state, including the `ambient_light_source = 2` (which is `COLOR`, not `SKY`). T3 will fix this to `3` (`SKY`) as part of the explicit lighting change. Keeping T2 as a pure refactor (no behavior change) lets us prove the externalization itself didn't break anything before any visible tweak lands.

- [ ] **Step 4: Force reimport so the editor sees the new resources**

```
mcp__godot-ai__filesystem_manage op="reimport" params={"paths": ["res://scenes/sky_material.tres", "res://scenes/sky.tres", "res://scenes/environment.tres"]}
```

Then check logs:

```
mcp__godot-ai__logs_read source="editor"
```

Expected: no errors. Each .tres should load cleanly.

- [ ] **Step 5: Point `/Main/WorldEnvironment` at the new external Environment**

Use MCP to update the in-memory scene model:

```
mcp__godot-ai__node_set_property params={"path": "/Main/WorldEnvironment", "property": "environment", "value": "res://scenes/environment.tres"}
```

Expected response: `value: "res://scenes/environment.tres"` (NOT null).

**Fallback if MCP rejects the assignment** (returns `value: null` like the v1 generator-assignment bug): hand-edit `main.tscn`. Stop the editor (or just don't `scene_save`), then `Edit` `main.tscn` to:
1. Add an `[ext_resource type="Environment" path="res://scenes/environment.tres" id="env_ext"]` line near the other ext_resource lines at the top.
2. Replace the inline `[sub_resource type="Environment" id="Env_1"]` block (and Sky_1, SkyMat_1 sub_resources) with nothing — they're now externalized.
3. Change the `WorldEnvironment` node's `environment = SubResource("Env_1")` line to `environment = ExtResource("env_ext")`.
4. After the disk edit, ask the user to **Project → Reload Current Project** so the editor's in-memory scene gets the new structure.

- [ ] **Step 6: Save the scene**

```
mcp__godot-ai__scene_save
```

This commits the in-memory model (which now points environment to the external .tres) back to disk. The old `[sub_resource ... Env_1]`, `Sky_1`, `SkyMat_1` blocks should be gone from main.tscn.

- [ ] **Step 7: Verify visual is unchanged**

```
mcp__godot-ai__project_run params={"autosave": false}
```

Wait ~5 seconds for chunks to mesh. Then:

```
mcp__godot-ai__editor_screenshot source="game" max_resolution=1000
```

Expected: the rendered scene looks IDENTICAL to before this task (sand seabed, green island, blue water, gradient sky). If the sky looks different (e.g., black sky), the environment.tres reference broke — check `main.tscn` content via `Read` and confirm `WorldEnvironment` has `environment = ExtResource(...)`.

Stop the run:

```
mcp__godot-ai__project_manage op="stop"
```

- [ ] **Step 8 (optional): Commit**

```bash
git add scenes/sky_material.tres scenes/sky.tres scenes/environment.tres scenes/main.tscn
git commit -m "feat(graphics-r1): externalize environment/sky/skymaterial as .tres for editable atmosphere"
```

---

### Task 3: Lighting retune (Sun + ambient)

**Files:**
- Modify (via MCP, NOT disk-edit): `res://scenes/main.tscn` (Sun node properties)
- Modify (via Write): `res://scenes/environment.tres` (ambient_light_energy)

**Goal:** Apply the spec's lighting changes — softer cool-tinted sun and brighter ambient.

- [ ] **Step 1: Sun light_energy 1.0 → 0.7**

```
mcp__godot-ai__node_set_property params={"path": "/Main/Sun", "property": "light_energy", "value": 0.7}
```

- [ ] **Step 2: Sun light_color cool tint**

```
mcp__godot-ai__node_set_property params={"path": "/Main/Sun", "property": "light_color", "value": [0.95, 0.97, 1.0, 1.0]}
```

- [ ] **Step 3: Sun shadow_blur 1.0 → 2.0**

```
mcp__godot-ai__node_set_property params={"path": "/Main/Sun", "property": "shadow_blur", "value": 2.0}
```

- [ ] **Step 4: Save the scene to commit Sun changes to disk**

```
mcp__godot-ai__scene_save
```

- [ ] **Step 5: Fix ambient source + bump energy in `environment.tres`**

Read `C:\Users\whann\Documents\mine-co\scenes\environment.tres`. Change two lines:
- `ambient_light_source = 2` → `ambient_light_source = 3` (COLOR → SKY — this is the actual fix; v1 was using flat-color ambient by mistake)
- `ambient_light_energy = 0.3` → `ambient_light_energy = 0.6`

The file should end up:

```
[gd_resource type="Environment" load_steps=2 format=3]

[ext_resource type="Sky" path="res://scenes/sky.tres" id="1_sky"]

[resource]
background_mode = 2
sky = ExtResource("1_sky")
ambient_light_source = 3
ambient_light_energy = 0.6
```

- [ ] **Step 6: Reimport the changed resource**

```
mcp__godot-ai__filesystem_manage op="reimport" params={"paths": ["res://scenes/environment.tres"]}
```

- [ ] **Step 7: Run + verify**

```
mcp__godot-ai__project_run params={"autosave": false}
```

Wait, screenshot:

```
mcp__godot-ai__editor_screenshot source="game" max_resolution=1000
```

Expected: the scene is slightly cooler in tone (less yellow), shadows are softer/blurrier on the terrain edges, and the dim shadowed parts of the terrain are noticeably less dark than before. The shift from COLOR to SKY ambient may add a subtle sky-tinted blue cast to shaded surfaces — that's expected. Stop the run with `project_manage op="stop"`.

- [ ] **Step 8 (optional): Commit**

```bash
git add scenes/main.tscn scenes/environment.tres
git commit -m "feat(graphics-r1): softer cooler sun + brighter ambient"
```

---

### Task 4: Sky retune (ProceduralSkyMaterial)

**Files:**
- Modify (via Write): `res://scenes/sky_material.tres`

**Goal:** Hazy desaturated sky that fades to gray-white at the horizon.

- [ ] **Step 1: Rewrite `sky_material.tres` with the tuned values**

Overwrite `C:\Users\whann\Documents\mine-co\scenes\sky_material.tres` with:

```
[gd_resource type="ProceduralSkyMaterial" format=3]

[resource]
sky_top_color = Color(0.55, 0.65, 0.75, 1)
sky_horizon_color = Color(0.85, 0.87, 0.9, 1)
ground_horizon_color = Color(0.85, 0.87, 0.9, 1)
ground_bottom_color = Color(0.45, 0.5, 0.55, 1)
sun_angle_max = 10.0
sun_curve = 0.3
```

> Note: the haze color `(0.85, 0.87, 0.90)` matches `Atmosphere.HAZE_COLOR` from T1. Add a comment in the file if your editor preserves it; .tres files don't natively support comments inside `[resource]`, so leave a comment in the matching .gd or simply rely on the contract.

- [ ] **Step 2: Reimport**

```
mcp__godot-ai__filesystem_manage op="reimport" params={"paths": ["res://scenes/sky_material.tres"]}
```

- [ ] **Step 3: Run + verify**

```
mcp__godot-ai__project_run params={"autosave": false}
mcp__godot-ai__editor_screenshot source="game" max_resolution=1000
```

Expected: sky is noticeably hazier and less saturated than before. The horizon should be a pale white-gray. The sun (look around if needed; default camera angle may not include it) is smaller and softer, not a bright dot. Stop the run.

- [ ] **Step 4 (optional): Commit**

```bash
git commit -am "feat(graphics-r1): hazy desaturated sky + smaller softer sun disk"
```

---

### Task 5: Fog enable + tune

**Files:**
- Modify (via Write): `res://scenes/environment.tres`

**Goal:** The single biggest visual change — exponential fog matching the haze color, with aerial perspective and full sky-affect blend.

- [ ] **Step 1: Add fog properties to `environment.tres`**

Overwrite `C:\Users\whann\Documents\mine-co\scenes\environment.tres` with:

```
[gd_resource type="Environment" load_steps=2 format=3]

[ext_resource type="Sky" path="res://scenes/sky.tres" id="1_sky"]

[resource]
background_mode = 2
sky = ExtResource("1_sky")
ambient_light_source = 3
ambient_light_energy = 0.6
fog_enabled = true
fog_mode = 0
fog_density = 0.004
fog_light_color = Color(0.85, 0.87, 0.9, 1)
fog_sun_scatter = 0.0
fog_aerial_perspective = 0.5
fog_sky_affect = 1.0
```

- [ ] **Step 2: Reimport**

```
mcp__godot-ai__filesystem_manage op="reimport" params={"paths": ["res://scenes/environment.tres"]}
```

- [ ] **Step 3: Run + verify**

```
mcp__godot-ai__project_run params={"autosave": false}
mcp__godot-ai__editor_screenshot source="game" max_resolution=1000
```

Expected:
- Distant terrain visibly fades toward the haze color (washed out, less saturated as it gets farther).
- The horizon between sky and ground is essentially invisible — they blend.
- Foreground terrain (within ~50m of player) stays normal; only distance is affected.

Stop the run.

If the scene looks barely-foggy, raise `fog_density` to 0.006 and reimport. If the scene is murky-pea-soup, drop `fog_density` to 0.0025. Tuning is expected here — the spec lists target transmittance values for reference.

- [ ] **Step 4 (optional): Commit**

```bash
git commit -am "feat(graphics-r1): exponential fog matching haze color"
```

---

### Task 6: Tonemap switch to filmic

**Files:**
- Modify (via Write): `res://scenes/environment.tres`

**Goal:** Filmic tonemapping for softer highlight rolloff, subtle under-exposure.

- [ ] **Step 1: Add tonemap properties to `environment.tres`**

Overwrite `C:\Users\whann\Documents\mine-co\scenes\environment.tres` with the additions appended to the existing block:

```
[gd_resource type="Environment" load_steps=2 format=3]

[ext_resource type="Sky" path="res://scenes/sky.tres" id="1_sky"]

[resource]
background_mode = 2
sky = ExtResource("1_sky")
ambient_light_source = 3
ambient_light_energy = 0.6
fog_enabled = true
fog_mode = 0
fog_density = 0.004
fog_light_color = Color(0.85, 0.87, 0.9, 1)
fog_sun_scatter = 0.0
fog_aerial_perspective = 0.5
fog_sky_affect = 1.0
tonemap_mode = 2
tonemap_white = 2.5
```

`tonemap_mode = 2` is `TONE_MAPPER_FILMIC`. `tonemap_exposure` stays at default 1.0 (so we don't include it).

- [ ] **Step 2: Reimport**

```
mcp__godot-ai__filesystem_manage op="reimport" params={"paths": ["res://scenes/environment.tres"]}
```

- [ ] **Step 3: Run + verify**

```
mcp__godot-ai__project_run params={"autosave": false}
mcp__godot-ai__editor_screenshot source="game" max_resolution=1000
```

Expected: the very brightest pixels (sky near sun direction, possibly water reflections) no longer clip to pure white — they have a slight roll-off into pale colors. The overall image feels marginally less harsh. Effect is subtle. Stop the run.

If highlights still clip badly, raise `tonemap_white` to 4.0. If image goes too dark / muddy, drop to 1.5.

- [ ] **Step 4 (optional): Commit**

```bash
git commit -am "feat(graphics-r1): filmic tonemap for softer highlights"
```

---

### Task 7: Water mesh subdivision

**Files:**
- Modify (via Write): `res://scenes/water_mesh.tres`

**Goal:** Give the water plane enough vertices for visible Gerstner waves. Visual look unchanged at this point — the existing material is still flat.

- [ ] **Step 1: Read current `water_mesh.tres`**

`Read` `C:\Users\whann\Documents\mine-co\scenes\water_mesh.tres`. It should contain:

```
[gd_resource type="PlaneMesh" format=3]

[resource]
size = Vector2(400, 400)
```

- [ ] **Step 2: Add subdivisions**

Rewrite to:

```
[gd_resource type="PlaneMesh" format=3]

[resource]
size = Vector2(400, 400)
subdivide_width = 80
subdivide_depth = 80
```

> Property names: `subdivide_width` and `subdivide_depth` (verified against Godot 4.6). The abbreviated forms `subdivide_w` / `subdivide_d` do not exist in 4.6.

- [ ] **Step 3: Reimport**

```
mcp__godot-ai__filesystem_manage op="reimport" params={"paths": ["res://scenes/water_mesh.tres"]}
```

- [ ] **Step 4: Run + verify**

```
mcp__godot-ai__project_run params={"autosave": false}
mcp__godot-ai__editor_screenshot source="game" max_resolution=1000
```

Expected: scene looks the SAME as before — the higher-vertex plane doesn't change anything yet because the material is still the flat StandardMaterial3D. Frame rate should be effectively unchanged. Stop the run.

If the scene looks broken (water disappears or renders as black), the .tres syntax has a real error — `Read` it back and confirm the file matches the spec above exactly; check editor logs via `mcp__godot-ai__logs_read source="editor"` for the parse error.

- [ ] **Step 5 (optional): Commit**

```bash
git commit -am "feat(graphics-r1): water plane subdivisions for wave displacement"
```

---

### Task 8: Water shader (Gerstner waves + fresnel + depth)

**Files:**
- Create: `res://scenes/water_waves.gdshader`

**Goal:** The shader file itself. It's not yet wired up to anything — that happens in T9 + T10. This task validates that the shader compiles cleanly.

- [ ] **Step 1: Write the shader**

Create `C:\Users\whann\Documents\mine-co\scenes\water_waves.gdshader`:

```glsl
shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_back;

uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;

uniform vec2 wave_dir_1 = vec2(1.0, 0.0);
uniform vec2 wave_dir_2 = vec2(0.7, 0.7);
uniform vec2 wave_dir_3 = vec2(0.3, -0.95);

uniform float wave_wavelength_1 = 12.0;
uniform float wave_wavelength_2 = 7.0;
uniform float wave_wavelength_3 = 4.0;

uniform float wave_amplitude_1 = 0.15;
uniform float wave_amplitude_2 = 0.08;
uniform float wave_amplitude_3 = 0.05;

uniform float wave_speed_1 = 0.4;
uniform float wave_speed_2 = 0.55;
uniform float wave_speed_3 = 0.7;

uniform vec3 shallow_color : source_color = vec3(0.4, 0.7, 0.7);
uniform vec3 deep_color : source_color = vec3(0.15, 0.25, 0.4);
uniform vec3 sky_color : source_color = vec3(0.85, 0.87, 0.9);
uniform float depth_falloff = 4.0;

// Single Gerstner wave: returns displacement (xyz) and writes accumulated tangent/binormal.
// For each wave, position oscillates: x,z circle horizontally, y bobs vertically.
vec3 gerstner_wave(vec2 pos, vec2 dir, float wavelength, float amplitude, float speed, float t,
                   inout vec3 tangent, inout vec3 binormal) {
	vec2 d = normalize(dir);
	float k = 6.28318 / wavelength;             // wave number
	float c = sqrt(9.81 / k);                    // gravity wave phase speed (looks natural)
	float w = c * k;                             // angular frequency, scaled later by speed
	float phase = dot(d, pos) * k - t * speed * w;
	float cos_p = cos(phase);
	float sin_p = sin(phase);
	float Q = 0.5; // steepness; lower = rounder, higher = peakier
	vec3 disp = vec3(
		Q * amplitude * d.x * cos_p,
		amplitude * sin_p,
		Q * amplitude * d.y * cos_p
	);
	// Accumulate Jacobian columns for normal computation
	tangent += vec3(
		-Q * amplitude * d.x * d.x * sin_p,
		amplitude * d.x * cos_p,
		-Q * amplitude * d.x * d.y * sin_p
	);
	binormal += vec3(
		-Q * amplitude * d.x * d.y * sin_p,
		amplitude * d.y * cos_p,
		-Q * amplitude * d.y * d.y * sin_p
	);
	return disp;
}

void vertex() {
	vec2 p = VERTEX.xz;
	vec3 tangent = vec3(1.0, 0.0, 0.0);
	vec3 binormal = vec3(0.0, 0.0, 1.0);
	vec3 disp = vec3(0.0);
	disp += gerstner_wave(p, wave_dir_1, wave_wavelength_1, wave_amplitude_1, wave_speed_1, TIME, tangent, binormal);
	disp += gerstner_wave(p, wave_dir_2, wave_wavelength_2, wave_amplitude_2, wave_speed_2, TIME, tangent, binormal);
	disp += gerstner_wave(p, wave_dir_3, wave_wavelength_3, wave_amplitude_3, wave_speed_3, TIME, tangent, binormal);
	VERTEX += disp;
	// cross(binormal, tangent) order is load-bearing: produces +Y for a flat plane (correct).
	// If water renders black, swap to cross(tangent, binormal) to flip the normal.
	vec3 world_normal = normalize(cross(binormal, tangent));
	NORMAL = (VIEW_MATRIX * vec4(world_normal, 0.0)).xyz;
}

void fragment() {
	// Fresnel in view space (VIEW points toward camera; NORMAL is view space from vertex stage).
	float ndotv = clamp(dot(VIEW, NORMAL), 0.0, 1.0);
	float fresnel = pow(1.0 - ndotv, 5.0);

	// Depth-based color: read seabed depth, lerp shallow→deep
	float depth_raw = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth_raw);
	vec4 view_h = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	float seabed_view_z = view_h.z / view_h.w;     // negative (Godot view z is -forward)
	float water_view_z = VERTEX.z;                 // VERTEX in fragment is view space
	float underwater_distance = abs(seabed_view_z - water_view_z);

	float t = smoothstep(0.0, depth_falloff, underwater_distance);
	vec3 base = mix(shallow_color, deep_color, t);
	ALBEDO = mix(base, sky_color, fresnel);

	ALPHA = mix(0.6, 1.0, fresnel);
	ROUGHNESS = 0.05;
	METALLIC = 0.0;
	SPECULAR = 0.5;
}
```

- [ ] **Step 2: Reimport and check for compile errors**

```
mcp__godot-ai__filesystem_manage op="reimport" params={"paths": ["res://scenes/water_waves.gdshader"]}
mcp__godot-ai__logs_read source="editor"
```

Expected: NO errors mentioning `water_waves.gdshader`. Warnings about deprecated APIs are fine; block on real compile errors.

If the compile fails on `INV_PROJECTION_MATRIX` or `VIEW_MATRIX` (these are spatial-shader built-ins; should be valid), the implementer should check exact spelling against Godot 4.6 docs.

If the compile fails on `hint_depth_texture`, the GDExtension version of the addon may not be in play (we shipped the module build) — the hint should work; if it doesn't, swap to `hint_normal` and skip depth (and switch to the constant-depth fallback in T8.5).

- [ ] **Step 3 (optional): Commit**

```bash
git add scenes/water_waves.gdshader
git commit -m "feat(graphics-r1): Gerstner-waves water shader with fresnel and depth-based color"
```

---

### Task 9: Water material rewrite (StandardMaterial3D → ShaderMaterial)

**Files:**
- Rewrite (via Write): `res://scenes/water_material.tres`

**Goal:** Replace the hacky `emission`-based StandardMaterial3D with a proper ShaderMaterial referencing `water_waves.gdshader`. Keep the SAME path so `main.tscn`'s ext_resource UID doesn't churn.

- [ ] **Step 1: Overwrite `water_material.tres`**

Overwrite `C:\Users\whann\Documents\mine-co\scenes\water_material.tres` with:

```
[gd_resource type="ShaderMaterial" load_steps=2 format=3]

[ext_resource type="Shader" path="res://scenes/water_waves.gdshader" id="1_shader"]

[resource]
shader = ExtResource("1_shader")
shader_parameter/wave_dir_1 = Vector2(1, 0)
shader_parameter/wave_dir_2 = Vector2(0.7, 0.7)
shader_parameter/wave_dir_3 = Vector2(0.3, -0.95)
shader_parameter/wave_wavelength_1 = 12.0
shader_parameter/wave_wavelength_2 = 7.0
shader_parameter/wave_wavelength_3 = 4.0
shader_parameter/wave_amplitude_1 = 0.15
shader_parameter/wave_amplitude_2 = 0.08
shader_parameter/wave_amplitude_3 = 0.05
shader_parameter/wave_speed_1 = 0.4
shader_parameter/wave_speed_2 = 0.55
shader_parameter/wave_speed_3 = 0.7
shader_parameter/shallow_color = Color(0.4, 0.7, 0.7, 1)
shader_parameter/deep_color = Color(0.15, 0.25, 0.4, 1)
shader_parameter/sky_color = Color(0.85, 0.87, 0.9, 1)
shader_parameter/depth_falloff = 4.0
```

- [ ] **Step 2: Reimport**

```
mcp__godot-ai__filesystem_manage op="reimport" params={"paths": ["res://scenes/water_material.tres"]}
```

- [ ] **Step 3: Verify the resource loads as ShaderMaterial**

```
mcp__godot-ai__resource_manage op="load" params={"path": "res://scenes/water_material.tres"}
```

Expected: `type: "ShaderMaterial"` (NOT `"StandardMaterial3D"`) and the shader_parameter values are present.

- [ ] **Step 4: Run + verify (visual sanity)**

```
mcp__godot-ai__project_run params={"autosave": false}
mcp__godot-ai__editor_screenshot source="game" max_resolution=1000
```

Expected: water now shows wave displacement (the surface should not be a flat plane — there's gentle moving relief). Coloring is teal-blue with depth gradient; no more emission-flat-blue. The waves animate over time, but a single screenshot will only show one frame — that's fine; if you see ANY surface variation rather than a perfectly flat plane, success.

If the water appears black: depth_tex sampling probably returned something invalid. Apply the constant-depth fallback (T8.5 below).

If the water appears flat (no waves): the shader's vertex stage isn't running — likely a mesh issue. Check that water_mesh.tres has subdivisions from T7.

Stop the run.

- [ ] **Step 5 (optional): Commit**

```bash
git commit -am "feat(graphics-r1): water material now ShaderMaterial referencing wave shader"
```

---

### Task 8.5 (CONTINGENCY): constant-depth water fallback

**Use this fallback if ANY of these symptoms appear in T8 Step 2 or T9 Step 4:**
- Shader compile error citing `INV_PROJECTION_MATRIX`, `hint_depth_texture`, `depth_prepass_alpha`, or `depth_tex`.
- Water renders as solid black (and swapping the cross order in the vertex stage didn't fix it).
- Water color does not vary with distance from shore (uniformly tinted regardless of seabed depth).
- Editor / game logs show errors from the depth-texture sampling path.

If none of these trigger, skip this task and proceed to T10.

**Files:**
- Modify (via Edit): `res://scenes/water_waves.gdshader`

- [ ] **Step 1: Edit the fragment stage's depth math**

In `water_waves.gdshader`, find this block in `void fragment()`:

```glsl
	float depth_raw = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth_raw);
	vec4 view_h = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	float seabed_view_z = view_h.z / view_h.w;
	float water_view_z = VERTEX.z;
	float underwater_distance = abs(seabed_view_z - water_view_z);
```

Replace with:

```glsl
	float underwater_distance = depth_falloff * 0.5;  // constant-depth fallback
```

Also remove the `uniform sampler2D depth_tex` declaration (it's now unused) to avoid Godot warnings, and remove `depth_prepass_alpha` from `render_mode` (no longer needed without depth reads):

```glsl
render_mode blend_mix, cull_back;
```

- [ ] **Step 2: Reimport, run, verify**

```
mcp__godot-ai__filesystem_manage op="reimport" params={"paths": ["res://scenes/water_waves.gdshader"]}
mcp__godot-ai__project_run params={"autosave": false}
mcp__godot-ai__editor_screenshot source="game" max_resolution=1000
```

Expected: water renders with a single mid-depth color (`mix(shallow, deep, 0.5)`), still has waves and fresnel reflection of sky. Looks decent, just no shallow/deep variation.

---

### Task 10: Wire up the water — VoxelViewer parent + init script

**Files:**
- Create: `res://scripts/water_init.gd`
- Modify (via MCP): `res://scenes/main.tscn` (attach script + bind `Water.material_override` is unchanged — the existing reference still points at the rewritten water_material.tres)

**Goal:** At runtime, write `Atmosphere.HAZE_COLOR` into the water shader's `sky_color` uniform so the water reflects the same haze color as the sky/fog. The .tres files all carry the same default value, so this script is for "if you change `Atmosphere.HAZE_COLOR`, the water updates without re-saving the material."

- [ ] **Step 1: Write `water_init.gd`**

Create `C:\Users\whann\Documents\mine-co\scripts\water_init.gd`:

```gdscript
extends MeshInstance3D

func _ready() -> void:
	var mat: ShaderMaterial = material_override as ShaderMaterial
	if mat == null:
		push_warning("water_init: material_override is not a ShaderMaterial")
		return
	mat.set_shader_parameter("sky_color", Atmosphere.HAZE_COLOR)
```

- [ ] **Step 2: Attach to `/Main/Water`**

```
mcp__godot-ai__script_attach params={"path": "/Main/Water", "script_path": "res://scripts/water_init.gd"}
```

- [ ] **Step 3: Refresh `/Main/Water`'s material reference + save scene**

The editor may still hold a stale in-memory `material_override` from when the file on disk was a `StandardMaterial3D`. Force-refresh by re-assigning the same path through MCP:

```
mcp__godot-ai__node_set_property params={"path": "/Main/Water", "property": "material_override", "value": "res://scenes/water_material.tres"}
mcp__godot-ai__scene_save
```

The set-property re-loads the resource from disk (now a `ShaderMaterial`) into the in-memory scene model. If the response value is null instead of the path, the editor refused — see T2 Step 5 disk-edit fallback (same problem, same recovery).

- [ ] **Step 4: Run + verify**

```
mcp__godot-ai__project_run params={"autosave": false}
mcp__godot-ai__editor_screenshot source="game" max_resolution=1000
```

Expected: same visual as end of T9 — confirms the script doesn't break anything. (The sky_color value is the same as the .tres default, so behavior is identical; we're paying for runtime push so future tweaks of HAZE_COLOR propagate.)

Verify the script ran by checking game logs:

```
mcp__godot-ai__logs_read source="game" count=50
```

Expected: no `water_init: material_override is not a ShaderMaterial` warning. If you see that warning, the material reassignment from T9 didn't take in main.tscn — re-do T9 step 4 verification.

Stop the run.

- [ ] **Step 5 (optional): Commit**

```bash
git add scripts/water_init.gd scenes/main.tscn
git commit -m "feat(graphics-r1): water init script binds Atmosphere.HAZE_COLOR to shader at runtime"
```

---

### Task 11: Walkthrough + tune

**Files:**
- Modify (potentially): `scenes/environment.tres`, `scenes/sky_material.tres`, `scenes/water_material.tres`, `scenes/water_waves.gdshader`

**Goal:** Walk the island. Observe the atmosphere as a whole. Tune any knob that doesn't read right. Confirm success criteria from the spec.

- [ ] **Step 1: Run and walk for 2-3 minutes**

```
mcp__godot-ai__project_run params={"autosave": false}
```

Switch to the game window. Walk with WASD; look around with mouse. Check:
- Distant terrain fades to haze (not sharp like a wall, not invisible).
- Sky and ground meet in a seamless gray-white blur — no horizon line.
- Sun is a soft pale region of the sky, not a hard white dot.
- Water has gentle visible motion (slow waves), color varies between shallow-near-shore (teal) and deeper (blue-gray) [unless using constant-depth fallback], reflects sky at grazing angles.
- Terrain colors are still recognizably sand and grass — not washed out beyond recognition.

- [ ] **Step 2: Tune fog density if needed**

If the world feels too clear (you can see crisp detail at 250m+), bump `fog_density` from 0.004 to 0.006 in `environment.tres`, reimport, re-run.

If the world feels too murky (you can barely see the island contours from anywhere), drop `fog_density` to 0.0025.

- [ ] **Step 3: Tune water amplitudes if needed**

Default wave amplitudes (0.15, 0.08, 0.05 m) are gentle. If waves look too tame: bump to (0.25, 0.15, 0.08). If waves look choppy/jarring: drop to (0.10, 0.05, 0.03). Edit `scenes/water_material.tres` shader_parameter values, reimport.

- [ ] **Step 4: Tune sun visibility if needed**

If the sun has become entirely invisible against the haze: raise `sun_angle_max` from 10 → 18, OR drop `sun_curve` from 0.3 → 0.15 in `sky_material.tres`.

- [ ] **Step 5: Confirm success criteria from spec**

- [ ] Vibe is unmistakably hazy/atmospheric. ✓
- [ ] Distant edges of island fade to soft gray. ✓
- [ ] Horizon between sky and ground is invisible. ✓
- [ ] Sun is a soft suggestion. ✓
- [ ] Water has visible gentle motion. ✓
- [ ] Water color varies (or uniform mid-depth if fallback). ✓
- [ ] Frame rate stays solid. ✓
- [ ] Terrain still reads as sand and grass. ✓

- [ ] **Step 6 (optional): Final commit + announce v1 of Round 1 done**

```bash
git commit -am "feat(graphics-r1): final tune"
```

Report to user: scene now has hazy Death-Stranding atmosphere, water has Gerstner waves, lighting and tonemap are tuned. Note any contingencies that activated (e.g., constant-depth water fallback) and what the natural next steps are (Round 2: grass / rocks / trees).

---

## Notes for the implementer

- **MCP tool names** in this plan use the `mcp__godot-ai__<tool>` form. The exact tool name surface and parameter shape may differ slightly from what's pinned here; treat the calls as intent specifications and adapt to the actual tool schema you're given.
- **autosave: false in project_run** — always pass this. Without it, the editor's stale in-memory scene state will overwrite our disk edits between tasks.
- **The editor's main.tscn cache** is the recurring antagonist. For property changes on existing nodes, ALWAYS use MCP `node_set_property` followed by `scene_save`, NOT a disk `Edit` of main.tscn. The .tres files we're externalizing in T2 are immune to this problem.
- **Don't add features not in the spec.** No clouds, no foam, no SSAO. v1 of this round is "atmosphere only."
- **Property name uncertainty for water_mesh**: `subdivide_width` vs `subdivide_w` — try the long form first, switch to short if needed (T7 covers both).
- **Depth texture failure mode** is well-known on Forward+; the contingency T8.5 is your escape hatch and should not be considered "giving up." It produces a respectable result.
