extends ColorRect

## PSX-style pixelation post-processing effect.
## Attach to a ColorRect that covers the full viewport inside a CanvasLayer.
## Adjustable via exported properties in the Inspector.

@export_range(1, 16, 1) var pixel_size: int = 3:
	set(val):
		pixel_size = val
		if material:
			(material as ShaderMaterial).set_shader_parameter("pixel_size", pixel_size)

@export_range(2.0, 256.0, 1.0) var color_depth: float = 32.0:
	set(val):
		color_depth = val
		if material:
			(material as ShaderMaterial).set_shader_parameter("color_depth", color_depth)

@export_range(0.0, 1.0, 0.01) var dither_strength: float = 0.05:
	set(val):
		dither_strength = val
		if material:
			(material as ShaderMaterial).set_shader_parameter("dither_strength", dither_strength)

@export var effect_enabled: bool = true:
	set(val):
		effect_enabled = val
		visible = effect_enabled


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Push initial values to shader
	if material:
		var mat := material as ShaderMaterial
		mat.set_shader_parameter("pixel_size", pixel_size)
		mat.set_shader_parameter("color_depth", color_depth)
		mat.set_shader_parameter("dither_strength", dither_strength)
