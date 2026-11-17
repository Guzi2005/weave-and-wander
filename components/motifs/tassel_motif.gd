class_name TasselMotif
extends Resource

## Parametric yarn-pompon tassel: a bound head, hanging yarn strands and
## small puff balls clustered toward the bottom, in alternating colors.
## Geometry is deterministic from `seed`. Returns one geometry Dictionary
## per color so each can share the doll's flat-ink material pipeline.

@export var colors: Array[Color] = [Color("d9b13b"), Color("7e4a8c")]
@export_range(4, 64) var strand_count: int = 24
@export_range(0, 40) var puff_count: int = 14
@export_range(.02, .3) var length: float = .095
@export_range(.01, .12) var spread: float = .038
@export_range(.001, .02) var strand_radius: float = .0026
@export_range(.004, .04) var puff_radius: float = .012
@export var seed: int = 7

const Mosuo = preload("res://components/mosuo_costume.gd")


func build(top: Vector3) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var groups := {}
	for index in colors.size():
		groups[index] = {"vertices": PackedVector3Array(), "indices": PackedInt32Array(),
			"arm_weights": PackedFloat32Array()}
	# Bound head uses the first color.
	Mosuo._append_sphere(groups[0].vertices, groups[0].indices, groups[0].arm_weights,
		top + Vector3(0, .004, 0), .012)
	for strand in strand_count:
		var color_index := strand % colors.size()
		var data: Dictionary = groups[color_index]
		var angle := TAU * strand / float(strand_count) + rng.randf_range(-.06, .06)
		var direction := Vector3(cos(angle), 0, sin(angle))
		var strand_length := length * rng.randf_range(.80, 1.02)
		var from := top + direction * .006
		var mid := top + direction * (spread * .35) + Vector3(0, -strand_length * .50, 0)
		var to := top + direction * (spread * .70) + Vector3(0, -strand_length, 0)
		_strand(from, mid, strand_radius, data)
		_strand(mid, to, strand_radius * .85, data)
	for puff in puff_count:
		var color_index := puff % colors.size()
		var data: Dictionary = groups[color_index]
		var angle := TAU * puff / float(puff_count) + rng.randf_range(-.2, .2)
		var drop := length * rng.randf_range(.80, 1.05)
		var radial := spread * 0.75 * sqrt(rng.randf())
		var center := top + Vector3(cos(angle) * radial, -drop, sin(angle) * radial)
		var radius := puff_radius * rng.randf_range(.85, 1.15)
		Mosuo._append_sphere(data.vertices, data.indices, data.arm_weights, center, radius)
	var out := {}
	for index in groups.size():
		var data: Dictionary = groups[index]
		out[index] = Mosuo._finish(data.vertices, data.indices, data.arm_weights, "bottom")
	return out


func _strand(from: Vector3, to: Vector3, radius: float, data: Dictionary) -> void:
	var vertices: PackedVector3Array = data.vertices
	var indices: PackedInt32Array = data.indices
	var weights: PackedFloat32Array = data.arm_weights
	var base := vertices.size()
	var tangent := (to - from).normalized()
	var horizontal := tangent.cross(Vector3.FORWARD).normalized()
	var vertical := tangent.cross(horizontal).normalized()
	for end in 2:
		var center := from if end == 0 else to
		for column in 6:
			var angle := TAU * column / 6.0
			vertices.append(center + (horizontal * cos(angle) + vertical * sin(angle)) * radius)
			weights.append(0.0)
	for column in 6:
		var a := base + column
		var b := base + 6 + column
		var a2 := base + (column + 1) % 6
		var b2 := base + 6 + (column + 1) % 6
		indices.append_array(PackedInt32Array([a, b, a2, a2, b, b2]))


func parameters() -> Dictionary:
	var hex := []
	for color in colors:
		hex.append(color.to_html())
	return {"motif": "yarn_pompon_tassel", "colors": hex, "strand_count": strand_count,
		"puff_count": puff_count, "length": length, "spread": spread,
		"strand_radius": strand_radius, "puff_radius": puff_radius, "seed": seed}
