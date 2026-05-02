# Mine Co. — Graphics Pass Round 1: Atmosphere

**Date:** 2026-05-01
**Project:** Mine Co. (Godot 4.6 module build with Voxel Tools 1.6, Forward+, D3D12)
**Status:** Approved by user, ready for implementation plan
**Reference image:** Death Stranding screenshot — hazy/overcast atmosphere, distance fades to misty white-gray, soft diffuse light, calm but visible water

## Goal

Transform the look of the existing v1 island from "neutral test scene" to a hazy, atmospheric Death-Stranding-flavored aesthetic — without touching terrain shape, decoration, or game logic. This is the first of three planned graphics passes:

- **Round 1 (this spec):** atmosphere — lighting, sky, fog, water polish
- **Round 2 (separate spec, later):** decoration — grass, rocks, trees
- **Round 3 (if needed):** wind, foam, polish details

These three rounds intentionally split because they have different perf characteristics, different failure modes, and benefit from being seen sequentially (Round 1 changes how Round 2 colors should be tuned).

## Non-goals (this round)

Distinct clouds (cloud "smudges" or volumetrics), grass / rocks / trees, day/night cycle, weather variations, foam at shoreline, animated wind on terrain, screen-space reflections, SSAO, glow/bloom. All explicitly parked for later rounds — adding them now expands scope and obscures whether the atmosphere itself is right.

## Architecture overview

Five independent tweaks composed via the existing `WorldEnvironment` and `Sun` nodes plus a new water shader:

1. **Lighting** — retune `Sun` (DirectionalLight3D) for softer, cooler diffuse feel; raise `WorldEnvironment` ambient.
2. **Sky** — retune the existing `ProceduralSkyMaterial` colors so sky and horizon read as hazy.
3. **Fog** — enable exponential fog on the `Environment` resource; pick density that fades distant terrain to sky color over ~120–250m.
4. **Tonemap** — switch to filmic tonemap on `Environment`; under-expose slightly for muted feel.
5. **Water** — replace the current `StandardMaterial3D` (with emission hack) with a `ShaderMaterial` doing Gerstner waves, fresnel, and depth-based color.

Each is a small, targeted change. Nothing else in the project changes.

## Project structure changes

```
res://
  scenes/
    main.tscn                  — modified: Sun, WorldEnvironment, Water mesh subdivisions
    water_material.tres        — REWRITTEN IN PLACE (same path; type changes from StandardMaterial3D to ShaderMaterial). Keep same path so main.tscn's ext_resource UID doesn't churn.
    water_mesh.tres            — modified: subdivide_w / subdivide_d bumped to 80
    water_waves.gdshader       — NEW: Gerstner waves + fresnel + depth-based color
  scripts/
    atmosphere.gd              — NEW: autoload constants (the single source of truth for the haze color and any other cross-component values).
  project.godot                — modified: register Atmosphere autoload
```

No new folders. Spec lives in `docs/superpowers/specs/`. No spec changes to the v1 design document.

### Single source of truth: `atmosphere.gd`

Four places need to share the haze color: sky's `horizon_color`, sky's `ground_horizon_color`, environment's `fog_light_color`, and the water shader's `sky_color` uniform. To avoid drift when tuning, introduce an autoload:

```gdscript
extends Node

const HAZE_COLOR: Color = Color(0.85, 0.87, 0.90)
```

Wire `Atmosphere` as an autoload in `project.godot` (`autoload/Atmosphere = "*res://scripts/atmosphere.gd"`). Where the value is settable in inspector (sky/environment), the implementer puts the literal `(0.85, 0.87, 0.90)` and adds a one-line comment `# matches Atmosphere.HAZE_COLOR`. The water shader receives the value from a tiny init script on the Water node:

```gdscript
extends MeshInstance3D
func _ready() -> void:
    var mat: ShaderMaterial = material_override as ShaderMaterial
    mat.set_shader_parameter("sky_color", Atmosphere.HAZE_COLOR)
```

This keeps the *runtime* source of truth in code (one place to edit) while still letting the editor preview the static colors.

## Component: Lighting

Retune the existing `Sun` (DirectionalLight3D) and `WorldEnvironment.environment` resource. No new nodes.

**Sun changes:**
- `light_energy`: 1.0 → **0.7**
- `light_color`: `Color(1, 0.96, 0.88)` → `Color(0.95, 0.97, 1.0)` (slight cool tint)
- `shadow_enabled`: stays `true`
- `shadow_blur` (`Light3D.shadow_blur`, default 1.0): → **2.0** (softer shadow edges, reads as diffuse light)
- `shadow_bias`: default `0.1` left untouched unless we see acne; if we do, raise to 0.2
- Rotation unchanged

