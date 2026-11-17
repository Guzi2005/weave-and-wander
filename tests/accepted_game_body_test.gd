extends SceneTree

const Accepted = preload("res://scripts/shorter_arm_body.gd")
const GameBody = preload("res://scripts/game_body_doll.gd")
const Customer = preload("res://scripts/customer_doll.gd")
const Garment = preload("res://scripts/garment_item.gd")
const Definition = preload("res://scripts/garment_definition.gd")
const BODY_COUNTS := {"MannequinTorso": 1, "ArmMannequin": 2,
	"ArmMannequinThumb": 2, "LegMannequin": 2}
const LEGACY_BODY := ["Neck", "Calf", "Mitten", "Thumb"]
const BODY_GROUPS := ["head", "hair", "shoeL", "shoeR"]
const BONE_NAMES := ["Root", "Hips", "Spine", "Head", "EyeL", "EyeR",
	"UpperArmL", "ForearmL", "HandL", "ThighL", "ShinL", "FootL",
	"UpperArmR", "ForearmR", "HandR", "ThighR", "ShinR", "FootR",
	"HemFront", "HemBack", "HemL", "HemR"]
# ArrayMesh quantizes each of the four skin weights to 16 bits.
const WEIGHT_EPSILON := 4.0 / 65535.0
var failures: Array[String] = []
var checks := 0
var checked_vertices := 0
var checked_poses := 0
var wardrobe_cycles := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok and not failures.has(message):
		failures.append(message)
		push_error(message)


func _configure(doll: Node3D, outfit: int) -> bool:
	doll.configure({"outfit": outfit, "hair": 1, "palette": 0})
	doll.set_process(false)
	var ready: bool = doll.rig != null and is_instance_valid(doll.rig.skeleton) and not doll.rig.meshes.is_empty()
	_check(ready, "%s outfit %d: configure did not bind a nonempty rig" % [doll.get_script().resource_path, outfit])
	return ready


func _is_body(part: MeshInstance3D) -> bool:
	return str(part.name) in BODY_COUNTS or part.get_meta("is_underbody", false) \
		or str(part.get_meta("semantic", "")) in BODY_GROUPS


func _parts(doll: Node3D, body_only := false) -> Dictionary:
	var result := {}
	var occurrences := {}
	for part: MeshInstance3D in doll.rig.meshes:
		if body_only and not _is_body(part):
			continue
		# Godot renames repeated ears/eyes with process-global instance IDs.
		var label := str(part.name)
		if label.begins_with("@"):
			label = "@generated"
		var key := "%s/%s" % [part.get_meta("semantic", ""), label]
		var ordinal: int = occurrences.get(key, 0)
		occurrences[key] = ordinal + 1
		result["%s#%d" % [key, ordinal]] = part
	return result


func _body_snapshot(doll: Node3D) -> Dictionary:
	var result := {}
	var parts := _parts(doll, true)
	for key in parts:
		var part: MeshInstance3D = parts[key]
		var surfaces: Array = []
		_check(part.mesh != null and part.mesh.get_surface_count() > 0, "accepted reference has an empty body mesh: " + key)
		if part.mesh == null:
			continue
		for surface in part.mesh.get_surface_count():
			var channels: Array = []
			for channel in part.mesh.surface_get_arrays(surface):
				channels.append(var_to_bytes(channel))
			surfaces.append(channels)
		result[key] = {"surfaces": surfaces, "transform": var_to_bytes(part.transform),
			"visible": part.is_visible_in_tree()}
	return result


