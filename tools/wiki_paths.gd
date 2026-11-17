extends RefCounted

## The Wiki is a sibling project, outside the Godot resource tree.
static func root_dir() -> String:
	return ProjectSettings.globalize_path("res://").path_join("../W&W Wiki").simplify_path()


static func public_assets_dir() -> String:
	return root_dir().path_join("public/assets")
