extends ProbeKit

# C2 判定：视觉同步逐位正确。
# 做法：接管主循环（关 main._process），逐 tick 推进 + view.sync，
# 按母版（view3d.lua）插值口径重算全部实体期望值，与节点实测对拍：
#   单位位置/缩放/受击脉冲、建筑位置/施工压扁、英雄位置/起伏、死亡消散、震荡环、幽灵（逐格/斜线）、热层。
# 跑法（cwd=reroute-godot，窗口模式）：godot -s res://tests/probes/probe_sync.gd
# 判定：exit 0 + stdout 含 [SYNC] match=100 + stderr 无 ERROR。
var moved_seen := 0
var from_cells := {} # id -> Vector2i（最近一次移动前的格）
var to_cells := {} # id -> Vector2i（最近一次移动后的格）
var move_ticks := {} # id -> int（最近一次移动发生的 tick）
var hero_from := Vector2i(-1, -1)
var hero_to := Vector2i(-1, -1)
var hero_move_tick := -999
var alpha_checked := false


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
	# 相邻墙（自动拼接测试）：优先取 wall_cell 的空闲六邻
	var wall_cell2 := Vector2i(-1, -1)
	for k in 6:
		var nx := Grid.nx(wall_cell.x, wall_cell.y, k)
		var ny := Grid.ny(wall_cell.x, wall_cell.y, k)
		if nx < 0 or ny < 0 or nx >= world.sc.w or ny >= world.sc.h:
			continue
		if not world.grid.passable(nx, ny) or world.building_at(nx, ny) != null:
			continue
		if not world.cell_vacant(nx, ny):
			continue
		if nx == int(world.hero["x"]) and ny == int(world.hero["y"]):
			continue
		if (Vector2i(nx, ny) == spawn_a or Vector2i(nx, ny) == spawn_b):
			continue
		wall_cell2 = Vector2i(nx, ny)
		break
	check(wall_cell2.x >= 0, "相邻墙格扫描")
	if wall_cell2.x >= 0:
		world.apply_command({ "kind": "wall", "x": wall_cell2.x, "y": wall_cell2.y })
	world.apply_command({ "kind": "tower", "x": tower_cell.x, "y": tower_cell.y })
	world.apply_command({ "kind": "spawn", "x": spawn_a.x, "y": spawn_a.y, "speed": 4, "kind_id": Sim.E_SWARM })
	world.apply_command({ "kind": "spawn", "x": spawn_b.x, "y": spawn_b.y, "speed": 8, "kind_id": Sim.E_BEHEMOTH })
	world.apply_command({ "kind": "hero", "x": hero_target.x, "y": hero_target.y })
	view.sync(world)
	_track_moves(world)

	# 初建断言：节点齐、种类缩放字面量
	var st0: Dictionary = view.debug_stats()
	cmp_int(st0["units"], 2, "初始单位节点数")
	cmp_int(st0["buildings"], 4, "初始建筑节点数（核心+双墙+塔）")
	# 连续墙：孤墙 6 条外轮廓；两墙相邻 = 5+5 外轮廓 + 1 条共享厚边 = 11
	var wkey1 := wall_cell.x * 1000 + wall_cell.y
	var wkey2 := wall_cell2.x * 1000 + wall_cell2.y
	check(view.wall_edges.has(wkey1), "墙 1 边缘段容器")
	if view.wall_edges.has(wkey1) and view.wall_edges.has(wkey2):
		var e1n: int = (view.wall_edges[wkey1] as Node3D).get_child_count()
		var e2n: int = (view.wall_edges[wkey2] as Node3D).get_child_count()
		cmp_int(e1n + e2n, 11, "相邻墙共享边拼接（5+5 轮廓 + 1 共享）")
	cmp_int(int(st0["rings"]), 4, "每栋建筑一条底座光环")
	check(st0["hero"] == true, "英雄节点")
	var e1a = view.unit_nodes.get(1)
	var e2a = view.unit_nodes.get(2)
	if e1a != null:
		var p1: AnimationPlayer = e1a["player"]
		check(p1 != null and p1.current_animation == "Crawl", "虫群模型基态 Crawl")
	if e2a != null:
		var p2: AnimationPlayer = e2a["player"]
		check(p2 != null and p2.current_animation == "Crawl", "蛮兽模型基态 Crawl")

	# ---- 主循环：130 tick 逐拍对拍 ----
	for _step in 130:
		world.tick()
		var t: int = world.tick_count
		_track_moves(world)
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

	# ---- 幽灵预览（逐格绘制：直连 + 斜线不越线）----
	var straight := [Vector2i(8, 8), Vector2i(9, 8), Vector2i(10, 8), Vector2i(11, 8)]
	_ghost_cells_check(view, straight, false)
	view.show_ghost(straight, true)
	if view.ghost_alive:
		check(view.ghost_mi.material_override == view.mats["ghost_bad"], "幽灵无效染色 bad")
	var diag := [Vector2i(8, 8), Vector2i(9, 9), Vector2i(10, 10), Vector2i(11, 11)]
	_ghost_cells_check(view, diag, false)
	# 实物预览：塔 = 塔模 + 射程填充/边缘；墙 = 连续墙段本体 + 边缘拼接
	view.show_ghost([Vector2i(8, 8)], false, "tower")
	cmp_int(view.preview_root.get_child_count(), 1, "塔预览模型节点")
	cmp_int(view.range_root.get_child_count(), 2, "塔射程填充+边缘")
	view.show_ghost([Vector2i(8, 8), Vector2i(9, 8)], false, "wall")
	cmp_int(view.preview_root.get_child_count(), 2, "墙预览逐格节点")
	if view.preview_root.get_child_count() > 0:
		var pv0: Node3D = view.preview_root.get_child(0)
		check(pv0.get_child_count() >= 2, "墙预览含本体 + 边缘段")
	view.show_ghost([])
	check(view.ghost_alive == false and view.ghost == null, "幽灵清除")
	cmp_int(view.preview_root.get_child_count(), 0, "实物预览清除")
	cmp_int(view.range_root.get_child_count(), 0, "射程预览清除")

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
	_terrain_edge_check(view, world, main)

	# ---- 视觉虫群（纯表现层）：同格 3 只必须错开，且偏移不越出格心安全半径 ----
	var swarm_cell := _find_free(world, 0, 0, 63, 63, [], Vector2i(32, 32), 400)
	check(swarm_cell.x >= 0, "虫群分离测试格扫描")
	if swarm_cell.x >= 0:
		var sid0: int = world.units.size()
		for _i in 3:
			world.apply_command({ "kind": "spawn", "x": swarm_cell.x, "y": swarm_cell.y, "speed": 4, "kind_id": Sim.E_SWARM })
		view.sync(world)
		cmp_int(world.units.size(), sid0 + 3, "虫群分离：同格三只已生成")
		if world.units.size() == sid0 + 3:
			var spos: Array = []
			for i in 3:
				var su: Dictionary = world.units[sid0 + i]
				var se = view.unit_nodes.get(int(su["id"]))
				if se != null:
					spos.append((se["node"] as Node3D).position)
			cmp_int(spos.size(), 3, "虫群分离：三只节点齐")
			if spos.size() == 3:
				var min_d := 999.0
				for i in 3:
					for j in range(i + 1, 3):
						min_d = minf(min_d, Vector2(spos[i].x - spos[j].x, spos[i].z - spos[j].z).length())
				check(min_d >= 0.05, "虫群分离：同格不重叠（min_d=%.3f）" % min_d)
				var cw3: Vector3 = view.cell_to_world(swarm_cell.x, swarm_cell.y)
				for i in 3:
					var off := Vector2(spos[i].x - cw3.x, spos[i].z - cw3.z)
					check(off.length() <= 0.17, "虫群分离：偏移在安全半径内（%.3f）" % off.length())
		# 只留一只：孤立单位必须零偏移；相邻格单位也零偏移（只有同格才分环）
		var keep_id: int = int(world.units[sid0]["id"])
		var kept: Array = []
		for u2 in world.units:
			if int(u2["id"]) == keep_id:
				kept.append(u2)
		world.units = kept
		view.sync(world)
		var ke = view.unit_nodes.get(keep_id)
		if ke != null:
			check(absf(float(ke["ox"])) < 0.0001 and absf(float(ke["oz"])) < 0.0001, "虫群分离：孤立单位零偏移")
			var adj := Vector2i(-1, -1)
			for dir2 in 6:
				var ax2 := Grid.nx(swarm_cell.x, swarm_cell.y, dir2)
				var ay2 := Grid.ny(swarm_cell.x, swarm_cell.y, dir2)
				if ax2 >= 0 and ay2 >= 0 and ax2 < world.sc.w and ay2 < world.sc.h and world.grid.passable(ax2, ay2) and world.building_at(ax2, ay2) == null and world.cell_vacant(ax2, ay2):
					adj = Vector2i(ax2, ay2)
					break
			check(adj.x >= 0, "虫群分离：相邻空格扫描")
			if adj.x >= 0:
				var n_adj: int = world.units.size()
				world.apply_command({ "kind": "spawn", "x": adj.x, "y": adj.y, "speed": 4, "kind_id": Sim.E_SWARM })
				view.sync(world)
				var ae = view.unit_nodes.get(int(world.units[n_adj]["id"]))
				if ae != null:
					check(absf(float(ae["ox"])) < 0.0001 and absf(float(ae["oz"])) < 0.0001, "虫群分离：相邻格零偏移")
					check(absf(float(ke["ox"])) < 0.0001 and absf(float(ke["oz"])) < 0.0001, "虫群分离：相邻格不互推孤立单位")

	# ---- 汇总 ----
	check(moved_seen >= 20, "移动覆盖（moved_seen=%d）" % moved_seen)
	check(alpha_checked, "分数帧插值覆盖（tick_alpha 生效）")
	_report()


## 独立跟踪「上一移动格 / 当前格 / 移动 tick」，与 view 内部缓存对拍（不读 view 的 px/py/mt）。
func _track_moves(world) -> void:
	var t: int = world.tick_count
	for u in world.units:
		var uid: int = int(u["id"])
		var cur := Vector2i(int(u["x"]), int(u["y"]))
		if not to_cells.has(uid):
			from_cells[uid] = cur
			to_cells[uid] = cur
			move_ticks[uid] = t - maxi(int(u["speed_ticks"]), 1)
		elif cur != to_cells[uid]:
			from_cells[uid] = to_cells[uid]
			to_cells[uid] = cur
			move_ticks[uid] = t
	var hcur := Vector2i(int(world.hero["x"]), int(world.hero["y"]))
	if hero_to.x < 0:
		hero_from = hcur
		hero_to = hcur
		hero_move_tick = t - maxi(int(Sim.HERO["speed_ticks"]), 1)
	elif hcur != hero_to:
		hero_from = hero_to
		hero_to = hcur
		hero_move_tick = t


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
			var cx := int(u["x"])
			var cy := int(u["y"])
			var p: Vector2i = from_cells.get(uid, Vector2i(cx, cy))
			var mt: int = int(move_ticks.get(uid, t - maxi(int(u["speed_ticks"]), 1)))
			var span := maxi(int(u["speed_ticks"]), 1)
			var frac := clampf(float(t - mt), 0.0, float(span)) / float(span)
			var cw: Vector3 = view.cell_to_world(cx, cy)
			var pw: Vector3 = view.cell_to_world(p.x, p.y)
			var ex := pw.x + (cw.x - pw.x) * frac
			var ez := pw.z + (cw.z - pw.z) * frac
			var ey: float = view.ground_y(p.x, p.y) * (1.0 - frac) + view.ground_y(cx, cy) * frac
			var m := 1.0
			var pulse_i: int = e["pulse"]
			if pulse_i >= 0:
				var a := 1.0 - float(t - pulse_i) / 6.0
				if a > 0.0:
					m = 1.0 + 0.6 * a
			var nd: Node3D = e["node"]
			var ox := float(e.get("ox", 0.0))
			var oz := float(e.get("oz", 0.0))
			check(Vector2(ox, oz).length() <= 0.17, "单位 %d 视觉偏移在安全半径内 t=%d" % [uid, t])
			cmp_v3(nd.position, Vector3(ex + ox, ey + 0.02, ez + oz), "单位 %d 位置 t=%d" % [uid, t])
			cmp_v3(nd.scale, Vector3(m, m, m), "单位 %d 缩放 t=%d" % [uid, t])
			# 插值缓存必须是「上一移动格 + 移动 tick」，而不是每帧覆写成当前格
			check(int(e["px"]) == p.x and int(e["py"]) == p.y, "单位 %d px/py 保留上一格 t=%d" % [uid, t])
			check(int(e["mt"]) == mt, "单位 %d mt 记录移动 tick t=%d" % [uid, t])
			# 分数帧：同一 tick 内 alpha 0.5 必须落在两格中点（旧实现只会格心/瞬移）
			if not alpha_checked and frac > 0.2 and frac < 0.8:
				alpha_checked = true
				var af := clampf(float(t - mt) + 0.5, 0.0, float(span)) / float(span)
				var ax := pw.x + (cw.x - pw.x) * af
				var az := pw.z + (cw.z - pw.z) * af
				var ay: float = view.ground_y(p.x, p.y) * (1.0 - af) + view.ground_y(cx, cy) * af
				view.sync(world, 0.5)
				cmp_v3(nd.position, Vector3(ax + ox, ay + 0.02, az + oz), "单位 %d 分数帧插值 t=%d" % [uid, t])
				view.sync(world, 0.0)
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
			# 2026-10-20 建筑表现：墙升起走 body 子节点（wrapper 恒 1.0）；塔按施工进度 0.12→1.0；核恒 1.0。
			var k := 1.0
			if int(b["kind"]) == Sim.B_TOWER and int(b["build_left"]) > 0:
				var total: int = maxi(int(e2.get("build_total", int(b["build_left"]))), 1)
				k = 0.12 + 0.88 * (1.0 - float(int(b["build_left"])) / float(total))
			cmp_v3(bnd.scale, Vector3(0.96, k, 0.96), "建筑 %d 压扁/进度 t=%d" % [int(b["id"]), t])
			check(e2.get("ring") != null and (e2["ring"] as Node3D).visible, "建筑 %d 底座光环 t=%d" % [int(b["id"]), t])
	cmp_int(view.building_nodes.size(), alive_b, "建筑节点数 t=%d" % t)
	# 墙边缘段：每格一个容器（连续墙靠共享边 + 外轮廓压边）
	var ds: Dictionary = view.debug_stats()
	cmp_int(int(ds["wall_edges"]), int(ds["wall_cells"]), "墙边缘段容器数与墙格数一致 t=%d" % t)

	# 英雄：位置/起伏/朝向
	var h: Dictionary = world.hero
	if view.hero == null:
		fail("英雄无节点 t=%d" % t)
		return
	var ph := hero_from
	if ph.x < 0:
		ph = Vector2i(int(h["x"]), int(h["y"]))
	var hspan := maxi(int(Sim.HERO["speed_ticks"]), 1)
	var frac2 := clampf(float(t - hero_move_tick), 0.0, float(hspan)) / float(hspan)
	var cw2: Vector3 = view.cell_to_world(int(h["x"]), int(h["y"]))
	var pw2: Vector3 = view.cell_to_world(ph.x, ph.y)
	var ix2 := pw2.x + (cw2.x - pw2.x) * frac2
	var iz2 := pw2.z + (cw2.z - pw2.z) * frac2
	var iy2: float = view.ground_y(ph.x, ph.y) * (1.0 - frac2) + view.ground_y(int(h["x"]), int(h["y"])) * frac2
	var moving := frac2 < 1.0 and (cw2.x != pw2.x or cw2.z != pw2.z)
	var bob := 0.03 * sin(frac2 * 6.283) if moving else 0.0
	var hnd: Node3D = view.hero["node"]
	cmp_v3(hnd.position, Vector3(ix2, iy2 + bob, iz2), "英雄位置 t=%d" % t)
	check(int(view.hero["px"]) == ph.x and int(view.hero["py"]) == ph.y, "英雄 px/py 保留上一格 t=%d" % t)
	check(int(view.hero["mt"]) == hero_move_tick, "英雄 mt 记录移动 tick t=%d" % t)
	if moving:
		moved_seen += 1
		var want_hyaw := atan2(cw2.x - pw2.x, cw2.z - pw2.z)
		var got_hyaw := hnd.rotation.y
		var dhy := absf(got_hyaw - want_hyaw)
		dhy = minf(dhy, absf(dhy - TAU))
		check(dhy <= 0.02, "英雄朝向 t=%d got=%.4f want=%.4f" % [t, got_hyaw, want_hyaw])


## 幽灵逐格断言：盒数 = 格数，且逐格世界位/缩放/染色对拍（直连与斜线共用）。
func _ghost_cells_check(view, cells: Array, is_bad: bool) -> void:
	view.show_ghost(cells, is_bad)
	check(view.ghost_alive == true, "幽灵出现")
	if not view.ghost_alive:
		return
	cmp_int(view.ghost.get_child_count(), cells.size(), "虚空盒数=格数（%d 格）" % cells.size())
	if view.ghost.get_child_count() != cells.size():
		return
	var mat: Material = view.mats["ghost_bad"] if is_bad else view.mats["ghost_ok"]
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


## 落差边自然化断言（2026-10-17 T1；2026-10-23 高度域 -2..5 更新）：分级以**模拟高度差**为真值
## （Δ1..2=可爬坡 / Δ≥3=崖壁 / 同层=石阶 / 实心邻=崖壁）；剖面 P0 恒在顶面边框线（无顶缝）且
## 高度单调不增；网格顶点账目独立重算逐点吻合；同状态重建两次逐位一致；负高度坑见 _pit_check。
## 旧实现无 edge_kind_at → 本段干净 FAIL（负对照）。
func _terrain_edge_check(view, world, main) -> void:
	var T = view.terrain
	if not (T.has_method("edge_kind_at") and T.has_method("edge_profile")):
		fail("地形自然化接口缺失（edge_kind_at/edge_profile；负对照=旧实现）")
		return
	var core_cmap: Dictionary = view.core.get_script().get_script_constant_map()
	var CELL_N: int = int(core_cmap["CELL_N"])
	var hstep: float = float(core_cmap["H_STEP"])

	# 平整 h0 格（六邻同层且空置）→ 填三级验证分级真值（1..2 级可爬 / 3 级崖壁）
	var c := _find_flat(world, CELL_N, 8, 24, 20, 34)
	check(c.x >= 0, "平整格扫描（六邻同层 h0 + 空置 + 邻界内）")
	if c.x < 0:
		return
	var h0: int = world.grid.get_h(c.x, c.y)
	cmp_int(h0, 0, "平整格基准高度 = 0（三级填高留余量）")
	world.apply_command({ "kind": "fill", "x": c.x, "y": c.y })
	cmp_int(world.grid.get_h(c.x, c.y), h0 + 1, "填一级成功")
	var kinds1 := _edge_kinds6(T, c)
	check(_all_eq(kinds1, 1), "填一级（dh=1）6 边全为可爬坡 EDGE_RAMP（kinds=%s）" % str(kinds1))
	world.apply_command({ "kind": "fill", "x": c.x, "y": c.y })
	cmp_int(world.grid.get_h(c.x, c.y), h0 + 2, "填二级成功")
	var kinds2 := _edge_kinds6(T, c)
	check(_all_eq(kinds2, 1), "填二级（dh=2）仍为可爬坡 EDGE_RAMP（kinds=%s）" % str(kinds2))
	world.apply_command({ "kind": "fill", "x": c.x, "y": c.y })
	cmp_int(world.grid.get_h(c.x, c.y), h0 + 3, "填三级成功")
	var kinds3 := _edge_kinds6(T, c)
	check(_all_eq(kinds3, 2), "填三级（dh=3）6 边全为崖壁 EDGE_CLIFF（kinds=%s）" % str(kinds3))

	# 重建后拿网格 → 顶点账目独立重算 + 确定性
	view.sync(world)
	var mesh: ArrayMesh = T._hex.mesh
	var arr1: Array = mesh.surface_get_arrays(0)
	var v1: PackedVector3Array = arr1[Mesh.ARRAY_VERTEX]
	var i1: PackedInt32Array = arr1[Mesh.ARRAY_INDEX]
	var expect := _edge_verts_expect(T, CELL_N)
	cmp_int(v1.size(), expect, "顶点账目（独立重算：顶面 13×4096（A8 中心+内环+角环）+ 逐边 strip×4×(双面×2)）")
	check(v1.size() > 4096 * 7 and v1.size() < 4096 * 64, "顶点数量级可控（%d）" % v1.size())
	T._rebuild_field()
	var arr2: Array = T._hex.mesh.surface_get_arrays(0)
	var v2: PackedVector3Array = arr2[Mesh.ARRAY_VERTEX]
	var i2: PackedInt32Array = arr2[Mesh.ARRAY_INDEX]
	check(v2 == v1 and i2 == i1, "同状态重建逐位一致（顶点 %d/索引 %d）" % [v1.size(), i1.size()])

	# 剖面形状（当前 = 三级高格 vs 邻格：崖壁）
	_profile_shape_check(T, CELL_N, c.x, c.y, 0, 2)
	# 降一级（dh=2）→ 可爬坡剖面（新口径：落差 2 仍是可爬坡）
	world.apply_command({ "kind": "lower", "x": c.x, "y": c.y })
	var hd: int = world.grid.get_h(c.x, c.y)
	cmp_int(hd, h0 + 2, "降一级成功")
	var kinds_l := _edge_kinds6(T, c)
	check(_all_eq(kinds_l, 1), "降一级后（dh=2）6 边回可爬坡（kinds=%s）" % str(kinds_l))
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
	_plate_merge_check(T, world, CELL_N)
	_pit_check(view, world, CELL_N, hstep, main)


## 负高度坑（2026-10-23 Task6）：连挖两级到 -2 → 顶面/贴地下沉 2×H_STEP；
## 6 条坑壁由**高邻**按 dh=2 生成 RAMP（低侧不叠反向剖面，顶点账目逐点吻合）；
## 邻格抬到 +1 后 dh=3 → 崖壁剖面（端点贴坑底、高度单调）。
func _pit_check(view, world, CELL_N: int, hstep: float, main) -> void:
	var T = view.terrain
	var p := _find_flat(world, CELL_N, 8, 24, 20, 34)
	check(p.x >= 0, "坑底格扫描（六邻同层 h0）")
	if p.x < 0:
		return
	var n := CELL_N
	var top0: float = T._cell_top[p.y * n + p.x]
	var gy0: float = T.ground_y(p.x, p.y)
	world.apply_command({ "kind": "lower", "x": p.x, "y": p.y })
	world.apply_command({ "kind": "lower", "x": p.x, "y": p.y })
	cmp_int(world.grid.get_h(p.x, p.y), -2, "连挖两级到 -2 坑底")
	view.sync(world)
	var top1: float = T._cell_top[p.y * n + p.x]
	var gy1: float = T.ground_y(p.x, p.y)
	check(absf((top0 - top1) - 2.0 * hstep) <= 0.5, "坑底顶面下沉 ≈2×H_STEP（%.3f→%.3f）" % [top0, top1])
	check(absf((gy0 - gy1) - 2.0 * hstep) <= 1e-6, "贴地 ground_y 同步下沉 2×H_STEP（%.3f→%.3f）" % [gy0, gy1])
	# -2 已到底：模式判定无效（幽灵红板）+ 模拟层拒绝且不扣费
	check(not main.mode_valid("lower", p.x, p.y), "坑底 -2 挖低模式判无效")
	var sup0: int = world.supply
	world.apply_command({ "kind": "lower", "x": p.x, "y": p.y })
	cmp_int(world.grid.get_h(p.x, p.y), -2, "坑底 -2 挖低被模拟层拒绝")
	cmp_int(world.supply, sup0, "-2 拒绝不扣供给")
	# 低侧闭合：坑底必须低于周围 6 邻顶（无反向剖面可画）
	var below := true
	var ramp_n := 0
	var wrong_n := 0
	var nb0 := Vector3i(-1, -1, -1) # 第一条可用的高邻边（供剖面断言）
	for k in 6:
		var nx := Grid.nx(p.x, p.y, k)
		var ny := Grid.ny(p.x, p.y, k)
		if nx < 0 or ny < 0 or nx >= CELL_N or ny >= CELL_N:
			continue
		if T._cell_top[ny * n + nx] <= top1:
			below = false
		var k2 := _opp_dir(nx, ny, p.x, p.y)
		if k2 < 0:
			continue
		if T.edge_kind_at(nx, ny, k2) == T.EDGE_RAMP:
			ramp_n += 1
		else:
			wrong_n += 1
		if nb0.x < 0:
			nb0 = Vector3i(nx, ny, k2)
	check(below, "坑底低于全部邻顶（低侧跳过完整剖面，由高侧闭合）")
	cmp_int(ramp_n, 6, "坑壁 6 边由高邻按 dh=2 生成 RAMP")
	cmp_int(wrong_n, 0, "坑壁无误分崖壁/石阶")
	# 坑底色：负高度按低洼沙色处理（坡度岩权压低，不刷成深色岩面块）
	var c_pit: Color = T._field_color_at(0.0, 0.0, 0.0, false, 5.0, true)
	var c_top: Color = T._field_color_at(0.0, 0.0, 0.0, false, 5.0)
	check(c_pit.a <= 0.19 and c_pit.a < c_top.a, "坑底岩权压低（低洼沙色 a=%.2f/%.2f）" % [c_pit.a, c_top.a])
	if nb0.x >= 0:
		_profile_shape_check(T, CELL_N, nb0.x, nb0.y, nb0.z, 1)
	var m2: ArrayMesh = T._hex.mesh
	var vm: PackedVector3Array = m2.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	cmp_int(vm.size(), _edge_verts_expect(T, CELL_N), "坑态顶点账目逐点吻合（低侧不叠反向剖面）")
	# 坑底对 +1（dh=3）→ 崖壁（白盒改高；探针专用，之后还原）
	if nb0.x >= 0:
		var hnb: int = world.grid.get_h(nb0.x, nb0.y)
		world.grid.set_h(nb0.x, nb0.y, 1)
		view.sync(world)
		cmp_int(T.edge_kind_at(nb0.x, nb0.y, nb0.z), 2, "坑底对 +1 高台（dh=3）= 崖壁 EDGE_CLIFF")
		_profile_shape_check(T, CELL_N, nb0.x, nb0.y, nb0.z, 2)
		world.grid.set_h(nb0.x, nb0.y, hnb)
	world.grid.set_h(p.x, p.y, 0)
	view.sync(world)


## 六向反号：从 (nx,ny) 看回 (x,y) 的邻向（越界/非邻返回 -1）。
func _opp_dir(nx: int, ny: int, x: int, y: int) -> int:
	for k in 6:
		if Grid.nx(nx, ny, k) == x and Grid.ny(nx, ny, k) == y:
			return k
	return -1


## 自然地形并台（2026-10-20 B）：场内 SOLID 岩顶应全部落在 PLATE_STEP 整倍上、内部以共面为主、
## 剩余错台 ≥ 一个台阶、位移有界；边框圈（含 RIM_BUMP 周向起伏）保持原始起伏不并。
func _plate_merge_check(T, world, CELL_N: int) -> void:
	var cmap: Dictionary = T.get_script().get_script_constant_map()
	var step: float = float(cmap["PLATE_STEP"])
	var dh_lim: float = float(cmap["PLATE_MERGE_DH"])
	var bump: float = float(cmap["SOLID_BUMP"])
	var rimb: float = float(cmap["RIM_BUMP"])
	var n_cells := 0
	var bad_quant := 0
	var flat_edges := 0
	var wall_edges := 0
	var min_step := 1e9
	var shift_max := 0.0
	for y in range(1, CELL_N - 1):
		for x in range(1, CELL_N - 1):
			if world.grid.at(x, y) != Grid.SOLID or world.grid.get_h(x, y) != 0:
				continue
			n_cells += 1
			var t: float = T._cell_top[y * CELL_N + x]
			if absf(t / step - roundf(t / step)) > 1e-4:
				bad_quant += 1
			var raw: float = T.field_h[y * CELL_N + x] + bump
			shift_max = maxf(shift_max, absf(t - raw))
			for dir in [0, 1, 2]: # 3 个方向即可覆盖无重复边
				var nx := Grid.nx(x, y, dir)
				var ny := Grid.ny(x, y, dir)
				if nx <= 0 or ny <= 0 or nx >= CELL_N - 1 or ny >= CELL_N - 1:
					continue
				if world.grid.at(nx, ny) != Grid.SOLID or world.grid.get_h(nx, ny) != 0:
					continue
				var d := absf(T._cell_top[ny * CELL_N + nx] - t)
				if d <= 1e-5:
					flat_edges += 1
				else:
					wall_edges += 1
					min_step = minf(min_step, d)
	check(n_cells > 0, "并台样本（场内 SOLID %d 格）" % n_cells)
	check(bad_quant == 0, "SOLID 岩顶对齐 %.2fm 台阶（越界 %d）" % [step, bad_quant])
	check(flat_edges > wall_edges, "岩顶内部以共面为主（flat=%d wall=%d）" % [flat_edges, wall_edges])
	check(min_step >= step - 0.002, "剩余错台 ≥ 一个台阶（最小 %.3f）" % min_step)
	check(shift_max <= 2.0 * dh_lim + step * 0.5 + 0.01, "并台位移有界（最大 %.3f）" % shift_max)
	var border_ok := true
	for b in [Vector2i(0, 20), Vector2i(CELL_N - 1, 20), Vector2i(20, 0), Vector2i(20, CELL_N - 1)]:
		if world.grid.at(b.x, b.y) != Grid.SOLID or world.grid.get_h(b.x, b.y) != 0:
			continue
		var want: float = T.field_h[b.y * CELL_N + b.x] + bump + rimb * T._rim_scale(b.x, b.y)
		if absf(T._cell_top[b.y * CELL_N + b.x] - want) > 1e-5:
			border_ok = false
	check(border_ok, "边框圈保留 RIM_BUMP 原始起伏（不参与并台）")


## 剖面形状：P0 恒在顶面边框线（无顶缝）；末点贴低邻顶；高度单调不增；外伸在界内。
func _profile_shape_check(T, CELL_N: int, x: int, y: int, k: int, kind: int) -> void:
	var t: float = T._cell_top[y * CELL_N + x]
	var nx := Grid.nx(x, y, k)
	var ny := Grid.ny(x, y, k)
	var t_lo: float = T._cell_top[ny * CELL_N + nx]
	var p: PackedFloat64Array = T.edge_profile(x, y, k, t, t_lo, kind)
	@warning_ignore("integer_division")
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


## 顶点账目独立重算：顶面恒 13 顶点/格；界外边（崖壁·双面）按崖壁剖面 strip×4×2；
## 内侧画出边按 kind 剖面点数（函数内自调 edge_profile 取点数，跟随实现演进）× 4 顶点；被跳过边 0。
## 等高阈值取 T.EDGE_MIN_DH（2026-10-20 由 0.02 降到 0.001：旧阈值会漏画 0~2cm 高差边，
## 平顶缝透出背景成「边缘发光」；探针与渲染共用同一常量，防止再次分叉）。
## 2026-10-23：界外边同渲染口径——界外地面高于本格顶（负高度低侧）时不画剖面（wall=0）。
func _edge_verts_expect(T, CELL_N: int) -> int:
	var cmap: Dictionary = T.get_script().get_script_constant_map()
	var min_dh: float = float(cmap.get("EDGE_MIN_DH", 0.001))
	var embed: float = float(cmap.get("WALL_EMBED", 0.5))
	var total := 0
	for y in CELL_N:
		for x in CELL_N:
			total += 13 # A8 顶面：中心 + 内环 6 + 角环 6
			var t: float = T._cell_top[y * CELL_N + x]
			for k in 6:
				var nx := Grid.nx(x, y, k)
				var ny := Grid.ny(x, y, k)
				if nx < 0 or ny < 0 or nx >= CELL_N or ny >= CELL_N:
					var w: Vector3 = T.core.cell_to_world(x, y)
					var ca: Vector2 = T.core.HEX_CORNERS[T.HEX_EDGE_A[k]]
					var cb: Vector2 = T.core.HEX_CORNERS[T.HEX_EDGE_B[k]]
					var tlo_rim: float = minf(T.ground_h(w.x + ca.x, w.z + ca.y), T.ground_h(w.x + cb.x, w.z + cb.y)) - embed
					if t <= tlo_rim + min_dh:
						continue # 本格是低侧：不画反向剖面
					@warning_ignore("integer_division")
					var po: int = T.edge_profile(x, y, k, t, tlo_rim, T.EDGE_CLIFF).size() / 2
					total += (po - 1) * 4 * 2
					continue
				var t2: float = T._cell_top[ny * CELL_N + nx]
				if t <= t2 + min_dh:
					continue
				@warning_ignore("integer_division")
				var pts: int = T.edge_profile(x, y, k, t, t2, T.edge_kind_at(x, y, k)).size() / 2
				total += (pts - 1) * 4
	return total


## 平整格扫描：通行 + 空置 + 六邻同层且高度 = 0（填三级/挖两级用例的基准格）。
func _find_flat(world, CELL_N: int, x0: int, y0: int, x1: int, y1: int) -> Vector2i:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if not world.grid.passable(x, y) or world.building_at(x, y) != null or not world.cell_vacant(x, y):
				continue
			var hr: Dictionary = world.hero
			if x == int(hr["x"]) and y == int(hr["y"]):
				continue
			if world.grid.get_h(x, y) != 0:
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
