extends SceneTree

## Headless regression for reusable facial expressions.
##
## Run with:
##   godot --headless --path . --script tests/expression_test.gd
##
## The test deliberately stays on the VolumeDoll contract: it does not require
## the shop scene, and it checks the baked skin arrays and blendshape topology
## that rig.bind() produces.

const Doll = preload("res://scripts/volume_doll.gd")
const Expressions = preload("res://scripts/doll_expressions.gd")
const RING_VERTICES := 9

var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		return
	if not failures.has(message):
		failures.append(message)
		push_error(message)


func _run() -> void:
	var doll := Doll.new()
	root.add_child(doll)
	doll.configure({"name": "ExpressionProbe", "hair": 1, "outfit": 1, "palette": 0, "skin": 1})
	await process_frame
	var controller: Expressions = doll.expression_controller()
	_check(controller != null, "Expression controller was not created after rig.bind().")
	if controller == null:
		await _finish(doll, null)
		return
	_check(controller.is_bound(), "Expression controller found no facial meshes.")
	_check(controller.get_features().size() == 5, "Expected one mouth, two brows and two closed eyes.")

	_test_feature_topology(controller)
	_test_ellipsoid_projection(controller)
	_test_style_targets(controller)
	_test_closed_eye_curve(controller)
	_test_position_offsets(doll, controller)
	_test_offset_continuity(doll, controller)
	_test_transitions(doll, controller)
	_test_auto_mapping(doll, controller)
	_test_invalid_input(doll, controller)
	_test_eye_closure(doll, controller)
	_test_runtime_stability(doll, controller)
	_test_reconfigure(doll, controller)
	await _finish(doll, doll.expression_controller())


func _finish(doll: VolumeDoll, controller: Expressions) -> void:
	var eye_closure := controller.get_eye_closure() if controller != null else 0.0
	var summary := "EXPRESSION_CHECK checks=%d failures=%d features=%d closure=%.3f" % [
		checks, failures.size(), controller.get_features().size() if controller != null else 0, eye_closure]
	print(summary)
	_write_log(summary)
	doll.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)


func _write_log(summary: String) -> void:
	var file := FileAccess.open("res://captures/expression_test.log", FileAccess.WRITE)
	if file == null:
		return
	file.store_line("Godot expression regression")
	file.store_line(summary)
	for failure in failures:
		file.store_line("FAIL " + failure)


func _features(controller: Expressions, kind: int) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for part in controller.get_features():
		if controller.get_feature_kind(part) == kind:
			result.append(part)
	return result


