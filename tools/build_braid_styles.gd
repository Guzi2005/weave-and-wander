extends SceneTree
const Braid = preload("res://components/path_braid.gd")

func _initialize() -> void:
	var legacy: Braid = load("res://assets/collections/node_styles/legacy-single.tres")
	var double := Braid.new()
	double.construction = 1
	double.style_id = "double-yak"
	double.wrap_count = 2
	double.width = .128
	double.depth = .062
	double.pitch = .35
	double.hair_color = Color("29252b")
	double.strand_sides = 12
	double.subdivisions = 768
	double.tail_taper = .06
	double.path = Curve3D.new()
	var points := PackedVector3Array()
	# Two distinct broad courses joined behind the crown; a hidden tail tucks in.
	for i in 49:
		var turn := float(i)/24
		var a := -PI+TAU*turn
		var upper := smoothstep(.87,1.10,turn)
		var rx := lerpf(.345,.30,upper)
		var rz := lerpf(.32,.28,upper)
		points.append(Vector3(sin(a)*rx,lerpf(.42,.635,upper)+.045*cos(a)+.025*sin(a),cos(a)*rz))
	points.append(Vector3(-.06,.60,-.19))
	for i in points.size():
		var tangent := (points[mini(i+1,points.size()-1)]-points[maxi(i-1,0)])/6.0
		double.path.add_point(points[i],-tangent,tangent)
	ResourceSaver.save(double,"res://assets/collections/mosuo_braid.tres")
	ResourceSaver.save(double,"res://assets/collections/node_styles/double-yak.tres")
	for entry in [["double-loose",.12,.065,.48,"29252b"],["double-dense",.128,.052,.23,"29252b"],["double-soft",.15,.078,.40,"383136"]]:
		var recipe: Braid = double.duplicate(true)
		recipe.style_id = entry[0]
		recipe.width = entry[1]
		recipe.depth = entry[2]
		recipe.pitch = entry[3]
		recipe.hair_color = Color(entry[4])
		ResourceSaver.save(recipe,"res://assets/collections/node_styles/"+entry[0]+".tres")
	var copper: Braid = legacy.duplicate(true)
	copper.style_id = "single-copper"
	copper.hair_color = Color("82513c")
	copper.width = .10
	copper.pitch = .23
	ResourceSaver.save(copper,"res://assets/collections/node_styles/single-copper.tres")
	print("BRAID_STYLES_SAVED six deterministic presets; legacy preserved")
	quit()
