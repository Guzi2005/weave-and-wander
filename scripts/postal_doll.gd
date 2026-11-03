extends "res://scripts/volume_doll.gd"

var riding := false
var pedal_phase := 0.0
var mount_blend := -1.0
var _mount_from: Array[Transform3D] = []
var _mount_from_yaw := 0.0


func begin_mount(to_riding: bool) -> void:
	_mount_from.clear()
	for index in rig.skeleton.get_bone_count():
		_mount_from.append(rig.skeleton.get_bone_pose(index))
	_mount_from_yaw = body_rig.rotation.y
	mount_blend = 0.0
	riding = to_riding
	_moving = false
	_walk_blend = 0.0
	_travel_speed = 0.0
	resting_facing = PI*.5
	set_activity("idle")


func _blend_mount_pose() -> void:
	if mount_blend < 0:
		return
	var blend := smoothstep(0,1,mount_blend)
	for index in rig.skeleton.get_bone_count():
		var from := _mount_from[index]
		var to: Transform3D = rig.skeleton.get_bone_pose(index)
		rig.skeleton.set_bone_pose_position(index,from.origin.lerp(to.origin,blend))
		rig.skeleton.set_bone_pose_rotation(index,from.basis.get_rotation_quaternion().slerp(to.basis.get_rotation_quaternion(),blend))
	_facing = lerp_angle(_mount_from_yaw,PI*.5,blend)
	body_rig.rotation.y = _facing
	rig.skeleton.force_update_all_bone_transforms()
	# Keep the flat soles above the road as the hips lower off the saddle.
	for side in ["L","R"]:
		var index: int = rig.bones["Foot"+side]
		var foot: Transform3D = rig.skeleton.get_bone_global_pose(index)
		var lift := maxf(.15-position.y-foot.origin.y,0.0)
		var parent: Transform3D = rig.skeleton.get_bone_global_pose(rig.bones["Shin"+side])
		rig.skeleton.set_bone_pose_position(index,rig.skeleton.get_bone_pose_position(index)+parent.basis.inverse()*Vector3(0,lift,0))
	rig.skeleton.force_update_all_bone_transforms()
	if mount_blend >= 1:
		mount_blend = -1
		_mount_from.clear()


func _covers_legs() -> bool:
	return false


func _costume_palette() -> Array:
	return [Color("347b62"),Color("b8ad66"),Color("e4dfca")]


func _flower(_parent: Node3D, _center: Vector3, _petal: Color, _core: Color) -> void:
	pass


func _build_volume_body() -> void:
	super._build_volume_body()
	for leg in legs:
		# Upper thighs are under the coat; do not render an intersecting inner shell.
		leg.get_node("Trouser").free()
		_lathe(leg,"Trouser",[Vector3(-.93,.095,.11),Vector3(-.82,.11,.115),Vector3(-.42,.12,.13),Vector3(-.17,.14,.15)],Color("3a6453"),16)
		for shoe in leg.find_children("*","MeshInstance3D",true,false):
			if str(shoe.name) in ["FlatSole","ShoeUpper"]:
				shoe.material_override = _material(Color("435653"))
	for part in skirt_root.get_children():
		part.free()
	_build_coat_tails()
	clothes_root.get_node("WaistRibbon").free()
	_lathe(clothes_root,"WaistRibbon",[Vector3(1.26,.288,.212),Vector3(1.31,.287,.213)],Color("b8ad66"),32,0.0,false)
	for child in clothes_root.get_children():
		if str(child.name).begins_with("ButtonRow"):
			child.free()
	_buttons(Vector3(.075,1.76,0),5,.13,Vector3(.028,.034,.009),Color("cbb868"))
	var placket := _surface_panel(clothes_root,"CoatPlacket",[Vector3(1.15,.022,.22),Vector3(1.30,.022,.221),Vector3(1.55,.022,.20),Vector3(1.85,.022,.15)],Color("4b8b70"))
	placket.set_meta("skin_layer_sources", PackedStringArray([str(placket.get_path_to(_garment))]))
	placket.set_meta("skin_layer_clearance", .006)
	var strap := _tube(clothes_root,"MailbagStrap",PackedVector3Array([Vector3(.13,1.84,.17),Vector3(.07,1.7,.21),Vector3(-.1,1.50,.23),Vector3(-.23,1.31,.22)]),.026,Color("b09e67"))
	strap.set_meta("skin_layer_sources", PackedStringArray([str(strap.get_path_to(_garment))]))
	_tube(clothes_root,"MailbagShoulderStrap",PackedVector3Array([Vector3(-.23,1.31,.22),Vector3(-.41,1.22,.14),Vector3(-.41,1.15,-.16),Vector3(.10,1.72,-.23),Vector3(.15,1.90,-.14),Vector3(.16,1.96,.025),Vector3(.13,1.84,.17)]),.026,Color("b09e67"))
	var bag := PaperArt.box("PostalSatchel",Vector3(.34,.43,.25),Color("6c7d53"),Vector3(-.44,1.0,-.055))
	bag.material_override = _material(Color("6c7d53"))
	bag.set_meta("skin_anchor_local", Vector3.ZERO)
	clothes_root.add_child(bag)
	var flap := PaperArt.box("SatchelFlap",Vector3(.35,.18,.025),Color("aeb07a"),Vector3(-.44,1.15,.081))
	flap.material_override = _material(Color("aeb07a"))
	flap.set_meta("skin_anchor_local", Vector3.ZERO)
	clothes_root.add_child(flap)
	_ellipsoid(clothes_root,"BagClasp",Vector3(-.44,1.09,.096),Vector3(.025,.035,.01),Color("d8bc73"))


