extends ProbeKit

# C2 判定：视觉同步逐位正确。
# 做法：接管主循环（关 main._process），逐 tick 推进 + view.sync，
# 按母版（view3d.lua）插值口径重算全部实体期望值，与节点实测对拍：
#   单位位置/缩放/受击脉冲、建筑位置/施工压扁、英雄位置/起伏、死亡消散、震荡环、幽灵（逐格/斜线）、热层。
# 跑法（cwd=reroute-godot，窗口模式）：godot -s res://tests/probes/probe_sync.gd
# 判定：exit 0 + stdout 含 [SYNC] match=100 + stderr 无 ERROR。
var moved_seen := 0
var prev_cells := {} # id -> Vector2i（上一 tick 快照）
var prev_hero := Vector2i(-1, -1)


func _initialize() -> void:
	var packed: PackedScene = load("res://game/main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	main.set_process(false) # 探针独占推进，保证确定性
	main.paused = true
	for _i in 3:
		await process_frame

	var view = main.view
	var world = main.world

	# 锚点：坐标映射的独立字面量检查（其余对拍以此为基）
	cmp_v3(view.cell_to_world(0, 0), Vector3(-31.5, 0.0, -31.5), "cell_to_world(0,0)")
	cmp_v3(view.cell_to_world(63, 63), Vector3(32.0, 0.0, 31.5), "cell_to_world(63,63)（六边 odd-r：63 为奇行 +0.5 右移；原方形口径 31.5 已废止）")

	# ---- 布置：2 单位 + 墙 + 塔（远处）+ 英雄移动 ----
	var spawn_a := _find_free(world, 24, 8, 40, 16, [])
	var spawn_b := _find_free(world, 24, 8, 40, 16, [spawn_a])
	var wall_cell := _find_free(world, 24, 8, 40, 16, [spawn_a, spawn_b])
	var tower_cell := _find_free(world, 0, 0, 63, 63, [], Vector2i(32, 8), 900)
	var hero_target := _find_free(world, 26, 20, 38, 34, [])
	check(spawn_a.x >= 0 and spawn_b.x >= 0, "出生格扫描")
	check(wall_cell.x >= 0, "墙格扫描")
	check(tower_cell.x >= 0, "塔格扫描（距英雄出生 >30 格）")
	check(hero_target.x >= 0, "英雄目标格扫描")
	if bad > 0:
		_report()
		return

	world.apply_command({ "kind": "wall", "x": wall_cell.x, "y": wall_cell.y })
	world.apply_command({ "kind": "tower", "x": tower_cell.x, "y": tower_cell.y })
	world.apply_command({ "kind": "spawn", "x": spawn_a.x, "y": spawn_a.y, "speed": 4, "kind_id": Sim.E_SWARM })
	world.apply_command({ "kind": "spawn", "x": spawn_b.x, "y": spawn_b.y, "speed": 8, "kind_id": Sim.E_BEHEMOTH })
	world.apply_command({ "kind": "hero", "x": hero_target.x, "y": hero_target.y })
	view.sync(world)

	# 初建断言：节点齐、种类缩放字面量
	var st0: Dictionary = view.debug_stats()
	cmp_int(st0["units"], 2, "初始单位节点数")
	cmp_int(st0["buildings"], 3, "初始建筑节点数（核心+墙+塔）")
	check(st0["hero"] == true, "英雄节点")
	var e1a = view.unit_nodes.get(1)
	var e2a = view.unit_nodes.get(2)
	if e1a != null:
		var p1: AnimationPlayer = e1a["player"]
		check(p1 != null and p1.current_animation == "Crawl", "虫群模型基态 Crawl")
	if e2a != null:
		var p2: AnimationPlayer = e2a["player"]
		check(p2 != null and p2.current_animation == "Crawl", "蛮兽模型基态 Crawl")

	prev_hero = Vector2i(int(world.hero["x"]), int(world.hero["y"]))

	# ---- 主循环：130 tick 逐拍对拍 ----
	for _step in 130:
		world.tick()
		var t: int = world.tick_count
		view.sync(world)
		_verify(view, world)

		# 脚本时刻（同步后施加）
		if t == 40:
			var u1 = _find_unit(world, 1)
			if u1 != null:
				u1["hp"] = int(u1["hp"]) - 5 # 白盒：制造受击脉冲
		elif t == 60:
			var u1c = _find_unit(world, 1)
			if u1c != null:
				u1c["hp"] = 0 # 白盒：制造死亡消散（视图口径=实体从活表消失）
				check(true, "t=60 置 hp=0")
			else:
				check(false, "t=60 找不到单位 1")
		elif t == 90:
			world.apply_command({ "kind": "shock" }) # 触发震荡环；下一 tick 冷却跳变被视图捕获

		# 纯观测时刻
		if t == 41:
			var e41 = view.unit_nodes.get(1)
			check(e41 != null and int(e41["pulse"]) == 41, "受击脉冲置位 t=41")
			if e41 != null:
				var ph41: AnimationPlayer = e41["player"]
				check(ph41 != null and ph41.current_animation == "Hurt", "受击动画 Hurt t=41")
		elif t == 47:
			var e47 = view.unit_nodes.get(1)
			check(e47 != null and int(e47["pulse"]) == -1, "脉冲衰减清除 t=47")
		elif t == 51:
			var e51 = view.unit_nodes.get(1)
			if e51 != null:
				var pc51: AnimationPlayer = e51["player"]
				check(pc51 != null and pc51.current_animation == "Crawl", "受击到期回 Crawl t=51")
			else:
				check(false, "t=51 单位 1 丢失")
		elif t == 61:
			cmp_int(int(view.debug_stats()["death_fx"]), 1, "死亡消散出现 t=61")
			if view.death_fx.size() == 1:
				var df61: Dictionary = view.death_fx[0]
				var pd61: AnimationPlayer = df61["player"]
				check(pd61 != null and pd61.current_animation == "Death", "死亡动画启动 t=61")
		elif t == 68:
			if view.death_fx.size() == 1:
				var df: Dictionary = view.death_fx[0]
				var dn7: Node3D = df["node"]
				cmp_v3(dn7.scale, Vector3(1.0, 1.0, 1.0), "死亡路径不做放大下沉 t=68")
			else:
				check(false, "t=68 消散条目数不符")
		elif t == 73:
			cmp_int(int(view.debug_stats()["death_fx"]), 1, "死亡动画中（寿命 28）t=73")
		elif t == 89:
			cmp_int(int(view.debug_stats()["death_fx"]), 0, "死亡动画播完移除 t=89")
		elif t == 91:
			check(view.ring != null, "震荡环出现 t=91")
			if view.ring != null:
				var rn: Node3D = view.ring["node"]
				cmp_int(rn.get_child_count(), 4, "震荡环边数")
				cmp_v3(rn.scale, Vector3(0.3, 1.0, 0.3), "震荡环初始缩放")
		elif t == 95:
			if view.ring != null:
				var rn2: Node3D = view.ring["node"]
				var k9 := 4.0 / 7.0
				cmp_v3(rn2.scale, Vector3(0.3 + 2.7 * k9, 1.0, 0.3 + 2.7 * k9), "震荡环扩散 t=95")
			else:
				check(false, "t=95 震荡环丢失")
		elif t == 98:
			check(view.ring == null and view.debug_stats()["ring_fx"] == false, "震荡环移除 t=98")

		# 快照（供下一 tick 的期望值）
		prev_cells = {}
		for u in world.units:
			prev_cells[int(u["id"])] = Vector2i(int(u["x"]), int(u["y"]))
		prev_hero = Vector2i(int(world.hero["x"]), int(world.hero["y"]))

	# ---- 幽灵预览（逐格绘制：直连 + 斜线不越线）----
	var straight := [Vector2i(8, 8), Vector2i(9, 8), Vector2i(10, 8), Vector2i(11, 8)]
	_ghost_cells_check(view, straight, false)
	view.show_ghost(straight, true)
	if view.ghost_alive:
		check(view.ghost_mi.material_override == view.mats["ghost_bad"], "幽灵无效染色 bad")
	var diag := [Vector2i(8, 8), Vector2i(9, 9), Vector2i(10, 10), Vector2i(11, 11)]
	_ghost_cells_check(view, diag, false)
	view.show_ghost([])
	check(view.ghost_alive == false and view.ghost == null, "幽灵清除")

	# ---- 热层 ----
	view.set_heat(true)
	view.sync(world)
	var exp_total := 0
	var maxd := 0
	var dists := []
	dists.resize(64 * 64)
	for y in 64:
		for x in 64:
			var d: int = world.field.dist_at(x, y)
			if d > maxd:
				maxd = d
			dists[y * 64 + x] = d
			if d >= 0:
				exp_total += 1
	cmp_int(int(view.debug_stats()["heat"]), exp_total, "热层实例数")
	var band_counts := [0, 0, 0, 0, 0, 0]
	for i in 64 * 64:
		var d2: int = dists[i]
		if d2 >= 0:
			var band: int = mini(6, 1 + (d2 * 6) / (maxd + 1))
			band_counts[band - 1] += 1
	if view.heat_root != null:
		for i in 6:
			var mmi: MultiMeshInstance3D = view.heat_root.get_child(i)
			cmp_int(mmi.multimesh.instance_count, band_counts[i], "热层第 %d 带" % (i + 1))
	else:
		check(false, "热层根缺失")
	view.set_heat(false)
	view.sync(world)
	check(view.heat_enabled() == false and int(view.debug_stats()["heat"]) == 0, "热层关闭清空")

	# ---- 落差边自然化（T1：分级 / 剖面形状 / 顶点账目 / 重建确定性）----
	_terrain_edge_check(view, world)

	# ---- 汇总 ----
	check(moved_seen >= 20, "移动覆盖（moved_seen=%d）" % moved_seen)
	_report()


func _verify(view, world) -> void:
	var t: int = world.tick_count
	# 单位：位置/缩放/脉冲 + 计数
	var alive := 0
	for u in world.units:
		if int(u["hp"]) > 0:
			alive += 1
			var uid: int = u["id"]
			var e = view.unit_nodes.get(uid)
			if e == null:
				fail("单位 %d 无节点 t=%d" % [uid, t])
				continue
			var p: Vector2i = prev_cells.get(uid, Vector2i(int(u["x"]), int(u["y"])))
			var cw: Vector3 = view.cell_to_world(int(u["x"]), int(u["y"]))
			var pw: Vector3 = view.cell_to_world(p.x, p.y)
			var frac := float((t + uid) % int(u["speed_ticks"])) / float(u["speed_ticks"])
			var ex := pw.x + (cw.x - pw.x) * frac
			var ez := pw.z + (cw.z - pw.z) * frac
			var ey: float = view.ground_y(p.x, p.y) * (1.0 - frac) + view.ground_y(int(u["x"]), int(u["y"])) * frac
			var m := 1.0
			var pulse_i: int = e["pulse"]
			if pulse_i >= 0:
				var a := 1.0 - float(t - pulse_i) / 6.0
				if a > 0.0:
					m = 1.0 + 0.6 * a
			var nd: Node3D = e["node"]
			cmp_v3(nd.position, Vector3(ex, ey + 0.02, ez), "单位 %d 位置 t=%d" % [uid, t])
			cmp_v3(nd.scale, Vector3(m, m, m), "单位 %d 缩放 t=%d" % [uid, t])
			var dx := cw.x - pw.x
			var dz := cw.z - pw.z
			if dx * dx + dz * dz > 1e-9:
				moved_seen += 1
				var want_yaw := atan2(dx, dz) + float(view.Z_YAW)
				var got_yaw := nd.rotation.y
				var dyaw := absf(got_yaw - want_yaw)
				dyaw = minf(dyaw, absf(dyaw - TAU))
				check(dyaw <= 0.02, "单位 %d 朝向 t=%d got=%.4f want=%.4f" % [uid, t, got_yaw, want_yaw])
	cmp_int(view.unit_nodes.size(), alive, "单位节点数 t=%d" % t)

	# 建筑：位置/施工压扁 + 计数
	var alive_b := 0
	for b in world.buildings:
		if int(b["hp"]) > 0:
			alive_b += 1
			var e2 = view.building_nodes.get(int(b["id"]))
			if e2 == null:
				fail("建筑 %d 无节点 t=%d" % [int(b["id"]), t])
				continue
			var w2: Vector3 = view.cell_to_world(int(b["x"]), int(b["y"]))
			var gy2: float = view.ground_y(int(b["x"]), int(b["y"]))
			var bnd: Node3D = e2["node"]
			cmp_v3(bnd.position, Vector3(w2.x, gy2, w2.z), "建筑 %d 位置 t=%d" % [int(b["id"]), t])
			var k := 0.35 if int(b["build_left"]) > 0 else 1.0
			cmp_v3(bnd.scale, Vector3(0.96, k, 0.96), "建筑 %d 压扁 t=%d" % [int(b["id"]), t])
	cmp_int(view.building_nodes.size(), alive_b, "建筑节点数 t=%d" % t)

	# 英雄：位置/起伏/朝向
	var h: Dictionary = world.hero
	if view.hero == null:
		fail("英雄无节点 t=%d" % t)
		return
	var ph := prev_hero
	if ph.x < 0:
		ph = Vector2i(int(h["x"]), int(h["y"]))
	var frac2 := float((t + 1) % int(Sim.HERO["speed_ticks"])) / float(Sim.HERO["speed_ticks"])
	var cw2: Vector3 = view.cell_to_world(int(h["x"]), int(h["y"]))
	var pw2: Vector3 = view.cell_to_world(ph.x, ph.y)
	var ix2 := pw2.x + (cw2.x - pw2.x) * frac2
	var iz2 := pw2.z + (cw2.z - pw2.z) * frac2
	var iy2: float = view.ground_y(ph.x, ph.y) * (1.0 - frac2) + view.ground_y(int(h["x"]), int(h["y"])) * frac2
	var moving := (cw2.x != pw2.x or cw2.z != pw2.z)
	var bob := 0.03 * sin(frac2 * 6.283) if moving else 0.0
	var hnd: Node3D = view.hero["node"]
	cmp_v3(hnd.position, Vector3(ix2, iy2 + bob, iz2), "英雄位置 t=%d" % t)
	if moving:
		moved_seen += 1
		var want_hyaw := atan2(cw2.x - pw2.x, cw2.z - pw2.z)
		var got_hyaw := hnd.rotation.y
		var dhy := absf(got_hyaw - want_hyaw)
		dhy = minf(dhy, absf(dhy - TAU))
		check(dhy <= 0.02, "英雄朝向 t=%d got=%.4f want=%.4f" % [t, got_hyaw, want_hyaw])


## 幽灵逐格断言：盒数 = 格数，且逐格世界位/缩放/染色对拍（直连与斜线共用）。
func _ghost_cells_check(view, cells: Array, bad: bool) -> void:
	view.show_ghost(cells, bad)
	check(view.ghost_alive == true, "幽灵出现")
	if not view.ghost_alive:
		return
	cmp_int(view.ghost.get_child_count(), cells.size(), "虚空盒数=格数（%d 格）" % cells.size())
	if view.ghost.get_child_count() != cells.size():
		return
	var mat: Material = view.mats["ghost_bad"] if bad else view.mats["ghost_ok"]
	for i in cells.size():
		var c: Vector2i = cells[i]
		var w: Vector3 = view.cell_to_world(c.x, c.y)
		var mi: MeshInstance3D = view.ghost.get_child(i)
		cmp_v3(mi.position, Vector3(w.x, view.ground_y(c.x, c.y) + 0.12, w.z), "虚空格(%d,%d)世界位" % [c.x, c.y])
		cmp_v3(mi.scale, Vector3(0.96, 0.24, 0.96), "虚空格(%d,%d)缩放" % [c.x, c.y])
		check(mi.material_override == mat, "虚空格(%d,%d)染色" % [c.x, c.y])


func _find_unit(world, uid: int):
	for u in world.units:
		if int(u["id"]) == uid:
			return u
	return null


## 扫描可通行空格（行主序）。far_from/min_d2 用于保证塔远离战场。
func _find_free(world, x0: int, y0: int, x1: int, y1: int, exclude: Array, far_from: Vector2i = Vector2i(-1, -1), min_d2: int = 0) -> Vector2i:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if far_from.x >= 0:
				var ddx := x - far_from.x
				var ddy := y - far_from.y
				if ddx * ddx + ddy * ddy < min_d2:
					continue
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


## 落差边自然化断言（2026-10-17 T1）：分级以**模拟高度差**为真值（Δ1=可爬坡/Δ≥2=崖壁/
## 同层=石阶/实心邻=崖壁）；剖面 P0 恒在顶面边框线（无顶缝）且高度单调不增；网格顶点账目
## 独立重算逐点吻合；同状态重建两次逐位一致。旧实现无 edge_kind_at → 本段干净 FAIL（负对照）。
func _terrain_edge_check(view, world) -> void:
	var T = view.terrain
	if not (T.has_method("edge_kind_at") and T.has_method("edge_profile")):
		fail("地形自然化接口缺失（edge_kind_at/edge_profile；负对照=旧实现）")
		return
	var core_cmap: Dictionary = view.core.get_script().get_script_constant_map()
	var CELL_N: int = int(core_cmap["CELL_N"])

	# 平整格（六邻同层且空置）→ 填两级验证分级真值
	var c := _find_flat(world, CELL_N, 8, 24, 20, 34)
	check(c.x >= 0, "平整格扫描（六邻同层 + 空置 + 邻界内）")
	if c.x < 0:
		return
	var h0: int = world.grid.get_h(c.x, c.y)
	world.apply_command({ "kind": "fill", "x": c.x, "y": c.y })
	cmp_int(world.grid.get_h(c.x, c.y), h0 + 1, "填一级成功")
	var kinds1 := _edge_kinds6(T, c)
	check(_all_eq(kinds1, 1), "填一级后 6 边全为可爬坡 EDGE_RAMP（kinds=%s）" % str(kinds1))
	world.apply_command({ "kind": "fill", "x": c.x, "y": c.y })
	cmp_int(world.grid.get_h(c.x, c.y), h0 + 2, "填二级成功")
	var kinds2 := _edge_kinds6(T, c)
	check(_all_eq(kinds2, 2), "填二级后 6 边全为崖壁 EDGE_CLIFF（kinds=%s）" % str(kinds2))

	# 重建后拿网格 → 顶点账目独立重算 + 确定性
	view.sync(world)
	var mesh: ArrayMesh = T._hex.mesh
	var arr1: Array = mesh.surface_get_arrays(0)
	var v1: PackedVector3Array = arr1[Mesh.ARRAY_VERTEX]
	var i1: PackedInt32Array = arr1[Mesh.ARRAY_INDEX]
	var expect := _edge_verts_expect(T, CELL_N)
	cmp_int(v1.size(), expect, "顶点账目（独立重算：顶面 7×4096 + 逐边 strip×4×(双面×2)）")
	check(v1.size() > 4096 * 7 and v1.size() < 4096 * 64, "顶点数量级可控（%d）" % v1.size())
	T._rebuild_field()
	var arr2: Array = T._hex.mesh.surface_get_arrays(0)
	var v2: PackedVector3Array = arr2[Mesh.ARRAY_VERTEX]
	var i2: PackedInt32Array = arr2[Mesh.ARRAY_INDEX]
	check(v2 == v1 and i2 == i1, "同状态重建逐位一致（顶点 %d/索引 %d）" % [v1.size(), i1.size()])

	# 剖面形状（当前 = 二级高格 vs 邻格：崖壁）
	_profile_shape_check(T, CELL_N, c.x, c.y, 0, 2)
	# 降一级 → 可爬坡剖面
	world.apply_command({ "kind": "lower", "x": c.x, "y": c.y })
	var hd: int = world.grid.get_h(c.x, c.y)
	cmp_int(hd, h0 + 1, "降一级成功")
	var kinds_l := _edge_kinds6(T, c)
	check(_all_eq(kinds_l, 1), "降一级后 6 边回可爬坡（kinds=%s）" % str(kinds_l))
	view.sync(world)
	_profile_shape_check(T, CELL_N, c.x, c.y, 0, 1)

	# 实心邻 → 崖壁；同层起伏 → 石阶（微差）
	var se := _find_solid_edge(world, CELL_N)
	check(se.x >= 0, "实心邻边扫描")
	if se.x >= 0:
		cmp_int(T.edge_kind_at(se.x, se.y, se.z), 2, "实心邻边 = 崖壁")
	var me := _find_micro_edge(T, world, CELL_N)
	check(me.x >= 0, "同层起伏边扫描")
	if me.x >= 0:
		cmp_int(T.edge_kind_at(me.x, me.y, me.z), 0, "同层高差边 = 石阶（微差）")


## 剖面形状：P0 恒在顶面边框线（无顶缝）；末点贴低邻顶；高度单调不增；外伸在界内。
func _profile_shape_check(T, CELL_N: int, x: int, y: int, k: int, kind: int) -> void:
	var t: float = T._cell_top[y * CELL_N + x]
	var nx := Grid.nx(x, y, k)
	var ny := Grid.ny(x, y, k)
	var t_lo: float = T._cell_top[ny * CELL_N + nx]
	var p: PackedFloat64Array = T.edge_profile(x, y, k, t, t_lo, kind)
	var pts: int = p.size() / 2
	check(pts >= 4, "剖面点数 ≥4（kind=%d pts=%d）" % [kind, pts])
	check(p[0] == 0.0 and p[1] == t, "剖面 P0 在顶面边框线（kind=%d）" % kind)
	var r_end: float = p[p.size() - 2]
	var h_end: float = p[p.size() - 1]
	check(r_end >= 0.004 and r_end <= 0.6, "剖面末端外伸合范围（kind=%d r=%.3f）" % [kind, r_end])
	check(h_end >= t_lo - 0.03 and h_end <= t_lo + 0.05, "剖面末点贴/沉低邻顶（kind=%d h=%.3f t_lo=%.3f）" % [kind, h_end, t_lo])
	var desc := true
	for j in range(1, pts):
		if p[j * 2 + 1] > p[(j - 1) * 2 + 1] + 0.001:
			desc = false
	check(desc, "剖面高度单调不增（kind=%d）" % kind)


## 顶点账目独立重算：顶面恒 7 顶点/格；界外边（崖壁·双面）按崖壁剖面 strip×4×2；
## 内侧画出边按 kind 剖面点数（函数内自调 edge_profile 取点数，跟随实现演进）× 4 顶点；被跳过边 0。
## 等高阈值取 T.EDGE_MIN_DH（2026-10-20 由 0.02 降到 0.001：旧阈值会漏画 0~2cm 高差边，
## 平顶缝透出背景成「边缘发光」；探针与渲染共用同一常量，防止再次分叉）。
func _edge_verts_expect(T, CELL_N: int) -> int:
	var min_dh: float = float(T.get_script().get_script_constant_map().get("EDGE_MIN_DH", 0.001))
	var total := 0
	for y in CELL_N:
		for x in CELL_N:
			total += 7
			var t: float = T._cell_top[y * CELL_N + x]
			for k in 6:
				var nx := Grid.nx(x, y, k)
				var ny := Grid.ny(x, y, k)
				if nx < 0 or ny < 0 or nx >= CELL_N or ny >= CELL_N:
					var po: int = T.edge_profile(x, y, k, t, t - 1.0, T.EDGE_CLIFF).size() / 2
					total += (po - 1) * 4 * 2
					continue
				var t2: float = T._cell_top[ny * CELL_N + nx]
				if t <= t2 + min_dh:
					continue
				var pts: int = T.edge_profile(x, y, k, t, t2, T.edge_kind_at(x, y, k)).size() / 2
				total += (pts - 1) * 4
	return total


func _find_flat(world, CELL_N: int, x0: int, y0: int, x1: int, y1: int) -> Vector2i:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if not world.grid.passable(x, y) or world.building_at(x, y) != null or not world.cell_vacant(x, y):
				continue
			var hr: Dictionary = world.hero
			if x == int(hr["x"]) and y == int(hr["y"]):
				continue
			var h: int = world.grid.get_h(x, y)
			var ok := true
			for k in 6:
				var nx := Grid.nx(x, y, k)
				var ny := Grid.ny(x, y, k)
				if nx < 0 or ny < 0 or nx >= CELL_N or ny >= CELL_N or not world.grid.passable(nx, ny) or world.grid.get_h(nx, ny) != h:
					ok = false
					break
			if ok:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func _find_solid_edge(world, CELL_N: int) -> Vector3i:
	for y in CELL_N:
		for x in CELL_N:
			if not world.grid.passable(x, y):
				continue
			for k in 6:
				var nx := Grid.nx(x, y, k)
				var ny := Grid.ny(x, y, k)
				if nx >= 0 and ny >= 0 and nx < CELL_N and ny < CELL_N and world.grid.at(nx, ny) == Grid.SOLID:
					return Vector3i(x, y, k)
	return Vector3i(-1, -1, -1)


func _find_micro_edge(T, world, CELL_N: int) -> Vector3i:
	for y in CELL_N:
		for x in CELL_N:
			if not world.grid.passable(x, y):
				continue
			var t: float = T._cell_top[y * CELL_N + x]
			for k in 6:
				var nx := Grid.nx(x, y, k)
				var ny := Grid.ny(x, y, k)
				if nx < 0 or ny < 0 or nx >= CELL_N or ny >= CELL_N:
					continue
				if not world.grid.passable(nx, ny):
					continue
				if world.grid.get_h(nx, ny) != world.grid.get_h(x, y):
					continue
				if t <= T._cell_top[ny * CELL_N + nx] + 0.02:
					continue
				return Vector3i(x, y, k)
	return Vector3i(-1, -1, -1)


func _edge_kinds6(T, c: Vector2i) -> Array:
	var out := []
	for k in 6:
		out.append(T.edge_kind_at(c.x, c.y, k))
	return out


func _all_eq(arr: Array, v: int) -> bool:
	for a in arr:
		if a != v:
			return false
	return true


## 收口：统一夹具输出 + sync 专属 moved/match 附加列。
func _report() -> void:
	var match_pct := 100 if bad == 0 else int(100.0 * float(checks - bad) / float(maxi(checks, 1)))
	finish("SYNC", 300, "moved=%d match=%d" % [moved_seen, match_pct])
