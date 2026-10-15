extends RefCounted

# scenario 单测（移植自 reroute/tests/test_scenario.lua）：数值表合同、64² 夹具结构、
# 高度夹具、剧本指纹确定性与负对照（含引擎现值对拍 0x02d81d2a）。


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

	kit.test("layout-anchors", func():
		var sc := Scenario.new()
		kit.eq(sc.w, 64, "w")
		kit.eq(sc.h, 64, "h")
		kit.eq(sc.core, Vector2i(32, 6), "core")
		kit.eq(sc.hero_spawn, Vector2i(32, 8), "hero_spawn")
		kit.eq(sc.spawns.size(), 3, "spawns 数")
		kit.eq(sc.spawns[2], Vector2i(5, 57), "盆地口")
		kit.eq(sc.basin_plug, Vector2i(5, 53), "plug")
		kit.eq(sc.end_tick, 6400, "end_tick")
		kit.eq(sc.hard_cap_tick, 8800, "hard_cap_tick")
		kit.eq(sc.trickle_every, 300, "trickle_every")
		kit.eq(sc.wave_scale_pct, 100, "wave_scale_pct"))

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

	kit.test("height-fixture", func():
		var sc := Scenario.new()
		kit.eq(sc.height_at(32, 6), 3, "核心山头 h3")
		kit.eq(sc.height_at(32, 12), 2, "山头南台阶 h2")
		kit.eq(sc.height_at(34, 12), 2, "台阶右缘 h2")
		kit.eq(sc.height_at(35, 12), 1, "台阶外落 h1")
		kit.eq(sc.height_at(32, 20), 1, "北岸台地 h1")
		kit.eq(sc.height_at(19, 40), 1, "咽喉谷口 y40 h1")
		kit.eq(sc.height_at(32, 40), 0, "y40 非谷口 h0")
		kit.eq(sc.height_at(32, 41), 0, "岩脊线南 h0")
		kit.eq(sc.height_at(32, 56), 0, "南岸低地 h0")
		kit.eq(sc.height_at(0, 0), 1, "西北角 h1"))

	kit.test("build-grid-structure", func():
		var sc := Scenario.new()
		var g := sc.build_grid()
		kit.eq(g.at(0, 0), Grid.SOLID, "西北角边境")
		kit.eq(g.at(32, 0), Grid.SOLID, "北边境")
		kit.eq(g.at(63, 63), Grid.SOLID, "东南角边境")
		kit.eq(g.at(sc.core.x, sc.core.y), Grid.SOLID, "核心占地")
		kit.eq(g.at(sc.hero_spawn.x, sc.hero_spawn.y), Grid.OPEN, "英雄落位格恒通行")
		kit.eq(g.at(sc.spawns[0].x, sc.spawns[0].y), Grid.OPEN, "主出怪口 1 通行")
		kit.eq(g.at(sc.spawns[1].x, sc.spawns[1].y), Grid.OPEN, "主出怪口 2 通行")
		kit.eq(g.at(sc.spawns[2].x, sc.spawns[2].y), Grid.COVER, "盆地口压在矿格上")
		kit.eq(g.at(28, 41), Grid.SOLID, "岩脊实心")
		kit.eq(g.at(19, 41), Grid.OPEN, "西咽喉口")
		kit.eq(g.at(44, 42), Grid.OPEN, "东咽喉口")
		kit.eq(g.at(21, 41), Grid.SOLID, "咽喉间岩脊")
		kit.eq(g.at(2, 53), Grid.SOLID, "盆地岩环")
		kit.eq(g.at(9, 61), Grid.SOLID, "盆地岩环角")
		kit.eq(g.at(sc.basin_plug.x, sc.basin_plug.y), Grid.COVER, "插口是唯一覆盖格")
		kit.eq(g.at(7, 60), Grid.OPEN, "盆地内腔非矿格通行")
		kit.eq(g.at(30, 20), Grid.COVER, "中场矿")
		kit.eq(g.at(34, 20), Grid.COVER, "中场矿右缘")
		kit.eq(g.at(29, 20), Grid.OPEN, "矿带外通行")
		kit.eq(g.at(4, 17), Grid.COVER, "稀疏表土（可挖不给矿）")
		kit.ok(g.rev > 0, "建图有实心/覆盖写入")
		kit.eq(g.get_h(32, 6), 3, "高度落盘：核心山头")
		kit.eq(g.get_h(32, 12), 2, "高度落盘：台阶")
		kit.eq(g.get_h(19, 40), 1, "高度落盘：谷口")
		kit.eq(g.get_h(32, 41), 0, "高度落盘：脊南"))

	kit.test("is-ore", func():
		var sc := Scenario.new()
		kit.ok(sc.is_ore(30, 20), "中场矿是矿")
		kit.ok(sc.is_ore(31, 20), "中场矿带内含 x31")
		kit.ok(sc.is_ore(4, 58), "盆地矿是矿")
		kit.ok(not sc.is_ore(5, 53), "插口不是矿")
		kit.ok(not sc.is_ore(29, 20), "矿带缝隙不是矿")
		kit.ok(not sc.is_ore(0, 0), "边境不是矿"))

	kit.test("fingerprint-determinism", func():
		var canon := Canon.new()
		var a := Scenario.new()
		var b := Scenario.new()
		kit.eq(a.fingerprint(canon), b.fingerprint(canon), "同剧本两次指纹不一致")
		kit.eq(a.fingerprint(canon), 47717674, "指纹 vs 引擎现值 0x02d81d2a")
		var mutated := Scenario.new()
		mutated.wave_scale_pct = 90
		kit.ok(a.fingerprint(canon) != mutated.fingerprint(canon), "改 wave_scale_pct 指纹没变")
		var mutated2 := Scenario.new()
		mutated2.waves[0] = [61, 1, Sim.E_SWARM, 1]
		kit.ok(a.fingerprint(canon) != mutated2.fingerprint(canon), "改波次指纹没变"))
