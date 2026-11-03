extends RefCounted

## Single source of truth for shared fabric appearance. Fabric batches, cut
## pieces, packages and finished garments all derive their cloth shader
## parameters from describe() so pattern, pigment and material survive the
## whole source fabric -> cut pieces -> made garment chain, with stable
## provenance ids attached.

const SHADER := preload("res://shaders/material_cloth.gdshader")
const PATTERN_CODES := {"plain": 0, "stripe": 1, "check": 2}
const PATTERN_NAMES := {0: "plain", 1: "stripe", 2: "check"}
const PATTERN_IDS := {0: "cloth.plain.v1", 1: "cloth.stripe.v1", 2: "cloth.check.v1"}
const PATTERN_REVISION := 1
const DEFAULT_PATTERN_SCALE := 12.0
const DEFAULT_PIGMENT := Color("779ab1")
const DEFAULT_MATERIAL := "cotton"
const DEFAULT_SOURCE := "procedural_cloth_v1"

const WEAVE_SCALES := {"wool": 75.0, "linen": 125.0}
const DEFAULT_WEAVE_SCALE := 180.0
const SILK_ROUGHNESS := 0.65
const DEFAULT_ROUGHNESS := 0.94
const WOOL_FIBER_STRENGTH := 0.09
const DEFAULT_FIBER_STRENGTH := 0.055


static func describe(data: Dictionary) -> Dictionary:
	var descriptor := data.duplicate(true)
	var code := 0
	if descriptor.has("pattern_code"):
		code = int(descriptor.get("pattern_code", 0))
	else:
		code = int(PATTERN_CODES.get(str(descriptor.get("pattern", "plain")), 0))
	if not PATTERN_NAMES.has(code):
		code = 0
	descriptor["pattern_code"] = code
	descriptor["pattern"] = str(PATTERN_NAMES[code])
	descriptor["pattern_id"] = str(PATTERN_IDS[code])
	var scale_value: Variant = descriptor.get("pattern_scale", 0.0)
	if typeof(scale_value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(scale_value)) or float(scale_value) <= 0.0:
		scale_value = DEFAULT_PATTERN_SCALE
	descriptor["pattern_scale"] = float(scale_value)
	var revision: Variant = descriptor.get("pattern_revision", 0)
	if typeof(revision) not in [TYPE_INT, TYPE_FLOAT] or int(revision) < 1:
		revision = PATTERN_REVISION
	descriptor["pattern_revision"] = int(revision)
	if not descriptor.get("pigment") is Color:
		descriptor["pigment"] = DEFAULT_PIGMENT
	if str(descriptor.get("material", "")).is_empty():
		descriptor["material"] = DEFAULT_MATERIAL
	if not descriptor.get("source_ids") is Array:
		descriptor["source_ids"] = [DEFAULT_SOURCE]
	return descriptor


static func make_material(data: Dictionary, use_uv: bool = false, uv_metres: Vector2 = Vector2.ONE) -> ShaderMaterial:
	var descriptor := describe(data)
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("pigment", descriptor["pigment"])
	material.set_shader_parameter("pattern", float(descriptor["pattern_code"]))
	material.set_shader_parameter("pattern_scale", float(descriptor["pattern_scale"]))
	var kind := str(descriptor["material"])
	material.set_shader_parameter("weave_scale", float(WEAVE_SCALES.get(kind, DEFAULT_WEAVE_SCALE)))
	material.set_shader_parameter("roughness", SILK_ROUGHNESS if kind == "silk" else DEFAULT_ROUGHNESS)
	material.set_shader_parameter("fiber_strength", WOOL_FIBER_STRENGTH if kind == "wool" else DEFAULT_FIBER_STRENGTH)
	if use_uv:
		material.set_shader_parameter("use_material_uv", true)
		material.set_shader_parameter("uv_metres", uv_metres)
	return material
