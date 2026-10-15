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
	check(st["field"] == 4096, "field=4096")
	check(st["plain"] == 39312, "plain=39312")
	check(st["solids"] == n_solid, "solids 对拍（%d/%d）" % [st["solids"], n_solid])
	check(st["covers"] == n_cover, "covers 对拍（%d/%d）" % [st["covers"], n_cover])
	check(n_solid > 0 and n_cover > 0, "solid/cover 非空（%d/%d）" % [n_solid, n_cover])
	check(st["cam"] == true, "cam 就位")

	# 连续地面网格结构（世界重做：单网格水密；场内 0.5m 细格 + 场外渐进格距）
	var grounds: Array = []
	for node in view.field_root.get_children():
		if node is MeshInstance3D:
			grounds.append(node)
	check(grounds.size() == 1, "Field 下单地面网格（%d）" % grounds.size())
	if grounds.size() == 1:
		var gmesh: Mesh = grounds[0].mesh
		check(gmesh.get_surface_count() == 1, "网格单 surface")
		var arr: Array = gmesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		check(verts.size() == 56169, "网格顶点数 56169（%d）" % verts.size())
		check(idx.size() == 334176, "网格索引数 334176（%d）" % idx.size())
		# 连续性抽检：穿过核心区的一行采样点，线序无缺口且相邻高差 ≤ 2.0（含 SOLID 1.6 台阶量级）
		var row_ok := true
		var by_x := {}
		for v in verts:
			if absf(v.z) < 0.01 and absf(v.x) <= 32.0:
				by_x[roundi(v.x * 2.0)] = v.y
		var keys: Array = by_x.keys()
		keys.sort()
		if keys.size() < 100:
			row_ok = false
		for i in range(1, keys.size()):
			var k0: int = keys[i - 1]
			var k1: int = keys[i]
			if k1 - k0 != 1:
				row_ok = false # 缺采样线 = 网格断裂
				break
			if absf(float(by_x[k1]) - float(by_x[k0])) > 2.0:
				row_ok = false
				break
		check(row_ok, "网格连续性抽检（无缺线且线高差 ≤ 2.0）")

	print("[SCENE] field=", st["field"], " plain=", st["plain"], " solids=", st["solids"], "/", n_solid, " covers=", st["covers"], "/", n_cover, " cam=", st["cam"])
	finish("SCENE", 11, "ms=%d" % (Time.get_ticks_msec() - t0))
