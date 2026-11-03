extends SceneTree

## Headless acceptance test for the modern everyday catalog garments
## (styles 10-13) and the continuous crossed apron straps.
##
## Run with:
##   Godot_v4.7.1-stable_win64_console.exe --headless --path . \
##       --script tests/basic_garment_geometry_test.gd --log-file captures/basic_garment_geometry_test.log

const Doll = preload("res://scripts/catalog_doll.gd")
const Definition = preload("res://scripts/garment_definition.gd")
const Basic = preload("res://components/basic_garment.gd")
const WEIGHT_EPSILON := 0.001
var failures: Array[String] = []
var _dolls: Array = []


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	if not ok and not failures.has(message):
		failures.append(message)
		push_error(message)


func _run() -> void:
	var garments := {}
	for style in [10, 11]:
		garments[style] = _check_top(style)
	garments[13] = _check_vest()
	garments[12] = _check_skirt()
	_check_apron_straps()
	_check_distinct(garments)
	for doll in _dolls:
		doll.free()
	print("BASIC_GARMENT_TEST failures=", failures.size())
	quit(0 if failures.is_empty() else 1)


func _make(style: int, outfit := 2) -> VolumeDoll:
	var doll := Doll.new()
	doll.catalog_style = style
	doll.configure({"outfit": outfit, "palette": 0})
	root.add_child(doll)
	_dolls.append(doll)
	return doll


func _part(doll: VolumeDoll, label: String) -> MeshInstance3D:
	for part in doll.rig.meshes:
		if part.name == label:
			return part
	return null


func _check_top(style: int) -> MeshInstance3D:
	var label: String = {10: "CubanShirt", 11: "BabydollBlouse"}[style]
	var doll := _make(style)
	var part := _part(doll, label)
	check(part != null, "style %d has no %s mesh" % [style, label])
	if part == null:
		return null
	check(part.skin != null, label + " must be bound to the body skin, not static")
	check(part.get_meta("garment_slot", "") == "top", label + " needs garment_slot top metadata")
	check(Definition.part_slot(part) == "top", label + " must resolve to the top part slot")
	check(part.get_meta("semantic", "") == "garment", label + " must use garment skinning")
	# Old outfit-2 clothing is stripped before the rig bind; the body stays.
	for removed in ["TailoredShell", "OpenWaistcoat", "FrontBinding"]:
		check(_part(doll, removed) == null, label + " build must remove " + removed)
	check(doll.body_rig.find_children("ButtonRow", "", true, false).is_empty(), label + " build must remove buttons")
	var trousers := 0
	var arm_skins := 0
	for mesh_part in doll.rig.meshes:
		if mesh_part.name == "Trouser":
			trousers += 1
		elif mesh_part.name == "ArmSkin":
			arm_skins += 1
	check(trousers == 2, label + " must keep the base trousers")
	check(arm_skins == 2, label + " must add bare arms down to the mittens")
	check(_part(doll, "Neck") != null, label + " build must preserve the body")
	_check_weights(part, label)
	# Hollow openings: one hem loop, a neck loop near the top, and one loop per
	# sleeve hem or armhole. (The Cuban collar band adds its own two loops.)
	var loops := _boundary_loops(part.mesh)
	var hem := loops.filter(func(loop: Array) -> bool: return loop[0] < 1.2)
	var neck := loops.filter(func(loop: Array) -> bool: return loop[0] > 1.75)
	var arm := loops.filter(func(loop: Array) -> bool: return loop[0] > 1.4 and loop[0] <= 1.75)
	check(hem.size() == 1, label + " must have exactly one open hem loop")
	check(neck.size() >= 1, label + " must have a hollow neck opening")
	check(arm.size() == 2, label + " must have two hollow arm openings")
	# Connected shell: hem + neck/collar edge + two sleeve hems, nothing else.
	# A detached sleeve slab or a floating collar strip would add a loop here.
	check(loops.size() == 4, label + " must weld into one shell (4 openings), got %d" % loops.size())
	var topology := _topology(part.mesh)
	check(topology["degenerate"] == 0, label + " has degenerate triangles")
	_check_top_builder(style, label)
	# Skinning survives a walk cycle without exploding.
	for pose in 8:
		doll.rig.animate(TAU * pose / 8.0, 1.0, "idle", pose * 0.3)
		for point in doll.rig.deformed_vertices(part):
			check(point.is_finite(), label + " walk pose produced non-finite vertices")

	return part


# Builder-level contract for the modern tops: a smooth analytic top edge (no
# stair-stepped cutouts), sleeves welded onto the armhole and sloping down the
# arm, and a length parameter that moves the hem only. Style 10 must read as a
# camp/Cuban shirt (open front V with a folded collar), style 11 as a babydoll
# (empire cinch, gather ripple, flared hem, puff sleeves, round neckline).
func _check_top_builder(style: int, label: String) -> void:
	var cuban := style == 10
	var data: Dictionary = Basic.cuban_shirt(.80) if cuban else Basic.babydoll_blouse(.80)
	check(data.slot == "top", label + " must report the top slot")
	check(absf(float(data.hem_y) - (Basic.TOP_HEIGHT - .80)) < .001, label + " hem must sit at TOP_HEIGHT - length")
	var edge: PackedVector3Array = data.top_edge
	check(edge.size() == Basic.SEGMENTS + 1, label + " must export its analytic top edge")
	var max_step := 0.0
	for i in edge.size() - 1:
		max_step = maxf(max_step, absf(edge[i + 1].y - edge[i].y))
	check(max_step < .06, label + " top edge must slope smoothly, not stair-step (max step %.4f)" % max_step)
	var front_low := INF
	for point in edge:
		if point.z > .02 and absf(point.x) < .12:
			front_low = minf(front_low, point.y)
	if cuban:
		check(absf(front_low - 1.705) < .02, label + " camp collar V must open at 1.705, got %.3f" % front_low)
	else:
		check(absf(front_low - 1.775) < .02, label + " round neckline must bottom at 1.775, got %.3f" % front_low)
	var back_high := -INF
	for point in edge:
		if point.z < -.02:
			back_high = maxf(back_high, point.y)
	check(back_high > 1.87, label + " back neck must stay high")
	var vertices: PackedVector3Array = data.vertices
	if cuban:
		var collar: PackedVector3Array = data.get("collar_edge", PackedVector3Array())
		check(collar.size() > 40, label + " must carry camp collar leaves around the neck opening")
		if not collar.is_empty():
			# Flat camp collar: every free-edge point lies on the shirt shell
			# (same torso profile, ~4mm cloth lift) one leaf below the neck
			# seam — a lying leaf, not a tall rolled rim sticking out.
			var flat_max := 0.0
			var collar_low := INF
			var collar_high := -INF
			for point in collar:
				var angle := atan2(point.x, point.z)
				var radii := Basic._cuban_profile(point.y)
				var shell_radius := Vector2(sin(angle) * radii.x, cos(angle) * radii.y).length()
				flat_max = maxf(flat_max, absf(Vector2(point.x, point.z).length() - shell_radius))
				collar_low = minf(collar_low, point.y)
				collar_high = maxf(collar_high, point.y)
			check(flat_max < .012, label + " collar leaves must lie flat on the shell (deviation %.4f)" % flat_max)
			check(collar_high < 1.83, label + " collar must lie below the neck seam, no tall rim (top %.3f)" % collar_high)
			check(collar_low > 1.62, label + " collar lapels must stay above the chest, got %.3f" % collar_low)
			for side in [-1,1]:
				var leaf_tip := INF
				for point in collar:
					if point.x*side > .09 and point.z > .09:
						leaf_tip = minf(leaf_tip,point.y)
				check(leaf_tip < front_low-.02,label+" must have a distinct pointed leaf beside the V")
	else:
		# Empire seam cinches between the bust and the flared sweep.
		var cinch: Vector2 = Basic._babydoll_profile(1.52)
		check(cinch.x < Basic._babydoll_profile(1.66).x - .005, label + " empire seam must cinch under the bust")
		check(Basic._babydoll_profile(1.10).x > cinch.x + .04, label + " hem must flare out from the empire seam")
		# Gather ripple is real geometry: radii vary around the body at 1.45.
		var ripple_low := INF
		var ripple_high := -INF
		for point in vertices:
			if absf(point.y - 1.45) < .012:
				var radius := Vector2(point.x, point.z).length()
				ripple_low = minf(ripple_low, radius)
				ripple_high = maxf(ripple_high, radius)
		check(ripple_high - ripple_low > .02,
			label + " must show gather ripple below the empire seam (%.4f)" % (ripple_high - ripple_low))
		# Puff: the middle sleeve ring balloons past the cinched hem band.
		check(Basic.BABYDOLL_SLEEVE[1][2] > Basic.BABYDOLL_SLEEVE[2][2] + .02,
			label + " sleeve must puff out before the hem band")
	# Connected sloped sleeve: the outer sleeve surface runs from shoulder
	# crown height down the arm to the sleeve hem.
	check(absf(float(data.sleeve_hem_y) - (1.59 if cuban else 1.648)) < .001, label + " sleeve hem height wrong")
	var sleeve_low := INF
	var sleeve_high := -INF
	for point in vertices:
		if absf(point.x) > .30 and point.y > 1.50:
			sleeve_low = minf(sleeve_low, point.y)
			sleeve_high = maxf(sleeve_high, point.y)
	check(sleeve_high > 1.70 and sleeve_low < 1.66,
		label + " sleeve must slope from the shoulder crown down the arm (y %.3f..%.3f)" % [sleeve_low, sleeve_high])
	# The length parameter moves the hem only: neckline, shoulders, collar and
	# sleeve hems keep their absolute heights.
	for length in [.55, 1.05]:
		var sized: Dictionary = Basic.cuban_shirt(length) if cuban else Basic.babydoll_blouse(length)
		check(absf(float(sized.hem_y) - (Basic.TOP_HEIGHT - length)) < .001,
			label + " hem must track garment_length %.2f" % length)
		check(is_equal_approx(float(sized.sleeve_hem_y), float(data.sleeve_hem_y)),
			label + " garment_length must not move the sleeve hem")
		var sized_edge: PackedVector3Array = sized.top_edge
		var moved := 0.0
		for i in mini(edge.size(), sized_edge.size()):
			moved = maxf(moved, (sized_edge[i] - edge[i]).length())
		check(moved < .001, label + " garment_length must not move the neckline/shoulders (moved %.4f)" % moved)
		if cuban:
			var sized_collar: PackedVector3Array = sized.get("collar_edge", PackedVector3Array())
			check(sized_collar.size() == (data.collar_edge as PackedVector3Array).size(),
				label + " garment_length must not change the collar")
	# A non-default length must reach the bound doll mesh, hem only.
	var long_doll := _make(style)
	long_doll.catalog_garment_length = 1.05
	long_doll.configure({"outfit": 2, "palette": 0})
	var long_part := _part(long_doll, label)
	check(long_part != null and absf(_aabb(long_part.mesh).position.y - (Basic.TOP_HEIGHT - 1.05)) < .01,
		"length 1.05 must drop the %s hem to %.2f" % [label, Basic.TOP_HEIGHT - 1.05])


func _check_vest() -> MeshInstance3D:
	var doll := _make(13)
	var part := _part(doll, "SweaterVest")
	check(part != null, "style 13 has no SweaterVest mesh")
	if part == null:
		return null
	check(part.skin != null, "SweaterVest must be bound to the body skin, not static")
	check(part.get_meta("garment_slot", "") == "outer", "SweaterVest needs garment_slot outer metadata")
	check(Definition.part_slot(part) == "outer", "SweaterVest must resolve to the outer part slot")
	check(part.get_meta("semantic", "") == "garment", "SweaterVest must use garment skinning")
	var rib := _part(doll, "SweaterVestRib")
	check(rib != null, "style 13 has no ribbed trim mesh")
	if rib != null:
		check(rib.get_meta("garment_slot", "") == "outer", "SweaterVestRib needs garment_slot outer metadata")
		check(Definition.part_slot(rib) == "outer", "SweaterVestRib must resolve to the outer part slot")
	# The vest is an outer layer: the shirt shell keeps the torso and sleeves.
	check(_part(doll, "TailoredShell") != null, "vest build must keep the shirt shell underneath")
	check(_part(doll, "TailoredShell").get_meta("garment_slot", "top") == "top", "shirt shell must stay in the top slot")
	for removed in ["OpenWaistcoat", "FrontBinding"]:
		check(_part(doll, removed) == null, "vest build must remove " + removed)
	check(doll.body_rig.find_children("ButtonRow", "", true, false).is_empty(), "vest build must remove buttons")
	var cuffs := 0
	var arm_skins := 0
	for mesh_part in doll.rig.meshes:
		if mesh_part.name == "CuffBinding":
			cuffs += 1
		elif mesh_part.name == "ArmSkin":
			arm_skins += 1
	check(cuffs == 2, "shirt cuffs must survive under the vest")
	check(arm_skins == 0, "vest over long sleeves must not add bare arms")
	check(_part(doll, "Neck") != null, "vest build must preserve the continuous neck")
	var mittens := 0
	for mesh_part in doll.rig.meshes:
		if mesh_part.name == "Mitten":
			mittens += 1
	check(mittens == 2, "vest build must preserve the palms")
	_check_weights(part, "SweaterVest")
	if rib != null:
		_check_weights(rib, "SweaterVestRib")
	# Exactly two openings: the hem and one continuous neck/armhole top edge.
	var loops := _boundary_loops(part.mesh)
	check(loops.size() == 4, "SweaterVest must have hem + neck + two armholes, got %d" % loops.size())
	var hem_loops := loops.filter(func(loop: Array) -> bool: return loop[0] < 1.3)
	check(hem_loops.size() == 1 and absf(hem_loops[0][0] - 1.10) < .02, "SweaterVest default hem must sit at 1.90 - 0.80")
	var top_loops := loops.filter(func(loop: Array) -> bool: return loop[0] >= 1.3)
	check(top_loops.size() == 3,
		"SweaterVest shoulders must separate neck and armhole openings")
	var topology := _topology(part.mesh)
	check(topology["degenerate"] == 0, "SweaterVest has degenerate triangles")
	# Analytic builder contract: a full grid (no stair-step skipped quads),
	# smooth top edge, shallow V over the shirt, and a length-driven hem.
	var data: Dictionary = Basic.sweater_vest(.80)
	check(data.slot == "outer", "sweater_vest must report the outer slot")
	var rows := int(data.row_count)
	check((data.vertices as PackedVector3Array).size() == rows * (Basic.SEGMENTS + 1) + 198,
		"vest grid must keep every column of every row (no skipped quads)")
	check((data.indices as PackedInt32Array).size() == (rows - 1) * Basic.SEGMENTS * 6 + 960,
		"vest grid must keep every quad (no skipped quads)")
	var edge: PackedVector3Array = data.top_edge
	check(edge.size() == Basic.SEGMENTS + 1, "vest must export its analytic top edge")
	var max_step := 0.0
	for i in edge.size() - 1:
		max_step = maxf(max_step, absf(edge[i + 1].y - edge[i].y))
	check(max_step < .06, "vest top edge must slope smoothly, not stair-step (max step %.4f)" % max_step)
	check(absf(edge[0].y - 1.66) < .01 and edge[0].z > .1, "vest front V must bottom out shallow at 1.66")
	var edge_high := -INF
	var edge_low := INF
	for point in edge:
		edge_high = maxf(edge_high, point.y)
		edge_low = minf(edge_low, point.y)
	check(edge_high > 1.89, "vest shoulders must rise to the neck")
	check(absf(edge_low - 1.565) < .02, "vest armholes must bottom out at 1.565")
	var trim: Dictionary = data.trim
	check((trim.vertices as PackedVector3Array).size() == 6 * (Basic.SEGMENTS + 1),
		"vest ribbing must band the top edge and the hem")
	for length in [.55, .80, 1.05]:
		var sized: Dictionary = Basic.sweater_vest(length)
		check(absf(float(sized.hem_y) - (1.90 - length)) < .001, "vest hem must track garment_length %.2f" % length)
		check(absf((sized.top_edge as PackedVector3Array)[0].y - 1.66) < .01,
			"garment_length must not move the vest neckline")
	# A non-default length must reach the bound doll mesh, hem only.
	var long_doll := _make(13)
	long_doll.catalog_garment_length = 1.05
	long_doll.configure({"outfit": 2, "palette": 0})
	var long_part := _part(long_doll, "SweaterVest")
	check(long_part != null and absf(_aabb(long_part.mesh).position.y - .85) < .01,
		"length 1.05 must drop the vest hem to 0.85")
	var short_doll := _make(13)
	short_doll.catalog_garment_length = .55
	short_doll.configure({"outfit": 2, "palette": 0})
	var short_part := _part(short_doll, "SweaterVest")
	check(short_part != null and absf(_aabb(short_part.mesh).position.y - 1.35) < .01,
		"length .55 must raise the vest hem to 1.35")
	# Skinning survives a walk cycle without exploding.
	for pose in 8:
		doll.rig.animate(TAU * pose / 8.0, 1.0, "idle", pose * 0.3)
		for point in doll.rig.deformed_vertices(part):
			check(point.is_finite(), "SweaterVest walk pose produced non-finite vertices")
	return part


