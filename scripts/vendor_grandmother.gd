extends "res://scripts/game_body_doll.gd"
## A local costume/proportion variant. Shared body, skeleton and garment sources stay untouched.

func _costume_palette() -> Array:
	return [Color("2c58cd"),Color("42c4d7"),Color("95bde7")]

func _build_volume_body() -> void:
	super()
	_garment.material_override = _material(Color("95bde7"))
	for child in clothes_root.get_children():
		if child.get_meta("material_role","") == "flower" or str(child.name).begins_with("Button"):
			child.free()
	# Derive the bib from the actual shirt surface so both layers share skinning.
	_fitted_panel("BlackShoulderWrap",[{"mesh":_garment}],FittedPanel.front_volumes([
		Vector3(1.40,.27,0),Vector3(1.49,.28,0),Vector3(1.72,.25,0),Vector3(1.88,.13,0)]),.016,Color("303034"))
	_fitted_panel("TurquoiseSash",[{"mesh":_garment},{"mesh":_skirt}],FittedPanel.front_volumes([
		Vector3(1.25,.31,0),Vector3(1.38,.31,0),Vector3(1.43,.27,0)]),.022,Color("42c4d7"))
	for label in ["HemRibbon","FineHemRibbon"]:
		var trim := skirt_root.get_node_or_null(label)
		if trim != null: trim.free()
	var collar := clothes_root.get_node_or_null("StandingCollar")
	if collar != null: collar.material_override = _material(Color("95bde7"))
	var tail := _surface_panel(clothes_root,"SashTail",[
		Vector3(1.43,.075,.235),Vector3(1.08,.065,.25),Vector3(.88,.08,.28)],Color("42c4d7"))
	tail.position.x = .24
	tail.set_meta("garment_slot","top")
	_ellipsoid(clothes_root,"SashKnot",Vector3(.24,1.40,.27),Vector3(.075,.065,.04),Color("42c4d7"))

func _build_shoe(parent: Node3D, _color: Color) -> void:
	super(parent,Color("ede9df"))

func _build_volume_head() -> void:
	super()
	var black := Color("262628")
	for child in hair_root.get_children(): child.free()
	# A higher hairline leaves both eyes and eyebrows visible below the kerchief.
	var previous_style := hair_style
	hair_style = 0
	_hair_cap(black)
	hair_style = previous_style
	# Folded kerchief crown: true capped, tapered prism with a paper-like crease.
	var points := PackedVector3Array([
		Vector3(-.35,.38,-.23),Vector3(.35,.38,-.23),Vector3(.35,.38,.21),Vector3(-.35,.38,.21),
		Vector3(-.38,.66,-.22),Vector3(.37,.62,-.22),Vector3(.37,.62,.20),Vector3(-.38,.66,.20)])
	var indices := PackedInt32Array([0,2,1,0,3,2,4,5,6,4,6,7,0,1,5,0,5,4,1,2,6,1,6,5,2,3,7,2,7,6,3,0,4,3,4,7])
	var normals := PackedVector3Array()
	for p in points: normals.append(p.normalized())
	_mesh(hair_root,"FoldedBlackKerchief",points,normals,indices,black)
	_tube(hair_root,"KerchiefFold",PackedVector3Array([Vector3(-.35,.43,.221),Vector3(-.07,.45,.23),Vector3(.34,.40,.221)]),.009,Color("3b3a3b"))
	for side in [-1.0,1.0]:
		_lathe(hair_root,"KerchiefSide",[Vector3(-.04,.075,.12),Vector3(.12,.09,.17),Vector3(.32,.08,.19),Vector3(.40,.06,.15)],black,16,0,true,[side*.28,side*.29,side*.29,side*.28],[-.10,-.09,-.08,-.06])
		for index in 2:
			_tube(head_rig,"SmileWrinkle",PackedVector3Array([
				_face_point(side*.17,.20-index*.025,.004),
				_face_point(side*.205,.19-index*.027,.004)]),.0035,Color("b47e70"))
		_tube(head_rig,"CheekCrease",PackedVector3Array([_face_point(side*.095,.135,.004),_face_point(side*.105,.10,.004)]),.003,Color("b47e70"))
