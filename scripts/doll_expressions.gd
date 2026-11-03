class_name DollExpressions
extends RefCounted

## Reusable, allocation-light facial expression controller for the volumetric doll.
##
## The controller is created after rig.bind() has baked the face meshes into body
## space and installed their skin arrays. It replaces only the ArrayMesh resources
## of the existing mouth, eyebrow and closed-eye MeshInstance3D nodes; node identity,
## materials, skin and every bone weight stay untouched.
##
## Every expression is a cached blendshape target. At runtime only the blend shape
## values are changed, so no mesh or material is allocated per frame.
##
## Feature points are authored in head-local coordinates and projected back onto
## the head ellipsoid. The tube cross-section offsets are rotated with the local
## centreline tangent, so the features keep their volume but cannot float away
## from, or sink into, the head.

const STATE_NAMES := ["neutral", "content", "happy", "thinking", "surprised", "tired", "asleep"]
const STATE_COUNT := 7

const NEUTRAL := 0
const CONTENT := 1
const HAPPY := 2
const THINKING := 3
const SURPRISED := 4
const TIRED := 5
const ASLEEP := 6

const FEATURE_MOUTH := 0
const FEATURE_BROW := 1
const FEATURE_CLOSED_EYE := 2

const RING_VERTICES := 9
const CLOSED_EYE_SAMPLES := 9
const DORMANT_SINK := 0.022

# Head-local mouth centreline targets, one entry per state.
const MOUTH_POINTS := [
	[Vector2(-0.050, 0.127), Vector2(-0.021, 0.121), Vector2(0.021, 0.121), Vector2(0.050, 0.127)],
	[Vector2(-0.059, 0.129), Vector2(-0.026, 0.116), Vector2(0.026, 0.116), Vector2(0.059, 0.129)],
	[Vector2(-0.078, 0.139), Vector2(-0.034, 0.107), Vector2(0.034, 0.107), Vector2(0.078, 0.139)],
	[Vector2(-0.056, 0.125), Vector2(-0.021, 0.121), Vector2(0.019, 0.118), Vector2(0.054, 0.131)],
	[Vector2(-0.018, 0.120), Vector2(0.000, 0.143), Vector2(0.018, 0.120), Vector2(0.000, 0.097)],
	[Vector2(-0.051, 0.120), Vector2(-0.019, 0.115), Vector2(0.019, 0.115), Vector2(0.051, 0.120)],
	[Vector2(-0.044, 0.126), Vector2(-0.018, 0.105), Vector2(0.018, 0.105), Vector2(0.044, 0.126)],
]

# Brow targets use positive x; the side sign is applied when the target is built.
# Inner, middle and outer points keep the default brows short and understated.
const BROW_POINTS := [
	[Vector2(0.083, 0.350), Vector2(0.116, 0.353), Vector2(0.142, 0.346)],
	[Vector2(0.082, 0.352), Vector2(0.115, 0.356), Vector2(0.142, 0.350)],
	[Vector2(0.082, 0.354), Vector2(0.116, 0.361), Vector2(0.143, 0.356)],
	[Vector2(0.081, 0.356), Vector2(0.114, 0.363), Vector2(0.141, 0.356)],
	[Vector2(0.084, 0.362), Vector2(0.116, 0.370), Vector2(0.142, 0.361)],
	[Vector2(0.084, 0.348), Vector2(0.116, 0.348), Vector2(0.141, 0.339)],
	[Vector2(0.085, 0.344), Vector2(0.116, 0.345), Vector2(0.141, 0.337)],
]

# Closed-eye anchors are start, middle and end offsets from the eye centre.
# closed_eye_curve() samples them through a parabola so both the baked base
# eyelid and every expression target share the same rounded U silhouette.
const CLOSED_EYE_POINTS := [
	[Vector2(-0.018, 0.292), Vector2(0.000, 0.285), Vector2(0.018, 0.292)],
	[Vector2(-0.018, 0.292), Vector2(0.000, 0.285), Vector2(0.018, 0.292)],
	[Vector2(-0.018, 0.292), Vector2(0.000, 0.285), Vector2(0.018, 0.292)],
	[Vector2(-0.018, 0.292), Vector2(0.000, 0.285), Vector2(0.018, 0.292)],
	[Vector2(-0.018, 0.292), Vector2(0.000, 0.285), Vector2(0.018, 0.292)],
	[Vector2(-0.020, 0.289), Vector2(0.000, 0.286), Vector2(0.020, 0.289)],
	[Vector2(-0.023, 0.288), Vector2(0.000, 0.274), Vector2(0.023, 0.288)],
]

