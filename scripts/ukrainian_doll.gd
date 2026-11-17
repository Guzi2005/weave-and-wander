class_name UkrainianDoll
extends "res://scripts/game_body_doll.gd"

## ukrainian_photo_001 set on the shared rig: the generic body, head, hair,
## arms, calves and shoes are built first and stay untouched; only the base
## outfit is replaced (same convention as MosuoDoll). Hair is the shared
## wavy bob (hair style 3) in chestnut; shoes are the shared strapped low
## shoes with white sock instep (shoe style 1).

const Costume = preload("res://components/ukrainian_costume.gd")
const FlatMaterial = preload("res://scripts/doll_costume_material.gd")


func _init() -> void:
	hosiery = preload("res://components/hosiery_style.gd").new()
	hosiery.enabled = true
	hosiery.length = .22
	hair_style = 3
	shoe_style = 1
	hair_color_index = 3


func _build_appearance() -> void:
	super()
	FlatMaterial.apply_to(body_rig)


func _costume_palette() -> Array:
	return [Costume.COLOR_SHIRT, Costume.COLOR_SASH, Costume.COLOR_APRON]


func _build_volume_body() -> void:
	super()
	preload("res://scripts/ukrainian_outfit.gd").new().apply(self)
