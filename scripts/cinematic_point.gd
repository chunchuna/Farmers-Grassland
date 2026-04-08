@tool
extends Resource
class_name CinematicPoint

## A single viewpoint in a cinematic sequence.

## Camera start position
@export var position: Vector3 = Vector3.ZERO
## Camera drift offset (camera moves from position to position + drift)
@export var drift: Vector3 = Vector3(0.3, 0.0, 0.3)
## Duration of this segment in seconds
@export var duration: float = 1.0
## FOV for this segment (0 = use default)
@export_range(0, 120, 1) var fov: float = 0.0
## Node path to look at (relative to the CinematicCamera's parent).
## If empty, uses the CinematicCamera's default look_at_target.
@export var look_at_node: NodePath = NodePath()
