shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, specular_schlick_ggx;

// Water colors
uniform vec3 water_color_shallow : source_color = vec3(0.15, 0.45, 0.42);
uniform vec3 water_color_deep : source_color = vec3(0.05, 0.15, 0.25);
uniform float color_depth : hint_range(0.5, 10.0) = 3.0;

// Transparency
uniform float water_alpha : hint_range(0.0, 1.0) = 0.75;

// Wave parameters
uniform float wave_speed : hint_range(0.0, 3.0) = 0.6;
uniform float wave_scale : hint_range(0.01, 1.0) = 0.15;
uniform float wave_height : hint_range(0.0, 1.0) = 0.08;

// Flow direction (for rivers)
uniform vec2 flow_direction = vec2(1.0, 0.0);
uniform float flow_speed : hint_range(0.0, 3.0) = 0.4;

// Surface detail
uniform float ripple_scale : hint_range(1.0, 50.0) = 12.0;
uniform float foam_amount : hint_range(0.0, 1.0) = 0.15;

// Specular
uniform float roughness : hint_range(0.0, 1.0) = 0.05;
uniform float metallic : hint_range(0.0, 1.0) = 0.3;

// Simple hash
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

// FBM 4 octaves
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	mat2 rot = mat2(vec2(0.8, -0.6), vec2(0.6, 0.8));
	for (int i = 0; i < 4; i++) {
		v += a * value_noise(p);
		p = rot * p * 2.0 + vec2(100.0);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Gentle wave displacement
	float wave1 = sin(world_pos.x * 2.0 + TIME * wave_speed) *
	              cos(world_pos.z * 1.5 + TIME * wave_speed * 0.8);
	float wave2 = sin(world_pos.x * 3.5 + world_pos.z * 2.5 + TIME * wave_speed * 1.3) * 0.5;
	VERTEX.y += (wave1 + wave2) * wave_height;
}

void fragment() {
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// Flow offset
	vec2 flow = normalize(flow_direction) * flow_speed * TIME;

	// Two layers of moving ripples for realistic water
	vec2 uv1 = world_pos.xz * wave_scale + flow;
	vec2 uv2 = world_pos.xz * wave_scale * 0.7 - flow * 0.6 + vec2(43.0, 17.0);

	float ripple1 = fbm(uv1 * ripple_scale);
	float ripple2 = fbm(uv2 * ripple_scale);
	float ripple = (ripple1 + ripple2) * 0.5;

	// Normal from ripples (fake)
	float eps = 0.05;
	float rx = fbm((uv1 + vec2(eps, 0.0)) * ripple_scale) - fbm((uv1 - vec2(eps, 0.0)) * ripple_scale);
	float rz = fbm((uv1 + vec2(0.0, eps)) * ripple_scale) - fbm((uv1 - vec2(0.0, eps)) * ripple_scale);
	vec3 ripple_normal = normalize(vec3(-rx * 2.0, 1.0, -rz * 2.0));

	// Fresnel effect — more opaque at glancing angles
	vec3 view_dir = normalize(VIEW);
	float fresnel = pow(1.0 - max(dot(ripple_normal, view_dir), 0.0), 3.0);
	fresnel = clamp(fresnel, 0.0, 1.0);

	// Color blend: shallow near edges, deep in center
	vec3 water_col = mix(water_color_shallow, water_color_deep, fresnel * 0.5 + ripple * 0.3);

	// Foam / white caps on ripple peaks
	float foam = smoothstep(0.55, 0.7, ripple) * foam_amount;
	water_col = mix(water_col, vec3(0.9, 0.95, 1.0), foam);

	// Subtle flow lines
	float flow_line = sin((world_pos.x * flow_direction.x + world_pos.z * flow_direction.y) * 8.0
	                      + TIME * flow_speed * 5.0) * 0.5 + 0.5;
	flow_line = smoothstep(0.7, 0.9, flow_line) * 0.08;
	water_col += vec3(flow_line);

	ALBEDO = water_col;
	ALPHA = clamp(water_alpha + fresnel * 0.2, 0.0, 0.95);
	ROUGHNESS = roughness;
	METALLIC = metallic;
	NORMAL = ripple_normal;
	SPECULAR = 0.5;
}
