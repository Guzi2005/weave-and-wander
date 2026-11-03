extends RefCounted
## Generated visual reconstruction, not a claim about the original fibre/printing technique.
static var _cache: Dictionary = {}

static func make(kind: String) -> StandardMaterial3D:
	if _cache.has(kind): return _cache[kind]
	var mat := StandardMaterial3D.new()
	mat.resource_name = "Photo001 / %s / generated textile study" % kind
	var image := Image.load_from_file(ProjectSettings.globalize_path("res://assets/materials/mosuo_photo_001/%s-albedo.png" % kind))
	mat.albedo_color = Color.WHITE if kind == "skirt" else Color("fff8f1")
	mat.roughness = .32 if kind == "blouse" else 1.0
	mat.metallic_specular = .58
	mat.anisotropy_enabled = true
	mat.anisotropy = .65
	mat.clearcoat_enabled = true
	mat.clearcoat = .18
	mat.clearcoat_roughness = .3
	if kind == "skirt":
		# Pale low-saturation pattern pixels form the silver-thread material mask.
		# The cyan substrate remains dielectric; only the motif reflects as metal.
		var metal := Image.create(image.get_width(),image.get_height(),false,Image.FORMAT_RGB8)
		var rough := Image.create(image.get_width(),image.get_height(),false,Image.FORMAT_RGB8)
		var relief := Image.create(image.get_width(),image.get_height(),false,Image.FORMAT_RGB8)
		for y in image.get_height():
			for x in image.get_width():
				var color := image.get_pixel(x,y)
				var silver := _silver(color)
				metal.set_pixel(x,y,Color(silver,silver,silver))
				var r := lerpf(.33,.19,silver)
				rough.set_pixel(x,y,Color(r,r,r))
				# A shallow woven relief shares the silver mask; the floral motif
				# catches light independently from the dyed satin substrate.
				var nx := (_silver(image.get_pixel((x-1+image.get_width())%image.get_width(),y))-_silver(image.get_pixel((x+1)%image.get_width(),y)))*.7
				var ny := (_silver(image.get_pixel(x,(y-1+image.get_height())%image.get_height()))-_silver(image.get_pixel(x,(y+1)%image.get_height())))*.7
				nx += sin(x*PI)*.025
				ny += sin(y*TAU/3.0)*.035
				var n := Vector3(nx,ny,1).normalized()*.5+Vector3.ONE*.5
				relief.set_pixel(x,y,Color(n.x,n.y,n.z))
		# Tone only the dye; silver remains neutral rather than receiving cyan tint.
		for y in image.get_height():
			for x in image.get_width():
				var color := image.get_pixel(x,y)
				var silver := metal.get_pixel(x,y).r
				var dye := color*Color("8eafb7")
				image.set_pixel(x,y,dye.lerp(Color("d8dce0"),silver))
		metal.generate_mipmaps()
		rough.generate_mipmaps()
		mat.metallic = .96
		mat.metallic_texture = ImageTexture.create_from_image(metal)
		mat.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		mat.roughness_texture = ImageTexture.create_from_image(rough)
		mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		relief.generate_mipmaps()
		mat.normal_enabled = true
		mat.normal_texture = ImageTexture.create_from_image(relief)
		mat.normal_scale = .55
	image.generate_mipmaps()
	mat.albedo_texture = ImageTexture.create_from_image(image)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mat.texture_repeat = true
	# Fine interlaced warp/weft micro-normal, independent of the floral colour map.
	var normal := Image.create(128,128,false,Image.FORMAT_RGB8)
	for y in 128:
		for x in 128:
			var nx := sin(x*TAU/8.0)*.16*(.7+.3*cos(y*TAU/8.0))
			var ny := sin(y*TAU/8.0)*.16*(.7-.3*cos(x*TAU/8.0))
			var v := Vector3(nx,ny,1).normalized()*.5+Vector3.ONE*.5
			normal.set_pixel(x,y,Color(v.x,v.y,v.z))
	normal.generate_mipmaps()
	# Exportable PBR micro-normal for the interlaced thread surface.
	mat.normal_enabled = true
	if kind != "skirt":
		mat.normal_texture = ImageTexture.create_from_image(normal)
		mat.normal_scale = .24
	_cache[kind] = mat
	return mat

static func _silver(color: Color) -> float:
	return smoothstep(.55,.76,color.r)*(1.0-smoothstep(.18,.36,color.s))
