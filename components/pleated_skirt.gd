@tool
class_name PleatedSkirt
extends Node3D

## Reusable, deterministically rebuilt pleated skirt from a versioned design.
##
## Geometry follows Docs/PLEATED_SKIRT_CONTRACT.md: Y up, metres, waist at
## y=length, hem at y=0, u=0/1 at the back (-Z), v=0 at the waist. Every pleat
## gets eight circumferential samples; the shell has 24 vertical rows, a real
## inner wall offset along the local surface normal, and connected waist/hem
## rims that leave both openings unobstructed.

signal design_changed
signal geometry_rebuilt

const Design = preload("res://scripts/pleated_skirt_design.gd")
const Dynamics = preload("res://scripts/pleated_skirt_dynamics.gd")
const PreviewPoses = preload("res://scripts/garment_preview_poses.gd")

const SEGMENTS_PER_PLEAT := 8
const VERTICAL_ROWS := 24
const TEXTURE_SIZE := 512
const MAX_IMPORTED_TEXTURE_BYTES := 16 * 1024 * 1024
const EPSILON := 0.00001

@export_file("*.json") var design_path := "":
	set(value):
		if is_inside_tree() and not _loading_design and not value.is_empty():
			load_design(value)
		else:
			design_path = value

@export_enum("plain", "mosuo_reference", "yi_reference", "wax_reference") var default_template_id := "plain"

var design: Dictionary = {}
var last_error := ""
var last_error_code := OK

var _mesh_instance: MeshInstance3D = null
var _material: StandardMaterial3D = null
var _source_texture_path := ""
var _texture_source := ""
var _loading_design := false
var _rebuild_count := 0
var _raw_shell: Dictionary = {}
var _bound_doll: WeakRef = null
var _cage_mesh: MeshInstance3D = null
var _binding: RefCounted = null
var _fitted_rest := PackedVector3Array()
var _constraint: RefCounted = null
var _inertia: RefCounted = null
var _last_warp_error := 0.0


func _ready() -> void:
	if not design_path.is_empty():
		load_design(design_path)
	elif design.is_empty():
		configure(Design.default_design(default_template_id))
	else:
		rebuild()


func configure(data: Dictionary) -> Error:
	var inspected := Design.inspect_design(data)
	if not inspected["ok"]:
		last_error = String(inspected["error"])
		last_error_code = int(inspected["code"])
		return last_error_code
	design = inspected["design"]
	_source_texture_path = ""
	design_path = ""
	last_error = ""
	last_error_code = OK
	rebuild()
	design_changed.emit()
	return OK


func load_design(path: String) -> Error:
	_loading_design = true
	var loaded := Design.load_design_file(path)
	if not loaded["ok"]:
		last_error = String(loaded["error"])
		last_error_code = int(loaded["code"])
		_loading_design = false
		return last_error_code
	design = loaded["design"]
	_source_texture_path = String(loaded.get("texture_path", ""))
	design_path = path
	last_error = ""
	last_error_code = OK
	rebuild()
	_loading_design = false
	design_changed.emit()
	return OK


func export_design(path: String) -> Error:
	if design.is_empty():
		last_error = "No design has been configured."
		last_error_code = ERR_UNCONFIGURED
		return last_error_code
	var saved := Design.save_design_file(path, design)
	if not saved["ok"]:
		last_error = String(saved["error"])
		last_error_code = int(saved["code"])
		return last_error_code
	last_error = ""
	last_error_code = OK
	return OK


func get_design_json() -> String:
	var encoded := Design.encode_design(design)
	if not encoded["ok"]:
		return ""
	return String(encoded["text"])


