extends ProbeKit

# 模型渲染探针 v2：三个单位形态 + 金堆，含动画帧（Crawl）截图验证。
# 判定：exit 0 + stdout 含 [MODEL] PASS。

const ModelsScript = preload("res://game/view/models.gd")

func _initialize() -> void:
	var models = ModelsScript.new()
	var root := get_root()
	var world := Node3D.new()
	world.name = "World"
	root.add_child(world)

	var cam := Camera3D.new()
	cam.fov = 42.0
	world.add_child(cam)
	cam.current = true

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -130, 0)
	sun.light_energy = 1.4
	sun.light_color = Color(1.0, 0.97, 0.9)
	world.add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.16, 0.17, 0.2)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.52, 0.55)
	e.ambient_light_energy = 0.55
	env.environment = e
	world.add_child(env)

	var grid := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(8, 8)
	grid.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.28, 0.3, 0.33)
	grid.material_override = gm
	world.add_child(grid)

	# 三个单位形态并排 + 金堆
	var items := [
		["blade", "res://assets/models/zerg_blade.glb", Vector3(-1.1, 0, 0.2), "Crawl", 0.6],
		["worker", "res://assets/models/zerg_worker.glb", Vector3(0.15, 0, 0.2), "Crawl", 0.6],
		["king", "res://assets/models/zerg_king.glb", Vector3(1.5, 0, 0.2), "Crawl", 0.6],
		["gold", "res://assets/models/gold_pile_full.glb", Vector3(-0.5, 0, 1.6), "", 0.0],
	]
	for item in items:
		var packed: PackedScene = load(item[1])
		check(packed != null, "加载 " + str(item[1]))
		if packed == null:
			continue
		var inst: Node3D = packed.instantiate()
		models.bind_lod(inst, 0.0) # 4 级 LOD 资产：裸实例化只显 LOD0（游戏内走 spawn_* 自动切级）
		inst.position = item[2]
		world.add_child(inst)
		var anim_name: String = item[3]
		if anim_name != "":
			var ap: AnimationPlayer = null
			var stack: Array = [inst]
			while not stack.is_empty():
				var n: Node = stack.pop_back()
				if n is AnimationPlayer:
					ap = n
					break
				for c in n.get_children():
					stack.append(c)
			if ap != null:
				var list := ap.get_animation_list()
				print("[MODEL] %s anims: %s" % [item[0], str(list)])
				if list.has(anim_name):
					ap.play(anim_name)
					ap.seek(item[4], true)
			else:
				print("[MODEL] %s: no AnimationPlayer" % item[0])
		print("[MODEL] %s placed" % item[0])

	cam.look_at_from_position(Vector3(1.6, 1.5, 3.6), Vector3(0, 0.4, 0.6), Vector3.UP)
	for _i in 30:
		await process_frame
	var img1 := get_root().get_texture().get_image()
	check(img1 != null, "取帧 models_all")
	if img1 != null:
		img1.save_png("res://shots/models_all.png")
	print("[MODEL] shot models_all saved")

	# 近景 blade（动画中段）
	cam.look_at_from_position(Vector3(-0.5, 0.9, 2.1), Vector3(-1.05, 0.35, 0.2), Vector3.UP)
	for _i in 10:
		await process_frame
	var img2 := get_root().get_texture().get_image()
	check(img2 != null, "取帧 model_blade_close")
	if img2 != null:
		img2.save_png("res://shots/model_blade_close.png")
	print("[MODEL] shot blade close saved")

	finish("MODEL")
