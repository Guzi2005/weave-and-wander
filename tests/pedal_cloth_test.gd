extends SceneTree
const Contact = preload("res://scripts/pedal_cloth_contact.gd")
var samples := 0
var corrected := 0
var failures := 0
func _initialize(): run.call_deferred()
func run():
	for type in [preload("res://scripts/volume_doll.gd"),preload("res://scripts/experimental_full_body_doll.gd"),preload("res://scripts/ukrainian_doll.gd")]:
		var doll = type.new()
		root.add_child(doll)
		doll.configure({"outfit":0})
		doll.set_process(false)
		var contact = Contact.new()
		for phase in 6:
			doll.rig.animate(0,0,"idle",0)
			doll.rig.pose_rest("sit",1.0)
			for side in ["L","R"]:
				var x := -.15 if side=="L" else .15
				var cycle := sin(phase*TAU/6+(PI if side=="L" else 0))
				doll.rig.place_foot(side,Vector3(x,.42+.06*cycle,.50+.10*cycle))
			contact.last_update=-1000
			contact.update(doll.rig)
			corrected+=contact.projected_count
			for instance in contact.copies.values():
				var arrays: Array = instance.mesh.surface_get_arrays(0)
				var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				for p in points:
					if not p.is_finite(): failures+=1
					for side in ["L","R"]:
						var knee: Vector3 = doll.rig.global_pose(doll.rig.bones["Shin"+side]).origin
						var ankle: Vector3 = doll.rig.global_pose(doll.rig.bones["Foot"+side]).origin
						samples+=1
						if Contact.project(p,knee,ankle,.110).distance_to(p)>.001: failures+=1
			contact.clear()
			for source in contact.copies:
				if not source.visible or contact.copies[source].visible: failures+=1
		doll.free()
	print("PEDAL_CLOTH samples=",samples," corrected=",corrected," failures=",failures)
	quit(0 if failures==0 and samples>0 and corrected>0 else 1)
