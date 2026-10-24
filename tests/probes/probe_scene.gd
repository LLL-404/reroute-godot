extends ProbeKit

# C1 判定：主场景 headless 加载 + 地形构建对拍。
# 跑法（cwd=reroute-godot）：godot --headless -s res://tests/probes/probe_scene.gd
# 判定：exit 0 + stdout 含 [SCENE] PASS + stderr 无 ERROR。
const Blueprint = preload("res://game/core/blueprint.gd")
func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var packed: PackedScene = load("res://game/app/main.tscn")
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
	check(st["plain"] == 39820, "plain=39820（六边化：场内区面片整体跳过，只留最外圈缝合环；原 39312 已废止）")
	check(st["solids"] == n_solid, "solids 对拍（%d/%d）" % [st["solids"], n_solid])
	check(st["covers"] == n_cover, "covers 对拍（%d/%d）" % [st["covers"], n_cover])
	check(n_solid > 0 and n_cover > 0, "solid/cover 非空（%d/%d）" % [n_solid, n_cover])
	check(st["cam"] == true, "cam 就位")

	# 连续地面网格结构（2026-10-17 六边化：lattice 底 = 场外渐进环 + 场内最外圈缝合环；
	# 场内高差表现由独立六棱板网格 "HexField" 承担）
	var grounds: Array = []
	var hexes: Array = []
	for node in view.field_root.get_children():
		if node is MeshInstance3D:
			if node.name == "HexField":
				hexes.append(node)
			else:
				grounds.append(node)
	check(grounds.size() == 1, "Field 下单地面网格（%d）" % grounds.size())
	check(hexes.size() == 1, "Field 下六棱板网格（%d）" % hexes.size())
	if grounds.size() == 1:
		var gmesh: Mesh = grounds[0].mesh
		check(gmesh.get_surface_count() == 1, "网格单 surface")
		var arr: Array = gmesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		check(verts.size() == 56169, "网格顶点数 56169（%d）" % verts.size())
		check(idx.size() == 238920, "网格索引数 238920（六边化：场内 126² 面片跳过；原 334176 已废止）")
		# 连续性抽检：穿过核心区的一行采样点，线序无缺口且相邻高差 ≤ 2.0。
		# 2026-10-16 视觉升级例外：地图边框圈为「峡谷崖壁」（RIM_BUMP 4.2，设计意图），
		# 仅允许在最外 1m 带（|x| ≥ 31）出现 >2.0 台阶；其余任何台阶/缺线仍判断裂。
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
				var rim_band := maxi(absi(k0), absi(k1)) >= 62 # x=±31 → k=±62（崖壁带）
				if not rim_band:
					row_ok = false
					break
		check(row_ok, "网格连续性抽检（无缺线且非崖壁带高差 ≤ 2.0）")
	if hexes.size() == 1:
		var hmesh: Mesh = hexes[0].mesh
		check(hmesh.get_surface_count() == 1, "六边网格单 surface")
		var harr: Array = hmesh.surface_get_arrays(0)
		var hv: PackedVector3Array = harr[Mesh.ARRAY_VERTEX]
		check(hv.size() >= 4096 * 7, "六边网格顶点数 ≥ 4096×7（%d）" % hv.size())
		# 抽检：格 (24,24)（开阔格）顶面中心顶点高度 = ground_y
		var w24: Vector3 = view.cell_to_world(24, 24)
		var gy24: float = view.ground_y(24, 24)
		var found := false
		for v2 in hv:
			if absf(v2.x - w24.x) < 0.01 and absf(v2.z - w24.z) < 0.01:
				found = true
				# 2026-10-21 口径变更：地形并台后 _cell_top 被量化到 PLATE_STEP(0.30) 整倍，
				# 与 sim 贴地真值 ground_y 允许有 ≤ 半档偏差（单位/拾取仍走 ground_y，视觉顶可差一格台阶）。
				check(absf(v2.y - gy24) <= 0.30, "六边格(24,24) 顶高对拍（%.3f/%.3f）" % [v2.y, gy24])
				break
		check(found, "六边格(24,24) 中心顶点存在")

	# B2 岩块散布（2026-10-20）：HexField 子节点（不占 field_root 直接子节点名额，ground=1 不变）；
	# 单 surface、顶点数在预算内（默认图实测约 26k；边界留 3k..120k 容纳变幅图）。
	if hexes.size() == 1:
		var rn: Node = hexes[0].get_node_or_null("RockProps")
		var rp: MeshInstance3D = null
		if rn is MeshInstance3D:
			rp = rn
		var rp_ok: bool = rp != null and rp.mesh != null and rp.mesh.get_surface_count() == 1
		check(rp_ok, "岩块散布网格就位（RockProps 单 surface）")
		if rp_ok:
			var rarr: Array = rp.mesh.surface_get_arrays(0)
			var rv: PackedVector3Array = rarr[Mesh.ARRAY_VERTEX]
			check(rv.size() >= 3000 and rv.size() <= 120000, "岩块顶点数在预算内（%d）" % rv.size())

	# ---- 拍2 视觉联动锚点（自由路径首局接线） ----
	var anchor: Dictionary = main._visual_anchor()
	check(anchor.get("ridge_off", false) == true, "自由路径关闭预设岩脊（ridge_off）")
	var rps: Array = anchor.get("ridge_pts", [])
	check(rps.size() >= 1 and rps.size() <= 10, "岩野山体点数 1..10（%d）" % rps.size())
	if not rps.is_empty():
		var r0: Array = rps[0]
		check(r0.size() == 4 and float(r0[2]) >= 2.3 and float(r0[3]) >= 0.8 and float(r0[3]) <= 1.7, "岩野山体参数域")
	check(anchor.has("basin_wx") and anchor.has("basin_wz") and anchor.has("basin_sig"), "2D 盆地锚（wx/wz/sig）")
	var gps: Array = anchor.get("gate_pts", [])
	check(gps.size() == main.sc.spawns.size() - 1, "视觉门数 = 主口数（%d）" % gps.size())
	var in_dom := true
	for gp in gps:
		var gv: Vector2 = gp
		if absf(gv.x) > 32.0 or absf(gv.y) > 32.0:
			in_dom = false
	check(in_dom, "视觉门口位在场内坐标域")
	# 边框豁口：第一主口侧边框格豁开；对侧同横向格不豁
	if not gps.is_empty():
		var g0: Vector2 = gps[0]
		var side := Blueprint.gate_side(g0.x, g0.y)
		var bx := 0
		var by := 0
		var bxo := 0
		var byo := 0
		if side <= 1:
			bx = clampi(int(round(g0.x + 31.5)), 0, 63)
			by = 63 if side == 0 else 0
			bxo = bx
			byo = 0 if side == 0 else 63
		else:
			by = clampi(int(round(g0.y + 31.5)), 0, 63)
			bx = 63 if side == 2 else 0
			byo = by
			bxo = 0 if side == 2 else 63
		var s_carve: float = view.terrain._rim_scale(bx, by)
		var s_ctrl: float = view.terrain._rim_scale(bxo, byo)
		check(s_carve < 0.35, "主口边框豁开（%.2f < 0.35）" % s_carve)
		check(s_ctrl > 0.3, "对侧边框不豁（%.2f > 0.3）" % s_ctrl)
	# 默认种子锚点历史口径不回归
	var keep_sc: Scenario = main.sc
	main.sc = Scenario.new(20261003)
	var a0: Dictionary = main._visual_anchor()
	main.sc = keep_sc
	check(a0.has("ridge_y") and a0.has("gate_x") and a0.has("basin_y") and not a0.has("ridge_pts") and not a0.has("gate_pts"), "默认种子锚点历史口径")

	print("[SCENE] field=", st["field"], " plain=", st["plain"], " solids=", st["solids"], "/", n_solid, " covers=", st["covers"], "/", n_cover, " cam=", st["cam"])
	finish("SCENE", 25, "ms=%d" % (Time.get_ticks_msec() - t0))
