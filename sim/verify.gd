class_name Verify
extends RefCounted

# 验证闸宿主（GDScript 移植）：黄金回放 + 确定性浸泡 + 不变式看门狗 + 终局冻结自证。
# 口径照搬 reroute/scripts/sim/verify.lua：每道量化闸带正对照与负对照。

## 黄金回放命令脚本模板（tick, kind, x, y, kind_id）：命令在"该 tick 开始前"生效。
## 2026-10-16 世界生成：坐标不再钉死，全部按 Scenario 锚点（核心/咽喉中心/脊行/矿表/插口）重排；
## 条目数与 tick 序列、同 tick 组内相对序与手搓夹具版一一对应：
##   放墙漏斗收窄双咽喉、塔火链、挖矿经济（中场全挖 + 盆地 9/12，末角矿留作非法命令）、
##   开门陷阱（1000t 挖插口 → 第三出怪口渗漏）、拆除、英雄点地/震荡波，以及非法命令（零副作用进指纹口径）。
## 咽喉几何约定：谷口宽 3（中心 ±1），咽喉相关行相对各口行 c.y（T0 恒 == ridge_y）——
## 漏斗墙行 = c.y+3（屏障带下行之南），走廊卡口行 = c.y+1，北侧塔行 c.y-1/c.y-2/c.y-3。
static func script_for(sc: Scenario) -> Array:
	var cx := sc.core.x
	var ry := sc.ridge_y
	var cw: Vector2i = sc.chokes[0]
	var ce: Vector2i = sc.chokes[1]
	var wx: int = cw.x
	var wy: int = cw.y # 西咽喉口行
	var ex: int = ce.x
	var ey: int = ce.y # 东咽喉口行
	var my: int = sc.mid_ore[0].y # 中场矿带行
	var ore := sc.mid_ore # x 主序：cx-2..cx+2
	var bo := sc.basin_ore # x 主序：3 列 × 4 行 = 12 格；末行（idx 3/7/11）留作非法命令
	var plug := sc.basin_plug
	return [
		[20, "dig", ore[0].x, ore[0].y], [20, "dig", ore[1].x, ore[1].y], [20, "dig", bo[2].x, bo[2].y], [20, "dig", bo[6].x, bo[6].y],
		[30, "dig", ore[2].x, ore[2].y], [30, "dig", ore[3].x, ore[3].y], [30, "dig", ore[4].x, ore[4].y], [30, "wall", cx, sc.core.y],
		[31, "hero", cx, sc.core.y], [32, "hero", plug.x, plug.y], [33, "shock", 0, 0], [34, "fill", wx - 2, wy],
		[35, "lower", cx, sc.core.y], [40, "dig", bo[10].x, bo[10].y], [40, "dig", bo[1].x, bo[1].y], [40, "dig", bo[5].x, bo[5].y],
		[40, "dig", bo[9].x, bo[9].y], [50, "dig", bo[0].x, bo[0].y], [50, "dig", bo[4].x, bo[4].y], [50, "dig", bo[8].x, bo[8].y],
		[50, "dig", cx, sc.core.y], [60, "wall", wx - 2, wy + 3], [60, "wall", wx - 1, wy + 3], [60, "wall", wx + 1, wy + 3],
		[60, "wall", wx + 2, wy + 3], [70, "wall", ex - 2, ey + 3], [70, "wall", ex - 1, ey + 3], [70, "wall", ex + 1, ey + 3],
		[70, "wall", ex + 2, ey + 3], [70, "wall", -5, 12], [80, "tower", wx - 1, wy - 2], [90, "tower", wx + 1, wy - 2],
		[90, "dig", 99, 99], [100, "tower", wx - 2, wy - 1], [110, "tower", ex - 1, ey - 2], [120, "tower", ex + 1, ey - 2],
		[130, "tower", ex - 2, ey - 1], [140, "wall", wx - 1, wy + 1], [140, "wall", wx + 1, wy + 1], [140, "wall", ex - 1, ey + 1],
		[140, "wall", ex + 1, ey + 1], [160, "hero", cx, 14], [220, "hero", cx - 4, my], [300, "tower", cx - 4, 12],
		[460, "dig", ore[0].x, ore[0].y], [461, "wall", bo[11].x, bo[11].y], [462, "fill", bo[11].x, bo[11].y], [500, "tower", cx + 3, 12],
		[1000, "tower", wx - 1, wy - 3], [1000, "dig", plug.x, plug.y], [1050, "tower", wx + 1, wy - 3], [1100, "tower", ex - 1, ey - 3],
		[1150, "fill", cx - 4, ry - 1], [1160, "fill", cx - 4, ry - 1], [1170, "fill", cx - 4, ry - 1], [1180, "fill", cx - 4, ry - 1],
		[1190, "lower", cx - 4, ry - 1], [1195, "fill", cx - 4, ry - 1], [2000, "hero", wx, wy - 3], [2600, "tower", cx - 3, 9],
		[2700, "tower", cx + 3, 9], [2900, "shock", 0, 0], [3400, "tower", cx - 1, 10], [3600, "tower", cx, 9],
		[4000, "wall", cx - 3, ry - 1], [4020, "wall", cx - 2, ry - 1], [4100, "tower", wx - 2, wy - 2], [4300, "tower", ex + 2, ey - 2],
		[4400, "tower", cx - 6, 14], [4500, "tower", cx + 6, 14], [4520, "shock", 0, 0], [4600, "tower", cx + 2, 8],
		[4620, "hero", cx, 12], [4700, "tower", cx - 2, 8], [4720, "wall", cx - 3, 11], [4740, "wall", cx + 3, 11],
		[4800, "shock", 0, 0], [5000, "remove", wx + 2, wy + 3], [5200, "tower", cx - 4, 10], [5400, "shock", 0, 0],
		[5600, "remove", ex - 1, ey + 1],
	]


