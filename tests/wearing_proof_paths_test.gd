extends SceneTree

const Paths = preload("res://tests/experiments/wearing_proof_paths.gd")
var checks := 0
var failures: Array[String] = []


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)


func _initialize() -> void:
	var sha := FileAccess.get_sha256("res://project.godot")
	for recorded in ["res://project.godot", "project.godot", ProjectSettings.globalize_path("res://project.godot"), "Z:/retired/game/project.godot"]:
		var resolved: Dictionary = Paths.resolve(recorded, "res://proof.json", sha)
		_check(resolved.error.is_empty() and resolved.path == "res://project.godot", "Portable resolution: " + recorded)
	_check(Paths.resolve("Z:/retired/game/project.godot", "res://proof.json", sha).rebased, "Legacy relocation recorded")
	_check(not Paths.resolve("project.godot", "res://proof.json", "0".repeat(64)).error.is_empty(), "Hash mismatch rejected")
	_check(not Paths.resolve("Z:/retired/game/project.godot", "res://captures/proof.json", sha).error.is_empty(), "No retired-path fallback")
	for recorded in ["../outside.json", "res://../outside.json", "user://project.godot", "", "https://example.com/project.godot"]:
		_check(not Paths.resolve(recorded, "res://proof.json", sha).error.is_empty(), "Reject missing/outside reference: " + recorded)
	_check(not Paths.resolve("project.godot", "Z:/outside/proof.json", sha).error.is_empty(), "Outside owner rejected")
	_check(not Paths.resolve("project.godot", "res://proof.json", "").error.is_empty(), "Missing hash rejected")
	print("WEARING_PROOF_PATHS %s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL", checks, str(failures)])
	quit(0 if failures.is_empty() else 1)