func _check_body(doll: Node3D, expected: Dictionary, context: String) -> void:
	var parts := _parts(doll, true)
	_check(parts.size() == expected.size(), context + ": body mesh count changed")
	var counts := {}
	for part: MeshInstance3D in doll.rig.meshes:
		var label := str(part.name)
		if label in BODY_COUNTS:
			counts[label] = counts.get(label, 0) + 1
			_check(part.get_meta("is_underbody", false), context + ": missing is_underbody on " + label)
			_check(part.visible and part.is_visible_in_tree(), context + ": body hidden: " + str(doll.body_rig.get_path_to(part)))
		if label in LEGACY_BODY or part.has_meta("everyday_skin"):
			_check(not part.is_visible_in_tree(), context + ": duplicate legacy body visible: " + label)
	for label in BODY_COUNTS:
		_check(counts.get(label, 0) == BODY_COUNTS[label], context + ": wrong count for " + label)
	for key in expected:
		_check(parts.has(key), context + ": missing accepted body mesh " + key)
		if not parts.has(key):
			continue
		var part: MeshInstance3D = parts[key]
		var saved: Dictionary = expected[key]
		_check(part.mesh != null, context + ": missing mesh resource: " + key)
		if part.mesh == null:
			continue
		_check(var_to_bytes(part.transform) == saved.transform, context + ": body transform changed: " + key)
		_check(part.is_visible_in_tree() == saved.visible, context + ": body visibility changed: " + key)
		_check(part.mesh.get_surface_count() == saved.surfaces.size(), context + ": body surface count changed: " + key)
		for surface in mini(part.mesh.get_surface_count(), saved.surfaces.size()):
			var arrays := part.mesh.surface_get_arrays(surface)
			for channel in arrays.size():
				var channel_name: String = {Mesh.ARRAY_VERTEX: "vertices", Mesh.ARRAY_NORMAL: "normals",
					Mesh.ARRAY_INDEX: "indices", Mesh.ARRAY_BONES: "bones", Mesh.ARRAY_WEIGHTS: "weights"}.get(channel, str(channel))
				_check(var_to_bytes(arrays[channel]) == saved.surfaces[surface][channel],
					"%s: body %s differ bit-for-bit: %s surface %d" % [context, channel_name, key, surface])


func _check_rest(doll: Node3D, accepted: Node3D, context: String) -> void:
	var skeleton: Skeleton3D = doll.rig.skeleton
	var reference: Skeleton3D = accepted.rig.skeleton
	_check(skeleton.get_bone_count() == 22, context + ": expected 22 bones")
	_check(reference.get_bone_count() == 22, context + ": accepted reference must have 22 bones")
	_check(doll.get("arm_shortening") == 0.045, context + ": arm_shortening must be 0.045")
	for index in mini(22, mini(skeleton.get_bone_count(), reference.get_bone_count())):
		var label: String = BONE_NAMES[index]
		_check(skeleton.get_bone_name(index) == label and reference.get_bone_name(index) == label,
			context + ": bone name/order changed: " + label)
		_check(skeleton.get_bone_parent(index) == reference.get_bone_parent(index), context + ": bone parent changed: " + label)
		_check(var_to_bytes(skeleton.get_bone_rest(index)) == var_to_bytes(reference.get_bone_rest(index)),
			context + ": local rest differs from accepted shorter arm: " + label)
		_check(var_to_bytes(skeleton.get_bone_global_rest(index)) == var_to_bytes(reference.get_bone_global_rest(index)),
			context + ": global rest differs from accepted shorter arm: " + label)


func _visibility(doll: Node3D) -> Dictionary:
	var result := {}
	var parts := _parts(doll)
	for key in parts:
		result[key] = [parts[key].visible, parts[key].is_visible_in_tree()]
	return result


func _check_toggles(doll: Node3D, expected: Dictionary, context: String) -> void:
	var dressed := _visibility(doll)
	var underbody := {}
	for cycle in 2:
		doll.set_underbody_mode(true)
		_check(doll.is_underbody_mode, context + ": underbody flag not set")
		_check_body(doll, expected, context + " underbody")
		for part: MeshInstance3D in doll.rig.meshes:
			if not _is_body(part):
				_check(not part.is_visible_in_tree(), context + ": non-body mesh visible in underbody mode: " + str(part.name))
		if cycle == 0:
			underbody = _visibility(doll)
		else:
			_check(_visibility(doll) == underbody, context + ": repeated underbody toggle changed visibility")
		doll.set_underbody_mode(false)
		_check(not doll.is_underbody_mode, context + ": clothed flag not restored")
		_check(_visibility(doll) == dressed, context + ": clothed toggle did not restore visibility")
		_check_body(doll, expected, context + " restored")