## Samples the three authored eyelid anchors (start, middle, end) with a
## quadratic Bezier. The control point is solved so the curve passes through the
## middle anchor at its midpoint, giving a rounded upward-opening U instead of a
## three-ring V. Base construction and every expression target call this helper.
static func closed_eye_curve(anchors, samples := CLOSED_EYE_SAMPLES) -> PackedVector2Array:
	var curve := PackedVector2Array()
	if anchors == null or anchors.size() < 3:
		return curve
	var start: Vector2 = anchors[0]
	var middle: Vector2 = anchors[1]
	var end: Vector2 = anchors[2]
	var control := middle * 2.0 - (start + end) * 0.5
	var count := maxi(samples, 3)
	curve.resize(count)
	for index in count:
		var t := float(index) / float(count - 1)
		var inverse := 1.0 - t
		curve[index] = start * (inverse * inverse) + control * (2.0 * inverse * t) + end * (t * t)
	return curve

# Head-local XY offsets are applied before the ellipsoid projection, so the
# features move along the face instead of floating in front of it. Offsets stay
# inside a 0.03-unit budget. Content is the zero reference used by transitions.
const MOUTH_OFFSETS := [
	Vector2(0.000, 0.000), # neutral
	Vector2(0.000, 0.000), # content
	Vector2(0.000, 0.000), # happy
	Vector2(0.012, 0.000), # thinking: a small sideways thought
	Vector2(0.000, 0.000), # surprised
	Vector2(0.000, -0.002), # tired
	Vector2(0.006, -0.001), # asleep: relaxed smile, slightly off-centre
]

const EYE_OFFSETS := [
	Vector2(0.000, 0.000), # neutral
	Vector2(0.000, 0.000), # content
	Vector2(0.000, 0.008), # happy
	Vector2(0.010, 0.000), # thinking: eyes glance sideways
	Vector2(0.000, 0.010), # surprised
	Vector2(0.000, -0.004), # tired
	Vector2(0.000, -0.022), # asleep: heavy lids settle lower
]

const EYE_BASE_X := 0.108
const EYE_BASE_Y := 0.292

# Brow offsets are [positive-x side, negative-x side]. Thinking raises exactly
# one brow; the other stays almost level, which reads as a lopsided idea.
const BROW_OFFSETS := [
	[Vector2(0.000, 0.000), Vector2(0.000, 0.000)], # neutral
	[Vector2(0.000, 0.000), Vector2(0.000, 0.000)], # content
	[Vector2(0.000, 0.000), Vector2(0.000, 0.000)], # happy
	[Vector2(0.004, 0.012), Vector2(0.008, -0.002)], # thinking
	[Vector2(0.000, 0.000), Vector2(0.000, 0.000)], # surprised
	[Vector2(0.000, -0.003), Vector2(0.000, -0.003)], # tired
	[Vector2(0.000, -0.008), Vector2(0.000, -0.008)], # asleep
]

var transition_seconds := 0.35
var _rig: RefCounted
var _head_origin := Vector3.ZERO
var _head_center := Vector3.ZERO
var _head_radius := Vector3.ONE
var _features: Array[MeshInstance3D] = []
var _closed_eyes: Array[MeshInstance3D] = []
var _feature_kind: Dictionary = {}
var _dormant_index: Dictionary = {}
var _expression_weights := PackedFloat32Array()
var _from_weights := PackedFloat32Array()
var _target_weights := PackedFloat32Array()
var _target_state := CONTENT
var _active_state := "content"
var _auto_state := "content"
var _transition_elapsed := 0.0
var _transition_duration := 0.0
var _eye_closure := 0.0
var _explicit := false
var _bound := false


