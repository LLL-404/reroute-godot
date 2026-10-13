extends SceneTree

# C3 判定：窗口渲染出帧（非 headless 运行）。
# 布置一局丰富场景（单位/墙阵/双塔/英雄），推进 90 tick 后截 3 张：
#   shots/game.png   对局全景（含地形/建筑/单位/核心）
#   shots/heat.png   威胁热层开启
#   shots/ghost.png  放墙预览幽灵（绿板）
# 跑法（cwd=reroute-godot）：godot -s res://probe_shots.gd   （窗口模式，勿加 --headless）
# 判定：exit 0 + 3 张 PNG 存在，交给 tools/check_shots.py 做像素校验（[SHOTS] PASS）。
var checks := 0
var misses := 0


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
		print("[SHOT] FAIL 布置格不足")
		quit(1)
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

	# ---- 幽灵预览（放墙拖拽三连）----
	view.set_heat(false)
	view.show_ghost([Vector2i(20, 12), Vector2i(23, 12)], false)
	view.sync(world)
	for _i in 3:
		await process_frame
	_shot("res://shots/ghost.png")

	print("[SHOT] done shots=", checks, " misses=", misses)
	quit(0 if misses == 0 else 1)


func _shot(path: String) -> void:
	var img := root.get_texture().get_image()
	checks += 1
	if img == null:
		misses += 1
		print("[SHOT] FAIL 空图像 ", path)
		return
	img.save_png(path)
	print("[SHOT] ", path, " ", img.get_width(), "x", img.get_height())


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
