@tool
class_name SeedBeadBundle
extends Resource

## Reusable seed-bead bundle. Units are model metres; identity/culture belongs to the host garment.
## Each bead is an open barrel, merged into one mesh. Parameters never imply historical dimensions.
##
## Parametric contract (schema ww-seed-bead-bundle-v2, v1 keys preserved):
## - bead_preset selects ONE global material family (glass/pearl/metal/matte); repeat-unit entries
##   vary real geometry (diameter_scale / length_scale) and vertex color per bead.
## - repeat_unit entries: {"diameter_scale":float, "length_scale":float,
##   "color":Color (optional), "material":StringName preset (optional)}. The cycle applies per bead,
##   so e.g. 3 small pearls + 1 large pearl changes bead count, silhouette and colors.
## - spacing is the bead pitch as a multiple of bead length; tightness divides the pitch
##   (higher tightness -> more beads per strand). Legacy defaults spacing=.96/tightness=1
##   reproduce the original baked look exactly when path and repeat_unit are empty.
## - path (Curve3D, HeadRig local coordinates, editable in the Inspector) routes the bundle:
##   every strand follows the full shared route, from nape over shoulder to free end.
##   Empty/null path keeps the legacy anchor fan.
## - Material variation is NOT faked through color alone: entries naming a different material
##   preset are surfaced through build_geometry_groups(), which returns one geometry dictionary
##   per preset plus "material_preset"; hosts wanting per-group materials call material_for(preset)
##   per group. build_geometry() stays the single-mesh default (one global material) and remains
##   the integration contract used by mosuo_doll.
## - Topology is bounded by max_beads; rebuilds stop placing beads past the cap.

@export var bead_color := Color("722ac4")
@export_range(.002, .016, .0005) var bead_diameter := .0045
@export_range(4, 72, 1) var strand_count := 12
@export_range(.1, 2.5, .01) var strand_length := 2.03
@export_range(.01, .25, .005) var bundle_width := .15
@export_range(0, .25, .005) var length_variation := .11
@export_range(-40, 40, .5) var angle_degrees := 1.5
@export var anchor := Vector3(.292, .445, .255)
@export var drape := Vector3(.012, 0, .075)
@export_range(0, 1, .01) var roughness := .28
@export var random_seed := 17
@export_enum("glass", "pearl", "metal", "matte") var bead_preset := "glass"
## Bead pitch as a multiple of bead length (.96 reproduces the original overlap).
@export_range(.5, 2.0, .01) var spacing := .96
## Divides the pitch: tighter strands seat more beads over the same length.
@export_range(.5, 1.6, .01) var tightness := 1.0
## Per-bead cycle; empty means uniform beads in bead_color / bead_preset.
@export var repeat_unit: Array[Dictionary] = []
## Shared route in HeadRig local coordinates, followed by every strand.
@export var path: Curve3D
## Hard cap on emitted beads so interactive rebuilds stay bounded.
@export_range(200, 120000, 100) var max_beads := 96000
## Shortest strand length as a fraction of strand_length at the gathered (path start) end.
@export_range(.05, 1.0, .01) var path_length_taper := .22

static func photo_001() -> SeedBeadBundle:
	return load("res://assets/collections/mosuo_seed_beads.tres").duplicate(true)

func parameters() -> Dictionary:
	var unit: Array = []
	for entry in repeat_unit:
		unit.append({"diameter_scale":float(entry.get("diameter_scale", 1.0)),
			"length_scale":float(entry.get("length_scale", 1.0)),
			"color":(entry.get("color") as Color).to_html() if entry.get("color") is Color else "",
			"material":String(entry.get("material", ""))})
	return {"schema":"ww-seed-bead-bundle-v2","color":bead_color.to_html(),"diameter":bead_diameter,
		"strands":strand_count,"length":strand_length,"width":bundle_width,"length_variation":length_variation,
		"angle_degrees":angle_degrees,"anchor":[anchor.x,anchor.y,anchor.z],"drape":[drape.x,drape.y,drape.z],
		"roughness":roughness,"seed":random_seed,"preset":bead_preset,"spacing":spacing,
		"tightness":tightness,"repeat_unit":unit,"max_beads":max_beads,
		"path_points":path.get_point_count() if path != null else 0,
		"units":"model metres", "attachment":"HeadwearSlot"}

