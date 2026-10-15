extends RefCounted

# world 单测（移植自 reroute/tests/test_world.lua）。
# 方法：真实 64² 场景管结构断言；行为断言用 StubScenario 小图把变量压到最少。
# 白盒仅用于制造边界（供给/血量/tick 直写），行为断言一律走 apply_command/tick。


func _run(w: World, n: int) -> void:
	for _i in n:
		w.tick()


func register(kit: TestKit) -> void:
	kit.module("world")

	# ---------------- 真实场景：构造与基础命令 ----------------

	kit.test("new-structure", func():
		var sc := Scenario.new()
		var w := World.new(sc, 20261003)
		kit.eq(w.tick_count, 0, "初始 tick")
		kit.eq(w.supply, Sim.START_SUPPLY, "初始供给")
		kit.eq(w.outcome, World.RUNNING, "初始进行中")
		kit.eq(w.units.size(), 0, "初始无单位")
		kit.eq(w.buildings.size(), 1, "初始只有核心")
		kit.eq(w.core["hp"], 1200, "核心血量")
		kit.ok(w.building_at(sc.core.x, sc.core.y) == w.core, "核心落位")
		kit.eq(w.hero["x"], sc.hero_spawn.x, "英雄 x")
		kit.eq(w.hero["y"], sc.hero_spawn.y, "英雄 y")
		kit.ok(w.grid.passable(w.hero["x"], w.hero["y"]), "英雄在通行格")
		kit.eq(w.grid.at(sc.core.x, sc.core.y), Grid.SOLID, "核心占地实心")
		kit.eq(w.field_rev, w.grid.rev, "主场已同步到当前 rev")
		kit.eq(w.hero["tx"], -1, "英雄待命"))

	kit.test("dig-ore-and-cover", func():
		var w := World.new(Scenario.new(), 1)
		w.apply_command({ "kind": "dig", "x": 30, "y": 20 })
		kit.eq(w.supply, Sim.START_SUPPLY + Sim.ORE_YIELD, "挖矿 +25")
		kit.eq(w.grid.at(30, 20), Grid.OPEN, "矿格挖开")
		w.apply_command({ "kind": "dig", "x": 4, "y": 17 })
		kit.eq(w.supply, Sim.START_SUPPLY + Sim.ORE_YIELD, "非矿覆盖无收益")
		kit.eq(w.grid.at(4, 17), Grid.OPEN, "表土挖开"))

	kit.test("dig-plug-opens-route", func():
		var w := World.new(Scenario.new(), 1)
		kit.eq(w.route_opened, false, "开局未开门")
		w.apply_command({ "kind": "dig", "x": 5, "y": 53 })
		kit.eq(w.route_opened, true, "挖插口开门")
		kit.eq(w.supply, Sim.START_SUPPLY, "插口无矿收益"))

	kit.test("dig-rejections", func():
		var w := World.new(Scenario.new(), 1)
		var fp0 := w.fingerprint()
		w.apply_command({ "kind": "dig", "x": 32, "y": 6 })
		w.apply_command({ "kind": "dig", "x": -5, "y": 12 })
		w.apply_command({ "kind": "dig", "x": 99, "y": 99 })
		w.apply_command({ "kind": "dig", "x": 32, "y": 8 })
		kit.eq(w.supply, Sim.START_SUPPLY, "拒绝的挖凿零供给副作用")
		kit.eq(w.fingerprint(), fp0, "拒绝的挖凿零指纹副作用"))

	kit.test("wall-build-and-reject", func():
		var w := World.new(Scenario.new(), 1)
		w.apply_command({ "kind": "wall", "x": 19, "y": 39 })
		kit.eq(w.supply, Sim.START_SUPPLY - 10, "墙费 10")
		kit.eq(w.grid.at(19, 39), Grid.SOLID, "墙落地挡路")
		kit.ok(w.by_cell.get(w.grid.idx(19, 39)) != null, "墙登记 by_cell")
		var s := w.supply
		w.apply_command({ "kind": "wall", "x": 32, "y": 6 })
		w.apply_command({ "kind": "wall", "x": -1, "y": 0 })
		w.apply_command({ "kind": "wall", "x": 34, "y": 20 })
		w.apply_command({ "kind": "wall", "x": 19, "y": 39 })
		kit.eq(w.supply, s, "拒绝的建造零扣费")
		kit.eq(w.buildings.size(), 2, "只有核心 + 一面墙"))

	kit.test("spawn-and-tick", func():
		var w := World.new(Scenario.new(), 1)
		w.apply_command({ "kind": "spawn", "x": 20, "y": 56 })
		kit.eq(w.units.size(), 1, "单位入表")
		kit.eq(w.units[0]["speed_ticks"], Sim.ENEMIES[Sim.E_SWARM - 1]["speed_ticks"], "speed=0 取默认")
		kit.eq(w.units[0]["hp"], 30, "swarm hp")
		kit.eq(w.units[0]["kind"], Sim.E_SWARM, "kind")
		w.apply_command({ "kind": "spawn", "x": 32, "y": 6 })
		kit.eq(w.units.size(), 1, "阻挡格拒收")
		_run(w, 1)
		kit.eq(w.tick_count, 1, "tick 计数"))

	kit.test("tower-build-halving", func():
		var w := World.new(Scenario.new(), 1)
		w.apply_command({ "kind": "tower", "x": 19, "y": 39 })
		kit.eq(w.buildings[1]["build_left"], 60, "首波前施工减半 120//2")
		w.tick_count = 60 # 白盒：越过 waves[1][1]
		w.apply_command({ "kind": "tower", "x": 20, "y": 39 })
		kit.eq(w.buildings[2]["build_left"], 120, "首波后不减半"))

	# ---------------- 经济：拆除退款 ----------------

	kit.test("remove-refund", func():
		var w := World.new(StubScenario.new(), 1)
		w.apply_command({ "kind": "wall", "x": 3, "y": 3 })
		kit.eq(w.supply, 290, "墙扣 10")
		w.apply_command({ "kind": "remove", "x": 3, "y": 3 })
		kit.eq(w.supply, 295, "即时建筑退 50% = 5")
		kit.eq(w.grid.at(3, 3), Grid.OPEN, "拆除后通行")
		kit.ok(w.by_cell.get(w.grid.idx(3, 3)) == null, "by_cell 清除")
		w.apply_command({ "kind": "remove", "x": 3, "y": 3 })
		kit.eq(w.supply, 295, "重复拆除零副作用")
		w.apply_command({ "kind": "tower", "x": 5, "y": 5 })
		kit.eq(w.supply, 235, "塔扣 60")
		w.apply_command({ "kind": "remove", "x": 5, "y": 5 })
		kit.eq(w.supply, 283, "施工中退 80% = 48")
		w.apply_command({ "kind": "remove", "x": 0, "y": 0 })
		kit.eq(w.supply, 283, "核心不可拆")
		kit.ok(w.building_at(0, 0) != null, "核心仍在"))

	# ---------------- 地形改造 ----------------

	kit.test("fill-lower-basic", func():
		var w := World.new(StubScenario.new(), 1)
		w.apply_command({ "kind": "fill", "x": 3, "y": 3 })
		kit.eq(w.grid.get_h(3, 3), 1, "填高 +1")
		kit.eq(w.supply, 285, "填高费 15")
		w.apply_command({ "kind": "fill", "x": 3, "y": 3 })
		kit.eq(w.grid.get_h(3, 3), 2, "再填 +1")
		kit.eq(w.supply, 270, "再扣 15")
		w.apply_command({ "kind": "lower", "x": 3, "y": 3 })
		kit.eq(w.grid.get_h(3, 3), 1, "挖低 -1")
		kit.eq(w.supply, 260, "挖低扣 10"))

	kit.test("fill-hmax-hmin", func():
		var w := World.new(StubScenario.new(), 1)
		for _i in 5:
			w.apply_command({ "kind": "fill", "x": 3, "y": 3 })
		kit.eq(w.grid.get_h(3, 3), Sim.H_MAX, "连填到 h5")
		kit.eq(w.supply, 225, "5 次填高 75")
		w.apply_command({ "kind": "fill", "x": 3, "y": 3 })
		kit.eq(w.grid.get_h(3, 3), Sim.H_MAX, "顶格再填被拒")
		kit.eq(w.supply, 225, "顶格拒填不扣费")
		for _i in 5:
			w.apply_command({ "kind": "lower", "x": 3, "y": 3 })
		kit.eq(w.grid.get_h(3, 3), Sim.H_MIN, "连挖到 h0")
		kit.eq(w.supply, 175, "5 次挖低扣 50")
		w.apply_command({ "kind": "lower", "x": 3, "y": 3 })
		kit.eq(w.grid.get_h(3, 3), Sim.H_MIN, "地板再挖被拒")
		kit.eq(w.supply, 175, "地板拒挖不扣费"))

	kit.test("fill-lower-guards", func():
		var w := World.new(StubScenario.new({ "cover": [Vector2i(3, 3)] }), 1)
		w.apply_command({ "kind": "fill", "x": 0, "y": 0 })
		kit.eq(w.grid.get_h(0, 0), 0, "Solid 填高被拒")
		w.apply_command({ "kind": "fill", "x": 3, "y": 3 })
		kit.eq(w.grid.get_h(3, 3), 0, "Cover 填高被拒")
		w.apply_command({ "kind": "fill", "x": 1, "y": 1 })
		kit.eq(w.grid.get_h(1, 1), 0, "英雄脚下填高被拒")
		w.apply_command({ "kind": "wall", "x": 4, "y": 4 })
		w.apply_command({ "kind": "fill", "x": 4, "y": 4 })
		kit.eq(w.grid.get_h(4, 4), 0, "建筑上填高被拒")
		w.apply_command({ "kind": "spawn", "x": 5, "y": 5, "speed": 1000 })
		w.apply_command({ "kind": "fill", "x": 5, "y": 5 })
		kit.eq(w.grid.get_h(5, 5), 0, "单位格填高被拒")
		w.supply = 10 # 白盒：制造供给不足
		w.apply_command({ "kind": "fill", "x": 6, "y": 6 })
		kit.eq(w.grid.get_h(6, 6), 0, "供给不足填高被拒")
		kit.eq(w.supply, 10, "拒填不扣费")
		w.apply_command({ "kind": "lower", "x": 6, "y": 6 })
		kit.eq(w.grid.get_h(6, 6), 0, "供给不足挖低被拒")
		kit.eq(w.supply, 10, "拒挖不扣费"))

	# ---------------- 单位移动与啃建筑 ----------------

	kit.test("unit-move-timing", func():
		var w := World.new(StubScenario.new(), 1)
		w.apply_command({ "kind": "spawn", "x": 2, "y": 2 })
		_run(w, 3)
		kit.eq(w.units[0]["x"], 1, "tick3 步点：移至 (1,1)")
		kit.eq(w.units[0]["y"], 1, "tick3 步点：移至 (1,1)")
		kit.eq(w.units[0]["traveled"], 1, "路程 +1")
		kit.eq(w.units[0]["stuck_ticks"], 0, "未卡住")
		_run(w, 4)
		kit.eq(w.units[0]["x"], 0, "tick7：贴核西侧")
		kit.eq(w.units[0]["y"], 1, "tick7：贴核西侧")
		kit.eq(w.units[0]["traveled"], 2, "路程 +2")
		kit.eq(w.units[0]["stuck_ticks"], 0, "仍在正常移动")
		_run(w, 4)
		kit.eq(w.units[0]["x"], 0, "贴脸不再移动")
		kit.eq(w.units[0]["y"], 1, "贴脸不再移动")
		kit.eq(w.units[0]["traveled"], 2, "卡住不计路程")
		kit.eq(w.units[0]["stuck_ticks"], 1, "卡住计数")
		kit.eq(w.units[0]["atk_target"], w.core["id"], "锁核为目标")
		kit.eq(w.core["hp"], 1200 - Sim.ENEMIES[Sim.E_SWARM - 1]["damage"], "啃第一口")
		_run(w, 4)
		kit.eq(w.units[0]["stuck_ticks"], 2, "卡住计数续增")
		kit.eq(w.core["hp"], 1200 - Sim.ENEMIES[Sim.E_SWARM - 1]["damage"], "冷却中零伤害")
		_run(w, 4)
		kit.eq(w.units[0]["stuck_ticks"], 3, "卡住计数续增")
		kit.eq(w.core["hp"], 1200 - Sim.ENEMIES[Sim.E_SWARM - 1]["damage"], "冷却中零伤害")
		_run(w, 4)
		kit.eq(w.units[0]["stuck_ticks"], 4, "卡住计数续增")
		kit.eq(w.core["hp"], 1200 - 2 * Sim.ENEMIES[Sim.E_SWARM - 1]["damage"], "冷却后续啃"))

	kit.test("wall-gnawed-through", func():
		var solid := []
		for y in 8:
			for x in 8:
				if y != 1:
					solid.append(Vector2i(x, y))
		var w := World.new(StubScenario.new({ "solid": solid }), 1)
		w.apply_command({ "kind": "wall", "x": 3, "y": 1 })
		var wall: Dictionary = w.buildings[1]
		kit.eq(wall["x"], 3, "墙在走廊里")
		kit.eq(wall["y"], 1, "墙在走廊里")
		w.apply_command({ "kind": "spawn", "x": 6, "y": 1 })
		_run(w, 11)
		kit.eq(w.units[0]["x"], 4, "墙前卡住")
		kit.eq(w.units[0]["traveled"], 2, "走 2 格")
		kit.eq(w.units[0]["atk_target"], wall["id"], "锁墙为目标")
		kit.eq(wall["hp"], 120 - Sim.ENEMIES[Sim.E_SWARM - 1]["damage"], "啃第一口")
		_run(w, 179)
		kit.eq(wall["hp"], 0, "墙被啃穿")
		kit.ok(w.by_cell.get(w.grid.idx(3, 1)) == null, "塌墙清除登记")
		kit.eq(w.grid.at(3, 1), Grid.OPEN, "塌墙即改道")
		kit.eq(w.buildings_lost, 1, "战损计数")
		kit.eq(w.buildings.size(), 1, "塌墙被 compact 清掉，只剩核心"))

	kit.test("core-destroyed-loses", func():
		var w := World.new(StubScenario.new(), 1)
		w.core["hp"] = 5 # 白盒：一口致死
		w.apply_command({ "kind": "spawn", "x": 2, "y": 1 })
		_run(w, 15)
		kit.eq(w.outcome, World.LOST, "核心毁 = 负")
		kit.eq(w.core["hp"], 0, "核心血量归零")
		kit.eq(w.units[0]["atk_target"], w.core["id"], "单位仍锁核（冻结前最后一击）"))

	kit.test("siege-advance", func():
		var solid := []
		for y in 12:
			solid.append(Vector2i(5, y))
		var w := World.new(StubScenario.new({ "size": 12, "solid": solid }), 1)
		w.apply_command({ "kind": "wall", "x": 8, "y": 8 })
		var wall: Dictionary = w.buildings[1]
		w.apply_command({ "kind": "spawn", "x": 10, "y": 10 })
		kit.eq(w.field.dist_at(10, 10), -1, "实心柱隔断：主场不可达")
		_run(w, 3)
		kit.eq(w.units[0]["x"], 9, "沿围攻场推进一格")
		kit.eq(w.units[0]["y"], 9, "沿围攻场推进一格")
		kit.eq(w.units[0]["traveled"], 1, "绕行也计路程")
		_run(w, 4)
		kit.eq(w.units[0]["x"], 8, "贴到墙西侧")
		kit.eq(w.units[0]["y"], 9, "贴到墙西侧")
		kit.eq(w.units[0]["traveled"], 2, "路程 +2")
		kit.eq(wall["hp"], 120, "全围死的建筑不被啃（打分 maxinteger 边角）")
		_run(w, 20)
		kit.eq(w.units[0]["x"], 8, "停走待命")
		kit.eq(w.units[0]["y"], 9, "停走待命")
		kit.eq(wall["hp"], 120, "始终不啃"))

	# ---------------- 英雄 ----------------

	kit.test("hero-move-arrive", func():
		var w := World.new(StubScenario.new(), 1)
		w.apply_command({ "kind": "hero", "x": 5, "y": 1 })
		kit.eq(w.hero["tx"], 5, "点地设目标")
		kit.eq(w.hero["ty"], 1, "点地设目标")
		_run(w, 2)
		kit.eq(w.hero["x"], 2, "tick2 首步（3 tick/格）")
		kit.eq(w.hero["tx"], 5, "未抵达不清目标")
		_run(w, 6)
		kit.eq(w.hero["x"], 4, "tick8 第三步")
		_run(w, 3)
		kit.eq(w.hero["x"], 5, "tick11 抵达")
		kit.eq(w.hero["y"], 1, "tick11 抵达")
		kit.eq(w.hero["tx"], 5, "抵达当拍不清目标（下一拍才清）")
		_run(w, 3)
		kit.eq(w.hero["tx"], -1, "tick14 清目标")
		kit.eq(w.hero["ty"], -1, "tick14 清目标"))

	kit.test("hero-command-guards", func():
		var w := World.new(StubScenario.new(), 1)
		w.apply_command({ "kind": "hero", "x": 0, "y": 0 })
		kit.eq(w.hero["tx"], -1, "不可通行目标被拒")
		w.apply_command({ "kind": "hero", "x": 1, "y": 1 })
		kit.eq(w.hero["tx"], -1, "原地目标被拒")
		w.apply_command({ "kind": "hero", "x": 4, "y": 4 })
		kit.eq(w.hero["tx"], 4, "合法目标接受"))

	kit.test("shock-radius-push-cd", func():
		var w := World.new(StubScenario.new({ "height": [[5, 1, 5]] }), 1)
		w.apply_command({ "kind": "spawn", "x": 2, "y": 1, "speed": 1000 })
		w.apply_command({ "kind": "spawn", "x": 4, "y": 1, "speed": 1000 })
		w.apply_command({ "kind": "spawn", "x": 6, "y": 1, "speed": 1000 })
		w.apply_command({ "kind": "spawn", "x": 1, "y": 1, "speed": 1000 })
		w.apply_command({ "kind": "shock" })
		kit.eq(w.units[0]["x"], 3, "半径内击退 1 格")
		kit.eq(w.units[1]["x"], 4, "落点爬崖被拒（可震下崖不可推上崖）")
		kit.eq(w.units[2]["x"], 6, "半径外不动")
		kit.eq(w.units[3]["x"], 1, "同格不震（d2=0）")
		kit.eq(w.hero["skill_cd"], Sim.HERO["skill_cooldown"], "震荡波置冷却")
		w.apply_command({ "kind": "shock" })
		kit.eq(w.hero["skill_cd"], Sim.HERO["skill_cooldown"], "冷却期重复施放被拒")
		kit.eq(w.units[0]["x"], 3, "冷却期零击退"))

	kit.test("build-blocked-on-hero", func():
		var w := World.new(StubScenario.new(), 1)
		var s := w.supply
		w.apply_command({ "kind": "wall", "x": 1, "y": 1 })
		kit.eq(w.supply, s, "英雄脚下不可建")
		kit.ok(w.building_at(1, 1) == null, "英雄脚下无建筑"))

	# ---------------- 塔火与经济 ----------------

	kit.test("tower-build-countdown", func():
		var w := World.new(StubScenario.new({ "size": 20 }), 1)
		w.apply_command({ "kind": "tower", "x": 4, "y": 4 })
		w.apply_command({ "kind": "spawn", "x": 4, "y": 5, "speed": 1000 })
		_run(w, 60)
		kit.eq(w.buildings[1]["build_left"], 0, "60 tick 竣工")
		kit.eq(w.units[0]["hp"], 30, "施工中不开火")
		_run(w, 1)
		kit.eq(w.units[0]["hp"], 30 - Sim.BUILDINGS[Sim.B_TOWER - 1]["damage"], "tick61 首炮"))

	kit.test("tower-target-selection", func():
		var w := World.new(StubScenario.new({ "size": 20 }), 1)
		w.apply_command({ "kind": "tower", "x": 4, "y": 4 })
		w.apply_command({ "kind": "spawn", "x": 4, "y": 5, "speed": 1000 })
		w.apply_command({ "kind": "spawn", "x": 5, "y": 4, "speed": 1000 })
		_run(w, 61)
		kit.eq(w.units[0]["hp"], 14, "平手打先入表者")
		kit.eq(w.units[1]["hp"], 30, "平手另一只无损"))

	kit.test("tower-range-boundary", func():
		var w := World.new(StubScenario.new({ "size": 20 }), 1)
		w.apply_command({ "kind": "tower", "x": 4, "y": 4 })
		w.apply_command({ "kind": "spawn", "x": 16, "y": 4, "speed": 1000 })
		w.apply_command({ "kind": "spawn", "x": 17, "y": 5, "speed": 1000 })
		_run(w, 61)
		kit.eq(w.units[0]["hp"], 14, "边界内可及")
		kit.eq(w.units[1]["hp"], 30, "边界外不可及"))

	kit.test("convoy-reward", func():
		var w := World.new(StubScenario.new({ "size": 20 }), 1)
		w.apply_command({ "kind": "tower", "x": 4, "y": 4 })
		kit.eq(w.supply, 240, "塔后供给")
		w.apply_command({ "kind": "spawn", "x": 4, "y": 5, "speed": 1000 })
		w.apply_command({ "kind": "spawn", "x": 4, "y": 5, "speed": 1000 })
		w.units[0]["traveled"] = 25 # 白盒：精确观测折算
		w.units[1]["traveled"] = 7
		_run(w, 61)
		kit.eq(w.kills, 0, "首炮仅致伤")
		_run(w, 21)
		kit.eq(w.kills, 1, "第一击杀")
		kit.eq(w.supply, 246, "3 + (25>>3)=3")
		kit.eq(w.convoy_earned, 3, "绕行累计 3")
		_run(w, 21)
		kit.eq(w.kills, 1, "B 仅致伤")
		_run(w, 21)
		kit.eq(w.kills, 2, "第二击杀")
		kit.eq(w.supply, 249, "3 + (7>>3)=0")
		kit.eq(w.convoy_earned, 3, "不足 8 格不凑整"))

	# ---------------- 波次与渗漏 ----------------

	kit.test("emit-wave-placement", func():
		var w := World.new(StubScenario.new(), 1)
		w.emit_wave(1, Sim.E_SWARM, 3)
		kit.eq(w.units.size(), 3, "一波三只")
		kit.eq(w.units[0]["x"], 6, "首只落出生点")
		kit.eq(w.units[0]["y"], 6, "首只落出生点")
		kit.eq(w.units[1]["x"], 5, "次只螺旋找空格")
		kit.eq(w.units[1]["y"], 5, "次只螺旋找空格")
		kit.eq(w.units[2]["x"], 6, "三只继续螺旋")
		kit.eq(w.units[2]["y"], 5, "三只继续螺旋")
		for i in 3:
			kit.eq(w.units[i]["id"], i + 1, "id 连号")
			var sp: int = w.units[i]["speed_ticks"]
			kit.ok(sp == 4 or sp == 5, "波次抖动 speed ∈ {4,5}"))

	kit.test("waves-fire-through-tick", func():
		var w := World.new(StubScenario.new({ "waves": [[5, 1, Sim.E_SWARM, 2]] }), 1)
		_run(w, 5)
		kit.eq(w.units.size(), 2, "波次按表触发"))

	kit.test("trickle-after-plug", func():
		var sc := StubScenario.new({
			"trickle_every": 300,
			"spawn3": Vector2i(6, 6),
			"cover": [Vector2i(6, 5)],
			"plug": Vector2i(6, 5),
		})
		var w := World.new(sc, 1)
		_run(w, 600)
		kit.eq(w.route_opened, false, "未挖插口无渗漏")
		kit.eq(w.units.size(), 0, "未挖插口零单位")
		var w2 := World.new(sc, 1)
		w2.apply_command({ "kind": "dig", "x": 6, "y": 5 })
		kit.eq(w2.route_opened, true, "挖插口开门")
		_run(w2, 300)
		kit.eq(w2.units.size(), 2, "tick300 渗 2 只")
		for u in w2.units:
			kit.ok(absi(u["x"] - 6) <= 3 and absi(u["y"] - 6) <= 3, "渗漏单位落在盆地口周边")
		_run(w2, 300)
		kit.eq(w2.units.size(), 4, "tick600 再渗 2 只"))

	kit.test("wave-scale-pct", func():
		var w := World.new(StubScenario.new({ "wave_scale_pct": 50 }), 1)
		w.apply_command({ "kind": "spawn", "x": 6, "y": 6, "kind_id": Sim.E_SWARM })
		kit.eq(w.units[0]["hp"], 15, "50% 缩放 30→15")
		var w2 := World.new(StubScenario.new({ "wave_scale_pct": 3 }), 1)
		w2.apply_command({ "kind": "spawn", "x": 6, "y": 6, "kind_id": Sim.E_SWARM })
		kit.eq(w2.units[0]["hp"], 1, "3% 缩放触底 1")
		var w3 := World.new(StubScenario.new({ "wave_scale_pct": 50 }), 1)
		w3.apply_command({ "kind": "spawn", "x": 6, "y": 6, "kind_id": Sim.E_BEHEMOTH })
		kit.eq(w3.units[0]["hp"], 120, "50% 缩放 240→120"))

	# ---------------- 终局与冻结 ----------------

	kit.test("judge-win", func():
		var w := World.new(StubScenario.new({ "end_tick": 10 }), 1)
		_run(w, 10)
		kit.eq(w.outcome, World.WON, "终局Tick且场清 = 胜"))

	kit.test("judge-running-with-units", func():
		var w := World.new(StubScenario.new({ "end_tick": 10 }), 1)
		w.apply_command({ "kind": "spawn", "x": 6, "y": 6, "speed": 1000 })
		_run(w, 10)
		kit.eq(w.outcome, World.RUNNING, "还有单位不判胜"))

	kit.test("judge-lose-hard-cap", func():
		var w := World.new(StubScenario.new({ "hard_cap_tick": 10 }), 1)
		w.apply_command({ "kind": "spawn", "x": 6, "y": 6, "speed": 1000 })
		_run(w, 10)
		kit.eq(w.outcome, World.LOST, "超时 = 负"))

	kit.test("frozen-after-outcome", func():
		var w := World.new(StubScenario.new(), 1)
		w.outcome = World.LOST # 白盒：直接终局
		var fp0 := w.fingerprint()
		w.apply_command({ "kind": "wall", "x": 4, "y": 4 })
		w.apply_command({ "kind": "dig", "x": 4, "y": 4 })
		w.apply_command({ "kind": "tower", "x": 5, "y": 5 })
		w.apply_command({ "kind": "hero", "x": 6, "y": 6 })
		w.apply_command({ "kind": "shock" })
		w.apply_command({ "kind": "fill", "x": 3, "y": 3 })
		w.apply_command({ "kind": "spawn", "x": 6, "y": 6 })
		_run(w, 50)
		kit.eq(w.fingerprint(), fp0, "终局后命令与 tick 零副作用"))

	kit.test("unknown-command-nop", func():
		var w := World.new(StubScenario.new(), 1)
		var fp0 := w.fingerprint()
		w.apply_command({ "kind": "nonsense", "x": 3, "y": 3 })
		w.apply_command({ "kind": "", "x": 3, "y": 3 })
		kit.eq(w.fingerprint(), fp0, "未知命令零副作用"))

	# ---------------- 规范编码 ----------------

	kit.test("fingerprint-determinism", func():
		var a := World.new(StubScenario.new(), 777)
		var b := World.new(StubScenario.new(), 777)
		_run(a, 10)
		_run(b, 10)
		kit.eq(a.fingerprint(), b.fingerprint(), "同种子同命令流指纹一致")
		var c := World.new(StubScenario.new(), 778)
		kit.ok(a.fingerprint() != c.fingerprint(), "不同种子指纹分叉（rng 状态入指纹）"))

	kit.test("canonical-schema-bytes", func():
		var w := World.new(StubScenario.new(), 1)
		var b := w.canonical_bytes()
		kit.eq(b.data[0], 0, "STATE_SCHEMA 大端字节 1")
		kit.eq(b.data[1], 0, "STATE_SCHEMA 大端字节 2")
		kit.eq(b.data[2], 0, "STATE_SCHEMA 大端字节 3")
		kit.eq(b.data[3], 5, "STATE_SCHEMA = 5"))

	kit.test("compact-keeps-order", func():
		var w := World.new(StubScenario.new(), 1)
		w.apply_command({ "kind": "spawn", "x": 6, "y": 6, "speed": 1000 })
		w.apply_command({ "kind": "spawn", "x": 5, "y": 5, "speed": 1000 })
		w.apply_command({ "kind": "spawn", "x": 4, "y": 4, "speed": 1000 })
		w.units[1]["hp"] = 0 # 白盒：中间单位阵亡
		_run(w, 1)
		kit.eq(w.units.size(), 2, "阵亡单位被清")
		kit.eq(w.units[0]["id"], 1, "存活顺序 = id 升序")
		kit.eq(w.units[1]["id"], 3, "存活顺序 = id 升序"))

	kit.test("amortized-rebuild-restarts-on-midchange", func():
		# 小预算摊销补场进行中连续改图：旧实现续用旧拓扑已定稿的距离，
		# 完成时却把 field_rev 记成最新 rev（谎报已同步）。用「与全量重建逐格对照」锁死。
		var w := World.new(StubScenario.new({ "size": 12 }), 7, 4)
		w.supply = 999999
		w.try_build(Sim.B_WALL, 7, 7) # 触发摊销（远离核心，不影响近端定稿区）
		w.tick()
		kit.ok(w.rebuilding, "小预算下摊销仍在进行")
		w.try_build(Sim.B_WALL, 1, 0) # 中途改图：墙落进已定稿区（上 tick 已定稿 (0,0)(0,1)(1,0)(1,1)）
		w.tick()
		w.try_build(Sim.B_WALL, 0, 2) # 连续改图
		while w.rebuilding:
			w.tick()
		kit.eq(w.field_rev, w.grid.rev, "完成后 field_rev = 当前 rev")
		kit.eq(w.field.dist_at(1, 0), -1, "中途变墙的格不可达（旧实现残留 10）")
		var ref := FlowField.new(w.grid)
		ref.begin(w.field_goals)
		while not ref.done():
			ref.step(1 << 30)
		var same := true
		for i in ref.dist.size():
			if ref.dist[i] != w.field.dist[i]:
				same = false
				break
		kit.ok(same, "摊销结果与全量重建逐格一致"))
