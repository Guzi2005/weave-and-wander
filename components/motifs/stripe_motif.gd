class_name StripeMotif
extends Resource

## Parametric warp-stripe fabric motif (weave-pleated-skirt "patches"
## semantics: u0/u1 are circumferential, colors repeat around the skirt).
## One sequence cell spans 1/repeat_count of the circumference; u0/u1 in
## each entry are relative to that cell. Used by UkrainianCostume for the
## overskirt, and exposed in the wiki as an adjustable recipe asset.

@export var base_color: Color = Color("1f3a3c")
@export_range(1, 32) var repeat_count: int = 8
@export var sequence: Array[Dictionary] = [
	{"role": "yellow", "color": Color("c8a23a"), "u0": .005, "u1": .018},
	{"role": "green", "color": Color("4a7a4a"), "u0": .022, "u1": .040},
	{"role": "purple", "color": Color("6e4a86"), "u0": .044, "u1": .054}]


func patches() -> Array:
	# Entry u0/u1 are absolute-u offsets inside one cell (same semantics as
	# the contract's patches array); do NOT rescale them per cell.
	var out := []
	for repeat in repeat_count:
		var cell := float(repeat) / repeat_count
		for entry in sequence:
			out.append({"u0": cell + float(entry["u0"]),
				"u1": cell + float(entry["u1"]),
				"role": String(entry["role"])})
	return out


func color_for(role: String) -> Color:
	if role == "base":
		return base_color
	if role == "base_shade":
		return base_color.darkened(.14)
	for entry in sequence:
		if String(entry["role"]) == role:
			return entry["color"]
	return base_color


func roles() -> Array:
	var out := ["base"]
	for entry in sequence:
		out.append(String(entry["role"]))
	return out


func parameters() -> Dictionary:
	var stripes := []
	for entry in sequence:
		stripes.append({"role": entry["role"], "color": (entry["color"] as Color).to_html(),
			"u0": entry["u0"], "u1": entry["u1"]})
	return {"motif": "warp_stripe", "base_color": base_color.to_html(),
		"repeat_count": repeat_count, "sequence": stripes}