func _uses_entry_colors() -> bool:
	for entry in repeat_unit:
		if entry.get("color") is Color: return true
	return false

func _entry(index: int) -> Dictionary:
	if repeat_unit.is_empty(): return {}
	return repeat_unit[index % repeat_unit.size()]

func build_geometry() -> Dictionary:
	var groups := build_geometry_groups()
	if groups.size() == 1:
		var single: Dictionary = groups[0]
		single.erase("material_preset")
		return single
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var colors := PackedColorArray()
	var bead_total := 0
	for group in groups:
		var base := vertices.size()
		vertices.append_array(group.vertices)
		normals.append_array(group.normals)
		colors.append_array(group.colors)
		for index in group.indices: indices.append(base + index)
		bead_total += group.bead_count
	return {"vertices":vertices,"normals":normals,"indices":indices,"colors":colors,
		"arm_weights":PackedFloat32Array(),"slot":"headwear","bead_count":bead_total}

## Optional integration route: one geometry dictionary per material preset named in repeat_unit.
## Each entry mirrors build_geometry() and adds "material_preset"; pair it with material_for().
func build_geometry_groups() -> Array[Dictionary]:
	var specs := _bead_specs()
	var order: Array[String] = []
	var by_preset := {}
	for spec in specs:
		var preset: String = spec.preset
		if not by_preset.has(preset):
			by_preset[preset] = []
			order.append(preset)
		by_preset[preset].append(spec)
	var groups: Array[Dictionary] = []
	var segments := 6
	for preset in order:
		var profiles := [Vector2(-.43,.32),Vector2(-.27,.5),Vector2(.27,.5),Vector2(.43,.32)]
		if preset == "pearl": profiles = [Vector2(-.5,.04),Vector2(-.35,.35),Vector2(0,.5),Vector2(.35,.35),Vector2(.5,.04)]
		var vertices := PackedVector3Array()
		var normals := PackedVector3Array()
		var indices := PackedInt32Array()
		var colors := PackedColorArray()
		for spec in by_preset[preset]:
			var base := vertices.size()
			var frame: Basis = spec.frame
			var size: float = spec.size
			for profile in profiles:
				for segment in segments:
					var a := TAU*segment/segments
					var radial := Vector3(cos(a),0,sin(a))
					vertices.append(spec.center+frame*(radial*profile.y*size+Vector3.UP*profile.x*size*spec.length_scale))
					normals.append(frame*(radial+Vector3.UP*profile.x*.9).normalized())
					colors.append(spec.tint)
			for row in profiles.size()-1:
				for segment in segments:
					var a := base+row*segments+segment
					var b := base+row*segments+(segment+1)%segments
					indices.append_array(PackedInt32Array([a,a+segments,b,b,a+segments,b+segments]))
		groups.append({"vertices":vertices,"normals":normals,"indices":indices,"colors":colors,
			"arm_weights":PackedFloat32Array(),"slot":"headwear","bead_count":(by_preset[preset] as Array).size(),
			"material_preset":preset})
	return groups

