extends RefCounted

const LayerSkinBinding = preload("res://scripts/layer_skin_binding.gd")
const RestCloth = preload("res://scripts/rest_cloth.gd")

var skeleton: Skeleton3D
var bones: Dictionary = {}
var meshes: Array[MeshInstance3D] = []
var long_garment := true
var relaxed_arm_angles := Vector2.ZERO


func bind(model: Node3D, covered_legs: bool, keep_covered_legs := false) -> void:
	long_garment = covered_legs
	relaxed_arm_angles = model.get_meta("relaxed_arm_angles", Vector2.ZERO)
	skeleton = Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	model.add_child(skeleton)
	_bone("Root", "", Vector3.ZERO)
	_bone("Hips", "Root", Vector3(0, 1.14, 0))
	_bone("Spine", "Hips", Vector3(0, 0.40, 0))
	_bone("Head", "Spine", Vector3(0, 0.48, 0.035))
	for side in [-1.0,1.0]:
		_bone("EyeL" if side < 0 else "EyeR","Head",Vector3(side*.108,.292,.269))
	for side in [-1.0, 1.0]:
		var suffix := "L" if side < 0 else "R"
		_bone("UpperArm" + suffix, "Spine", Vector3(side * 0.155, 0.25, 0))
		var elbow := Vector3(side * 0.27, 1.48, 0)
		var wrist := Vector3(side * 0.30, 1.17, 0.025)
		_bone("Forearm" + suffix, "UpperArm" + suffix, elbow - Vector3(side * 0.155, 1.79, 0))
		_bone("Hand" + suffix, "Forearm" + suffix, wrist - elbow)
		_bone("Thigh" + suffix, "Hips", Vector3(side * 0.15, -0.04, 0))
		_bone("Shin" + suffix, "Thigh" + suffix, Vector3(0, -0.50, 0))
		_bone("Foot" + suffix, "Shin" + suffix, Vector3(0, -0.45, 0.095))
	_bone("HemFront", "Hips", Vector3(0, -0.9, 0.24))
	_bone("HemBack", "Hips", Vector3(0, -0.9, -0.24))
	_bone("HemL", "Hips", Vector3(-0.32, -0.9, 0))
	_bone("HemR", "Hips", Vector3(0.32, -0.9, 0))
	skeleton.reset_bone_poses()
	var skin := skeleton.create_skin_from_rest_transforms()
	var render_root := Node3D.new()
	render_root.name = "SkinnedMeshes"
	model.add_child(render_root)
	var groups: Dictionary = {}
	var layers: Dictionary = {}
	# Resolve source nodes before the baking pass changes their scene paths.
	for value in model.find_children("*", "MeshInstance3D", true, false):
		if not value.has_meta("skin_layer_sources"):
			continue
		var sources: Array = []
		for path in value.get_meta("skin_layer_sources"):
			var source := value.get_node_or_null(NodePath(path)) as MeshInstance3D
			assert(source != null, "Missing clothing skin source: " + str(path))
			sources.append(source)
		layers[value] = sources
	for value in model.find_children("*", "MeshInstance3D", true, false):
		var instance := value as MeshInstance3D
		var semantic := _semantic(instance)
		if covered_legs and str(instance.name).begins_with("Trouser"):
			if not keep_covered_legs:
				instance.free()
				continue
			instance.hide()
		var transform := instance.transform
		var ancestor := instance.get_parent() as Node3D
		while ancestor != model:
			transform = ancestor.transform * transform
			ancestor = ancestor.get_parent() as Node3D
		var arrays := instance.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var bone_indices := PackedInt32Array()
		var weights := PackedFloat32Array()
		var normal_matrix := transform.basis.inverse().transposed()
		var anchor: Vector3 = transform * instance.get_meta("skin_anchor_local", Vector3.ZERO)
		var arm_weights: PackedFloat32Array = instance.get_meta("garment_arm_weights", PackedFloat32Array())
		for index in vertices.size():
			vertices[index] = transform * vertices[index]
			normals[index] = (normal_matrix * normals[index]).normalized()
			var influences := _weights(semantic, str(instance.name), anchor if instance.has_meta("skin_anchor_local") else vertices[index],
				arm_weights[index] if not arm_weights.is_empty() else 0.0)
			if instance.has_meta("attachment_bone"):
				var attached_bone := str(instance.get_meta("attachment_bone"))
				assert(bones.has(attached_bone),"Unknown accessory attachment bone")
				influences = [[bones[attached_bone],0,0,0],[1.0,0.0,0.0,0.0]]
			if instance.get_meta("eye_state","") == "open":
				influences = [[bones["EyeL" if vertices[index].x < 0 else "EyeR"],0,0,0],[1.0,0.0,0.0,0.0]]
			if instance.get_meta("skin_profile", "") == "split_coat":
				influences = _split_coat_weights(vertices[index])
			for slot in 4:
				bone_indices.append(influences[0][slot])
				weights.append(influences[1][slot])
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TANGENT] = null
		arrays[Mesh.ARRAY_BONES] = bone_indices
		arrays[Mesh.ARRAY_WEIGHTS] = weights
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		if arrays[Mesh.ARRAY_TEX_UV] != null:
			var surface := SurfaceTool.new()
			surface.create_from(mesh,0)
			surface.generate_tangents()
			mesh = surface.commit()
		instance.mesh = mesh
		if not groups.has(semantic):
			var group := Node3D.new()
			group.name = semantic
			render_root.add_child(group)
			groups[semantic] = group
		instance.reparent(groups[semantic], false)
		instance.transform = Transform3D.IDENTITY
		instance.skin = skin
		instance.skeleton = instance.get_path_to(skeleton)
		instance.set_meta("semantic", semantic)
		instance.custom_aabb = AABB(Vector3(-1, -0.3, -0.9), Vector3(2, 3.3, 1.8))
		if instance.get_script() != null:
			instance.set_meta("procedural_source", instance.get_script().resource_path)
			instance.set_script(null)
		meshes.append(instance)
	var bound_layers: Dictionary = {}
	for layer in layers:
		_bind_layer(layer, layers, bound_layers, {})
	for part in meshes:
		if part.get_meta("semantic","") in ["skirt","apron"] or part.has_meta("skin_layer_sources"):
			RestCloth.install(part)
	# Pose-space correctives keep overlays outside the same animated source triangles.
	for mode in RestCloth.SHAPES.size():
		animate(0,0,"idle",0)
		var pose_weights := Vector4.ZERO
		pose_weights[maxi(0,mode-1)] = 1.0
		pose_rest("sit" if mode == 0 else "nap",1.0,0.0,pose_weights)
		for layer in bound_layers:
			RestCloth.fit_layer(self,layer,mode)
	animate(0,0,"idle",0)
	for node in model.find_children("ButtonRow", "", true, false):
		node.set_script(null)
	skeleton.force_update_all_bone_transforms()


