extends Node3D

const PAPER = preload("res://shaders/room_paper.gdshader")
const WOOD = Color("cbb28c")
const METAL = Color("a4aaa7")
const DISPLAY_ANGLE := deg_to_rad(-35)
var mount: Marker3D
var frame: Node3D
var occupant_ids: Array[String] = []
var occupant_id: String:
	get: return occupant_ids[0] if not occupant_ids.is_empty() else ""
var _mounts: Dictionary = {}
var kind := "shoulder"
@export_range(.002,.05,.001) var layer_clearance := .012
@export_range(1.0,2.0,.05) var layer_depth_growth := 1.15
var _materials := {}


func _ready() -> void:
	# The hook stays perpendicular to the rail; the hanger and garment swivel together.
	var points := PackedVector3Array()
	for i in 13:
		var angle := lerpf(-.35, PI + .3, i / 12.0)
		points.append(Vector3(0, sin(angle) * .055, cos(angle) * .055))
	points.append(Vector3(0,-.16,0))
	points.append(Vector3(0,-.22,0))
	for i in points.size() - 1:
		_rod(self, "Hook", points[i], points[i+1], .012, METAL)
	frame = Node3D.new()
	frame.name = "SupportFrame"
	frame.rotation.y = DISPLAY_ANGLE
	add_child(frame)
	mount = Marker3D.new()
	mount.name = "GarmentMount"
	mount.rotation.y = DISPLAY_ANGLE
	add_child(mount)
	_configure_support({"kind":"shoulder", "span":.18}, 1.83)


func display(items: Array) -> void:
	occupant_ids.clear()
	for marker in _mounts.values(): marker.free()
	_mounts.clear()
	if items.is_empty(): return
	var first: Node3D = items[0]
	var profile: Dictionary = first.definition.hanger_profile()
	var height: float = first.hang_height - .018 if profile.kind == "clip" else profile.height
	_configure_support(profile, height)
	var inner: Node3D
	if items.size() == 2:
		for piece in items:
			if "outer" not in piece.definition.slots():
				inner = piece
	for item in items:
		item.reset_hanger_fit()
		occupant_ids.append(item.item_id)
		var marker := Marker3D.new()
		marker.name = "Mount_" + item.item_id
		add_child(marker)
		marker.transform = mount.transform
		# Expand the outer panels about the hanger plane to clear both
		# faces of the actual inner piece, regardless of insertion order.
		if inner != null and "outer" in item.definition.slots():
			var lining: AABB = inner.presentation_bounds("Hanging")
			var shell: AABB = item.presentation_bounds("Hanging")
			var clearance := layer_clearance
			var front := (lining.end.z + clearance) / maxf(.001,shell.end.z)
			var back := (clearance - lining.position.z) / maxf(.001,-shell.position.z)
			var depth_scale := maxf(layer_depth_growth,maxf(front,back))
			item.fit_hanger_layer(inner,clearance,depth_scale)
			marker.transform = marker.transform.scaled_local(Vector3(1,1,depth_scale))
		_mounts[item.item_id] = marker


func item_mount(item: Node3D) -> Marker3D:
	return _mounts[item.item_id]


