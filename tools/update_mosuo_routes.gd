extends SceneTree
const Beads = preload("res://components/seed_bead_bundle.gd")
func _initialize() -> void:
	var beads = Beads.photo_001()
	beads.path = Curve3D.new()
	var points := PackedVector3Array([Vector3(0,.42,-.26),Vector3(.29,.23,-.23),Vector3(.34,.04,-.02),Vector3(.24,-.16,.125),Vector3(.18,-.30,.17),Vector3(.16,-.56,.19),Vector3(.16,-.80,.205),Vector3(.17,-1.12,.25),Vector3(.18,-1.48,.31)])
	for i in points.size():
		var tangent: Vector3 = (points[mini(i+1,points.size()-1)]-points[maxi(i-1,0)])/6
		beads.path.add_point(points[i],-tangent,tangent)
	beads.max_beads = 96000
	ResourceSaver.save(beads,"res://assets/collections/mosuo_seed_beads.tres")
	quit()