func rebuild() -> void:
	if design.is_empty():
		return
	var built := _build_shell(design)
	_raw_shell = built
	var mesh_instance := _ensure_mesh_instance()
	mesh_instance.mesh = built["mesh"]
	_material = _build_material(design)
	mesh_instance.material_override = _material
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mesh_instance.set_meta("pleated_skirt_schema", Design.SCHEMA)
	mesh_instance.set_meta("outer_vertex_count", built["outer_vertex_count"])
	mesh_instance.set_meta("inner_vertex_count", built["inner_vertex_count"])
	mesh_instance.set_meta("rim_vertex_count", built["rim_vertex_count"])
	mesh_instance.set_meta("columns", built["columns"])
	mesh_instance.set_meta("vertical_rows", built["rows"])
	mesh_instance.set_meta("thickness_m", built["thickness_m"])
	mesh_instance.set_meta("open_waist_hem", true)
	mesh_instance.set_meta("fabric", String(design["parameters"]["fabric"]))
	mesh_instance.set_meta("texture_source", _texture_source)
	set_meta("pleated_skirt_schema", Design.SCHEMA)
	set_meta("rebuild_count", _rebuild_count)
	_rebuild_count += 1
	if _bound_doll != null and is_instance_valid(_bound_doll.get_ref()):
		bind_to_doll(_bound_doll.get_ref())
	geometry_rebuilt.emit()


## Applies Toolkit standalone silhouette, hem ellipse, and longitudinal length
## constraints to the current skirt shell without modifying the raw contract
## metadata. Returns the maximum warp length error.
func apply_standalone_drape(spin_time: float = 0.0, motion: Dictionary = Dynamics.DEFAULT_MOTION) -> float:
	if design.is_empty() or _raw_shell.is_empty():
		return 0.0
	var cols: int = int(_raw_shell["columns"])
	var rows: int = int(_raw_shell["rows"])
	var rest_pos: PackedVector3Array = _raw_shell["vertices"]
	var p := rest_pos.duplicate()
	var n: PackedVector3Array = (_raw_shell["normals"] as PackedVector3Array).duplicate()
	var solo_constraint := Dynamics.DrapeConstraint.new(cols, rows, rest_pos)
	var dyn: RefCounted = null
	if spin_time > 0.0:
		if _inertia == null:
			_inertia = Dynamics.SkirtInertia.new()
		dyn = _inertia.sample(spin_time, design, motion)
	Dynamics.natural_envelope(p, rest_pos, design, cols + 1, dyn)
	solo_constraint.project_lengths(p)
	solo_constraint.finish_surface(p, n)
	_last_warp_error = solo_constraint.max_warp_error(p)
	_apply_deformed_arrays(p, n)
	return _last_warp_error


## Binds this PleatedSkirt to a VolumeDoll (using its 40x8 LongSkirt deformation
## cage), preparing it for stand/walk/sit/lie/display/spin posing.
func bind_to_doll(doll: Node3D) -> bool:
	if doll == null or not is_instance_valid(doll) or doll.get("rig") == null:
		return false
	if design.is_empty():
		configure(Design.default_design(default_template_id))
	_bound_doll = weakref(doll)
	_cage_mesh = null
	for part: MeshInstance3D in doll.rig.meshes:
		if str(part.name) == "LongSkirt":
			_cage_mesh = part
		var semantic := str(part.get_meta("semantic", ""))
		if semantic in ["skirt", "apron"] or str(part.name) in ["WaistRibbon", "ApronStrapL", "ApronStrapR", "ApronTie"]:
			part.visible = false
	if _cage_mesh == null:
		return false
	var garment: Object = doll.get("_garment")
	if garment != null and is_instance_valid(garment) and garment.get("waist_height") != null:
		if absf(float(garment.get("waist_height")) - 1.31) > 0.001:
			garment.set("waist_height", 1.31)
			if garment.has_method("rebuild"):
				garment.call("rebuild")
	_ensure_preview_thighs(doll)
	doll.rig.animate(0.0, 0.0, "idle", 0.0)
	var cage_rest: PackedVector3Array = doll.rig.deformed_vertices(_cage_mesh)
	var cols: int = int(_raw_shell["columns"])
	var rows: int = int(_raw_shell["rows"])
	var length_cm := float(design["parameters"]["length_cm"])
	_binding = Dynamics.GarmentBinding.new(
		_raw_shell["vertices"],
		_raw_shell["normals"],
		_raw_shell["uvs"],
		cage_rest,
		length_cm
	)
	_binding.deform(cage_rest)
	_fitted_rest = _binding.positions.duplicate()
	_constraint = Dynamics.DrapeConstraint.new(cols, rows, _fitted_rest)
	_inertia = Dynamics.SkirtInertia.new()
	return true