func _bind_layer(layer: MeshInstance3D, layers: Dictionary, bound: Dictionary, visiting: Dictionary) -> void:
	if bound.has(layer):
		return
	assert(not visiting.has(layer), "Cyclic clothing layer dependency.")
	visiting[layer] = true
	for source in layers[layer]:
		if layers.has(source):
			_bind_layer(source, layers, bound, visiting)
	LayerSkinBinding.bind_layer(layer, layers[layer])
	bound[layer] = true
	visiting.erase(layer)


func _bone(label: String, parent: String, offset: Vector3, tilt: float = 0.0) -> void:
	var index := skeleton.add_bone(label)
	bones[label] = index
	if not parent.is_empty():
		skeleton.set_bone_parent(index, bones[parent])
	skeleton.set_bone_rest(index, Transform3D(Basis(Vector3.FORWARD, tilt), offset))


func _semantic(mesh: Node) -> String:
	if mesh.has_meta("garment_arm_weights"):
		return "garment"
	var parent := mesh.get_parent()
	var shoe := str(mesh.name) in ["FlatSole", "ShoeUpper", "InstepStrap", "WhiteSockInstep"]
	while parent != null:
		match str(parent.name):
			"HairSlot": return "hair"
			"HeadwearSlot": return "headwear"
			"HeadRig": return "head"
			"ArmLeft": return "armL"
			"ArmRight": return "armR"
			"LegLeft": return "shoeL" if shoe else "legL"
			"LegRight": return "shoeR" if shoe else "legR"
			"SkirtAndTrims": return "skirt"
		parent = parent.get_parent()
	return "apron" if str(mesh.name) in ["Apron", "Pocket"] else "torso"


