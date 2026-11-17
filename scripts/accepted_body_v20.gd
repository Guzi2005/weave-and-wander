class_name AcceptedBodyV20
extends "res://scripts/volume_doll.gd"

## Experimental doll subclass with a continuous underbody mannequin
## remodeled strictly to reference the stylized silhouette trend of the fake torso:
## - Slender neck with natural soft sloping shoulders ("自然溜肩", smooth trapezius slope)
## - Arm gradually widening and seamlessly flowing into the mitten hand ("手臂从上到下逐渐加粗与手连接")
## - Natural proud upright posture without hunchback ("驼背修正", straight upper back, forward chest)
## - Plump, rounded, cute peach buttocks and pelvis thickness ("胯部垫厚，圆润翘臀")
## - Cute, plump chibi legs matching overall doll proportions ("饱满软萌Q版腿型")
## - Straight, graceful leg alignment without bow legs ("罗圈腿修正")
## - Balanced, snug shoe heel counter ("鞋子后帮适度贴合脚跟")

var is_underbody_mode := false

func _build_volume_body() -> void:
	super._build_volume_body()
	_build_continuous_mannequin()

func _build_continuous_mannequin() -> void:
	var skin: Color = get_skin_color()

	# Hide original disconnected Neck on this experimental doll so MannequinTorso
	# provides the unified, continuous neck-to-crotch anatomy without seams or giraffe neck.
	var old_neck := body_rig.get_node_or_null("Neck")
	if old_neck != null:
		old_neck.visible = false

	# 1. Unified Torso & Neck Hull:
	# Beautiful, upright chibi mannequin silhouette with natural sloping shoulders ("溜肩")
	# and plump, rounded peach buttocks ("丰满圆润翘臀，胯部厚度自然垫起"):
	# - Slender neck centered directly under the head cranium (Z ≈ +0.030)
	# - Natural sloping shoulders ("自然溜肩") smoothly flowing into upper arms without shoulder ridges
	# - Upright, proud posture: chest projects forward (matching dress front), straight upper back (no hunchback/驼背)
	# - High waistline at Y=1.32 matching the dress waistband
	# - Plump, smooth rounded peach buttocks spanning Y=1.08..1.20 with gentle dome peak at Y=1.14 (Z=-0.180)
	# - Clean crotch closure at Y=1.05 right above leg separation
	var torso_rings := [
		Vector3(1.05, .068, .110), # 0: crotch bottom closure (safely nested inside thigh confluence)
		Vector3(1.08, .205, .152), # 1: lower buttock curve / subgluteal crease
		Vector3(1.12, .228, .166), # 2: buttock dome lower peak
		Vector3(1.16, .230, .166), # 3: cute rounded chibi peach buttock dome upper peak ("圆润翘臀")
		Vector3(1.20, .222, .156), # 4: upper buttock curve
		Vector3(1.24, .208, .144), # 5: upper hip & lumbar transition
		Vector3(1.28, .188, .134), # 6: lower waist
		Vector3(1.32, .176, .130), # 7: natural high waist (subtle, soft flow matching blue dress)
		Vector3(1.45, .185, .136), # 8: mid torso
		Vector3(1.58, .195, .142), # 9: smooth chest (cute chibi volume, proud posture)
		Vector3(1.70, .198, .138), # 10: upper chest
		Vector3(1.78, .190, .130), # 11: rounded natural sloping shoulder curve ("自然溜肩")
		Vector3(1.84, .152, .114), # 12: gentle trapezius slope
		Vector3(1.90, .116, .096), # 13: neck-to-shoulder transition
		Vector3(1.96, .086, .080), # 14: slender lower neck column
		Vector3(2.02, .078, .076), # 15: slender mid neck
		Vector3(2.09, .076, .074), # 16: delicate neck entering head cranium
	]
	var torso_z_offsets := [
		0.004,  # 1.05: crotch apex (-0.106 back)
		-0.008, # 1.08: lower buttock (-0.160 back)
		-0.014, # 1.12: buttock lower dome (-0.180 back)
		-0.014, # 1.16: buttock upper dome (-0.180 back - beautifully rounded peach dome!)
		-0.010, # 1.20: upper buttock (-0.166 back)
		-0.005, # 1.24: lumbar transition (-0.149 back)
		0.000,  # 1.28: lower waist (-0.134 back)
		0.006,  # 1.32: high waist (-0.124 back)
		0.012,  # 1.45: mid torso
		0.022,  # 1.58: proud chest forward (+0.164 front, eliminates hunchback)
		0.024,  # 1.70: upper chest (+0.162 front)
		0.020,  # 1.78: sloping shoulder line (-0.110 back, upright straight back)
		0.016,  # 1.84: shoulder slope (-0.098 back)
		0.018,  # 1.90: trapezius slope (-0.078 back)
		0.024,  # 1.96: lower neck (-0.056 back)
		0.028,  # 2.02: mid neck (-0.048 back)
		0.030,  # 2.09: neck top directly under cranium center (+0.035)
	]
	var torso_mesh := _lathe(body_rig, "MannequinTorso", torso_rings, skin, 32, 0.0, true, [], torso_z_offsets)
	torso_mesh.set_meta("garment_slot", "")
	torso_mesh.set_meta("is_underbody", true)

	# 2. Arms & Hands:
	# Continuous, tapering arm lathe extending all the way into the mitten hand:
	# - Shoulder root starts flush inside the sloping shoulder so no joint pokes out ("溜肩平滑过渡")
	# - Arm gradually widens from shoulder to wrist and smoothly flows into the hand ("手臂从上到下逐渐加粗与手连接")
	for index in arms.size():
		var arm: Node3D = arms[index]
		var side: float = -1.0 if index == 0 else 1.0
		var arm_rings := [
			Vector3(-0.90, .018, .016),  # hand tip closure
			Vector3(-0.86, .058, .050),  # fingertips rounded curve
			Vector3(-0.80, .084, .076),  # mitten hand body
			Vector3(-0.72, .090, .082),  # palm / wrist-to-hand seamless flare
			Vector3(-0.62, .086, .080),  # lower forearm / wrist
			Vector3(-0.50, .076, .072),  # forearm (widening downwards)
			Vector3(-0.36, .064, .062),  # elbow / mid arm
			Vector3(-0.22, .052, .050),  # bicep / upper arm
			Vector3(-0.10, .042, .042),  # upper arm under shoulder
			Vector3(-0.01, .030, .030),  # shoulder root (flush with sloping shoulder line, zero poke-out)
		]
		var arm_x_offsets := [
			side * 0.145,
			side * 0.145,
			side * 0.145,
			side * 0.145,
			side * 0.134,
			side * 0.108,
			side * 0.078,
			side * 0.050,
			side * 0.024,
			side * 0.005,
		]
		var arm_z_offsets := [
			0.030,
			0.030,
			0.028,
			0.026,
			0.024,
			0.020,
			0.015,
			0.012,
			0.014,
			0.018,
		]
		var arm_mesh := _lathe(arm, "ArmMannequin", arm_rings, skin, 28, 0.0, true, arm_x_offsets, arm_z_offsets)
		arm_mesh.position.z = 0.0
		arm_mesh.set_meta("garment_slot", "")
		arm_mesh.set_meta("is_underbody", true)

		# Cute integrated thumb ellipsoid resting naturally at inner front of hand
		var thumb_node := _ellipsoid(arm, "ArmMannequinThumb",
			Vector3(side * 0.088, -0.72, 0.062),
			Vector3(0.036, 0.056, 0.040), skin)
		thumb_node.set_meta("garment_slot", "")
		thumb_node.set_meta("is_underbody", true)

	# 3. Plump, Cute Chibi Legs (LegMannequin):
	# Substantially thickened, adorable chibi legs matching the cute doll aesthetic
	# with smooth, continuous under-buttock transition:
	# - Full, rounded thighs and calves properly proportioned to body and head
	# - Thigh back smoothly blends into the plump rounded peach buttocks
	# - Leg axis runs straight and vertical from hip to ankle (hip 0.136, knee 0.134, ankle 0.132)
	# - Completely eliminates bow legs ("罗圈腿")
	# - Natural crotch arch closure touching at apex
	# - Accurate joint positions: smooth gluteal fold, patella front curve, popliteal crease,
	#   gastrocnemius calf belly, achilles tendon, and graceful ankle cleanly inserting into shoe
	for index in legs.size():
		var leg: Node3D = legs[index]
		var side: float = -1.0 if index == 0 else 1.0

		# Hide original disconnected Trouser and Calf meshes on experimental doll
		var old_calf := leg.get_node_or_null("Calf")
		if old_calf != null:
			old_calf.visible = false
		var old_trouser := leg.get_node_or_null("Trouser")
		if old_trouser != null:
			old_trouser.visible = false

		var leg_rings := [
			Vector3(-0.93, .072, .072),  # 0: ankle insert into shoe upper
			Vector3(-0.88, .076, .076),  # 1: ankle joint (cute plump chibi ankle)
			Vector3(-0.78, .084, .084),  # 2: lower calf / achilles tendon
			Vector3(-0.66, .094, .094),  # 3: mid calf
			Vector3(-0.52, .104, .106),  # 4: calf belly (chubby gastrocnemius curve)
			Vector3(-0.40, .098, .100),  # 5: knee joint (patella front, popliteal crease rear)
			Vector3(-0.32, .102, .106),  # 6: above knee
			Vector3(-0.22, .110, .116),  # 7: mid thigh (full rounded chibi thigh)
			Vector3(-0.10, .122, .126),  # 8: upper thigh (blending with under-buttock crease)
			Vector3(-0.02, .142, .136),  # 9: crotch confluence & gluteal fold
			Vector3(0.06, .116, .146),   # 10: hip socket insert (nestled inside plump buttock)
		]
		var leg_x_offsets := [
			-side * 0.018,  # world X = side * 0.132 (ankle)
			-side * 0.018,  # world X = side * 0.132
			-side * 0.017,  # world X = side * 0.133
			-side * 0.017,  # world X = side * 0.133
			-side * 0.017,  # world X = side * 0.133 (calf belly)
			-side * 0.016,  # world X = side * 0.134 (knee joint - strictly aligned, never bowing out)
			-side * 0.015,  # world X = side * 0.135
			-side * 0.015,  # world X = side * 0.135
			-side * 0.014,  # world X = side * 0.136
			-side * 0.014,  # world X = side * 0.136 (crotch confluence)
			-side * 0.014,  # world X = side * 0.136 (hip joint)
		]
		var leg_z_offsets := [
			0.040,  # ankle insert (matches shoe upper collar)
			0.034,  # ankle joint
			0.026,  # lower calf
			0.020,  # mid calf
			0.018,  # calf belly (smooth posterior swell)
			0.024,  # knee joint (patella forward curve)
			0.016,  # above knee
			0.008,  # mid thigh
			-0.002, # upper thigh (under buttock)
			-0.010, # crotch / subgluteal crease
			-0.016, # hip socket (emerges smoothly from plump buttock peak)
		]
		var leg_mesh := _lathe(leg, "LegMannequin", leg_rings, skin, 28, 0.0, true, leg_x_offsets, leg_z_offsets)
		leg_mesh.position.z = 0.0
		leg_mesh.set_meta("garment_slot", "")
		leg_mesh.set_meta("is_underbody", true)

