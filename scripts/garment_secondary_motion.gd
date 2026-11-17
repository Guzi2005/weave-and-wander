extends RefCounted
## Live-input counterpart of PleatedSkirtDynamics.SkirtInertia: fixed-step
## damped twist/opening modes driven by real root motion, never a looping animation.
const ROWS := 9
const STEP := 1.0 / 120.0
var states := PackedVector4Array()
var velocities := PackedVector4Array()
var _accumulator := 0.0
var _input_integral := Vector4.ZERO
var _initialized := false
var _previous_position := Vector3.ZERO
var _previous_yaw := 0.0
var _previous_velocity := Vector2.ZERO
var _previous_omega := 0.0
var steps := 0


func _init() -> void:
	states.resize(ROWS)
	velocities.resize(ROWS)
	clear()


func clear() -> void:
	_clear_motion()
	_initialized = false
	_previous_velocity = Vector2.ZERO
	_previous_omega = 0.0


func _clear_motion() -> void:
	states.fill(Vector4.ZERO)
	velocities.fill(Vector4.ZERO)
	_accumulator = 0.0
	_input_integral = Vector4.ZERO


func advance(delta: float, root: Transform3D, fabric: Resource, support_blend := 0.0) -> void:
	if delta <= 0.0: return
	var forward := root.basis.z.normalized()
	var yaw := atan2(forward.x, forward.z)
	var distance := root.origin.distance_to(_previous_position)
	if not _initialized or distance > 2.0 or delta > .3:
		clear()
		_initialized = true
		_previous_position = root.origin
		_previous_yaw = yaw
		return
	var world_velocity := Vector2(root.origin.x - _previous_position.x, root.origin.z - _previous_position.z) / delta
	var yaw_delta := angle_difference(_previous_yaw, yaw)
	var omega := clampf(yaw_delta / delta, -12, 12)
	var angular_acceleration := clampf((omega - _previous_omega) / delta, -80, 80)
	var world_acceleration := (world_velocity - _previous_velocity) / delta
	var local_acceleration := root.basis.orthonormalized().inverse() * Vector3(world_acceleration.x, 0, world_acceleration.y)
	var acceleration := Vector2(local_acceleration.x, local_acceleration.z).limit_length(16.0)
	# State is root-local; preserve the world direction of existing sway on turns.
	var rebase := Basis(Vector3.UP, -yaw_delta)
	var pending := rebase * Vector3(_input_integral.z, 0, _input_integral.w)
	_input_integral.z = pending.x
	_input_integral.w = pending.z
	for row in range(1, ROWS):
		var offset := rebase * Vector3(states[row].z, 0, states[row].w)
		var velocity := rebase * Vector3(velocities[row].z, 0, velocities[row].w)
		states[row].z = offset.x
		states[row].w = offset.z
		velocities[row].z = velocity.x
		velocities[row].w = velocity.z
	_previous_position = root.origin
	_previous_yaw = yaw
	_previous_velocity = world_velocity
	_previous_omega = omega
	if not fabric.enabled or support_blend >= .35:
		# Keep kinematic history warm while cloth is disabled or supported.
		_clear_motion()
		return
	# Integrate input over each simulation interval, including render frames shorter
	# than STEP. Otherwise a start/stop impulse can vanish between physics ticks.
	var remaining := delta
	var input := Vector4(omega * omega, angular_acceleration, acceleration.x, acceleration.y)
	while remaining > .00000001:
		var duration := minf(remaining, STEP - _accumulator)
		_input_integral += input * duration
		_accumulator += duration
		remaining -= duration
		if _accumulator + .00000001 >= STEP:
			var averaged := _input_integral / STEP
			_integrate(STEP, averaged.x, averaged.y, Vector2(averaged.z, averaged.w), fabric)
			_accumulator = 0.0
			_input_integral = Vector4.ZERO
			steps += 1


