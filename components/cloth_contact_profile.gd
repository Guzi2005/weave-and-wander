extends Resource
## Collision clearance and visible thickness are separate, in doll-space units.
@export_range(0.002, 0.04, 0.001) var skin_offset := 0.022
@export_range(0.002, 0.03, 0.001) var collision_thickness := 0.008
@export_range(0.0, 0.02, 0.001) var rendering_thickness := 0.004
@export_range(0.004, 0.04, 0.001) var layer_gap := 0.014


func body_clearance() -> float:
	return skin_offset + maxf(collision_thickness, rendering_thickness * 0.5)
