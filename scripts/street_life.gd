extends Node3D

const Doll = preload("res://scripts/volume_doll.gd")
const PostalDoll = preload("res://scripts/postal_doll.gd")
const Bicycle = preload("res://scripts/postal_bicycle.gd")
const MOUNT_SECONDS := 1.2
const SADDLE_OFFSET := Vector3(-.26,.16,0)
const STANDING_OFFSET := Vector3(-.26,0,.80)
@export var subscribed_publications: Array[String] = ["地方生活"]
var controller: Node
var pedestrians: Array[PaperDoll] = []
var postman: PaperDoll
var bicycle: Node3D
var postal_stage := "waiting"
var last_visit_day := 0
var deliveries: Array[Dictionary] = []
var _delivery_wait := 0.0
var _delivery_stack: Node3D
var _bike_speed := 0.0
var _mount_clock := 0.0
var _mount_origin := Vector3.ZERO
var _mount_target := Vector3.ZERO
var _visit_publications: Array[String] = []


func _ready() -> void:
	for i in 6:
		var person := Doll.new()
		person.configure({"name":"行人%d"%i,"role":"pedestrian","hair":i%3,"outfit":i%3,"palette":i%4,"skin":i%4,"hair_color":(i+1)%4,"speed":1.05+i*.1})
		person.position = Vector3(-27+i*10,0,6.75+(i%3)*1.45)
		person.scale *= .87+(i%3)*.065
		person.set_meta("direction",1 if i%2 else -1)
		add_child(person)
		person.set_destination(Vector3(50*int(person.get_meta("direction")),0,person.position.z),"walking")
		person._task_badge.hide()
		pedestrians.append(person)
	bicycle = Bicycle.new()
	bicycle.name = "PostalBicycle"
	add_child(bicycle)
	bicycle.position = Vector3(-38,0,6.0)
	bicycle.hide()
	postman = PostalDoll.new()
	postman.configure({"name":"邮递员","role":"postman","hair":1,"outfit":0,"palette":2,"skin":1,"hair_color":0,"speed":1.5})
	postman.name = "Postman"
	postman.arrived.connect(_arrived)
	add_child(postman)
	postman.hide()
	postman._task_badge.hide()
	_delivery_stack = Node3D.new()
	_delivery_stack.name = "DeliveredPeriodicals"
	controller._shop.get_node("CheckoutCounter").add_child(_delivery_stack)
	_delivery_stack.position = Vector3(-.5,1.23,.27)
	for i in 3:
		var page: MeshInstance3D = controller._shop._box(_delivery_stack,"Publication",Vector3(.5,.018,.34),Vector3(i*.014,i*.025,0),Color("efecdc"))
		page.rotation.y = -.12+i*.1
	controller._shop._box(_delivery_stack,"CoverPicture",Vector3(.16,.008,.23),Vector3(-.12,.072,0),Color("498d80"))
	controller._shop._box(_delivery_stack,"CoverBand",Vector3(.43,.008,.045),Vector3(.02,.074,-.11),Color("bb6475"))
	_delivery_stack.hide()


func simulate(delta: float, day: int, minutes: float) -> void:
	if delta <= 0:
		return
	postman._task_badge.hide()
	for person in pedestrians:
		person.simulate(delta,1)
		if not person.is_moving():
			var direction: int = person.get_meta("direction")
			person.position.x = -direction*50
			person.set_destination(Vector3(direction*50,0,person.position.z),"walking")
		person._task_badge.hide()
	if postal_stage == "waiting" and day > last_visit_day and minutes >= 9*60+15 and minutes < 12*60:
		last_visit_day = day
		_visit_publications.assign(subscribed_publications)
		postal_stage = "arriving" if not _visit_publications.is_empty() else "passing"
		bicycle.position = Vector3(-38,0,6)
		bicycle.set_parked(0)
		_bike_speed = 4.5
		bicycle.show()
		postman.show()
		postman.riding = true
	if postal_stage in ["arriving","passing","departing"]:
		var target := 2.6 if postal_stage == "arriving" else 50.0
		var before := bicycle.position.x
		var desired_speed := minf(4.5,sqrt(maxf(target-before,0)*6.0)) if postal_stage == "arriving" else 4.5
		_bike_speed = move_toward(_bike_speed,desired_speed,delta*3.5)
		bicycle.position.x = move_toward(before,target,delta*_bike_speed)
		bicycle.roll(bicycle.position.x-before)
		postman.position = bicycle.position+SADDLE_OFFSET
		postman.pedal_phase = bicycle.crank.rotation.z
		postman._update_puppet_motion(delta)
		if is_equal_approx(bicycle.position.x,target):
			if postal_stage == "arriving":
				_begin_mount(false)
			else:
				postal_stage = "waiting"
				postman.hide()
				bicycle.hide()
	elif postal_stage in ["to_door","to_bike"]:
		postman.simulate(delta,1)
	elif postal_stage in ["dismounting","mounting"]:
		_mount_clock = minf(_mount_clock+delta,MOUNT_SECONDS)
		var t := _mount_clock/MOUNT_SECONDS
		postman.position = _mount_origin.lerp(_mount_target,smoothstep(0,1,t))
		postman.mount_blend = t
		postman._update_puppet_motion(delta)
		bicycle.set_parked(smoothstep(.35,.85,t) if postal_stage == "dismounting" else 1.0-smoothstep(.15,.65,t))
		if t >= 1:
			if postal_stage == "dismounting":
				postal_stage = "to_door"
				postman.route_provider = controller._customer_route
				postman.navigation_version = controller._navigation.version
				postman.move_to_anchor(controller._shop.interaction_anchor("customer_checkout"),"entering")
			else:
				postal_stage = "departing"
	elif postal_stage == "delivering":
		_delivery_wait -= delta
		postman._update_puppet_motion(delta)
		if _delivery_wait <= 0:
			deliveries.append({"day":last_visit_day,"publications":_visit_publications.duplicate()})
			_delivery_stack.show()
			controller._show_toast("收到订阅报刊："+"、".join(_visit_publications))
			postal_stage = "to_bike"
			postman.set_destination(bicycle.position+STANDING_OFFSET,"leaving")


func _begin_mount(onto_bicycle: bool) -> void:
	postal_stage = "mounting" if onto_bicycle else "dismounting"
	_bike_speed = 0.0
	_mount_clock = 0.0
	_mount_origin = postman.position
	_mount_target = bicycle.position+(SADDLE_OFFSET if onto_bicycle else STANDING_OFFSET)
	postman.begin_mount(onto_bicycle)


func _arrived(_person: PaperDoll) -> void:
	if postal_stage == "to_door":
		postal_stage = "delivering"
		_delivery_wait = 2.0
		postman.resting_facing = PI
		postman.set_activity("checkout")
	elif postal_stage == "to_bike":
		_begin_mount(true)
