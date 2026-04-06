@tool
extends EditorPlugin

const DOCK_SCENE := preload("res://addons/character_importer/importer_dock.tscn")
var _dock: Control


func _enter_tree() -> void:
	_dock = DOCK_SCENE.instantiate()
	_dock.editor_plugin = self
	add_control_to_dock(EditorPlugin.DOCK_SLOT_RIGHT_UL, _dock)


func _exit_tree() -> void:
	if _dock:
		remove_control_from_docks(_dock)
		_dock.queue_free()
