@tool
class_name GarmentButtonRow3D
extends Node3D

const Stud = preload("res://components/button_stud.gd")

@export_range(1, 12, 1) var count := 3:
	set(value):
		count = clampi(value, 1, 12)
		_queue_rebuild()
@export_range(0.025, 0.3, 0.005) var spacing := 0.105:
	set(value):
		spacing = clampf(value, 0.025, 0.3)
		_queue_rebuild()
@export var button_size := Vector3(0.036, 0.044, 0.009):
	set(value):
		button_size = value
		_queue_rebuild()
@export var button_material: Material:
	set(value):
		button_material = value
		_queue_rebuild()
@export var mount_surface: NodePath:
	set(value):
		mount_surface = value
		_queue_rebuild()
@export_range(0.0, 0.02, 0.001) var surface_gap := 0.001:
	set(value):
		surface_gap = clampf(value, 0.0, 0.02)
		_queue_rebuild()

var _pending := false


func _ready() -> void:
	rebuild()


func _queue_rebuild() -> void:
	if is_inside_tree() and not _pending:
		_pending = true
		rebuild.call_deferred()


func rebuild() -> void:
	_pending = false
	for child in get_children():
		child.free()
	var surface := get_node_or_null(mount_surface) as MeshInstance3D if not mount_surface.is_empty() else null
	if surface != null and surface.has_signal("geometry_rebuilt") and not surface.is_connected("geometry_rebuilt", _queue_rebuild):
		surface.connect("geometry_rebuilt", _queue_rebuild)
	for i in count:
		var button := Stud.new()
		button.name = "Button%d" % i
		button.width = button_size.x
		button.height = button_size.y
		button.depth = button_size.z
		button.material_override = button_material
		button.position = Vector3(0, -spacing * i, 0)
		add_child(button)
		button.rebuild()
		if surface != null and surface.mesh != null:
			_mount(button, surface)


func _mount(button: MeshInstance3D, surface: MeshInstance3D) -> void:
	var arrays := surface.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	# Mount along the garment's front normal, using its actual generated surface.
	var relative := _to_root(surface).affine_inverse() * _to_root(self)
	var point := relative * button.position
	var closest_z := -INF
	var contact := Vector3.ZERO
	var normal := Vector3.BACK
	for i in range(0, indices.size(), 3):
		var a := vertices[indices[i]]
		var b := vertices[indices[i + 1]]
		var c := vertices[indices[i + 2]]
		var hit = Geometry3D.segment_intersects_triangle(Vector3(point.x, point.y, 1), Vector3(point.x, point.y, -1), a, b, c)
		if hit == null or hit.z <= closest_z:
			continue
		closest_z = hit.z
		contact = hit
		var weights := Geometry3D.get_triangle_barycentric_coords(hit, a, b, c)
		normal = (normals[indices[i]] * weights.x + normals[indices[i + 1]] * weights.y + normals[indices[i + 2]] * weights.z).normalized()
	if closest_z == -INF:
		return
	var up := Vector3.UP
	var right := up.cross(normal).normalized()
	up = normal.cross(right).normalized()
	button.transform = relative.affine_inverse() * Transform3D(Basis(right, up, normal), contact + normal * surface_gap)
	button.set_meta("skin_anchor_local", Vector3(0, 0, -surface_gap))


func _to_root(node: Node3D) -> Transform3D:
	var result := node.transform
	var ancestor := node.get_parent()
	while ancestor != null:
		if ancestor is Node3D:
			result = ancestor.transform * result
		ancestor = ancestor.get_parent()
	return result
