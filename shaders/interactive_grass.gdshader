shader_type spatial;
render_mode cull_disabled;

// Grass appearance
uniform vec3 grass_color_base : source_color = vec3(0.15, 0.38, 0.08);
uniform vec3 grass_color_tip : source_color = vec3(0.35, 0.6, 0.1);
uniform vec3 grass_color_dry : source_color = vec3(0.5, 0.48, 0.2);
uniform float color_variation : hint_range(0.0, 1.0) = 0.3;

// Grass geometry
uniform float grass_height : hint_range(0.1, 3.0) = 0.6;
uniform float grass_width : hint_range(0.01, 0.3) = 0.06;

// Wind
uniform float wind_speed : hint_range(0.0, 5.0) = 1.2;
uniform float wind_strength : hint_range(0.0, 1.0) = 0.3;
uniform vec2 wind_direction = vec2(1.0, 0.5);

// Player interaction - support up to 8 players
uniform vec3 player_positions[8];
uniform int player_count = 0;
uniform float push_radius : hint_range(0.5, 5.0) = 1.8;
uniform float push_strength : hint_range(0.0, 3.0) = 1.5;

// Simple hash
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	// Get instance transform to find world position of grass base
	vec3 world_pos = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;

	// Height factor: 0 at base, 1 at tip (using vertex Y)
	float height_factor = clamp(VERTEX.y / grass_height, 0.0, 1.0);

	// === Wind ===
	vec2 wind_dir = normalize(wind_direction);
	float wind_phase = dot(world_pos.xz, wind_dir) * 0.3 + TIME * wind_speed;
	float wind_wave = sin(wind_phase) * 0.5 + sin(wind_phase * 2.3 + 1.3) * 0.3;
	// Only bend upper part of blade
	float wind_bend = wind_wave * wind_strength * height_factor * height_factor;
	VERTEX.x += wind_bend * wind_dir.x;
	VERTEX.z += wind_bend * wind_dir.y;

	// === Player push ===
	for (int i = 0; i < 8; i++) {
		if (i >= player_count) break;
		vec3 player_pos = player_positions[i];
		vec2 diff = world_pos.xz - player_pos.xz;
		float dist = length(diff);
		if (dist < push_radius && dist > 0.01) {
			// Push direction: away from player
			vec2 push_dir = diff / dist;
			// Strength: strongest at center, falls off smoothly
			float push_t = 1.0 - (dist / push_radius);
			push_t = push_t * push_t; // quadratic falloff
			float push = push_t * push_strength * height_factor * height_factor;
			VERTEX.x += push_dir.x * push;
			VERTEX.z += push_dir.y * push;
			// Also push down slightly when heavily bent
			VERTEX.y -= push * 0.3 * height_factor;
		}
	}

	// Random per-instance slight tilt for natural look
	float tilt = hash(world_pos.xz) * 0.15;
	VERTEX.x += tilt * height_factor;
}

void fragment() {
	// Get world position for color variation
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// Base to tip gradient
	float tip_t = clamp(UV.y, 0.0, 1.0);
	vec3 col = mix(grass_color_base, grass_color_tip, tip_t);

	// Per-blade color variation using world position
	float var_noise = hash(floor(world_pos.xz * 2.0));
	col = mix(col, grass_color_dry, var_noise * color_variation);

	// Slight AO at base
	col *= mix(0.6, 1.0, tip_t);

	ALBEDO = col;
	ROUGHNESS = 0.85;
	SPECULAR = 0.1;

	// Subsurface scattering look: brighten when backlit
	if (!FRONT_FACING) {
		ALBEDO *= 1.3;
	}
}