**Ambient (on `Environment`):**
- `ambient_light_source`: set to `Sky` — enum value `3` (NOT 2 — value 2 is `COLOR`, which would ignore the sky entirely; v1 mistakenly used 2)
- `ambient_light_energy`: scene currently overrides Godot's default of `1.0` to `0.3`; raise our override to **0.6** (lifts shadows so they're not pure black under the diffuse light)
- `ambient_light_sky_contribution`: stays default `1.0`

## Component: Sky

Retune the existing `ProceduralSkyMaterial` resource (currently using all defaults). New values (note: properties on `ProceduralSkyMaterial` are named without the `_color` suffix — `sky_top_color` is just `sky_top_color`, but `horizon_color` is `sky_horizon_color`. The exact property names below are verified against Godot 4.6):

- `sky_top_color`: default → `Color(0.55, 0.65, 0.75)` — desaturated pale blue, not vivid
- `sky_horizon_color`: default → `Color(0.85, 0.87, 0.90)` — very pale gray-white (`Atmosphere.HAZE_COLOR`)
- `ground_horizon_color`: same as `sky_horizon_color` so the procedural-sky ground transition disappears into the haze (`Atmosphere.HAZE_COLOR`)
- `ground_bottom_color`: default → `Color(0.45, 0.50, 0.55)` — muted blue-gray
- `sun_angle_max`: default 30.0 → **10.0** — shrinks the sun disk so it doesn't dominate the hazy sky. (Note: `sun_disk_scale` is NOT a real property on `ProceduralSkyMaterial`; this is the correct knob to make the sun smaller.)
- `sun_curve`: default 0.15 → **0.3** — softer falloff at the disk edge so the sun reads as a diffuse glow rather than a hard ball.

These values establish the "hazy sky" — the next sections (fog, water) all reference `Atmosphere.HAZE_COLOR` so the atmosphere reads as cohesive.

## Component: Fog

This is the single highest-impact change. Enables on `Environment`:

- `fog_enabled`: false → **true**
- `fog_mode`: stays default exponential (value `0` = `FOG_MODE_EXPONENTIAL`)
- `fog_density`: default `0.01` → **0.004** — looser fog than default, tuned for our 300m island scale; expect to land between 0.003 and 0.006 in playtest
- `fog_light_color`: `Atmosphere.HAZE_COLOR` `Color(0.85, 0.87, 0.90)`
- `fog_light_energy`: 1.0 (default)
- `fog_sun_scatter`: 0.0 (default; would add a sun glare halo if raised — we want flat misty look)
- Height fog: leave `fog_height_density` at default `0.0` — no height-based component for v1. (Note: `fog_height_enabled` is NOT a real property; height fog is gated by `fog_height_density != 0.0`.)
- `fog_aerial_perspective`: **0.5** — gives distant geometry the sky tint, the classic "mountains fade to white-gray" effect
- `fog_sky_affect`: **1.0** — sky and fog blend seamlessly at the horizon (no visible horizon line)

Fog density tuning notes for the implementer: at 0.004, transmittance at 100m is ≈ 0.67, at 250m ≈ 0.37, at 500m ≈ 0.14. Our island is ~300m, so the far edge fades meaningfully but stays visible. If it feels under-foggy in the build, raise to 0.006; if over-foggy, drop to 0.0025.

## Component: Tonemap

`Environment` settings:

- `tonemap_mode`: `TONE_MAPPER_LINEAR` (default) → **`TONE_MAPPER_FILMIC`** (value `2`). Softer rolloff in highlights, fits the muted look.
- `tonemap_exposure`: stays 1.0
- `tonemap_white`: 1.0 → **2.5** — modestly wider luminance range so the bright sky doesn't clip and the highlights have room to breathe. (We considered 6.0 but it crushes mid-grays too much; 2.5 is a calmer starting point. Tune in playtest if highlights still clip.)
- No glow, SSAO, SSR, SSIL, adjustments — explicitly off for v1 to keep look intentional and perf cheap.

## Component: Water — Gerstner waves + fresnel + depth

Three coupled parts: mesh subdivision, the shader, the material.

### Mesh: `water_mesh.tres`

Existing `PlaneMesh` 400×400m. Bumped subdivision:
- `subdivide_w`: 0 → **80**
- `subdivide_d`: 0 → **80**