func _weights(semantic: String, label: String, point: Vector3, arm_weight: float = 0.0) -> Array:
	var ids := [bones["Spine"], 0, 0, 0]
	var values := [1.0, 0.0, 0.0, 0.0]
	if label == "HosieryWaist":
		var waist_blend := smoothstep(1.14, 1.40, point.y)
		return [[bones.Hips, bones.Spine, 0, 0], [1.0-waist_blend, waist_blend, 0.0, 0.0]]
	if label.begins_with("MosuoBeadStrands"):
		# The nape follows the head, shoulder/chest follow the torso; lower strands
		# rest against the front skirt rather than orbiting with the head bone.
		var head_weight := smoothstep(1.86,2.27,point.y)
		var skirt_weight := 1.0-smoothstep(1.14,1.38,point.y)
		var hem := clampf((1.30-point.y)/1.08,0.0,1.0)
		ids = [bones.Head,bones.Spine,bones.Hips,bones.HemFront]
		values = [head_weight,(1.0-head_weight)*(1.0-skirt_weight),(1.0-head_weight)*skirt_weight*(1.0-hem),(1.0-head_weight)*skirt_weight*hem]
	elif semantic in ["head", "hair", "headwear"]:
		ids[0] = bones["Head"]
	elif semantic.begins_with("shoe"):
		ids[0] = bones["Foot" + semantic.right(1)]
	elif semantic == "garment":
		var side := "L" if (arm_weight < -0.001 or (absf(arm_weight) <= 0.001 and point.x < 0)) else "R"
		var sleeve := absf(arm_weight)
		sleeve = clampf(sleeve, 0.0, 1.0)
		var upper := smoothstep(1.32, 1.64, point.y)
		var spine := smoothstep(1.23, 1.68, point.y)
		ids = [bones["Spine"], bones["Hips"], bones["UpperArm" + side], bones["Forearm" + side]]
		values = [(1.0 - sleeve) * spine, (1.0 - sleeve) * (1.0 - spine), sleeve * upper, sleeve * (1.0 - upper)]
	elif semantic.begins_with("arm"):
		var side := semantic.right(1)
		if label == "InternalShoulder":
			ids[0] = bones["Spine"]
		elif label in ["Mitten", "Thumb", "HandMannequin", "ArmMannequinThumb"]:
			ids[0] = bones["Hand" + side]
		else:
			var upper := smoothstep(1.32, 1.64, point.y)
			var medial := clampf((0.145 - absf(point.x)) / 0.035, 0.0, 1.0)
			var anchor := medial * smoothstep(1.76, 1.86, point.y) * 0.40
			ids = [bones["UpperArm" + side], bones["Forearm" + side], bones["Spine"], 0]
			values = [upper * (1.0 - anchor), (1.0 - upper) * (1.0 - anchor), anchor, 0.0]
	elif semantic.begins_with("leg"):
		var side := semantic.right(1)
		var upper := smoothstep(0.47, 0.79, point.y)
		ids = [bones["Thigh" + side], bones["Shin" + side], 0, 0]
		values = [upper, 1.0 - upper, 0.0, 0.0]
	elif semantic in ["skirt", "apron"] and point.y < 1.30:
		var hem := smoothstep(0.0, 1.0, (1.30 - point.y) / 1.08)
		var across := absf(point.x) / maxf(absf(point.x) + absf(point.z), 0.01)
		ids = [bones["Hips"], bones["HemL" if point.x < 0 else "HemR"], bones["HemBack" if point.z < 0 else "HemFront"], 0]
		values = [1.0 - hem, hem * across, hem * (1.0 - across), 0.0]
	else:
		var upper := smoothstep(1.23, 1.68, point.y)
		ids = [bones["Hips"], bones["Spine"], 0, 0]
		values = [1.0 - upper, upper, 0.0, 0.0]
	return [ids, values]


