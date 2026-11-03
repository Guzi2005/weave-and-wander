@tool
extends "res://scripts/service_queue.gd"

var curtain: Node3D
const EXIT_CLEARANCE := 1.4
var occupant: WeakRef
var _leaving: WeakRef


func request(customer: Node) -> bool:
	_cleanup()
	if owns(customer):
		return true
	if join(customer) == null:
		return false
	if occupant == null and curtain.is_open() and _exit_clear() and is_first(customer):
		occupant = weakref(customer)
		leave(customer)
		return true
	return false


func owns(customer: Node) -> bool:
	return occupant != null and occupant.get_ref() == customer


func close_for(customer: Node, closed: bool) -> bool:
	if not owns(customer):
		return false
	curtain.set_closed(closed)
	return true


func release(customer: Node) -> void:
	leave(customer)
	if owns(customer):
		occupant = null
		_leaving = weakref(customer)
		curtain.set_closed(false)


func _exit_clear() -> bool:
	var previous: Node3D = _leaving.get_ref() if _leaving != null else null
	if not is_instance_valid(previous):
		return true
	var offset := previous.global_position - global_position
	return Vector2(offset.x, offset.z).length() > EXIT_CLEARANCE


func _cleanup() -> void:
	super._cleanup()
	if occupant != null and not is_instance_valid(occupant.get_ref()):
		occupant = null
		curtain.set_closed(false)


func advance(delta: float) -> void:
	_cleanup()
	if curtain != null:
		curtain.advance(delta)


func is_closed() -> bool:
	return curtain != null and curtain.is_closed()


func is_open() -> bool:
	return curtain != null and curtain.is_open()
