extends SceneTree

const Surface = preload("res://scripts/cloth_surface_proxy.gd")
const Contact = preload("res://scripts/cloth_body_contact.gd")
var checks := 0
var failures: Array[String] = []


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)


func _initialize() -> void:
	var surface := Surface.new()
	surface.centers.resize(12)
	surface.across.resize(12)
	surface.depth.resize(12)
	for i in 6:
		surface.centers[i] = Vector4(0, float(i) * .2, 0, 1)
		surface.across[i] = Vector4(.3, 0, 0, 0)
		surface.depth[i] = Vector4(0, 0, .2, 0)
	for angle in 48:
		var theta := TAU * angle / 48.0
		var point := Vector3(sin(theta) * .22, .51, cos(theta) * .12)
		var fitted: Vector3 = surface.project(point, .02)
		check(fitted.is_finite(), "Nonfinite surface correction")
		check(Vector2(fitted.x / .3, fitted.z / .2).length() > 1.05, "Layer did not leave the inner garment")
		check(surface.project(fitted, .02).distance_to(fitted) < .00001, "Surface contact is not stable")
	check(surface.project(Vector3(.8, .5, 0), .02) == Vector3(.8, .5, 0), "Uncontacted cloth moved")
	check(surface.project(Vector3(.1, 1.2, 0), .02) == Vector3(.1, 1.2, 0), "Open hem became an end cap")
	var contact := Contact.new()
	contact.bone_names = ["Hips"]
	contact.ends_a = PackedVector4Array([Vector4(0, 0, 0, .2)])
	contact.ends_b = PackedVector4Array([Vector4(0, 1, 0, .2)])
	contact.settings = PackedVector4Array([Vector4(1, 0, 0, 0)])
	contact.to_pose = [Transform3D.IDENTITY]
	contact.to_rest = [Transform3D.IDENTITY]
	var from_wrong_side := Vector3(-.05, .5, 0)
	var corrected: Vector3 = contact.project(from_wrong_side, .01, false, Vector3.RIGHT)
	check(corrected.x > .209, "Skirt exited toward the gap between legs instead of its outside")
	check(absf(corrected.y - .5) < .00001, "Directional contact moved the pin longitudinally")
	print("CLOTH_SURFACE_CONTACT checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