func set_underbody_mode(underbody_only: bool) -> void:
	is_underbody_mode = underbody_only
	if clothes_root != null:
		clothes_root.visible = not underbody_only
	var skinned := body_rig.get_node_or_null("SkinnedMeshes")
	if skinned != null:
		var g := skinned.get_node_or_null("garment")
		if g != null: g.visible = not underbody_only
		var s := skinned.get_node_or_null("skirt")
		if s != null: s.visible = not underbody_only
		var t := skinned.get_node_or_null("torso")
		if t != null:
			for ch in t.get_children():
				if not ch.has_meta("is_underbody"):
					ch.visible = not underbody_only
		for suffix in ["L", "R"]:
			var arm_node := skinned.get_node_or_null("arm" + suffix)
			if arm_node != null:
				for ch in arm_node.get_children():
					if not ch.has_meta("is_underbody"):
						ch.visible = not underbody_only

	# Hide/show unskinned arm details (WristDetails containing old mitten, thumb, and cuff rings)
	for arm in arms:
		var wrist := arm.get_node_or_null("WristDetails")
		if wrist != null:
			wrist.visible = not underbody_only
		var mannequin_arm := arm.get_node_or_null("ArmMannequin")
		if mannequin_arm != null:
			mannequin_arm.visible = underbody_only
		var mannequin_thumb := arm.get_node_or_null("ArmMannequinThumb")
		if mannequin_thumb != null:
			mannequin_thumb.visible = underbody_only

	# Manage leg mannequin visibility
	for leg in legs:
		var leg_mannequin := leg.get_node_or_null("LegMannequin")
		if leg_mannequin != null:
			leg_mannequin.visible = true
		var calf := leg.get_node_or_null("Calf")
		if calf != null:
			calf.visible = false
		var trouser := leg.get_node_or_null("Trouser")
		if trouser != null:
			trouser.visible = false
