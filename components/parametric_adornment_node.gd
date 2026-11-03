@tool
extends MeshInstance3D
## Editor-facing procedural node. The Resource is the shared game recipe; Path3D
## exposes its Curve3D handles in the 3D editor. Rebuilds are debounced for beads.
@export var recipe: Resource
@export_node_path("Path3D") var path_node: NodePath
@export var geometry_origin := Vector3.ZERO
var _signature := ""
var _elapsed := 0.0

func _ready() -> void:
	rebuild()
	set_process(Engine.is_editor_hint())

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < .4: return
	_elapsed = 0.0
	if _recipe_signature() != _signature: rebuild()

func _recipe_signature() -> String:
	if recipe == null: return ""
	var values: Array = [geometry_origin]
	for property in recipe.get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			var value: Variant = recipe.get(property.name)
			if value is Curve3D:
				values.append(value.get_baked_points())
			else: values.append(value)
	var route := get_node_or_null(path_node) as Path3D if not path_node.is_empty() else null
	if route != null and route.curve != null: values.append(route.curve.get_baked_points())
	return var_to_str(values)

func rebuild() -> void:
	if recipe == null or not recipe.has_method("build_geometry"): return
	var route := get_node_or_null(path_node) as Path3D if not path_node.is_empty() else null
	if route != null: recipe.path = route.curve
	var groups: Array = recipe.build_geometry_groups() if recipe.has_method("build_geometry_groups") else [recipe.build_geometry()]
	var result := ArrayMesh.new()
	for group: Dictionary in groups:
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		var vertices: PackedVector3Array = group.vertices.duplicate()
		for i in vertices.size(): vertices[i] -= geometry_origin
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = group.normals
		arrays[Mesh.ARRAY_INDEX] = group.indices
		if group.has("colors"): arrays[Mesh.ARRAY_COLOR] = group.colors
		if group.has("uv"): arrays[Mesh.ARRAY_TEX_UV] = group.uv
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		result.surface_set_material(result.get_surface_count()-1,recipe.material_for(group.material_preset) if group.has("material_preset") else recipe.material())
	mesh = result
	_signature = _recipe_signature()
