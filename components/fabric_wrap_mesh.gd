extends RefCounted
## Folded cloth wound continuously around a narrow board, including both rounded spines.
const CORNER_STEPS := 8

const BOARD_THICKNESS := 0.016
const BOARD_HEIGHT := 0.84
const BOARD_DEPTH := 0.46
const COVER_WIDTH := 0.74
const BOARD_PERIMETER := 2.0 * (BOARD_THICKNESS + BOARD_DEPTH)
const MAX_WINDING_LAYERS := 24
const MIN_GAUGE_M := 0.00005
const MIN_RADIAL_BUILD := 0.0015
const TRACE_SAMPLES_PER_TURN := 16
const TRACE_HEIGHT := 0.0006
const POOL_BUCKETS := 24

static var _sleeve_pool: Dictionary = {}
static var _end_winding_pool: Dictionary = {}
static var _tail_pool: Dictionary = {}


static func clear_mesh_pools() -> void:
	_sleeve_pool.clear()
	_end_winding_pool.clear()
	_tail_pool.clear()


## A cloth wider than the .74 m cover is folded into more plies, so its radial
## build per wrap scales with folded width / cover width.
static func layer_pitch(thickness_m: float, folded_width: float) -> float:
	var gauge := maxf(thickness_m, MIN_GAUGE_M) if is_finite(thickness_m) else MIN_GAUGE_M
	var width := maxf(folded_width, 0.1) if is_finite(folded_width) else COVER_WIDTH
	return gauge * width / COVER_WIDTH


static func winding_wraps(remaining_m: float) -> float:
	if not is_finite(remaining_m) or remaining_m <= 0.0:
		return 0.0
	return minf(remaining_m / BOARD_PERIMETER, float(MAX_WINDING_LAYERS))


static func winding_layers(remaining_m: float) -> int:
	var wraps := winding_wraps(remaining_m)
	if wraps <= 0.0:
		return 0
	return clampi(int(ceil(wraps)), 1, MAX_WINDING_LAYERS)


## Total wrapped thickness in metres. Every layer is one cloth gauge high and
## the board stays its original .016 m thick; one layer remains at tiny amounts.
static func wrapped_thickness(remaining_m: float, thickness_m: float, folded_width: float) -> float:
	var wraps := winding_wraps(remaining_m)
	if wraps <= 0.0:
		return BOARD_THICKNESS
	var build := maxf(layer_pitch(thickness_m, folded_width) * maxf(wraps, 1.0), MIN_RADIAL_BUILD)
	return BOARD_THICKNESS + 2.0 * build


static func outline(half_x: float, half_z: float, corner_radius: float = -1.0) -> PackedVector2Array:
	var points := PackedVector2Array()
	var radius := half_x*.94 if corner_radius < 0.0 else corner_radius
	radius = clampf(radius, 0.001, minf(half_x, half_z)*.98)
	for corner in 4:
		var center := Vector2((half_x-radius)*(1 if corner in [0,3] else -1),(half_z-radius)*(1 if corner < 2 else -1))
		for step in CORNER_STEPS+1:
			var angle := (corner+float(step)/CORNER_STEPS)*PI*.5
			points.append(center+Vector2(cos(angle),sin(angle))*radius)
	return points


