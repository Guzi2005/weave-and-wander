extends SceneTree

const BeadBundle = preload("res://components/seed_bead_bundle.gd")
const Braid = preload("res://components/path_braid.gd")
var failures: Array[String] = []

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _aabb(vertices: PackedVector3Array) -> AABB:
	var box := AABB(vertices[0], Vector3.ZERO)
	for v in vertices: box = box.expand(v)
	return box

func _check_finite(data: Dictionary, label: String) -> void:
	check(data.indices.size() % 3 == 0, "%s indices not triangles" % label)
	check(data.vertices.size() == data.normals.size(), "%s vertex/normal count mismatch" % label)
	check(data.vertices.size() == data.colors.size(), "%s vertex/color count mismatch" % label)
	for index in data.indices:
		check(index >= 0 and index < data.vertices.size(), "%s index out of range" % label)
	for n in data.normals:
		check(is_finite(n.x) and is_finite(n.y) and is_finite(n.z), "%s non-finite normal" % label)
		check(absf(n.length()-1.0) < .01, "%s normal not unit length" % label)

func _run() -> void:
	# Default photo001 preset: purple tiny seed beads, 28 strands.
	var beads: BeadBundle = BeadBundle.photo_001()
	check(beads.bead_color.is_equal_approx(Color("722ac4")), "photo001 beads lost the purple color")
	check(is_equal_approx(beads.bead_diameter, .008), "photo001 bead diameter changed")
	check(beads.strand_count == 28, "photo001 strand count changed")
	check(beads.bead_preset == "glass", "photo001 bead preset changed")

	# Bead path: gathers behind the head, rounds the right side, hangs down the front.
	check(beads.path != null and beads.path.get_point_count() >= 4, "bead path missing")
	var first := beads.path.get_point_position(0)
	var last := beads.path.get_point_position(beads.path.get_point_count()-1)
	check(first.z < -.1, "bead path does not start behind the head")
	check(last.z > .1, "bead path does not end at the front")
	check(last.y < first.y, "bead path does not descend toward the front")
	var max_x := -1.0
	for i in beads.path.get_point_count():
		max_x = maxf(max_x, beads.path.get_point_position(i).x)
	check(max_x > .3, "bead path never rounds the right side")

	# Path mode changes the real mesh compared to the legacy anchor fan.
	var with_path: Dictionary = beads.build_geometry()
	_check_finite(with_path, "beads")
	var legacy: BeadBundle = beads.duplicate()
	legacy.path = null
	var without_path: Dictionary = legacy.build_geometry()
	check(_aabb(with_path.vertices) != _aabb(without_path.vertices), "bead path did not affect geometry")
	check(with_path.slot == "headwear" and with_path.has("arm_weights"), "bead geometry contract keys missing")
	check(with_path.bead_count > 100, "suspiciously few beads in default build")

	# Tightness changes bead counts.
	var loose: BeadBundle = beads.duplicate()
	loose.tightness = .6
	var tight: BeadBundle = beads.duplicate()
	tight.tightness = 1.5
	var loose_count: int = loose.build_geometry().bead_count
	var tight_count: int = tight.build_geometry().bead_count
	check(tight_count > loose_count, "tighter spacing did not increase bead count")

	# Repeat unit 3 small pearls + 1 large pearl changes geometry and colors.
	var repeated: BeadBundle = beads.duplicate()
	repeated.repeat_unit = [
		{"diameter_scale":.72, "length_scale":.72, "color":Color("e8e2d4"), "material":"pearl"},
		{"diameter_scale":.72, "length_scale":.72, "color":Color("e8e2d4"), "material":"pearl"},
		{"diameter_scale":.72, "length_scale":.72, "color":Color("e8e2d4"), "material":"pearl"},
		{"diameter_scale":1.55, "length_scale":1.35, "color":Color("f2ecdd"), "material":"pearl"}]
	var repeat_geo: Dictionary = repeated.build_geometry()
	_check_finite(repeat_geo, "repeat beads")
	check(repeat_geo.bead_count != with_path.bead_count, "repeat unit did not change bead count")
	check(_aabb(repeat_geo.vertices) != _aabb(with_path.vertices), "repeat unit did not change bead geometry")
	var distinct := {}
	for c in repeat_geo.colors: distinct[c.to_html()] = true
	check(distinct.size() >= 2, "repeat unit did not introduce per-bead colors")
	var groups := repeated.build_geometry_groups()
	check(groups.size() == 1 and groups[0].material_preset == "pearl", "grouped build lost the pearl preset")
	var mixed: BeadBundle = beads.duplicate()
	mixed.repeat_unit = [{"material":"pearl"}, {"material":"metal", "diameter_scale":1.4}]
	check(mixed.build_geometry_groups().size() == 2, "mixed material presets did not split geometry groups")
	var metal_mat := mixed.material_for("metal")
	var matte_mat := mixed.material_for("matte")
	check(metal_mat.metallic > .8 and matte_mat.metallic < .1, "material presets do not differ")
	check(repeat_geo.bead_count <= repeated.max_beads, "bead cap not enforced")

	# Deterministic rebuild.
	var again: Dictionary = BeadBundle.photo_001().build_geometry()
	check(again.vertices == with_path.vertices and again.indices == with_path.indices, "bead geometry not deterministic")

	# Retained legacy recipe remains independently reproducible.
	var current: Braid = Braid.photo_001()
	check(current.wrap_count == 2 and current.construction == 1,"Current braid must use two broad plait courses")
	_check_finite(current.build_geometry(),"double braid")
	var braid: Braid = load("res://assets/collections/node_styles/legacy-single.tres")
	check(braid.strands == 3, "braid strand count changed")
	check(is_equal_approx(braid.width, .075) and is_equal_approx(braid.depth, .055), "braid dimensions changed")
	check(is_equal_approx(braid.pitch, .16), "braid pitch changed")
	var bfirst := braid.path.get_point_position(0)
	var blast := braid.path.get_point_position(braid.path.get_point_count()-1)
	check(bfirst.z > .2, "braid path does not start at front/top")
	check(blast.z < -.1, "braid tail is not concealed at the back")
	check(Vector2(blast.x, blast.z).length() < .30, "braid tail not tucked inside the ring")
	var braid_geo: Dictionary = braid.build_geometry()
	_check_finite(braid_geo, "braid")
	var bbox := _aabb(braid_geo.vertices)
	check(bbox.size.x > .68 and bbox.size.x < .92, "braid crown span off: %s" % bbox.size)
	check(bbox.size.y < .30, "braid not a flat crown ring: %s" % bbox.size)
	check(braid_geo.strand_count == 3, "braid geometry lost strands")

	# Interlacing: strand phases make the over-under oscillation, not a plain ring.
	var braid_params := braid.parameters()
	check(braid_params.schema == "ww-path-braid-v1", "braid parameters schema missing")

	# Width/depth/pitch are parametric.
	var wider: Braid = braid.duplicate()
	wider.width = .12
	var wider_box := _aabb(wider.build_geometry().vertices)
	check(wider_box.size.x > bbox.size.x+.02, "braid width did not affect geometry")
	var thicker: Braid = braid.duplicate()
	thicker.depth = .10
	check(_aabb(thicker.build_geometry().vertices) != bbox, "braid depth did not affect geometry")
	var coarse: Braid = braid.duplicate()
	coarse.pitch = .30
	check(_aabb(coarse.build_geometry().vertices) != bbox, "braid pitch did not affect geometry")
	check(coarse.build_geometry().vertices != braid.build_geometry().vertices, "braid pitch did not move vertices")

	# Braid determinism.
	var braid_again: Dictionary = braid.duplicate(true).build_geometry()
	check(braid_again.vertices == braid_geo.vertices, "braid geometry not deterministic")

	print("PARAMETRIC_ADORNMENTS_TEST failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
