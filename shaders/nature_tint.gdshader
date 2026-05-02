shader_type spatial;
render_mode cull_disabled, diffuse_lambert;

uniform vec4 base_color : source_color = vec4(0.5, 0.6, 0.3, 1.0);
uniform float saturation : hint_range(0.0, 1.0) = 0.7;
uniform float haze_mix_strength : hint_range(0.0, 1.0) = 0.15;
uniform vec3 haze_color : source_color = vec3(0.85, 0.87, 0.90);

uniform float wind_strength : hint_range(0.0, 1.0) = 0.0;
uniform float wind_speed : hint_range(0.0, 5.0) = 1.5;
uniform vec2 wind_direction = vec2(1.0, 0.0);
uniform float wind_stiffness_height : hint_range(0.5, 5.0) = 2.0;

uniform float color_variation_amount : hint_range(0.0, 1.0) = 0.0;

float hash12(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void vertex() {
	if (wind_strength > 0.0) {
		vec3 instance_origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
		float gust = 0.7 + 0.3 * sin(TIME * 0.3);
		float phase = dot(instance_origin.xz, wind_direction) * 0.3 + TIME * wind_speed;
		float stiffness = smoothstep(0.0, wind_stiffness_height, VERTEX.y);
		float sway = sin(phase) * stiffness * wind_strength * gust;
		VERTEX.x += sway * wind_direction.x;
		VERTEX.z += sway * wind_direction.y;
	}
}

void fragment() {
	vec3 c = base_color.rgb;
	float l = dot(c, vec3(0.3, 0.59, 0.11));
	c = mix(vec3(l), c, saturation);
	c = mix(c, haze_color, haze_mix_strength);

	if (color_variation_amount > 0.0) {
		vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
		float v = hash12(floor(world_pos.xz * 4.0));
		c.g += (v - 0.5) * 0.20 * color_variation_amount;
		c.r += (v - 0.5) * 0.10 * color_variation_amount;
		c = clamp(c, vec3(0.0), vec3(1.0));
	}

	ALBEDO = c;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
}
