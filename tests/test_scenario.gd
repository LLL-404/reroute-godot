extends RefCounted

# scenario 单测（2026-10-16 世界生成后重写；2026-10-19 增自由路径扁平快照）：数值表合同、
# 默认种子（黄金图 20261003）快照、自由路径（游戏内第 1 局 20261004）快照、高度模板、
# 结构校验契约、路径长标定与指纹确定性与负对照。

# 白盒仅用于制造边界（wave_scale_pct 直写触发指纹分叉）；行为断言一律走公开面。


func register(kit: TestKit) -> void:
	kit.module("scenario")

	kit.test("sim-constants", func():
		kit.eq(Sim.TICK_HZ, 20, "TICK_HZ")
		kit.eq(Sim.START_SUPPLY, 300, "START_SUPPLY")
		kit.eq(Sim.ORE_YIELD, 25, "ORE_YIELD")
		kit.eq(Sim.CONVOY_SHIFT, 3, "CONVOY_SHIFT")
		kit.eq(Sim.FILL_COST, 15, "FILL_COST")
		kit.eq(Sim.LOWER_COST, 10, "LOWER_COST")
		kit.eq(Sim.H_MIN, -2, "H_MIN")
		kit.eq(Sim.H_MAX, 5, "H_MAX")
		kit.eq(Sim.B_WALL, 1, "B_WALL")
		kit.eq(Sim.B_TOWER, 2, "B_TOWER")
		kit.eq(Sim.B_CORE, 3, "B_CORE")
		kit.eq(Sim.E_SWARM, 1, "E_SWARM")
		kit.eq(Sim.E_BEHEMOTH, 2, "E_BEHEMOTH"))

	kit.test("buildings-table", func():
		var w: Dictionary = Sim.BUILDINGS[Sim.B_WALL - 1]
		kit.eq(w["name"], "wall", "wall name")
		kit.eq(w["cost"], 10, "wall cost")
		kit.eq(w["hp"], 120, "wall hp")
		kit.eq(w["build_ticks"], 0, "wall build_ticks")
		kit.eq(w["shoots"], false, "wall shoots")
		var t: Dictionary = Sim.BUILDINGS[Sim.B_TOWER - 1]
		kit.eq(t["cost"], 60, "tower cost")
		kit.eq(t["hp"], 200, "tower hp")
		kit.eq(t["build_ticks"], 120, "tower build_ticks")
		kit.eq(t["range"], 12, "tower range")
		kit.eq(t["damage"], 16, "tower damage")
		kit.eq(t["cooldown"], 20, "tower cooldown")
		kit.eq(t["shoots"], true, "tower shoots")
		var c: Dictionary = Sim.BUILDINGS[Sim.B_CORE - 1]
		kit.eq(c["cost"], 0, "core cost")
		kit.eq(c["hp"], 1200, "core hp"))

	kit.test("enemies-table", func():
		var s: Dictionary = Sim.ENEMIES[Sim.E_SWARM - 1]
		kit.eq(s["name"], "swarm", "swarm name")
		kit.eq(s["hp"], 30, "swarm hp")
		kit.eq(s["speed_ticks"], 4, "swarm speed_ticks")
		kit.eq(s["damage"], 8, "swarm damage")
		kit.eq(s["cooldown"], 12, "swarm cooldown")
		kit.eq(s["reward"], 3, "swarm reward")
		var b: Dictionary = Sim.ENEMIES[Sim.E_BEHEMOTH - 1]
		kit.eq(b["hp"], 240, "behemoth hp")
		kit.eq(b["speed_ticks"], 8, "behemoth speed_ticks")
		kit.eq(b["damage"], 60, "behemoth damage")
		kit.eq(b["cooldown"], 24, "behemoth cooldown")
		kit.eq(b["reward"], 14, "behemoth reward"))

	kit.test("hero-table", func():
		kit.eq(Sim.HERO["speed_ticks"], 3, "hero speed_ticks")
		kit.eq(Sim.HERO["skill_radius"], 3, "hero skill_radius")
		kit.eq(Sim.HERO["skill_cooldown"], 400, "hero skill_cooldown"))

	kit.test("layout-snapshot", func():
		var sc := Scenario.new()
		kit.eq(sc.seed, Scenario.DEFAULT_SEED, "默认种子 = 黄金图")
		kit.eq(sc.seed, 20261003, "默认种子字面值")
		kit.eq(sc.w, 64, "w")
		kit.eq(sc.h, 64, "h")
		kit.eq(sc.core, Vector2i(33, 6), "core")
		kit.eq(sc.hero_spawn, Vector2i(33, 8), "hero_spawn")
		kit.eq(sc.ridge_y, 42, "ridge_y")
		kit.seq(sc.chokes, [Vector2i(22, 42), Vector2i(46, 42)], "chokes")
		kit.eq(sc.spawns.size(), 3, "spawns 数")
		kit.eq(sc.spawns[0], Vector2i(21, 56), "出怪口 1")
		kit.eq(sc.spawns[1], Vector2i(45, 56), "出怪口 2")
		kit.eq(sc.spawns[2], Vector2i(6, 57), "盆地口")
		kit.eq(sc.basin_rect, Rect2i(3, 53, 7, 8), "盆地矩形")
		kit.eq(sc.basin_plug, Vector2i(8, 53), "插口")
		kit.eq(sc.mesa, Rect2i(16, 48, 2, 2), "微丘")
		kit.eq(sc.sparse_phase, 2, "表土相位")
		kit.eq(sc.resample_salt, 0, "默认图无需重采样")
		kit.eq(sc.end_tick, 6400, "end_tick")
		kit.eq(sc.hard_cap_tick, 8800, "hard_cap_tick")
		kit.eq(sc.trickle_every, 300, "trickle_every")
		kit.eq(sc.wave_scale_pct, 100, "wave_scale_pct")
		kit.eq(sc.mid_ore.size(), 5, "中场矿数")
		kit.eq(sc.basin_ore.size(), 12, "盆地矿数")
		kit.eq(sc.ore_cells.size(), 17, "矿总表（盆地在前、中场在后）")
		kit.eq(sc.ore_cells[0], Vector2i(5, 56), "矿表首 = 盆地矿")
		kit.eq(sc.ore_cells[16], Vector2i(35, 21), "矿表末 = 中场矿"))

	kit.test("freeform-snapshot", func():
		var sc := Scenario.new(20261004) # 游戏内第 1 局种子（自由路径扁平快照，2026-10-19 铸造；再调参需同步）
		kit.eq(sc._freeform, true, "自由路径标记")
		kit.eq(sc.resample_salt, 3, "盐")
		kit.eq(sc.template_id, -1, "自由路径无模板")
		kit.eq(sc.ridge_y, -1, "自由路径无单一脊线")
		kit.eq(sc.chokes.size(), 0, "自由路径无固定咽喉")
		kit.eq(sc.core, Vector2i(43, 14), "核心")
		kit.eq(sc.hero_spawn, Vector2i(43, 16), "英雄位（核心朝内 2）")
		kit.eq(sc.spawns.size(), 3, "双主口 + 盆地口")
		kit.eq(sc.spawns[0], Vector2i(14, 50), "主口 1")
		kit.eq(sc.spawns[1], Vector2i(3, 41), "主口 2")
		kit.eq(sc.spawns[2], Vector2i(30, 15), "盆地口（压块心矿）")
		kit.eq(sc.basin_rect, Rect2i(27, 11, 9, 8), "盆地矩形")
		kit.eq(sc.basin_plug, Vector2i(35, 15), "插口（右棱中）")
		kit.eq(sc.mid_ore.size(), 5, "中场矿数")
		kit.eq(sc.mid_ore[0], Vector2i(41, 21), "中场矿左缘")
		kit.eq(sc.mid_ore[4], Vector2i(45, 21), "中场矿右缘")
		kit.eq(sc.basin_ore.size(), 12, "盆地矿数")
		kit.eq(sc.ore_cells.size(), 17, "矿总表（盆地在前、中场在后）")
		kit.eq(sc._rock_arr.size(), 216, "岩群数（2026-10-25 矿台扩圈后重钉）")
		kit.eq(sc._hill_arr.size(), 285, "微丘数")
		kit.eq(sc._sparse_arr.size(), 9, "散土数")
		kit.eq(sc._sparse_arr[0], Vector2i(13, 30), "散土首格")
		# 地形（2026-10-23 随机高度）：基地地貌三选一，不再有三级同心山头
		kit.eq(sc.terrain_kind, MapGen.TERRAIN_SLOPE, "地形类型（山腰）")
		kit.eq(sc.height_at(sc.core.x, sc.core.y), 2, "山腰核心 h2")
		kit.eq(sc.check_terrain(sc.build_grid()), "", "地形校验全绿")
		var hcell: Vector2i = sc._hill_arr[0]
		kit.eq(sc.height_at(hcell.x, hcell.y), 1, "微丘 h1")
		# 建图落格
		var g := sc.build_grid()
		kit.eq(g.at(sc.core.x, sc.core.y), Grid.SOLID, "核心实心")
		kit.eq(g.at(sc.spawns[2].x, sc.spawns[2].y), Grid.COVER, "盆地口压矿")
		kit.eq(g.at(sc.basin_plug.x, sc.basin_plug.y), Grid.COVER, "插口唯一覆盖")
		kit.eq(g.at(sc._rock_arr[0].x, sc._rock_arr[0].y), Grid.SOLID, "岩群实心")
		kit.eq(g.at(sc._sparse_arr[0].x, sc._sparse_arr[0].y), Grid.COVER, "散土覆盖")
		kit.eq(g.get_h(sc._hill_arr[0].x, sc._hill_arr[0].y), 1, "微丘落盘")
		kit.eq(sc.check_grid(g), "", "结构校验全绿")
		# 路径长（等权步数场：核心 → 主口；盆地口密闭）
		var ff := FlowField.new(sc.build_grid(), true)
		ff.begin([sc.core])
		while not ff.done():
			ff.step(1 << 20)
		kit.eq(ff.dist_at(sc.spawns[0].x, sc.spawns[0].y), 470, "主口 1 路径长")
		kit.eq(ff.dist_at(sc.spawns[1].x, sc.spawns[1].y), 530, "主口 2 路径长")
		kit.eq(ff.dist_at(sc.spawns[2].x, sc.spawns[2].y), -1, "盆地口密闭")
		# 指纹（自由分支铸造值；默认图不受影响）
		kit.eq(sc.fingerprint(Canon.new()), 3771210114, "自由路径指纹（2026-10-25 末波阶段化后重录）"))

	kit.test("waves-contract", func():
		var sc := Scenario.new()
		var total := 0
		var first := 1 << 30
		var last := 0
		var max_batch := 0
		var finale := 0
		for wv in sc.waves:
			total += wv[3]
			if wv[0] < first:
				first = wv[0]
			if wv[0] > last:
				last = wv[0]
			if wv[3] > max_batch:
				max_batch = wv[3]
			if wv[0] >= 4600:
				finale += wv[3]
		kit.eq(sc.waves.size(), 25, "波次条目数")
		kit.eq(total, 200, "敌军总量")
		kit.eq(first, 60, "首条 tick")
		kit.eq(last, 5080, "末条 tick（阶段化后蛮兽殿后至 5080）")
		kit.eq(max_batch, 14, "单批上限")
		kit.eq(finale, 82, "末波开闸总量"))

	kit.test("terrain-contract", func():
		var sc := Scenario.new()
		var g := sc.build_grid()
		kit.eq(sc.check_terrain(g), "", "地形校验全绿")
		# 统计带（64×64 全格口径）：非零 150..450‰、负值 20..100‰、h≥3 至少 1
		var nz := 0
		var neg := 0
		var hi := 0
		for y in sc.h:
			for x in sc.w:
				var v := sc.height_at(x, y)
				if v != 0:
					nz += 1
				if v < 0:
					neg += 1
				if v >= 3:
					hi += 1
		var nz_perm := nz * 1000 / (sc.w * sc.h)
		var neg_perm := neg * 1000 / (sc.w * sc.h)
		kit.ok(nz_perm >= MapGen.TERRAIN_NZ_LO and nz_perm <= MapGen.TERRAIN_NZ_HI, "非零占比 %d‰ 越带" % nz_perm)
		kit.ok(neg_perm >= MapGen.TERRAIN_NEG_LO and neg_perm <= MapGen.TERRAIN_NEG_HI, "负高度占比 %d‰ 越带" % neg_perm)
		kit.ok(hi >= MapGen.TERRAIN_HI_MIN, "无 h≥3 格")
		# 基地地貌断言（按类型分支，不硬编码种子）
		var plain_zero := true
		var cliff_high := false
		var slope_nonzero := false
		for y in sc.h:
			for x in sc.w:
				var d := Grid.hex_dist(x, y, sc.core.x, sc.core.y)
				var v2 := sc.height_at(x, y)
				if sc.terrain_kind == MapGen.TERRAIN_PLAIN and d <= 5 and v2 != 0:
					plain_zero = false
				if sc.terrain_kind == MapGen.TERRAIN_CLIFF and d >= 4 and d <= 6 and v2 >= 3:
					cliff_high = true
				if sc.terrain_kind == MapGen.TERRAIN_SLOPE and d <= 3 and v2 != 0:
					slope_nonzero = true
		if sc.terrain_kind == MapGen.TERRAIN_PLAIN:
			kit.ok(plain_zero, "平原核心 5 圈非全 0")
		elif sc.terrain_kind == MapGen.TERRAIN_CLIFF:
			kit.ok(cliff_high, "崖旁核心 4..6 圈无 h≥3")
		else:
			kit.ok(slope_nonzero, "山腰核心 3 圈全 0")
		# 净空：主口 3×3 = 0、外圈 0..1；英雄位 0；矿与六邻 0..1
		for i in range(0, sc.spawns.size() - 1):
			var s: Vector2i = sc.spawns[i]
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					kit.eq(sc.height_at(s.x + dx, s.y + dy), 0, "主口净空高度 (%d,%d)" % [s.x + dx, s.y + dy])
			if not sc._freeform:
				kit.eq(g.get_h(s.x, s.y), 0, "出怪口落盘 h0")
		kit.eq(sc.height_at(sc.hero_spawn.x, sc.hero_spawn.y), 0, "英雄位 h0")
		for o in sc.ore_cells:
			var v3 := sc.height_at(o.x, o.y)
			kit.ok(v3 >= 0 and v3 <= 1, "矿格高度越界 (%d,%d)=%d" % [o.x, o.y, v3])
			for k in 6:
				var v4 := sc.height_at(Grid.nx(o.x, o.y, k), Grid.ny(o.x, o.y, k))
				kit.ok(v4 >= 0 and v4 <= 1, "矿邻格高度越界 (%d,%d)=%d" % [o.x, o.y, v4])
		# 矿台渐变带 + 矿口（2026-10-25）：中场矿 d2 环 ∈ [-1,2]（边界恒坡不崖），
		# 带中心六方向各走 5 格至少 2 向无 h≥2 墙（坡肩不许连圈围矿）
		for o in sc.mid_ore:
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					var gx: int = o.x + dx
					var gy: int = o.y + dy
					if Grid.hex_dist(gx, gy, o.x, o.y) == 2:
						var v5 := sc.height_at(gx, gy)
						kit.ok(v5 >= -1 and v5 <= 2, "矿台渐变带越界 (%d,%d)=%d" % [gx, gy, v5])
		var ctr: Vector2i = sc.mid_ore[2]
		var open_dirs := 0
		for k in 6:
			var cx := ctr.x
			var cy := ctr.y
			var walled := false
			for _step in 5:
				cx = Grid.nx(cx, cy, k)
				cy = Grid.ny(cx, cy, k)
				if cx < 0 or cy < 0 or cx >= sc.w or cy >= sc.h or sc.height_at(cx, cy) >= 2:
					walled = true
					break
			if not walled:
				open_dirs += 1
		kit.ok(open_dirs >= 2, "中场矿台开向不足 %d/6" % open_dirs))

	kit.test("terrain-ore-negative-control", func():
		var sc := Scenario.new()
		var g := sc.build_grid()
		kit.eq(sc.check_terrain(g), "", "基线地形合法")
		var o: Vector2i = sc.mid_ore[2]
		for k in 6:
			g.set_cell(Grid.nx(o.x, o.y, k), Grid.ny(o.x, o.y, k), Grid.SOLID)
		kit.ok(sc.check_terrain(g) != "", "矿六邻全封未被拒"))

	kit.test("terrain-ore-terrace-negative-control", func():
		# 矿台渐变带破例（d2 环抬到 h4）→ check_terrain 必须拒。
		# _height 与布局缓存共享引用：先 duplicate 再改，别毒化同进程后续 Scenario。
		var sc := Scenario.new()
		kit.eq(sc.check_terrain(sc.build_grid()), "", "基线地形合法")
		sc._height = sc._height.duplicate()
		var o: Vector2i = sc.mid_ore[2]
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				if Grid.hex_dist(o.x + dx, o.y + dy, o.x, o.y) == 2:
					sc._height[(o.y + dy) * sc.w + o.x + dx] = 4
		kit.ok(sc.check_terrain(sc.build_grid()) != "", "矿台渐变带破例未被拒")
		# 矿台围死（六方向 3..5 格全砌 h≥2，d1/d2 留合法）→ 必须拒
		var sc2 := Scenario.new()
		sc2._height = sc2._height.duplicate()
		for k in 6:
			var cx: int = sc2.mid_ore[2].x
			var cy: int = sc2.mid_ore[2].y
			var step := 0
			for _walk in 5:
				cx = Grid.nx(cx, cy, k)
				cy = Grid.ny(cx, cy, k)
				step += 1
				if cx < 0 or cy < 0 or cx >= sc2.w or cy >= sc2.h or step <= 2:
					continue
				sc2._height[cy * sc2.w + cx] = maxi(int(sc2._height[cy * sc2.w + cx]), 2)
		kit.ok(sc2.check_terrain(sc2.build_grid()) != "", "矿台围死未被拒"))

	kit.test("build-grid-structure", func():
		var sc := Scenario.new()
		var g := sc.build_grid()
		kit.eq(g.at(0, 0), Grid.SOLID, "西北角边境")
		kit.eq(g.at(sc.core.x, 0), Grid.SOLID, "北边境")
		kit.eq(g.at(63, 63), Grid.SOLID, "东南角边境")
		kit.eq(g.at(sc.core.x, sc.core.y), Grid.SOLID, "核心占地")
		kit.eq(g.at(sc.hero_spawn.x, sc.hero_spawn.y), Grid.OPEN, "英雄落位格恒通行")
		kit.eq(g.at(sc.spawns[0].x, sc.spawns[0].y), Grid.OPEN, "主出怪口 1 通行")
		kit.eq(g.at(sc.spawns[1].x, sc.spawns[1].y), Grid.OPEN, "主出怪口 2 通行")
		kit.eq(g.at(sc.spawns[2].x, sc.spawns[2].y), Grid.COVER, "盆地口压在矿格上")
		kit.eq(g.at(28, sc.ridge_y), Grid.SOLID, "岩脊实心")
		kit.eq(g.at(sc.chokes[0].x, sc.ridge_y), Grid.OPEN, "西咽喉口")
		kit.eq(g.at(sc.chokes[1].x, sc.ridge_y + 1), Grid.OPEN, "东咽喉口（脊中行）")
		kit.eq(g.at(30, sc.ridge_y + 1), Grid.SOLID, "咽喉间岩脊")
		kit.eq(g.at(sc.basin_rect.position.x, sc.basin_rect.position.y), Grid.SOLID, "盆地岩环")
		kit.eq(g.at(sc.basin_rect.position.x + sc.basin_rect.size.x - 1, sc.basin_rect.position.y + sc.basin_rect.size.y - 1), Grid.SOLID, "盆地岩环角")
		kit.eq(g.at(sc.basin_plug.x, sc.basin_plug.y), Grid.COVER, "插口是唯一覆盖格")
		kit.eq(g.at(4, 55), Grid.OPEN, "盆地内腔非矿格通行")
		kit.eq(g.at(33, 21), Grid.COVER, "中场矿")
		kit.eq(g.at(35, 21), Grid.COVER, "中场矿右缘")
		kit.eq(g.at(30, 21), Grid.OPEN, "矿带外通行")
		kit.eq(g.at(2, 17), Grid.COVER, "稀疏表土（可挖不给矿）")
		kit.eq(g.at(3, 17), Grid.OPEN, "表土纹理间断")
		kit.ok(g.rev > 0, "建图有实心/覆盖写入")
		kit.eq(g.get_h(sc.core.x, 6), sc.height_at(sc.core.x, 6), "高度落盘：核心格 = 地貌高度")
		kit.eq(g.get_h(sc.spawns[0].x, sc.spawns[0].y), 0, "高度落盘：主口 1 h0")
		kit.eq(g.get_h(sc.spawns[1].x, sc.spawns[1].y), 0, "高度落盘：主口 2 h0")
		kit.eq(g.get_h(sc.hero_spawn.x, sc.hero_spawn.y), 0, "高度落盘：英雄位 h0")
		kit.eq(g.get_h(sc.mesa.position.x, sc.mesa.position.y), 1, "高度落盘：台地 h1")
		kit.eq(sc.check_grid(g), "", "结构校验全绿"))

	kit.test("path-length-calibration", func():
		var sc := Scenario.new()
		var g := sc.build_grid()
		var ff := FlowField.new(g, true) # 等权步数口径（不吃爬坡代价）
		ff.begin([sc.core])
		while not ff.done():
			ff.step(1 << 20)
		for i in range(0, 2):
			var d := ff.dist_at(sc.spawns[i].x, sc.spawns[i].y)
			kit.ok(d >= Scenario.PATH_LO and d <= Scenario.PATH_HI, "主口 %d 路径长 %d 越标定带 [%d,%d]" % [i + 1, d, Scenario.PATH_LO, Scenario.PATH_HI])
		kit.eq(ff.dist_at(sc.spawns[2].x, sc.spawns[2].y), -1, "盆地口密闭不可达"))

	kit.test("64-seed-terrain-sweep", func():
		var kinds := [0, 0, 0]
		var nz_lo := 1 << 30
		var nz_hi := 0
		var neg_lo := 1 << 30
		var neg_hi := 0
		var path_lo := 1 << 30
		var path_hi := 0
		for i in 64:
			var s := Scenario.DEFAULT_SEED + i
			var sc := Scenario.new(s)
			kit.eq(sc.check_grid(sc.build_grid()), "", "种子 %d 结构校验" % s)
			kit.eq(sc.check_plug_open(sc.build_grid()), "", "种子 %d 插口开门" % s)
			var ct := sc.check_terrain(sc.build_grid())
			kit.eq(ct, "", "种子 %d 地形校验：%s" % [s, ct])
			kinds[sc.terrain_kind] += 1
			# 三类地貌的基地断言
			var plain_zero := true
			var cliff_high := false
			var slope_nonzero := false
			var nz := 0
			var neg := 0
			for y in sc.h:
				for x in sc.w:
					var d := Grid.hex_dist(x, y, sc.core.x, sc.core.y)
					var v := sc.height_at(x, y)
					if v != 0:
						nz += 1
					if v < 0:
						neg += 1
					if sc.terrain_kind == MapGen.TERRAIN_PLAIN and d <= 5 and v != 0:
						plain_zero = false
					if sc.terrain_kind == MapGen.TERRAIN_CLIFF and d >= 4 and d <= 6 and v >= 3:
						cliff_high = true
					if sc.terrain_kind == MapGen.TERRAIN_SLOPE and d <= 3 and v != 0:
						slope_nonzero = true
			if sc.terrain_kind == MapGen.TERRAIN_PLAIN:
				kit.ok(plain_zero, "种子 %d 平原核心 5 圈非全 0" % s)
			elif sc.terrain_kind == MapGen.TERRAIN_CLIFF:
				kit.ok(cliff_high, "种子 %d 崖旁核心 4..6 圈无 h≥3" % s)
			else:
				kit.ok(slope_nonzero, "种子 %d 山腰核心 3 圈全 0" % s)
			nz_lo = mini(nz_lo, nz * 1000 / (sc.w * sc.h))
			nz_hi = maxi(nz_hi, nz * 1000 / (sc.w * sc.h))
			neg_lo = mini(neg_lo, neg * 1000 / (sc.w * sc.h))
			neg_hi = maxi(neg_hi, neg * 1000 / (sc.w * sc.h))
			# 等权步数路径长（所有主口）
			var ff := FlowField.new(sc.build_grid(), true)
			ff.begin([sc.core])
			while not ff.done():
				ff.step(1 << 20)
			for j in range(0, sc.spawns.size() - 1):
				var d2: int = ff.dist_at(sc.spawns[j].x, sc.spawns[j].y)
				kit.ok(d2 >= Scenario.PATH_LO and d2 <= Scenario.PATH_HI, "种子 %d 主口 %d 路径长 %d 越带" % [s, j + 1, d2])
				path_lo = mini(path_lo, d2)
				path_hi = maxi(path_hi, d2)
		kit.ok(kinds[0] > 0 and kinds[1] > 0 and kinds[2] > 0, "三类地貌覆盖 %s" % str(kinds))
		kit.ok(nz_lo >= MapGen.TERRAIN_NZ_LO and nz_hi <= MapGen.TERRAIN_NZ_HI, "非零占比 [%d,%d]‰ 越带" % [nz_lo, nz_hi])
		kit.ok(neg_lo >= MapGen.TERRAIN_NEG_LO and neg_hi <= MapGen.TERRAIN_NEG_HI, "负高度占比 [%d,%d]‰ 越带" % [neg_lo, neg_hi])
		kit.ok(path_lo >= Scenario.PATH_LO and path_hi <= Scenario.PATH_HI, "路径长 [%d,%d] 越带" % [path_lo, path_hi]))

	kit.test("cliff-forms-64-seed-sweep", func():
		# 崖形摆布（2026-10-25 §11.45，软保证）：h≥3 连通分量 ≤3 格=孤峰、≥5 格=崖脉。
		# 诊断实测 64/64 双形态齐备（地形 2.0 自然山体也有贡献），钉满带。
		var both := 0
		var misses: Array = []
		for i in 64:
			var s := Scenario.DEFAULT_SEED + i
			var sc := Scenario.new(s)
			var seen := {}
			var n_butte := 0
			var n_range := 0
			for idx in sc.w * sc.h:
				@warning_ignore("integer_division")
				var bx: int = idx % sc.w
				@warning_ignore("integer_division")
				var by: int = idx / sc.w
				if seen.has(idx) or sc.height_at(bx, by) < 3:
					continue
				var q: Array = [idx]
				var comp := 0
				seen[idx] = true
				var head := 0
				while head < q.size():
					var cur: int = q[head]
					head += 1
					comp += 1
					@warning_ignore("integer_division")
					var cx: int = cur % sc.w
					@warning_ignore("integer_division")
					var cy: int = cur / sc.w
					for k in 6:
						var nx: int = Grid.nx(cx, cy, k)
						var ny: int = Grid.ny(cx, cy, k)
						if nx < 0 or ny < 0 or nx >= sc.w or ny >= sc.h:
							continue
						var ni: int = ny * sc.w + nx
						if seen.has(ni) or sc.height_at(nx, ny) < 3:
							continue
						seen[ni] = true
						q.append(ni)
				if comp <= 3:
					n_butte += 1
				elif comp >= 5:
					n_range += 1
			if n_butte > 0 and n_range > 0:
				both += 1
			else:
				misses.append([s, n_butte, n_range])
		kit.eq(both, 64, "双形态命中率（孤峰+崖脉）缺：%s" % str(misses)))

	kit.test("cliff-entrance-reachable", func():
		var sc: Scenario = null
		for i in 64:
			var s := Scenario.DEFAULT_SEED + i
			var c := Scenario.new(s)
			if c.terrain_kind == MapGen.TERRAIN_CLIFF:
				sc = c
				break
		kit.ok(sc != null, "64 种子内无崖旁样本")
		if sc != null:
			var g := sc.build_grid()
			for climb in [2, 1]:
				var ff := FlowField.new(g, false, climb)
				ff.begin([sc.core])
				while not ff.done():
					ff.step(1 << 20)
				for j in range(0, sc.spawns.size() - 1):
					kit.ok(ff.dist_at(sc.spawns[j].x, sc.spawns[j].y) >= 0, "崖旁基地主口 %d 不可达（climb=%d）" % [j + 1, climb]))

	kit.test("is-ore", func():
		var sc := Scenario.new()
		kit.ok(sc.is_ore(33, 21), "中场矿是矿")
		kit.ok(sc.is_ore(31, 21), "中场矿带左缘")
		kit.ok(sc.is_ore(35, 21), "中场矿带右缘")
		kit.ok(sc.is_ore(5, 56), "盆地矿左上")
		kit.ok(sc.is_ore(7, 59), "盆地矿右下")
		kit.ok(not sc.is_ore(30, 21), "矿带外不是矿")
		kit.ok(not sc.is_ore(sc.basin_plug.x, sc.basin_plug.y), "插口不是矿")
		kit.ok(not sc.is_ore(4, 55), "盆地内腔非矿格不是矿")
		kit.ok(not sc.is_ore(0, 0), "边境不是矿"))

	kit.test("fingerprint-determinism", func():
		var canon := Canon.new()
		var a := Scenario.new()
		var b := Scenario.new()
		kit.eq(a.fingerprint(canon), b.fingerprint(canon), "同种子两次指纹不一致")
		kit.eq(a.fingerprint(canon), 2137177064, "指纹 vs 引擎现值（2026-10-25 末波阶段化九次基线）")
		var third := Scenario.new(20261004)
		kit.ok(a.fingerprint(canon) != third.fingerprint(canon), "换种子指纹没变")
		var mutated := Scenario.new()
		mutated.wave_scale_pct = 90
		kit.ok(a.fingerprint(canon) != mutated.fingerprint(canon), "改 wave_scale_pct 指纹没变")
		var mutated2 := Scenario.new()
		mutated2.waves[0] = [61, 1, Sim.E_SWARM, 1]
		kit.ok(a.fingerprint(canon) != mutated2.fingerprint(canon), "改波次指纹没变")
		var mutated3 := Scenario.new()
		mutated3.mesa = Rect2i(50, 46, 2, 2)
		kit.ok(a.fingerprint(canon) != mutated3.fingerprint(canon), "改微丘指纹没变"))
