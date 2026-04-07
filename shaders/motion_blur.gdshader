shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform vec2 blur_velocity = vec2(0.0, 0.0);
uniform int samples : hint_range(2, 16) = 8;
uniform float intensity : hint_range(0.0, 1.0) = 0.5;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 vel = blur_velocity * intensity;

	vec4 result = vec4(0.0);
	float total_weight = 0.0;
	for (int i = 0; i < samples; i++) {
		float t = float(i) / float(samples - 1) - 0.5;
		vec2 sample_uv = uv + vel * t;
		sample_uv = clamp(sample_uv, vec2(0.0), vec2(1.0));
		float weight = 1.0 - abs(t) * 0.5;
		result += texture(screen_texture, sample_uv) * weight;
		total_weight += weight;
	}
	COLOR = result / total_weight;
}