## Deterministic list of bead placements; shared by the merged and grouped builds.
func _bead_specs() -> Array[Dictionary]:
	var specs: Array[Dictionary] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed
	var size := clampf(bead_diameter,.002,.016)
	var count := clampi(strand_count,4,72)
	var tilt := Basis(Vector3.FORWARD,deg_to_rad(angle_degrees))
	var pitch := spacing/maxf(tightness,.05)
	var colored := _uses_entry_colors()
	var bead_total := 0
	var path_length := path.get_baked_length() if path != null and path.get_point_count() >= 2 else 0.0
	for strand in count:
		var t := float(strand) / maxf(count-1,1)
		var length := strand_length + rng.randf_range(-length_variation,length_variation)
		var depth := float(strand % 3-1)*size*1.65
		var phase := rng.randf_range(0,TAU)
		var strand_anchor := anchor
		var hang := Vector3.DOWN
		if path_length > 0.0:
			var distance := 0.0
			strand_anchor = path.sample_baked(distance)
			var tangent := path.sample_baked(minf(distance+.01,path_length))-path.sample_baked(maxf(distance-.01,0.0))
			if tangent.length() < .0001: tangent = Vector3.FORWARD
			tangent = tangent.normalized()
			hang = (Vector3.DOWN+Vector3(tangent.x,0,tangent.z)*.45).normalized()
			length = path_length-rng.randf_range(0,length_variation)
		var strand_tilt := tilt
		if path_length > 0.0:
			var side := hang.cross(Vector3.FORWARD)
			if side.length() < .001: side = Vector3.RIGHT
			strand_tilt = Basis(side.normalized(),-hang,side.normalized().cross(-hang)).orthonormalized()
		var bead_index := 0
		var cursor := 0.0
		while bead_total < max_beads:
			var entry := _entry(bead_index)
			var dscale := clampf(float(entry.get("diameter_scale",1.0)),.2,3.0)
			var lscale := clampf(float(entry.get("length_scale",1.0)),.2,3.0)
			var step := size*dscale*lscale*pitch
			var u := (cursor+step*.5)/length
			if u >= 1.0: break
			var sway := sin(u*PI*1.4+phase)*size*.7*u
			var center := Vector3()
			if path_length > 0.0:
				var distance := minf(cursor+step*.5,path_length)
				center = path.sample_baked(distance,true)
				var tangent := (path.sample_baked(minf(distance+.005,path_length),true)-path.sample_baked(maxf(distance-.005,0),true)).normalized()
				var side := Vector3.RIGHT-tangent*Vector3.RIGHT.dot(tangent)
				if side.length_squared() < .01: side = Vector3.FORWARD-tangent*Vector3.FORWARD.dot(tangent)
				side = side.normalized()
				strand_tilt = Basis(side,-tangent,side.cross(-tangent)).orthonormalized()
				var spread := bundle_width*(.35+.65*smoothstep(.12,.45,u))
				center += side*((t-.5)*spread+sway)+strand_tilt.z*depth
				center.y = path.get_point_position(0).y+(center.y-path.get_point_position(0).y)*(strand_length/2.03)
			else:
				center = strand_anchor + tilt*Vector3((t-.5)*bundle_width*(.52+.48*sin(u*PI*.8))+drape.x*u+sway,-u*length,depth+drape.z*sin(u*PI*.7))
			var shade := 1.0-rng.randf_range(0,.14)
			var tint := Color(shade,shade,shade)
			if colored:
				var base_color: Color = entry.get("color",bead_color) if entry.get("color") is Color else bead_color
				tint = base_color.srgb_to_linear()*shade
			specs.append({"center":center,"frame":strand_tilt,"size":size*dscale,"length_scale":lscale,
				"tint":tint,"preset":String(entry.get("material",bead_preset))})
			bead_total += 1
			bead_index += 1
			cursor += step
		if bead_total >= max_beads: break
	return specs

## One global material for the merged build; albedo moves to vertex colors when repeat-unit
## entries carry explicit colors so per-bead colors survive the single-material default.
func material() -> StandardMaterial3D:
	return material_for(bead_preset)

func material_for(preset: String) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.resource_name = "Seed beads · %s" % preset.capitalize()
	mat.albedo_color = Color.WHITE if _uses_entry_colors() else bead_color
	mat.vertex_color_use_as_albedo = true
	match preset:
		"pearl":
			mat.roughness = .34
			mat.metallic = 0.0
			mat.metallic_specular = .5
		"metal":
			mat.roughness = minf(roughness,.32)
			mat.metallic = .92
			mat.metallic_specular = .8
		"matte":
			mat.roughness = .82
			mat.metallic = 0.0
			mat.metallic_specular = .3
		_:
			mat.roughness = roughness
			mat.metallic = .05
			mat.metallic_specular = .65
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat
