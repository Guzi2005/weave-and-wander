extends Resource

const STYLE_NAMES := ["连衣裙", "围裙", "马甲", "衬衣", "长裤", "半裙", "贝雷帽", "渔夫帽", "宽檐帽", "胸花", "古巴领衬衫", "娃娃衫", "日常半裙", "V领背心", "彩饰头饰与紫色米珠串", "红底花纹上衣", "浅蓝长褶裙", "布艺发箍"]
const STYLE_PRICES := [48, 18, 24, 26, 28, 30, 16, 20, 22, 6, 28, 30, 26, 20, 32, 36, 40, 14]
const DESIGN_IDS := ["long_dress", "apron", "waistcoat", "shirt", "trousers", "skirt", "beret", "bucket_hat", "sun_hat", "flower", "cuban_shirt", "babydoll_blouse", "everyday_skirt", "v_neck_tank", "mosuo_headwear_001", "mosuo_top_001", "mosuo_skirt_001", "fabric_headband"]
const PALETTE_NAMES := ["湖蓝", "赭红", "松绿", "藕紫"]
const MOSUO_STYLES := [14, 15, 16]
const MOSUO_COLLECTION := "mosuo_photo_001"

@export var design_id := "long_dress"
@export var outfit_style := 0
@export var palette_index := 0
@export var price := 40
@export var collection_id := "everyday_study"
@export var collection_name := ""
@export var wiki_record_id := ""
@export var source_record_id := ""
@export var culture_attribution := ""
@export var source_design_path := ""
@export var material_data: Dictionary = {}
@export var fabric_physics: Resource = preload("res://components/garment_fabric_profile.gd").new()
@export var accessory_kind := ""
@export_range(.012,.12,.002) var headband_min_width := .025
@export_range(.025,.18,.002) var headband_max_width := .09
@export var flower_material_data: Dictionary = {}
@export var compact_apron_folds := false
@export_range(.12,1.0,.01) var clip_release_depth := .55
@export_range(.1,1.0,.05) var clip_release_fraction := .65
# Retained depth relative to the worn shell; zero override selects style defaults.
@export_range(0.0,1.0,.01) var hanging_depth_override := 0.0
@export_range(.05,1.0,.01) var hanging_depth_min := .10
@export_range(.05,1.0,.01) var hanging_depth_max := .65

@export_range(.35,1.05,.01) var skirt_length := .70
@export_range(.55,1.05,.01) var garment_length := .80
@export_range(0.0, 0.12, 0.005) var folded_thickness := 0.018


static func create(style: int, palette: int) -> Resource:
	var definition = load("res://scripts/garment_definition.gd").new()
	definition.outfit_style = style
	definition.palette_index = palette
	definition.collection_id = "everyday_study_%d" % palette
	definition.design_id = DESIGN_IDS[style]
	definition.price = STYLE_PRICES[style]
	if style in MOSUO_STYLES:
		definition.palette_index = 0
		definition.collection_id = MOSUO_COLLECTION
		definition.collection_name = "摩梭·照片001套装"
		definition.wiki_record_id = "WW-MOS-001-C%02d" % (style - 13)
		definition.source_record_id = "WW-MOS-001"
		definition.source_design_path = "res://Docs/wiki-concept-2026-10-28/mosuo-example/source-user-upload.png"
		definition.culture_attribution = "摩梭（用户提供归属，待考证）"
	return definition


func slots() -> Array[String]:
	match outfit_style:
		0: return ["top", "bottom"]
		1, 2, 13: return ["outer"]
		3, 10, 11, 15: return ["top"]
		4, 5, 12, 16: return ["bottom"]
		_: return ["headwear"]


func is_hat() -> bool:
	return outfit_style in [6,7,8,14,17]


func is_mosuo_photo_set() -> bool:
	return outfit_style in MOSUO_STYLES


func hanger_profile() -> Dictionary:
	# Support points belong to the garment template, in its original mesh coordinates.
	match outfit_style:
		1: return {"kind":"strap", "height":1.88, "span":.145}
		4: return {"kind":"clip", "span":.24, "depth":.018}
		5,12,16: return {"kind":"clip", "span":.26, "depth":.026}
		_: return {"kind":"shoulder", "height":1.83, "span":.18}


func form_profile(bottom: float, top: float) -> Dictionary:
	# Empty garments retain a little air between the panels on a shoulder rail.
	var hanging_depth := .12
	if hanger_profile().kind == "shoulder":
		match outfit_style:
			2, 13: hanging_depth = .42  # Sleeveless outer layers.
			0: hanging_depth = .55      # The skirt keeps more of its fullness.
			_: hanging_depth = .48      # Blouses and shirts.
	if hanging_depth_override > 0: hanging_depth = hanging_depth_override
	hanging_depth = clampf(hanging_depth,minf(hanging_depth_min,hanging_depth_max),maxf(hanging_depth_min,hanging_depth_max))
	return {"bottom":bottom,"top":top,"half_width":.20,"half_y":lerpf(bottom,top,.5),
		"quarter_y":lerpf(bottom,top,.75),"quarter_fold":top-bottom > 1.35,
		"clip_hung":hanger_profile().kind == "clip","clip_release_depth":clip_release_depth,"clip_release_fraction":clip_release_fraction,
		"hanging_depth":hanging_depth,"pressed_depth":.015 + folded_thickness,
		"fold_thickness":folded_thickness,"uv_width":1.04,"compact_apron_folds":compact_apron_folds}


func long_bottom() -> bool:
	return outfit_style in [0, 5, 12, 16]


func compatible(other: Resource) -> bool:
	for slot in slots():
		if slot in other.slots():
			return false
	return true


static func part_slot(part: MeshInstance3D) -> String:
	if part.has_meta("garment_slot"): return str(part.get_meta("garment_slot"))
	var label := str(part.name)
	var semantic: String = part.get_meta("semantic", "")
	if semantic == "headwear": return "headwear"
	if semantic in ["head", "hair", "shoeL", "shoeR"] or label in ["Neck", "Mitten", "Thumb", "InternalShoulder"]: return ""
	if label in ["Apron", "Pocket", "ApronTie", "OpenWaistcoat", "FrontBinding"] or label.begins_with("ApronStrap"): return "outer"
	if semantic in ["legL", "legR", "skirt"] or label in ["WaistRibbon", "TrouserWaistband"]: return "bottom"
	return "top"


static func is_flower(part: MeshInstance3D) -> bool:
	return part.get_meta("material_role","") == "flower" or str(part.name).begins_with("Petal") or str(part.name).begins_with("FlowerCenter")


static func is_button(part: MeshInstance3D) -> bool:
	return str(part.name).begins_with("Button")


func display_name() -> String:
	if is_mosuo_photo_set(): return collection_name + " / " + STYLE_NAMES[outfit_style]
	if accessory_kind == "flower": return str(material_data.get("name","布艺")) + "胸花"
	if not material_data.is_empty(): return str(material_data.get("name","定制布料")) + STYLE_NAMES[outfit_style]
	return PALETTE_NAMES[palette_index] + STYLE_NAMES[outfit_style]