That's 81×81 = ~6.6k vertices. At our 400m water plane, that's 5m vertex spacing — enough resolution for waves with 4–12m wavelengths to look continuous, not enough to dent the GPU.

### Shader: `scenes/water_waves.gdshader`

```
shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_back;
```

`blend_mix` is the default but we state it explicitly. `depth_prepass_alpha` makes our transparent-due-to-`ALPHA`-write material write to the depth buffer in a prepass — required for clean self-depth-testing and stable depth reads of opaque geometry behind the water. `cull_back` is fine because the player can't go underwater.

**Required uniforms at the top of the shader:**

```glsl
uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;
```

This is how Godot 4 exposes the depth texture — there is NO built-in `DEPTH_TEXTURE` like in some older docs. The `hint_depth_texture` hint is required.

**Vertex stage:**
- Sum 3 Gerstner waves at the input vertex (x, z) position. Each wave has its own direction, wavelength, amplitude, speed. Standard Gerstner formula produces (dx, dy, dz) displacement and a recomputed normal.
- Apply displacement to `VERTEX` (model space) so the world position is offset.
- Compute the world-space normal from the wave-derivatives, then convert to view space and write to `NORMAL` directly (Godot accepts view-space normal in vertex stage; no varying needed for lighting). Output `world_pos` as a varying for the fragment stage's depth math.

**Fragment stage:**
- View-direction-vs-normal computation: use `VIEW` (view-space, normalized, points TOWARD the camera in fragment) dotted with `NORMAL` (view-space, since vertex stage already converted). `fresnel = pow(1.0 - clamp(dot(VIEW, NORMAL), 0.0, 1.0), 5.0)`. View-flat = 0 (see through), view-grazing = 1 (reflect).
- Linear depth read for seabed:
  ```glsl
  float depth_raw = textureLod(depth_tex, SCREEN_UV, 0.0).r;
  vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth_raw);
  vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
  float seabed_view_z = view.z / view.w;
  float water_view_z = VERTEX.z; // VERTEX in fragment is view space
  float underwater_distance = abs(seabed_view_z - water_view_z);
  ```
- `albedo = mix(shallow_color, deep_color, smoothstep(0.0, depth_falloff, underwater_distance))`. Tunables: `shallow_color = (0.4, 0.7, 0.7)` teal, `deep_color = (0.15, 0.25, 0.4)` muted blue-gray, `depth_falloff = 4.0` meters.
- Sky tint via `sky_color` uniform (set at runtime from `Atmosphere.HAZE_COLOR`).
- Final: `ALBEDO = mix(albedo, sky_color, fresnel)`.
- Alpha: `ALPHA = mix(0.6, 1.0, fresnel)` — see-through when looking down, opaque at grazing angles. Writing to ALPHA makes the material transparent automatically; combined with `blend_mix` (default) and `depth_prepass_alpha` we get correct sorting and depth.
- `ROUGHNESS = 0.05`; `METALLIC = 0.0`; `SPECULAR = 0.5`. Smooth surface so the directional light's specular is visible on wave faces — a hint of glistening. The contrast with the matte terrain (`SPECULAR = 0`) is intentional: water *is* the one specular surface in the scene.

The shader is roughly 80 lines. Full source goes in the implementation plan.

**Depth-blend fallback** (pre-stated for the implementer, in case depth reads return garbage on this Forward+/D3D12 build): replace the depth math with `float underwater_distance = depth_falloff * 0.5;` (constant mid-depth). Loses the shallow-near-shore color contrast but gives a respectable single-color water surface that still reflects the sky correctly. This is a cheap fallback, NOT a polish exercise — the implementer should use it without further escalation if the depth path doesn't produce sensible numbers in playtest.

### Material: `scenes/water_material.tres`

Replace the current `StandardMaterial3D` (with emission hack) with a `ShaderMaterial` referencing `water_waves.gdshader`. Exposed `shader_parameter` uniforms with sane defaults:

- `wave_dir_1`, `wave_dir_2`, `wave_dir_3`: `Vector2` — wave directions (normalized). Defaults: `(1, 0)`, `(0.7, 0.7)`, `(0.3, -0.95)`.
- `wave_wavelength_1/2/3`: floats — `12.0, 7.0, 4.0`.
- `wave_amplitude_1/2/3`: floats — `0.15, 0.08, 0.05`.
- `wave_speed_1/2/3`: floats — `0.4, 0.55, 0.7`.
- `shallow_color: Color` — `(0.4, 0.7, 0.7, 1)`.
- `deep_color: Color` — `(0.15, 0.25, 0.4, 1)`.
- `sky_color: Color` — `(0.85, 0.87, 0.90, 1)` (must match fog_light_color).
- `depth_falloff: float` — `4.0`.

