extends "res://scripts/game_body_doll.gd"

var catalog_style := 0
@export_range(.012,.12,.002) var headband_min_width := .025
@export_range(.025,.18,.002) var headband_max_width := .09
@export_range(.35, 1.05, .01) var catalog_skirt_length := .65
@export_range(.55, 1.05, .01) var catalog_garment_length := .80


func _build_volume_head() -> void:
	super()
	if catalog_style < 6:
		return
	var hat := Node3D.new()
	hat.name = "HeadwearSlot"
	head_rig.add_child(hat)
	var palette := _costume_palette()
	var color: Color = palette[0]
	var trim: Color = palette[1]
	var base := _hat_component(hat, "HatBase", "base")
	var ribbon := _hat_component(hat, "HatRibbon", "ribbon")
	var decor := _hat_component(hat, "HatDecorations", "decoration")
	hat.set_meta("diy_schema", "hat-kit-v1")
	hat.set_meta("diy_slots", PackedStringArray(["base", "ribbon", "decoration"]))
	match catalog_style:
		17:
			var data := preload("res://components/fabric_headband.gd").build(headband_min_width,headband_max_width)
			var band := _mesh(base,"FabricHeadband",data.vertices,data.normals,data.indices,color)
			band.set_meta("garment_slot","headwear")
			band.set_meta("head_contact",Vector3(0,2.61,0))
		6:
			hat.rotation.z = -.14
			_lathe(ribbon, "BeretBand", [Vector3(.44,.302,.32), Vector3(.49,.306,.325)], trim, 32)
			_lathe(base, "BeretCrown", [Vector3(.48,.307,.33), Vector3(.54,.36,.37), Vector3(.62,.33,.35), Vector3(.69,.18,.22), Vector3(.715,.012,.015)], color, 40)
			_ellipsoid(decor, "BeretStem", Vector3(0,.73,0), Vector3(.022,.035,.022), color)
		7:
			_lathe(base, "BucketBrim", [Vector3(.39,.42,.44), Vector3(.42,.41,.43), Vector3(.50,.32,.34)], color, 40)
			_lathe(base, "BucketCrown", [Vector3(.50,.32,.34), Vector3(.69,.275,.30), Vector3(.71,.25,.275), Vector3(.715,.01,.01)], color, 32)
			_lathe(ribbon, "BucketRibbon", [Vector3(.51,.322,.342), Vector3(.55,.315,.335)], trim, 40)
		8:
			_lathe(base, "SunBrim", [Vector3(.45,.56,.52), Vector3(.475,.56,.52), Vector3(.51,.32,.34)], color, 48)
			_lathe(base, "SunCrown", [Vector3(.50,.32,.34), Vector3(.64,.30,.32), Vector3(.73,.19,.22), Vector3(.75,.01,.01)], color, 40)
			_lathe(ribbon, "SunRibbon", [Vector3(.51,.324,.344), Vector3(.56,.318,.338)], trim, 40)
			_ellipsoid(decor, "RibbonKnot", Vector3(.307,.55,.12), Vector3(.035,.03,.028), trim)


