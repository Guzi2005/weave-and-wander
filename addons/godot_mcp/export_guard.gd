@tool
extends EditorExportPlugin
func _get_name() -> String: return "GodotMcpExportExclusion"
func _export_file(path: String, _type: String, _features: PackedStringArray) -> void:
    if path.begins_with("res://addons/godot_mcp/"): skip()
