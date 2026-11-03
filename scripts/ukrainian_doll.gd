class_name UkrainianDoll
extends "res://scripts/volume_doll.gd"

## ukrainian_photo_001 set on the shared rig: the generic body, head, hair,
## arms, calves and shoes are built first and stay untouched; only the base
## outfit is replaced (same convention as MosuoDoll). White ankle-length
## undershirt-dress with red neck ribbon, high yellow sash with yellow/purple
## tassels, purple front apron, dark striped overskirt. Skirts are built by
## UkrainianCostume's contract-compliant parametric shell.

const Costume = preload("res://components/ukrainian_costume.gd")
const FlatMaterial = preload("res://scripts/doll_costume_material.gd")
const COLOR_SHOE := Color("674137")


func _init() -> void:
	hair_style = 3
	shoe_style = 1


func _build_appearance() -> void:
	super()
	FlatMaterial.apply_to(body_rig)


func _costume_palette() -> Array:
	return [Costume.COLOR_SHIRT, Costume.COLOR_SASH, Costume.COLOR_APRON]


func _build_volume_body() -> void:
	super()
	preload("res://scripts/ukrainian_outfit.gd").new().apply(self)