func _ensure_preview_thighs(doll: Node3D) -> void:
	if doll.get("legs") == null:
		return
	for leg in doll.legs:
		if leg.get_node_or_null("PreviewThigh") != null:
			continue
		if doll.has_method("_lathe") and doll.get("SKIN_TONES") != null:
			var thigh: MeshInstance3D = doll._lathe(leg, "PreviewThigh", [
				Vector3(-0.50, 0.080, 0.084),
				Vector3(-0.40, 0.075, 0.079),
				Vector3(-0.20, 0.102, 0.108),
				Vector3(0.02, 0.115, 0.120),
				Vector3(0.10, 0.105, 0.110),
			], doll.SKIN_TONES[doll.skin_index], 16)
			thigh.position.z = 0.045


## Evaluates the full Toolkit pleated-skirt pose & physics pipeline on the bound
## VolumeDoll and updates the SkirtMesh surface in-place.
func pose_on_doll(action: String = "stand", progress: float = 0.0, elapsed: float = 0.0, motion: Dictionary = Dynamics.DEFAULT_MOTION) -> Dictionary:
	var doll: Node3D = _bound_doll.get_ref() if _bound_doll != null else null
	if doll == null or not is_instance_valid(doll) or _binding == null or _constraint == null or _cage_mesh == null:
		return {"ok": false, "warp_error": 0.0}
	var clamped_progress := clampf(progress, 0.0, 1.0)
	var base_action := "stand" if action in ["display", "spin"] else action
	doll.rig.animate(TAU * clamped_progress if base_action == "walk" else 0.0, 1.0 if base_action == "walk" else 0.0, "idle", 0.0)
	if base_action in ["sit", "lie"]:
		PreviewPoses._pose_rest_frame(doll, base_action, clamped_progress)
	var cage_positions: PackedVector3Array = doll.rig.deformed_vertices(_cage_mesh)
	_binding.deform(cage_positions)
	var cols: int = int(_raw_shell["columns"])
	var rows: int = int(_raw_shell["rows"])
	var width := cols + 1
	var length_cm := float(design["parameters"]["length_cm"])
	var grip_active := false
	var grip_row := 0
	var hem_lag := 0.0
	var hem_opening := 0.0

	if action in ["stand", "display", "spin"]:
		var dyn: RefCounted = null
		if action == "spin":
			dyn = _inertia.sample(elapsed, design, motion)
			hem_lag = dyn.lag[rows]
			hem_opening = dyn.opening[rows]
		Dynamics.natural_envelope(_binding.positions, _fitted_rest, design, width, dyn)
		_constraint.project_lengths(_binding.positions)
	else:
		var relaxed := _fitted_rest.duplicate()
		Dynamics.natural_envelope(relaxed, _fitted_rest, design, width, null)
		_constraint.project_lengths(relaxed)
		var resting := action in ["sit", "lie"]
		var support := Dynamics.rest_frame_from_doll(doll) if resting else {}
		if resting:
			Dynamics.transform_rest_cloth(_binding.positions, support, _constraint.shell, true)
		for i in range(_constraint.shell):
			_binding.positions[i] += relaxed[i] - _fitted_rest[i]
		var rest_progress := minf(1.0, clamped_progress / 0.4) if action == "lie" else clamped_progress
		var amount := 0.35 if action == "walk" else rest_progress * rest_progress * (3.0 - 2.0 * rest_progress)
		var drape := Dynamics.effective_drape(design)
		var knee_drop := 0.2 * cos(float(support.get("angle", 0.0))) if resting else 0.0
		_constraint.apply(_binding.positions, _binding.normals, drape, amount, "sit" if resting else action, relaxed, knee_drop)
		if resting:
			Dynamics.transform_rest_cloth(_binding.positions, support, _constraint.shell, false)
			Dynamics.settle_reclining_cloth(_binding.positions, width, rows, float(support.get("angle", 0.0)), float(drape["weight"]), _constraint)

	if action == "display":
		var natural: PackedVector3Array = (_binding.positions as PackedVector3Array).duplicate()
		var hands := Dynamics.grasp_skirt(_binding.positions, natural, width, clamped_progress, motion)
		if not hands.is_empty():
			grip_active = bool(hands[0]["contact"])
			grip_row = int(hands[0]["row"])
			for hand in hands:
				var suffix := "L" if float(hand["side"]) < 0.0 else "R"
				if doll.rig.has_method("reach_hand"):
					doll.rig.reach_hand(suffix, doll.to_global(hand["target"]))

	_constraint.finish_surface(_binding.positions, _binding.normals)
	_last_warp_error = _constraint.max_warp_error(_binding.positions)
	var cover_cut := 1.31 - (length_cm / 100.0) * (1.11 / 0.88) + 0.025 - (clamped_progress * 0.25 if action == "lie" else 0.0)
	_update_leg_visibility(doll, cover_cut)
	_apply_deformed_arrays(_binding.positions, _binding.normals)
	return {
		"ok": true,
		"warp_error": _last_warp_error,
		"hem_lag": hem_lag,
		"hem_opening": hem_opening,
		"grip": grip_active,
		"grip_row": grip_row,
		"cover_cut": cover_cut,
	}


