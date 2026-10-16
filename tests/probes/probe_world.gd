extends ProbeKit

# R6 验证探针：world 移植（构造/命令/200 tick 不变式/确定性/冻结/schema）。
# 判定：exit 0 + stdout 含 `[WORLD] PASS`。


func _initialize() -> void:
	# 构造（真实 64² 场景，坐标一律锚定 Scenario）
	var sc := Scenario.new()
	var w := World.new(sc, 20261003)
	check(w.tick_count == 0 and w.supply == 300 and w.outcome == World.RUNNING, "new basics")
	check(w.units.size() == 0 and w.buildings.size() == 1, "new tables")
	check(w.core["hp"] == 1200 and w.core["x"] == sc.core.x and w.core["y"] == sc.core.y, "core placed")
	check(w.hero["x"] == sc.hero_spawn.x and w.hero["y"] == sc.hero_spawn.y and w.hero["tx"] == -1, "hero placed")
	check(w.building_at(sc.core.x, sc.core.y) == w.core, "building_at core")
	check(w.field_rev == w.grid.rev, "field synced")

	# 真实图命令
	w.apply_command({ "kind": "dig", "x": sc.mid_ore[0].x, "y": sc.mid_ore[0].y })
	check(w.supply == 325 and w.grid.at(sc.mid_ore[0].x, sc.mid_ore[0].y) == Grid.OPEN, "dig ore")
	w.apply_command({ "kind": "dig", "x": sc.core.x, "y": 17 })
	check(w.supply == 325, "dig non-ore no yield")
	w.apply_command({ "kind": "dig", "x": sc.basin_plug.x, "y": sc.basin_plug.y })
	check(w.route_opened == true, "dig plug opens route")
	w.apply_command({ "kind": "wall", "x": sc.core.x, "y": 20 })
	check(w.supply == 315 and w.grid.at(sc.core.x, 20) == Grid.SOLID, "wall build")
	w.apply_command({ "kind": "wall", "x": sc.core.x, "y": sc.core.y })
	check(w.supply == 315, "wall on core rejected")
	w.apply_command({ "kind": "spawn", "x": sc.spawns[0].x, "y": sc.spawns[0].y })
	check(w.units.size() == 1 and w.units[0]["speed_ticks"] == 4, "spawn")
	w.apply_command({ "kind": "spawn", "x": sc.core.x, "y": sc.core.y })
	check(w.units.size() == 1, "spawn on solid rejected")
	w.tick()
	check(w.tick_count == 1, "tick count")

	# 200 tick 推进 + 不变式
	var w2 := World.new(Scenario.new(), 777)
	for _i in 200:
		w2.tick()
	var inv_ok := true
	for u in w2.units:
		if not w2.grid.passable(u["x"], u["y"]):
			inv_ok = false
	if w2.supply < 0:
		inv_ok = false
	if w2.outcome == World.RUNNING and (w2.core == null or w2.core.is_empty() or w2.core["hp"] <= 0):
		inv_ok = false
	check(inv_ok, "invariants after 200 ticks")
	check(w2.tick_count == 200, "tick advanced")
	check(w2.units.size() > 0, "trickle spawned units")

	# 确定性：同种子同指纹
	var a := World.new(Scenario.new(), 4242)
	var b := World.new(Scenario.new(), 4242)
	for _i in 100:
		a.tick()
		b.tick()
	check(a.fingerprint() == b.fingerprint(), "determinism")

	# schema 字节
	var buf := a.canonical_bytes()
	check(buf.data[0] == 0 and buf.data[1] == 0 and buf.data[2] == 0 and buf.data[3] == 5, "STATE_SCHEMA bytes")

	# 终局冻结
	var f := World.new(sc, 1)
	f.outcome = World.LOST
	var fp0 := f.fingerprint()
	f.apply_command({ "kind": "wall", "x": sc.core.x, "y": 20 })
	f.apply_command({ "kind": "dig", "x": sc.mid_ore[0].x, "y": sc.mid_ore[0].y })
	f.apply_command({ "kind": "hero", "x": sc.core.x, "y": 14 })
	f.apply_command({ "kind": "shock" })
	f.apply_command({ "kind": "spawn", "x": sc.spawns[0].x, "y": sc.spawns[0].y })
	for _i in 50:
		f.tick()
	check(f.fingerprint() == fp0, "frozen after outcome")

	finish("WORLD")