func _build_coat_tails() -> void:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for row in 13:
		var t := row / 12.0
		var y := lerpf(.54, 1.31, t)
		var rx := lerpf(.35, .28, t)
		var rz := lerpf(.28, .205, t)
		var gap := .24 * (1.0 - smoothstep(.92, 1.23, y))
		for column in 49:
			var angle := lerpf(gap, TAU-gap, column/48.0)
			vertices.append(Vector3(sin(angle)*rx, y, cos(angle)*rz))
			normals.append(Vector3(sin(angle)/rx, .13/rx, cos(angle)/rz).normalized())
	for row in 12:
		for column in 48:
			var a := row*49+column
			indices.append_array(PackedInt32Array([a,a+49,a+1,a+1,a+49,a+50]))
	_skirt = _mesh(skirt_root,"PostalCoatSkirt",vertices,normals,indices,Color("347b62"))
	_skirt.set_meta("skin_profile", "split_coat")


func _build_volume_head() -> void:
	super._build_volume_head()
	var hat := Node3D.new()
	hat.name = "HeadwearSlot"
	head_rig.add_child(hat)
	hat.rotation.z = .045
	var crown := _lathe(hat,"PeakedCapCrown",[Vector3(.405,.328,.354),Vector3(.49,.38,.37),Vector3(.57,.36,.335),Vector3(.66,.25,.23),Vector3(.685,.06,.06)],Color("347b62"),40)
	var band := _lathe(hat,"CapBand",[Vector3(.33,.315,.347),Vector3(.407,.33,.356)],Color("245e4e"),40,0.0,false)
	for part in [crown,band]:
		var arrays: Array = part.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for i in vertices.size():
			# The rear band reaches the occiput while the visor clears the eyes.
			vertices[i].y += .42*vertices[i].z
			vertices[i].z -= .012
			normals[i] = Vector3(normals[i].x,normals[i].y,normals[i].z-.42*normals[i].y).normalized()
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		part.mesh = mesh
	_ellipsoid(hat,"BroadVisor",Vector3(0,.48,.29),Vector3(.345,.025,.24),Color("245e4e"))
	var badge := _ellipsoid(hat,"CapBadge",Vector3(0,.629,.35),Vector3(.06,.045,.012),Color("d8bc73"))
	badge.rotation.x = -.30


func _update_puppet_motion(delta: float) -> void:
	if not riding:
		super._update_puppet_motion(delta)
		_blend_mount_pose()
		return
	body_rig.rotation.y = PI*.5
	_facing = PI*.5
	rig.skeleton.reset_bone_poses()
	rig._rotate("Spine",Vector3(-.12,0,0))
	for side in [-1,1]:
		var suffix := "L" if side < 0 else "R"
		# Two-link leg pose targets the actual pedal circle; shoes stay level.
		var target := Vector2(.51-side*.16*sin(pedal_phase),.16-side*.16*cos(pedal_phase))
		var down := 1.1-target.x
		var distance := Vector2(down,target.y).length()
		var shin_length := Vector2(.45,.095).length()
		var forward_angle := atan2(target.y,down)+acos(clampf((.25+distance*distance-shin_length*shin_length)/(distance),-1,1))
		var knee := Vector2(1.1-.5*cos(forward_angle),.5*sin(forward_angle))
		var lower_angle := atan2(target.y-knee.y,knee.x-target.x)
		var thigh := -forward_angle
		var shin := atan2(.095,.45)-lower_angle-thigh
		rig._rotate("Thigh"+suffix,Vector3(thigh,0,0))
		rig._rotate("Shin"+suffix,Vector3(shin,0,0))
		rig._rotate("Foot"+suffix,Vector3(-thigh-shin,0,0))
		rig._rotate("UpperArm"+suffix,Vector3(-.70,0,0))
		rig._rotate("Forearm"+suffix,Vector3(-.66,0,0))
	rig._offset("HemFront",Vector3(0,.12,.22))
	rig._offset("HemBack",Vector3(0,.07,-.12))
	rig.skeleton.force_update_all_bone_transforms()
	_blend_mount_pose()
