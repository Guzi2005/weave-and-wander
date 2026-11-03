class_name NapDrapeData
extends Resource

const RINGS := [.20,.24,.30,.48,.70,.99,1.22,1.31]
const RADII := [Vector2(.437,.313),Vector2(.440,.315),Vector2(.427,.307),Vector2(.389,.284),Vector2(.345,.260),Vector2(.299,.222),Vector2(.281,.204),Vector2(.280,.202)]
const SEGMENTS := 40
@export var offsets: PackedFloat32Array

func sample(p: Vector3, variant: int) -> float:
	if offsets.size() != 4*RINGS.size()*SEGMENTS or p.y >= RINGS[-1]:
		return 0.0
	var ring := 0
	while ring < RINGS.size()-2 and p.y > RINGS[ring+1]:
		ring += 1
	var t := clampf(inverse_lerp(RINGS[ring],RINGS[ring+1],p.y),0.0,1.0)
	var radius: Vector2 = RADII[ring].lerp(RADII[ring+1],t)
	var around := fposmod(atan2(p.x/radius.x,p.z/radius.y),TAU)/TAU*SEGMENTS
	var column := int(around)%SEGMENTS
	var fraction := around-floorf(around)
	var index := (clampi(variant,0,3)*RINGS.size()+ring)*SEGMENTS
	var lower := lerpf(offsets[index+column],offsets[index+(column+1)%SEGMENTS],fraction)
	var upper := lerpf(offsets[index+SEGMENTS+column],offsets[index+SEGMENTS+(column+1)%SEGMENTS],fraction)
	return lerpf(lower,upper,t)
