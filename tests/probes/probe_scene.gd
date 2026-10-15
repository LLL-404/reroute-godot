extends ProbeKit

# C1 判定：主场景 headless 加载 + 地形构建对拍。
# 跑法（cwd=reroute-godot）：godot --headless -s res://tests/probes/probe_scene.gd
# 判定：exit 0 + stdout 含 [SCENE] PASS + stderr 无 ERROR。
func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var packed: PackedScene = load("res://game/main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	for _i in 5:
		await process_frame

	var view = main.view
	var world = main.world

	# 期望值：直接从 sim 网格计数
	var n_solid := 0
	var n_cover := 0
	for y in world.grid.h:
		for x in world.grid.w:
			var c: int = world.grid.at(x, y)
			if c == Grid.SOLID:
				n_solid += 1
			elif c == Grid.COVER:
				n_cover += 1

	var st: Dictionary = view.debug_stats()
	check(st["field"] == 2304, "field=2304")
	check(st["ring"] == 4384, "ring=4384")
	check(st["solids"] == n_solid, "solids 对拍（%d/%d）" % [st["solids"], n_solid])
	check(st["covers"] == n_cover, "covers 对拍（%d/%d）" % [st["covers"], n_cover])
	check(n_solid > 0 and n_cover > 0, "solid/cover 非空（%d/%d）" % [n_solid, n_cover])
	check(st["cam"] == true, "cam 就位")

	print("[SCENE] field=", st["field"], " ring=", st["ring"], " solids=", st["solids"], "/", n_solid, " covers=", st["covers"], "/", n_cover, " cam=", st["cam"])
	finish("SCENE", 6, "ms=%d" % (Time.get_ticks_msec() - t0))