func _split_coat_weights(point: Vector3) -> Array:
	# The outer/front tails ride on each thigh; the rear stays with the seat.
	if point.y >= 1.30:
		return _weights("torso", "", point)
	var lower := 1.0 - smoothstep(1.05, 1.30, point.y)
	var follows_leg := smoothstep(-0.22, -0.025, point.z)
	var upper := smoothstep(0.47, 0.79, point.y)
	var side := "L" if point.x < 0 else "R"
	if point.y > 1.13:
		var spine := smoothstep(1.23,1.68,point.y)
		return [[bones["Spine"],bones["Hips"],bones["Thigh"+side],bones["HemBack"]],
			[(1.0-lower)*spine,(1.0-lower)*(1.0-spine),lower*follows_leg,lower*(1.0-follows_leg)]]
	return [[bones["Hips"], bones["Thigh"+side], bones["Shin"+side], bones["HemBack"]],
		[1.0-lower, lower*follows_leg*upper, lower*follows_leg*(1.0-upper), lower*(1.0-follows_leg)]]


func animate(wave: float, movement: float, activity: String, work_phase: float) -> void:
	skeleton.reset_bone_poses()
	for part in meshes:
		if part.get_meta("rest_cloth",false):
			for shape in part.mesh.get_blend_shape_count():
				part.set_blend_shape_value(shape,0.0)
	# A four-second breathing cycle affects the torso, not the planted feet.
	var breath := sin(work_phase * TAU / 4.0) * (1.0 - movement)
	# Two gentle rises per stride, lowest at alternating foot contacts.
	# Move hips and all descendants; the foot correction below keeps soles grounded.
	_offset("Hips", Vector3(0, .018 * (1.0 + cos(wave * 2.0)) * movement, 0))
	_rotate("Spine", Vector3(0.045 * movement + breath * .009, 0, cos(wave) * 0.012 * movement))
	_offset("Spine", Vector3(0, breath * .003, 0))
	_rotate("Head", Vector3(-breath * .004, 0, 0))
	for side in [-1.0, 1.0]:
		var suffix := "L" if side < 0 else "R"
		var stride: float = sin(wave) * side * movement
		var thigh := stride * (0.235 if long_garment else 0.34)
		var knee := maxf(-stride, 0) * 0.18
		_rotate("Thigh" + suffix, Vector3(thigh, 0, 0))
		_rotate("Shin" + suffix, Vector3(knee, 0, 0))
		_rotate("Foot" + suffix, Vector3(-thigh - knee, 0, 0))
		var swing := -stride * 0.29 + relaxed_arm_angles.x
		var spread: float = side * relaxed_arm_angles.y
		var elbow := -0.06 * movement
		if activity in ["sewing", "stocking", "checkout", "browsing"]:
			swing = lerpf(-0.48 + sin(work_phase * 3 + side) * 0.08, swing, movement)
			elbow = lerpf(-0.36, elbow, movement)
			spread *= movement
		_rotate("UpperArm" + suffix, Vector3(swing, 0, spread))
		_rotate("Forearm" + suffix, Vector3(elbow, 0, 0))
		# Compensate the planted foot so its flat sole does not sink or roll.
		skeleton.force_update_all_bone_transforms()
		var foot := global_pose(bones["Foot" + suffix])
		var lift := maxf(-stride, 0.0) * 0.055
		var desired_y := 0.15 + lift
		var shin := global_pose(bones["Shin" + suffix])
		var correction := shin.basis.inverse() * Vector3(0, desired_y - foot.origin.y, 0)
		_offset("Foot" + suffix, correction)
	var opening := absf(sin(wave)) * 0.24 * movement
	_offset("HemFront", Vector3(0, 0.0, opening))
	_offset("HemBack", Vector3(0, 0.0, -opening))
	_offset("HemL", Vector3(-0.012 * movement, 0, sin(wave) * 0.028 * movement))
	_offset("HemR", Vector3(0.012 * movement, 0, -sin(wave) * 0.028 * movement))
	skeleton.force_update_all_bone_transforms()