func _update_leg_visibility(doll: Node3D, cover_cut: float) -> void:
	if doll.get("legs") == null:
		return
	for leg in doll.legs:
		var thigh := leg.get_node_or_null("PreviewThigh") as MeshInstance3D
		if thigh != null:
			thigh.visible = cover_cut > 0.62


func get_last_warp_error() -> float:
	return _last_warp_error


func get_inertia() -> RefCounted:
	return _inertia


func _apply_deformed_arrays(p: PackedVector3Array, n: PackedVector3Array) -> void:
	if _raw_shell.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = p
	arrays[Mesh.ARRAY_NORMAL] = n
	arrays[Mesh.ARRAY_TEX_UV] = _raw_shell["uvs"]
	arrays[Mesh.ARRAY_INDEX] = _raw_shell["indices"]
	var mesh_instance := _ensure_mesh_instance()
	var mesh := ArrayMesh.new()
	mesh.resource_name = "PleatedSkirt_%s" % String(design.get("design_id", "draped"))
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.set_meta("pleated_skirt_schema", Design.SCHEMA)
	mesh.set_meta("open_waist_hem", true)
	mesh.set_meta("seam_axis", "-Z")
	mesh.set_meta("vertical_rows", int(_raw_shell["rows"]))
	mesh.set_meta("segments_per_pleat", SEGMENTS_PER_PLEAT)
	mesh_instance.mesh = mesh


func get_mesh_instance() -> MeshInstance3D:
	return _ensure_mesh_instance()


func get_active_material() -> StandardMaterial3D:
	return _material


func get_texture_source() -> String:
	return _texture_source


static func fabric_roughness(fabric: String) -> float:
	match fabric:
		"cotton":
			return 0.86
		"linen":
			return 0.68
		"silk":
			return 0.24
		"wool":
			return 0.97
	return 0.86


func _ensure_mesh_instance() -> MeshInstance3D:
	if _mesh_instance != null and is_instance_valid(_mesh_instance):
		return _mesh_instance
	_mesh_instance = get_node_or_null("SkirtMesh") as MeshInstance3D
	if _mesh_instance == null:
		_mesh_instance = MeshInstance3D.new()
		_mesh_instance.name = "SkirtMesh"
		add_child(_mesh_instance)
	return _mesh_instance


