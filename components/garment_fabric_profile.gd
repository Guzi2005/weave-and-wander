@tool
extends Resource
## Game-scale secondary motion, not a calibrated CLO material or cloth solver.
## Density, thickness, bending and stretch are independent fabric properties.

@export var enabled := true
@export_range(40.0, 800.0, 5.0) var density_gsm := 180.0
@export_range(0.1, 4.0, 0.1) var thickness_mm := 0.7
@export_range(0.0, 1.0, 0.01) var bending_stiffness := 0.55
@export_range(0.0, 1.0, 0.01) var stretch_stiffness := 0.85
@export_range(0.0, 1.0, 0.01) var internal_damping := 0.65
@export_group("Pleat Structure")
@export_range(0, 128, 1) var pleat_count := 0
@export_range(0.0, 4.0, 0.1) var pleat_depth_cm := 0.0
@export_range(80.0, 400.0, 1.0) var hem_circumference_cm := 200.0
@export_group("Motion Limits")
@export_range(0.0, 30.0, 0.5) var maximum_twist_degrees := 18.0
@export_range(0.0, 0.15, 0.005) var maximum_sway := 0.045
@export_range(0.0, 0.2, 0.005) var maximum_opening := 0.08
@export var motion_freedom: Curve = _freedom_curve()


static func _freedom_curve() -> Curve:
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0))
	curve.add_point(Vector2(.15, .02))
	curve.add_point(Vector2(.55, .45))
	curve.add_point(Vector2(1, 1))
	return curve


func freedom(s: float) -> float:
	if s <= 0.0: return 0.0
	return clampf(motion_freedom.sample_baked(clampf(s, 0, 1)), 0, 1) if motion_freedom else s * s


func mass_ratio() -> float:
	# Added folded area contributes mass; thickness does not double-count areal density.
	return clampf(density_gsm / 180.0, .22, 4.5) * (1.0 + pleat_reserve())


func pleat_reserve() -> float:
	return clampf(2.0 * pleat_count * pleat_depth_cm / maxf(hem_circumference_cm, 1), 0, 2)


func collision_margin() -> float:
	return clampf(thickness_mm, .1, 4.0) * .001


func import_pleated_design(design: Dictionary) -> void:
	var p: Dictionary = design.get("parameters", {})
	thickness_mm = clampf(float(p.get("thickness_mm", .7)), .1, 4)
	pleat_count = clampi(int(p.get("pleat_count", 0)), 0, 128)
	pleat_depth_cm = clampf(float(p.get("pleat_depth_cm", 0)), 0, 4)
	hem_circumference_cm = clampf(float(p.get("hem_cm", 200)), 80, 400)
	var drape := preload("res://scripts/pleated_skirt_dynamics.gd").effective_drape(design)
	bending_stiffness = drape.bending
	# Legacy weight is normalized/art-directed, not measured grams per square metre.
	density_gsm = lerpf(70, 400, drape.weight)
