extends Node3D
## A physical package presentation. The ledger owns quantity; this node only reads it.

const PAPER := preload("res://shaders/room_paper.gdshader")
const APPEARANCE := preload("res://scripts/material_appearance.gd")
const FORMS := ["book", "roll", "spool", "ribbon", "yarn"]
const WRAP := preload("res://components/fabric_wrap_mesh.gd")
const BOOK_BOARD_SIZE := Vector3(0.016, 0.84, 0.46)
const DEFAULT_CLOTH_GAUGE_M := 0.001
const DEFAULT_CLOTH_WIDTH_M := 1.4
static var _ring_pool: Dictionary = {}
static var _yarn_strand_pool: Dictionary = {}

var data: Dictionary = {}
var form := "book"
var quantity := 0.0
var shell: MeshInstance3D
var core: Node3D
var cloth_material: ShaderMaterial
var _capacity := 1.0
var _full_radius := 0.16
var _core_radius := 0.0275
var _radius := 0.16
var _thickness := 0.2
var _gauge := DEFAULT_CLOTH_GAUGE_M
var _cloth_width := DEFAULT_CLOTH_WIDTH_M
var _winding_layers := 0
var _layers: Array[MeshInstance3D] = []
var _bands: Array[MeshInstance3D] = []
var _grips: Array[Vector3] = []
var _has_quantity := false
var open_amount := 0.0


func set_open_amount(amount: float) -> void:
	open_amount = clampf(amount,0,1)
	if form != "book" or _bands.size() < 2: return
	_bands[0].mesh = WRAP.tail(_thickness,false,open_amount)
	_bands[1].mesh = WRAP.tail(_thickness,true,open_amount)


func configure(source_data: Dictionary, package_form: String = "book") -> void:
	data = source_data
	form = package_form if package_form in FORMS else "book"
	for child in get_children():
		child.free()
	_layers.clear()
	_bands.clear()
	_has_quantity = false
	open_amount = 0.0
	core = Node3D.new()
	core.name = "FixedCore"
	add_child(core)
	var amount := _finite_number(data.get("meters", 0.0), 0.0)
	_capacity = maxf(0.0001, _finite_number(data.get("capacity_m", maxf(amount, 1.0)), maxf(amount, 1.0)))
	_gauge = clampf(_finite_number(data.get("thickness_m", DEFAULT_CLOTH_GAUGE_M), DEFAULT_CLOTH_GAUGE_M), 0.00005, 0.02)
	_cloth_width = clampf(_finite_number(data.get("width_m", DEFAULT_CLOTH_WIDTH_M), DEFAULT_CLOTH_WIDTH_M), 0.1, 3.0)
	cloth_material = APPEARANCE.make_material(data)
	match form:
		"book": _build_book()
		"roll": _build_roll()
		"spool", "ribbon": _build_spool()
		"yarn": _build_yarn()
	set_quantity(amount)


