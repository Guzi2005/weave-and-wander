extends Node3D

const PAPER = preload("res://shaders/room_paper.gdshader")
static var _mesh_cache: Dictionary = {}
var _wound_thread_part: MeshInstance3D = null
var _thread_core_part: MeshInstance3D = null
var fullness := 1.0


func build(radius: float, height: float, color: Color) -> void:
	var quantized_r := snappedf(radius, 0.001)
	var quantized_h := snappedf(height, 0.002)
	var key := Vector2(quantized_r, quantized_h)
	if not _mesh_cache.has(key):
		var turns := clampi(roundi(quantized_h / .002), 128, 220)
		var strand := minf(quantized_r * .010, quantized_h * .0035)
		var yarn := _cross_winding(quantized_r, quantized_h, turns, strand)
		var section := PackedVector2Array([
			Vector2(quantized_r*.25,-quantized_h*.5-.012),Vector2(quantized_r*1.13,-quantized_h*.5-.012),
			Vector2(quantized_r*1.19,-quantized_h*.5),Vector2(quantized_r*1.13,-quantized_h*.5+.012),
			Vector2(quantized_r*.33,-quantized_h*.5+.012),Vector2(quantized_r*.33,quantized_h*.5-.012),
			Vector2(quantized_r*1.13,quantized_h*.5-.012),Vector2(quantized_r*1.19,quantized_h*.5),
			Vector2(quantized_r*1.13,quantized_h*.5+.012),Vector2(quantized_r*.25,quantized_h*.5+.012)])
		var bobbin := SurfaceTool.new()
		bobbin.begin(Mesh.PRIMITIVE_TRIANGLES)
		for row in section.size():
			for side in 32:
				for corner in [Vector2i(0,0),Vector2i(1,0),Vector2i(1,1),Vector2i(0,0),Vector2i(1,1),Vector2i(0,1)]:
					var p := section[(row+corner.y)%section.size()]
					var angle := float(side+corner.x)/32.0*TAU
					bobbin.add_vertex(Vector3(cos(angle)*p.x,p.y,sin(angle)*p.x))
		bobbin.generate_normals()
		var underlay := CylinderMesh.new()
		underlay.top_radius = quantized_r-strand*2.5
		underlay.bottom_radius = underlay.top_radius
		underlay.height = quantized_h*.94
		underlay.radial_segments = 32
		_mesh_cache[key] = [yarn,bobbin.commit(),underlay,turns]
	var meshes: Array = _mesh_cache[key]
	for index in 3:
		var part := MeshInstance3D.new()
		part.name = ["ContinuousWoundThread","HollowBobbin","ThreadCore"][index]
		part.mesh = meshes[index]
		var material := ShaderMaterial.new()
		material.shader = preload("res://shaders/wound_thread.gdshader") if index == 0 else PAPER
		if index == 0:
			part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_wound_thread_part = part
		elif index == 2:
			_thread_core_part = part
		material.set_shader_parameter("pigment",Color("e5dfc9") if index == 1 else color)
		part.material_override = material
		add_child(part)
	set_meta("thread_turns",meshes[3])
	set_meta("hollow_core",true)
	set_meta("winding_angle_degrees",14.0)
	set_meta("winding_pattern","reciprocating_cross_wound")


## Continuous thread consumption uses radial X/Z transform scaling on the wound
## thread and underlay rather than rebuilding the cross-wound ArrayMesh.
func set_fullness(fraction: float) -> void:
	fullness = clampf(fraction, 0.0, 1.0)
	var radial := lerpf(0.34, 1.0, sqrt(fullness))
	if is_instance_valid(_wound_thread_part):
		_wound_thread_part.visible = fullness > 0.001
		_wound_thread_part.scale = Vector3(radial, 1.0, radial)
	if is_instance_valid(_thread_core_part):
		_thread_core_part.visible = fullness > 0.001
		_thread_core_part.scale = Vector3(radial, 1.0, radial)


static func _winding_point(angle: float, radius: float, height: float, turns: int) -> Vector3:
	# The guide travels back and forth while the bobbin keeps rotating in one direction.
	var span := height * .89
	var guide := angle * radius * tan(deg_to_rad(14.0)) / span
	var phase := fposmod(guide, 2.0)
	var travel := phase if phase <= 1.0 else 2.0-phase
	# Round only the turnaround, leaving a constant diagonal pitch across the body.
	var edge := .045
	if travel < edge:
		travel = (travel*travel/edge + edge)*.5
	elif travel > 1.0-edge:
		travel = 1.0-((1.0-travel)*(1.0-travel)/edge+edge)*.5
	var layer := angle / (turns * TAU)
	var shell := radius * (1.0 - .014 * pow(absf(travel*2.0-1.0), 8)) + (layer-.5)*radius*.018
	return Vector3(cos(angle)*shell, (travel-.5)*span, sin(angle)*shell)


static func _cross_winding(radius: float, height: float, turns: int, strand: float) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var steps := turns * 48
	const SIDES := 5
	for step in steps+1:
		var angle := TAU * turns * float(step) / steps
		var point := _winding_point(angle,radius,height,turns)
		var tangent := (_winding_point(angle+.002,radius,height,turns)-_winding_point(angle-.002,radius,height,turns)).normalized()
		var outward := Vector3(cos(angle),0,sin(angle))
		var across := tangent.cross(outward).normalized()
		outward = across.cross(tangent).normalized()
		for side in SIDES:
			var cross_angle := TAU * side / SIDES
			var normal := outward*cos(cross_angle) + across*sin(cross_angle)
			vertices.append(point + normal*strand)
			normals.append(normal)
		if step == steps:
			continue
		for side in SIDES:
			var a := step*SIDES+side
			var b := step*SIDES+(side+1)%SIDES
			indices.append_array(PackedInt32Array([a,b,a+SIDES,b,b+SIDES,a+SIDES]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh
