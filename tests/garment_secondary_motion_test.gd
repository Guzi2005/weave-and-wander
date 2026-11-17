extends SceneTree
const Motion = preload("res://scripts/garment_secondary_motion.gd")
const Fabric = preload("res://components/garment_fabric_profile.gd")
var checks := 0
var failures: Array[String] = []


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)


func drive(fabric: Resource, fps: int, duration := 2.0, direction := 1.0) -> RefCounted:
	var motion := Motion.new()
	var dt := 1.0 / fps
	motion.advance(dt, Transform3D.IDENTITY, fabric)
	for frame in int(duration * fps):
		var t := (frame + 1.0) * dt
		var angle := 1.2 * t * t if t < 1.0 else 1.2 + 2.4 * (t - 1.0)
		motion.advance(dt, Transform3D(Basis(Vector3.UP, angle * direction), Vector3.ZERO), fabric)
		check(motion.states[0] == Vector4.ZERO, "Waist anchor moved")
		for state in motion.states: check(state.is_finite(), "Nonfinite motion")
	return motion


func start_trace(fps: int) -> float:
	var motion := Motion.new()
	var fabric := Fabric.new()
	var dt := 1.0 / fps
	motion.advance(dt, Transform3D.IDENTITY, fabric)
	var peak := 0.0
	for frame in fps:
		var t := (frame + 1.0) * dt
		motion.advance(dt, Transform3D(Basis.IDENTITY, Vector3(.02 * t, 0, 0)), fabric)
		peak = maxf(peak, absf(motion.states[-1].z))
	return peak


func check_warm_history(supported: bool) -> void:
	var motion := Motion.new()
	var fabric := Fabric.new()
	fabric.enabled = supported
	for frame in 20:
		motion.advance(1.0 / 60, Transform3D(Basis.IDENTITY, Vector3(frame * .01, 0, 0)), fabric, 1.0 if supported else 0.0)
	fabric.enabled = true
	motion.advance(1.0 / 60, Transform3D(Basis.IDENTITY, Vector3(.2, 0, 0)), fabric)
	check(motion.states[-1].length() < .000001, "Re-enabling steady motion injected acceleration (supported=%s)" % supported)


func _initialize() -> void:
	var fabric := Fabric.new()
	var idle := Motion.new()
	for i in 300: idle.advance(1.0 / 60, Transform3D.IDENTITY, fabric)
	check(not idle.is_active(), "Stationary clothing must remain unchanged")
	var spin := drive(fabric, 60)
	check(spin.states[-1].y > .005, "Spin did not open hem")
	check(spin.steps == 240, "Fixed-step count drifted")
	var peak: float = spin.states[-1].length()
	var final_root := Transform3D(Basis(Vector3.UP, 3.6), Vector3.ZERO)
	spin.advance(1.0 / 60, final_root, fabric)
	check(spin.is_active(), "Hem stopped instantly with body")
	for i in 600: spin.advance(1.0 / 60, final_root, fabric)
	check(spin.states[-1].length() < peak * .001, "Motion did not settle")
	var low := drive(fabric, 30)
	var high := drive(fabric, 120)
	var reverse := drive(fabric, 60, 2.0, -1.0)
	var forward := drive(fabric, 60)
	check(absf(reverse.states[-1].x + forward.states[-1].x) < .0001, "Mirrored turns have asymmetric lag")
	check(absf(reverse.states[-1].y - forward.states[-1].y) < .0001, "Spin direction changed radial opening")
	check(low.states[-1].distance_to(high.states[-1]) < .006, "Frame-rate dependence exceeds tolerance")
	var peak_120 := start_trace(120)
	check(peak_120 > .0001, "Start trace failed to excite sway")
	for fps in [30, 60, 144, 240, 480]:
		check(absf(start_trace(fps) - peak_120) < .00002, "Substep start impulse lost at %s FPS" % fps)
	check_warm_history(false)
	check_warm_history(true)
	var soft := Fabric.new()
	soft.bending_stiffness = .1
	var stiff := Fabric.new()
	stiff.bending_stiffness = .95
	var soft_motion := drive(soft, 60)
	var stiff_motion := drive(stiff, 60)
	check(soft_motion.states[-1].y > stiff_motion.states[-1].y, "Bending stiffness has no opening effect")
	var heavy := Fabric.new()
	heavy.density_gsm = 600
	var heavy_motion := drive(heavy, 60, .6)
	var light_motion := drive(fabric, 60, .6)
	check(heavy_motion.states[-1].distance_to(light_motion.states[-1]) > .002, "Density has no inertial effect")
	var pleated := Fabric.new()
	pleated.pleat_count = 40
	pleated.pleat_depth_cm = 2
	check(pleated.mass_ratio() > fabric.mass_ratio(), "Pleat area missing from mass")
	var pleated_motion := drive(pleated, 60)
	check(pleated_motion.states[-1].y > low.states[-1].y, "Pleat reserve does not affect opening")
	var point := Vector3(.36, .3, .14)
	check(low.deform(point, 0, Transform3D.IDENTITY, 1, .8) == point, "Pinned root deformed")
	check(low.deform(point, 1, Transform3D.IDENTITY, 0, .8) == point, "Disabled deformation not identity")
	var normal: Vector3 = low.deform_normal(point, Vector3.RIGHT, .9, Transform3D.IDENTITY, 1, .8)
	check(normal.is_finite() and absf(normal.length() - 1) < .0001, "Motion normal invalid")
	var paused: PackedVector4Array = low.states.duplicate()
	low.advance(0, Transform3D.IDENTITY, fabric)
	check(low.states == paused, "Pause changed cloth")
	low.advance(1.0 / 60, Transform3D(Basis.IDENTITY, Vector3(20, 0, 0)), fabric)
	check(not low.is_active(), "Teleport injected cloth impulse")
	high.advance(1.0 / 60, final_root, fabric, 1.0)
	check(not high.is_active(), "Supported rest pose retained spin")
	fabric.enabled = false
	soft_motion.advance(1.0 / 60, final_root, fabric)
	check(not soft_motion.is_active(), "Off switch retained motion")
	var thin := Fabric.new()
	var thick := Fabric.new()
	thick.thickness_mm = 3
	check(thick.mass_ratio() == thin.mass_ratio(), "Thickness double-counted areal density")
	check(thick.collision_margin() > thin.collision_margin(), "Thickness has no contact effect")
	print("GARMENT_SECONDARY_MOTION checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
