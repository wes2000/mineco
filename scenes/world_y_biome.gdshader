shader_type spatial;
render_mode cull_disabled, diffuse_lambert;

uniform float water_level = 0.0;
uniform float sand_band = 1.2;
uniform vec3 sand_color : source_color = vec3(0.92, 0.85, 0.65);
uniform vec3 grass_color : source_color = vec3(0.35, 0.55, 0.25);

uniform sampler3D ore_noise;
uniform vec3 stone_color : source_color = vec3(0.45, 0.45, 0.50);
uniform vec3 iron_color : source_color = vec3(0.60, 0.50, 0.35);
uniform vec3 gold_color : source_color = vec3(0.85, 0.75, 0.30);
uniform float ore_iron_threshold = 0.3;
uniform float ore_gold_threshold = 0.8;
uniform float underground_blend_top_y = -0.5;
uniform float underground_blend_bottom_y = -3.0;
uniform vec3 ore_world_size = vec3(400.0, 200.0, 400.0);
uniform vec3 ore_world_origin = vec3(-200.0, -100.0, -200.0);

uniform float bump_strength : hint_range(0.0, 2.0) = 0.6;
uniform float bump_freq : hint_range(0.1, 5.0) = 1.0;
uniform float underground_darkness : hint_range(0.0, 1.0) = 0.6;
uniform float darkness_depth_meters : hint_range(1.0, 50.0) = 12.0;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.7;
uniform float rim_power : hint_range(1.0, 16.0) = 4.0;

varying vec3 world_pos;

float hash13(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash13(i + vec3(0,0,0)), hash13(i + vec3(1,0,0)), f.x),
		    mix(hash13(i + vec3(0,1,0)), hash13(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(hash13(i + vec3(0,0,1)), hash13(i + vec3(1,0,1)), f.x),
		    mix(hash13(i + vec3(0,1,1)), hash13(i + vec3(1,1,1)), f.x), f.y),
		f.z
	);
}

vec3 underground_color(vec3 wp) {
	vec3 uv = (wp - ore_world_origin) / ore_world_size;
	uv = clamp(uv, vec3(0.0), vec3(1.0));
	float n = texture(ore_noise, uv).r * 2.0 - 1.0;
	float t_iron = smoothstep(ore_iron_threshold, ore_iron_threshold + 0.3, n);
	float t_gold = smoothstep(ore_gold_threshold - 0.1, ore_gold_threshold + 0.1, n);
	vec3 c = mix(stone_color, iron_color, t_iron);
	c = mix(c, gold_color, t_gold);
	return c;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Surface biome (sand → grass)
	float t = clamp((world_pos.y - water_level) / sand_band, 0.0, 1.0);
	t = smoothstep(0.0, 1.0, t);
	vec3 surface = mix(sand_color, grass_color, t);

	// Underground biome (stone/iron/gold via 3D noise)
	float underground_t = 1.0 - smoothstep(underground_blend_bottom_y, underground_blend_top_y, world_pos.y);
	vec3 underground = underground_color(world_pos);
	vec3 albedo = mix(surface, underground, underground_t);

	// Underground darkening: deeper = darker
	float depth_below_top = max(0.0, underground_blend_top_y - world_pos.y);
	float darkness_t = clamp(depth_below_top / darkness_depth_meters, 0.0, 1.0);
	albedo *= mix(1.0, underground_darkness, darkness_t);

	// Flat shading: per-triangle normal from view-space VERTEX derivatives.
	// Compute fresh; ignore the interpolated NORMAL (which Transvoxel emits with
	// inconsistent winding for our voxel terrain).
	vec3 dx = dFdx(VERTEX);
	vec3 dy = dFdy(VERTEX);
	vec3 flat_normal = normalize(cross(dy, dx));

	// Rim/silhouette darkening: dot(flat_normal, view_dir). Fragments viewed at a
	// grazing angle (where the surface curves away from the camera) get darker, drawing
	// a soft black outline at object edges. View direction in view space is normalize(-VERTEX)
	// because VERTEX in fragment is view-space position; viewer is at origin, looking down -Z.
	float n_dot_v = max(0.0, dot(flat_normal, normalize(-VERTEX)));
	float rim = pow(1.0 - n_dot_v, rim_power);
	albedo *= mix(1.0, 1.0 - rim_strength, rim);

	ALBEDO = albedo;

	// 3D-noise bump perturbation underground (rocky texture).
	if (underground_t > 0.01 && bump_strength > 0.0) {
		vec3 bp = world_pos * bump_freq;
		float eps = 0.1;
		float n_xp = vnoise(bp + vec3(eps, 0.0, 0.0));
		float n_xn = vnoise(bp - vec3(eps, 0.0, 0.0));
		float n_yp = vnoise(bp + vec3(0.0, eps, 0.0));
		float n_yn = vnoise(bp - vec3(0.0, eps, 0.0));
		float n_zp = vnoise(bp + vec3(0.0, 0.0, eps));
		float n_zn = vnoise(bp - vec3(0.0, 0.0, eps));
		vec3 grad_world = vec3(n_xp - n_xn, n_yp - n_yn, n_zp - n_zn);

		vec3 flat_world = (INV_VIEW_MATRIX * vec4(flat_normal, 0.0)).xyz;
		vec3 perturbed_world = normalize(flat_world + grad_world * bump_strength * underground_t);
		flat_normal = (VIEW_MATRIX * vec4(perturbed_world, 0.0)).xyz;
	}

	NORMAL = flat_normal;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
}