func bind(rig_value: RefCounted, head_origin: Vector3, head_center: Vector3,
		head_radius: Vector3, seconds := 0.35) -> bool:
	_rig = rig_value
	_head_origin = head_origin
	_head_center = head_center
	_head_radius = head_radius
	transition_seconds = _safe_seconds(seconds, 0.35)
	_features.clear()
	_closed_eyes.clear()
	_feature_kind.clear()
	_dormant_index.clear()
	_bound = false
	if _rig == null:
		return false
	var meshes_value: Variant = _rig.get("meshes")
	if not (meshes_value is Array):
		return false
	for value in meshes_value:
		var instance := value as MeshInstance3D
		if instance == null:
			continue
		var kind := _feature_kind_for(instance)
		if kind < 0:
			continue
		if not _install_feature(instance, kind):
			continue
		_features.append(instance)
		_feature_kind[instance.get_instance_id()] = kind
		if kind == FEATURE_CLOSED_EYE:
			_closed_eyes.append(instance)
	_bound = not _features.is_empty()
	if not _bound:
		return false
	_expression_weights.resize(STATE_COUNT)
	_expression_weights.fill(0.0)
	_expression_weights[CONTENT] = 1.0
	_from_weights = _expression_weights.duplicate()
	_target_weights = _expression_weights.duplicate()
	_target_state = CONTENT
	_active_state = STATE_NAMES[CONTENT]
	_auto_state = _active_state
	_transition_elapsed = 0.0
	_transition_duration = 0.0
	_eye_closure = 0.0
	_explicit = false
	_apply_weights()
	return true


func is_bound() -> bool:
	return _bound


func set_transition_seconds(value: float) -> void:
	transition_seconds = _safe_seconds(value, 0.35)


func set_expression(name: String, duration := -1.0) -> bool:
	if not _bound:
		return false
	var key := name.strip_edges().to_lower()
	if key == "auto":
		clear_expression(duration)
		return true
	var index: int = STATE_NAMES.find(key)
	var valid := index >= 0
	if not valid:
		index = NEUTRAL
	_explicit = true
	_retarget(index, _duration_for(duration))
	return valid


func clear_expression(duration := -1.0) -> void:
	_explicit = false
	if not _bound:
		return
	var index: int = STATE_NAMES.find(_auto_state)
	if index < 0:
		index = CONTENT
	_retarget(index, _duration_for(duration))


func set_auto_context(activity: String, resting: bool, napping: bool) -> void:
	var resolved := resolve_auto_state(activity, resting, napping)
	_auto_state = resolved
	if _explicit or not _bound:
		return
	var index: int = STATE_NAMES.find(resolved)
	if index >= 0 and index != _target_state:
		_retarget(index, transition_seconds)


func update(delta: float) -> void:
	if not _bound:
		return
	if is_finite(delta) and delta > 0.0 and _transition_elapsed < _transition_duration:
		_transition_elapsed = minf(_transition_duration, _transition_elapsed + delta)
		var amount := smoothstep(0.0, 1.0, _transition_elapsed / maxf(_transition_duration, 0.0001))
		for index in STATE_COUNT:
			_expression_weights[index] = lerpf(_from_weights[index], _target_weights[index], amount)
		_normalize_weights()
	_eye_closure = clampf(_expression_weights[ASLEEP] + _expression_weights[TIRED] * 0.5, 0.0, 1.0)
	_apply_weights()


static func resolve_auto_state(activity: String, resting: bool, napping: bool) -> String:
	if napping:
		return "asleep"
	if resting:
		return "tired"
	if activity == "thinking" or activity == "browsing":
		return "thinking"
	if activity == "checkout":
		return "happy"
	return "content"


func get_expression() -> String:
	return _active_state


func get_current_expression() -> String:
	var best := 0
	for index in STATE_COUNT:
		if _expression_weights[index] > _expression_weights[best]:
			best = index
	return STATE_NAMES[best]


func get_auto_expression() -> String:
	return _auto_state


func is_auto() -> bool:
	return not _explicit


func get_eye_closure() -> float:
	return _eye_closure


## Head-local displacement of the current blended eye centre from the baked
## base at (side * EYE_BASE_X, EYE_BASE_Y). The XY part follows the expression
## targets; Z is re-solved against the head ellipsoid so the eye cannot lift off
## or sink into the face. The rig can add this to an eye bone offset each frame.
func get_eye_offset(side: float) -> Vector3:
	if not _bound or _expression_weights.is_empty():
		return Vector3.ZERO
	var direction := -1.0 if side < 0.0 else 1.0
	var offset := Vector2.ZERO
	for state in STATE_COUNT:
		var state_offset: Vector2 = EYE_OFFSETS[state]
		offset += state_offset * _expression_weights[state]
	var base_x := direction * EYE_BASE_X
	var base := _surface_local(base_x, EYE_BASE_Y)
	var moved := _surface_local(base_x + offset.x, EYE_BASE_Y + offset.y)
	return Vector3(offset.x, offset.y, moved.z - base.z)


func get_blend_weights() -> PackedFloat32Array:
	return _expression_weights.duplicate()


func get_features() -> Array[MeshInstance3D]:
	return _features.duplicate()


func get_closed_eyes() -> Array[MeshInstance3D]:
	return _closed_eyes.duplicate()


func get_feature_kind(instance: MeshInstance3D) -> int:
	return int(_feature_kind.get(instance.get_instance_id(), -1))


func head_radial(point_body: Vector3) -> float:
	var local := point_body - _head_origin
	var rx := maxf(absf(_head_radius.x), 0.0001)
	var ry := maxf(absf(_head_radius.y), 0.0001)
	var rz := maxf(absf(_head_radius.z), 0.0001)
	return (pow(local.x / rx, 2.0) + pow((local.y - _head_center.y) / ry, 2.0)
		+ pow((local.z - _head_center.z) / rz, 2.0))


func _duration_for(duration: float) -> float:
	return transition_seconds if duration < 0.0 else _safe_seconds(duration, transition_seconds)


func _safe_seconds(value: float, fallback: float) -> float:
	if not is_finite(value):
		return clampf(fallback, 0.0, 10.0)
	return clampf(value, 0.0, 10.0)


func _retarget(state: int, seconds: float) -> void:
	state = clampi(state, 0, STATE_COUNT - 1)
	var duration := _safe_seconds(seconds, transition_seconds)
	_from_weights = _expression_weights.duplicate()
	_target_weights.resize(STATE_COUNT)
	_target_weights.fill(0.0)
	_target_weights[state] = 1.0
	_target_state = state
	_active_state = STATE_NAMES[state]
	_transition_duration = duration
	_transition_elapsed = 0.0
	if duration <= 0.00001:
		_expression_weights = _target_weights.duplicate()
		_transition_elapsed = 0.0


func _normalize_weights() -> void:
	var total := 0.0
	for index in STATE_COUNT:
		total += _expression_weights[index]
	if total > 0.00001:
		var inverse := 1.0 / total
		for index in STATE_COUNT:
			_expression_weights[index] *= inverse
	else:
		_expression_weights.fill(0.0)
		_expression_weights[NEUTRAL] = 1.0


func _apply_weights() -> void:
	var reveal := _eye_reveal()
	for instance in _features:
		if not is_instance_valid(instance) or instance.mesh == null:
			continue
		var strength := reveal if _feature_kind[instance.get_instance_id()] == FEATURE_CLOSED_EYE else 1.0
		for state in STATE_COUNT:
			if state < instance.mesh.get_blend_shape_count():
				instance.set_blend_shape_value(state, _expression_weights[state]*strength)
	for instance in _closed_eyes:
		if not is_instance_valid(instance) or instance.mesh == null:
			continue
		var dormant := int(_dormant_index.get(instance.get_instance_id(), -1))
		if dormant >= 0 and dormant < instance.mesh.get_blend_shape_count():
			instance.set_blend_shape_value(dormant, 1.0 - reveal)
		# The curve is sunk inside the head while fully dormant, so changing
		# visibility there cannot pop. It is revealed only when the bean eye is
		# already nearly closed, which avoids two visible eye curves.
		instance.visible = reveal > 0.0005


func _eye_reveal() -> float:
	return smoothstep(0.72, 0.97, _eye_closure)


func _feature_kind_for(instance: MeshInstance3D) -> int:
	var tag := str(instance.get_meta("expression_feature", ""))
	if tag == "mouth":
		return FEATURE_MOUTH
	if tag == "brow":
		return FEATURE_BROW
	if tag == "closed_eye":
		return FEATURE_CLOSED_EYE
	# Safe fallback for rigs built before the metadata was present.
	var label := str(instance.name)
	if label.begins_with("Smile"):
		return FEATURE_MOUTH
	if label.begins_with("Eyebrow"):
		return FEATURE_BROW
	if label.begins_with("ClosedEye"):
		return FEATURE_CLOSED_EYE
	return -1


func _install_feature(instance: MeshInstance3D, kind: int) -> bool:
	if not (instance.mesh is ArrayMesh) or instance.mesh.get_surface_count() != 1:
		return false
	var base: Array = instance.mesh.surface_get_arrays(0)
	if base.size() < Mesh.ARRAY_MAX:
		return false
	var vertices: PackedVector3Array = base[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = base[Mesh.ARRAY_NORMAL]
	if vertices.is_empty() or normals.size() != vertices.size():
		return false
	if vertices.size() % RING_VERTICES != 0:
		return false
	var centers := _ring_centers(vertices)
	var local_centers := PackedVector3Array()
	for center in centers:
		local_centers.append(center - _head_origin)
	var average_x := _average_x(local_centers)
	var side := -1.0 if average_x < 0.0 else 1.0
	var shapes: Array = []
	for state in STATE_COUNT:
		var shape := _make_expression_shape(kind, state, vertices, normals, centers, side, average_x)
		if shape.is_empty():
			return false
		shapes.append(shape)
	if kind == FEATURE_CLOSED_EYE:
		shapes.append(_make_dormant_shape(vertices, normals, centers))
	var mesh := ArrayMesh.new()
	mesh.resource_name = str(instance.mesh.resource_name)
	# Targets are absolute positions. Closed eyes blend with the buried target
	# using normalized weights, matching both Godot and CPU skinning.
	mesh.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_NORMALIZED
	for state_name in STATE_NAMES:
		mesh.add_blend_shape(state_name)
	if kind == FEATURE_CLOSED_EYE:
		mesh.add_blend_shape("dormant")
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, base, shapes)
	if mesh.get_surface_count() != 1 or mesh.get_blend_shape_count() < STATE_COUNT:
		return false
	instance.mesh = mesh
	if kind == FEATURE_CLOSED_EYE:
		_dormant_index[instance.get_instance_id()] = STATE_COUNT
		instance.set_meta("expression_dormant_shape", "dormant")
	instance.set_meta("expression_states", STATE_NAMES)
	return true


func _make_expression_shape(kind: int, state: int, vertices: PackedVector3Array,
		normals: PackedVector3Array, centers: PackedVector3Array, side: float,
		eye_x: float) -> Array:
	var points := _shape_points(kind, state, side, eye_x)
	if points.size() != centers.size():
		return []
	var target_centers := PackedVector3Array()
	target_centers.resize(centers.size())
	for index in centers.size():
		var point: Vector2 = points[index]
		target_centers[index] = _head_origin + _surface_local(point.x, point.y)
	var target_vertices := PackedVector3Array()
	target_vertices.resize(vertices.size())
	var target_normals := PackedVector3Array()
	target_normals.resize(vertices.size())
	for ring in centers.size():
		var rotation := _arc_rotation(_ring_tangent(centers, ring), _ring_tangent(target_centers, ring))
		for column in RING_VERTICES:
			var index := ring * RING_VERTICES + column
			var rotated := rotation * (vertices[index] - centers[ring])
			target_vertices[index] = target_centers[ring] + rotated
			var direction := rotated.normalized()
			if not _finite(direction) or direction.length_squared() < 0.000001:
				direction = normals[index]
			target_normals[index] = direction.normalized()
	var shape: Array = []
	shape.resize(Mesh.ARRAY_MAX)
	shape[Mesh.ARRAY_VERTEX] = target_vertices
	shape[Mesh.ARRAY_NORMAL] = target_normals
	return shape


func _make_dormant_shape(vertices: PackedVector3Array, normals: PackedVector3Array,
		centers: PackedVector3Array) -> Array:
	var target_vertices := PackedVector3Array()
	target_vertices.resize(vertices.size())
	var target_normals := PackedVector3Array()
	target_normals.resize(vertices.size())
	for ring in centers.size():
		var inward := _ellipsoid_normal(centers[ring])
		for column in RING_VERTICES:
			var index := ring * RING_VERTICES + column
			target_vertices[index] = vertices[index] - inward * DORMANT_SINK
			var direction := normals[index]
			if not _finite(direction) or direction.length_squared() < 0.000001:
				direction = inward
			target_normals[index] = direction.normalized()
	var shape: Array = []
	shape.resize(Mesh.ARRAY_MAX)
	shape[Mesh.ARRAY_VERTEX] = target_vertices
	shape[Mesh.ARRAY_NORMAL] = target_normals
	return shape