func _integrate(dt: float, angular_speed_squared: float, angular_acceleration: float, acceleration: Vector2, fabric: Resource) -> void:
	var mass: float = fabric.mass_ratio()
	var bend: float = clampf(fabric.bending_stiffness, 0, 1)
	var stiffness := (22.0 + 46.0 * bend) / mass
	var damping_ratio: float = .25 + clampf(fabric.internal_damping, 0, 1) * .95
	for row in range(1, ROWS):
		var s := float(row) / (ROWS - 1)
		var freedom: float = fabric.freedom(s)
		var k := stiffness / (.5 + .5 * s)
		var damping := 2.0 * sqrt(k) * damping_ratio
		var radius := lerpf(.25, .39, s)
		var centrifugal := angular_speed_squared * radius
		var reserve: float = .25 + .35 * fabric.pleat_reserve()
		var open_target: float = minf(fabric.maximum_opening, centrifugal / (9.81 + centrifugal) * reserve * (1.0 - .6 * bend)) * freedom
		var force := Vector4(-angular_acceleration * .32 * freedom, k * open_target,
			-acceleration.x * .18 * freedom, -acceleration.y * .18 * freedom)
		velocities[row] += (force - states[row] * k - velocities[row] * damping) * dt
		states[row] += velocities[row] * dt
		var limits := Vector4(deg_to_rad(fabric.maximum_twist_degrees) * freedom,
			fabric.maximum_opening * freedom, fabric.maximum_sway * freedom, fabric.maximum_sway * freedom)
		for axis in 4:
			var lower: float = 0.0 if axis == 1 else -limits[axis]
			var bounded := clampf(states[row][axis], lower, limits[axis])
			if bounded != states[row][axis]: velocities[row][axis] = 0.0
			states[row][axis] = bounded
	states[0] = Vector4.ZERO
	velocities[0] = Vector4.ZERO


func sample(s: float) -> Vector4:
	var u := clampf(s, 0, 1) * (ROWS - 1)
	var row := mini(ROWS - 2, int(floor(u)))
	return states[row].lerp(states[row + 1], u - row)


func is_active() -> bool:
	for state in states:
		if state.length_squared() > .0000000001: return true
	return false


func deform_normal(point: Vector3, normal: Vector3, s: float, hips: Transform3D, amount: float, stretch: float) -> Vector3:
	if amount <= 0.0: return normal
	var n := normal.normalized()
	var axis := Vector3.UP if absf(n.y) < .9 else Vector3.RIGHT
	var tangent := axis.cross(n).normalized()
	var bitangent := n.cross(tangent)
	var inverse := hips.basis.inverse()
	var moved := deform(point, s, hips, amount, stretch)
	var t := deform(point + tangent * .001, clampf(s - (inverse * tangent).y * .001 / 1.11, 0, 1), hips, amount, stretch) - moved
	var b := deform(point + bitangent * .001, clampf(s - (inverse * bitangent).y * .001 / 1.11, 0, 1), hips, amount, stretch) - moved
	var candidate := t.cross(b)
	return candidate.normalized() if candidate.length_squared() > .000000000001 else normal


func deform(point: Vector3, s: float, hips: Transform3D, amount: float, stretch: float) -> Vector3:
	if amount <= 0.0 or s <= 0.0: return point
	var p := hips.affine_inverse() * point
	var state := sample(s) * amount
	var radius := Vector2(p.x, p.z).length()
	var rotated := Basis(Vector3.UP, state.x) * p
	var expansion := 1.0 + state.y / maxf(radius, .001)
	rotated.x = rotated.x * expansion + state.z
	rotated.z = rotated.z * expansion + state.w
	# Opening consumes meridian length, rather than stretching the skirt sideways.
	var drop := maxf(.001, 1.11 * s)
	var radial_run := maxf(0, radius - .25)
	var meridian_sq := drop * drop + radial_run * radial_run
	var remaining := sqrt(maxf(0, meridian_sq - pow(radial_run + state.y, 2)))
	rotated.y += (drop - remaining) * lerpf(.55, 1.0, clampf(stretch, 0, 1))
	return hips * rotated
