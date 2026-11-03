class_name BehaviorTreeRuntime
extends RefCounted

enum Status { SUCCESS, FAILURE, RUNNING }


class BTNode extends RefCounted:
	var running := false

	func tick(_actor: Node, _delta: float) -> int:
		return Status.SUCCESS

	func reset() -> void:
		running = false


class BTAction extends BTNode:
	var action: Callable

	func _init(callback: Callable) -> void:
		action = callback

	func tick(actor: Node, delta: float) -> int:
		var first := not running
		running = true
		var result: int = action.call(actor, delta, first)
		if result != Status.RUNNING:
			running = false
		return result


class BTWait extends BTNode:
	var duration: float
	var elapsed := 0.0
	var label: String

	func _init(seconds: float, status_label := "") -> void:
		duration = seconds
		label = status_label

	func tick(_actor: Node, delta: float) -> int:
		if not running:
			running = true
			elapsed = 0.0
		elapsed += delta
		if elapsed < duration:
			return Status.RUNNING
		running = false
		return Status.SUCCESS

	func reset() -> void:
		super()
		elapsed = 0.0


class BTCondition extends BTNode:
	var predicate: Callable

	func _init(callback: Callable) -> void:
		predicate = callback

	func tick(actor: Node, delta: float) -> int:
		return Status.SUCCESS if predicate.call(actor, delta) else Status.FAILURE


class BTSequence extends BTNode:
	var children: Array[BTNode]
	var index := 0

	func _init(nodes: Array[BTNode]) -> void:
		children = nodes

	func tick(actor: Node, delta: float) -> int:
		running = true
		while index < children.size():
			var result := children[index].tick(actor, delta)
			if result == Status.RUNNING:
				return Status.RUNNING
			if result == Status.FAILURE:
				reset()
				return Status.FAILURE
			index += 1
		reset()
		return Status.SUCCESS

	func reset() -> void:
		super()
		index = 0
		for child in children:
			child.reset()


class BTSelector extends BTNode:
	var children: Array[BTNode]
	var index := 0

	func _init(nodes: Array[BTNode]) -> void:
		children = nodes

	func tick(actor: Node, delta: float) -> int:
		running = true
		while index < children.size():
			var result := children[index].tick(actor, delta)
			if result == Status.RUNNING:
				return Status.RUNNING
			if result == Status.SUCCESS:
				reset()
				return Status.SUCCESS
			index += 1
		reset()
		return Status.FAILURE

	func reset() -> void:
		super()
		index = 0
		for child in children:
			child.reset()
