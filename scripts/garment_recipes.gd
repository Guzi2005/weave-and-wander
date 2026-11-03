extends RefCounted

## Bounded heuristic recipe table for the producible clothing styles.
## Amounts are per-unit size_factor estimates (net fabric, recoverable remnant,
## waste, thread), not a nesting solver. Style 1 (apron) preserves the original
## single-recipe amounts exactly; every other style has its own distinct tuple.

const STYLE_NAMES: Array[String] = ["连衣裙", "围裙", "马甲", "衬衣", "长裤", "半裙"]
const FLOWER_STYLE := 9
const BASIC_NAMES := {17:"布艺发箍",10:"古巴领衬衫",11:"娃娃衫",12:"日常半裙",13:"V领背心"}
const PRODUCTION_STYLES := [0,1,2,3,4,5,10,11,12,13,17]

const RECIPES := {
	17: {"net_fraction":.10,"remnant_fraction":.015,"waste_fraction":.01,"thread_per_size_m":1.8},
	10: {"net_fraction": 1.05, "remnant_fraction": .14, "waste_fraction": .07, "thread_per_size_m": 13.0},
	11: {"net_fraction": 1.25, "remnant_fraction": .16, "waste_fraction": .08, "thread_per_size_m": 14.0},
	12: {"net_fraction": .90, "remnant_fraction": .15, "waste_fraction": .07, "thread_per_size_m": 11.0},
	13: {"net_fraction": .60, "remnant_fraction": .10, "waste_fraction": .04, "thread_per_size_m": 8.0},
	9: {"net_fraction": 0.035, "remnant_fraction": 0.005, "waste_fraction": 0.005, "thread_per_size_m": 0.8},
	0: {"net_fraction": 1.50, "remnant_fraction": 0.24, "waste_fraction": 0.10, "thread_per_size_m": 18.0},
	1: {"net_fraction": 0.90, "remnant_fraction": 0.18, "waste_fraction": 0.06, "thread_per_size_m": 12.0},
	2: {"net_fraction": 0.70, "remnant_fraction": 0.12, "waste_fraction": 0.05, "thread_per_size_m": 9.0},
	3: {"net_fraction": 1.10, "remnant_fraction": 0.15, "waste_fraction": 0.07, "thread_per_size_m": 14.0},
	4: {"net_fraction": 1.30, "remnant_fraction": 0.20, "waste_fraction": 0.08, "thread_per_size_m": 15.0},
	5: {"net_fraction": 1.00, "remnant_fraction": 0.22, "waste_fraction": 0.09, "thread_per_size_m": 13.0},
}


static func valid(outfit_style: int) -> bool:
	return RECIPES.has(outfit_style)


static func recipe(outfit_style: int) -> Dictionary:
	return RECIPES.get(outfit_style, {})


static func style_name(outfit_style: int) -> String:
	if BASIC_NAMES.has(outfit_style): return BASIC_NAMES[outfit_style]
	if outfit_style == FLOWER_STYLE: return "胸花小物"
	return STYLE_NAMES[outfit_style] if valid(outfit_style) else "未知款式"