func set_quantity(meters: float) -> void:
	var next := clampf(meters, 0.0, _capacity) if is_finite(meters) else 0.0
	if _has_quantity and next == quantity:
		return
	quantity = next
	if not is_instance_valid(shell):
		return
	_has_quantity = true
	_winding_layers = 0
	if form != "book":
		_thickness = 0.0
	var fraction := quantity / _capacity
	shell.visible = quantity > 0.000001
	for layer in _layers:
		layer.visible = shell.visible
	for band in _bands:
		band.visible = shell.visible
	match form:
		"book":
			# Every layer is one cloth gauge; metres left decides how many wraps and
			# the exposed ends show the resulting continuous spiral.
			var pitch := WRAP.layer_pitch(_gauge, _cloth_width)
			_winding_layers = WRAP.winding_layers(quantity)
			_thickness = WRAP.wrapped_thickness(quantity, _gauge, _cloth_width)
			shell.mesh = WRAP.sleeve(_thickness)
			shell.mesh.set_meta("winding_layers", _winding_layers)
			shell.mesh.set_meta("layer_pitch_m", pitch)
			shell.mesh.set_meta("cloth_thickness_m", _thickness)
			shell.mesh.set_meta("remaining_meters", quantity)
			for index in _layers.size():
				var facing := -1.0 if index == 0 else 1.0
				var end_mesh := WRAP.end_winding(_thickness, pitch, _winding_layers, facing)
				end_mesh.set_meta("continuous_spiral", true)
				end_mesh.set_meta("spiral_turns", _winding_layers)
				end_mesh.set_meta("layer_pitch_m", pitch)
				end_mesh.set_meta("cloth_thickness_m", _thickness)
				end_mesh.set_meta("remaining_meters", quantity)
				_layers[index].mesh = end_mesh
			set_open_amount(open_amount)
			_grips.assign([Vector3(0, 0.12, 0.0), Vector3(0, 0.72, 0.0)])
		"roll", "spool", "ribbon":
			_radius = sqrt(_core_radius * _core_radius + (_full_radius * _full_radius - _core_radius * _core_radius) * fraction)
			var cylinder := shell.mesh as CylinderMesh
			cylinder.top_radius = _radius
			cylinder.bottom_radius = _radius
			for index in _layers.size():
				var ring_radius := lerpf(_core_radius, _radius, float(index % 3 + 1) / 4.0)
				_layers[index].mesh = _ring_mesh(ring_radius, 0.002, 28)
			if form == "roll":
				_grips.assign([Vector3(-0.38, 0.06, 0.03), Vector3(0.38, 0.06, 0.03)])
			else:
				var height := 0.24 if form == "spool" else 0.12
				_grips.assign([Vector3(-_radius - 0.012, height * 0.5, 0.0), Vector3(_radius + 0.012, height * 0.5, 0.0)])
		"yarn":
			_radius = 0.16 * pow(fraction, 1.0 / 3.0)
			var sphere := shell.mesh as SphereMesh
			sphere.radius = maxf(_radius, 0.00001)
			sphere.height = maxf(_radius * 1.7, 0.00002)
			shell.position.y = _radius * 0.85
			for index in _layers.size():
				var band := _layers[index]
				band.mesh = _yarn_strand(maxf(_radius, 0.00001), index)
				band.position.y = shell.position.y
			var label := _bands[0]
			(label.mesh as BoxMesh).size = Vector3(maxf(_radius * 1.35, 0.00001), 0.055, 0.006)
			label.position = Vector3(0, shell.position.y, _radius * 0.96)
			_grips.assign([Vector3(-_radius, shell.position.y, 0), Vector3(_radius, shell.position.y, 0)])
	set_meta("remaining_meters", quantity)
	set_meta("package_form", form)
	set_meta("winding_layers", _winding_layers)
	set_meta("cloth_thickness_m", _thickness)
	set_meta("layer_pitch_m", WRAP.layer_pitch(_gauge, _cloth_width))


func grip_points() -> Array[Vector3]:
	var result: Array[Vector3] = []
	for point in _grips:
		result.append(global_transform * point)
	return result


func display_bounds() -> AABB:
	var bounds := AABB()
	var first := true
	for part in find_children("*", "MeshInstance3D", true, false):
		if not part.visible:
			continue
		var relative: Transform3D = global_transform.affine_inverse() * part.global_transform
		var part_bounds: AABB = relative * part.mesh.get_aabb()
		bounds = part_bounds if first else bounds.merge(part_bounds)
		first = false
	return bounds


func _build_book() -> void:
	# Cloth wraps around both narrow edges. Only the board's top/bottom tabs project.
	var initial_meters := _finite_number(data.get("meters", 0.0), 0.0)
	var pitch := WRAP.layer_pitch(_gauge, _cloth_width)
	var layers := WRAP.winding_layers(initial_meters)
	var thickness := WRAP.wrapped_thickness(initial_meters, _gauge, _cloth_width)
	_box(core, "Board", BOOK_BOARD_SIZE, Vector3(0, 0.42, 0), _paper(Color("c5af89")))
	cloth_material.set_shader_parameter("use_material_uv",true)
	cloth_material.set_shader_parameter("uv_metres",Vector2.ONE)
	shell = _mesh(self,"WrappedFabric",WRAP.sleeve(thickness),Vector3(0,.42,0),cloth_material)
	var edge_material := _paper((data.get("pigment", Color("779ab1")) as Color).darkened(0.10))
	var trace_material := _paper((data.get("pigment", Color("779ab1")) as Color).lightened(0.16))
	for end in [-1, 1]:
		_layers.append(_mesh(self,"WoundClothEnd%d" % end,WRAP.end_winding(thickness,pitch,layers,end),Vector3(0,.42+end*.3705,0),trace_material))
	var tail_material := cloth_material.duplicate() as ShaderMaterial
	tail_material.set_shader_parameter("pigment",(data.get("pigment",Color("779ab1")) as Color).lightened(.025))
	_bands.append(_mesh(self,"TuckedClothTail",WRAP.tail(thickness),Vector3(0,.42,0),tail_material))
	_bands.append(_mesh(self,"FoldedSelvage",WRAP.tail(thickness,true),Vector3(0,.42,0),edge_material))


func _build_roll() -> void:
	_full_radius = 0.16
	_core_radius = 0.0275
	var tube := _cylinder(core, "RollCore", _core_radius, 1.12, Vector3(0, 0.16, 0), _paper(Color("bd9b70")))
	tube.rotation.z = PI * 0.5
	shell = _cylinder(self, "WoundFabric", _full_radius, 1.05, Vector3(0, 0.16, 0), cloth_material)
	shell.rotation.z = PI * 0.5
	_add_roll_edges(true, 0.526)


func _build_spool() -> void:
	_full_radius = 0.085 if form == "spool" else 0.115
	_core_radius = 0.0225
	var height := 0.24 if form == "spool" else 0.12
	var paper := _paper(Color("e7d8b9"))
	_cylinder(core, "Spindle", _core_radius, height, Vector3(0, height * 0.5, 0), paper)
	for y in [0.01, height - 0.01]:
		_cylinder(core, "Flange", _full_radius + 0.014, 0.02, Vector3(0, y, 0), paper)
	shell = _cylinder(self, "WoundThread" if form == "spool" else "WoundRibbon", _full_radius, height - 0.043, Vector3(0, height * 0.5, 0), cloth_material)
	cloth_material.set_shader_parameter("weave_scale", 240.0 if form == "spool" else 130.0)
	_add_roll_edges(false, height - 0.021)
	_box(core, "StockLabel", Vector3(0.045, 0.002, 0.025), Vector3(0, height + 0.001, 0), _paper(Color("c1ae87")))


func _build_yarn() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 0.16
	sphere.height = 0.272
	sphere.radial_segments = 24
	sphere.rings = 12
	shell = _mesh(self, "YarnBall", sphere, Vector3(0, 0.136, 0), cloth_material)
	cloth_material.set_shader_parameter("weave_scale", 65.0)
	var edge_material := _paper((data.get("pigment", Color("779ab1")) as Color).darkened(0.14))
	for index in 12:
		var strand := _mesh(self, "Winding", _yarn_strand(0.16, index), Vector3(0, 0.136, 0), edge_material)
		_layers.append(strand)
	_bands.append(_box(self, "PaperBand", Vector3(0.22, 0.055, 0.006), Vector3(0, 0.136, 0.155), _paper(Color("f0e7cf"))))


func _add_roll_edges(horizontal: bool, end: float) -> void:
	var edge_material := _paper((data.get("pigment", Color("779ab1")) as Color).lightened(0.25))
	for side in [-1, 1]:
		for index in 3:
			var at := Vector3(end * side, 0.16, 0) if horizontal else Vector3(0, end if side == 1 else 0.021, 0)
			var ring := _mesh(self, "WindingEdge", _ring_mesh(0.07, 0.002, 28), at, edge_material)
			if horizontal:
				ring.rotation.z = PI * 0.5
			_layers.append(ring)


func _paper(pigment: Color) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = PAPER
	material.set_shader_parameter("pigment", pigment)
	return material


func _mesh(parent: Node, label: String, mesh: Mesh, at: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = label
	instance.mesh = mesh
	instance.material_override = material
	parent.add_child(instance)
	instance.position = at
	return instance


func _box(parent: Node, label: String, size: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _mesh(parent, label, mesh, at, material)


func _cylinder(parent: Node, label: String, radius: float, height: float, at: Vector3, material: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 28
	mesh.rings = 1
	return _mesh(parent, label, mesh, at, material)


func _ring_mesh(radius: float, thickness: float, segments: int) -> ArrayMesh:
	var key := "%d:%d:%d" % [int(round(radius * 2000.0)), int(round(thickness * 10000.0)), segments]
	if _ring_pool.has(key):
		return _ring_pool[key]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in segments:
		for corner in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 0), Vector2i(1, 1), Vector2i(0, 1)]:
			var angle := TAU * float(index + corner.x) / segments
			var r := maxf(0.000001, radius + (float(corner.y) - 0.5) * thickness)
			surface.set_normal(Vector3.UP)
			surface.add_vertex(Vector3(cos(angle) * r, 0, sin(angle) * r))
	var mesh := surface.commit()
	_ring_pool[key] = mesh
	return mesh


func _yarn_strand(radius: float, index: int) -> ArrayMesh:
	var key := "%d:%d" % [int(round(radius * 2000.0)), index]
	if _yarn_strand_pool.has(key):
		return _yarn_strand_pool[key]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var orientation := Basis.from_euler(Vector3(PI * 0.5, float(index) * 0.26, 0.35))
	for segment in 28:
		for corner in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 0), Vector2i(1, 1), Vector2i(0, 1)]:
			var angle := TAU * float(segment + corner.x) / 28.0
			var local := Vector3(cos(angle) * radius, (float(corner.y) - 0.5) * 0.006, sin(angle) * radius)
			var point := orientation * local
			point.y *= 0.85
			surface.set_normal(point.normalized())
			surface.add_vertex(point)
	var mesh := surface.commit()
	_yarn_strand_pool[key] = mesh
	return mesh


func _finite_number(value: Variant, fallback: float) -> float:
	if value is float or value is int:
		return float(value) if is_finite(float(value)) else fallback
	return fallback

