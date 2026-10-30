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
		kit.eq(w.workers.size(), 0, "开局 0 工人（开局成长改造：购买制）")
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
		var sc := Scenario.new()
		var w := World.new(sc, 1)
		var ore: Vector2i = sc.mid_ore[0]
		w.apply_command({ "kind": "dig", "x": ore.x, "y": ore.y })
		kit.eq(w.supply, Sim.START_SUPPLY, "挖矿不再即时入账（改形 C：矿由工人搬运）")
		kit.eq(w.grid.at(ore.x, ore.y), Grid.OPEN, "矿格挖开")
		kit.eq(int(w.ore_left[w.grid.idx(ore.x, ore.y)]), Sim.ORE_STORE, "矿格余量就绪")
		var sparse := Vector2i(sc.sparse_phase, 17)
		w.apply_command({ "kind": "dig", "x": sparse.x, "y": sparse.y })
		kit.eq(w.supply, Sim.START_SUPPLY, "非矿覆盖无收益")
		kit.eq(w.grid.at(sparse.x, sparse.y), Grid.OPEN, "表土挖开"))

	kit.test("worker-purchase", func():
		var w := World.new(StubScenario.new({ "size": 20 }), 1)
		kit.eq(w.workers.size(), 0, "开局 0 工人")
		w.apply_command(Command.worker())
		kit.eq(w.workers.size(), 1, "买 1 矿工")
		kit.eq(w.supply, Sim.START_SUPPLY - Sim.WORKER_COST, "扣 30")
		kit.ok(w.grid.passable(int(w.workers[0]["x"]), int(w.workers[0]["y"])), "矿工出生在核心邻格通行格")
		w.apply_command(Command.worker())
		kit.eq(w.workers.size(), 2, "再买 1 矿工")
		kit.eq(w.supply, Sim.START_SUPPLY - Sim.WORKER_COST * 2, "再扣 30")
		w.supply = 999 # 白盒：直购到上限
		for _i in Sim.WORKER_CAP - 2:
			w.apply_command(Command.worker())
		kit.eq(w.workers.size(), Sim.WORKER_CAP, "买满上限")
		var fp := w.fingerprint()
		w.apply_command(Command.worker())
		kit.eq(w.workers.size(), Sim.WORKER_CAP, "超上限拒收")
		kit.eq(w.fingerprint(), fp, "超上限零副作用")
		w.supply = Sim.WORKER_COST - 1 # 白盒：差 1 块钱
		w.apply_command(Command.worker())
		kit.eq(w.workers.size(), Sim.WORKER_CAP, "缺钱拒收"))

	kit.test("worker-no-ore-idles", func():
		var w := World.new(StubScenario.new({ "size": 20 }), 1)
		w.apply_command(Command.worker()) # 开局成长改造：先买才有工人
		_run(w, 4) # 连续无矿：后续 tick 也不能拿 target=-1 去取矿格
		kit.eq(w.tick_count, 4, "无矿时世界仍连续推进")
		kit.eq(w.supply, Sim.START_SUPPLY - Sim.WORKER_COST, "无矿不产供给")
		for wk in w.workers:
			kit.eq(int(wk["target"]), -1, "工人保持空目标")
			kit.eq(int(wk["state"]), Sim.W_TO_MINE, "工人原地待命"))

	kit.test("worker-mining-cycle", func():
		# stub 矿格默认生来 OPEN；显式盖 COVER（Vector2i 列表）才真正走到「矿工自动挖开」路径
		var w := World.new(StubScenario.new({ "size": 20, "ore": [[4, 1]], "cover": [Vector2i(4, 1)] }), 1)
		w.apply_command(Command.worker())
		w.apply_command(Command.worker())
		kit.eq(w.grid.at(4, 1), Grid.COVER, "开局矿格覆盖")
		_run(w, 2000) # 足够走完 40 储量的全自动采运（矿工自己挖开，无需玩家 dig）
		kit.eq(w.grid.at(4, 1), Grid.OPEN, "矿工自动挖开了覆盖矿格")
		kit.eq(w.supply, Sim.START_SUPPLY - Sim.WORKER_COST * 2 + Sim.ORE_STORE, "40 储量全数搬运入账（扣 2 矿工钱）")
		kit.eq(int(w.ore_left[w.grid.idx(4, 1)]), 0, "矿格采完枯竭"))

	kit.test("worker-sealed-idles", func():
		var solids := []
		for c in [[16, 15], [14, 15], [15, 14], [15, 16], [16, 14], [16, 16]]:
			solids.append(Vector2i(c[0], c[1]))
		# 矿格显式盖 COVER：未挖开且密封——自动挖开也够不着（六邻全实心，没有站位）
		var w := World.new(StubScenario.new({ "size": 20, "ore": [[15, 15]], "solid": solids, "cover": [Vector2i(15, 15)] }), 1)
		w.apply_command(Command.worker())
		_run(w, 600)
		kit.eq(w.supply, Sim.START_SUPPLY - Sim.WORKER_COST, "密封矿不产供给（白嫖线死亡）")
		kit.eq(w.grid.at(15, 15), Grid.COVER, "矿格保持覆盖（工人没挖开它）")
		kit.eq(int(w.ore_left[w.grid.idx(15, 15)]), Sim.ORE_STORE, "余量原封")
		w.apply_command({ "kind": "dig", "x": 15, "y": 15 }) # 隔空挖开：工人依然进不去
		_run(w, 600)
		kit.eq(w.supply, Sim.START_SUPPLY - Sim.WORKER_COST, "密封矿仍不产供给")
		kit.eq(int(w.ore_left[w.grid.idx(15, 15)]), Sim.ORE_STORE, "余量仍原封"))

	kit.test("worker-no-build-underfoot", func():
		var w := World.new(StubScenario.new({ "size": 20, "ore": [[4, 1]] }), 1)
		w.supply = 999
		w.apply_command(Command.worker())
		var wx: int = int(w.workers[0]["x"])
		var wy: int = int(w.workers[0]["y"])
		w.try_build(Sim.B_WALL, wx, wy)
		kit.ok(w.building_at(wx, wy) == null, "工人脚下不可建造"))

	kit.test("dig-plug-opens-route", func():
		var sc := Scenario.new()
		var w := World.new(sc, 1)
		kit.eq(w.route_opened, false, "开局未开门")
		w.apply_command({ "kind": "dig", "x": sc.basin_plug.x, "y": sc.basin_plug.y })
		kit.eq(w.route_opened, true, "挖插口开门")
		kit.eq(w.supply, Sim.START_SUPPLY, "插口无矿收益"))

	kit.test("dig-rejections", func():
		var sc := Scenario.new()
		var w := World.new(sc, 1)
		var fp0 := w.fingerprint()
		w.apply_command({ "kind": "dig", "x": sc.core.x, "y": sc.core.y })
		w.apply_command({ "kind": "dig", "x": -5, "y": 12 })
		w.apply_command({ "kind": "dig", "x": 99, "y": 99 })
		w.apply_command({ "kind": "dig", "x": sc.hero_spawn.x, "y": sc.hero_spawn.y })
		kit.eq(w.supply, Sim.START_SUPPLY, "拒绝的挖凿零供给副作用")
		kit.eq(w.fingerprint(), fp0, "拒绝的挖凿零指纹副作用"))

	kit.test("wall-build-and-reject", func():
		var sc := Scenario.new()
		var w := World.new(sc, 1)
		var spot := Vector2i(sc.core.x, 20)
		w.apply_command({ "kind": "wall", "x": spot.x, "y": spot.y })
		kit.eq(w.supply, Sim.START_SUPPLY - 5, "首面墙阶梯价 5")
		kit.eq(w.grid.at(spot.x, spot.y), Grid.SOLID, "墙落地挡路")
		kit.ok(w.by_cell.get(w.grid.idx(spot.x, spot.y)) != null, "墙登记 by_cell")
		var s := w.supply
		var ore: Vector2i = sc.mid_ore[0]
		w.apply_command({ "kind": "wall", "x": sc.core.x, "y": sc.core.y })
		w.apply_command({ "kind": "wall", "x": -1, "y": 0 })
		w.apply_command({ "kind": "wall", "x": ore.x, "y": ore.y })
		w.apply_command({ "kind": "wall", "x": spot.x, "y": spot.y })
		kit.eq(w.supply, s, "拒绝的建造零扣费")
		kit.eq(w.buildings.size(), 2, "只有核心 + 一面墙"))

	kit.test("wall-tier-pricing", func():
		var w := World.new(StubScenario.new({ "size": 45 }), 1)
		w.supply = 999999
		var spent := 0
		for i in Sim.WALL_TIER_CHEAP: # 前 20 面：单价 5
			w.try_build(Sim.B_WALL, i + 2, 10)
			spent += Sim.WALL_TIER_CHEAP_COST
		kit.eq(w.live_walls(), 20, "20 面已建")
		kit.eq(w.supply, 999999 - spent, "前 20 面半价")
		kit.eq(w.wall_price(), 10, "第 21 面恢复基准价")
		w.try_build(Sim.B_WALL, Sim.WALL_TIER_CHEAP + 2, 10) # 第 21 面
		var b21: Dictionary = w.buildings[w.buildings.size() - 1]
		kit.eq(int(b21["paid"]), 10, "第 21 面实付 10")
		for i in Sim.WALL_TIER_CAP - Sim.WALL_TIER_CHEAP - 1: # 建满 35 面
			w.try_build(Sim.B_WALL, Sim.WALL_TIER_CHEAP + 3 + i, 10)
		kit.eq(w.live_walls(), Sim.WALL_TIER_CAP, "35 面达上限")
		kit.eq(w.wall_price(), -1, "上限后不可再建")
		var fp := w.fingerprint()
		w.try_build(Sim.B_WALL, 2, 12)
		kit.eq(w.fingerprint(), fp, "超上限建造零副作用")
		kit.eq(w.live_walls(), Sim.WALL_TIER_CAP, "仍是 35 面")
		w.supply = 0
		w.try_remove(Sim.WALL_TIER_CHEAP + 2, 10) # 拆实付 10 的第 21 面
		kit.eq(w.supply, 5, "退款 = 实付 10 的 50%")
		kit.eq(w.live_walls(), Sim.WALL_TIER_CAP - 1, "名额回收")
		kit.eq(w.wall_price(), 10, "回收后可再建（基准价）"))

	kit.test("spawn-and-tick", func():
		var sc := Scenario.new()
		var w := World.new(sc, 1)
		w.apply_command({ "kind": "spawn", "x": sc.spawns[0].x, "y": sc.spawns[0].y })
		kit.eq(w.units.size(), 1, "单位入表")
		kit.eq(w.units[0]["speed_ticks"], Sim.ENEMIES[Sim.E_SWARM - 1]["speed_ticks"], "speed=0 取默认")
		kit.eq(w.units[0]["hp"], 30, "swarm hp")
		kit.eq(w.units[0]["kind"], Sim.E_SWARM, "kind")
		w.apply_command({ "kind": "spawn", "x": sc.core.x, "y": sc.core.y })
		kit.eq(w.units.size(), 1, "阻挡格拒收")
		_run(w, 1)
		kit.eq(w.tick_count, 1, "tick 计数"))

	kit.test("tower-build-halving", func():
		var sc := Scenario.new()
		var w := World.new(sc, 1)
		w.apply_command({ "kind": "tower", "x": sc.core.x, "y": 20 })
		kit.eq(w.buildings[1]["build_left"], 60, "首波前施工减半 120//2")
		w.tick_count = 2400 # 白盒：越过 waves[0][0]（开局成长改造后首波 2400）
		w.supply = 999 # 白盒：60 开局买完第一座塔就没钱了（开局成长改造）
		w.apply_command({ "kind": "tower", "x": sc.core.x + 1, "y": 20 })
		kit.eq(w.buildings[2]["build_left"], 120, "首波后不减半"))

	# ---------------- 经济：拆除退款 ----------------

	kit.test("remove-refund", func():
		var w := World.new(StubScenario.new(), 1)
		w.apply_command({ "kind": "wall", "x": 3, "y": 3 })
		kit.eq(w.supply, Sim.START_SUPPLY - 5, "首面墙阶梯价扣 5")
		w.apply_command({ "kind": "remove", "x": 3, "y": 3 })
		kit.eq(w.supply, Sim.START_SUPPLY - 3, "即时建筑退实付 5 的 50% = 2")
		kit.eq(w.grid.at(3, 3), Grid.OPEN, "拆除后通行")
		kit.ok(w.by_cell.get(w.grid.idx(3, 3)) == null, "by_cell 清除")
		w.apply_command({ "kind": "remove", "x": 3, "y": 3 })
		kit.eq(w.supply, Sim.START_SUPPLY - 3, "重复拆除零副作用")
		w.supply = 999 # 白盒：塔 60 超出 60 开局（开局成长改造），补足再测退款口径
		w.apply_command({ "kind": "tower", "x": 5, "y": 5 })
		kit.eq(w.supply, 939, "塔扣 60")
		w.apply_command({ "kind": "remove", "x": 5, "y": 5 })
		kit.eq(w.supply, 987, "施工中退 80% = 48")
		w.apply_command({ "kind": "remove", "x": 0, "y": 0 })
		kit.eq(w.supply, 987, "核心不可拆")
		kit.ok(w.building_at(0, 0) != null, "核心仍在"))

	# ---------------- 地形改造 ----------------

	kit.test("fill-lower-basic", func():
		var w := World.new(StubScenario.new(), 1)
		w.apply_command({ "kind": "fill", "x": 3, "y": 3 })
		kit.eq(w.grid.get_h(3, 3), 1, "填高 +1")
		kit.eq(w.supply, Sim.START_SUPPLY - 15, "填高费 15")
		w.apply_command({ "kind": "fill", "x": 3, "y": 3 })
		kit.eq(w.grid.get_h(3, 3), 2, "再填 +1")
		kit.eq(w.supply, Sim.START_SUPPLY - 30, "再扣 15")
		w.apply_command({ "kind": "lower", "x": 3, "y": 3 })
		kit.eq(w.grid.get_h(3, 3), 1, "挖低 -1")
		kit.eq(w.supply, Sim.START_SUPPLY - 40, "挖低扣 10"))

	kit.test("fill-hmax-hmin", func():
		var w := World.new(StubScenario.new(), 1)
		w.supply = 999 # 白盒：60 开局不够 75 金填高序列（开局成长改造），补足再测高度边界
		for _i in 5:
			w.apply_command({ "kind": "fill", "x": 3, "y": 3 })
		kit.eq(w.grid.get_h(3, 3), Sim.H_MAX, "连填到 h5")
		kit.eq(w.supply, 924, "5 次填高 75")
		w.apply_command({ "kind": "fill", "x": 3, "y": 3 })
		kit.eq(w.grid.get_h(3, 3), Sim.H_MAX, "顶格再填被拒")
		kit.eq(w.supply, 924, "顶格拒填不扣费")
		for _i in 5:
			w.apply_command({ "kind": "lower", "x": 3, "y": 3 })
		kit.eq(w.grid.get_h(3, 3), 0, "连挖到 h0")
		kit.eq(w.supply, 874, "5 次挖低扣 50")
		w.apply_command({ "kind": "lower", "x": 3, "y": 3 })
		kit.eq(w.grid.get_h(3, 3), -1, "继续挖到 h-1")
		w.apply_command({ "kind": "lower", "x": 3, "y": 3 })
		kit.eq(w.grid.get_h(3, 3), Sim.H_MIN, "连挖到 h-2")
		kit.eq(w.supply, 854, "7 次挖低扣 70")
		w.apply_command({ "kind": "lower", "x": 3, "y": 3 })
		kit.eq(w.grid.get_h(3, 3), Sim.H_MIN, "地板再挖被拒")
		kit.eq(w.supply, 854, "地板拒挖不扣费"))

	kit.test("lower-to-negative-min", func():
		var w := World.new(StubScenario.new(), 1)
		w.apply_command({ "kind": "lower", "x": 3, "y": 3 })
		kit.eq(w.grid.get_h(3, 3), -1, "第一次挖低到 -1")
		w.apply_command({ "kind": "lower", "x": 3, "y": 3 })
		kit.eq(w.grid.get_h(3, 3), -2, "第二次挖低到 -2")
		kit.eq(w.supply, Sim.START_SUPPLY - 20, "两次挖低扣 20")
		w.apply_command({ "kind": "lower", "x": 3, "y": 3 })
		kit.eq(w.grid.get_h(3, 3), -2, "第三次挖低无效")
		kit.eq(w.supply, Sim.START_SUPPLY - 20, "无效挖低不扣费"))

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
		w.supply = 9 # 白盒：制造供给不足（填 15 / 挖 10 都不够）
		w.apply_command({ "kind": "fill", "x": 6, "y": 6 })
		kit.eq(w.grid.get_h(6, 6), 0, "供给不足填高被拒")
		kit.eq(w.supply, 9, "拒填不扣费")
		w.apply_command({ "kind": "lower", "x": 6, "y": 6 })
		kit.eq(w.grid.get_h(6, 6), 0, "供给不足挖低被拒")
		kit.eq(w.supply, 9, "拒挖不扣费"))

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
		kit.eq(w.units[0]["x"], 1, "tick7：贴核东侧（六边与核心 (0,0) 正邻）")
		kit.eq(w.units[0]["y"], 0, "tick7：贴核东侧")
		kit.eq(w.units[0]["traveled"], 2, "路程 +2")
		kit.eq(w.units[0]["stuck_ticks"], 0, "仍在正常移动")
		_run(w, 4)
		kit.eq(w.units[0]["x"], 1, "贴脸不再移动")
		kit.eq(w.units[0]["y"], 0, "贴脸不再移动")
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
		kit.eq(w.units[0]["x"], 9, "绕向墙侧 (9,8)")
		kit.eq(w.units[0]["y"], 8, "绕向墙侧 (9,8)")
		kit.eq(w.units[0]["traveled"], 2, "路程 +2")
		kit.eq(wall["hp"], 120, "全围死的建筑不被啃（打分 maxinteger 边角）")
		_run(w, 20)
		kit.eq(w.units[0]["x"], 9, "停走待命（贴墙侧 (9,8)，围攻场无处可降）")
		kit.eq(w.units[0]["y"], 8, "停走待命（贴墙侧 (9,8)，围攻场无处可降）")
		kit.eq(wall["hp"], 120, "始终不啃"))

	kit.test("climb-wait-after-ascent", func():
		# 单宽走廊 y=1：在 (4,1) 造 1 级坡，单位从 (5,1) 爬上去后必须后摇 2 tick。
		var solid := []
		for y in 8:
			for x in 8:
				if y != 1:
					solid.append(Vector2i(x, y))
		var w := World.new(StubScenario.new({ "size": 8, "solid": solid }), 1)
		w.grid.set_h(4, 1, 1)
		w.apply_command({ "kind": "spawn", "x": 5, "y": 1, "speed": 1 })
		w.tick() # tick1：补场 → 移动跨坡
		kit.eq(w.units[0]["x"], 4, "tick1 跨坡进入 h1 格")
		kit.eq(w.units[0]["climb_wait"], Sim.CLIMB_EXTRA_TICKS, "爬 1 级等待 2 tick")
		w.tick()
		kit.eq(w.units[0]["x"], 4, "等待第 1 tick 不动")
		kit.eq(w.units[0]["climb_wait"], 1, "等待计数递减")
		w.tick()
		kit.eq(w.units[0]["x"], 4, "等待第 2 tick 不动")
		kit.eq(w.units[0]["climb_wait"], 0, "等待计数归零")
		w.tick()
		kit.eq(w.units[0]["x"], 3, "后摇结束后继续移动"))

	kit.test("swarm-climbs-two-behemoth-detours", func():
		# 走廊 y=1 在 (3,1) 有 2 级坡；y=3 是绕行长廊（x<=6），两端经 (6,2)/(1,2) 连通。
		var solid := []
		for y in 8:
			for x in 8:
				var keep := (y == 1) or (y == 3 and x <= 6) or (x == 6 and y == 2) or (x == 1 and y == 2)
				if not keep:
					solid.append(Vector2i(x, y))
		var w := World.new(StubScenario.new({ "size": 8, "solid": solid }), 1)
		w.grid.set_h(3, 1, 2)
		kit.ok(w.field_for(Sim.E_SWARM) == w.field, "虫群用普通场（climb_max=2）")
		kit.ok(w.field_for(Sim.E_BEHEMOTH) == w.field_heavy, "蛮兽用 heavy 场（climb_max=1）")
		w.apply_command({ "kind": "spawn", "x": 6, "y": 1, "speed": 4, "kind_id": Sim.E_SWARM })
		_run(w, 40)
		kit.eq(w.units[0]["x"], 0, "虫群爬 2 级坡后到达核心侧")
		kit.eq(w.units[0]["y"], 1, "虫群沿走廊抵达")
		kit.ok(w.units[0]["stuck_ticks"] > 0 and w.units[0]["atk_target"] == w.core["id"], "虫群贴核开啃（未卡死）")

		var w2 := World.new(StubScenario.new({ "size": 8, "solid": solid }), 1)
		w2.grid.set_h(3, 1, 2)
		w2.apply_command({ "kind": "spawn", "x": 6, "y": 1, "speed": 4, "kind_id": Sim.E_BEHEMOTH })
		var crossed_cliff := false
		var took_detour := false
		for _i in 60:
			w2.tick()
			var u: Dictionary = w2.units[0]
			if u["x"] == 3 and u["y"] == 1:
				crossed_cliff = true
			if u["y"] == 3:
				took_detour = true
		kit.ok(not crossed_cliff, "蛮兽不进入 2 级坡格")
		kit.ok(took_detour, "蛮兽绕行至 y=3 长廊")
		kit.ok(w2.units[0]["stuck_ticks"] > 0 and w2.units[0]["atk_target"] == w2.core["id"], "蛮兽最终贴核开啃（未卡死）"))

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
		kit.eq(w.units[0]["x"], 3, "第二格被单位占据：只退 1 格")
		kit.eq(w.units[1]["x"], 4, "落点爬崖被拒（可震下崖不可推上崖）")
		kit.eq(w.units[2]["x"], 6, "半径外不动")
		kit.eq(w.units[3]["x"], 1, "同格不震（d2=0）")
		kit.eq(w.units[0]["stun"], Sim.STUN_TICKS, "命中即眩晕")
		kit.eq(w.units[2]["stun"], 0, "半径外不眩晕")
		kit.eq(w.hero["skill_cd"], Sim.HERO["skill_cooldown"], "震荡波置冷却")
		w.apply_command({ "kind": "shock" })
		kit.eq(w.hero["skill_cd"], Sim.HERO["skill_cooldown"], "冷却期重复施放被拒")
		kit.eq(w.units[0]["x"], 3, "冷却期零击退"))

	kit.test("shock-push-two-steps", func():
		var w := World.new(StubScenario.new(), 1)
		w.apply_command({ "kind": "spawn", "x": 3, "y": 1, "speed": 1000 })
		w.apply_command({ "kind": "shock" })
		kit.eq(w.units[0]["x"], 5, "无阻挡时击退 2 格")
		kit.eq(w.units[0]["traveled"], 0, "击退不计路程")
		# 眩晕完全冻结：不移动、不啃、攻击冷却也不走
		w.units[0]["atk_cd"] = 7 # 白盒
		w.units[0]["stun"] = 2 # 白盒
		var fx: int = w.units[0]["x"]
		var fy: int = w.units[0]["y"]
		_run(w, 2)
		kit.eq(w.units[0]["stun"], 0, "2 tick 后眩晕解除")
		kit.eq(w.units[0]["atk_cd"], 7, "冻结期 atk_cd 不走")
		kit.eq(w.units[0]["x"], fx, "冻结期不动"))

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
		kit.eq(w.supply, Sim.START_SUPPLY - 60, "塔后供给")
		w.apply_command({ "kind": "spawn", "x": 4, "y": 5, "speed": 1000 })
		w.apply_command({ "kind": "spawn", "x": 4, "y": 5, "speed": 1000 })
		# 白盒：站桩单位死位即出生位；裸图基线不含塔、主位剩余绕塔 ⇒ 二者差 = 塔造成的绕行
		var base0: int = w.units[0]["bare_dist"]
		var rest0: int = w.field_for(Sim.E_SWARM).dist_at(4, 5)
		w.units[0]["traveled"] = 25 # 白盒：精确观测折算
		w.units[1]["traveled"] = 7
		_run(w, 61)
		kit.eq(w.kills, 0, "首炮仅致伤")
		_run(w, 21)
		kit.eq(w.kills, 1, "第一击杀")
		var b0: int = mini(Lua64.lshr(25 * 10 + rest0 - base0, 3), 6)
		kit.eq(w.supply, Sim.START_SUPPLY - 60 + 3 + b0, "3 + 有效绕行折算")
		kit.eq(w.convoy_earned, b0, "绕行累计")
		_run(w, 21)
		kit.eq(w.kills, 1, "B 仅致伤")
		_run(w, 21)
		kit.eq(w.kills, 2, "第二击杀")
		var b1: int = mini(Lua64.lshr(7 * 10 + rest0 - base0, 3), 6)
		kit.eq(w.supply, Sim.START_SUPPLY - 60 + 6 + b0 + b1, "B 基础+有效绕行")
		kit.eq(w.convoy_earned, b0 + b1, "绕行累计累加"))

	kit.test("effdetour-semantics", func():
		var w := World.new(StubScenario.new({ "size": 20 }), 1)
		w.apply_command({ "kind": "spawn", "x": 4, "y": 5, "speed": 1000 })
		var u: Dictionary = w.units[0]
		kit.eq(w.effdetour(u), 0, "未改图的站桩怪绕行为 0")
		u["bare_dist"] = -1 # 白盒：模拟开门陷阱流（出生口裸图不可达）
		kit.eq(w.effdetour(u), 0, "出生口不可达记 0")
		var rest0: int = w.field_for(Sim.E_SWARM).dist_at(4, 5)
		u["bare_dist"] = rest0 - 50
		kit.eq(w.effdetour(u), 50, "基线少 5 格 = 绕行 5 格当量")
		u["bare_dist"] = rest0 - 10
		kit.eq(w.bounty_bonus(u), 1, "绕行 1 格当量 10>>3=1 未触顶")
		u["traveled"] = 30
		kit.eq(w.bounty_bonus(u), 6, "(300+10)>>3=38 触顶 2×3=6")
		kit.eq(w.bounty_of(u), 9, "总额 = 基础 3 + 加成 6"))

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
		kit.eq(b.data[3], Canon.STATE_SCHEMA, "STATE_SCHEMA = %d（随 sim/canon.gd 单源走）" % Canon.STATE_SCHEMA))

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
		var w := World.new(StubScenario.new({ "size": 12, "hero_spawn": Vector2i(3, 3) }), 7, 4)
		w.supply = 999999
		w.try_build(Sim.B_WALL, 7, 7) # 触发摊销（远离核心，不影响近端定稿区）
		w.tick()
		kit.ok(w.rebuilding, "小预算下摊销仍在进行")
		w.try_build(Sim.B_WALL, 1, 1) # 中途改图：墙落进已定稿区（上 tick 已定稿 (0,0)(0,1)(1,0)(1,1)；(1,0)/(0,1) 工人位、英雄已挪 (3,3)）
		w.tick()
		w.try_build(Sim.B_WALL, 0, 2) # 连续改图
		while w.rebuilding:
			w.tick()
		kit.eq(w.field_rev, w.grid.rev, "完成后 field_rev = 当前 rev")
		kit.eq(w.field.dist_at(1, 1), -1, "中途变墙的格不可达（旧实现残留 10）")
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