func _check_weights(doll: Node3D, context: String) -> Array[MeshInstance3D]:
	var valid: Array[MeshInstance3D] = []
	_check(not doll.rig.meshes.is_empty(), context + ": no skinned meshes to validate")
	for part: MeshInstance3D in doll.rig.meshes:
		var has_surface := part.mesh != null and part.mesh.get_surface_count() > 0
		_check(has_surface, context + ": empty skinned mesh: " + str(part.name))
		if not has_surface:
			continue
		var safe := true
		for surface in part.mesh.get_surface_count():
			var arrays := part.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var ids: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var context_part := "%s: %s surface %d" % [context, doll.body_rig.get_path_to(part), surface]
			var valid_sizes := not vertices.is_empty() and ids.size() == vertices.size() * 4 and weights.size() == ids.size()
			_check(valid_sizes, context_part + ": expected four skin weights per vertex")
			if not valid_sizes:
				safe = false
				continue
			for vertex in vertices.size():
				var total := 0.0
				for slot in 4:
					var index := vertex * 4 + slot
					var valid_id: bool = ids[index] >= 0 and ids[index] < doll.rig.skeleton.get_bone_count()
					_check(valid_id, context_part + ": invalid bone index")
					safe = safe and valid_id
					_check(is_finite(weights[index]) and weights[index] >= 0.0, context_part + ": invalid skin weight")
					total += weights[index]
				_check(is_finite(total) and absf(total - 1.0) <= WEIGHT_EPSILON, context_part + ": weights not normalized")
				_check(vertices[vertex].is_finite(), context_part + ": non-finite rest vertex")
				checked_vertices += 1
		if safe:
			valid.append(part)
	return valid


func _check_motion(doll: Node3D, context: String) -> void:
	var parts := _check_weights(doll, context)
	for activity in ["idle", "browsing", "checkout", "sewing"]:
		for phase in [0.0, 0.5, 1.5]:
			doll.rig.animate(phase, 1.0 if activity == "idle" else 0.35, activity, phase)
			doll.rig.skeleton.force_update_all_bone_transforms()
			checked_poses += 1
			var pose_context := "%s %s %.1f" % [context, activity, phase]
			for bone in doll.rig.skeleton.get_bone_count():
				_check(doll.rig.skeleton.get_bone_global_pose(bone).is_finite(), pose_context + ": non-finite bone pose")
			for part in parts:
				var posed: PackedVector3Array = doll.rig.deformed_vertices(part)
				_check(posed.size() == part.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size(), pose_context + ": posed vertex count changed")
				for point in posed:
					_check(point.is_finite(), pose_context + ": non-finite posed vertex: " + str(part.name))
	doll.rig.animate(0.0, 0.0, "idle", 0.0)


func _check_shell(doll: Node3D, context: String) -> void:
	var shell := doll.body_rig.get_node_or_null("SkinnedMeshes/garment/TailoredShell") as MeshInstance3D
	_check(shell != null, context + ": missing TailoredShell")
	if shell == null:
		return
	_check(shell.is_visible_in_tree(), context + ": configured outfit shell hidden")
	_check(shell.get_meta("garment_component", "") == "fitted_nested_shell", context + ": not using fitted approved nested shell")
	_check(shell.mesh != null and shell.mesh.get_surface_count() == 1, context + ": shell must have one nonempty surface")
	if shell.mesh == null or shell.mesh.get_surface_count() != 1:
		return
	var arrays := shell.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	_check(not indices.is_empty() and indices.size() % 3 == 0, context + ": invalid shell triangles")
	if indices.is_empty() or indices.size() % 3 != 0:
		return
	var neighbors := {}
	for index in indices:
		_check(index >= 0 and index < vertices.size(), context + ": shell index out of bounds")
		if index < 0 or index >= vertices.size():
			return
		neighbors[index] = []
	for triangle in range(0, indices.size(), 3):
		for corner in 3:
			neighbors[indices[triangle + corner]].append(indices[triangle + (corner + 1) % 3])
	var visited := {}
	var panels := 0
	for start: int in neighbors:
		if visited.has(start): continue
		panels += 1
		var pending: Array[int] = [start]
		while not pending.is_empty():
			var index: int = pending.pop_back()
			if visited.has(index): continue
			visited[index] = true
			for adjacent: int in neighbors[index]:
				if not visited.has(adjacent): pending.append(adjacent)
	# Preserve the approved nested torso/two-sleeve construction, not a new body silhouette.
	_check(panels == 3, context + ": expected torso and two continuous sleeve panels")
	_check(visited.size() == vertices.size(), context + ": unreferenced shell vertices")


