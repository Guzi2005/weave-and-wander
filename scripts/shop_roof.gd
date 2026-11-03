@tool
extends Node3D

const Art = preload("res://scripts/paper_art.gd")
const PAPER = preload("res://shaders/room_paper.gdshader")
const HALF_WIDTH := 7.20
const EAVE := 4.82
const RIDGE := 6.64
const BACK := -3.0
const FRONT := 3.95
const OPEN_ANGLE := 44.0
const OPEN_TIME := .38
const CLOSE_DELAY := .24
const TILE_COLORS := [Color("719193"), Color("759497"), Color("6e8d92"), Color("78989a")]
const TIMBER := Color("728b8b")

var hovered_side := 0
var _halves: Dictionary = {}
var _progress := {-1: 0.0, 1: 0.0}
var _close_wait := {-1: 0.0, 1: 0.0}
var _pinned := {-1: false, 1: false}


func _ready() -> void:
	rebuild()


func rebuild() -> void:
	for child in get_children():
		child.free()
	_halves.clear()
	hovered_side = 0
	_progress = {-1: 0.0, 1: 0.0}
	_close_wait = {-1: 0.0, 1: 0.0}
	_pinned = {-1: false, 1: false}
	var back_gable := Art.flat_shape("RearGable", PackedVector2Array([
		Vector2(-7.2,EAVE), Vector2(0,RIDGE-.14), Vector2(7.2,EAVE)
	]), Color("e6d6cc"), BACK+.35, 0)
	add_child(back_gable)
	var length := Vector2(HALF_WIDTH,RIDGE-EAVE).length()
	for side in [-1,1]:
		var slope := Node3D.new()
		slope.name = "LeftSlope" if side < 0 else "RightSlope"
		slope.position = Vector3(0,RIDGE,0)
		slope.rotation.z = _angle(side,0.0)
		add_child(slope)
		_halves[side] = slope
		var left := -length if side < 0 else 0.0
		var outline := PackedVector2Array([
			Vector2(left,BACK),Vector2(left+length,BACK),
			Vector2(left+length,FRONT),Vector2(left,FRONT)
		])
		_board(slope,outline)
		_tiles(slope,length,side,outline)
		_beam("FrontEdge",Vector3(0,-.035,FRONT),Vector3(side*length,-.035,FRONT),.07,slope)
		_beam("RearEdge",Vector3(0,-.035,BACK),Vector3(side*length,-.035,BACK),.07,slope)
		_beam("Eave",Vector3(side*length,-.035,BACK),Vector3(side*length,-.035,FRONT),.08,slope)
	_beam("RidgeBeam",Vector3(0,RIDGE-.03,BACK),Vector3(0,RIDGE-.03,FRONT),.09)
	for index in 20:
		var cap := Art.cylinder("RidgeTile",.09,.35,Color("829b9b"),Vector3(0,RIDGE+.045,BACK+.17+index*.347),8)
		cap.rotation_degrees.x = 90
		cap.material_override = _material(Color("829b9b"))
		add_child(cap)
	_chimney()
	get_node("Chimney").reparent(_halves[1],true)
	# Keep the illustrative room lighting stable while the paper lids move.
	for instance in find_children("*","GeometryInstance3D",true,false):
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _material(color: Color) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = PAPER
	mat.set_shader_parameter("pigment",color)
	return mat


func _beam(label: String, from: Vector3, to: Vector3, width: float, parent: Node = self) -> void:
	var node := Art.box(label,Vector3(width,from.distance_to(to),width),TIMBER,(from+to)*.5)
	node.quaternion = Quaternion(Vector3.UP,(to-from).normalized())
	node.material_override = _material(TIMBER)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)


func add_lamp_support(at: Vector3) -> void:
	var side := -1 if at.x < 0 else 1
	_beam("FixedLampRafter",Vector3(0,RIDGE-.10,at.z),Vector3(side*HALF_WIDTH,EAVE-.10,at.z),.08)


func _angle(side: int, amount: float) -> float:
	return -side*atan2(RIDGE-EAVE,HALF_WIDTH) + side*deg_to_rad(OPEN_ANGLE)*smoothstep(0.0,1.0,amount)


func animate_lids(delta: float, requested_side: int) -> void:
	hovered_side = requested_side
	for side in [-1,1]:
		var wants_open: bool = side == requested_side or _pinned[side]
		if wants_open:
			_close_wait[side] = CLOSE_DELAY
		else:
			_close_wait[side] = maxf(0.0,_close_wait[side]-delta)
		var target := 1.0 if wants_open or _close_wait[side] > 0.0 else 0.0
		_progress[side] = move_toward(_progress[side],target,delta/OPEN_TIME)
		_halves[side].rotation.z = _angle(side,_progress[side])


func toggle_touch(side: int) -> void:
	_pinned[side] = not _pinned[side]


func clear_touch() -> void:
	_pinned = {-1: false, 1: false}


func open_amount(side: int) -> float:
	return _progress[side]


func corners(side: int, amount: float = -1.0) -> PackedVector3Array:
	var length := Vector2(HALF_WIDTH,RIDGE-EAVE).length()
	var transform: Transform3D = _halves[side].global_transform
	if amount >= 0:
		transform = global_transform * Transform3D(Basis(Vector3.BACK,_angle(side,amount)),Vector3(0,RIDGE,0))
	var result := PackedVector3Array()
	for point in [Vector3(0,0,BACK),Vector3(side*length,0,BACK),Vector3(side*length,0,FRONT),Vector3(0,0,FRONT)]:
		result.append(transform*point)
	return result


