extends "res://tests/rest_contact_isolation_capture.gd"


func _initialize() -> void:
	experiment_prefix = "rejected_wearing_"
	super()


func _setup_stage() -> void:
	super()
	for doll in dolls:
		preload("res://tests/experiments/rejected_centroid_pose_binding.gd").install(doll)
		doll.body_contact.setup(doll)
		_check(_body_signature(doll) == body_signatures[doll.outfit_style], "Wear binding altered body")