func _check_item_state(item: Node3D, customer: Node3D, stock: Node3D, worn: bool, context: String) -> void:
	_check(item.get_parent() == stock and item.stock_parent == stock, context + ": stock lost ownership of garment node")
	_check(item.owner_id == "shop" and not item.paid, context + ": try-on changed purchase ownership")
	_check(item.reserved_by == customer.customer_id, context + ": reservation lost")
	_check(item.holder != null and item.holder.get_ref() == customer, context + ": garment holder inconsistent")
	_check(item.location == ("worn" if worn else "carried"), context + ": incorrect location")
	_check(item.presentation == ("Worn" if worn else "Folded"), context + ": incorrect presentation")
	_check(customer.wearing == worn and customer.carrying == (not worn), context + ": customer flags inconsistent")
	_check(customer.garments.count(item) == 1 and customer.garment == item, context + ": garment membership inconsistent")
	_check(item.is_visible_in_tree() and not item.parts.is_empty(), context + ": garment missing or hidden")
	var visible_parts := 0
	for index in item.parts.size():
		var part: MeshInstance3D = item.parts[index]
		_check(not _is_body(part) and str(part.name) not in LEGACY_BODY, context + ": wearer body leaked into inventory garment")
		if part.is_visible_in_tree():
			visible_parts += 1
		_check(part.material_override == (item.worn_materials[index] if worn else item.prop_materials[index]),
			context + ": presentation material inconsistent")
	_check(visible_parts > 0, context + ": all garment parts hidden")
	_check(item.global_transform.is_finite(), context + ": non-finite attachment")
	if worn:
		_check(item.global_transform.is_equal_approx(customer.body_rig.global_transform), context + ": worn attachment drifted")
		_check(item.skeleton.get_bone_count() == customer.rig.skeleton.get_bone_count(), context + ": garment rig count mismatch")
		for bone in mini(item.skeleton.get_bone_count(), customer.rig.skeleton.get_bone_count()):
			_check(item.skeleton.get_bone_name(bone) == customer.rig.skeleton.get_bone_name(bone), context + ": garment bone order mismatch")
			_check(item.skeleton.get_bone_rest(bone) == customer.rig.skeleton.get_bone_rest(bone), context + ": garment rest differs from wearer")
			_check(item.skeleton.get_bone_pose(bone).is_equal_approx(customer.rig.skeleton.get_bone_pose(bone)), context + ": garment pose differs from wearer")


