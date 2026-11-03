@tool
extends Node3D

const PANEL_COUNT := 12
const PANEL_WIDTH := 0.195
const HEIGHT := 2.98
const OPEN_WIDTH := 0.36
const CLOSED_WIDTH := 2.10
const DURATION := 0.85
var amount := 0.0
var target := 0.0
var panels: Array[MeshInstance3D] = []
var closed_width := CLOSED_WIDTH


func build(material: Material) -> void:
	for i in PANEL_COUNT:
		var panel := MeshInstance3D.new()
		panel.name = "PaperPleat%02d" % i
		var mesh := BoxMesh.new()
		mesh.size = Vector3(PANEL_WIDTH, HEIGHT, 0.014)
		panel.mesh = mesh
		panel.material_override = material
		add_child(panel)
		panels.append(panel)
	_pose()


func set_closed(closed: bool) -> void:
	target = 1.0 if closed else 0.0


func advance(delta: float) -> void:
	if delta <= 0 or is_equal_approx(amount, target):
		return
	amount = move_toward(amount, target, delta / DURATION)
	_pose()


func is_closed() -> bool:
	return amount >= 0.999 and target == 1.0


func is_open() -> bool:
	return amount <= 0.001 and target == 0.0


func _pose() -> void:
	var width := lerpf(OPEN_WIDTH, CLOSED_WIDTH, smoothstep(0, 1, amount))
	var dx := width / PANEL_COUNT
	# Rigid paper leaves keep their width; only the concertina hinge angles change.
	var depth := sqrt(PANEL_WIDTH * PANEL_WIDTH - dx * dx)
	for i in panels.size():
		var dz := depth if i % 2 == 0 else -depth
		panels[i].position = Vector3(-closed_width * .5 + (i + 0.5) * dx, 1.63, 0)
		panels[i].rotation.y = atan2(-dz, dx)
