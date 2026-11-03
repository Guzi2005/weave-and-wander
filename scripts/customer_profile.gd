extends RefCounted

const Definition = preload("res://scripts/garment_definition.gd")
const ARCHETYPES := {
	"resident": {"title": "本地居民", "styles": [3, 4, 5, 10, 11, 12, 13], "budget": [48, 90], "color_weight": 0.25, "threshold": 0.45, "wear_out": 0.3},
	"tourist": {"title": "游客", "styles": [0, 6, 7, 8], "budget": [55, 100], "color_weight": 0.35, "threshold": 0.45, "wear_out": 0.6},
	"enthusiast": {"title": "爱好者", "styles": [], "budget": [44, 58], "color_weight": 0.5, "threshold": 0.6, "wear_out": 0.35},
}

var archetype := "resident"
var title := ""
var wanted_styles: Array = []
var favorite_palette := 0
var disliked_palette := -1
var budget := 45
var color_weight := 0.3
var threshold := 0.5
var wear_out_chance := 0.4
var retries_left := 1
var max_pieces := 1


static func roll(rng: RandomNumberGenerator) -> RefCounted:
	var profile = load("res://scripts/customer_profile.gd").new()
	var keys := ARCHETYPES.keys()
	profile.archetype = keys[rng.randi_range(0, keys.size() - 1)]
	var data: Dictionary = ARCHETYPES[profile.archetype]
	profile.title = data["title"]
	profile.wanted_styles = data["styles"].duplicate()
	if profile.wanted_styles.is_empty():
		var wearable_styles := []
		for style in Definition.STYLE_NAMES.size():
			if style != 9: wearable_styles.append(style)
		profile.wanted_styles = [wearable_styles[rng.randi_range(0, wearable_styles.size() - 1)]]
	profile.favorite_palette = rng.randi_range(0, Definition.PALETTE_NAMES.size() - 1)
	if profile.archetype == "enthusiast":
		profile.disliked_palette = posmod(profile.favorite_palette + rng.randi_range(1, 3), Definition.PALETTE_NAMES.size())
	profile.budget = rng.randi_range(data["budget"][0], data["budget"][1])
	profile.max_pieces = rng.randi_range(1, 3)
	profile.color_weight = data["color_weight"]
	profile.threshold = data["threshold"]
	profile.wear_out_chance = data["wear_out"]
	return profile


func wants(definition: Resource) -> bool:
	return definition.outfit_style in wanted_styles


func color_score(definition: Resource) -> float:
	if definition.palette_index == favorite_palette:
		return 1.0
	if definition.palette_index == disliked_palette:
		return -1.0
	return 0.2


# Browsing only sees style, colour and the price tag; fit is learnt in the mirror.
func browse_score(definition: Resource) -> float:
	if not wants(definition) or definition.price > budget:
		return -INF
	return 0.5 + color_score(definition) * color_weight - float(definition.price) / float(budget) * 0.2


func wish_text() -> String:
	var styles: Array[String] = []
	for style in wanted_styles:
		styles.append(Definition.STYLE_NAMES[style])
	return "想找%s，喜欢%s" % ["或".join(styles), Definition.PALETTE_NAMES[favorite_palette]]