## Risks and open questions

1. **Depth-texture availability on Forward+ / D3D12** — sampling depth requires the water shader to render after opaque geometry, with depth available. The `hint_depth_texture` uniform + `depth_prepass_alpha` render mode are the documented Godot 4 path. **Mitigation already baked into the spec:** the water-shader section names a constant-depth fallback the implementer can ship without escalation if depth reads look wrong.

2. **Fog density at 300m scale** — most fog tutorials assume km-scale scenes. 0.004 is a defensible starting point (transmittance ≈ 0.30 at 300m) but expect 1–2 retunes. Build will look wrong fast if it's off by an order of magnitude — the mitigation is just iteration, not a structural change.

3. **Procedural sky horizon line** — even with `fog_sky_affect = 1.0`, if `ground_horizon_color` ≠ `sky_horizon_color`, you can see a faint band at y=0. Both pinned to `Atmosphere.HAZE_COLOR`; flagging in case the implementer changes one and forgets the other.

4. **Sun visibility with fog** — `fog_sky_affect = 1.0` will fog the sun disk. Sun is shrunk via `sun_angle_max = 10.0` and softened via `sun_curve = 0.3`. If the sun becomes effectively invisible (no hint of where it is in the sky), that's a regression — implementer can raise `sun_angle_max` back toward 20 in playtest. We *want* the sun barely-visible, not entirely-invisible.

5. **Per-vertex Gerstner cost** — ~6.6k verts × 3 waves per frame is fine on modern GPUs but worth measuring. If the perf hit is unexpectedly high, drop to 2 waves first, then bump down subdivisions to 40×40. Visual impact of fewer waves is significant; visual impact of fewer subdivisions is less so for our 5m wavelengths.

6. **Shader-space consistency** — the water shader uses `VIEW` (view-space, fragment built-in) dotted with `NORMAL` (view-space, since vertex stage writes view-space normal). Both must be in the SAME space for fresnel to be correct. The shader code in the implementation plan must show the conversion explicitly so future maintainers don't accidentally pass a world-space normal varying alongside `VIEW` and silently break fresnel.

## Implementation guidance — the editor-cache trap

In v1 we hit a recurring bug: editor's in-memory copy of `main.tscn` overrides disk on save, so disk edits to scene properties get clobbered. For this round, the plan should:

- Make all `Sun` and `Environment` property changes via MCP `node_set_property` while `main.tscn` is loaded in the editor, then `scene_save`. Do NOT hand-edit `main.tscn` for property tweaks on existing nodes.
- For NEW assets (`atmosphere.gd`, `water_waves.gdshader`, the rewritten `water_material.tres`), write directly to disk; these are not "in-memory" until the editor's resource cache loads them, which it does fresh on first reference.
- For modifying `water_mesh.tres` (changing subdivide_w/d on the existing PlaneMesh resource): MCP route via `resource_manage` if available, or write the .tres directly since this resource is loaded via `ext_resource` and the editor doesn't keep a writable in-memory representation of it that could clobber.
- After `project.godot` autoload edit, ask the user to do **Project → Reload Current Project** to load the autoload — same as the v1 input-map flow.

## Out of scope (parked for later rounds)

- Foam ring at shoreline (Round 3)
- Volumetric fog / volumetric clouds (deliberately not done — perf cost vs visual gain bad at our scale)
- Bloom / glow (would clash with the muted aesthetic)
- SSAO / SSIL (terrain shader is unlit-feeling enough that ambient occlusion won't add much)
- Day/night cycle (separate feature, big enough for its own design)
- Water displacement responding to player position (immersion — Round 3+)
- Underwater post-process effect (out of scope; player can't go underwater anyway in current build)

## Success criteria

When this round ships:

- Open `main.tscn`, press F5, look around. The vibe is unmistakably hazy/atmospheric. Distant edges of the island fade to soft gray. Nothing punches out as overly bright or overly dark.
- The horizon between sky and ground is invisible — they blend.
- The sun is a soft suggestion in the sky, not a punch.
- Water has visible gentle motion (waves), shows the sandy seabed in shallow areas near shore, fades to deeper blue-gray further out, and reflects sky color at grazing angles. No black water, no flat-uniform-color water.
- Frame rate stays solid (no chugging) on the existing target hardware.
- The terrain colors we already have still read as sand-and-grass — they shouldn't shift unrecognizably under the new lighting.