func _test_feature_topology(controller: Expressions) -> void:
	var mouth := _features(controller, Expressions.FEATURE_MOUTH)
	var brows := _features(controller, Expressions.FEATURE_BROW)
	var closed := _features(controller, Expressions.FEATURE_CLOSED_EYE)
	_check(mouth.size() == 1, "Expected exactly one mouth mesh.")
	_check(brows.size() == 2, "Expected exactly two eyebrow meshes.")
	_check(closed.size() == 2, "Expected exactly two closed-eye meshes.")
	_check(controller.get_closed_eyes().size() == 2, "Closed-eye cache is incomplete.")
	for instance in controller.get_features():
		var mesh := instance.mesh as ArrayMesh
		_check(instance.skin != null, "Feature lost its skin: " + str(instance.name))
		_check(mesh != null and mesh.get_surface_count() == 1, "Feature has no single surface: " + str(instance.name))
		_check(mesh.blend_shape_mode == Mesh.BLEND_SHAPE_MODE_NORMALIZED,
			"Absolute facial targets must not be rendered as relative deltas.")
		if mesh == null:
			continue
		_check(mesh.get_blend_shape_count() >= 7, "Feature is missing expression blendshapes: " + str(instance.name))
		for state in 7:
			_check(mesh.get_blend_shape_name(state) == Expressions.STATE_NAMES[state],
				"Unexpected blendshape name: " + str(instance.name))
		var kind := controller.get_feature_kind(instance)
		if kind == Expressions.FEATURE_CLOSED_EYE:
			_check(mesh.get_blend_shape_count() == 8, "Closed eye needs its dormant shape.")
			_check(mesh.get_blend_shape_name(7) == "dormant", "Closed eye dormant shape name changed.")
		else:
			_check(mesh.get_blend_shape_count() == 7, "Unexpected extra blendshape on: " + str(instance.name))

		var base: Array = mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = base[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = base[Mesh.ARRAY_NORMAL]
		var bones: PackedInt32Array = base[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = base[Mesh.ARRAY_WEIGHTS]
		_check(!vertices.is_empty(), "Feature has no baked vertices: " + str(instance.name))
		_check(normals.size() == vertices.size(), "Feature normal array changed size: " + str(instance.name))
		if kind == Expressions.FEATURE_CLOSED_EYE:
			_check(vertices.size() == 9 * RING_VERTICES,
				"Closed eye needs nine consistently sampled rings: " + str(instance.name))
		_check(bones.size() == vertices.size() * 4, "Feature lost bone indices: " + str(instance.name))
		_check(weights.size() == vertices.size() * 4, "Feature lost bone weights: " + str(instance.name))
		var weights_ok := true
		for index in vertices.size():
			var total := (weights[index * 4] + weights[index * 4 + 1]
				+ weights[index * 4 + 2] + weights[index * 4 + 3])
			if absf(total - 1.0) > 0.001:
				weights_ok = false
				break
		_check(weights_ok, "Feature bone weights are not normalized: " + str(instance.name))
		var normals_ok := true
		for normal in normals:
			if not _finite(normal) or normal.length_squared() < 0.98 or normal.length_squared() > 1.02:
				normals_ok = false
				break
		_check(normals_ok, "Feature base normals are not finite unit vectors: " + str(instance.name))

		var shapes: Array = mesh.surface_get_blend_shape_arrays(0)
		_check(shapes.size() == mesh.get_blend_shape_count(), "Blendshape topology cache is incomplete: " + str(instance.name))
		for shape_index in shapes.size():
			var shape: Array = shapes[shape_index]
			var shape_vertices: PackedVector3Array = shape[Mesh.ARRAY_VERTEX]
			var shape_normals: PackedVector3Array = shape[Mesh.ARRAY_NORMAL]
			_check(shape_vertices.size() == vertices.size(), "Blendshape vertex count changed: " + str(instance.name))
			_check(shape_normals.size() == vertices.size(), "Blendshape normal count changed: " + str(instance.name))
			if kind == Expressions.FEATURE_CLOSED_EYE:
				_check(shape_vertices.size() == 9 * RING_VERTICES,
					"Closed-eye blendshape needs nine consistently sampled rings: " + str(instance.name))
			var finite_ok := true
			for point in shape_vertices:
				if not _finite(point):
					finite_ok = false
					break
			_check(finite_ok, "Blendshape contains non-finite vertices: " + str(instance.name))
			var shape_normals_ok := true
			for normal in shape_normals:
				if not _finite(normal) or normal.length_squared() < 0.98 or normal.length_squared() > 1.02:
					shape_normals_ok = false
					break
			_check(shape_normals_ok, "Blendshape normals are not finite unit vectors: " + str(instance.name))


func _test_ellipsoid_projection(controller: Expressions) -> void:
	for instance in controller.get_features():
		var mesh := instance.mesh as ArrayMesh
		if mesh == null:
			continue
		var shapes: Array = mesh.surface_get_blend_shape_arrays(0)
		var closed := controller.get_feature_kind(instance) == Expressions.FEATURE_CLOSED_EYE
		for shape_index in mini(7, shapes.size()):
			var vertices: PackedVector3Array = shapes[shape_index][Mesh.ARRAY_VERTEX]
			var centers := _ring_centers(vertices)
			var centers_ok := true
			var vertices_ok := true
			for center in centers:
				var radial: float = controller.head_radial(center)
				if absf(radial - 1.0) > 0.02:
					centers_ok = false
				if radial < 0.90 or radial > 1.08:
					vertices_ok = false
			# Each tube ring is centered exactly on the ellipsoid; its vertices
			# carry only the tube radius away from that surface.
			for point in vertices:
				var radial: float = controller.head_radial(point)
				if radial < 0.90 or radial > 1.08:
					vertices_ok = false
			_check(centers_ok, "Expression centreline left the head ellipsoid: " + str(instance.name))
			_check(vertices_ok, "Expression geometry floats or sinks: " + str(instance.name))
		if closed and shapes.size() > 7:
			var dormant: PackedVector3Array = shapes[7][Mesh.ARRAY_VERTEX]
			var hidden_ok := true
			for point in dormant:
				if controller.head_radial(point) > 0.95:
					hidden_ok = false
					break
			_check(hidden_ok, "Dormant closed-eye curve is still outside the head.")


func _test_style_targets(controller: Expressions) -> void:
	var mouth := _features(controller, Expressions.FEATURE_MOUTH)
	var brows := _features(controller, Expressions.FEATURE_BROW)
	var closed := _features(controller, Expressions.FEATURE_CLOSED_EYE)
	if mouth.size() == 1:
		var neutral_width := _centers_width(_shape_centers(mouth[0], Expressions.NEUTRAL))
		var happy_width := _centers_width(_shape_centers(mouth[0], Expressions.HAPPY))
		var asleep_width := _centers_width(_shape_centers(mouth[0], Expressions.ASLEEP))
		var surprised_height := _centers_height(_shape_centers(mouth[0], Expressions.SURPRISED))
		_check(neutral_width < 0.12, "Neutral mouth is not the understated short curve.")
		_check(happy_width > neutral_width, "Happy mouth did not widen.")
		_check(asleep_width < happy_width, "Asleep mouth did not relax.")
		_check(surprised_height > 0.03, "Surprised mouth did not open.")
	if brows.size() == 2:
		var neutral_width := _centers_width(_shape_centers(brows[0], Expressions.NEUTRAL))
		_check(neutral_width < 0.075, "Default brows are not subtle enough.")
		var asleep_y := _centers_average_y(_shape_centers(brows[0], Expressions.ASLEEP))
		var surprised_y := _centers_average_y(_shape_centers(brows[0], Expressions.SURPRISED))
		_check(asleep_y < surprised_y, "Asleep brows did not soften.")
	if closed.size() == 2:
		var neutral_vertices := _shape_vertices(closed[0], Expressions.NEUTRAL)
		var asleep_vertices := _shape_vertices(closed[0], Expressions.ASLEEP)
		_check(neutral_vertices != asleep_vertices, "Asleep closed-eye curve has no soft shape.")
		for eye in closed:
			var points := _shape_centers(eye, Expressions.ASLEEP)
			_check(points[points.size()/2].y < minf(points[0].y,points[-1].y)-.008,
				"Sleeping eyelid must open upward like U, not an inverted arch.")


func _test_closed_eye_curve(controller: Expressions) -> void:
	var closed := _features(controller, Expressions.FEATURE_CLOSED_EYE)
	_check(closed.size() == 2, "Closed-eye curve test needs two eyelids.")
	for eye in closed:
		for state in Expressions.STATE_COUNT:
			var centers := _shape_centers(eye, state)
			_check(centers.size() == 9,
				"Closed eye is not sampled with nine rings for %s." % Expressions.STATE_NAMES[state])
			if centers.size() != 9:
				continue
			var ends := minf(centers[0].y, centers[8].y)
			_check(centers[4].y < ends,
				"Closed-eye curve is an inverted arch rather than a U.")
			if state == Expressions.ASLEEP:
				_check(centers[4].y < ends - 0.008,
					"Sleeping eyelid midpoint is not at least 0.008 lower than its ends.")
			var minimum_step := INF
			var maximum_step := 0.0
			for index in range(1, centers.size()):
				var step := absf(centers[index].x - centers[index - 1].x)
				minimum_step = minf(minimum_step, step)
				maximum_step = maxf(maximum_step, step)
			_check(maximum_step - minimum_step < 0.0015,
				"Closed-eye rings are not sampled consistently along the curve.")
			var before := centers[4] - centers[3]
			var after := centers[5] - centers[4]
			var turn := rad_to_deg(absf(before.angle_to(after)))
			_check(turn < 35.0,
				"Closed-eye bottom is a sharp V rather than a rounded U.")


func _test_position_offsets(doll: VolumeDoll, controller: Expressions) -> void:
	var mouth := _features(controller, Expressions.FEATURE_MOUTH)
	var brows := _features(controller, Expressions.FEATURE_BROW)
	var closed := _features(controller, Expressions.FEATURE_CLOSED_EYE)

	doll.set_expression("content", 0.0)
	controller.update(0.0)
	_check(controller.get_eye_offset(-1.0).length_squared() < 0.0000001,
		"Content must leave the left eye at its base position.")
	_check(controller.get_eye_offset(1.0).length_squared() < 0.0000001,
		"Content must leave the right eye at its base position.")

	for state in Expressions.STATE_COUNT:
		doll.set_expression(Expressions.STATE_NAMES[state], 0.0)
		controller.update(0.0)
		for side in [-1.0, 1.0]:
			var offset := controller.get_eye_offset(side)
			_check(_finite(offset),
				"Eye offset became non-finite for %s." % Expressions.STATE_NAMES[state])
			_check(offset.length() <= 0.0301,
				"Eye offset exceeded the 0.03-unit budget for %s." % Expressions.STATE_NAMES[state])
			var base: Vector3 = controller._surface_local(side * Expressions.EYE_BASE_X,
				Expressions.EYE_BASE_Y)
			var body: Vector3 = controller._head_origin + base + offset
			_check(absf(controller.head_radial(body) - 1.0) < 0.002,
				"Eye offset left the head surface for %s." % Expressions.STATE_NAMES[state])

	doll.set_expression("happy", 0.0)
	controller.update(0.0)
	var happy := controller.get_eye_offset(1.0)
	_check(absf(happy.y - 0.008) < 0.0001, "Happy eye lift should be 0.008 units.")
	doll.set_expression("surprised", 0.0)
	controller.update(0.0)
	var surprised := controller.get_eye_offset(1.0)
	_check(absf(surprised.y - 0.010) < 0.0001, "Surprised eye lift should be 0.010 units.")
	doll.set_expression("asleep", 0.0)
	controller.update(0.0)
	var asleep := controller.get_eye_offset(1.0)
	_check(asleep.y < -0.011, "Asleep eyes did not settle lower than content.")
	_check(absf(asleep.y + 0.022) < 0.0001, "Asleep eye lower should be 0.022 units.")

	if mouth.size() == 1:
		var content_mouth := _shape_center(mouth[0], Expressions.CONTENT)
		var thinking_delta := _shape_center(mouth[0], Expressions.THINKING) - content_mouth
		_check(absf(thinking_delta.x) > 0.004, "Thinking mouth did not shift sideways.")
		_check(Vector2(thinking_delta.x, thinking_delta.y).length() <= 0.0301,
			"Thinking mouth offset exceeded the 0.03-unit budget.")
		var asleep_delta := _shape_center(mouth[0], Expressions.ASLEEP) - content_mouth
		_check(asleep_delta.x > 0.002, "Asleep smile is not slightly off-centre.")
		_check(absf(asleep_delta.y) > 0.0001, "Asleep smile has no vertical relaxed offset.")

	if brows.size() == 2:
		var thinking_heights: Array[float] = []
		var content_heights: Array[float] = []
		for brow in brows:
			thinking_heights.append(_shape_center(brow, Expressions.THINKING).y)
			content_heights.append(_shape_center(brow, Expressions.CONTENT).y)
		_check(absf(thinking_heights[0] - thinking_heights[1]) > 0.004,
			"Thinking brows are not asymmetric.")
		_check(maxf(thinking_heights[0], thinking_heights[1])
			> maxf(content_heights[0], content_heights[1]) + 0.004,
			"Thinking did not raise one brow.")

	if closed.size() == 2:
		doll.set_expression("thinking", 0.0)
		controller.update(0.0)
		var eye_offset := controller.get_eye_offset(1.0)
		for eye in closed:
			var shift := (_shape_center(eye, Expressions.THINKING)
				- _shape_center(eye, Expressions.CONTENT))
			_check(absf(shift.x - eye_offset.x) < 0.0025
				and absf(shift.y - eye_offset.y) < 0.0025,
				"Closed-eye curve does not follow the open-eye offset.")
		var depth_ok := true
		for state in [Expressions.CONTENT, Expressions.THINKING, Expressions.ASLEEP]:
			for center in _shape_centers(closed[0], state):
				if absf(controller.head_radial(center) - 1.0) > 0.02:
					depth_ok = false
					break
		_check(depth_ok, "Closed-eye positional offsets left the head surface.")


func _test_offset_continuity(doll: VolumeDoll, controller: Expressions) -> void:
	doll.set_expression("happy", 0.4)
	_advance(controller, 0.16)
	var before := controller.get_eye_offset(1.0)
	_check(doll.set_expression("asleep", 0.4), "Interrupted-eye test could not start asleep.")
	var after := controller.get_eye_offset(1.0)
	_check((after - before).length() < 0.0001,
		"Interrupting a transition snapped the eye offset.")
	var previous := after
	var largest_step := 0.0
	for frame in 36:
		controller.update(1.0 / 60.0)
		var current := controller.get_eye_offset(1.0)
		largest_step = maxf(largest_step, (current - previous).length())
		previous = current
	_check(largest_step < 0.01, "Interrupted eye transition jumped between frames.")
	_check(_finite(previous), "Interrupted eye transition produced a non-finite offset.")


func _test_transitions(doll: VolumeDoll, controller: Expressions) -> void:
	_check(doll.set_expression("happy", 0.4), "Happy expression was rejected.")
	var start := controller.get_blend_weights()
	_check(start[Expressions.HAPPY] < 0.99, "Expression snapped instead of starting a transition.")
	_advance(controller, 0.2)
	var middle := controller.get_blend_weights()
	_check(middle[Expressions.HAPPY] > start[Expressions.HAPPY],
		"Expression transition did not progress.")
	_check(absf(_weight_sum(middle) - 1.0) < 0.0001, "Transition weights are not normalized.")
	var before_retarget := controller.get_blend_weights()
	_check(doll.set_expression("thinking", 0.4), "Thinking expression was rejected.")
	_advance(controller, 0.0001)
	var after_retarget := controller.get_blend_weights()
	var close := true
	for index in 7:
		if absf(after_retarget[index] - before_retarget[index]) > 0.02:
			close = false
	_check(close, "Retarget did not snapshot the current blended weights.")
	_advance(controller, 1.0)
	var settled := controller.get_blend_weights()
	_check(doll.current_expression() == "thinking", "Transition did not reach thinking.")
	_check(settled[Expressions.THINKING] > 0.999, "Thinking blendshape is not fully applied.")
	_check(absf(_weight_sum(settled) - 1.0) < 0.0001, "Settled weights are not normalized.")
	doll.clear_expression()
	controller.update(1.0)
	_check(controller.is_auto(), "Clearing an expression did not return to auto.")


func _test_auto_mapping(doll: VolumeDoll, controller: Expressions) -> void:
	_check(Expressions.resolve_auto_state("browsing", false, false) == "thinking", "Browsing auto state is not thinking.")
	_check(Expressions.resolve_auto_state("thinking", false, false) == "thinking", "Thinking auto state is not thinking.")
	_check(Expressions.resolve_auto_state("checkout", false, false) == "happy", "Checkout auto state is not happy.")
	_check(Expressions.resolve_auto_state("idle", true, false) == "tired", "Resting auto state is not tired.")
	_check(Expressions.resolve_auto_state("idle", false, true) == "asleep", "Napping auto state is not asleep.")
	_check(Expressions.resolve_auto_state("sewing", false, false) == "content", "Ordinary auto state is not content.")
	_check(Expressions.resolve_auto_state("checkout", true, false) == "tired", "Rest must outrank checkout.")

	controller.set_auto_context("browsing", false, false)
	doll.clear_expression()
	controller.update(1.0)
	_check(doll.current_expression() == "thinking", "Auto browsing did not reach thinking.")

	controller.set_auto_context("checkout", false, false)
	doll.set_expression("surprised", 0.0)
	_check(doll.set_expression("surprised", 0.0), "Explicit surprised expression was rejected.")
	controller.set_auto_context("browsing", false, false)
	controller.update(1.0)
	_check(doll.current_expression() == "surprised", "Auto context overrode an explicit expression.")
	_check(not controller.is_auto(), "Explicit expression lost its override flag.")
	doll.clear_expression()
	controller.update(1.0)
	_check(doll.current_expression() == "thinking", "Clearing the override did not resume auto thinking.")


func _test_invalid_input(doll: VolumeDoll, controller: Expressions) -> void:
	_check(not doll.set_expression("", 0.0), "Empty expression name was accepted.")
	controller.update(0.0)
	_check(doll.current_expression() == "neutral", "Empty expression did not fall back safely.")
	_check(not doll.set_expression("not-a-state", 0.0), "Unknown expression name was accepted.")
	controller.update(0.0)
	var fallback := controller.get_blend_weights()
	_check(doll.current_expression() == "neutral", "Unknown expression did not fall back to neutral.")
	_check(fallback[Expressions.NEUTRAL] > 0.999, "Neutral fallback weights were not applied.")
	_check(absf(_weight_sum(fallback) - 1.0) < 0.0001, "Fallback weights are not normalized.")
	doll.set_expression("happy",.35)
	var before := controller.get_blend_weights()
	for delta in [0.0,-1.0,NAN,INF]:
		controller.update(delta)
		_check(controller.get_blend_weights() == before,"Invalid delta changed expression weights.")
	controller.update(100.0)
	_check(controller.get_blend_weights()[Expressions.HAPPY] > .999,"Large delta did not settle safely.")


func _test_eye_closure(doll: VolumeDoll, controller: Expressions) -> void:
	doll.set_expression("tired", 0.0)
	controller.update(0.0)
	_check(absf(controller.get_eye_closure() - 0.5) < 0.01, "Tired eye closure is not half-lidded.")
	for eye in controller.get_closed_eyes():
		_check(not eye.visible, "Closed-eye curve is visible during a half-lidded expression.")

	doll.set_expression("asleep", 0.35)
	var previous := controller.get_eye_closure()
	var largest_step := 0.0
	for frame in 24:
		controller.update(1.0 / 60.0)
		largest_step = maxf(largest_step, absf(controller.get_eye_closure() - previous))
		previous = controller.get_eye_closure()
	_check(largest_step < 0.15, "Eye closure jumped instead of easing.")
	controller.update(1.0)
	_check(controller.get_eye_closure() > 0.99, "Asleep did not close the eyes smoothly.")
	for eye in controller.get_closed_eyes():
		_check(eye.visible, "Closed-eye curve did not appear for sleep.")
		_check(eye.get_blend_shape_value(7) < 0.01, "Closed-eye curve is still dormant while asleep.")
		var arrays: Array = eye.mesh.surface_get_arrays(0)
		var ids: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var skin_weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		for slot in ids.size():
			if skin_weights[slot] > 0:
				_check(ids[slot] == doll.rig.bones.Head,"Closed-eye curve must not collapse with the blinking pupil.")
	var bean_count := 0
	for part in doll.rig.meshes:
		if str(part.get_meta("eye_state", "")) == "open":
			bean_count += 1
			_check(part.visible, "Bean eye was hidden by sleep.")
	_check(bean_count == 2, "Expected two bean eyes on the baked rig.")

	doll._work_phase = 2.0
	doll.simulate(1.0 / 60.0, 1.0)
	_check(doll.rig.skeleton.get_bone_pose_scale(doll.rig.bones["EyeL"]).y < 0.15,
		"Sleep did not close the bean-eye bone.")
	_check(doll.rig.skeleton.get_bone_pose_scale(doll.rig.bones["EyeR"]).y < 0.15,
		"Sleep did not close both bean-eye bones.")
	for part in doll.rig.meshes:
		if part.get_meta("eye_state","") != "open": continue
		var transform: Transform3D = doll.rig.global_pose(doll.rig.bones.Head)*doll.rig.skeleton.get_bone_global_rest(doll.rig.bones.Head).affine_inverse()
		var largest := 0.0
		for vertex in doll.rig.deformed_vertices(part):
			largest = maxf(largest,controller.head_radial(transform.affine_inverse()*vertex))
		_check(largest < 1.0,"An open pupil still draws a second stroke over the sleeping eyelid.")

	controller.set_auto_context("idle", false, false)
	doll.clear_expression()
	controller.update(1.0)
	_check(controller.get_eye_closure() < 0.01, "Waking did not reopen the eyes.")
	for eye in controller.get_closed_eyes():
		_check(not eye.visible, "Closed-eye curve remained visible after waking.")
	doll._work_phase = 2.0
	doll.simulate(1.0 / 60.0, 1.0)
	_check(doll.rig.skeleton.get_bone_pose_scale(doll.rig.bones["EyeL"]).y > 0.9,
		"Waking did not restore the bean-eye bone.")


func _test_runtime_stability(doll: VolumeDoll, controller: Expressions) -> void:
	var features := controller.get_features()
	var instance_ids: Array[int] = []
	var mesh_ids: Array[int] = []
	var material_ids: Array[int] = []
	var weight_copies: Array = []
	for instance in features:
		instance_ids.append(instance.get_instance_id())
		mesh_ids.append(instance.mesh.get_instance_id())
		material_ids.append(instance.material_override.get_instance_id() if instance.material_override != null else 0)
		var arrays: Array = instance.mesh.surface_get_arrays(0)
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		weight_copies.append(weights.duplicate())
	doll.set_expression("happy", 0.2)
	for frame in 120:
		controller.update(1.0 / 60.0)
	var stable := true
	for index in features.size():
		var instance := features[index]
		if instance.get_instance_id() != instance_ids[index]:
			stable = false
		if instance.mesh.get_instance_id() != mesh_ids[index]:
			stable = false
		if instance.material_override == null or instance.material_override.get_instance_id() != material_ids[index]:
			stable = false
		var arrays: Array = instance.mesh.surface_get_arrays(0)
		var current_weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		if current_weights != weight_copies[index]:
			stable = false
	_check(stable, "Per-frame expression updates allocated meshes/materials or changed skin weights.")


func _test_reconfigure(doll: VolumeDoll, controller: Expressions) -> void:
	doll.set_expression("asleep", 0.0)
	controller.update(0.0)
	doll.configure({"hair": 2, "outfit": 2, "palette": 2, "skin": 2})
	var next: Expressions = doll.expression_controller()
	_check(next != null and next != controller, "Reconfigure did not rebuild the expression controller.")
	_check(doll.expression_mode == 7, "Reconfigure lost the explicit asleep expression.")
	_check(doll.current_expression() == "asleep", "Reconfigure lost the explicit expression target.")
	if next == null:
		return
	_check(next.is_bound(), "Reconfigured controller did not bind to the new face.")
	_check(next.get_features().size() == 5, "Reconfigured face lost expression features.")
	for eye in next.get_closed_eyes():
		_check(eye.visible, "Reconfigured asleep face lost its closed-eye curve.")
	doll.clear_expression()
	doll.set_activity("browsing")
	doll._work_phase = 2.0
	doll.simulate(1.0, 1.0)
	next.update(1.0)
	_check(doll.current_expression() == "thinking", "Clear after reconfigure did not resume auto browsing.")
	_check(next.is_auto(), "Clear after reconfigure left an explicit override.")
	doll.set_expression("asleep", 0.0)
	next.update(0.0)
	doll.clear_expression()
	next.update(1.0)
	_check(next.is_auto() and doll.current_expression() != "asleep",
		"Repeated clear did not release the sleep expression.")


func _advance(controller: Expressions, seconds: float) -> void:
	var remaining := seconds
	while remaining > 0.0:
		var step := minf(remaining, 1.0 / 60.0)
		controller.update(step)
		remaining -= step


func _shape_vertices(instance: MeshInstance3D, state: int) -> PackedVector3Array:
	var shapes: Array = instance.mesh.surface_get_blend_shape_arrays(0)
	if state >= shapes.size():
		return PackedVector3Array()
	return shapes[state][Mesh.ARRAY_VERTEX]


func _shape_centers(instance: MeshInstance3D, state: int) -> PackedVector3Array:
	return _ring_centers(_shape_vertices(instance, state))


func _shape_center(instance: MeshInstance3D, state: int) -> Vector3:
	var centers := _shape_centers(instance, state)
	if centers.is_empty():
		return Vector3.ZERO
	var total := Vector3.ZERO
	for center in centers:
		total += center
	return total / float(centers.size())


func _ring_centers(vertices: PackedVector3Array) -> PackedVector3Array:
	var centers := PackedVector3Array()
	if vertices.size() % RING_VERTICES != 0:
		return centers
	centers.resize(vertices.size() / RING_VERTICES)
	for ring in centers.size():
		var total := Vector3.ZERO
		for column in RING_VERTICES:
			total += vertices[ring * RING_VERTICES + column]
		centers[ring] = total / float(RING_VERTICES)
	return centers


func _centers_width(points: PackedVector3Array) -> float:
	if points.is_empty():
		return 0.0
	var minimum := points[0].x
	var maximum := points[0].x
	for point in points:
		minimum = minf(minimum, point.x)
		maximum = maxf(maximum, point.x)
	return maximum - minimum


func _centers_height(points: PackedVector3Array) -> float:
	if points.is_empty():
		return 0.0
	var minimum := points[0].y
	var maximum := points[0].y
	for point in points:
		minimum = minf(minimum, point.y)
		maximum = maxf(maximum, point.y)
	return maximum - minimum


func _centers_average_y(points: PackedVector3Array) -> float:
	if points.is_empty():
		return 0.0
	var total := 0.0
	for point in points:
		total += point.y
	return total / float(points.size())


func _weight_sum(weights: PackedFloat32Array) -> float:
	var total := 0.0
	for value in weights:
		total += value
	return total


func _finite(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)