func _shape_points(kind: int, state: int, side: float, eye_x: float) -> Array:
	if kind == FEATURE_MOUTH:
		var curve: Array = []
		var anchors: Array = MOUTH_POINTS[state]
		var mouth_offset: Vector2 = MOUTH_OFFSETS[state]
		for index in 9:
			var t := float(index)/8
			if state == SURPRISED:
				curve.append(Vector2(.018*cos(t*TAU),.12+.023*sin(t*TAU)) + mouth_offset)
			else:
				var u := 1.0-t
				curve.append(anchors[0]*u*u*u+anchors[1]*3*u*u*t+anchors[2]*3*u*t*t+anchors[3]*t*t*t + mouth_offset)
		return curve
	if kind == FEATURE_BROW:
		var brows: Array = []
		var side_index := 0 if side >= 0.0 else 1
		var brow_offset: Vector2 = BROW_OFFSETS[state][side_index]
		for point in BROW_POINTS[state]:
			brows.append(Vector2(point.x * side, point.y) + brow_offset)
		return brows
	var eyes: Array = []
	var eye_offset: Vector2 = EYE_OFFSETS[state]
	for point in DollExpressions.closed_eye_curve(CLOSED_EYE_POINTS[state]):
		eyes.append(Vector2(eye_x + point.x, point.y) + eye_offset)
	return eyes


func _ring_centers(vertices: PackedVector3Array) -> PackedVector3Array:
	var centers := PackedVector3Array()
	centers.resize(vertices.size() / RING_VERTICES)
	for ring in centers.size():
		var center := Vector3.ZERO
		# The last vertex duplicates the seam; exclude it from the mean.
		for column in RING_VERTICES - 1:
			center += vertices[ring * RING_VERTICES + column]
		centers[ring] = center / float(RING_VERTICES - 1)
	return centers


func _average_x(points: PackedVector3Array) -> float:
	if points.is_empty():
		return 0.0
	var total := 0.0
	for point in points:
		total += point.x
	return total / float(points.size())


func _surface_local(x: float, y: float) -> Vector3:
	var rx := maxf(absf(_head_radius.x), 0.0001)
	var ry := maxf(absf(_head_radius.y), 0.0001)
	var rz := maxf(absf(_head_radius.z), 0.0001)
	var radial := 1.0 - pow(x / rx, 2.0) - pow((y - _head_center.y) / ry, 2.0)
	return Vector3(x, y, _head_center.z + rz * sqrt(maxf(radial, 0.0)))


func _project_body(point_body: Vector3) -> Vector3:
	var local := point_body - _head_origin
	return _head_origin + _surface_local(local.x, local.y)


func _ellipsoid_normal(point_body: Vector3) -> Vector3:
	var local := point_body - _head_origin
	var rx := maxf(absf(_head_radius.x), 0.0001)
	var ry := maxf(absf(_head_radius.y), 0.0001)
	var rz := maxf(absf(_head_radius.z), 0.0001)
	var normal := Vector3(local.x / (rx * rx), (local.y - _head_center.y) / (ry * ry),
		(local.z - _head_center.z) / (rz * rz))
	if normal.length_squared() < 0.000001:
		return Vector3(0.0, 0.0, 1.0)
	return normal.normalized()


func _ring_tangent(centers: PackedVector3Array, ring: int) -> Vector3:
	var previous := centers[maxi(ring - 1, 0)]
	var next := centers[mini(ring + 1, centers.size() - 1)]
	var tangent := next - previous
	if tangent.length_squared() < 0.000001:
		return Vector3.RIGHT
	return tangent.normalized()


func _arc_rotation(from: Vector3, to: Vector3) -> Quaternion:
	if from.length_squared() < 0.000001 or to.length_squared() < 0.000001:
		return Quaternion()
	var start := from.normalized()
	var end := to.normalized()
	if start.dot(end) < -0.9999:
		return Quaternion()
	return Quaternion(start, end)


func _finite(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)
