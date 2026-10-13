extends SceneTree

# C2 判定：视觉同步逐位正确。
# 做法：接管主循环（关 main._process），逐 tick 推进 + view.sync，
# 按母版（view3d.lua）插值口径重算全部实体期望值，与节点实测对拍：
#   单位位置/缩放/受击脉冲、建筑位置/施工压扁、英雄位置/起伏、死亡消散、震荡环、幽灵、热层。
# 跑法（cwd=reroute-godot）：godot --headless -s res://probe_sync.gd
# 判定：exit 0 + stdout 含 [SYNC] match=100 + stderr 无 ERROR。
var checks := 0
var bad := 0
var first_bad := ""
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
	_cmp_v3(view.cell_to_world(0, 0), Vector3(-23.5, 0.0, -23.5), "cell_to_world(0,0)")
	_cmp_v3(view.cell_to_world(47, 47), Vector3(23.5, 0.0, 23.5), "cell_to_world(47,47)")

	# ---- 布置：2 单位 + 墙 + 塔（远处）+ 英雄移动 ----
	var spawn_a := _find_free(world, 16, 8, 32, 16, [])
	var spawn_b := _find_free(world, 16, 8, 32, 16, [spawn_a])
	var wall_cell := _find_free(world, 16, 8, 32, 16, [spawn_a, spawn_b])
	var tower_cell := _find_free(world, 0, 0, 47, 47, [], Vector2i(24, 8), 900)
	var hero_target := _find_free(world, 18, 20, 30, 34, [])
	_gcheck(spawn_a.x >= 0 and spawn_b.x >= 0, "出生格扫描")
	_gcheck(wall_cell.x >= 0, "墙格扫描")
	_gcheck(tower_cell.x >= 0, "塔格扫描（距英雄出生 >30 格）")
	_gcheck(hero_target.x >= 0, "英雄目标格扫描")
	if bad > 0:
		_finish(1)

	world.apply_command({ "kind": "wall", "x": wall_cell.x, "y": wall_cell.y })
	world.apply_command({ "kind": "tower", "x": tower_cell.x, "y": tower_cell.y })
	world.apply_command({ "kind": "spawn", "x": spawn_a.x, "y": spawn_a.y, "speed": 4, "kind_id": Sim.E_SWARM })
	world.apply_command({ "kind": "spawn", "x": spawn_b.x, "y": spawn_b.y, "speed": 8, "kind_id": Sim.E_BEHEMOTH })
	world.apply_command({ "kind": "hero", "x": hero_target.x, "y": hero_target.y })
	view.sync(world)

	# 初建断言：节点齐、种类缩放字面量
	var st0: Dictionary = view.debug_stats()
	_cmp_int(st0["units"], 2, "初始单位节点数")
	_cmp_int(st0["buildings"], 3, "初始建筑节点数（核心+墙+塔）")
	_gcheck(st0["hero"] == true, "英雄节点")
	var e1a = view.unit_nodes.get(1)
	var e2a = view.unit_nodes.get(2)
	if e1a != null:
		_gcheck(absf(float(e1a["s"]) - 0.42) < 1e-9, "虫群缩放字面量 0.42")
	if e2a != null:
		_gcheck(absf(float(e2a["s"]) - 0.72) < 1e-9, "蛮兽缩放字面量 0.72")

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
				_gcheck(true, "t=60 置 hp=0")
			else:
				_gcheck(false, "t=60 找不到单位 1")
		elif t == 90:
			world.apply_command({ "kind": "shock" }) # 触发震荡环；下一 tick 冷却跳变被视图捕获

		# 纯观测时刻
		if t == 41:
			var e41 = view.unit_nodes.get(1)
			_gcheck(e41 != null and int(e41["pulse"]) == 41, "受击脉冲置位 t=41")
		elif t == 47:
			var e47 = view.unit_nodes.get(1)
			_gcheck(e47 != null and int(e47["pulse"]) == -1, "脉冲衰减清除 t=47")
		elif t == 61:
			_cmp_int(int(view.debug_stats()["death_fx"]), 1, "死亡消散出现 t=61")
		elif t == 68:
			if view.death_fx.size() == 1:
				var df: Dictionary = view.death_fx[0]
				var s7: float = df["s"]
				var k7 := 7.0 / 12.0
				var dn7: Node3D = df["node"]
				_cmp_v3(dn7.scale, Vector3(s7 * (1.0 + 2.0 * k7), s7 * (1.0 - 0.6 * k7), s7 * (1.0 + 2.0 * k7)), "死亡消散缩放 t=68")
			else:
				_gcheck(false, "t=68 消散条目数不符")
		elif t == 73:
			_cmp_int(int(view.debug_stats()["death_fx"]), 0, "死亡消散移除 t=73")
		elif t == 91:
			_gcheck(view.ring != null, "震荡环出现 t=91")
			if view.ring != null:
				var rn: Node3D = view.ring["node"]
				_cmp_int(rn.get_child_count(), 4, "震荡环边数")
				_cmp_v3(rn.scale, Vector3(0.3, 1.0, 0.3), "震荡环初始缩放")
		elif t == 95:
			if view.ring != null:
				var rn2: Node3D = view.ring["node"]
				var k9 := 4.0 / 7.0
				_cmp_v3(rn2.scale, Vector3(0.3 + 2.7 * k9, 1.0, 0.3 + 2.7 * k9), "震荡环扩散 t=95")
			else:
				_gcheck(false, "t=95 震荡环丢失")
		elif t == 98:
			_gcheck(view.ring == null and view.debug_stats()["ring_fx"] == false, "震荡环移除 t=98")

		# 快照（供下一 tick 的期望值）
		prev_cells = {}
		for u in world.units:
			prev_cells[int(u["id"])] = Vector2i(int(u["x"]), int(u["y"]))
		prev_hero = Vector2i(int(world.hero["x"]), int(world.hero["y"]))

	# ---- 幽灵预览 ----
	view.show_ghost([Vector2i(8, 8), Vector2i(11, 8)], false)
	_gcheck(view.ghost_alive == true, "幽灵出现")
	if view.ghost_alive:
		var gy: float = maxf(view.ground_y(8, 8), view.ground_y(11, 8))
		_cmp_v3(view.ghost.position, Vector3(-14.0, gy + 0.12, -15.5), "幽灵位置")
		_cmp_v3(view.ghost.scale, Vector3(3.06, 0.24, 0.96), "幽灵缩放")
		_gcheck(view.ghost_mi.material_override == view.mats["ghost_ok"], "幽灵有效性染色 ok")
	view.show_ghost([Vector2i(8, 8), Vector2i(11, 8)], true)
	if view.ghost_alive:
		_gcheck(view.ghost_mi.material_override == view.mats["ghost_bad"], "幽灵无效染色 bad")
	view.show_ghost([])
	_gcheck(view.ghost_alive == false and view.ghost == null, "幽灵清除")

	# ---- 热层 ----
	view.set_heat(true)
	view.sync(world)
	var exp_total := 0
	var maxd := 0
	var dists := []
	dists.resize(48 * 48)
	for y in 48:
		for x in 48:
			var d: int = world.field.dist_at(x, y)
			if d > maxd:
				maxd = d
			dists[y * 48 + x] = d
			if d >= 0:
				exp_total += 1
	_cmp_int(int(view.debug_stats()["heat"]), exp_total, "热层实例数")
	var band_counts := [0, 0, 0, 0, 0, 0]
	for i in 48 * 48:
		var d2: int = dists[i]
		if d2 >= 0:
			var band: int = mini(6, 1 + (d2 * 6) / (maxd + 1))
			band_counts[band - 1] += 1
	if view.heat_root != null:
		for i in 6:
			var mmi: MultiMeshInstance3D = view.heat_root.get_child(i)
			_cmp_int(mmi.multimesh.instance_count, band_counts[i], "热层第 %d 带" % (i + 1))
	else:
		_gcheck(false, "热层根缺失")
	view.set_heat(false)
	view.sync(world)
	_gcheck(view.heat_enabled() == false and int(view.debug_stats()["heat"]) == 0, "热层关闭清空")

	# ---- 汇总 ----
	_gcheck(moved_seen >= 20, "移动覆盖（moved_seen=%d）" % moved_seen)
	_finish(0)


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
				_fail("单位 %d 无节点 t=%d" % [uid, t])
				continue
			var p: Vector2i = prev_cells.get(uid, Vector2i(int(u["x"]), int(u["y"])))
			var cw: Vector3 = view.cell_to_world(int(u["x"]), int(u["y"]))
			var pw: Vector3 = view.cell_to_world(p.x, p.y)
			var frac := float((t + uid) % int(u["speed_ticks"])) / float(u["speed_ticks"])
			var ex := pw.x + (cw.x - pw.x) * frac
			var ez := pw.z + (cw.z - pw.z) * frac
			var ey: float = view.ground_y(p.x, p.y) * (1.0 - frac) + view.ground_y(int(u["x"]), int(u["y"])) * frac
			var s: float = e["s"]
			var pulse_i: int = e["pulse"]
			if pulse_i >= 0:
				var a := 1.0 - float(t - pulse_i) / 6.0
				if a > 0.0:
					s *= (1.0 + 0.6 * a)
			var nd: Node3D = e["node"]
			_cmp_v3(nd.position, Vector3(ex, ey + s / 2.0 + 0.02, ez), "单位 %d 位置 t=%d" % [uid, t])
			_cmp_v3(nd.scale, Vector3(s, s, s), "单位 %d 缩放 t=%d" % [uid, t])
			var dx := cw.x - pw.x
			var dz := cw.z - pw.z
			if dx * dx + dz * dz > 1e-9:
				moved_seen += 1
				var want_yaw := atan2(dx, dz)
				var got_yaw := nd.rotation.y
				var dyaw := absf(got_yaw - want_yaw)
				dyaw = minf(dyaw, absf(dyaw - TAU))
				checks += 1
				if dyaw > 0.02:
					_fail("单位 %d 朝向 t=%d got=%.4f want=%.4f" % [uid, t, got_yaw, want_yaw])
	_cmp_int(view.unit_nodes.size(), alive, "单位节点数 t=%d" % t)

	# 建筑：位置/施工压扁 + 计数
	var alive_b := 0
	for b in world.buildings:
		if int(b["hp"]) > 0:
			alive_b += 1
			var e2 = view.building_nodes.get(int(b["id"]))
			if e2 == null:
				_fail("建筑 %d 无节点 t=%d" % [int(b["id"]), t])
				continue
			var w2: Vector3 = view.cell_to_world(int(b["x"]), int(b["y"]))
			var gy2: float = view.ground_y(int(b["x"]), int(b["y"]))
			var bnd: Node3D = e2["node"]
			_cmp_v3(bnd.position, Vector3(w2.x, gy2, w2.z), "建筑 %d 位置 t=%d" % [int(b["id"]), t])
			var k := 0.35 if int(b["build_left"]) > 0 else 1.0
			_cmp_v3(bnd.scale, Vector3(0.96, k, 0.96), "建筑 %d 压扁 t=%d" % [int(b["id"]), t])
	_cmp_int(view.building_nodes.size(), alive_b, "建筑节点数 t=%d" % t)

	# 英雄：位置/起伏/朝向
	var h: Dictionary = world.hero
	if view.hero == null:
		_fail("英雄无节点 t=%d" % t)
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
	_cmp_v3(hnd.position, Vector3(ix2, iy2 + bob, iz2), "英雄位置 t=%d" % t)
	if moving:
		moved_seen += 1
		var want_hyaw := atan2(cw2.x - pw2.x, cw2.z - pw2.z)
		var got_hyaw := hnd.rotation.y
		var dhy := absf(got_hyaw - want_hyaw)
		dhy = minf(dhy, absf(dhy - TAU))
		checks += 1
		if dhy > 0.02:
			_fail("英雄朝向 t=%d got=%.4f want=%.4f" % [t, got_hyaw, want_hyaw])


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


func _fail(msg: String) -> void:
	bad += 1
	if first_bad == "":
		first_bad = msg


func _gcheck(cond: bool, label: String) -> void:
	checks += 1
	if not cond:
		_fail(label)


func _cmp_int(got: int, want: int, label: String) -> void:
	checks += 1
	if got != want:
		_fail(label + " got=%d want=%d" % [got, want])


func _cmp_v3(got: Vector3, want: Vector3, label: String) -> void:
	checks += 1
	if absf(got.x - want.x) > 0.01 or absf(got.y - want.y) > 0.01 or absf(got.z - want.z) > 0.01:
		_fail(label + " got=%s want=%s" % [str(got), str(want)])


func _finish(force_code: int) -> void:
	var match_pct := 100 if bad == 0 else int(100.0 * float(checks - bad) / float(maxi(checks, 1)))
	var ok := bad == 0 and checks >= 300 and moved_seen >= 20
	print("[SYNC] checks=", checks, " bad=", bad, " moved=", moved_seen, " match=", match_pct)
	if bad > 0:
		print("[SYNC] first_bad: ", first_bad)
	print("[SYNC] ", "PASS" if ok else "FAIL")
	quit(0 if (ok and force_code == 0) else 1)