func _build_shell(data: Dictionary) -> Dictionary:
	var parameters: Dictionary = data["parameters"]
	var shape := {
		"length": float(parameters["length_cm"]) / 100.0,
		"waist_radius": (float(parameters["waist_cm"]) / 100.0) / TAU,
		"hem_radius": (float(parameters["hem_cm"]) / 100.0) / TAU,
		"pleat_count": int(parameters["pleat_count"]),
		"pleat_depth": float(parameters["pleat_depth_cm"]) / 100.0,
		"sharpness": float(parameters["sharpness"]),
	}
	var thickness := float(parameters["thickness_mm"]) / 1000.0
	var columns := int(shape["pleat_count"]) * SEGMENTS_PER_PLEAT
	var rows := VERTICAL_ROWS
	var column_count := columns + 1
	var outer_vertices := PackedVector3Array()
	var outer_normals := PackedVector3Array()
	var inner_vertices := PackedVector3Array()
	var inner_normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	outer_vertices.resize(column_count * (rows + 1))
	outer_normals.resize(column_count * (rows + 1))
	inner_vertices.resize(column_count * (rows + 1))
	inner_normals.resize(column_count * (rows + 1))
	uvs.resize(column_count * (rows + 1))

	for row in range(rows + 1):
		var v := float(row) / float(rows)
		for column in range(column_count):
			var u := float(column) / float(columns)
			var point := _skirt_position(u, v, shape)
			var normal := _skirt_normal(u, v, shape)
			var index := row * column_count + column
			outer_vertices[index] = point + normal * thickness * 0.5
			outer_normals[index] = normal
			inner_vertices[index] = point - normal * thickness * 0.5
			inner_normals[index] = -normal
			uvs[index] = Vector2(u, v)

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var mesh_uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	vertices.append_array(outer_vertices)
	normals.append_array(outer_normals)
	vertices.append_array(inner_vertices)
	normals.append_array(inner_normals)
	mesh_uvs.append_array(uvs)
	mesh_uvs.append_array(uvs)

	var outer_base := 0
	var inner_base := outer_vertices.size()
	for row in range(rows):
		for column in range(columns):
			var a := row * column_count + column
			var b := a + 1
			var c := a + column_count
			var d := c + 1
			# Clockwise in Godot's front-face convention: (c-a) x (b-a) points out.
			indices.append_array(PackedInt32Array([outer_base + a, outer_base + c, outer_base + b]))
			indices.append_array(PackedInt32Array([outer_base + b, outer_base + c, outer_base + d]))
			# The inner wall faces the cavity, so its winding is reversed.
			indices.append_array(PackedInt32Array([inner_base + a, inner_base + b, inner_base + c]))
			indices.append_array(PackedInt32Array([inner_base + b, inner_base + d, inner_base + c]))

	var rim_vertices := PackedVector3Array()
	var rim_normals := PackedVector3Array()
	var rim_uvs := PackedVector2Array()
	var rim_base := vertices.size()
	# Outer waist, inner waist, outer hem, inner hem.
	for ring in range(4):
		for column in range(column_count):
			var source_index := column if ring < 2 else rows * column_count + column
			var point := outer_vertices[source_index] if ring % 2 == 0 else inner_vertices[source_index]
			var normal := Vector3.UP if ring < 2 else Vector3.DOWN
			rim_vertices.append(point)
			rim_normals.append(normal)
			rim_uvs.append(Vector2(float(column) / float(columns), 0.0 if ring < 2 else 1.0))
	vertices.append_array(rim_vertices)
	normals.append_array(rim_normals)
	mesh_uvs.append_array(rim_uvs)

	var waist_outer := rim_base
	var waist_inner := rim_base + column_count
	var hem_outer := rim_base + column_count * 2
	var hem_inner := rim_base + column_count * 3
	for column in range(columns):
		var next := column + 1
		# Waist rim faces up.
		indices.append_array(PackedInt32Array([waist_outer + column, waist_outer + next, waist_inner + column]))
		indices.append_array(PackedInt32Array([waist_inner + column, waist_outer + next, waist_inner + next]))
		# Hem rim faces down.
		indices.append_array(PackedInt32Array([hem_outer + column, hem_inner + column, hem_outer + next]))
		indices.append_array(PackedInt32Array([hem_inner + column, hem_inner + next, hem_outer + next]))

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = mesh_uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.resource_name = "PleatedSkirt_%s" % String(data["design_id"])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.set_meta("pleated_skirt_schema", Design.SCHEMA)
	mesh.set_meta("open_waist_hem", true)
	mesh.set_meta("seam_axis", "-Z")
	mesh.set_meta("vertical_rows", rows)
	mesh.set_meta("segments_per_pleat", SEGMENTS_PER_PLEAT)

	return {
		"mesh": mesh,
		"vertices": vertices,
		"normals": normals,
		"uvs": mesh_uvs,
		"indices": indices,
		"outer_vertex_count": outer_vertices.size(),
		"inner_vertex_count": inner_vertices.size(),
		"rim_vertex_count": rim_vertices.size(),
		"columns": columns,
		"rows": rows,
		"thickness_m": thickness,
	}


