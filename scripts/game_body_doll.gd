class_name GameBodyDoll
extends "res://scripts/shorter_arm_body.gd"

const FittedShell = preload("res://components/accepted_body_shell.gd")
const BodyFit = preload("res://scripts/accepted_body_fit.gd")
const ShapeProfile = preload("res://components/garment_shape_profile.gd")
@export var cloth_contact: Resource = preload("res://components/cloth_contact_profile.gd").new()
@export var skirt_fabric: Resource = preload("res://components/garment_fabric_profile.gd").new()
@export var skirt_shape: Resource = _skirt_shape()
@export var shell_shape: Resource = _shell_shape()
var body_contact: RefCounted


static func _skirt_shape() -> Resource:
	var shape := ShapeProfile.new()
	shape.bridge_tension = .85
	return shape


static func _shell_shape() -> Resource:
	var shape := ShapeProfile.new()
	shape.root_height = 1.93
	shape.hem_height = 1.13
	shape.bridge_tension = .8
	shape.contour_strength = ShapeProfile._curve([Vector2(0, 0), Vector2(.55, 0), Vector2(1, 1)])
	return shape


func _new_garment_shell() -> MeshInstance3D:
	return FittedShell.new()


func _lathe(parent: Node3D, label: String, rings: Array, color: Color,
		segments: int = 24, folds: float = 0.0, caps: bool = true,
		x_offsets: Array = [], z_offsets: Array = []) -> MeshInstance3D:
	if label in ["LongSkirt", "Trouser"]:
		# Garments are tubes, not solid lathes: a closing disk cuts through ankles
		# and folded legs, and cannot behave as a free cloth hem.
		caps = false
		var refined: Array = []
		var refined_x: Array = []
		var refined_z: Array = []
		for i in rings.size() - 1:
			var count := maxi(1, ceili(absf(rings[i + 1].x - rings[i].x) / .055))
			for j in count:
				var t := float(j) / count
				refined.append(rings[i].lerp(rings[i + 1], t))
				if not x_offsets.is_empty(): refined_x.append(lerpf(x_offsets[i], x_offsets[i + 1], t))
				if not z_offsets.is_empty(): refined_z.append(lerpf(z_offsets[i], z_offsets[i + 1], t))
		refined.append(rings.back())
		if not x_offsets.is_empty():
			refined_x.append(x_offsets.back())
			x_offsets = refined_x
		if not z_offsets.is_empty():
			refined_z.append(z_offsets.back())
			z_offsets = refined_z
		rings = refined
	return super(parent, label, rings, color, segments, folds, caps, x_offsets, z_offsets)


func _prepare_body_for_rig() -> void:
	body_rig.set_meta("accepted_body_version", "v20-short-arm-0045")
	BodyFit.new().apply(self, cloth_contact)
	_build_fitted_cuffs()
	if outfit_style == 2 and clothes_root.get_node_or_null("TrouserWaistband") == null:
		var seat := _lathe(clothes_root, "TrouserSeat", [Vector3(1.02, .21, .18),
			Vector3(1.09, .27, .20), Vector3(1.19, .27, .20)],
			get_outfit_color().darkened(.12), 32, 0.0, false)
		seat.set_meta("garment_slot", "bottom")
		seat.set_meta("skin_profile", "trouser_seat")


func _cuff_rim(_parent: Node3D, _edge_color: Color, _inside_color: Color) -> void:
	pass


func _build_fitted_cuffs() -> void:
	if not is_instance_valid(_garment) or not _garment.visible: return
	var arrays := _garment.mesh.surface_get_arrays(0)
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var source: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var weights: PackedFloat32Array = _garment.get_meta("garment_arm_weights")
	var counts := {}
	for i in range(0, source.size(), 3):
		for j in 3:
			var a := source[i + j]
			var b := source[i + (j + 1) % 3]
			var key := Vector2i(mini(a, b), maxi(a, b))
			counts[key] = counts.get(key, 0) + 1
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var arms_weights := PackedFloat32Array()
	for edge: Vector2i in counts:
		if counts[edge] != 1 or absf(weights[edge.x]) < .95 or points[edge.x].y > 1.5: continue
		var start := vertices.size()
		for id in [edge.x, edge.y]:
			var n: Vector3 = arrays[Mesh.ARRAY_NORMAL][id]
			vertices.append(points[id] + n * .006)
			vertices.append(points[id] + n * .006 + Vector3.UP * .022)
			normals.append(n)
			normals.append(n)
			arms_weights.append(weights[id])
			arms_weights.append(weights[id])
		indices.append_array(PackedInt32Array([start, start + 1, start + 2, start + 2, start + 1, start + 3]))
	if vertices.is_empty(): return
	var cuff := _mesh(clothes_root, "CuffBinding", vertices, normals, indices, _costume_palette()[1])
	cuff.set_meta("garment_arm_weights", arms_weights)
	cuff.set_meta("garment_slot", "top")


func _build_appearance() -> void:
	body_contact = null
	super()
	set_underbody_mode(false)
	body_contact = preload("res://scripts/cloth_body_contact.gd").new()
	body_contact.setup(self)


func _update_puppet_motion(delta: float) -> void:
	super(delta)
	if rig != null and rest_mode == "sit" and activity == "resting" and _rest_blend > 0.0:
		# Same accepted arm lengths; place the palms on top of the fitted lap.
		for suffix in ["L", "R"]:
			var side := -1.0 if suffix == "L" else 1.0
			rig._rest_arm(suffix, Vector3(side * .24, 1.39, .47),
				Vector3(side * .49, 1.37, .12), smoothstep(0.0, 1.0, _rest_blend))
	if body_contact != null:
		body_contact.advance(delta)
		body_contact.update()


func apply_reaches() -> void:
	super()
	if body_contact != null: body_contact.update()


func set_underbody_mode(underbody_only: bool) -> void:
	is_underbody_mode = underbody_only
	if not is_instance_valid(body_rig) or rig == null: return
	for part: MeshInstance3D in rig.meshes:
		var label := str(part.name)
		var semantic: String = part.get_meta("semantic", "")
		if label in ["Neck", "Calf", "Mitten", "Thumb"]:
			part.hide()
		elif part.get_meta("is_underbody", false):
			part.show()
		elif semantic not in ["head", "hair", "shoeL", "shoeR"]:
			if not part.has_meta("dressed_visibility"):
				part.set_meta("dressed_visibility", part.visible or (label == "Trouser" and not _covers_legs()))
			part.visible = not underbody_only and part.get_meta("dressed_visibility")
