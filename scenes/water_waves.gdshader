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

uniform vec3 foam_color : source_color = vec3(0.95, 0.97, 1.0);
uniform float foam_distance = 1.5;
uniform float foam_softness = 0.5;
uniform float foam_max_strength : hint_range(0.0, 1.0) = 0.7;

// Don't render water where the seabed is implausibly far below — i.e., over a mined shaft.
// Set to 0 to disable.
uniform float water_max_depth = 30.0;

// Heightmap of the island's natural surface. Where heightmap value > water_level + threshold,
// the terrain is naturally land — discard water there entirely so we don't render water over land
// (or in mined shafts that descended through it).
uniform sampler2D island_heightmap;
uniform vec2 heightmap_xz_origin = vec2(-200.0, -200.0);
uniform vec2 heightmap_xz_size = vec2(400.0, 400.0);
uniform float heightmap_y_min = -100.0;
uniform float heightmap_y_max = 100.0;
uniform float water_surface_y = 0.0;
uniform float land_clear_threshold = 0.5;  // metres above water_surface_y that count as "land"

varying vec3 world_pos;

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
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Discard water over natural land — the heightmap tells us the island's surface
	// elevation at this fragment's x,z. If terrain rises above water level here,
	// no water exists at this location.
	vec2 hmap_uv = (world_pos.xz - heightmap_xz_origin) / heightmap_xz_size;
	if (hmap_uv.x >= 0.0 && hmap_uv.x <= 1.0 && hmap_uv.y >= 0.0 && hmap_uv.y <= 1.0) {
		float h_norm = texture(island_heightmap, hmap_uv).r;
		float terrain_y = mix(heightmap_y_min, heightmap_y_max, h_norm);
		if (terrain_y > water_surface_y + land_clear_threshold) {
			discard;
		}
	}

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

	// Foam at shoreline — applied AFTER fresnel so it survives sky-tint at grazing angles
	float foam_t = smoothstep(foam_distance, foam_distance - foam_softness, underwater_distance);
	float n1 = sin(world_pos.x * 1.3 + TIME * 0.5) * sin(world_pos.z * 1.3 + TIME * 0.4);
	float n2 = sin(world_pos.x * 0.4 + TIME * 0.2) * sin(world_pos.z * 0.4 + TIME * 0.3);
	float foam_noise = (n1 * 0.6 + n2 * 0.4) * 0.5 + 0.5;
	foam_t *= mix(0.6, 1.0, foam_noise);
	ALBEDO = mix(ALBEDO, foam_color, foam_t * foam_max_strength);

	ALPHA = mix(0.6, 1.0, fresnel);
	ROUGHNESS = 0.05;
	METALLIC = 0.0;
	SPECULAR = 0.5;
}