func _skirt_position(u: float, v: float, shape: Dictionary) -> Vector3:
	var local_radius := lerpf(float(shape["waist_radius"]), float(shape["hem_radius"]), v)
	var pleat_count := int(shape["pleat_count"])
	var phase := fposmod(u * float(pleat_count), 1.0)
	var cosine_wave := cos(TAU * phase)
	var triangle_wave := absf(2.0 * phase - 1.0) * 2.0 - 1.0
	var wave := lerpf(cosine_wave, triangle_wave, float(shape["sharpness"]))
	var depth_limit := TAU * local_radius / float(pleat_count) * 0.45
	var amplitude := minf(float(shape["pleat_depth"]), depth_limit) * lerpf(0.15, 1.0, v)
	var radius := local_radius + amplitude * wave
	var angle := TAU * u
	if u >= 1.0:
		# Make the u=1 seam vertex exactly coincide with u=0, not merely close.
		angle = 0.0
	return Vector3(sin(angle) * radius, float(shape["length"]) * (1.0 - v), -cos(angle) * radius)


func _skirt_normal(u: float, v: float, shape: Dictionary) -> Vector3:
	var wrapped_u := fposmod(u, 1.0)
	var u_low := fposmod(wrapped_u - EPSILON, 1.0)
	var u_high := fposmod(wrapped_u + EPSILON, 1.0)
	var v_low := maxf(v - EPSILON, 0.0)
	var v_high := minf(v + EPSILON, 1.0)
	var du := _skirt_position(u_high, v, shape) - _skirt_position(u_low, v, shape)
	var dv := _skirt_position(wrapped_u, v_high, shape) - _skirt_position(wrapped_u, v_low, shape)
	var normal := du.cross(dv)
	if normal.length_squared() < 0.000000000001:
		var point := _skirt_position(wrapped_u, v, shape)
		normal = Vector3(point.x, 0.0, point.z)
		if normal.length_squared() < 0.000000000001:
			normal = Vector3.UP
	return normal.normalized()


func _build_material(data: Dictionary) -> StandardMaterial3D:
	var parameters: Dictionary = data["parameters"]
	var material := StandardMaterial3D.new()
	material.resource_name = "PleatedSkirtMaterial"
	material.albedo_color = Color.WHITE
	material.albedo_texture = _build_texture(data)
	material.roughness = fabric_roughness(String(parameters["fabric"]))
	material.metallic = 0.0
	material.metallic_specular = 0.35 if String(parameters["fabric"]) != "silk" else 0.75
	material.cull_mode = BaseMaterial3D.CULL_BACK
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	material.set_meta("fabric", String(parameters["fabric"]))
	return material


func _build_texture(data: Dictionary) -> Texture2D:
	if not _source_texture_path.is_empty() and FileAccess.file_exists(_source_texture_path):
		var texture_file := FileAccess.open(_source_texture_path, FileAccess.READ)
		if texture_file != null:
			var byte_count := texture_file.get_length()
			texture_file.close()
			if byte_count > 0 and byte_count <= MAX_IMPORTED_TEXTURE_BYTES:
				var imported := Image.load_from_file(_source_texture_path)
				if imported != null and not imported.is_empty():
					imported.generate_mipmaps()
					_texture_source = "sibling_png"
					return ImageTexture.create_from_image(imported)
	return _generate_texture(data)


func _generate_texture(data: Dictionary) -> Texture2D:
	var parameters: Dictionary = data["parameters"]
	var image := Image.create_empty(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(String(parameters["base_color"])))
	for band in data["bands"]:
		_paint_region(image, band, 0.0, 1.0, float(band["start"]), float(band["end"]))
	for patch in data["patches"]:
		_paint_region(image, patch, float(patch["u0"]), float(patch["u1"]), float(patch["v0"]), float(patch["v1"]))
	for stroke in data["strokes"]:
		_paint_stroke(image, stroke)
	image.generate_mipmaps()
	_texture_source = "generated"
	return ImageTexture.create_from_image(image)


