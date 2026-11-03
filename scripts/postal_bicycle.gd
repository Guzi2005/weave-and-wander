extends "res://scripts/shop_room.gd"

var wheels: Array[Node3D] = []
var crank: Node3D
var stand: Node3D
var parking_amount := 0.0


func build() -> void:
	for x in [-.90,.90]:
		var pivot := _group("Wheel",Vector3(x,.48,0))
		wheels.append(pivot)
		var tire := MeshInstance3D.new()
		var ring := TorusMesh.new()
		ring.inner_radius = .407
		ring.outer_radius = .472
		ring.rings = 32
		ring.ring_segments = 8
		tire.mesh = ring
		tire.rotation.x = PI*.5
		tire.material_override = _material(Color("48585d"))
		pivot.add_child(tire)
		for i in 8:
			var a := TAU*i/8
			_rod(pivot,Vector3.ZERO,Vector3(cos(a)*.42,sin(a)*.42,0),.012,Color("c3c9b9"))
		var hub := _cylinder(pivot,"Hub",.075,.15,Vector3.ZERO,GOLD)
		hub.rotation.x = PI*.5
	var rear := Vector3(-.90,.48,0)
	var pedals := Vector3(-.1,.53,0)
	var seat := Vector3(-.28,1.18,0)
	var fork := Vector3(.67,1.25,0)
	var step_through := Vector3(.03,.78,0)
	for endpoints in [[rear,pedals],[rear,seat],[pedals,seat],[seat,step_through],[step_through,fork],[pedals,fork],[fork,Vector3(.9,.48,0)]]:
		_rod(self,endpoints[0],endpoints[1],.04,GREEN)
	_rod(self,seat,Vector3(-.30,1.32,0),.035,INK)
	_box(self,"Saddle",Vector3(.42,.10,.28),Vector3(-.31,1.34,0),Color("665a51"))
	_rod(self,fork,Vector3(.40,1.74,0),.035,INK)
	_rod(self,Vector3(.40,1.74,-.30),Vector3(.40,1.74,.30),.025,GOLD)
	for z in [-.30,.30]:
		_rod(self,Vector3(.40,1.74,z),Vector3(.26,1.715,z),.035,INK)
	_box(self,"PostalCarrier",Vector3(.62,.35,.40),Vector3(-.97,1.12,0),Color("879668"))
	_box(self,"CarrierFlap",Vector3(.64,.06,.43),Vector3(-.97,1.32,0),Color("b4b881"))
	for x in [-1.2,-.75]:
		_rod(self,Vector3(x,1,0),rear,.025,GREEN)
	crank = _group("Pedals",pedals)
	for side in [-1,1]:
		_rod(crank,Vector3(0,0,side*.10),Vector3(side*.16,0,side*.10),.024,INK)
		_box(crank,"Pedal",Vector3(.14,.06,.17),Vector3(side*.16,0,side*.15),INK)
	stand = _group("FoldingKickstand",Vector3(-.21,.53,-.06))
	_rod(stand,Vector3.ZERO,Vector3(-.12,-.49,-.24),.023,Color("65716b"))
	_rod(stand,Vector3(-.19,-.49,-.24),Vector3(-.05,-.49,-.24),.026,Color("65716b"))
	set_parked(0)


func set_parked(amount: float) -> void:
	parking_amount = clampf(amount,0,1)
	stand.visible = parking_amount > .001
	stand.rotation.x = lerpf(-1.35,0,parking_amount)


func _rod(parent: Node3D, a: Vector3, b: Vector3, radius: float, color: Color) -> void:
	var piece := _cylinder(parent,"Tube",radius,a.distance_to(b),(a+b)*.5,color)
	piece.quaternion = Quaternion(Vector3.UP,(b-a).normalized())


func roll(distance: float) -> void:
	for wheel in wheels:
		wheel.rotation.z -= distance/.46
	crank.rotation.z -= distance*2.2
	for pedal in crank.get_children():
		if str(pedal.name).begins_with("Pedal"):
			pedal.rotation.z = -crank.rotation.z
