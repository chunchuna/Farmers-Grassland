shader_type spatial;

// Grass colors
uniform vec3 grass_color_valley : source_color = vec3(0.18, 0.42, 0.12);
uniform vec3 grass_color_peak : source_color = vec3(0.45, 0.65, 0.15);
uniform vec3 grass_color_dry : source_color = vec3(0.55, 0.52, 0.22);

// Terrain parameters
uniform float height_blend_range : hint_range(0.0, 30.0) = 12.0;
uniform float height_offset : hint_range(-20.0, 20.0) = 0.0;

// Detail noise for color variation
uniform float color_noise_scale : hint_range(0.001, 0.2) = 0.05;
uniform float color_noise_strength : hint_range(0.0, 1.0) = 0.3;

// Grass texture tiling
uniform float texture_scale : hint_range(0.1, 50.0) = 8.0;

// Roughness / specular
uniform float roughness : hint_range(0.0, 1.0) = 0.85;
uniform float specular_amount : hint_range(0.0, 1.0) = 0.15;

// Wind
uniform float wind_speed : hint_range(0.0, 5.0) = 0.8;
uniform float wind_strength : hint_range(0.0, 2.0) = 0.15;

// Simple hash for noise
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Value noise
float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);

	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));

	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Fractal noise (3 octaves)
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	vec2 shift = vec2(100.0);
	for (int i = 0; i < 3; i++) {
		v += a * value_noise(p);
		p = p * 2.0 + shift;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 world_normal = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;

	// Height-based blend: valley (low) vs peak (high)
	float h = (world_pos.y + height_offset) / height_blend_range;
	h = clamp(h, 0.0, 1.0);

	vec3 base_color = mix(grass_color_valley, grass_color_peak, h);

	// Add dry patches using noise
	float dry_noise = fbm(world_pos.xz * color_noise_scale);
	base_color = mix(base_color, grass_color_dry, dry_noise * color_noise_strength);

	// Slope-based darkening — steeper areas are slightly darker
	float slope = 1.0 - abs(world_normal.y);
	base_color *= mix(1.0, 0.7, slope * slope);

	// Fine grass-blade pattern using high-freq noise
	float grass_detail = fbm(world_pos.xz * texture_scale);
	base_color *= mix(0.85, 1.1, grass_detail);

	// Subtle wind-driven color shimmer
	float wind = sin(world_pos.x * 0.5 + TIME * wind_speed) *
	             cos(world_pos.z * 0.3 + TIME * wind_speed * 0.7);
	base_color += vec3(0.02, 0.04, 0.0) * wind * wind_strength;

	ALBEDO = clamp(base_color, vec3(0.0), vec3(1.0));
	ROUGHNESS = roughness;
	SPECULAR = specular_amount;
	NORMAL_MAP_DEPTH = 0.5;
}