## 按声明 tick 稳定排序命令副本（同 tick 保持原相对序）。
## 命令语义 = 「在声明 tick 开始前生效」，与数组排列顺序无关；黄金表必须满足此序（见 金表有序性单测）。
static func sorted_commands(commands: Array) -> Array:
	var dec := []
	for i in commands.size():
		dec.append([commands[i][0], i, commands[i]])
	dec.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	var out := []
	for d in dec:
		out.append(d[2])
	return out


## 不变式看门狗：单位不在阻挡格、供给不为负、核心存活到终局、英雄在通行格、路程不越界。
static func check_invariants(world: World) -> String:
	var g := world.grid
	for u in world.units:
		if not g.passable(u["x"], u["y"]):
			return "不变式1破例：单位 %d 位于阻挡格 (%d,%d) tick=%d" % [u["id"], u["x"], u["y"], world.tick_count]
	if world.supply < 0:
		return "不变式2破例：供给为负 %d tick=%d" % [world.supply, world.tick_count]
	if world.outcome == World.RUNNING and (world.core.is_empty() or world.core["hp"] <= 0):
		return "不变式3破例：核心已毁但局未终 tick=%d" % world.tick_count
	if not world.hero.is_empty() and not g.passable(world.hero["x"], world.hero["y"]):
		return "不变式4破例：英雄位于阻挡格 (%d,%d) tick=%d" % [world.hero["x"], world.hero["y"], world.tick_count]
	for u in world.units:
		if u["traveled"] < 0 or u["traveled"] > world.tick_count:
			return "不变式5破例：单位 %d 路程 %d 越界 tick=%d" % [u["id"], u["traveled"], world.tick_count]
	for u in world.units:
		var bd := int(u.get("bare_dist", -1))
		if bd < -1 or bd > 4096:
			return "不变式6破例：单位 %d 裸图基线 %d 越界 tick=%d" % [u["id"], bd, world.tick_count]
	for b in world.buildings:
		var pd := int(b.get("paid", 0))
		if pd < 0 or pd > 999:
			return "不变式7破例：建筑 %d 实付价 %d 越界 tick=%d" % [int(b["id"]), pd, world.tick_count]
	for u in world.units:
		var st := int(u.get("stun", 0))
		if st < 0 or st > Sim.STUN_TICKS:
			return "不变式8破例：单位 %d 眩晕 %d 越界 tick=%d" % [u["id"], st, world.tick_count]
	return ""


## 单局推进到 hard_cap 并每 sample_every tick 采样指纹。返回 [samples, err]。
static func run_world(sc: Scenario, seed: int, commands: Array, sample_every: int, invariant_check: bool) -> Array:
	commands = sorted_commands(commands) # 防守：输入乱序时也按声明 tick 生效
	var world := World.new(sc, seed)
	var samples := []
	var ci := 0
	var cmd_fail := ""
	while world.tick_count < sc.hard_cap_tick and world.outcome == World.RUNNING:
		while ci < commands.size() and commands[ci][0] <= world.tick_count + 1:
			var c: Array = commands[ci]
			var cmd := { "kind": c[1], "x": c[2], "y": c[3] }
			if c.size() > 4:
				cmd["kind_id"] = c[4]
			world.apply_command(cmd)
			ci += 1
		world.tick()
		if world.tick_count % sample_every == 0:
			samples.append([world.tick_count, "%08x" % world.fingerprint()])
		if invariant_check and world.tick_count % 100 == 0:
			var err := check_invariants(world)
			if err != "":
				return [null, err]
	while ci < commands.size(): # 剩余命令全部喂入（终局冻结：必须零副作用）
		var c2: Array = commands[ci]
		var cmd2 := { "kind": c2[1], "x": c2[2], "y": c2[3] }
		if c2.size() > 4:
			cmd2["kind_id"] = c2[4]
		world.apply_command(cmd2)
		ci += 1
	# 终局冻结自证：再喂 200 tick + 20 条建造命令，指纹必须纹丝不动
	var fp0 := world.fingerprint()
	for _i in 200:
		world.tick()
	for _i in 20:
		world.apply_command({ "kind": "wall", "x": sc.core.x, "y": sc.core.y })
	if world.fingerprint() != fp0:
		return [null, "终局冻结破例：Outcome 后状态仍在变 tick=%d" % world.tick_count]
	if world.outcome == World.RUNNING:
		return [null, "终止看门狗：跑到 hard_cap=%d 仍未收口" % sc.hard_cap_tick]
	return [samples, cmd_fail]
