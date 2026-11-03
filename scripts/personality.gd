extends RefCounted

# Per-actor personality traits. Rolled once at spawn and kept on the actor for
# its whole lifetime, so behavior stays consistent. The registry is data-driven:
# adding an entry to TRAITS makes the trait available to roll() and value().
const TRAITS := {
	# High persistence keeps working at lower energy instead of breaking at once.
	"persistence": {"name": "韧性", "min": 0.0, "max": 1.0, "default": 0.5},
	# High recovery regains energy faster while seated or napping.
	"recovery": {"name": "恢复", "min": 0.0, "max": 1.0, "default": 0.5},
	# Numeric work-speed bonus: positive finishes timed jobs faster.
	"work_bonus": {"name": "手艺", "min": -0.05, "max": 0.15, "default": 0.0},
}


static func roll(rng: RandomNumberGenerator) -> Dictionary:
	var traits := {}
	for key in TRAITS:
		traits[key] = rng.randf_range(float(TRAITS[key]["min"]), float(TRAITS[key]["max"]))
	return traits


static func value(traits: Dictionary, key: String) -> float:
	if traits.has(key):
		return float(traits[key])
	return float(TRAITS.get(key, {"default": 0.0})["default"])


static func rest_threshold(traits: Dictionary, base: float) -> float:
	return clampf(base * (1.0 + (.5 - value(traits, "persistence")) * .8), .15, .45)


static func recovery_scale(traits: Dictionary) -> float:
	return 0.7 + 0.6 * value(traits, "recovery")


static func work_bonus(traits: Dictionary) -> float:
	return value(traits, "work_bonus")


static func describe(traits: Dictionary) -> String:
	var p := value(traits,"persistence")
	return "%s · 恢复 ×%.2f · 工速 %+.0f%%" % ["有始有终" if p >= .65 else ("量力而行" if p < .35 else "随性"), recovery_scale(traits), work_bonus(traits)*100.0]
