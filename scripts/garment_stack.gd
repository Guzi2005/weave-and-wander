extends RefCounted

const GAP := .018


static func ordered(selection: Array) -> Array[Node3D]:
	var result: Array[Node3D] = []
	# Stable partition: preserve the selection order within each category.
	for hats in [false, true]:
		for item in selection:
			if is_instance_valid(item) and item.definition.is_hat() == hats:
				result.append(item)
	return result


static func orientation(item: Node3D) -> Basis:
	return Basis.IDENTITY if item.definition.is_hat() else Basis(Vector3.RIGHT, -PI * .5)


static func box(item: Node3D) -> AABB:
	var bounds: AABB = Transform3D(orientation(item), Vector3.ZERO) * item.presentation_bounds("Folded")
	if item.head_contact.is_finite():
		bounds.position.y = item.head_contact.y
		bounds.size.y = maxf(.08,item.presentation_bounds().end.y-item.head_contact.y)
	return bounds


static func placement(item: Node3D, selection: Array, base := Vector3.ZERO) -> Transform3D:
	var height := 0.0
	for other in ordered(selection):
		if other == item: break
		height += box(other).size.y + GAP
	var bounds := box(item)
	if item.head_contact.is_finite():
		return Transform3D(Basis.IDENTITY,base+Vector3(0,height,0)-item.head_contact)
	return Transform3D(orientation(item), base + Vector3(0, height + bounds.size.y * .5, 0) - bounds.get_center())