func _build_connected_trousers(color: Color) -> void:
	# Replace the two plain tubes with a seat/waist/crotch shell the legs grow out of.
	# The seat binds to Hips through the existing "TrouserWaistband"/torso mechanism;
	# each tapered leg keeps the LegLeft/LegRight semantic so Thigh/Shin skinning,
	# the "Trouser" covered-leg removal and the "bottom" part slot all keep working.
	for leg in legs:
		var plain := leg.get_node_or_null("Trouser")
		if plain != null:
			plain.free()
		var tube := _lathe(leg, "Trouser", [Vector3(-.93,.092,.104),Vector3(-.90,.090,.102),
			Vector3(-.84,.090,.102),Vector3(-.72,.094,.106),Vector3(-.58,.099,.111),
			Vector3(-.42,.107,.119),Vector3(-.28,.118,.130),Vector3(-.15,.124,.138),
			Vector3(-.07,.120,.134),Vector3(-.012,.118,.132)], color, 32, 0.0, false)
		tube.material_override = (tube.material_override as ShaderMaterial).duplicate()
		tube.material_override.set_shader_parameter("backface_shade", .22)
	var rows := [
		[.865,.065,.040,false], [.900,.170,.098,false], [.960,.267,.140,false],
		[1.015,.276,.146,false], [1.08,.278,.149,false], [1.12,.274,.148,false],
		[1.15,.272,.152,false], [1.176,.264,.146,false],
		[1.166,.254,.141,true], [1.118,.258,.146,true]]
	var segments := 40
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	for row in rows:
		for column in segments + 1:
			var angle := TAU * column / segments
			vertices.append(Vector3(sin(angle) * row[1], row[0], cos(angle) * row[2]))
	for row in rows.size() - 1:
		var inner: bool = rows[row + 1][3]
		for column in segments:
			var a := row * (segments + 1) + column
			var b := a + segments + 1
			if inner:
				indices.append_array(PackedInt32Array([a, a + 1, b, a + 1, b + 1, b]))
			else:
				indices.append_array(PackedInt32Array([a, b, a + 1, a + 1, b, b + 1]))
	var center := vertices.size()
	vertices.append(Vector3(0, .860, 0))
	for column in segments:
		indices.append_array(PackedInt32Array([center, column, column + 1]))
	var seat := _mesh(clothes_root, "TrouserWaistband", vertices, _smooth_normals(vertices, indices, segments + 1), indices, color)
	seat.material_override = (seat.material_override as ShaderMaterial).duplicate()
	seat.material_override.set_shader_parameter("backface_shade", .28)


func _smooth_normals(vertices: PackedVector3Array, indices: PackedInt32Array, row_stride: int) -> PackedVector3Array:
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	for i in range(0, indices.size(), 3):
		var a := indices[i]
		var b := indices[i + 1]
		var c := indices[i + 2]
		var normal := (vertices[c] - vertices[a]).cross(vertices[b] - vertices[a])
		normals[a] += normal
		normals[b] += normal
		normals[c] += normal
	for i in normals.size():
		normals[i] = normals[i].normalized()
	for row in (vertices.size() - 1) / row_stride:
		var seam := row * row_stride
		var welded := (normals[seam] + normals[seam + row_stride - 1]).normalized()
		normals[seam] = welded
		normals[seam + row_stride - 1] = welded
	return normals


func _hat_component(parent: Node3D, label: String, slot: String) -> Node3D:
	var component := Node3D.new()
	component.name = label
	component.set_meta("diy_component", slot)
	component.set_meta("component_schema", "hat-component-v1")
	parent.add_child(component)
	return component


func set_hat_component_color(slot: String, color: Color) -> void:
	var component := head_rig.get_node_or_null("HeadwearSlot/Hat" + slot.capitalize())
	if component == null:
		return
	for part in component.find_children("*", "MeshInstance3D", true, false):
		var material := part.material_override as ShaderMaterial
		if material != null:
			material.set_shader_parameter("pigment", color)


func _build_volume_body() -> void:
	super()
	if catalog_style == 3:
		_lathe(clothes_root, "ShirtCollar", [Vector3(1.86,.15,.13), Vector3(1.94,.11,.10)], _costume_palette()[2], 32)
	elif catalog_style == 4:
		_build_connected_trousers(_costume_palette()[0].darkened(.12))
	elif catalog_style >= 10 and catalog_style <= 13:
		_build_modern_everyday(catalog_style)


