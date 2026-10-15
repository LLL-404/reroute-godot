class_name Verify
extends RefCounted

# 验证闸宿主（GDScript 移植）：黄金回放 + 确定性浸泡 + 不变式看门狗 + 终局冻结自证。
# 口径照搬 reroute/scripts/sim/verify.lua：每道量化闸带正对照与负对照。

# 黄金回放命令脚本（tick, kind, x, y, kind_id）：命令在"该 tick 开始前"生效。
# 覆盖放墙改道（漏斗墙收窄双咽喉）、塔火、挖矿经济、开门陷阱、拆除、英雄点地移动与震荡波，
# 以及非法命令（零副作用也进指纹口径）。
# 2026-10-16 世界重做：坐标随 64² 地图整体平移（中心系 x+8、y 按区带 +10/+16，盆地系 y+16），
# 条目数与 tick 序列不变；行为等价性由二次重录后的黄金基线锁定。
const SCRIPT_COMMANDS := [
	[20, "dig", 30, 20], [20, "dig", 31, 20], [20, "dig", 4, 58], [20, "dig", 5, 58],
	[30, "dig", 32, 20], [30, "dig", 33, 20], [30, "dig", 34, 20], [30, "wall", 32, 6],
	[31, "hero", 32, 6], [32, "hero", 5, 53], [33, "shock", 0, 0], [34, "fill", 17, 40],
	[35, "lower", 32, 6], [40, "dig", 6, 58], [40, "dig", 4, 57], [40, "dig", 5, 57],
	[40, "dig", 6, 57], [50, "dig", 4, 56], [50, "dig", 5, 56], [50, "dig", 6, 56],
	[50, "dig", 32, 6], [60, "wall", 17, 43], [60, "wall", 18, 43], [60, "wall", 20, 43],
	[60, "wall", 21, 43], [70, "wall", 42, 43], [70, "wall", 43, 43], [70, "wall", 45, 43],
	[70, "wall", 46, 43], [70, "wall", -5, 12], [80, "tower", 18, 38], [90, "tower", 20, 38],
	[90, "dig", 99, 99], [100, "tower", 17, 39], [110, "tower", 43, 38], [120, "tower", 45, 38],
	[130, "tower", 42, 39], [140, "wall", 18, 41], [140, "wall", 20, 41], [140, "wall", 43, 41],
	[140, "wall", 45, 41], [160, "hero", 32, 14], [220, "hero", 28, 20], [300, "tower", 28, 12],
	[460, "dig", 30, 20], [461, "wall", 5, 59], [462, "fill", 5, 59], [500, "tower", 35, 12],
	[1000, "tower", 18, 37], [1000, "dig", 5, 53], [1050, "tower", 20, 37], [1100, "tower", 43, 37],
	[1150, "fill", 28, 39], [1160, "fill", 28, 39], [1170, "fill", 28, 39], [1180, "fill", 28, 39],
	[1190, "lower", 28, 39], [1195, "fill", 28, 39], [2000, "hero", 19, 37], [2600, "tower", 29, 9],
	[2700, "tower", 35, 9], [2900, "shock", 0, 0], [3400, "tower", 31, 10], [3600, "tower", 32, 9],
	[4000, "wall", 29, 39], [4020, "wall", 30, 39], [4100, "tower", 17, 38], [4300, "tower", 46, 38],
	[4400, "tower", 26, 14], [4500, "tower", 38, 14], [4520, "shock", 0, 0], [4600, "tower", 34, 8],
	[4620, "hero", 32, 12], [4700, "tower", 30, 8], [4720, "wall", 29, 11], [4740, "wall", 35, 11],
	[4800, "shock", 0, 0], [5000, "remove", 21, 43], [5200, "tower", 28, 10], [5400, "shock", 0, 0],
	[5600, "remove", 43, 41],
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
		world.apply_command({ "kind": "wall", "x": 30, "y": 44 })
	if world.fingerprint() != fp0:
		return [null, "终局冻结破例：Outcome 后状态仍在变 tick=%d" % world.tick_count]
	if world.outcome == World.RUNNING:
		return [null, "终止看门狗：跑到 hard_cap=%d 仍未收口" % sc.hard_cap_tick]
	return [samples, cmd_fail]