func _check_wardrobe(accepted: Node3D, expected: Dictionary) -> void:
	var stock := Node3D.new()
	root.add_child(stock)
	var customer := Customer.new()
	customer.customer_id = "accepted-body-regression"
	root.add_child(customer)
	if not _configure(customer, 2):
		customer.free()
		stock.free()
		return
	_check_body(customer, expected, "customer configured")
	_check_rest(customer, accepted, "customer configured")
	var initial_visibility := _visibility(customer)
	for style in [0, 1, 2]:
		var context := "wardrobe style %d" % style
		var item := Garment.new()
		item.item_id = "accepted-body-%d" % style
		item.definition = Definition.create(style, 0)
		stock.add_child(item)
		item.build()
		item.set_process(false)
		var built: bool = is_instance_valid(item.skeleton) and item.forms != null and not item.parts.is_empty()
		_check(built, context + ": garment build incomplete")
		if not built:
			item.free()
			continue
		item.place("rack", Transform3D.IDENTITY, 0)
		_check(item.presentation == "Hanging" and item.owner_id == "shop", context + ": initial rack state inconsistent")
		_check(item.reserve(customer), context + ": reserve failed")
		_check(customer.carry_item(item), context + ": carry failed")
		_check_item_state(item, customer, stock, false, context + " carried")
		var contact_flags: Array[bool] = []
		var layer_flags: Array = []
		for material in item.worn_materials:
			contact_flags.append(material is ShaderMaterial and material.get_shader_parameter("cloth_contact_enabled") == true)
			layer_flags.append([material.get_shader_parameter("cloth_outer_layer"), material.get_shader_parameter("cloth_skirt_side"), material.get_shader_parameter("cloth_secondary_enabled")])
		item.apply_material_data({"pigment": Color("709aa3"), "pattern": "check", "material": "cotton"})
		for index in item.worn_materials.size():
			if not contact_flags[index]: continue
			_check(item.worn_materials[index].get_shader_parameter("cloth_contact_enabled") == true, context + ": fabric replacement lost body contact")
			_check(item.prop_materials[index].get_shader_parameter("cloth_contact_enabled") != true, context + ": folded cloth must not contact an absent body")
			_check(item.worn_materials[index].get_shader_parameter("cloth_outer_layer") == layer_flags[index][0], context + ": fabric replacement lost layering")
			_check(item.worn_materials[index].get_shader_parameter("cloth_skirt_side") == layer_flags[index][1], context + ": fabric replacement lost skirt-side contact")
			_check(item.worn_materials[index].get_shader_parameter("cloth_secondary_enabled") == layer_flags[index][2], context + ": fabric replacement lost secondary motion")
			if layer_flags[index][2] == true:
				var arrays: Array = item.parts[index].mesh.surface_get_arrays(0)
				_check(arrays[Mesh.ARRAY_TEX_UV2] != null and arrays[Mesh.ARRAY_TEX_UV2].size() == arrays[Mesh.ARRAY_VERTEX].size(), context + ": folding lost stable cloth coordinates")
				if arrays[Mesh.ARRAY_TEX_UV2] != null:
					for binding: Vector2 in arrays[Mesh.ARRAY_TEX_UV2]:
						_check(binding.x >= 0 and binding.x <= 1 and absf(binding.y - 1) < .001, context + ": interpolated motion coordinates invalid")
		for cycle in 2:
			_check(customer.put_on(item), context + ": put_on failed")
			customer.rig.animate(0.5, 0.6, "checkout", 0.5)
			item.update_attachment()
			_check_item_state(item, customer, stock, true, context + " worn")
			_check_body(customer, expected, context + " worn")
			_check(customer.take_off(item), context + ": take_off failed")
			_check_item_state(item, customer, stock, false, context + " removed")
			_check(_visibility(customer) == initial_visibility, context + ": take_off did not restore own outfit")
			_check_body(customer, expected, context + " removed")
			_check_rest(customer, accepted, context + " removed")
			wardrobe_cycles += 1
		customer.garments.erase(item)
		customer.refresh_outfit()
		item.place("rack", Transform3D.IDENTITY, 0)
		_check(item.holder == null and item.reserved_by.is_empty() and item.presentation == "Hanging",
			context + ": returning to rack retained holder/reservation/presentation")
		item.free()
	customer.free()
	stock.free()


func _run() -> void:
	var accepted := Accepted.new()
	accepted.arm_shortening = 0.045
	root.add_child(accepted)
	var doll := GameBody.new()
	root.add_child(doll)
	# Reconfigure the same instance to catch state leaking between outfits.
	for outfit in [0, 1, 2]:
		if not _configure(accepted, outfit):
			continue
		accepted.set_underbody_mode(true)
		var expected := _body_snapshot(accepted)
		_check(not expected.is_empty(), "accepted body snapshot is empty")
		if not _configure(doll, outfit):
			continue
		var context := "outfit %d" % outfit
		_check(not doll.is_underbody_mode, context + ": configure left body in underbody mode")
		_check_body(doll, expected, context + " configured")
		_check_rest(doll, accepted, context)
		_check_shell(doll, context)
		_check_toggles(doll, expected, context)
		_check_motion(doll, context)
		_check_body(doll, expected, context + " after movement")
		_check_rest(doll, accepted, context + " after movement")
	_check_wardrobe(accepted, _body_snapshot(accepted))
	_check(checked_vertices > 0, "skin-weight coverage did not execute")
	_check(checked_poses == 36, "movement coverage did not complete all 36 poses")
	_check(wardrobe_cycles == 6, "wardrobe coverage did not complete all six wear/take-off cycles")
	doll.free()
	accepted.free()
	print("ACCEPTED_GAME_BODY checks=", checks, " vertices=", checked_vertices,
		" poses=", checked_poses, " wardrobe_cycles=", wardrobe_cycles, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
