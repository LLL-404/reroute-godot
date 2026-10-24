extends SceneTree

# 投稿视频取景测试（非闸）：指定 run_index → 新局 → 两机位截图。
# 跑法（cwd=reroute-godot）：
#   $env:PROMO_RUN=0; godot --resolution 1920x1080 -s res://tests/probes/probe_promo_shots.gd
# 输出：shots/promo_test/run{N}_core.png（zoom 0.62 对核心）、run{N}_mid.png（zoom 0.85 中景）

const OUT_DIR := "res://shots/promo_test/"


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var packed: PackedScene = load("res://game/app/main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	for _i in 10:
		await process_frame

	var run := int(OS.get_environment("PROMO_RUN"))
	main.run_index = run - 1
	main.new_game()
	main.start_match()
	var view = main.view
	var world = main.world
	main.paused = true

	print("[PROMO] run=", run, " seed=", main.BASE_SEED + run, " core=", world.sc.core, " spawns=", world.sc.spawns)
	print("[PROMO] waves=", world.sc.waves)

	# 核心周围放两塔一英雄做取景参照（真实建筑）
	var towers: Array = []
	for r in [[3, 8], [-4, 6], [5, -6]]:
		var c := _find_free(world, int(world.sc.core.x) + r[0] - 2, int(world.sc.core.y) + r[1] - 2, int(world.sc.core.x) + r[0] + 2, int(world.sc.core.y) + r[1] + 2, towers)
		if c.x >= 0:
			world.apply_command({ "kind": "tower", "x": c.x, "y": c.y })
			towers.append(c)
	view.sync(world)

	# 机位 1：核心（zoom 0.62）
	var cw: Vector3 = view.cell_to_world(int(world.sc.core.x), int(world.sc.core.y))
	view.core.focus = Vector3(cw.x, 0.0, cw.z)
	view.core._zoom = 0.62
	view.core._apply_cam()
	for _i in 4:
		await process_frame
	_shot(OUT_DIR + "run%d_core.png" % run)

	# 机位 2：核心与盆地中点（zoom 0.85）
	var bc: Vector2i = world.sc.basin_cell()
	var mx := int((world.sc.core.x + bc.x) / 2)
	var my := int((world.sc.core.y + bc.y) / 2)
	var mw: Vector3 = view.cell_to_world(mx, my)
	view.core.focus = Vector3(mw.x, 0.0, mw.z)
	view.core._zoom = 0.85
	view.core._apply_cam()
	for _i in 4:
		await process_frame
	_shot(OUT_DIR + "run%d_mid.png" % run)

	quit(0)


func _shot(path: String) -> void:
	var img: Image = root.get_texture().get_image()
	if img == null:
		print("[PROMO] shot null ", path)
		return
	img.save_png(path)
	print("[PROMO] ", path, " ", img.get_width(), "x", img.get_height())


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