static func sleeve(thickness: float) -> ArrayMesh:
	var wrapped := maxf(thickness, BOARD_THICKNESS)
	var key := snappedi(int(round(wrapped * 5000.0)), 1)
	if _sleeve_pool.has(key):
		return (_sleeve_pool[key] as ArrayMesh).duplicate()
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var build := (wrapped - BOARD_THICKNESS) * 0.5
	var outer_half_z := BOARD_DEPTH * 0.5 + build
	# At small quantities the corner must stay tight to the board instead of
	# pinching inside it; thicker stacks can afford the broad rounded spine.
	var perimeter := outline(wrapped*.5, outer_half_z, minf(wrapped*.5*.94, maxf(.001, build*2.0)))
	var inner := outline(minf(.009, wrapped*.5-.0002), minf(.231, outer_half_z-.0002))
	var distances := PackedFloat32Array([0.0])
	for index in perimeter.size():
		distances.append(distances[-1]+perimeter[index].distance_to(perimeter[(index+1)%perimeter.size()]))
	var levels := [-.37,-.364,.364,.37]
	for layer in 3:
		for index in perimeter.size():
			var next := (index+1)%perimeter.size()
			for vertex in [Vector2i(index,layer),Vector2i(next,layer),Vector2i(next,layer+1),Vector2i(index,layer),Vector2i(next,layer+1),Vector2i(index,layer+1)]:
				var p := perimeter[vertex.x]
				var bevel: bool = vertex.y in [0,3]
				var point := Vector3(p.x*(.97 if bevel else 1.0),levels[vertex.y],p.y*(.993 if bevel else 1.0))
				var before: Vector2 = perimeter[(vertex.x-1+perimeter.size())%perimeter.size()]
				var after: Vector2 = perimeter[(vertex.x+1)%perimeter.size()]
				var tangent := (after-before).normalized()
				var normal := Vector3(tangent.y,(-.5 if vertex.y == 0 else .5) if bevel else 0.0,-tangent.x).normalized()
				var u := distances[index+1] if vertex.x == next else distances[index]
				surface.set_normal(normal)
				surface.set_uv(Vector2(u,levels[vertex.y]+.37))
				surface.add_vertex(point)
	# Annular ends show cloth around the board, without a white longitudinal seam.
	for sign_value in [-1.0,1.0]:
		for index in perimeter.size():
			var next := (index+1)%perimeter.size()
			var outer_a := Vector2(maxf(perimeter[index].x*.97, inner[index].x+.0001), maxf(perimeter[index].y*.993, inner[index].y+.0001))
			var outer_b := Vector2(maxf(perimeter[next].x*.97, inner[next].x+.0001), maxf(perimeter[next].y*.993, inner[next].y+.0001))
			var quad := [outer_a,outer_b,inner[next],inner[index]]
			for corner in [0,1,2,0,2,3]:
				var p: Vector2 = quad[corner]
				surface.set_normal(Vector3.UP*sign_value)
				surface.set_uv(Vector2(p.x,p.y))
				surface.add_vertex(Vector3(p.x,.37*sign_value,p.y))
	var mesh := surface.commit()
	_sleeve_pool[key] = mesh
	return mesh.duplicate()


