extends RefCounted


static func _project_path(path: String) -> String:
	var root := ProjectSettings.globalize_path("res://").replace("\\", "/").simplify_path().trim_suffix("/")
	var absolute := ProjectSettings.globalize_path(path).replace("\\", "/").simplify_path()
	if not absolute.to_lower().begins_with(root.to_lower() + "/"): return ""
	return "res://" + absolute.substr(root.length() + 1)


static func resolve(recorded: String, owner: String, expected_sha256: String) -> Dictionary:
	var result := {"recorded": recorded, "path": "", "rebased": false, "error": ""}
	var local_owner := _project_path(owner)
	if local_owner.is_empty() or recorded.is_empty() or expected_sha256.length() != 64:
		result.error = "Invalid project owner, reference or SHA256"
		return result
	var path := recorded.replace("\\", "/")
	if path.begins_with("res://"):
		path = _project_path(path)
	elif "://" in path:
		path = ""
	elif path.is_absolute_path():
		var localized := _project_path(path)
		if localized.is_empty():
			# Legacy proofs moved with their siblings. Never read the retired copy.
			localized = local_owner.get_base_dir().path_join(path.get_file())
			result.rebased = true
		path = _project_path(localized)
	else:
		path = _project_path(local_owner.get_base_dir().path_join(path))
	result.path = path
	if path.is_empty() or not FileAccess.file_exists(path):
		result.error = "Dependency is missing from the active project"
	elif FileAccess.get_sha256(path) != expected_sha256:
		result.error = "Active project dependency SHA256 mismatch"
	return result
