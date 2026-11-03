extends SceneTree

const Data = preload("res://assets/rest_cloth/nap_gravity.tres")
const Cloth = preload("res://scripts/rest_cloth.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok and message not in failures:
		failures.append(message)
		push_error(message)

func surface_point(ring: int, t: float, angle: float) -> Vector3:
	var radius: Vector2 = Data.RADII[ring].lerp(Data.RADII[ring+1],t)
	return Vector3(radius.x*sin(angle),lerpf(Data.RINGS[ring],Data.RINGS[ring+1],t),radius.y*cos(angle))

func _run() -> void:
	check(Data.offsets.size() == 4*8*40,"Incomplete gravity bake")
	for value in Data.offsets: check(is_finite(value),"Nonfinite baked offset")
	for variant in 4:
		for ring in 7:
			for angle in [.0,.37,1.9,4.4,TAU-.001]:
				var a := surface_point(ring,0.0,angle)
				var b := surface_point(ring,1.0,angle)
				var middle := surface_point(ring,.5,angle)
				check(absf(Data.sample(middle,variant)-(Data.sample(a,variant)+Data.sample(b,variant))*.5)<.0001,"Ring interpolation overshoots or jumps")
				for p in [a,middle,b]:
					var authored: Vector3 = Cloth.point(p,true,variant,false)
					var settled: Vector3 = Cloth.point(p,true,variant,true)
					check(settled.is_finite(),"Gravity generated a nonfinite vertex")
					check(absf(settled.y-authored.y)<.000001 and absf(settled.z-authored.z)<.000001,"Gravity changed the approved horizontal drape")
					check(Cloth.point(p,false,variant,true).is_equal_approx(Cloth.point(p,false,variant,false)),"Nap bake changed seated clothing")
			var seam_a := surface_point(ring,.5,-.000001)
			var seam_b := surface_point(ring,.5,.000001)
			check(absf(Data.sample(seam_a,variant)-Data.sample(seam_b,variant))<.0001,"Lathe seam has a gravity discontinuity")
			if ring > 0:
				var before := surface_point(ring-1,.999999,.83)
				var after := surface_point(ring,.000001,.83)
				check(absf(Data.sample(before,variant)-Data.sample(after,variant))<.0001,"Ring boundary has a gravity discontinuity")
		for height in [-10.0,.0,1.30,1.31,4.0]:
			var p := Vector3(.13,height,.2)
			check(is_finite(Data.sample(p,variant)),"Out-of-range height is nonfinite")
			if height >= 1.30:
				check(is_zero_approx(Data.sample(p,variant)),"Pinned waist moves")
				check(Cloth.point(p,true,variant)==p,"Waist attachment moved")
	var sample := surface_point(1,.3,.67)
	check(is_equal_approx(Data.sample(sample,-10),Data.sample(sample,0)),"Negative pose index is not clamped")
	check(is_equal_approx(Data.sample(sample,20),Data.sample(sample,3)),"High pose index is not clamped")
	print("NAP_GRAVITY_CHECK checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
