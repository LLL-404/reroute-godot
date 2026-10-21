extends ProbeKit

# 受击闪白探针（2026-10-21）：验证 material_overlay 这条提亮通道确实落在 skinned mesh 上，
# 且在真实对局里能触发、能自行消退。
#
# 为什么单独一道闸：overlay 的两个坑都只能靠实测发现，代码审查看不出来 ——
# ① ADD 混合下 albedo_color 的 alpha 不参与强度，强度必须写进颜色值（否则闪白形同虚设）；
# ② cull_mode = CULL_DISABLED 会让背面再叠一遍，暗色单位直接过曝成纯白剪影。
#
# 跑法（窗口模式）：godot -path <proj> -s res://tests/probes/probe_flash.gd
# 判定：exit 0 + `[FLASH] PASS`；证据图 shots/flash_off.png / shots/flash_on.png（同姿态对照）。

const ModelsScript = preload("res://game/models.gd")
const ViewEntitiesScript = preload("res://game/view_entities.gd") # 直接取游戏内常量，避免探针图与实际参数脱节

var _meshes: Array = []


func _initialize() -> void:
	root.size = Vector2i(720, 720)
	var models = ModelsScript.new()
	var packed: PackedScene = load("res://assets/models/zerg_blade.glb")
	check(packed != null, "加载 zerg_blade")
	var inst: Node3D = packed.instantiate()
	root.add_child(inst)
	var player: AnimationPlayer = models.find_player(inst)
	check(player != null, "有 AnimationPlayer")
	if player != null:
		models.play(player, "Crawl", true)
		player.seek(0.55, true) # 取非 rest 姿态：若 overlay 用 rest pose 渲染会出现鬼影

	var cam := Camera3D.new()
	cam.fov = 45.0
	root.add_child(cam)
	cam.position = Vector3(0.0, 1.5, 3.6)
	cam.look_at_from_position(Vector3(0.0, 1.5, 3.6), Vector3(0.0, 0.55, 0.0), Vector3.UP)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-42.0, -35.0, 0.0)
	light.light_energy = 1.3
	root.add_child(light)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.12, 0.14, 0.17)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.64)
	env.ambient_light_energy = 0.7
	we.environment = env
	root.add_child(we)

	_collect(inst, _meshes)
	check(_meshes.size() > 0, "收集到 mesh 节点 " + str(_meshes.size()))
	for _i in 8:
		await process_frame
	await _shot("res://shots/flash_off.png")

	var lv: float = ViewEntitiesScript.FLASH_HI_LEVEL
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	mat.albedo_color = Color(lv, lv, lv, 1.0)
	for m in _meshes:
		var mi: MeshInstance3D = m
		mi.material_overlay = mat
		check(mi.material_overlay != null, "overlay 已挂上 " + str(mi.name))
	for _i in 6:
		await process_frame
	await _shot("res://shots/flash_on.png")
	inst.free()
	cam.free()
	light.free()
	we.free()

	# ---- 第二段：真实对局里是否真的走上闪白路径（结构 + 状态，不靠目检）----
	var main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	for _i in 3:
		await process_frame
	main.set_process(false) # 时序铁律：await 后再关
	main.start_match()
	for _i in 2:
		await process_frame
	var view = main.view
	var world = main.world
	# 最小防御：复用冒烟探针的固定塔位，确保有击杀链才有受击链
	for s in [Vector2i(32, 9), Vector2i(32, 12), Vector2i(30, 12), Vector2i(34, 12)]:
		world.apply_command({ "kind": "tower", "x": s.x, "y": s.y })
	var flashed := 0
	var total := 0
	for i in 3000:
		main._process(0.1) # 2 tick/次：flash 持续 6 tick，2 tick 步进必能采样到
		if i % 20 == 0:
			await process_frame
		for uid in view.unit_nodes.keys():
			var e: Dictionary = view.unit_nodes[uid]
			var ms: Array = e.get("meshes", [])
			if ms.size() > 0:
				total += 1
				var mi: MeshInstance3D = ms[0]
				if mi.material_overlay != null:
					flashed += 1
		if flashed > 0:
			print("[FLASH] 首次闪白 @i=", i, " tick=", world.tick_count)
			break
	check(total > 0, "单位 mesh 已收集（样本 " + str(total) + "）")
	check(flashed > 0, "受击闪白在真实对局中出现（命中 " + str(flashed) + "）")

	# 闪白必须自行消退：脉冲走完要写回 null，否则单位会一直顶着亮层
	var probe_uid := -1
	for uid2 in view.unit_nodes.keys():
		var e2: Dictionary = view.unit_nodes[uid2]
		var ms2: Array = e2.get("meshes", [])
		if ms2.size() > 0 and (ms2[0] as MeshInstance3D).material_overlay != null:
			probe_uid = uid2
			break
	var clear_ok := false
	if probe_uid >= 0:
		for _i in 10:
			main._process(0.5)
		if not view.unit_nodes.has(probe_uid):
			clear_ok = true # 单位已死：节点随 death_fx 销毁，不存在残留
		else:
			var e3: Dictionary = view.unit_nodes[probe_uid]
			var ms3: Array = e3.get("meshes", [])
			clear_ok = ms3.size() > 0 and (ms3[0] as MeshInstance3D).material_overlay == null
	check(clear_ok, "闪白自行消退（overlay 已清空）")
	finish("FLASH", 3)


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	check(img != null, "截图非空 " + path)
	if img != null:
		img.save_png(path)
		print("[FLASH] ", path, " ", img.get_width(), "x", img.get_height())


func _collect(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is MeshInstance3D:
			out.append(c)
		_collect(c, out)