func _rotate(label: String, angles: Vector3) -> void:
	var index: int = bones[label]
	var rest := skeleton.get_bone_rest(index).basis.get_rotation_quaternion()
	skeleton.set_bone_pose_rotation(index, rest * Quaternion.from_euler(angles))


func pose_rest(mode: String, amount: float, phase := 0.0, pose_weights := Vector4(1,0,0,0)) -> void:
	var nap := mode == "nap"
	var breath := sin(phase*1.25)
	var shift := sin(phase*.35)
	var curl: float = pose_weights.y if nap else 0.0
	var loose: float = pose_weights.z if nap else 0.0
	var relaxed_arm: float = pose_weights.w if nap else 0.0
	var targets := {"Root":Vector3(0,0,PI*.5 if nap else 0.0),"Spine":Vector3(.12+curl*.035 if nap else -.035+breath*.009,0,-.22 if nap else shift*.012),
		"Head":Vector3(.08+breath*.008 if nap else .035+sin(phase*.51)*.012,0,-.12 if nap else shift*.025)}
	for suffix in ["L","R"]:
		var side := -1.0 if suffix == "L" else 1.0
		var thigh := (-1.48-curl*.30+loose*.23 if nap else -1.50)+side*(.10 if nap else .025)
		var shin := 2.10+curl*.32-loose*.28-side*.07 if nap else 1.50+sin(phase*.65+side)*.035
		targets["Thigh"+suffix] = Vector3(thigh,0,side*.035 if not nap else (-.18 if side > 0 else 0.0))
		targets["Shin"+suffix] = Vector3(shin,0,0)
		# Relax the ankle relative to the bent leg instead of presenting both soles.
		targets["Foot"+suffix] = Vector3(-thigh-shin-.12+side*.06 if nap else 0.0,side*.08 if nap else 0.0,-.40+side*.06 if nap else 0.0)
		targets["UpperArm"+suffix] = Vector3(-.82 if nap else -.72,side*.15,-side*.10)
		targets["Forearm"+suffix] = Vector3(-1.42 if nap else -.32,0,side*.09)
	for label in targets:
		var index: int = bones[label]
		var rest := skeleton.get_bone_rest(index).basis.get_rotation_quaternion()
		var target := rest*Quaternion.from_euler(targets[label])
		skeleton.set_bone_pose_rotation(index,skeleton.get_bone_pose_rotation(index).slerp(target,amount))
	for label in ["HemFront","HemBack","HemL","HemR"]:
		var index: int = bones[label]
		var target := skeleton.get_bone_rest(index).origin
		skeleton.set_bone_pose_position(index,skeleton.get_bone_pose_position(index).lerp(target,amount))
	# Protract the shoulder girdle with the original sleeve skin, not exposed joints.
	for suffix in ["L","R"]:
		var side := -1.0 if suffix == "L" else 1.0
		_offset("UpperArm"+suffix,Vector3(-side*.025,-.018,.055)*amount if nap else Vector3.ZERO)
	for part in meshes:
		if part.get_meta("rest_cloth",false):
			part.set_blend_shape_value(0,0.0 if nap else amount)
			for variant in 4:
				part.set_blend_shape_value(variant+1,pose_weights[variant]*amount if nap else 0.0)
	skeleton.force_update_all_bone_transforms()
	for suffix in ["L","R"]:
		var side := -1.0 if suffix == "L" else 1.0
		var hand_target := Vector3(-.09+side*.022,2.23,.27) if nap else Vector3(side*.24,1.30+sin(phase*.65+side)*.008,.36)
		var elbow_pole := Vector3(-.04+side*.10,1.78,.46) if nap else Vector3(side*.49,1.37,.12)
		if nap and suffix == "L":
			hand_target = hand_target.lerp(Vector3(-.52,1.54,.78),relaxed_arm)
			elbow_pole = elbow_pole.lerp(Vector3(-.40,1.85,.75),relaxed_arm)
			# Clear the cushion edge before lowering the hand into the draped pose.
			var clearance := 4.0*relaxed_arm*(1.0-relaxed_arm)
			hand_target.x += .09*clearance
			elbow_pole.x += .05*clearance
		_rest_arm(suffix,hand_target,elbow_pole,amount)
		if nap:
			var parent := global_pose(bones["Forearm"+suffix]).basis.get_rotation_quaternion()
			var root_rotation := global_pose(bones.Root).basis.get_rotation_quaternion()
			var hand := bones["Hand"+suffix] as int
			skeleton.set_bone_pose_rotation(hand,skeleton.get_bone_pose_rotation(hand).slerp(parent.inverse()*root_rotation*Quaternion(Vector3.FORWARD,PI),amount))
	skeleton.force_update_all_bone_transforms()


