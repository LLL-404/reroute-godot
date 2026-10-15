extends ProbeKit

# R5 验证探针：scenario 移植（数值表/夹具结构/is_ore/指纹对拍引擎现值/波次合同）。
# 判定：exit 0 + stdout 含 `[SCENARIO] PASS`。


func _initialize() -> void:
	# 数值表
	check(Sim.TICK_HZ == 20 and Sim.START_SUPPLY == 300 and Sim.ORE_YIELD == 25, "sim consts")
	check(Sim.CONVOY_SHIFT == 3 and Sim.FILL_COST == 15 and Sim.LOWER_COST == 10, "economy consts")
	check(Sim.H_MIN == 0 and Sim.H_MAX == 5, "height consts")
	check(Sim.B_WALL == 1 and Sim.B_TOWER == 2 and Sim.B_CORE == 3, "building idx")
	check(Sim.E_SWARM == 1 and Sim.E_BEHEMOTH == 2, "enemy idx")
	check(Sim.BUILDINGS[Sim.B_WALL - 1]["cost"] == 10 and Sim.BUILDINGS[Sim.B_WALL - 1]["hp"] == 120, "wall def")
	check(Sim.BUILDINGS[Sim.B_TOWER - 1]["range"] == 12 and Sim.BUILDINGS[Sim.B_TOWER - 1]["shoots"] == true, "tower def")
	check(Sim.ENEMIES[Sim.E_SWARM - 1]["reward"] == 3 and Sim.ENEMIES[Sim.E_BEHEMOTH - 1]["damage"] == 60, "enemy defs")
	check(Sim.HERO["speed_ticks"] == 3 and Sim.HERO["skill_cooldown"] == 400, "hero def")

	var sc := Scenario.new()
	# 布局锚点
	check(sc.core == Vector2i(24, 6) and sc.hero_spawn == Vector2i(24, 8), "anchors")
	check(sc.spawns.size() == 3 and sc.spawns[2] == Vector2i(5, 41), "spawns")
	check(sc.basin_plug == Vector2i(5, 37), "plug")
	check(sc.end_tick == 6400 and sc.hard_cap_tick == 8800 and sc.trickle_every == 300, "ticks")

	# 波次合同
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
	check(sc.waves.size() == 25, "waves count")
	check(total == 200 and first == 60 and last == 4860 and max_batch == 14 and finale == 82, "waves contract")

	# 高度夹具
	check(sc.height_at(24, 6) == 3 and sc.height_at(24, 12) == 2 and sc.height_at(27, 12) == 1, "height fixture")
	check(sc.height_at(11, 30) == 1 and sc.height_at(24, 31) == 0 and sc.height_at(24, 40) == 0, "height fixture 2")

	# 建图结构
	var g := sc.build_grid()
	check(g.at(0, 0) == Grid.SOLID and g.at(24, 0) == Grid.SOLID and g.at(47, 47) == Grid.SOLID, "borders")
	check(g.at(24, 6) == Grid.SOLID, "core solid")
	check(g.at(24, 8) == Grid.OPEN, "hero spawn open")
	check(g.at(12, 40) == Grid.OPEN and g.at(36, 40) == Grid.OPEN, "main spawns open")
	check(g.at(5, 41) == Grid.COVER, "basin spawn on ore cover")
	check(g.at(20, 31) == Grid.SOLID and g.at(11, 31) == Grid.OPEN and g.at(36, 32) == Grid.OPEN, "ridge/chokes")
	check(g.at(2, 37) == Grid.SOLID and g.at(9, 45) == Grid.SOLID, "basin ring")
	check(g.at(5, 37) == Grid.COVER, "plug cover")
	check(g.at(7, 44) == Grid.OPEN, "basin interior")
	check(g.at(22, 20) == Grid.COVER and g.at(26, 20) == Grid.COVER and g.at(21, 20) == Grid.OPEN, "mid ore")
	check(g.at(4, 17) == Grid.COVER, "sparse cover")
	check(g.get_h(24, 6) == 3 and g.get_h(24, 12) == 2 and g.get_h(11, 30) == 1, "heights landed")

	# is_ore
	check(sc.is_ore(22, 20) and sc.is_ore(23, 20) and sc.is_ore(4, 42), "is_ore true")
	check(not sc.is_ore(5, 37) and not sc.is_ore(21, 20) and not sc.is_ore(0, 0), "is_ore false")

	# 指纹：确定性 + 负对照 + **引擎现值对拍**
	var canon := Canon.new()
	var fp := sc.fingerprint(canon)
	var fp2 := Scenario.new().fingerprint(canon)
	check(fp == fp2, "fingerprint determinism")
	check(fp == 309416034, "fingerprint vs 引擎现值 0x12715062（得 " + str(fp) + "）")
	var mut := Scenario.new()
	mut.wave_scale_pct = 90
	check(sc.fingerprint(canon) != mut.fingerprint(canon), "fingerprint negative control")

	finish("SCENARIO")