## One open spiral ribbon per exposed end. The centreline advances by one
## thickness_m-derived layer pitch per turn and is extruded just enough to read
## against the sleeve cap. Both end faces share this bounded, finite geometry.
static func end_winding(thickness: float, layer_pitch_m: float = 0.0, layer_count: int = 0, facing: float = 1.0) -> ArrayMesh:
	var build := maxf((maxf(thickness, BOARD_THICKNESS) - BOARD_THICKNESS) * 0.5, MIN_RADIAL_BUILD)
	var pitch := layer_pitch_m if layer_pitch_m > 0.0 else layer_pitch(0.001, COVER_WIDTH)
	var turns := layer_count
	if turns <= 0:
		turns = clampi(int(ceil(build / maxf(pitch, 0.00001))), 1, MAX_WINDING_LAYERS)
	turns = clampi(turns, 1, MAX_WINDING_LAYERS)
	var face_sign := -1 if facing < 0.0 else 1
	var key := "%d:%d:%d:%d" % [int(round(build * 10000.0)), int(round(pitch * 100000.0)), turns, face_sign]
	if _end_winding_pool.has(key):
		return (_end_winding_pool[key] as ArrayMesh).duplicate()
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	# The inner turn hugs the board and the outer turn hugs the sleeve skin, so
	# tight quantities keep square-ish corners while thick stacks stay rounded.
	var inner := outline(BOARD_THICKNESS*.5+.0005, BOARD_DEPTH*.5+.0005, .0012)
	var outer_half_x := BOARD_THICKNESS*.5+build-.0008
	var outer_half_z := BOARD_DEPTH*.5+build-.0008
	var outer := outline(outer_half_x, outer_half_z, minf(outer_half_x*.94, maxf(.001, build*2.0)))
	var span_x := outer_half_x-(BOARD_THICKNESS*.5+.0005)
	var span_z := outer_half_z-(BOARD_DEPTH*.5+.0005)
	var half_width := clampf(minf(span_x, span_z)/float(turns)*0.28, 0.00022, 0.0007)
	var sample_count := turns*TRACE_SAMPLES_PER_TURN
	var point_count := inner.size()
	var centres := PackedVector2Array()
	for sample in sample_count+1:
		var turn := float(sample)/float(TRACE_SAMPLES_PER_TURN)
		var mix := turn/float(turns)
		# Same corner index on both contours keeps the morph radial instead of
		# letting the long cover edges shear against the tight inner turn.
		var position := fposmod(turn, 1.0)*float(point_count)
		var index := mini(int(floor(position)), point_count-1)
		var local := position-float(index)
		var next := (index+1)%point_count
		var inner_point := inner[index].lerp(inner[next], local)
		var outer_point := outer[index].lerp(outer[next], local)
		centres.append(inner_point.lerp(outer_point, mix))
	var ribbon_normals := PackedVector2Array()
	for index in centres.size():
		var before := centres[maxi(index-1, 0)]
		var after := centres[mini(index+1, centres.size()-1)]
		var tangent := after-before
		tangent = tangent.normalized() if tangent.length_squared() > 0.0000000001 else Vector2.RIGHT
		ribbon_normals.append(Vector2(tangent.y, -tangent.x))
	var top_y := TRACE_HEIGHT*.5*facing
	var bottom_y := -TRACE_HEIGHT*.5*facing
	var top_normal := Vector3.UP*facing
	var bottom_normal := Vector3.DOWN*facing
	for index in sample_count:
		var left_a := centres[index]+ribbon_normals[index]*half_width
		var right_a := centres[index]-ribbon_normals[index]*half_width
		var left_b := centres[index+1]+ribbon_normals[index+1]*half_width
		var right_b := centres[index+1]-ribbon_normals[index+1]*half_width
		_add_quad(surface, left_a, right_a, right_b, left_b, top_y, top_normal)
		_add_quad(surface, left_a, left_b, right_b, right_a, bottom_y, bottom_normal)
	var mesh := surface.commit()
	_end_winding_pool[key] = mesh
	return mesh.duplicate()


static func _add_quad(surface: SurfaceTool, a: Vector2, b: Vector2, c: Vector2, d: Vector2, y: float, normal: Vector3) -> void:
	for point in [a,b,c,a,c,d]:
		surface.set_normal(normal)
		surface.set_uv(point)
		surface.add_vertex(Vector3(point.x, y, point.y))


static func tail(thickness: float, edge_only: bool = false, opening: float = 0.0) -> ArrayMesh:
	var open_bucket := roundi(clampf(opening, 0.0, 1.0) * float(POOL_BUCKETS))
	var quantized_open := float(open_bucket) / float(POOL_BUCKETS)
	var key := "%d:%d:%d" % [int(round(thickness * 5000.0)), 1 if edge_only else 0, open_bucket]
	if _tail_pool.has(key):
		return _tail_pool[key]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Outer cloth tail lies over a broad face, short of the rounded front spine.
	for row in 8:
		for column in 6:
			if edge_only and column < 5: continue
			for corner in [Vector2i(0,0),Vector2i(1,0),Vector2i(1,1),Vector2i(0,0),Vector2i(1,1),Vector2i(0,1)]:
				var y: float = -.363+(row+corner.y)*.726/8.0
				var v: float = (column+corner.x)/6.0
				var z: float = -.15+v*.26
				if edge_only: z = .106+(v-5.0/6.0)*.024
				var lift := .009+.0015*sin(y*25)
				var x := thickness*.5+.0015+pow(v,7)*lift
				if edge_only: x = thickness*.5+.0018+lift
				surface.set_uv(Vector2(z+.15,y+.37))
				var hinge := Vector3(thickness*.5+.0015,y,-.15)
				var bend := Basis(Vector3.UP,quantized_open*PI*.4)
				surface.set_normal(bend*Vector3(1,-pow(v,7)*.0375*cos(y*25),-7*pow(v,6)*lift/.26).normalized())
				surface.add_vertex(hinge+bend*(Vector3(x,y,z)-hinge))
	var mesh := surface.commit()
	_tail_pool[key] = mesh
	return mesh