func look_toward(yaw: float, pitch: float, eye: Vector2, blink: float, left_layout := Vector3.ZERO, right_layout := Vector3.ZERO) -> void:
	var head: int = bones.Head
	var current := skeleton.get_bone_pose_rotation(head)
	skeleton.set_bone_pose_rotation(head,current*Quaternion.from_euler(Vector3(pitch,yaw,0)))
	for suffix in ["L","R"]:
		var index: int = bones["Eye"+suffix]
		var offset := Vector3(eye.x*.014,eye.y*.009,-absf(eye.x)*.003)
		offset += left_layout if suffix == "L" else right_layout
		# Sink the last sliver of the open pupil as the closed lid takes over.
		offset.z -= .018*smoothstep(.72,1.0,blink)
		_offset("Eye"+suffix,offset)
		skeleton.set_bone_pose_scale(index,Vector3(1,maxf(.08,1.0-blink),1))
	skeleton.force_update_all_bone_transforms()


func _rest_arm(suffix: String, target: Vector3, pole: Vector3, amount: float) -> void:
	# Keep the original sleeve skin; solve the two bones to a resting hand contact.
	var root_pose := global_pose(bones.Root)
	target = root_pose*target
	pole = root_pose*pole
	var shoulder := global_pose(bones["UpperArm"+suffix]).origin
	var upper_length := skeleton.get_bone_rest(bones["Forearm"+suffix]).origin.length()
	var lower_length := skeleton.get_bone_rest(bones["Hand"+suffix]).origin.length()
	var direction := (target-shoulder).normalized()
	var distance := clampf(shoulder.distance_to(target),.02,upper_length+lower_length-.001)
	var along := (upper_length*upper_length-lower_length*lower_length+distance*distance)/(2.0*distance)
	var perpendicular := (pole-shoulder)-direction*(pole-shoulder).dot(direction)
	var elbow := shoulder+direction*along+perpendicular.normalized()*sqrt(maxf(0.0,upper_length*upper_length-along*along))
	_aim_bone("UpperArm"+suffix,"Forearm"+suffix,elbow,amount)
	_aim_bone("Forearm"+suffix,"Hand"+suffix,shoulder+direction*distance,amount)


func _aim_bone(label: String, child: String, destination: Vector3, amount: float) -> void:
	var index: int = bones[label]
	var current := global_pose(index)
	var child_origin := global_pose(bones[child]).origin
	var correction := Quaternion((child_origin-current.origin).normalized(),(destination-current.origin).normalized())
	var parent := global_pose(skeleton.get_bone_parent(index)).basis.get_rotation_quaternion()
	var target := parent.inverse()*correction*current.basis.get_rotation_quaternion()
	skeleton.set_bone_pose_rotation(index,skeleton.get_bone_pose_rotation(index).slerp(target,amount))
	skeleton.force_update_all_bone_transforms()


