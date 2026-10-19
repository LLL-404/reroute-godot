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
		kit.eq(Sim.H_MIN, 0, "H_MIN")
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
		kit.eq(sc._rock_arr.size(), 217, "岩群数")
		kit.eq(sc._hill_arr.size(), 285, "微丘数")
		kit.eq(sc._sparse_arr.size(), 9, "散土数")
		kit.eq(sc._sparse_arr[0], Vector2i(13, 30), "散土首格")
		# 山头高度分带（按六边距离取 d3/d4 格，不手算坐标）
		var d3 := Vector2i(-1, -1)
		var d4 := Vector2i(-1, -1)
		for y in sc.h:
			for x in sc.w:
				var d := Grid.hex_dist(x, y, sc.core.x, sc.core.y)
				if d == 3 and d3.x < 0:
					d3 = Vector2i(x, y)
				if d == 4 and d4.x < 0:
					d4 = Vector2i(x, y)
		kit.eq(sc.height_at(sc.core.x, sc.core.y), 3, "核心山头 h3")
		kit.eq(sc.height_at(d3.x, d3.y), 2, "山头 d3 = h2")
		kit.eq(sc.height_at(d4.x, d4.y), 1, "山头 d4 = h1")
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
		# 路径长（核心流场 → 主口；盆地口密闭）
		var ff := FlowField.new(sc.build_grid(), false)
		ff.begin([sc.core])
		while not ff.done():
			ff.step(1 << 20)
		kit.eq(ff.dist_at(sc.spawns[0].x, sc.spawns[0].y), 470, "主口 1 路径长")
		kit.eq(ff.dist_at(sc.spawns[1].x, sc.spawns[1].y), 530, "主口 2 路径长")
		kit.eq(ff.dist_at(sc.spawns[2].x, sc.spawns[2].y), -1, "盆地口密闭")
		# 指纹（自由分支铸造值；默认图 0x7dea2b02 不受影响）
		kit.eq(sc.fingerprint(Canon.new()), 0xf5f49e0c, "自由路径指纹"))

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
		kit.eq(last, 4860, "末条 tick")
		kit.eq(max_batch, 14, "单批上限")
		kit.eq(finale, 82, "末波开闸总量"))

	kit.test("height-template", func():
		var sc := Scenario.new()
		kit.eq(sc.height_at(sc.core.x, 6), 3, "核心山头 h3")
		kit.eq(sc.height_at(sc.core.x, 12), 2, "山头南台阶 h2")
		kit.eq(sc.height_at(sc.core.x + 2, 12), 2, "台阶右缘 h2")
		kit.eq(sc.height_at(sc.core.x + 3, 12), 1, "台阶外落 h1")
		kit.eq(sc.height_at(sc.core.x, 20), 1, "北岸台地 h1")
		kit.eq(sc.height_at(sc.chokes[0].x, sc.ridge_y), 1, "咽喉谷口 h1")
		kit.eq(sc.height_at(sc.core.x, sc.ridge_y), 0, "脊带非谷口 h0")
		kit.eq(sc.height_at(sc.core.x, sc.ridge_y + 1), 0, "岩脊线南 h0")
		kit.eq(sc.height_at(sc.core.x, 56), 0, "南岸低地 h0")
		kit.eq(sc.height_at(sc.mesa.position.x, sc.mesa.position.y), 1, "微丘 h1")
		kit.eq(sc.height_at(sc.mesa.position.x + 1, sc.mesa.position.y + 1), 1, "微丘右下 h1")
		kit.eq(sc.height_at(sc.mesa.position.x + 2, sc.mesa.position.y), 0, "微丘外 h0")
		kit.eq(sc.height_at(0, 0), 1, "西北角 h1"))

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
		kit.eq(g.get_h(sc.core.x, 6), 3, "高度落盘：核心山头")
		kit.eq(g.get_h(sc.core.x, 12), 2, "高度落盘：台阶")
		kit.eq(g.get_h(sc.chokes[0].x, sc.ridge_y), 1, "高度落盘：谷口")
		kit.eq(g.get_h(sc.core.x, sc.ridge_y + 1), 0, "高度落盘：脊南")
		kit.eq(sc.check_grid(g), "", "结构校验全绿"))

	kit.test("path-length-calibration", func():
		var sc := Scenario.new()
		var g := sc.build_grid()
		var ff := FlowField.new(g, false)
		ff.begin([sc.core])
		while not ff.done():
			ff.step(1 << 20)
		for i in range(0, 2):
			var d := ff.dist_at(sc.spawns[i].x, sc.spawns[i].y)
			kit.ok(d >= Scenario.PATH_LO and d <= Scenario.PATH_HI, "主口 %d 路径长 %d 越标定带 [%d,%d]" % [i + 1, d, Scenario.PATH_LO, Scenario.PATH_HI])
		kit.eq(ff.dist_at(sc.spawns[2].x, sc.spawns[2].y), -1, "盆地口密闭不可达"))

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
		kit.eq(a.fingerprint(canon), 0x7dea2b02, "指纹 vs 引擎现值")
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
