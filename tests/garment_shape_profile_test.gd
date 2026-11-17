extends SceneTree

const Profile = preload("res://components/garment_shape_profile.gd")
const ROWS := 64
const COLUMNS := 32
const EPSILON := 0.000002

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok and message not in failures:
		failures.append(message)
		if failures.size() <= 12: push_error(message)


func _constant(value: float) -> Curve:
	var curve := Curve.new()
	curve.min_value = minf(0.0, value)
	curve.max_value = maxf(1.0, value)
	curve.add_point(Vector2(0, value), 0, 0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	curve.add_point(Vector2(1, value), 0, 0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	return curve


func _curve_state(curve: Curve) -> PackedByteArray:
	var state: Array = [curve.min_value, curve.max_value, curve.min_domain, curve.max_domain, curve.bake_resolution]
	for index in curve.point_count:
		state.append([curve.get_point_position(index), curve.get_point_left_tangent(index),
			curve.get_point_right_tangent(index), curve.get_point_left_mode(index), curve.get_point_right_mode(index)])
	return var_to_bytes(state)


func _cone(rows := ROWS, columns := COLUMNS) -> PackedVector3Array:
	var points := PackedVector3Array()
	for row in rows + 1:
		var t := float(row) / rows
		for column in columns:
			var angle := TAU * column / columns
			var radius := 0.26 + t * 0.18
			points.append(Vector3(sin(angle) * radius, lerpf(1.31, 0.20, t), cos(angle) * radius))
	return points


func _bump(points: PackedVector3Array, index: int, amount: float) -> PackedVector3Array:
	var result := points.duplicate()
	var p := points[index]
	var direction := Vector2(p.x, p.z).normalized()
	result[index] += Vector3(direction.x, 0, direction.y) * amount
	return result


func _radius(point: Vector3) -> float:
	return Vector2(point.x, point.z).length()


func _near(a: PackedVector3Array, b: PackedVector3Array) -> bool:
	if a.size() != b.size(): return false
	for index in a.size():
		if a[index].distance_to(b[index]) > EPSILON: return false
	return true


func _identity_and_locality() -> void:
	var profile := Profile.new()
	var original := _cone()
	var peak := (ROWS / 2) * COLUMNS
	var fitted := _bump(original, peak, 0.06)
	var original_bytes := var_to_bytes(original)
	var fitted_bytes := var_to_bytes(fitted)
	_check(profile.enabled and profile.root_height == 1.31 and profile.hem_height == 0.20 and profile.contour_span == 0.16, "Defaults changed")
	_check(is_zero_approx(profile.contour_strength.sample(0)) and is_equal_approx(profile.contour_strength.sample(0.15), 1) \
		and is_equal_approx(profile.contour_strength.sample(0.9), 1), "Default strength curve changed")
	_check(profile.fit(original, original) == original, "Default profile expanded an unchanged silhouette")
	var output := profile.fit(original, fitted)
	_check(_radius(output[peak + COLUMNS]) > _radius(fitted[peak + COLUMNS]) + 0.001, "Positive fit peak did not spread along length")
	_check(output[peak] == fitted[peak], "Source peak was inflated or pulled inward")
	for index in output.size():
		_check(output[index].is_finite(), "Nonfinite output")
		_check(output[index].y == fitted[index].y, "Y changed")
		_check(_radius(output[index]) + EPSILON >= _radius(fitted[index]), "Fitted radius moved inward")
		if output[index].distance_to(fitted[index]) <= EPSILON: continue
		var angle := absf(wrapf(atan2(original[index].x, original[index].z), -PI, PI))
		_check(absf(original[index].y - original[peak].y) < profile.contour_span and angle < profile.ANGLE_SUPPORT,
			"Default contour influence escaped compact support")
	_check(output[peak + COLUMNS / 2] == fitted[peak + COLUMNS / 2], "Front peak affected back")
	_check(output[peak + COLUMNS * 12] == fitted[peak + COLUMNS * 12], "Peak expanded distant hem silhouette")
	_check(var_to_bytes(original) == original_bytes and var_to_bytes(fitted) == fitted_bytes, "Input arrays mutated")
	_check(profile.fit(original, fitted) == output, "Repeated evaluation drifted")
	profile.enabled = false
	_check(profile.fit(original, fitted) == fitted, "Disabled profile did not revert to fitted input")
	profile.enabled = true
	_check(profile.fit(original, fitted) == output, "Re-enabling did not restore result")
	profile.contour_span = 0
	_check(profile.fit(original, fitted) == fitted, "Zero span with zero ease changed input")
	profile.contour_span = 0.16
	profile.contour_strength = _constant(0)
	_check(profile.fit(original, fitted) == fitted, "Zero strength changed input")
	var inward := _bump(original, peak, -0.04)
	profile.contour_strength = _constant(1)
	_check(profile.fit(original, inward) == inward, "Negative fit excess propagated")
	var uniform := original.duplicate()
	for index in uniform.size():
		var direction := Vector2(uniform[index].x, uniform[index].z).normalized()
		uniform[index] += Vector3(direction.x, 0, direction.y) * 0.04
	_check(_near(profile.fit(original, uniform), uniform), "Uniform fitted ease expanded again")
	var reverse_original := original.duplicate()
	var reverse_fitted := fitted.duplicate()
	reverse_original.reverse()
	reverse_fitted.reverse()
	var reverse_output := profile.fit(reverse_original, reverse_fitted)
	reverse_output.reverse()
	_check(_near(reverse_output, output), "Vertex ordering changed contour result")


func _ease_and_anchor() -> void:
	var profile := Profile.new()
	profile.contour_span = 0
	var original := _cone()
	var row := (ROWS / 2) * COLUMNS
	profile.front_ease = _constant(0.04)
	var front := profile.fit(original, original)
	_check(absf(_radius(front[row]) - _radius(original[row]) - 0.04) < EPSILON, "Front ease has wrong magnitude")
	_check(front[row + COLUMNS / 2] == original[row + COLUMNS / 2], "Front ease affected back")
	_check(front[row + COLUMNS / 4].distance_to(original[row + COLUMNS / 4]) < EPSILON, "Front ease affected side")
	profile.front_ease = _constant(0)
	profile.back_ease = _constant(0.07)
	var back := profile.fit(original, original)
	_check(back[row] == original[row], "Back ease affected front")
	_check(absf(_radius(back[row + COLUMNS / 2]) - _radius(original[row + COLUMNS / 2]) - 0.07) < EPSILON, "Back ease has wrong magnitude")
	profile.side_ease = _constant(0.03)
	profile.front_ease = _constant(0.04)
	var eased := profile.fit(original, original)
	_check(absf(_radius(eased[row + COLUMNS / 8]) - _radius(original[row + COLUMNS / 8]) - 0.035) < EPSILON, "Directional easing is not blended per vertex")
	for index in COLUMNS: _check(eased[index] == original[index], "Root is not anchored")
	var limits := PackedVector3Array([Vector3(0, 1.5, 0.3), Vector3(0, 1.31, 0.3),
		Vector3(0, 0.20, 0.4), Vector3(0, 0.1, 0.4)])
	var fitted := _bump(limits, 1, 0.05)
	var result := profile.fit(limits, fitted)
	_check(result[0] == fitted[0] and result[1] == fitted[1] and result[3] == fitted[3], "Root/out-of-range fitted points changed")
	_check(result[2].z > fitted[2].z, "Hem cannot receive ease")
	profile.side_ease = _constant(0)
	profile.back_ease = _constant(0)
	profile.front_ease = _constant(0)
	profile.front_ease.set_point_value(1, 0.08)
	var ramp := profile.fit(original, original)
	for row_index in [ROWS / 4, ROWS * 3 / 4]:
		var index: int = row_index * COLUMNS
		var expected := 0.08 * float(row_index) / ROWS
		_check(absf(_radius(ramp[index]) - _radius(original[index]) - expected) < EPSILON,
			"Ease Curve was not sampled in root-to-hem rest coordinates")
	profile.root_height = profile.hem_height
	_check(profile.fit(original, original) == original, "Invalid height range was not a no-op")


func _mask_and_rest_coordinates() -> void:
	var profile := Profile.new()
	var original := _cone()
	var peak := (ROWS / 2) * COLUMNS
	var fitted := _bump(original, peak, 0.06)
	var mask := PackedByteArray()
	mask.resize(original.size())
	_check(profile.fit(original, fitted, mask) == fitted, "Ineligible vertices changed")
	mask.fill(1)
	mask[peak] = 0
	_check(profile.fit(original, fitted, mask) == fitted, "Ineligible source contaminated neighbors")
	mask[peak] = 1
	mask[peak + COLUMNS] = 0
	var masked := profile.fit(original, fitted, mask)
	_check(masked[peak + COLUMNS] == fitted[peak + COLUMNS], "Ineligible recipient changed")
	_check(_radius(masked[peak - COLUMNS]) > _radius(fitted[peak - COLUMNS]), "Eligible recipient did not change")
	_check(profile.fit(original, fitted, PackedByteArray([1])) == fitted, "Malformed mask not rejected")
	_check(profile.fit(PackedVector3Array(), fitted) == fitted, "Mismatched arrays not rejected")
	fitted[peak + COLUMNS].y += 2.0
	var shifted := profile.fit(original, fitted)
	_check(_radius(shifted[peak + COLUMNS]) > _radius(fitted[peak + COLUMNS]) and shifted[peak + COLUMNS].y == fitted[peak + COLUMNS].y,
		"Profile used fitted/posed height instead of fixed original height")
	var seam := PackedVector3Array([Vector3(0.0002, 0.75, 0.35), Vector3(-0.0002, 0.74, 0.35)])
	var seam_fit := _bump(seam, 0, 0.05)
	_check(_radius(profile.fit(seam, seam_fit)[1]) > _radius(seam_fit[1]), "Azimuth seam split contour support")
	var root_peak := _bump(original, 0, 0.05)
	_check(profile.fit(original, root_peak) == root_peak, "Anchored root became a contour source")


func _curves_and_serialization() -> void:
	var profile := Profile.new()
	var other := Profile.new()
	_check(profile.front_ease != other.front_ease and profile.side_ease != profile.back_ease, "Default curves are shared")
	var shared := _constant(0.04)
	profile.front_ease = shared
	other.front_ease = shared
	var snapshot := _curve_state(shared)
	var original := PackedVector3Array([Vector3(0, 0.75, 0.35)])
	var before := profile.fit(original, original)
	_check(_curve_state(shared) == snapshot and other.front_ease == shared, "Fit mutated a shared curve")
	shared.set_point_value(0, 0.08)
	shared.set_point_value(1, 0.08)
	var changed := profile.fit(original, original)
	_check(changed[0].z > before[0].z + 0.03, "Curve edits were not sampled on the next fit")
	shared.set_point_value(0, 0)
	shared.set_point_value(1, 0)
	_check(profile.fit(original, original) == original, "Clearing ease did not revert")
	var negative := _constant(-0.2)
	profile.front_ease = negative
	var negative_snapshot := _curve_state(negative)
	_check(profile.fit(original, original) == original and _curve_state(negative) == negative_snapshot, "Negative ease was not clamped without resource mutation")
	profile.front_ease = _constant(0.06)
	profile.side_ease = _constant(0.025)
	profile.back_ease = _constant(0.015)
	profile.contour_span = 0.12
	profile.bridge_tension = .73
	var path := OS.get_cache_dir().path_join("garment_shape_profile_test_%d_%d.tres" % [OS.get_process_id(), Time.get_ticks_usec()])
	_check(not FileAccess.file_exists(path), "Serialization fixture already exists")
	if FileAccess.file_exists(path): return
	var error := ResourceSaver.save(profile, path)
	_check(error == OK, "Resource serialization failed")
	if error != OK: return
	var loaded = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	_check(loaded != null, "Resource load failed")
	if loaded != null:
		_check(loaded.enabled and loaded.root_height == profile.root_height and loaded.hem_height == profile.hem_height \
			and loaded.contour_span == profile.contour_span and is_equal_approx(loaded.bridge_tension, .73), "Scalar properties did not survive serialization")
		for key in ["front_ease", "back_ease", "side_ease", "contour_strength"]:
			# Text resources canonicalize negative-zero tangents; compare values here.
			_check(bytes_to_var(_curve_state(loaded.get(key))) == bytes_to_var(_curve_state(profile.get(key))), "Serialized curve differs: " + key)
		var cone := _cone()
		var fitted := _bump(cone, (ROWS / 2) * COLUMNS, 0.06)
		_check(_near(loaded.fit(cone, fitted), profile.fit(cone, fitted)), "Serialized profile changed fit results")
		loaded.front_ease.set_point_value(0, 0.12)
		loaded.front_ease.set_point_value(1, 0.12)
		_check(loaded.fit(original, original)[0].z > profile.fit(original, original)[0].z + 0.05,
			"Loaded Curve edit did not update fit")
		_check(is_equal_approx(profile.front_ease.sample(0.5), 0.06), "Loaded Curve edit mutated original resource")
		_check(ResourceSaver.save(loaded, path) == OK, "Edited Curve could not be saved")
		var reloaded = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		_check(reloaded != null and is_equal_approx(reloaded.front_ease.sample(0.5), 0.12), "Edited Curve did not persist after saving again")
	_check(DirAccess.remove_absolute(path) == OK, "Could not remove serialization fixture")


func _tension_bridge() -> void:
	var profile := Profile.new()
	var original := _cone()
	var peak := (ROWS / 4) * COLUMNS
	var fitted := _bump(original, peak, .09)
	profile.contour_span = 0
	profile.bridge_tension = 1
	var taut := profile.fit(original, fitted)
	_check(profile.fit(original, original) == original, "Tension inflated an untouched garment")
	_check(taut[peak] == fitted[peak], "Tension inflated its source obstacle")
	_check(_radius(taut[peak + 12 * COLUMNS]) > _radius(fitted[peak + 12 * COLUMNS]) + .03, "Tension did not bridge the concavity below contact")
	_check(taut[0] == fitted[0] and taut[ROWS * COLUMNS] == fitted[ROWS * COLUMNS], "Tension moved root or hem anchors")
	_check(taut[peak + 12 * COLUMNS + COLUMNS / 2] == fitted[peak + 12 * COLUMNS + COLUMNS / 2], "Tension leaked to opposite meridian")
	profile.bridge_tension = .4
	var soft := profile.fit(original, fitted)
	for i in soft.size():
		_check(_radius(soft[i]) >= _radius(fitted[i]) - EPSILON and _radius(soft[i]) <= _radius(taut[i]) + EPSILON, "Tension is not monotonic/outward only")
		_check(soft[i].is_finite() and soft[i].y == fitted[i].y, "Bridge changed height or became nonfinite")
	profile.bridge_tension = 0
	_check(profile.fit(original, fitted) == fitted, "Zero tension did not restore compact-only behavior")
	profile.bridge_tension = 1
	profile.contour_strength = _constant(0)
	_check(profile.fit(original, fitted) == fitted, "Strength curve did not disable bridge")


func _run() -> void:
	var started := Time.get_ticks_msec()
	_identity_and_locality()
	_ease_and_anchor()
	_mask_and_rest_coordinates()
	_curves_and_serialization()
	_tension_bridge()
	print("GARMENT_SHAPE_PROFILE_TEST %s checks=%d failures=%d elapsed_ms=%d" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size(), Time.get_ticks_msec() - started])
	quit(0 if failures.is_empty() else 1)
