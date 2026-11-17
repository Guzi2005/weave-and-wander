extends "res://tests/layered_cloth_capture.gd"

var experiment_prefix := ""


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("REST_CONTACT_ISOLATION requires GPU")
		quit(1)
		return
	create_timer(180).timeout.connect(func() -> void: quit(1))
	_setup_stage()
	contact_evaluator = true
	_prepare_rest(true)
	var records: Array = []
	var geometry: Array = []
	for variant in 4:
		for doll in dolls: doll.nap_pose = variant
		_settle(150)
		_check_supports(true, variant)
		for contact_mode: String in ["raw", "nearest", "contact"]:
			var enabled := contact_mode != "raw"
			for doll in dolls:
				for material in doll.body_contact.materials:
					material.set_shader_parameter("cloth_contact_enabled", enabled)
				for garment in doll.rig.meshes:
					if garment.get_meta("semantic", "") in ["skirt", "apron"]:
						garment.material_override.set_shader_parameter("cloth_skirt_side", contact_mode != "nearest")
				var part: MeshInstance3D = doll.body_rig.find_child("LongSkirt", true, false)
				if part == null: continue
				var rest: PackedVector3Array = part.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
				var posed: PackedVector3Array = doll.rig.deformed_vertices(part)
				var contacted: PackedVector3Array = doll.body_contact.evaluate_vertices(part)
				var seams := {}
				var raw_gap := 0.0
				var contact_gap := 0.0
				var worst := []
				for i in rest.size():
					var key := Vector3i((rest[i] * 100000).round())
					if not seams.has(key): seams[key] = i
					var other: int = seams[key]
					raw_gap = maxf(raw_gap, posed[i].distance_to(posed[other]))
					var gap := contacted[i].distance_to(contacted[other])
					if gap > contact_gap:
						contact_gap = gap
						worst = [i, other, str(rest[i])]
				records.append({"style": doll.outfit_style, "nap": variant, "mode": contact_mode,
					"raw_seam_gap": raw_gap, "contact_seam_gap": contact_gap, "worst": worst})
				print("REST_SEAM ", records.back())
				if doll.outfit_style == 0 and contact_mode in ["raw", "contact"]:
					var entry := {"pose": variant, "mode": contact_mode, "skirt": {}, "body": []}
					entry.skirt = {"vertices": _json_points(contacted), "raw": _json_points(posed),
						"indices": Array(part.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX])}
					for body in doll.rig.meshes:
						if str(body.name) not in ["LegMannequin", "MannequinTorso"]: continue
						entry.body.append({"name": str(body.name), "vertices": _json_points(doll.rig.deformed_vertices(body)),
							"indices": Array(body.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX])})
					geometry.append(entry)
			await _capture_pose({"name": experiment_prefix + "isolate_%s_sleep_%d" % [contact_mode, variant]}, true, true)
	_write_json(experiment_prefix + "rest_contact_isolation.json", {"records": records, "captures": captures, "failures": failures,
		"gpu": RenderingServer.get_video_adapter_name()})
	_write_json(experiment_prefix + "rest_contact_geometry.json", geometry)
	viewport.free()
	print("REST_CONTACT_ISOLATION ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)


func _json_points(points: PackedVector3Array) -> Array:
	var output: Array = []
	for p in points: output.append([p.x, p.y, p.z])
	return output
