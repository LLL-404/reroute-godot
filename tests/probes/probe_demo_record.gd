extends SceneTree

# 临时实机录屏脚本（TapTap 投稿用，非测试闸）：
# 启动即进入对局，脚本化放墙/放塔/刷怪，Movie Maker 以 60fps 录制。
# 跑法：godot_console --path . --write-movie <out.avi> -s res://tests/probes/probe_demo_record.gd

var main = null
var view = null
var world = null
var spawned_heavy := false


func _initialize() -> void:
	var packed: PackedScene = load("res://game/main.tscn")
	main = packed.instantiate()
	root.add_child(main)
	for _i in 10:
		await process_frame

	# 钉死默认经典图（与商店实机图/投稿讲解片一致）：probe 内自增 1 → run0 → seed 20261003
	main.run_index = -1
	main.new_game()
	main.start_match()
	view = main.view
	world = main.world

	# 镜头：对准核心下方，青玉核心在画面上三分之一，能看清塔防与来路
	var cw: Vector3 = view.cell_to_world(int(world.sc.core.x), int(world.sc.core.y) + 10)
	view.core.focus = Vector3(cw.x, 0.0, cw.z)
	view.core._zoom = 0.55
	view.core._apply_cam()

	# 核心周围三塔 + 英雄（先建好，保证不会失守）
	var towers: Array = []
	for r in [[27, 12, 35, 18], [26, 18, 36, 24], [29, 8, 35, 14]]:
		var c := _find_free(r[0], r[1], r[2], r[3], towers)
		if c.x >= 0:
			world.apply_command({ "kind": "tower", "x": c.x, "y": c.y })
			towers.append(c)
	var hp := _find_free(30, 20, 36, 24, [])
	if hp.x >= 0:
		world.apply_command({ "kind": "hero", "x": hp.x, "y": hp.y })

	# 0.5s：远处刷一小队，前 5 秒有目标在移动
	_spawn_group(3, 20, 52, Sim.E_SWARM)
	await create_timer(1.2).timeout

	# 2s：幽灵预览 → 放一排墙（核心机制）
	var line: Array = main.line_cells(Vector2i(28, 32), Vector2i(35, 32))
	view.show_ghost(line, false)
	await create_timer(1.8).timeout
	for c in line:
		world.apply_command({ "kind": "wall", "x": c.x, "y": c.y })
	view.show_ghost([], false)
	await create_timer(4.0).timeout

	# 8s：热层展示
	view.set_heat(true)
	await create_timer(3.5).timeout
	view.set_heat(false)

	# 12s：第二段墙，把来路继续拉长
	var line2: Array = main.line_cells(Vector2i(24, 38), Vector2i(31, 38))
	for c in line2:
		world.apply_command({ "kind": "wall", "x": c.x, "y": c.y })
	_spawn_group(3, 18, 54, Sim.E_SWARM)
	await create_timer(8.0).timeout

	# 20s：一只重甲，展示赏金机制；镜头稍拉远
	view.core._zoom = 0.48
	view.core._apply_cam()
	if not spawned_heavy:
		_spawn_group(1, 26, 56, Sim.E_BEHEMOTH)
		spawned_heavy = true
	await create_timer(8.0).timeout

	# 28s：最后一波虫群
	if int(world.core["hp"]) > 700:
		_spawn_group(4, 16, 52, Sim.E_SWARM)
	await create_timer(8.0).timeout

	# 36s：再补两塔，收尾
	var t4 := _find_free(26, 14, 38, 22, towers)
	if t4.x >= 0:
		world.apply_command({ "kind": "tower", "x": t4.x, "y": t4.y })
	await create_timer(5.0).timeout

	print("[DEMO] done hp=", int(world.core["hp"]), " outcome=", world.outcome)
	quit(0)


func _spawn_group(n: int, x0: int, y0: int, kind_id: int) -> void:
	var used: Array = []
	for _i in n:
		var c := _find_free(x0, y0, x0 + 12, y0 + 7, used)
		if c.x < 0:
			return
		used.append(c)
		world.apply_command({ "kind": "spawn", "x": c.x, "y": c.y, "speed": 4, "kind_id": kind_id })


func _find_free(x0: int, y0: int, x1: int, y1: int, exclude: Array) -> Vector2i:
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
