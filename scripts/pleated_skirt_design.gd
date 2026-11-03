@tool
class_name PleatedSkirtDesign
extends RefCounted

## Versioned importer/exporter for Docs/PLEATED_SKIRT_CONTRACT.md v1.
##
## Every entry point validates the complete document before returning a design.
## Unknown fields are rejected rather than silently discarded, and all arrays,
## strings and point counts have hard limits so malformed input cannot trigger
## unbounded allocation.

const SCHEMA := "weave-pleated-skirt"
const VERSION := 1

const TEMPLATE_IDS := ["plain", "mosuo_reference", "yi_reference", "wax_reference"]
const CANVAS_VIEWS := ["front", "sector", "ring"]
const FABRICS := ["cotton", "linen", "silk", "wool"]
const PATTERNS := ["solid", "dash", "diamond", "wax"]

const SHAPE_RANGES := {
	"relaxed": {"fullness": [0.0, 1.0], "taper": [0.0, 1.0]},
	"a_line": {"flare": [0.0, 1.0], "curve": [0.0, 1.0]},
	"bell": {"volume": [0.0, 1.0], "peak": [0.2, 0.85]},
	"trumpet": {"fit": [0.0, 1.0], "flare_start": [0.2, 0.85], "flare": [0.0, 1.0]},
}

const MAX_REFERENCES := 32
const MAX_BANDS := 32
const MAX_PATCHES := 64
const MAX_STROKES := 256
const MAX_TOTAL_POINTS := 40000
const MAX_FILE_BYTES := 4 * 1024 * 1024
const MAX_ID_LENGTH := 128
const MAX_NOTE_LENGTH := 4000
const MAX_TITLE_LENGTH := 512
const MAX_PATH_LENGTH := 2048

const TOP_LEVEL_KEYS := [
	"schema", "version", "design_id", "item_id", "component_id", "collection_id",
	"template_id", "canvas_view", "source", "parameters", "bands", "patches",
	"strokes", "pattern_uv",
]
const PARAMETER_KEYS := [
	"length_cm", "waist_cm", "hem_cm", "pleat_count", "pleat_depth_cm",
	"sharpness", "thickness_mm", "fabric", "base_color",
]
const SOURCE_KEYS := ["note", "references"]
const REFERENCE_KEYS := ["title", "path"]
const BAND_KEYS := ["id", "start", "end", "color", "pattern", "repeat"]
const PATCH_KEYS := ["id", "u0", "u1", "v0", "v1", "color", "pattern", "repeat"]
const STROKE_KEYS := ["id", "color", "width", "points"]
const PATTERN_UV_KEYS := ["origin", "seam", "u", "v"]
const HEX_DIGITS := "0123456789abcdefABCDEF"


static func validate_design(value: Variant) -> String:
	var result := inspect_design(value)
	if result["ok"]:
		return ""
	return String(result["error"])