# Styles 10-13 are neutral modern daily patterns built on the base outfit-2
# body. The tailored shell, waistcoat, buttons and trousers are stripped
# before the rig binds, then the replacement garment joins the same skin pass.
func _build_modern_everyday(style: int) -> void:
	var palette := _costume_palette()
	var cloth: Color = palette[0]
	var linen: Color = palette[2]
	var waistcoat := clothes_root.get_node_or_null("OpenWaistcoat")
	if waistcoat != null:
		waistcoat.free()
	var buttons := clothes_root.get_node_or_null("ButtonRow")
	if buttons != null:
		buttons.free()
	var data: Dictionary
	var label := ""
	var color := cloth
	var parent := clothes_root
	match style:
		10:
			data = BasicGarment.cuban_shirt(catalog_garment_length)
			label = "CubanShirt"
			color = linen
		11:
			data = BasicGarment.babydoll_blouse(catalog_garment_length)
			label = "BabydollBlouse"
		12:
			data = BasicGarment.simple_skirt(catalog_skirt_length)
			label = "ModernSkirt"
			color = cloth.darkened(.08)
		13:
			data = BasicGarment.sweater_vest(catalog_garment_length)
			label = "SweaterVest"
	if style == 12:
		for leg in legs:
			var trouser := leg.get_node_or_null("Trouser")
			if trouser != null:
				trouser.free()
			# Bare calves under the hem, like the long-dress outfits.
			var skin: Color = SKIN_TONES[skin_index]
			var calf := _lathe(leg, "Calf", [Vector3(-.95,.053,.060),Vector3(-.86,.057,.065),
				Vector3(-.65,.074,.081),Vector3(-.49,.081,.085),Vector3(-.40,.075,.079),
				Vector3(-.28,.088,.092),Vector3(-.12,.092,.098)], skin, 16)
			calf.position.z = .045
			calf.set_meta("garment_slot", "")
			calf.set_meta("everyday_skin", true)
		skirt_root = Node3D.new()
		skirt_root.name = "SkirtAndTrims"
		clothes_root.add_child(skirt_root)
		parent = skirt_root
	else:
		if style != 13:
			_garment.free()
			_garment = null
			_build_modern_arms()
			# Short garment lengths expose the midriff between the hem and the
			# trousers; the removed tailored shell used to cover it.
			var midriff := _lathe(clothes_root, "Midriff", [Vector3(1.12,.225,.128),
				Vector3(1.20,.222,.140), Vector3(1.35,.215,.142), Vector3(1.53,.210,.137)],
				SKIN_TONES[skin_index], 32, 0.0, false)
			midriff.set_meta("garment_slot", "")
			midriff.set_meta("everyday_skin", true)
		# Style 13 is an outer layer: the kept TailoredShell shirt underneath
		# covers the arms with its own long sleeves, so the vest needs no bare
		# arms and the shirt/cuffs survive intact.
	var part := _mesh(parent, label, data.vertices, data.normals, data.indices, color)
	part.set_meta("garment_slot", data.slot)
	if not (data.arm_weights as PackedFloat32Array).is_empty():
		part.set_meta("garment_arm_weights", data.arm_weights)
	if data.has("collar_trim"):
		var collar: Dictionary = data.collar_trim
		var leaf := _mesh(parent,"CubanCollarLeaves",collar.vertices,collar.normals,collar.indices,color.darkened(.09))
		leaf.position.z = .0007
		leaf.set_meta("garment_slot","top")
		leaf.set_meta("garment_arm_weights",collar.arm_weights)
	if data.has("trim"):
		var trim: Dictionary = data.trim
		var rib := _mesh(parent, label + "Rib", trim.vertices, trim.normals, trim.indices, color.darkened(.18))
		rib.set_meta("garment_slot", data.slot)
		if not (trim.arm_weights as PackedFloat32Array).is_empty():
			rib.set_meta("garment_arm_weights", trim.arm_weights)


# Short or absent sleeves need the bare arm down to the mitten; the cuff
# furniture belongs to the removed long sleeves.
func _build_modern_arms() -> void:
	var skin: Color = SKIN_TONES[skin_index]
	for index in arms.size():
		var arm := arms[index]
		var side := -1.0 if index == 0 else 1.0
		var wrist := arm.get_node_or_null("WristDetails")
		if wrist != null:
			for cuff in ["CuffBinding", "CuffThickness", "SleeveLining"]:
				var piece := wrist.get_node_or_null(cuff)
				if piece != null:
					piece.free()
		var data := BasicGarment.bare_arm(side)
		var arm_mesh := _mesh(arm, "ArmSkin", data.vertices, data.normals, data.indices, skin)
		arm_mesh.set_meta("garment_slot", "")
		arm_mesh.set_meta("everyday_skin", true)

