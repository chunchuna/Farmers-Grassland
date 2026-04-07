shader_type canvas_item;

// PSX-style pixelation post-processing shader
// Reduces the apparent resolution to create a retro low-res look
// commonly seen in indie horror games (PS1/PSX aesthetic)

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform int pixel_size : hint_range(1, 16, 1) = 3;
uniform float color_depth : hint_range(2.0, 256.0, 1.0) = 32.0;
uniform float dither_strength : hint_range(0.0, 1.0, 0.01) = 0.05;

void fragment() {
	vec2 screen_size = vec2(textureSize(screen_tex, 0));
	float ps = float(pixel_size);

	// Snap SCREEN_UV to pixel grid
	vec2 snapped_uv = floor(SCREEN_UV * screen_size / ps) * ps / screen_size;

	vec4 col = texture(screen_tex, snapped_uv);

	// Optional: reduce color depth for more retro feel
	if (color_depth < 256.0) {
		col.rgb = floor(col.rgb * color_depth + 0.5) / color_depth;
	}

	// Optional: simple ordered dither (Bayer 2x2)
	if (dither_strength > 0.0) {
		vec2 pixel_pos = floor(SCREEN_UV * screen_size / ps);
		float bayer = mod(pixel_pos.x + pixel_pos.y * 2.0, 4.0) / 4.0 - 0.5;
		col.rgb += bayer * dither_strength / color_depth;
	}

	COLOR = col;
}
