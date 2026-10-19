extends ProbeKit

# C3 判定：窗口渲染出帧（非 headless 运行）。
# 布置一局丰富场景（单位/墙阵/双塔/英雄），推进 90 tick 后截 8 张：
#   shots/game.png          对局全景（含地形/建筑/单位/核心）
#   shots/heat.png          威胁热层开启
#   shots/ghost.png         放墙预览幽灵（斜线逐格绿板，D5-3 目视件）
#   shots/game_20x9.png / game_narrow.png / game_tablet.png / game_16x10.png  宽屏/窄屏/平板目视件（D1-5 扩展）
#   shots/game_closeup.png  改造特写（自然化 T1：填两级崖壁+裙脚 / 挖一级坑，相机拉近）
# 跑法（cwd=reroute-godot）：godot -s res://tests/probes/probe_shots.gd   （窗口模式，勿加 --headless）
# 判定：exit 0 + stdout 含 [SHOTS] PASS（8 图非空）；像素口径交给 tools/check_shots.py。


func _initialize() -> void:
	var packed: PackedScene = load("res://game/main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	for _i in 10:
		await process_frame # -s 模式：_ready 在首帧才跑；set_process 须在 ready 之后调用才粘（引擎在 ready 时重置处理态）
	main.set_process(false)
	main.start_match() # 进入对局（R6 起启动即标题屏）
	main.paused = true

	var view = main.view
	var world = main.world

	# ---- 布置：4 单位 + 3 连墙 + 2 塔 + 英雄移动 ----
	var cells: Array = []
	for _i in 6:
		var c := _find_free(world, 14, 8, 34, 18, cells)
		if c.x < 0:
			break
		cells.append(c)
	if cells.size() < 6:
		fail("布置格不足（%d/6）" % cells.size())
		finish("SHOTS", 3)
		return
	world.apply_command({ "kind": "spawn", "x": cells[0].x, "y": cells[0].y, "speed": 4, "kind_id": Sim.E_SWARM })
	world.apply_command({ "kind": "spawn", "x": cells[1].x, "y": cells[1].y, "speed": 4, "kind_id": Sim.E_SWARM })
	world.apply_command({ "kind": "spawn", "x": cells[2].x, "y": cells[2].y, "speed": 8, "kind_id": Sim.E_BEHEMOTH })
	world.apply_command({ "kind": "wall", "x": cells[3].x, "y": cells[3].y })
	world.apply_command({ "kind": "wall", "x": cells[4].x, "y": cells[4].y })
	world.apply_command({ "kind": "tower", "x": cells[5].x, "y": cells[5].y })
	var hero_target := _find_free(world, 18, 22, 30, 36, [])
	if hero_target.x >= 0:
		world.apply_command({ "kind": "hero", "x": hero_target.x, "y": hero_target.y })

	# ---- 推进 90 tick（第 60 tick 自然波次进场合流）----
	for _i in 90:
		world.tick()
	view.sync(world)
	for _i in 3:
		await process_frame
	_shot("res://shots/game.png")

	# ---- 热层 ----
	view.set_heat(true)
	view.sync(world)
	for _i in 3:
		await process_frame
	_shot("res://shots/heat.png")

	# ---- 幽灵预览（斜线拖拽：经 main.line_cells 的真产线，逐格绿板）----
	view.set_heat(false)
	view.show_ghost(main.line_cells(Vector2i(20, 12), Vector2i(23, 15)), false)
	view.sync(world)
	for _i in 3:
		await process_frame
	_shot("res://shots/ghost.png")

	# ---- 宽屏 20:9 与窄屏 4:3（D1-5 目视件：canvas_items+expand 下取景与 HUD S）----
	view.show_ghost([], false)
	view.sync(world)
	root.size = Vector2i(1600, 720)
	for _i in 5:
		await process_frame
	_shot("res://shots/game_20x9.png")
	root.size = Vector2i(960, 720)
	for _i in 5:
		await process_frame
	_shot("res://shots/game_narrow.png")
	root.size = Vector2i(1600, 1200)
	for _i in 5:
		await process_frame
	_shot("res://shots/game_tablet.png")
	root.size = Vector2i(1280, 800)
	for _i in 5:
		await process_frame
	_shot("res://shots/game_16x10.png")
	root.size = Vector2i(1280, 720)
	for _i in 3:
		await process_frame

	# ---- 改造特写（自然化 T1 目视件）：填两级（崖壁+裙脚）+ 挖一级（坑），相机拉近 ----
	var e0 := _find_free(world, 22, 22, 44, 40, [])
	if e0.x >= 0:
		world.apply_command({ "kind": "fill", "x": e0.x, "y": e0.y })
		world.apply_command({ "kind": "fill", "x": e0.x, "y": e0.y })
	var e1 := _find_free(world, 22, 22, 44, 40, [e0])
	if e1.x >= 0:
		world.apply_command({ "kind": "lower", "x": e1.x, "y": e1.y })
	view.sync(world)
	if e0.x >= 0:
		var w: Vector3 = view.cell_to_world(e0.x, e0.y)
		view.core.focus = Vector3(w.x, 0.0, w.z)
		view.core._zoom = 0.30
		view.core._apply_cam()
		for _i in 3:
			await process_frame
		_shot("res://shots/game_closeup.png")
		finish("SHOTS", 8)
		return
	finish("SHOTS", 5)


func _shot(path: String) -> void:
	var img := root.get_texture().get_image()
	check(img != null, "截图非空 " + path)
	if img == null:
		return
	img.save_png(path)
	print("[SHOTS] ", path, " ", img.get_width(), "x", img.get_height())


func _find_free(world, x0: int, y0: int, x1: int, y1: int, exclude: Array) -> Vector2i:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if not world.grid.passable(x, y):
				continue
			if world.building_at(x, y) != null:
				continue
			if not world.cell_vacant(x, y):
				continue
			var hr: Dictionary = world.hero
			if x == int(hr["x"]) and y == int(hr["y"]):
				continue
			if exclude.has(Vector2i(x, y)):
				continue
			return Vector2i(x, y)
	return Vector2i(-1, -1)