func place_foot(suffix: String, target: Vector3) -> void:
	var hip := global_pose(bones["Thigh"+suffix]).origin
	var a := skeleton.get_bone_rest(bones["Shin"+suffix]).origin.length()
	var b := skeleton.get_bone_pose(bones["Foot"+suffix]).origin.length()
	var direction := (target-hip).normalized()
	var distance := clampf(hip.distance_to(target),.05,a+b-.001)
	var along := (a*a-b*b+distance*distance)/(2*distance)
	var forward := (Vector3.FORWARD*-1.0-direction*direction.dot(Vector3.BACK)).normalized()
	var knee := hip+direction*along+forward*sqrt(maxf(0,a*a-along*along))
	# A pedal reach must carry the skirt forward with the bent knee.
	var seated_cloth := false
	for part in meshes:
		if part.get_meta("rest_cloth",false) and part.get_blend_shape_value(0)>.5:
			seated_cloth = true
			break
	if long_garment and not seated_cloth:
		var front := skeleton.get_bone_rest(bones.HemFront).origin.z
		var required := maxf(0,knee.z+.14-front)
		var current := skeleton.get_bone_pose_position(bones.HemFront)-skeleton.get_bone_rest(bones.HemFront).origin
		_offset("HemFront",Vector3(current.x,current.y,maxf(current.z,required)))
	_aim_bone("Thigh"+suffix,"Shin"+suffix,knee,1)
	_aim_bone("Shin"+suffix,"Foot"+suffix,hip+direction*distance,1)
	var parent := global_pose(bones["Shin"+suffix]).basis.get_rotation_quaternion()
	skeleton.set_bone_pose_rotation(bones["Foot"+suffix],parent.inverse())
	skeleton.force_update_all_bone_transforms()


func _offset(label: String, offset: Vector3) -> void:
	var index: int = bones[label]
	skeleton.set_bone_pose_position(index, skeleton.get_bone_rest(index).origin + offset)


func global_pose(index: int) -> Transform3D:
	# Skeleton3D's cached global poses are not evaluated before entering the tree.
	var pose := skeleton.get_bone_pose(index)
	var parent := skeleton.get_bone_parent(index)
	while parent >= 0:
		pose = skeleton.get_bone_pose(parent)*pose
		parent = skeleton.get_bone_parent(parent)
	return pose


func deformed_vertices(instance: MeshInstance3D) -> PackedVector3Array:
	var arrays := instance.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if instance.mesh is ArrayMesh:
		for blend_index in instance.mesh.get_blend_shape_count():
			var amount := instance.get_blend_shape_value(blend_index)
			if is_zero_approx(amount): continue
			var target: PackedVector3Array = instance.mesh.surface_get_blend_shape_arrays(0)[blend_index][Mesh.ARRAY_VERTEX]
			for index in vertices.size():
				vertices[index] += (target[index]-arrays[Mesh.ARRAY_VERTEX][index])*amount
	var ids: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var transforms: Array[Transform3D] = []
	for index in skeleton.get_bone_count():
		transforms.append(global_pose(index) * skeleton.get_bone_global_rest(index).affine_inverse())
	var result := PackedVector3Array()
	for index in vertices.size():
		var point := Vector3.ZERO
		for slot in 4:
			point += (transforms[ids[index * 4 + slot]] * vertices[index]) * weights[index * 4 + slot]
		result.append(point)
	return result


func add_animation_player(model: Node3D) -> void:
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	player.root_node = NodePath("..")
	model.add_child(player)
	var library := AnimationLibrary.new()
	for clip in ["idle", "walk", "sewing"]:
		var animation := Animation.new()
		animation.length = 4.0 if clip == "idle" else 1.0
		animation.loop_mode = Animation.LOOP_LINEAR
		for index in skeleton.get_bone_count():
			var path := NodePath("Skeleton3D:" + skeleton.get_bone_name(index))
			var rotation_track := animation.add_track(Animation.TYPE_ROTATION_3D)
			animation.track_set_path(rotation_track, path)
			var position_track := animation.add_track(Animation.TYPE_POSITION_3D)
			animation.track_set_path(position_track, path)
		for frame in 25:
			var cycle := frame / 24.0
			var time := cycle * animation.length
			animate(TAU * cycle, 1.0 if clip == "walk" else 0.0, clip, time if clip == "idle" else cycle * TAU / 3.0)
			for index in skeleton.get_bone_count():
				animation.rotation_track_insert_key(index * 2, time, skeleton.get_bone_pose_rotation(index))
				animation.position_track_insert_key(index * 2 + 1, time, skeleton.get_bone_pose_position(index))
		library.add_animation(clip, animation)
	player.add_animation_library("", library)
	animate(0, 0, "idle", 0)
