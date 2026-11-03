extends RefCounted
const Costume = preload("res://components/ukrainian_costume.gd")
const COLOR_SHOE = Color("674137")
var doll: Node3D

func apply(target: Node3D) -> void:
	doll = target
	_strip_base_costume()
	_part(doll.clothes_root, "UkrShirt", Costume.shirt_body(), Costume.COLOR_SHIRT)
	_part(doll.clothes_root, "UkrShirtCollar", Costume.shirt_collar(), Costume.COLOR_SHIRT)
	_part(doll.clothes_root, "UkrCuffs", Costume.shirt_cuffs(), Costume.COLOR_SHIRT)
	_part(doll.clothes_root, "UkrNeckBow", Costume.neck_bow(), Costume.COLOR_RIBBON)
	var beads = Costume.neck_beads()
	_part(doll.clothes_root, "UkrBeadsDark", beads["dark"], Costume.COLOR_BEAD_DARK)
	_part(doll.clothes_root, "UkrBeadsLight", beads["light"], Costume.COLOR_BEAD_LIGHT)
	_part(doll.skirt_root, "UkrUnderskirt", Costume.underskirt(), Costume.COLOR_SHIRT)
	_part(doll.skirt_root, "UkrUnderskirtHemA", Costume.underskirt_hem_band(.90, .915), Costume.COLOR_SHIRT.darkened(.10))
	_part(doll.skirt_root, "UkrUnderskirtHemB", Costume.underskirt_hem_band(.96, .975), Costume.COLOR_SHIRT.darkened(.06))
	_part(doll.skirt_root, "UkrOverskirtBase", Costume.overskirt("base"), Costume.stripe_asset().color_for("base"))
	_part(doll.skirt_root, "UkrOverskirtShade", Costume.overskirt("base_shade"), Costume.stripe_asset().color_for("base_shade"))
	_part(doll.skirt_root, "UkrOverskirtYellow", Costume.overskirt("yellow"), Costume.stripe_asset().color_for("yellow"))
	_part(doll.skirt_root, "UkrOverskirtGreen", Costume.overskirt("green"), Costume.stripe_asset().color_for("green"))
	_part(doll.skirt_root, "UkrOverskirtPurple", Costume.overskirt("purple"), Costume.stripe_asset().color_for("purple"))
	_part(doll.skirt_root, "UkrApron", Costume.apron(), Costume.COLOR_APRON)
	_part(doll.skirt_root, "UkrApronHemBand", Costume.apron_hem_band(), Costume.COLOR_APRON.darkened(.15))
	_part(doll.clothes_root, "UkrSashWrap", Costume.sash_wrap(), Costume.COLOR_SASH)
	_part(doll.clothes_root, "UkrSashKnot", Costume.sash_knot(), Costume.COLOR_SASH)
	for side in [-1.0, 1.0]:
		var suffix = "L" if side < 0.0 else "R"
		_part(doll.clothes_root, "UkrSashTail" + suffix, Costume.sash_tail(side), Costume.COLOR_SASH)
		var groups = Costume.sash_tassels(side)
		for index in groups.size():
			var color: Color = Costume.tassel_asset().colors[index]
			_part(doll.clothes_root, "UkrTassel%d%s" % [index, suffix], groups[index], color)


func _strip_base_costume() -> void:
	# Same removal set as MosuoDoll: only generic outfit-0 clothing; body,
	# head, hair, doll.arms, calves and shoes stay.
	if doll._garment != null:
		doll._garment.free()
		doll._garment = null
	for label in ["WaistRibbon", "StandingCollar", "ButtonRow", "FlowerCenter"]:
		var node = doll.clothes_root.get_node_or_null(label)
		if node != null:
			node.free()
	for petal in doll.clothes_root.find_children("Petal*", "MeshInstance3D", false, false):
		petal.free()
	if doll.skirt_root != null:
		doll.skirt_root.free()
	doll._skirt = null
	doll.skirt_root = Node3D.new()
	doll.skirt_root.name = "SkirtAndTrims"
	doll.clothes_root.add_child(doll.skirt_root)
	for arm in doll.arms:
		var wrist = arm.get_node_or_null("WristDetails")
		if wrist == null:
			continue
		for cuff in ["CuffBinding", "CuffThickness", "SleeveLining"]:
			var piece = wrist.get_node_or_null(cuff)
			if piece != null:
				piece.free()
	for leg in doll.legs:
		var calf = leg.get_node_or_null("Calf")
		if calf != null:
			calf.set_meta("garment_slot", "")
		var shoe = leg.get_node_or_null("Shoe")
		if shoe != null:
			for piece in shoe.get_children():
				if piece.name == "WhiteSockInstep": continue
				var dark = str(piece.name) == "FlatSole"
				(piece as MeshInstance3D).material_override = doll._material(COLOR_SHOE.darkened(.18) if dark else COLOR_SHOE)


func _part(parent: Node3D, label: String, data: Dictionary, color: Color) -> MeshInstance3D:
	var part = doll._mesh(parent, label, data.vertices, data.normals, data.indices, color)
	if data.has("uv") or data.has("colors"):
		var arrays = part.mesh.surface_get_arrays(0)
		if data.has("uv"):
			arrays[Mesh.ARRAY_TEX_UV] = data.uv
		if data.has("colors"):
			arrays[Mesh.ARRAY_COLOR] = data.colors
		var mesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		part.mesh = mesh
		if data.has("uv"):
			part.set_meta("preserve_fabric_uv", true)
	part.set_meta("garment_slot", data.slot)
	part.set_meta("source_geometry", "Procedural / ukrainian_photo_001")
	part.set_meta("wiki_record_id", "WW-UKR-001")
	var arm_weights: PackedFloat32Array = data.arm_weights
	for value in arm_weights:
		if not is_zero_approx(value):
			part.set_meta("garment_arm_weights", arm_weights)
			break
	return part