func _paint_region(image: Image, entry: Dictionary, u0: float, u1: float, v0: float, v1: float) -> void:
	var size := Vector2(image.get_width(), image.get_height())
	var region := Rect2(Vector2(u0, v0) * size, Vector2(u1 - u0, v1 - v0) * size)
	var clip := Rect2i(Vector2i(region.position.floor()), Vector2i(region.end.ceil()) - Vector2i(region.position.floor()))
	clip = clip.intersection(Rect2i(Vector2i.ZERO, Vector2i(size)))
	image.fill_rect(clip, Color(String(entry["color"])))
	var pattern := String(entry["pattern"])
	if pattern == "solid":
		return
	var step := size.x / float(entry["repeat"])
	var line_width := maxf(1.0, step * 0.05)
	var ink := Color("#f2e9d4")
	for index in range(int(floor(region.position.x / step)) - 1, int(ceil(region.end.x / step)) + 1):
		var center := Vector2((float(index) + 0.5) * step, region.get_center().y)
		if pattern == "dash":
			var dash := Rect2i(Vector2i(center.x - step * 0.12, region.position.y + region.size.y * 0.25), Vector2i(ceil(step * 0.24), ceil(region.size.y * 0.5)))
			image.fill_rect(dash.intersection(clip), ink)
			continue
		var corners := [center + Vector2(0, -region.size.y * 0.36), center + Vector2(step * 0.4, 0), center + Vector2(0, region.size.y * 0.36), center + Vector2(-step * 0.4, 0)]
		for corner in 4:
			_draw_capsule(image, corners[corner], corners[(corner + 1) % 4], ink, line_width, clip)
		if pattern == "wax":
			var radius := minf(step * 0.16, region.size.y * 0.18)
			for segment in 24:
				var a := center + Vector2.from_angle(TAU * float(segment) / 24.0) * radius
				var b := center + Vector2.from_angle(TAU * float(segment + 1) / 24.0) * radius
				_draw_capsule(image, a, b, ink, line_width, clip)
			var dot := Rect2i(Vector2i(center.x - step * 0.04, region.position.y + region.size.y * 0.07), Vector2i(ceil(step * 0.08), ceil(region.size.y * 0.07)))
			image.fill_rect(dot.intersection(clip), ink)


func _paint_stroke(image: Image, stroke: Dictionary) -> void:
	var points: Array = stroke["points"]
	if points.is_empty():
		return
	var color := Color(String(stroke["color"]))
	var width := float(stroke["width"]) * float(image.get_width())
	var clip := Rect2i(0, 0, image.get_width(), image.get_height())
	var previous := Vector2(float(points[0][0]) * image.get_width(), float(points[0][1]) * image.get_height())
	_draw_capsule(image, previous, previous, color, width, clip)
	for index in range(1, points.size()):
		var current := Vector2(float(points[index][0]) * image.get_width(), float(points[index][1]) * image.get_height())
		_draw_capsule(image, previous, current, color, width, clip)
		previous = current


# Image has no draw_line API. Rasterize a clipped round-capped segment instead.
# A scanline interval bounds the capsule so long diagonal strokes do not scan
# their entire rectangular bounding box.
func _draw_capsule(image: Image, start: Vector2, finish: Vector2, ink: Color, width: float, clip: Rect2i) -> void:
	var radius := maxf(width * 0.5, 0.5)
	var delta := finish - start
	var length_squared := delta.length_squared()
	var min_y := maxi(clip.position.y, int(floor(minf(start.y, finish.y) - radius)))
	var max_y := mini(clip.end.y - 1, int(ceil(maxf(start.y, finish.y) + radius)))
	for y in range(min_y, max_y + 1):
		var sample_y := float(y) + 0.5
		var left := minf(start.x, finish.x) - radius
		var right := maxf(start.x, finish.x) + radius
		if absf(delta.y) > 0.000001:
			var t := (sample_y - start.y) / delta.y
			var center_x := start.x + t * delta.x
			var half_span := radius * sqrt(length_squared) / absf(delta.y)
			left = maxf(left, center_x - half_span)
			right = minf(right, center_x + half_span)
		for x in range(maxi(clip.position.x, int(floor(left))), mini(clip.end.x - 1, int(ceil(right))) + 1):
			var sample := Vector2(float(x) + 0.5, sample_y)
			var t := clampf((sample - start).dot(delta) / length_squared, 0.0, 1.0) if length_squared > 0.000001 else 0.0
			if sample.distance_squared_to(start + delta * t) <= radius * radius:
				image.set_pixel(x, y, ink)