static func inspect_design(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return _failure(ERR_INVALID_DATA, "Design must be a JSON object/dictionary.")
	var data: Dictionary = value
	var allowed_keys := TOP_LEVEL_KEYS.duplicate()
	if data.has("drape"):
		allowed_keys.append("drape")
	if data.has("silhouette"):
		allowed_keys.append("silhouette")
	if data.has("shape"):
		allowed_keys.append("shape")
	var key_error := _check_object_keys(data, allowed_keys, "design")
	if not key_error.is_empty():
		return _failure(ERR_INVALID_DATA, key_error)

	if typeof(data["schema"]) != TYPE_STRING or String(data["schema"]) != SCHEMA:
		return _failure(ERR_INVALID_DATA, "schema must be exactly \"%s\"." % SCHEMA)
	if not _is_integer(data["version"]) or int(data["version"]) != VERSION:
		return _failure(ERR_INVALID_DATA, "version must be the integer %d." % VERSION)

	var design_id_result := _read_string(data["design_id"], "design_id", MAX_ID_LENGTH, false)
	if not design_id_result["ok"]:
		return _failure(ERR_INVALID_DATA, design_id_result["error"])
	var item_id_result := _read_string(data["item_id"], "item_id", MAX_ID_LENGTH, false)
	if not item_id_result["ok"]:
		return _failure(ERR_INVALID_DATA, item_id_result["error"])
	var component_id_result := _read_string(data["component_id"], "component_id", MAX_ID_LENGTH, false)
	if not component_id_result["ok"]:
		return _failure(ERR_INVALID_DATA, component_id_result["error"])
	var collection_id_result := _read_string(data["collection_id"], "collection_id", MAX_ID_LENGTH, false)
	if not collection_id_result["ok"]:
		return _failure(ERR_INVALID_DATA, collection_id_result["error"])

	if typeof(data["template_id"]) != TYPE_STRING or not TEMPLATE_IDS.has(String(data["template_id"])):
		return _failure(ERR_INVALID_DATA, "template_id must be one of %s." % str(TEMPLATE_IDS))
	if typeof(data["canvas_view"]) != TYPE_STRING or not CANVAS_VIEWS.has(String(data["canvas_view"])):
		return _failure(ERR_INVALID_DATA, "canvas_view must be one of %s." % str(CANVAS_VIEWS))

	var source := _validate_source(data["source"])
	if not source["ok"]:
		return _failure(ERR_INVALID_DATA, source["error"])

	var parameters := _validate_parameters(data["parameters"])
	if not parameters["ok"]:
		return _failure(ERR_INVALID_DATA, parameters["error"])

	var bands := _validate_bands(data["bands"])
	if not bands["ok"]:
		return _failure(ERR_INVALID_DATA, bands["error"])
	var patches := _validate_patches(data["patches"])
	if not patches["ok"]:
		return _failure(ERR_INVALID_DATA, patches["error"])
	var strokes := _validate_strokes(data["strokes"])
	if not strokes["ok"]:
		return _failure(ERR_INVALID_DATA, strokes["error"])
	var decoration_ids := {}
	for collection in [bands["value"], patches["value"], strokes["value"]]:
		for entry in collection:
			if decoration_ids.has(entry["id"]):
				return _failure(ERR_INVALID_DATA, "Decoration IDs must be unique across bands, patches and strokes.")
			decoration_ids[entry["id"]] = true

	var pattern_uv := _validate_pattern_uv(data["pattern_uv"])
	if not pattern_uv["ok"]:
		return _failure(ERR_INVALID_DATA, pattern_uv["error"])

	var normalized := {
		"schema": SCHEMA,
		"version": VERSION,
		"design_id": String(design_id_result["value"]),
		"item_id": String(item_id_result["value"]),
		"component_id": String(component_id_result["value"]),
		"collection_id": String(collection_id_result["value"]),
		"template_id": String(data["template_id"]),
		"canvas_view": String(data["canvas_view"]),
		"source": source["value"],
		"parameters": parameters["value"],
		"bands": bands["value"],
		"patches": patches["value"],
		"strokes": strokes["value"],
		"pattern_uv": pattern_uv["value"],
	}
	if data.has("silhouette"):
		if not ["relaxed", "a_line", "bell", "trumpet"].has(data["silhouette"]):
			return _failure(ERR_INVALID_DATA, "Invalid silhouette")
		normalized["silhouette"] = data["silhouette"]
	if data.has("shape"):
		var shape_result := _validate_shape(data["shape"])
		if not shape_result["ok"]:
			return shape_result
		normalized["shape"] = shape_result["value"]
	if data.has("drape"):
		var settings: Variant = data["drape"]
		var drape_error := _check_object_keys(settings, ["mode", "weight", "bending", "opening"], "drape")
		if not drape_error.is_empty():
			return _failure(ERR_INVALID_DATA, drape_error)
		if settings["mode"] not in ["auto", "manual"]:
			return _failure(ERR_INVALID_DATA, "Invalid drape mode")
		var drape := {"mode": settings["mode"]}
		for field in ["weight", "bending", "opening"]:
			var number := _read_number(settings[field], "drape." + field, 0.0, 1.0)
			if not number["ok"]:
				return _failure(ERR_INVALID_DATA, number["error"])
			drape[field] = number["value"]
		normalized["drape"] = drape
	return {"ok": true, "code": OK, "error": "", "design": normalized}


static func _validate_shape(value: Variant) -> Dictionary:
	var shape_error := _check_object_keys(value, ["relaxed", "a_line", "bell", "trumpet", "hem"], "shape")
	if not shape_error.is_empty():
		return _failure(ERR_INVALID_DATA, shape_error)
	var normalized := {}
	for profile in SHAPE_RANGES:
		var fields: Dictionary = SHAPE_RANGES[profile]
		shape_error = _check_object_keys(value[profile], fields.keys(), "shape." + profile)
		if not shape_error.is_empty():
			return _failure(ERR_INVALID_DATA, shape_error)
		var values := {}
		for field in fields:
			var bounds: Array = fields[field]
			var number := _read_number(value[profile][field], "shape." + profile + "." + field, bounds[0], bounds[1])
			if not number["ok"]:
				return _failure(ERR_INVALID_DATA, number["error"])
			values[field] = number["value"]
		normalized[profile] = values
	var hem_fields := ["mode", "ratio"]
	if typeof(value["hem"]) == TYPE_DICTIONARY and value["hem"].has("angle_deg"):
		hem_fields.append("angle_deg")
	shape_error = _check_object_keys(value["hem"], hem_fields, "shape.hem")
	if not shape_error.is_empty():
		return _failure(ERR_INVALID_DATA, shape_error)
	if value["hem"]["mode"] not in ["body", "circle", "wide", "deep", "custom"]:
		return _failure(ERR_INVALID_DATA, "Invalid hem shape mode")
	var ratio := _read_number(value["hem"]["ratio"], "shape.hem.ratio", 0.35, 1.0)
	if not ratio["ok"]:
		return _failure(ERR_INVALID_DATA, ratio["error"])
	normalized["hem"] = {"mode": value["hem"]["mode"], "ratio": ratio["value"]}
	if value["hem"].has("angle_deg"):
		var angle := _read_number(value["hem"]["angle_deg"], "shape.hem.angle_deg", 0.0, 180.0)
		if not angle["ok"]:
			return _failure(ERR_INVALID_DATA, angle["error"])
		normalized["hem"]["angle_deg"] = angle["value"]
	return {"ok": true, "value": normalized}


static func inspect_json_text(text: String) -> Dictionary:
	var json := JSON.new()
	var parse_error := json.parse(text)
	if parse_error != OK:
		return _failure(ERR_PARSE_ERROR, "Malformed JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()])
	return inspect_design(json.data)


static func load_design_file(path: String) -> Dictionary:
	if path.strip_edges().is_empty():
		return _failure(ERR_INVALID_PARAMETER, "Design path is empty.")
	if not FileAccess.file_exists(path):
		return _failure(ERR_FILE_NOT_FOUND, "Design file does not exist: %s" % path)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure(FileAccess.get_open_error(), "Cannot read design file: %s" % path)
	var byte_count := file.get_length()
	if byte_count > MAX_FILE_BYTES:
		file.close()
		return _failure(ERR_FILE_CANT_READ, "Design file is larger than %d bytes." % MAX_FILE_BYTES)
	var text := file.get_as_text()
	file.close()
	if text.length() > MAX_FILE_BYTES:
		return _failure(ERR_FILE_CANT_READ, "Design file text is larger than %d bytes." % MAX_FILE_BYTES)
	var result := inspect_json_text(text)
	if not result["ok"]:
		return result
	var sibling := path.get_basename() + ".png"
	result["texture_path"] = sibling if FileAccess.file_exists(sibling) else ""
	return result


static func encode_design(value: Dictionary) -> Dictionary:
	var inspected := inspect_design(value)
	if not inspected["ok"]:
		return inspected
	var text := JSON.stringify(inspected["design"], "  ", false, true)
	return {"ok": true, "code": OK, "error": "", "design": inspected["design"], "text": text}


static func save_design_file(path: String, value: Dictionary) -> Dictionary:
	if path.strip_edges().is_empty():
		return _failure(ERR_INVALID_PARAMETER, "Design path is empty.")
	var encoded := encode_design(value)
	if not encoded["ok"]:
		return encoded
	var directory := path.get_base_dir()
	if not directory.is_empty():
		var directory_path := directory
		if directory.begins_with("res://") or directory.begins_with("user://"):
			directory_path = ProjectSettings.globalize_path(directory)
		var directory_error := DirAccess.make_dir_recursive_absolute(directory_path)
		if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
			return _failure(directory_error, "Cannot create design directory: %s" % directory)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return _failure(FileAccess.get_open_error(), "Cannot write design file: %s" % path)
	file.store_string(String(encoded["text"]))
	file.close()
	return {"ok": true, "code": OK, "error": "", "design": encoded["design"], "path": path}


static func default_design(template_id: String = "plain") -> Dictionary:
	var resolved := template_id if TEMPLATE_IDS.has(template_id) else "plain"
	var parameters := {"length_cm": 88.0, "waist_cm": 68.0, "hem_cm": 230.0,
		"pleat_count": 64, "pleat_depth_cm": 1.4, "sharpness": 0.82,
		"thickness_mm": 0.7, "fabric": "cotton", "base_color": "#ede8db"}
	var bands: Array = []
	var references: Array = []
	match resolved:
		"mosuo_reference":
			bands = [_band("mosuo_trim", 0.79, 0.80, "#c74674", "solid", 32)]
			references = [{"title": "当代摩梭母女-1 — 摄影者朱晓安", "path": "D:/Eagle库/纯纯素材仓库.library/images/MVL2PCZVKPFCJ.info/当代摩梭母女-1 - 摄影者朱晓安.jpg"}]
		"yi_reference":
			parameters.merge({"base_color": "#202135", "hem_cm": 290.0, "pleat_count": 96, "sharpness": 0.96}, true)
			bands = [_band("yi_purple", 0.42, 0.72, "#765178", "solid", 32),
				_band("yi_cyan", 0.72, 0.745, "#34b6cc", "solid", 32),
				_band("yi_white", 0.75, 0.76, "#e6ddd5", "solid", 32),
				_band("yi_pink", 0.77, 0.78, "#d84b69", "solid", 32),
				_band("yi_stitches", 0.785, 0.81, "#e9ded4", "dash", 48)]
			references = [{"title": "收到了越西老板寄来的彝族裙子 — baby blue", "path": "D:/Eagle库/纯纯素材仓库.library/images/MVL2IMSGPE1ZL.info/收到了越西老板寄来的彝族裙子 - baby blue.jpg"}]
		"wax_reference":
			parameters.merge({"base_color": "#e3dfcc", "hem_cm": 280.0, "pleat_count": 96, "sharpness": 0.7, "fabric": "linen"}, true)
			bands = [_band("wax_upper", 0.56, 0.61, "#293b43", "solid", 32),
				_band("wax_geometry", 0.64, 0.76, "#283d48", "wax", 32),
				_band("wax_line", 0.80, 0.82, "#263d45", "solid", 32),
				_band("wax_hem", 0.88, 0.94, "#273b43", "diamond", 40)]
			references = [{"title": "用户提供的手工蜡染裙参考图", "path": "user-reference:codex-clipboard-b560de74-fa8d-40a8-8261-94da1e678c64.png"}]
	return {
		"schema": SCHEMA, "version": VERSION,
		"design_id": "design_%s_v1" % resolved,
		"item_id": "item_%s_pleated_skirt" % resolved,
		"component_id": "component_pleated_skirt_%s" % resolved,
		"collection_id": "pleated-skirt-study", "template_id": resolved, "canvas_view": "sector",
		"source": {"note": "依据用户提供的服饰照片建立的可编辑设计起点；具体地域与工艺以来源为准。", "references": references},
		"parameters": parameters, "bands": bands, "patches": [], "strokes": [],
		"pattern_uv": {"origin": "waist", "seam": "back", "u": "circumference", "v": "waist_to_hem"},
	}

static func _band(id: String, start: float, end: float, color: String, pattern: String, repeat_count: int) -> Dictionary:
	return {"id": id, "start": start, "end": end, "color": color, "pattern": pattern, "repeat": repeat_count}


static func _patch(id: String, u0: float, u1: float, v0: float, v1: float, color: String, pattern: String, repeat_count: int) -> Dictionary:
	return {"id": id, "u0": u0, "u1": u1, "v0": v0, "v1": v1, "color": color, "pattern": pattern, "repeat": repeat_count}


static func _stroke(id: String, color: String, width: float, points: Array) -> Dictionary:
	return {"id": id, "color": color, "width": width, "points": points}


static func _validate_source(value: Variant) -> Dictionary:
	var key_error := _check_object_keys(value, SOURCE_KEYS, "source")
	if not key_error.is_empty():
		return _failure(ERR_INVALID_DATA, key_error)
	var source: Dictionary = value
	var note_result := _read_string(source["note"], "source.note", MAX_NOTE_LENGTH, true)
	if not note_result["ok"]:
		return _failure(ERR_INVALID_DATA, note_result["error"])
	if typeof(source["references"]) != TYPE_ARRAY:
		return _failure(ERR_INVALID_DATA, "source.references must be an array.")
	var references: Array = source["references"]
	if references.size() > MAX_REFERENCES:
		return _failure(ERR_INVALID_DATA, "source.references exceeds %d entries." % MAX_REFERENCES)
	var output: Array = []
	for index in references.size():
		var reference = references[index]
		var reference_error := _check_object_keys(reference, REFERENCE_KEYS, "source.references[%d]" % index)
		if not reference_error.is_empty():
			return _failure(ERR_INVALID_DATA, reference_error)
		var reference_dictionary: Dictionary = reference
		var title_result := _read_string(reference_dictionary["title"], "source.references[%d].title" % index, MAX_TITLE_LENGTH, false)
		if not title_result["ok"]:
			return _failure(ERR_INVALID_DATA, title_result["error"])
		var path_result := _read_string(reference_dictionary["path"], "source.references[%d].path" % index, MAX_PATH_LENGTH, false)
		if not path_result["ok"]:
			return _failure(ERR_INVALID_DATA, path_result["error"])
		output.append({"title": String(title_result["value"]), "path": String(path_result["value"])})
	return {"ok": true, "value": {"note": String(note_result["value"]), "references": output}}


static func _validate_parameters(value: Variant) -> Dictionary:
	var key_error := _check_object_keys(value, PARAMETER_KEYS, "parameters")
	if not key_error.is_empty():
		return _failure(ERR_INVALID_DATA, key_error)
	var parameters: Dictionary = value

	var length_result := _read_number(parameters["length_cm"], "parameters.length_cm", 40.0, 120.0)
	if not length_result["ok"]:
		return _failure(ERR_INVALID_DATA, length_result["error"])
	var waist_result := _read_number(parameters["waist_cm"], "parameters.waist_cm", 50.0, 110.0)
	if not waist_result["ok"]:
		return _failure(ERR_INVALID_DATA, waist_result["error"])
	var hem_result := _read_number(parameters["hem_cm"], "parameters.hem_cm", 100.0, 360.0)
	if not hem_result["ok"]:
		return _failure(ERR_INVALID_DATA, hem_result["error"])
	var pleat_count_result := _read_integer(parameters["pleat_count"], "parameters.pleat_count", 16, 128)
	if not pleat_count_result["ok"]:
		return _failure(ERR_INVALID_DATA, pleat_count_result["error"])
	var depth_result := _read_number(parameters["pleat_depth_cm"], "parameters.pleat_depth_cm", 0.2, 4.0)
	if not depth_result["ok"]:
		return _failure(ERR_INVALID_DATA, depth_result["error"])
	var sharpness_result := _read_number(parameters["sharpness"], "parameters.sharpness", 0.0, 1.0)
	if not sharpness_result["ok"]:
		return _failure(ERR_INVALID_DATA, sharpness_result["error"])
	var thickness_result := _read_number(parameters["thickness_mm"], "parameters.thickness_mm", 0.2, 3.0)
	if not thickness_result["ok"]:
		return _failure(ERR_INVALID_DATA, thickness_result["error"])

	if typeof(parameters["fabric"]) != TYPE_STRING or not FABRICS.has(String(parameters["fabric"])):
		return _failure(ERR_INVALID_DATA, "parameters.fabric must be one of %s." % str(FABRICS))
	if typeof(parameters["base_color"]) != TYPE_STRING:
		return _failure(ERR_INVALID_DATA, "parameters.base_color must be a #RRGGBB string.")
	var color_result := _read_color(parameters["base_color"], "parameters.base_color")
	if not color_result["ok"]:
		return _failure(ERR_INVALID_DATA, color_result["error"])

	return {
		"ok": true,
		"value": {
			"length_cm": float(length_result["value"]),
			"waist_cm": float(waist_result["value"]),
			"hem_cm": float(hem_result["value"]),
			"pleat_count": int(pleat_count_result["value"]),
			"pleat_depth_cm": float(depth_result["value"]),
			"sharpness": float(sharpness_result["value"]),
			"thickness_mm": float(thickness_result["value"]),
			"fabric": String(parameters["fabric"]),
			"base_color": String(parameters["base_color"]),
		},
	}


static func _validate_bands(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_ARRAY:
		return _failure(ERR_INVALID_DATA, "bands must be an array.")
	var bands: Array = value
	if bands.size() > MAX_BANDS:
		return _failure(ERR_INVALID_DATA, "bands exceeds %d entries." % MAX_BANDS)
	var output: Array = []
	for index in bands.size():
		var band = bands[index]
		var key_error := _check_object_keys(band, BAND_KEYS, "bands[%d]" % index)
		if not key_error.is_empty():
			return _failure(ERR_INVALID_DATA, key_error)
		var band_dictionary: Dictionary = band
		var id_result := _read_string(band_dictionary["id"], "bands[%d].id" % index, MAX_ID_LENGTH, false)
		if not id_result["ok"]:
			return _failure(ERR_INVALID_DATA, id_result["error"])
		var id := String(id_result["value"])
		var start_result := _read_number(band_dictionary["start"], "bands[%d].start" % index, 0.0, 1.0)
		if not start_result["ok"]:
			return _failure(ERR_INVALID_DATA, start_result["error"])
		var end_result := _read_number(band_dictionary["end"], "bands[%d].end" % index, 0.0, 1.0)
		if not end_result["ok"]:
			return _failure(ERR_INVALID_DATA, end_result["error"])
		var start := float(start_result["value"])
		var end := float(end_result["value"])
		if start > 0.995 or end < 0.005 or end - start < 0.004999:
			return _failure(ERR_INVALID_DATA, "bands[%d] must have end - start >= 0.005." % index)
		var color_result := _read_color(band_dictionary["color"], "bands[%d].color" % index)
		if not color_result["ok"]:
			return _failure(ERR_INVALID_DATA, color_result["error"])
		var pattern_result := _read_pattern(band_dictionary["pattern"], "bands[%d].pattern" % index)
		if not pattern_result["ok"]:
			return _failure(ERR_INVALID_DATA, pattern_result["error"])
		var repeat_result := _read_integer(band_dictionary["repeat"], "bands[%d].repeat" % index, 4, 64)
		if not repeat_result["ok"]:
			return _failure(ERR_INVALID_DATA, repeat_result["error"])
		output.append({
			"id": id,
			"start": start,
			"end": end,
			"color": String(band_dictionary["color"]),
			"pattern": String(band_dictionary["pattern"]),
			"repeat": int(repeat_result["value"]),
		})
	return {"ok": true, "value": output}


static func _validate_patches(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_ARRAY:
		return _failure(ERR_INVALID_DATA, "patches must be an array.")
	var patches: Array = value
	if patches.size() > MAX_PATCHES:
		return _failure(ERR_INVALID_DATA, "patches exceeds %d entries." % MAX_PATCHES)
	var output: Array = []
	for index in patches.size():
		var patch = patches[index]
		var key_error := _check_object_keys(patch, PATCH_KEYS, "patches[%d]" % index)
		if not key_error.is_empty():
			return _failure(ERR_INVALID_DATA, key_error)
		var patch_dictionary: Dictionary = patch
		var id_result := _read_string(patch_dictionary["id"], "patches[%d].id" % index, MAX_ID_LENGTH, false)
		if not id_result["ok"]:
			return _failure(ERR_INVALID_DATA, id_result["error"])
		var id := String(id_result["value"])
		var u0_result := _read_number(patch_dictionary["u0"], "patches[%d].u0" % index, 0.0, 1.0)
		if not u0_result["ok"]:
			return _failure(ERR_INVALID_DATA, u0_result["error"])
		var u1_result := _read_number(patch_dictionary["u1"], "patches[%d].u1" % index, 0.0, 1.0)
		if not u1_result["ok"]:
			return _failure(ERR_INVALID_DATA, u1_result["error"])
		var v0_result := _read_number(patch_dictionary["v0"], "patches[%d].v0" % index, 0.0, 1.0)
		if not v0_result["ok"]:
			return _failure(ERR_INVALID_DATA, v0_result["error"])
		var v1_result := _read_number(patch_dictionary["v1"], "patches[%d].v1" % index, 0.0, 1.0)
		if not v1_result["ok"]:
			return _failure(ERR_INVALID_DATA, v1_result["error"])
		var u0 := float(u0_result["value"])
		var u1 := float(u1_result["value"])
		var v0 := float(v0_result["value"])
		var v1 := float(v1_result["value"])
		if u1 <= u0 or v1 <= v0:
			return _failure(ERR_INVALID_DATA, "patches[%d] must satisfy u1 > u0 and v1 > v0." % index)
		var color_result := _read_color(patch_dictionary["color"], "patches[%d].color" % index)
		if not color_result["ok"]:
			return _failure(ERR_INVALID_DATA, color_result["error"])
		var pattern_result := _read_pattern(patch_dictionary["pattern"], "patches[%d].pattern" % index)
		if not pattern_result["ok"]:
			return _failure(ERR_INVALID_DATA, pattern_result["error"])
		var repeat_result := _read_integer(patch_dictionary["repeat"], "patches[%d].repeat" % index, 4, 64)
		if not repeat_result["ok"]:
			return _failure(ERR_INVALID_DATA, repeat_result["error"])
		output.append({
			"id": id,
			"u0": u0,
			"u1": u1,
			"v0": v0,
			"v1": v1,
			"color": String(patch_dictionary["color"]),
			"pattern": String(patch_dictionary["pattern"]),
			"repeat": int(repeat_result["value"]),
		})
	return {"ok": true, "value": output}


static func _validate_strokes(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_ARRAY:
		return _failure(ERR_INVALID_DATA, "strokes must be an array.")
	var strokes: Array = value
	if strokes.size() > MAX_STROKES:
		return _failure(ERR_INVALID_DATA, "strokes exceeds %d entries." % MAX_STROKES)
	var output: Array = []
	var total_points := 0
	for index in strokes.size():
		var stroke = strokes[index]
		var key_error := _check_object_keys(stroke, STROKE_KEYS, "strokes[%d]" % index)
		if not key_error.is_empty():
			return _failure(ERR_INVALID_DATA, key_error)
		var stroke_dictionary: Dictionary = stroke
		var id_result := _read_string(stroke_dictionary["id"], "strokes[%d].id" % index, MAX_ID_LENGTH, false)
		if not id_result["ok"]:
			return _failure(ERR_INVALID_DATA, id_result["error"])
		var id := String(id_result["value"])
		var color_result := _read_color(stroke_dictionary["color"], "strokes[%d].color" % index)
		if not color_result["ok"]:
			return _failure(ERR_INVALID_DATA, color_result["error"])
		var width_result := _read_number(stroke_dictionary["width"], "strokes[%d].width" % index, 0.001, 0.05)
		if not width_result["ok"]:
			return _failure(ERR_INVALID_DATA, width_result["error"])
		if typeof(stroke_dictionary["points"]) != TYPE_ARRAY:
			return _failure(ERR_INVALID_DATA, "strokes[%d].points must be an array." % index)
		var points: Array = stroke_dictionary["points"]
		total_points += points.size()
		if total_points > MAX_TOTAL_POINTS:
			return _failure(ERR_INVALID_DATA, "strokes contain more than %d points in total." % MAX_TOTAL_POINTS)
		var points_output: Array = []
		for point_index in points.size():
			var point = points[point_index]
			if typeof(point) != TYPE_ARRAY:
				return _failure(ERR_INVALID_DATA, "strokes[%d].points[%d] must be a [u, v] array." % [index, point_index])
			var point_array: Array = point
			if point_array.size() != 2:
				return _failure(ERR_INVALID_DATA, "strokes[%d].points[%d] must contain exactly two numbers." % [index, point_index])
			var u_result := _read_number(point_array[0], "strokes[%d].points[%d][0]" % [index, point_index], 0.0, 1.0)
			if not u_result["ok"]:
				return _failure(ERR_INVALID_DATA, u_result["error"])
			var v_result := _read_number(point_array[1], "strokes[%d].points[%d][1]" % [index, point_index], 0.0, 1.0)
			if not v_result["ok"]:
				return _failure(ERR_INVALID_DATA, v_result["error"])
			points_output.append([float(u_result["value"]), float(v_result["value"])])
		output.append({
			"id": id,
			"color": String(stroke_dictionary["color"]),
			"width": float(width_result["value"]),
			"points": points_output,
		})
	return {"ok": true, "value": output}


static func _validate_pattern_uv(value: Variant) -> Dictionary:
	var key_error := _check_object_keys(value, PATTERN_UV_KEYS, "pattern_uv")
	if not key_error.is_empty():
		return _failure(ERR_INVALID_DATA, key_error)
	var pattern_uv: Dictionary = value
	var expected := {"origin": "waist", "seam": "back", "u": "circumference", "v": "waist_to_hem"}
	for key in PATTERN_UV_KEYS:
		if typeof(pattern_uv[key]) != TYPE_STRING or String(pattern_uv[key]) != expected[key]:
			return _failure(ERR_INVALID_DATA, "pattern_uv.%s must be \"%s\"." % [key, expected[key]])
	return {"ok": true, "value": expected.duplicate()}


static func _check_object_keys(value: Variant, expected: Array, label: String) -> String:
	if typeof(value) != TYPE_DICTIONARY:
		return "%s must be an object/dictionary." % label
	var dictionary: Dictionary = value
	for key in dictionary.keys():
		if typeof(key) != TYPE_STRING:
			return "%s contains a non-string key." % label
		if not expected.has(String(key)):
			return "%s contains unknown field \"%s\"." % [label, String(key)]
	for key in expected:
		if not dictionary.has(key):
			return "%s is missing field \"%s\"." % [label, String(key)]
	return ""


static func _read_string(value: Variant, label: String, max_length: int, allow_empty: bool) -> Dictionary:
	if typeof(value) != TYPE_STRING:
		return _failure(ERR_INVALID_DATA, "%s must be a string." % label)
	var text := String(value)
	if not allow_empty and text.is_empty():
		return _failure(ERR_INVALID_DATA, "%s must not be empty." % label)
	if text.length() > max_length:
		return _failure(ERR_INVALID_DATA, "%s is longer than %d characters." % [label, max_length])
	return {"ok": true, "value": text}


static func _read_number(value: Variant, label: String, minimum: float, maximum: float) -> Dictionary:
	if not _is_number(value):
		return _failure(ERR_INVALID_DATA, "%s must be a finite number." % label)
	var number := float(value)
	if not is_finite(number):
		return _failure(ERR_INVALID_DATA, "%s must be a finite number." % label)
	if number < minimum or number > maximum:
		return _failure(ERR_INVALID_DATA, "%s must be within [%s, %s]." % [label, str(minimum), str(maximum)])
	return {"ok": true, "value": number}


static func _read_integer(value: Variant, label: String, minimum: int, maximum: int) -> Dictionary:
	if not _is_integer(value):
		return _failure(ERR_INVALID_DATA, "%s must be an integer." % label)
	var number := int(value)
	if number < minimum or number > maximum:
		return _failure(ERR_INVALID_DATA, "%s must be within [%d, %d]." % [label, minimum, maximum])
	return {"ok": true, "value": number}


static func _read_color(value: Variant, label: String) -> Dictionary:
	if typeof(value) != TYPE_STRING:
		return _failure(ERR_INVALID_DATA, "%s must be a #RRGGBB string." % label)
	var text := String(value)
	if text.length() != 7 or text.substr(0, 1) != "#":
		return _failure(ERR_INVALID_DATA, "%s must be a #RRGGBB string." % label)
	for index in range(1, 7):
		if not HEX_DIGITS.contains(text.substr(index, 1)):
			return _failure(ERR_INVALID_DATA, "%s must be a #RRGGBB string." % label)
	return {"ok": true, "value": text}


static func _read_pattern(value: Variant, label: String) -> Dictionary:
	if typeof(value) != TYPE_STRING or not PATTERNS.has(String(value)):
		return _failure(ERR_INVALID_DATA, "%s must be one of %s." % [label, str(PATTERNS)])
	return {"ok": true, "value": String(value)}


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


static func _is_integer(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) != TYPE_FLOAT:
		return false
	var number := float(value)
	return is_finite(number) and number == floorf(number)


static func _failure(code: int, message: String) -> Dictionary:
	return {"ok": false, "code": code, "error": message, "design": {}}