func _configure_support(profile: Dictionary, height: float) -> void:
	kind = profile.kind
	mount.position = Vector3(0, -.32 - height, 0)
	for child in frame.get_children():
		child.free()
	var span: float = profile.span
	if kind in ["shoulder","strap"]:
		# A solid curved wooden shoulder, with strap notches, not a wire triangle.
		var width := maxf(span,.18)
		var outline := PackedVector2Array([Vector2(0,-.215),Vector2(-.055,-.219),
			Vector2(-width*.68,-.252),Vector2(-width*.77,-.266),Vector2(-width*.77,-.280),
			Vector2(-width*.88,-.279),Vector2(-width*1.10,-.310),Vector2(-width*1.12,-.330),
			Vector2(-width*1.05,-.343),Vector2(-width*.84,-.337),Vector2(-width*.47,-.290),
			Vector2(0,-.259),Vector2(width*.47,-.290),Vector2(width*.84,-.337),
			Vector2(width*1.05,-.343),Vector2(width*1.12,-.330),Vector2(width*1.10,-.310),
			Vector2(width*.88,-.279),Vector2(width*.77,-.280),Vector2(width*.77,-.266),
			Vector2(width*.68,-.252),Vector2(.055,-.219)])
		_wood("BeechShoulder",outline,.018,Vector3.ZERO)
	else:
		var depth: float = profile.depth
		# Two full-length wooden jaws. The broad U-shaped spring wraps both jaws,
		# with folded sheet-metal handles at each end (not two isolated trouser clips).
		var outline := PackedVector2Array([Vector2(-span+.012,-.265),Vector2(span-.012,-.265),
			Vector2(span,-.277),Vector2(span,-.357),Vector2(span-.012,-.369),Vector2(-span+.012,-.369),
			Vector2(-span,-.357),Vector2(-span,-.277)])
		for side in [-1.0,1.0]:
			_wood("StraightWoodJaw",outline,.026,Vector3(0,0,side*(depth+.015)))
			_box("FeltGrip",Vector3(span*1.88,.06,.006),Vector3(0,-.332,side*depth),Color("68645b"))
			_rod(frame,"SpringRail",Vector3(-span*.91,-.239,side*(depth+.04)),Vector3(span*.91,-.239,side*(depth+.04)),.007,METAL)
		for x in [-span*.86,span*.86]:
			for side in [-1.0,1.0]:
				_box("FoldedSteelHandle",Vector3(.052,.155,.009),Vector3(x,-.277,side*(depth+.036)),METAL)
				_box("HandleLip",Vector3(.052,.009,.027),Vector3(x,-.354,side*(depth+.025)),METAL)
			_rod(frame,"SpringHinge",Vector3(x,-.215,-depth-.04),Vector3(x,-.215,depth+.04),.010,METAL)
		_rod(frame,"HookSeat",Vector3(-.045,-.245,0),Vector3(.045,-.245,0),.010,METAL)


func _material(color: Color) -> Material:
	if not _materials.has(color):
		var material := ShaderMaterial.new()
		material.shader = PAPER
		material.set_shader_parameter("pigment", color)
		_materials[color] = material
	return _materials[color]


func _rod(parent: Node3D, label: String, a: Vector3, b: Vector3, radius: float, color: Color) -> void:
	var shape := CylinderMesh.new()
	shape.top_radius = radius
	shape.bottom_radius = radius
	shape.height = a.distance_to(b)
	shape.radial_segments = 8
	var part := MeshInstance3D.new()
	part.name = label
	part.mesh = shape
	part.material_override = _material(color)
	part.position = (a+b)*.5
	part.quaternion = Quaternion(Vector3.UP,(b-a).normalized())
	parent.add_child(part)


func _box(label: String, size: Vector3, at: Vector3, color: Color) -> void:
	var shape := BoxMesh.new()
	shape.size = size
	var part := MeshInstance3D.new()
	part.name = label
	part.mesh = shape
	part.material_override = _material(color)
	part.position = at
	frame.add_child(part)


func _wood(label: String, outline: PackedVector2Array, depth: float, at: Vector3) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var indices := Geometry2D.triangulate_polygon(outline)
	for side in [-1.0,1.0]:
		for face in range(0,indices.size(),3):
			for corner in ([0,1,2] if side > 0 else [2,1,0]):
				var p := outline[indices[face+corner]]
				surface.set_uv(Vector2(p.x*2,p.y*4))
				surface.add_vertex(Vector3(p.x,p.y,side*depth*.5))
	for i in outline.size():
		var a := outline[i]
		var b := outline[(i+1)%outline.size()]
		for p in [Vector3(a.x,a.y,-depth*.5),Vector3(b.x,b.y,-depth*.5),Vector3(b.x,b.y,depth*.5),
			Vector3(a.x,a.y,-depth*.5),Vector3(b.x,b.y,depth*.5),Vector3(a.x,a.y,depth*.5)]:
			surface.set_uv(Vector2(p.x*2,p.y*4))
			surface.add_vertex(p)
	surface.generate_normals()
	var part := MeshInstance3D.new()
	part.name = label
	part.position = at
	part.mesh = surface.commit()
	part.material_override = _material(WOOD)
	frame.add_child(part)
