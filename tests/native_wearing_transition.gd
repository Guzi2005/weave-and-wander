extends "res://tests/native_wearing_capture.gd"
## Isolated runtime-path gate. Does not install a new garment in the game.

const REVIEW_PROOF := "res://captures/wearing_seamed_simulation_nap0_blender_waist_review.json"
var transition_samples: Array = []
var transition_topology: Array = []
var transition_parts: Array[MeshInstance3D] = []
var support_geometry := {}
var transition_images: Array[Image] = []


func _record_transition(doll: Node3D, phase: String, step: int) -> void:
	var samples: Array = []
	for part in transition_parts:
		var points: Array = []
		for vertex: Vector3 in doll.rig.deformed_vertices(part):
			var p: Vector3 = doll.rig.skeleton.to_global(vertex)
			_check(p.is_finite(), "Nonfinite runtime transition geometry")
			points.append([p.x, p.y, p.z])
		samples.append(points)
	_check(_body_signature(doll) == body_signatures[0], "Runtime proof changed the accepted body or bone rests")
	transition_samples.append({"phase": phase, "step": step, "seconds": step / 60.0,
		"rest_blend": doll._rest_blend, "vertices": samples})


func _run() -> void:
	var gpu := DisplayServer.get_name() != "headless"
	var proof := REVIEW_PROOF
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--proof="): proof = arg.trim_prefix("--proof=")
		else: _check(false, "Unknown argument: " + arg)
	var data := _read_dictionary(proof)
	var source_path := _dependency(str(data.get("source", "")), proof, str(data.get("source_sha256", "")))
	if source_path.is_empty():
		quit(1)
		return
	var source := _read_dictionary(source_path)
	_source_hashes(source)
	input_hashes["res://tests/native_wearing_transition.gd"] = FileAccess.get_sha256("res://tests/native_wearing_transition.gd")
	input_hashes["res://tests/native_wearing_capture.gd"] = FileAccess.get_sha256("res://tests/native_wearing_capture.gd")
	input_hashes["res://tests/experiments/native_layer_transfer.gd"] = FileAccess.get_sha256("res://tests/experiments/native_layer_transfer.gd")
	if not failures.is_empty():
		quit(1)
		return
	_setup_stage()
	for i in dolls.size():
		var actor: Node3D = dolls[i]
		var entry: Marker3D = benches[i].reserve(actor, true)
		_check(entry != null, "Runtime approach reservation failed")
		if entry == null: continue
		# Production actors arrive at this marker before support_actor is called.
		actor.global_position = entry.global_position
		actor._moving = false
		actor.nap_pose = 0
		benches[i].show()
		benches[i].support_actor(actor)
	_settle(150)
	_check_supports(true, 0)
	var doll: Node3D = dolls[0]
	var skirt: MeshInstance3D = doll.body_rig.find_child("LongSkirt", true, false)
	var before := _actor_signature(doll)
	if source.has("mesh_seam"):
		var split := SeamSplit.split(skirt.mesh, float(source.mesh_seam.height))
		_check(split.error.is_empty(), str(split.error))
		if split.error.is_empty(): skirt.mesh = split.mesh
	_validate_geometry(doll, skirt, source, data)
	if failures.is_empty():
		_install_native(skirt, data)
		var transfer := LayerTransfer.new()
		transfer.surface_follow = true
		transfer.derive_ribbons(doll, skirt)
		var transfer_report := transfer.run(doll, skirt)
		for failure: String in transfer.failures: _check(false, failure)
		_check(transfer_report.unbound_count == 0, "Unbound garment layer")
		transition_parts.assign([skirt])
		transition_parts.append_array(transfer.changed)
		for part in transition_parts:
			_disable_contact(part)
			_check(part.mesh.get_blend_shape_count() == skirt.mesh.get_blend_shape_count(), "Runtime rest channel count differs: " + str(part.name))
			for i in part.mesh.get_blend_shape_count():
				_check(part.mesh.get_blend_shape_name(i) == skirt.mesh.get_blend_shape_name(i), "Runtime rest channel order differs: " + str(part.name))
			var arrays := part.mesh.surface_get_arrays(0)
			_check(arrays[Mesh.ARRAY_TEX_UV2] != null and arrays[Mesh.ARRAY_TEX_UV2].size() == arrays[Mesh.ARRAY_VERTEX].size(), "Missing runtime motion coordinates: " + str(part.name))
	_check(_actor_signature(doll) == before, "Installing the corrective altered the actor")
	if not failures.is_empty():
		viewport.free()
		print("NATIVE_WEARING_TRANSITION FAIL ", failures)
		quit(1)
		return
	var endpoint := _geometry_packet(doll, transition_parts, benches[0])
	for part: MeshInstance3D in doll.rig.meshes:
		if part.get_meta("is_underbody", false) and part.get_meta("semantic", "") in ["torso", "legL", "legR"]:
			transition_parts.append(part)
	for part in transition_parts:
		var arrays := part.mesh.surface_get_arrays(0)
		transition_topology.append({"name": str(doll.body_rig.get_path_to(part)),
			"role": "body" if part.get_meta("is_underbody", false) else "cloth", "indices": Array(arrays[Mesh.ARRAY_INDEX])})
	support_geometry = endpoint.parts[-1].duplicate(true)
	var support_points: Array = []
	for p in support_geometry.vertices:
		var world: Vector3 = doll.rig.skeleton.to_global(Vector3(p[0], p[1], p[2]))
		support_points.append([world.x, world.y, world.z])
	support_geometry.vertices = support_points
	viewport.size = Vector2i(640, 480)
	for phase in ["exit", "enter"]:
		if phase == "exit": benches[0].release(doll)
		else:
			_check(benches[0].reserve(doll, true) != null, "Cannot reserve runtime bench")
			benches[0].support_actor(doll)
		for step in 151:
			if step > 0: doll.simulate(1.0 / 60.0, 1.0)
			if step % 5 == 0: _record_transition(doll, phase, step)
			if gpu and step in [15, 30, 150]:
				caption.text = "%s step %d | blend %.3f" % [phase, step, doll._rest_blend]
				var bounds: AABB = _sample(doll, {"name": phase}).bounds
				_frame(_bench_bounds(benches[0], bounds), "side")
				for frame in 3: await process_frame
				await RenderingServer.frame_post_draw
				var rendered := viewport.get_texture().get_image()
				_image_stats(rendered)
				transition_images.append(rendered)
		_check(doll._rest_blend < .001 if phase == "exit" else doll._rest_blend > .999, "Runtime transition did not settle: " + phase)
	var name := proof.get_file().get_basename() + "_runtime_transition"
	for path: String in input_hashes: _check(FileAccess.get_sha256(path) == input_hashes[path], "Input changed during runtime check: " + path)
	if gpu and failures.is_empty():
		_check(transition_images.size() == 6, "Incomplete runtime GPU frames")
		var sheet := Image.create_empty(1920, 960, false, Image.FORMAT_RGB8)
		for i in transition_images.size():
			transition_images[i].convert(Image.FORMAT_RGB8)
			sheet.blit_rect(transition_images[i], Rect2i(Vector2i.ZERO, viewport.size), Vector2i((i % 3) * 640, (i / 3) * 480))
		_check(sheet.save_png(OUTPUT + name + ".png") == OK, "Runtime sheet write failed")
	_write_json(name + ".json", {"experimental_not_accepted": true, "transition_validated": false,
		"method": "Native endpoint as a normalized RestNap corrective; actual reserve/support/simulate/release, not Blender cache playback",
		"scope": "Style0/nap0, both directions, 62 samples at 60Hz; listed clothing contact and secondary disabled; not collision acceptance",
		"coordinate_space": "Godot world", "input_sha256": input_hashes, "proof": proof,
		"parts": transition_topology, "support": support_geometry, "frames": transition_samples,
		"gpu": RenderingServer.get_video_adapter_name() if gpu else "headless",
		"failures": failures, "body_and_rest_unchanged": _body_signature(doll) == body_signatures[0]})
	viewport.free()
	print("NATIVE_WEARING_TRANSITION %s samples=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL", transition_samples.size(), str(failures)])
	quit(0 if failures.is_empty() else 1)