func _check_skirt() -> MeshInstance3D:
	var doll := _make(12)
	var part := _part(doll, "ModernSkirt")
	check(part != null, "style 12 has no ModernSkirt mesh")
	if part == null:
		return null
	check(part.skin != null, "ModernSkirt must be bound to the body skin, not static")
	check(part.get_meta("garment_slot", "") == "bottom", "ModernSkirt needs garment_slot bottom metadata")
	check(Definition.part_slot(part) == "bottom", "ModernSkirt must resolve to the bottom part slot")
	check(part.get_meta("semantic", "") == "skirt", "ModernSkirt must use skirt hem skinning")
	check(part.get_meta("rest_cloth", false), "ModernSkirt must join the rest-cloth poses")
	check(_part(doll, "Trouser") == null, "skirt build must remove the base trousers")
	check(_part(doll, "TailoredShell") != null, "skirt build keeps the plain shell as the top")
	var calves := 0
	for mesh_part in doll.rig.meshes:
		if mesh_part.name == "Calf":
			calves += 1
	check(calves == 2, "skirt build must add bare calves")
	var loops := _boundary_loops(part.mesh)
	check(loops.size() == 2, "ModernSkirt must be an open tube: waist and hem loops only")
	var waist := loops.filter(func(loop: Array) -> bool: return loop[0] > 1.0)
	check(waist.size() == 1 and absf(waist[0][0] - 1.30) < .01, "ModernSkirt waist must sit at 1.30")
	var hem := loops.filter(func(loop: Array) -> bool: return loop[0] < 1.0)
	check(hem.size() == 1 and absf(hem[0][0] - .65) < .02, "ModernSkirt default hem must sit at 1.30 - length")
	_check_weights(part, "ModernSkirt")
	for pose in 8:
		doll.rig.animate(TAU * pose / 8.0, 1.0, "idle", pose * 0.3)
		for point in doll.rig.deformed_vertices(part):
			check(point.is_finite(), "ModernSkirt walk pose produced non-finite vertices")

	# The length parameter moves the hem only; the waist stays put.
	var long_doll := _make(12)
	long_doll.catalog_skirt_length = 1.05
	long_doll.configure({"outfit": 2, "palette": 0})
	var long_part := _part(long_doll, "ModernSkirt")
	var long_loops := _boundary_loops(long_part.mesh)
	var long_hem := long_loops.filter(func(loop: Array) -> bool: return loop[0] < 1.0)
	var long_waist := long_loops.filter(func(loop: Array) -> bool: return loop[0] > 1.0)
	check(long_hem.size() == 1 and absf(long_hem[0][0] - .25) < .02, "length 1.05 must drop the hem to 0.25")
	check(long_waist.size() == 1 and absf(long_waist[0][0] - 1.30) < .01, "length must not move the waist")
	var long_box := _aabb(long_part.mesh)

	var short_doll := _make(12)
	short_doll.catalog_skirt_length = .35
	short_doll.configure({"outfit": 2, "palette": 0})
	var short_part := _part(short_doll, "ModernSkirt")
	var short_hem := _boundary_loops(short_part.mesh).filter(func(loop: Array) -> bool: return loop[0] < 1.0)
	check(short_hem.size() == 1 and absf(short_hem[0][0] - .95) < .02, "length .35 must raise the hem to 0.95")
	check(_aabb(short_part.mesh).size.y < long_box.size.y - .5, "shorter length must shrink the skirt height")

	return part


func _check_apron_straps() -> void:
	var doll := _make(1, 1)
	# Dressed torso surfaces (tailored shell + skirt) for contact checks.
	# Distance is measured against the real triangles, not the coarse lathe
	# vertices, so a lying strap reads as contact.
	var surfaces := []
	for surface_part in [_part(doll, "TailoredShell"), _part(doll, "LongSkirt")]:
		check(surface_part != null, "apron doll must keep its dressed torso surfaces")
		if surface_part != null:
			var arrays: Array = surface_part.mesh.surface_get_arrays(0)
			surfaces.append([arrays[Mesh.ARRAY_VERTEX], arrays[Mesh.ARRAY_INDEX]])
	for side in ["L", "R"]:
		var strap := _part(doll, "ApronStrapCross" + side)
		check(strap != null, "apron has no continuous crossed strap " + side)
		if strap == null:
			continue
		check(Definition.part_slot(strap) == "outer", "crossed strap must stay in the outer slot")
		var sign := -1.0 if side == "L" else 1.0
		var over_shoulder := false
		var reaches_tie := false
		var crossed := false
		var max_gap := 0.0
		var sunk := INF
		for point in strap.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			# The shoulder crown under the strap tops out at y~1.894; the
			# crest must ride on it (1.885..1.92), not fly above it.
			if point.y > 1.885 and point.y < 1.92 and absf(point.z) < .05 and signf(point.x) == sign:
				over_shoulder = true
			if point.y < 1.33 and point.z < -.1:
				reaches_tie = true
				if signf(point.x) == -sign:
					crossed = true
			if not surfaces.is_empty():
				max_gap = maxf(max_gap, _surface_gap(point, surfaces))
			sunk = minf(sunk, _torso_clearance(point))
		check(over_shoulder, "strap " + side + " must crest on the shoulder crown (~1.90), not fly above it")
		check(reaches_tie, "strap " + side + " must reach the back waist tie")
		check(crossed, "strap " + side + " must cross to the opposite back side")
		check(max_gap < .045, "strap " + side + " must hug the torso, not fly (max gap %.3f)" % max_gap)
		check(sunk > -.006, "strap " + side + " must not sink into the torso (clearance %.4f)" % sunk)
		# Skinning survives a walk cycle without exploding.
		for pose in 8:
			doll.rig.animate(TAU * pose / 8.0, 1.0, "idle", pose * 0.3)
			for point in doll.rig.deformed_vertices(strap):
				check(point.is_finite(), "strap " + side + " walk pose produced non-finite vertices")
	check(_part(doll, "ApronTie") != null, "apron waist tie must survive")