func hit_test(camera: Camera3D, screen: Vector2) -> Dictionary:
	var origin := camera.project_ray_origin(screen)
	var direction := camera.project_ray_normal(screen)
	var result := {"side":0,"distance":INF}
	for side in [-1,1]:
		var points := corners(side)
		for triangle in [[0,1,2],[0,2,3]]:
			var hit = Geometry3D.ray_intersects_triangle(origin,direction,points[triangle[0]],points[triangle[1]],points[triangle[2]])
			if hit != null and origin.distance_to(hit) < result["distance"]:
				result = {"side":side,"distance":origin.distance_to(hit)}
	return result


func holds_pointer(camera: Camera3D, screen: Vector2, side: int) -> bool:
	# Keep the original footprint and the space below it active as the lid rises.
	var points := PackedVector2Array()
	for point in corners(side,0.0) + corners(side):
		points.append(camera.unproject_position(point))
	for x in [0.0,side*HALF_WIDTH]:
		for z in [BACK,FRONT]:
			points.append(camera.unproject_position(to_global(Vector3(x,0,z))))
	return Geometry2D.is_point_in_polygon(screen,Geometry2D.convex_hull(points))


func framing_points() -> PackedVector3Array:
	var result := PackedVector3Array()
	for side in [-1,1]:
		for amount in [0.0,1.0]:
			for node in _halves[side].find_children("*","MeshInstance3D",true,false):
				var relative: Transform3D = _halves[side].global_transform.affine_inverse()*node.global_transform
				var transform := global_transform * Transform3D(Basis(Vector3.BACK,_angle(side,amount)),Vector3(0,RIDGE,0)) * relative
				for i in 8:
					result.append(transform*node.mesh.get_aabb().get_endpoint(i))
	return result


func _board(slope: Node3D, outline: PackedVector2Array) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var indices := Geometry2D.triangulate_polygon(outline)
	for y in [-.035,.035]:
		for index in indices:
			var point := outline[index]
			surface.set_normal(Vector3.UP if y > 0 else Vector3.DOWN)
			surface.set_uv(point*.2)
			surface.add_vertex(Vector3(point.x,y,point.y))
	for i in outline.size():
		var a := outline[i]
		var b := outline[(i+1)%outline.size()]
		var corners := [Vector3(a.x,-.035,a.y),Vector3(b.x,-.035,b.y),Vector3(b.x,.035,b.y),Vector3(a.x,.035,a.y)]
		for index in [0,1,2,0,2,3]:
			surface.set_normal(Vector3(b.y-a.y,0,a.x-b.x).normalized())
			surface.set_uv(Vector2.ZERO)
			surface.add_vertex(corners[index])
	var node := MeshInstance3D.new()
	node.name = "RoofBoard"
	node.mesh = surface.commit()
	node.material_override = _material(Color("779294"))
	slope.add_child(node)


func _tiles(slope: Node3D, length: float, side: int, outline: PackedVector2Array) -> void:
	# Four batched meshes share tile colors; the stepped edges are real geometry.
	for color_index in TILE_COLORS.size():
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for row in 16:
			var center := (-length if side < 0 else 0.0) + (row+.5)*length/16.0
			for column in 17:
				if (row*7+column*3)%4 != color_index:
					continue
				var low := BACK + column*.425 - (row%2)*.2125
				var high := low+.422
				if high <= low:
					continue
				var left := center-length/32.0
				var right := center+length/32.0
				var tile := PackedVector2Array([Vector2(left,low),Vector2(right,low),Vector2(right,high),Vector2(left,high)])
				for clipped in Geometry2D.intersect_polygons(tile,outline):
					for index in Geometry2D.triangulate_polygon(clipped):
						var point: Vector2 = clipped[index]
						var depth := inverse_lerp(left,right,point.x)
						surface.set_normal(Vector3.UP)
						surface.set_uv(Vector2(depth,inverse_lerp(low,high,point.y)))
						surface.add_vertex(Vector3(point.x,.043+.015*(depth if side > 0 else 1.0-depth),point.y))
		var mesh := MeshInstance3D.new()
		mesh.name = "SlateTiles%d"%color_index
		mesh.mesh = surface.commit()
		mesh.material_override = _material(TILE_COLORS[color_index])
		slope.add_child(mesh)


func _chimney() -> void:
	var chimney := Node3D.new()
	chimney.name = "Chimney"
	chimney.position = Vector3(4.65,5.45,-1.80)
	add_child(chimney)
	for row in 5:
		var brick := Art.box("BrickCourse",Vector3(.63,.18,.64),Color("ad8084") if row%2 else Color("bc9492"),Vector3(0,row*.19,0))
		brick.material_override = _material(Color("ad8084") if row%2 else Color("bc9492"))
		chimney.add_child(brick)
	var cap := Art.box("Cap",Vector3(.85,.13,.84),TIMBER,Vector3(0,.91,0))
	cap.material_override = _material(TIMBER)
	chimney.add_child(cap)
