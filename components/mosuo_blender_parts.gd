extends RefCounted

## Mesh handoff from the editable Blender source. The shared game rig supplies skinning.
const PATH := "res://assets/collections/mosuo_photo_001/blender_geometry.json"
static var _parts: Array[Dictionary] = []
const MATERIALS := {
	"braid":["18151d",.36,0.0], "red":["e92e44",.24,.08],
	"yellow":["e3c433",.36,0.0], "green":["659442",.4,0.0],
	"blue":["2563a9",.38,0.0], "purple":["873db4",.32,0.0],
	"pink":["ee334c",.4,0.0], "pinklight":["ff6870",.43,0.0],
	"ivory":["f0e2c7",.43,0.0], "piping":["be1b35",.32,0.0],
	"stripe":["a62652",.39,0.0], "sash":["714152",.48,0.0],
	"sashthread":["bd8994",.46,0.0], "insole":["a5a49a",.9,0.0],
	"insoleedge":["bf3871",.55,0.0]
}

static func parts(slot: String) -> Array[Dictionary]:
	if _parts.is_empty():
		var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		assert(document.get("schema") == "ww-blender-costume-geometry-v1")
		for record: Dictionary in document.parts:
			var data := {"name":record.name,"slot":record.slot,"material":record.material,
				"vertices":PackedVector3Array(),"normals":PackedVector3Array(),
				"indices":PackedInt32Array(record.indices),"arm_weights":PackedFloat32Array(record.arm_weights)}
			for v: Array in record.vertices: data.vertices.append(Vector3(v[0],v[1],v[2]))
			for n: Array in record.normals: data.normals.append(Vector3(n[0],n[1],n[2]))
			if not record.uv.is_empty():
				data["uv"] = PackedVector2Array()
				for uv: Array in record.uv: data.uv.append(Vector2(uv[0],uv[1]))
			_parts.append(data)
	var selected: Array[Dictionary] = []
	for part in _parts:
		if part.slot == slot: selected.append(part)
	return selected

static func material(key: String) -> StandardMaterial3D:
	var values: Array = MATERIALS[key]
	var mat := StandardMaterial3D.new()
	mat.resource_name = "Photo001 / Blender / " + key
	mat.albedo_color = Color(values[0])
	mat.roughness = values[1]
	mat.metallic = values[2]
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if key == "braid":
		mat.anisotropy_enabled = true
		mat.anisotropy = .65
	return mat