# Signed clearance of a point against the dressed torso ellipse: positive
# outside the TailoredShell silhouette, negative sunk inside it. Points on
# the shoulder crown (beyond the top rings' x extent) read positive.
func _torso_clearance(point: Vector3) -> float:
	var profile: Array = Basic.TORSO_PROFILE
	var rx: float = profile[0][1]
	var rz: float = profile[0][2]
	if point.y > profile.back()[0]:
		return point.y - profile.back()[0]
	for span in profile.size() - 1:
		var a: Array = profile[span]
		var b: Array = profile[span + 1]
		if point.y <= b[0]:
			var t := (point.y - float(a[0])) / (float(b[0]) - float(a[0]))
			rx = lerpf(float(a[1]), float(b[1]), t)
			rz = lerpf(float(a[2]), float(b[2]), t)
			break
	var fx: float = point.x / rx
	var fz: float = point.z / rz
	return (Vector2(fx, fz).length() - 1.0) * minf(rx, rz)


# Distance from a point to the closest triangle of the given surfaces
# (each [vertices, indices]).
func _surface_gap(point: Vector3, surfaces: Array) -> float:
	var gap := INF
	for surface in surfaces:
		var vertices: PackedVector3Array = surface[0]
		var indices: PackedInt32Array = surface[1]
		for face in indices.size() / 3:
			gap = minf(gap, point.distance_to(_closest_on_triangle(point,
				vertices[indices[face * 3]], vertices[indices[face * 3 + 1]],
				vertices[indices[face * 3 + 2]])))
	return gap


# Closest point on a triangle (Ericson, Real-Time Collision Detection 5.1.5).
func _closest_on_triangle(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var ab := b - a
	var ac := c - a
	var ap := p - a
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0:
		return a
	var bp := p - b
	var d3 := ab.dot(bp)
	var d4 := ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3:
		return b
	var vc := d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
		return a + ab * (d1 / (d1 - d3))
	var cp := p - c
	var d5 := ab.dot(cp)
	var d6 := ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6:
		return c
	var vb := d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
		return a + ac * (d2 / (d2 - d6))
	var va := d3 * d6 - d5 * d4
	if va <= 0.0 and (d4 - d3) >= 0.0 and (d5 - d6) >= 0.0:
		return b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6)))
	var denom := 1.0 / (va + vb + vc)
	return a + ab * (vb * denom) + ac * (vc * denom)



