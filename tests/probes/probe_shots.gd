extends ProbeKit

# C3 判定：窗口渲染出帧（非 headless 运行）。
# 布置一局丰富场景（单位/墙阵/双塔/英雄），推进 90 tick 后截 11 张：
#   shots/game.png          对局全景（含地形/建筑/单位/核心）
#   shots/heat.png          威胁热层开启
#   shots/ghost.png         放墙预览幽灵（斜线逐格绿板 + 半透明连续墙段，D5-3/2026-10-20）
#   shots/build_preview.png 塔实物预览 + 12 格射程
#   shots/game_20x9.png / game_narrow.png / game_tablet.png / game_16x10.png  宽屏/窄屏/平板目视件（D1-5 扩展）
#   shots/game_closeup.png  改造特写（自然化 T1：填三级崖壁+裙脚 / 挖一级坑，相机拉近）
#   shots/game_pit.png      负高度坑（2026-10-23：连挖两级到 -2，相机聚焦坑）
#   shots/game_cliff.png    CLIFF 地貌（固定种子重开：相机聚焦核心崖壁）
# 跑法（cwd=reroute-godot）：godot -s res://tests/probes/probe_shots.gd   （窗口模式，勿加 --headless）
# 判定：exit 0 + stdout 含 [SHOTS] PASS（11 图非空）；像素口径交给 tools/check_shots.py。

const CLIFF_SEED := 20261007 # sweep（20261004..20261051）首个 TERRAIN_CLIFF 局（确定性）


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

	# ---- 幽灵预览（斜线拖拽：经 main.line_cells 的真产线，逐格绿板 + 实物墙段）----
	view.set_heat(false)
	view.show_ghost(main.line_cells(Vector2i(20, 12), Vector2i(23, 15)), false, "wall")
	view.sync(world)
	for _i in 3:
		await process_frame
	_shot("res://shots/ghost.png")

	# ---- 塔实物预览 + 射程（12 格填充 + 边缘带）----
	view.show_ghost([Vector2i(20, 12)], false, "tower")
	view.sync(world)
	for _i in 3:
		await process_frame
	_shot("res://shots/build_preview.png")

	# ---- 宽屏 20:9 与窄屏 4:3（D1-5 目视件：canvas_items+expand 下取景与 HUD S）----
	view.show_ghost([], false, "")
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

	# ---- 改造特写（自然化 T1 目视件）：填三级（崖壁+裙脚）+ 挖一级（缓坡坑），相机拉近 ----
	var e0 := _find_flat_free(world, 22, 22, 44, 40, [])
	if e0.x >= 0:
		for _i in 3: # 2026-10-23：dh≥3 才是崖壁（落差 2 已按可爬坡 RAMP）
			world.apply_command({ "kind": "fill", "x": e0.x, "y": e0.y })
	var e1 := _find_flat_free(world, 22, 22, 44, 40, [e0])
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

	# ---- 负高度坑（Task6 目视件）：在平坦区连挖两级到 -2（孤立坑），相机聚焦坑 ----
	var pc := _find_flat_free(world, 22, 22, 44, 40, [e0, e1])
	if pc.x >= 0:
		for _i in 2:
			world.apply_command({ "kind": "lower", "x": pc.x, "y": pc.y })
	view.sync(world)
	check(pc.x >= 0 and world.grid.get_h(pc.x, pc.y) == -2, "坑目视件布置（-2 坑）")
	if pc.x >= 0:
		var wp: Vector3 = view.cell_to_world(pc.x, pc.y)
		# 焦点落在坑底上方（focus.y 参与相机位姿）：否则 y=0 的注视点会落在坑口之上，坑被构图推到画面底缘
		view.core.focus = Vector3(wp.x, view.ground_y(pc.x, pc.y) + 0.3, wp.z)
		view.core._zoom = 0.36
		view.core._apply_cam()
		for _i in 3:
			await process_frame
		_shot("res://shots/game_pit.png")
		print("[SHOTS] pit cell=", pc, " top=", view.ground_y(pc.x, pc.y))

	# ---- CLIFF 地貌（Task6 目视件）：固定种子重开，相机在核心一侧正对核心崖壁 ----
	var mcmap: Dictionary = main.get_script().get_script_constant_map()
	var base_seed: int = int(mcmap["BASE_SEED"])
	main.run_index = CLIFF_SEED - base_seed - 1 # new_game 内部再 +1
	main.new_game()
	view = main.view
	world = main.world
	check(world.sc.terrain_kind == MapGen.TERRAIN_CLIFF, "CLIFF 种子开局（%d）" % CLIFF_SEED)
	var cc := _find_cliff(world.sc)
	check(cc.x >= 0, "核心崖壁格扫描")
	if cc.x >= 0:
		var wc: Vector3 = view.cell_to_world(cc.x, cc.y)
		var wcore: Vector3 = view.cell_to_world(world.sc.core.x, world.sc.core.y)
		var dir := Vector2(wc.x - wcore.x, wc.z - wcore.z)
		if dir.length() < 0.001:
			dir = Vector2(0.0, 1.0)
		dir = dir.normalized()
		# 注视点取崖面中段高度（崖顶 - 一档半）：核心崖壁（≥3 级）完整入画
		view.core.focus = Vector3(wc.x, view.ground_y(cc.x, cc.y) - 1.6, wc.z)
		view.core.yaw = atan2(-dir.x, -dir.y) # 相机落在核心一侧（朝崖壁看）
		view.core._zoom = 0.55
		view.core._apply_cam()
		for _i in 3:
			await process_frame
		_shot("res://shots/game_cliff.png")
		print("[SHOTS] cliff cell=", cc, " top=", view.ground_y(cc.x, cc.y))
	finish("SHOTS", 14)


## 核心 4..6 圈内最高的崖格（MapGen CLIFF 朝边界半环带；同高取行主序首个）。
func _find_cliff(sc) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_h := 2
	for y in sc.h:
		for x in sc.w:
			var d := Grid.hex_dist(x, y, sc.core.x, sc.core.y)
			if d < 4 or d > 6:
				continue
			var hv: int = sc.height_at(x, y)
			if hv > best_h:
				best_h = hv
				best = Vector2i(x, y)
	return best


func _shot(path: String) -> void:
	var img := root.get_texture().get_image()
	check(img != null, "截图非空 " + path)
	if img == null:
		return
	img.save_png(path)
	print("[SHOTS] ", path, " ", img.get_width(), "x", img.get_height())


## 扫描一个「六邻同为 h0」的可建造空格（填/挖目视件基准：孤立坑/孤立高台四周平坦）。
func _find_flat_free(world, x0: int, y0: int, x1: int, y1: int, exclude: Array) -> Vector2i:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if not world.grid.passable(x, y) or world.grid.get_h(x, y) != 0:
				continue
			if world.building_at(x, y) != null or not world.cell_vacant(x, y):
				continue
			if exclude.has(Vector2i(x, y)):
				continue
			var ok := true
			for k in 6:
				var nx := Grid.nx(x, y, k)
				var ny := Grid.ny(x, y, k)
				if nx < 0 or ny < 0 or nx >= world.grid.w or ny >= world.grid.h:
					ok = false
					break
				if not world.grid.passable(nx, ny) or world.grid.get_h(nx, ny) != 0:
					ok = false
					break
			if ok:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


## 扫描一个可建造空格。
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
