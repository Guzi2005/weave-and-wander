@tool
class_name PathBraid
extends Resource

## Parametric false braid: strands wind around a Curve3D path in HeadRig local coordinates.
## photo_001 is the P1-informed broad two-wrap plait. The preceding one-wrap
## recipe is preserved byte-for-byte in node_styles/legacy-single.tres.
## Control points are editable in the Inspector. Units are model metres.
##
## Contract (schema ww-path-braid-v1):
## - path: open Curve3D. The preset starts at front/top, circles the crown once, then tucks
##   toward the back so the tail end is concealed under the headwear.
## - width is the braid half-width across the head surface, depth the outward thickness,
##   pitch the path length of one full strand crossing cycle. strands defaults to 3.
## - Strands are visibly interlaced: each follows the path with a phase-offset elliptical
##   orbit (wide across the head, shallow outward) so strands alternately cross over and
##   under instead of forming a round spring helix.
## - build_geometry() returns the same dictionary shape as SeedBeadBundle
##   (vertices/normals/indices/colors/arm_weights/slot "headwear"); material() is the single
##   dark hair material and vertex colors carry per-strand shading only.

@export var path: Curve3D
@export var hair_color := Color("171319")
@export_enum("Legacy coiled", "Broad yak-hair plait") var construction := 0
@export_range(0.0, 1.0, .05) var fiber_texture := .5
@export var style_id := "legacy-single"
@export_range(1, 3, 1) var wrap_count := 1
## Braid half-width across the head surface.
@export_range(.02, .16, .001) var width := .075
## Braid outward thickness.
@export_range(.015, .12, .001) var depth := .055
## Path length of one full crossing cycle per strand.
@export_range(.04, .5, .005) var pitch := .16
@export_range(2, 5, 1) var strands := 3
## Samples along the baked path.
@export_range(24, 1024, 4) var subdivisions := 512
## Ring resolution of each strand tube.
@export_range(4, 12, 1) var strand_sides := 8
## Fraction of the path tail over which the braid tapers to its concealed end.
@export_range(0, .3, .01) var tail_taper := .12

static func photo_001() -> PathBraid:
	return load("res://assets/collections/mosuo_braid.tres").duplicate(true)

func parameters() -> Dictionary:
	return {"schema":"ww-path-braid-v1","color":hair_color.to_html(),"width":width,"depth":depth,
		"pitch":pitch,"strands":strands,"subdivisions":subdivisions,"strand_sides":strand_sides,
		"style_id":style_id,"construction":construction,"wrap_count":wrap_count,"fiber_texture":fiber_texture,
		"path_points":path.get_point_count() if path != null else 0,
		"units":"model metres","attachment":"HeadwearSlot"}

func build_geometry() -> Dictionary:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var length := path.get_baked_length() if path != null and path.get_point_count() >= 2 else 0.0
	if length <= .0001:
		return {"vertices":vertices,"normals":normals,"indices":indices,"colors":colors,
			"arm_weights":PackedFloat32Array(),"slot":"headwear","strand_count":0}
	var samples := clampi(subdivisions,24,1024)+1
	var sides := clampi(strand_sides,4,12)
	var strand_total := clampi(strands,2,5)
	var centers: Array[PackedVector3Array] = []
	var frames: Array[Basis] = []
	for k in samples:
		var transform := path.sample_baked_with_rotation(length*k/(samples-1))
		var frame := transform.basis.orthonormalized()
		if construction == 1:
			# A wide plait lies across the crown wall, with shallow radial depth.
			# Parallel up frames avoid unwanted tube roll at the back crossover.
			var tangent := -frame.z
			var vertical := (Vector3.UP-tangent*tangent.dot(Vector3.UP)).normalized()
			frame = Basis(vertical,tangent.cross(vertical),-tangent)
		frames.append(frame)
	for strand in strand_total:
		var centerline := PackedVector3Array()
		var phase := TAU*strand/strand_total
		for k in samples:
			var u := float(k)/(samples-1)
			var theta := TAU*length*u/maxf(pitch,.01)+phase
			var taper := 1.0
			if tail_taper > .001 and u > 1.0-tail_taper:
				taper = lerpf(1.0,.42,smoothstep(1.0-tail_taper,1.0,u))
			var frame: Basis = frames[k]
			var pos := path.sample_baked(length*u)
			var orbit := (frame.x*sin(theta)*width+frame.y*sin(theta*2)*depth)*.62*taper
			centerline.append(pos+orbit)
		centers.append(centerline)
		var base := vertices.size()
		var shade := 1.0-float(strand % 3)*.07
		var tint := hair_color.srgb_to_linear()*shade
		for k in samples:
			var tangent := (centerline[mini(k+1,samples-1)]-centerline[maxi(k-1,0)]).normalized()
			var cross_axis := frames[k].x-tangent*frames[k].x.dot(tangent)
			cross_axis = cross_axis.normalized()
			var frame := Basis(cross_axis,tangent.cross(cross_axis),-tangent)
			var tube := width*(.46 if construction == 1 else .5)
			if tail_taper > .001:
				var u := float(k)/(samples-1)
				if u > 1.0-tail_taper:
					tube *= lerpf(1.0,.42,smoothstep(1.0-tail_taper,1.0,u))
			for side in sides:
				var a := TAU*side/sides
				var outward := (frame.x*cos(a)*1.12+frame.y*sin(a)*.82).normalized()
				vertices.append(centerline[k]+(frame.x*cos(a)*1.12+frame.y*sin(a)*.82)*tube)
				normals.append(outward)
				# Broad ink facets keep crossings readable without specular plastic.
				var ink_shade := (1.0 if outward.dot(Vector3(-.55,.8,.65)) > .05 else .67) if construction == 1 else 1.0
				colors.append(tint*ink_shade)
				uvs.append(Vector2(float(side)/sides,float(k)/(samples-1)*length*5))
		for k in samples-1:
			for side in sides:
				var a := base+k*sides+side
				var b := base+k*sides+(side+1)%sides
				indices.append_array(PackedInt32Array([a,a+sides,b,b,a+sides,b+sides]))
		for end_k in [0, samples-1]:
			var sign := -1.0 if end_k == 0 else 1.0
			var cap_base := vertices.size()
			var tangent := (centerline[mini(end_k+1,samples-1)]-centerline[maxi(end_k-1,0)]).normalized()*sign
			vertices.append(centerline[end_k])
			normals.append(tangent)
			colors.append(tint)
			uvs.append(Vector2.ZERO)
			for side in sides:
				vertices.append(vertices[base+end_k*sides+side])
				normals.append(tangent)
				colors.append(tint)
				uvs.append(Vector2.ZERO)
			for side in sides:
				var rim := cap_base+1+side
				var rim_next := cap_base+1+(side+1)%sides
				if end_k == 0:
					indices.append_array(PackedInt32Array([cap_base,rim_next,rim]))
				else:
					indices.append_array(PackedInt32Array([cap_base,rim,rim_next]))
	return {"vertices":vertices,"normals":normals,"indices":indices,"colors":colors,"uv":uvs,
		"arm_weights":PackedFloat32Array(),"slot":"headwear","strand_count":strand_total}

func material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.resource_name = "False braid · dark hair"
	mat.albedo_color = Color.WHITE
	mat.vertex_color_use_as_albedo = true
	mat.roughness = .52
	mat.metallic = 0.0
	mat.metallic_specular = .45
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if construction == 1 and fiber_texture > 0.0:
		# A repeatable visual cue for long dark fibres, not a fibre identification.
		var image := Image.create(64,128,false,Image.FORMAT_RGB8)
		for y in 128:
			for x in 64:
				var streak := sin(x*2.4+sin(y*TAU/128.0)*.5)*sin(x*5.3)
				var value := 1.0-fiber_texture*(.11+.09*streak)
				image.set_pixel(x,y,Color(value,value,value))
		image.generate_mipmaps()
		mat.albedo_texture = ImageTexture.create_from_image(image)
	return mat
