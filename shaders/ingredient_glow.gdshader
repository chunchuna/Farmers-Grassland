shader_type spatial;
render_mode blend_add, depth_draw_opaque, cull_back, unshaded;

uniform vec4 glow_color : source_color = vec4(0.3, 1.0, 0.3, 1.0);
uniform float glow_intensity : hint_range(0.0, 5.0, 0.1) = 2.0;
uniform float pulse_speed : hint_range(0.5, 5.0, 0.1) = 2.0;

void fragment() {
	float pulse = 0.4 + 0.6 * sin(TIME * pulse_speed);
	ALBEDO = glow_color.rgb * glow_intensity * pulse;
	ALPHA = pulse * 0.6;
}
