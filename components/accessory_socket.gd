extends Marker3D
## Authoring socket: the shared rig bakes this local transform and keeps its source metadata.
@export var bone_name := "Head"
@export var socket_id := ""
@export var purpose := ""

func specification() -> Dictionary:
	return {"id":socket_id,"bone":bone_name,"purpose":purpose,
		"position":[position.x,position.y,position.z],
		"rotation_degrees":[rotation_degrees.x,rotation_degrees.y,rotation_degrees.z]}
