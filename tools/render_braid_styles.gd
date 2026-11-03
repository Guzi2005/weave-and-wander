extends SceneTree
const Braid = preload("res://components/path_braid.gd")
const Flat = preload("res://scripts/doll_costume_material.gd")
var shots: Array[Dictionary] = []
const STYLES = [
	["legacy-single","01  单圈盘旋 · 保留旧版","通用节点样式；历史实现保留，不标为民族志发式。"],
	["double-yak","02  双圈粗辫 · 当前适配","依据 P1 与用户指认调整；不同穿戴者，材料未实物鉴定。"],
	["double-loose","03  双圈 · 疏编","仅改变交叉节距，展示较松的编排。"],
	["double-dense","04  双圈 · 密编","缩短交叉节距、减薄径向厚度。"],
	["single-copper","05  单圈 · 棕色变体","旧版单圈的颜色、宽度和节距变体；无文化归属。"],
	["double-soft","06  双圈 · 宽厚变体","增加辫宽与厚度；通用参数探索，不作历史断言。"]]

func _initialize() -> void: _run.call_deferred()

func label(text: String,size: int,color := Color("354a4d")) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size",size)
	node.add_theme_color_override("font_color",color)
	return node

func _run() -> void:
	root.size = Vector2i(1560,1060)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_factor = 1.0
	var page := ColorRect.new()
	page.color = Color("f1eee5")
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(page)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+edge,32)
	page.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",14)
	margin.add_child(column)
	column.add_child(label("W&W  /  节点生成样式     PATH BRAID · 01",24))
	column.add_child(label("同一相机 · 同一比例 · 游戏扁平三渲二    /    参数样例不等同于文化分类",15))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation",18)
	grid.add_theme_constant_override("v_separation",18)
	column.add_child(grid)
	var entries: Array = []
	var out := "res://tools/ww-wiki/public/assets/node-styles"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	for entry in STYLES:
		var recipe: Braid = load("res://assets/collections/node_styles/"+entry[0]+".tres")
		var cell := VBoxContainer.new()
		cell.custom_minimum_size.x = 486
		grid.add_child(cell)
		var viewport := SubViewport.new()
		viewport.size = Vector2i(972,650)
		viewport.own_world_3d = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		viewport.msaa_3d = Viewport.MSAA_4X
		root.add_child(viewport)
		var world := WorldEnvironment.new()
		world.environment = Environment.new()
		world.environment.background_mode = Environment.BG_COLOR
		world.environment.background_color = Color("e8eeeb")
		viewport.add_child(world)
		var mesh := MeshInstance3D.new()
		var data := recipe.build_geometry()
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = data.vertices
		arrays[Mesh.ARRAY_NORMAL] = data.normals
		arrays[Mesh.ARRAY_INDEX] = data.indices
		arrays[Mesh.ARRAY_COLOR] = data.colors
		arrays[Mesh.ARRAY_TEX_UV] = data.uv
		mesh.mesh = ArrayMesh.new()
		mesh.mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		mesh.material_override = Flat.from_source(recipe.material())
		viewport.add_child(mesh)
		var camera := Camera3D.new()
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 1.35
		viewport.add_child(camera)
		camera.position = Vector3(.9,1.4,2.8)
		camera.look_at(Vector3(0,.53,0))
		camera.current = true
		var image_view := TextureRect.new()
		image_view.texture = viewport.get_texture()
		image_view.custom_minimum_size = Vector2(486,325)
		image_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		cell.add_child(image_view)
		cell.add_child(label(entry[1],18))
		cell.add_child(label("%d 圈   宽 %.3f   厚 %.3f   节距 %.3f" % [recipe.wrap_count,recipe.width,recipe.depth,recipe.pitch],14))
		cell.add_child(label("色 #%s   /   模型单位 m" % recipe.hair_color.to_html(false),13))
		var note := label(entry[2],12)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cell.add_child(note)
		var filename: String = out+"/"+entry[0]
		# Resource script path remains res://components/path_braid.gd for game reuse.
		ResourceSaver.save(recipe,filename+".tres")
		shots.append({"viewport":viewport,"file":filename+".png"})
		entries.append({"id":entry[0],"label":entry[1],"image":"/assets/node-styles/"+entry[0]+".png",
			"recipe":"/assets/node-styles/"+entry[0]+".tres","parameters":{"圈数":recipe.wrap_count,"辫半宽 / m":recipe.width,"径向厚度 / m":recipe.depth,"交叉节距 / m":recipe.pitch,"编织股数":recipe.strands,"发色":"#"+recipe.hair_color.to_html(false),"纤维纹理强度":recipe.fiber_texture},
			"evidence_status":"用户参考适配" if entry[0] == "double-yak" else "通用节点生成样式","note":entry[2]})
	column.add_child(label("P1 仅支持双圈粗辫的形态比较。牦牛毛材质依据用户指认；配方尺寸服务于游戏角色比例。",13))
	var file := FileAccess.open(out+"/manifest.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"schema":"ww-node-styles-v1","title":"路径发辫 · 节点生成样式","description":"真实游戏几何渲染，固定视角与比例；保留旧版并列参数组合。配方依赖项目中的 PathBraid 组件。","entries":entries},"  "))
	for tick in 12: await process_frame
	await RenderingServer.frame_post_draw
	for shot in shots:
		shot.viewport.get_texture().get_image().save_png(ProjectSettings.globalize_path(shot.file))
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(out+"/comparison.png"))
	print("BRAID_STYLE_GALLERY_PASS six rendered recipes + comparison + manifest")
	quit()