func _check_distinct(garments: Dictionary) -> void:
	var boxes := {}
	for style in garments:
		var part: MeshInstance3D = garments[style]
		if part == null:
			continue
		boxes[style] = _aabb(part.mesh)
	for a in boxes:
		for b in boxes:
			if a >= b:
				continue
			var delta: Vector3 = (boxes[a].size - boxes[b].size).abs()
			check(maxf(delta.x, maxf(delta.y, delta.z)) > .02,
				"styles %d and %d must read as distinct silhouettes" % [a, b])


func _check_weights(part: MeshInstance3D, label: String) -> void:
	var arrays := part.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	check(weights.size() == vertices.size() * 4, label + " lost its skin weights")
	for i in vertices.size():
		var total := 0.0
		for slot in 4:
			total += weights[i * 4 + slot]
		check(absf(total - 1.0) < WEIGHT_EPSILON, label + " skin weights not normalized")


func _aabb(mesh: ArrayMesh) -> AABB:
	var box := AABB()
	var first := true
	for point in mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		box = AABB(point, Vector3.ZERO) if first else box.expand(point)
		first = false
	return box


# Welds coincident vertices, then reports triangle/component health.
func _topology(mesh: ArrayMesh) -> Dictionary:
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var raw_indices = arrays[Mesh.ARRAY_INDEX]
	var welded := _weld(vertices)
	var remap: PackedInt32Array = welded[0]
	var degenerate := 0
	for face in raw_indices.size() / 3:
		var corners: PackedInt32Array = raw_indices.slice(face * 3, face * 3 + 3)
		var a := remap[corners[0]]
		var b := remap[corners[1]]
		var c := remap[corners[2]]
		if a == b or b == c or a == c:
			degenerate += 1
			continue
		if (vertices[corners[1]] - vertices[corners[0]]).cross(vertices[corners[2]] - vertices[corners[0]]).length() < 0.000001:
			degenerate += 1
	return {"degenerate": degenerate}


# Boundary loops after welding; each entry is [mean height, edge count].
func _boundary_loops(mesh: ArrayMesh) -> Array:
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var raw_indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var welded := _weld(vertices)
	var remap: PackedInt32Array = welded[0]
	var use := {}
	for face in raw_indices.size() / 3:
		var corners := raw_indices.slice(face * 3, face * 3 + 3)
		for corner in 3:
			var a: int = mini(remap[corners[corner]], remap[corners[(corner + 1) % 3]])
			var b: int = maxi(remap[corners[corner]], remap[corners[(corner + 1) % 3]])
			if a == b:
				continue
			var key := a * 100000 + b
			use[key] = use.get(key, 0) + 1
	var adjacency := {}
	for key in use:
		if use[key] != 1:
			continue
		var a: int = key / 100000
		var b: int = key % 100000
		if not adjacency.has(a):
			adjacency[a] = []
		if not adjacency.has(b):
			adjacency[b] = []
		adjacency[a].append(b)
		adjacency[b].append(a)
	var heights := {}
	for i in remap.size():
		heights[remap[i]] = vertices[i].y
	var loops := []
	var visited := {}
	for start in adjacency:
		if visited.has(start):
			continue
		var size := 0
		var height := 0.0
		var stack := [start]
		while not stack.is_empty():
			var node: int = stack.pop_back()
			if visited.has(node):
				continue
			visited[node] = true
			size += 1
			height += heights[node]
			for next in adjacency[node]:
				if not visited.has(next):
					stack.append(next)
		loops.append([height / size, size])
	return loops


func _weld(vertices: PackedVector3Array) -> Array:
	var slots := {}
	var remap := PackedInt32Array()
	var count := 0
	for point in vertices:
		var key := str(snappedf(point.x, 0.0005)) + "," + str(snappedf(point.y, 0.0005)) + "," + str(snappedf(point.z, 0.0005))
		if not slots.has(key):
			slots[key] = count
			count += 1
		remap.append(slots[key])
	return [remap, count]
