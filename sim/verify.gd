class_name Verify
extends RefCounted

# 验证闸宿主（GDScript 移植）：黄金回放 + 确定性浸泡 + 不变式看门狗 + 终局冻结自证。
# 口径照搬 reroute/scripts/sim/verify.lua：每道量化闸带正对照与负对照。

# 黄金回放命令脚本（tick, kind, x, y, kind_id）：命令在"该 tick 开始前"生效。
# 覆盖放墙改道（漏斗墙收窄双咽喉）、塔火、挖矿经济、开门陷阱、拆除、英雄点地移动与震荡波，
# 以及非法命令（零副作用也进指纹口径）。
const SCRIPT_COMMANDS := [
	[20, "dig", 22, 20], [20, "dig", 23, 20], [20, "dig", 4, 42], [20, "dig", 5, 42],
	[30, "dig", 24, 20], [30, "dig", 25, 20], [30, "dig", 26, 20], [30, "wall", 24, 6],
	[31, "hero", 24, 6], [32, "hero", 5, 37], [33, "shock", 0, 0], [34, "fill", 9, 30],
	[35, "lower", 24, 6], [40, "dig", 6, 42], [40, "dig", 4, 41], [40, "dig", 5, 41],
	[40, "dig", 6, 41], [50, "dig", 4, 40], [50, "dig", 5, 40], [50, "dig", 6, 40],
	[50, "dig", 24, 6], [60, "wall", 9, 33], [60, "wall", 10, 33], [60, "wall", 12, 33],
	[60, "wall", 13, 33], [70, "wall", 34, 33], [70, "wall", 35, 33], [70, "wall", 37, 33],
	[70, "wall", 38, 33], [70, "wall", -5, 12], [80, "tower", 10, 28], [90, "tower", 12, 28],
	[90, "dig", 99, 99], [100, "tower", 9, 29], [110, "tower", 35, 28], [120, "tower", 37, 28],
	[130, "tower", 34, 29], [140, "wall", 10, 31], [140, "wall", 12, 31], [140, "wall", 35, 31],
	[140, "wall", 37, 31], [160, "hero", 24, 14], [220, "hero", 20, 20], [300, "tower", 20, 12],
	[460, "dig", 22, 20], [461, "wall", 5, 43], [462, "fill", 5, 43], [500, "tower", 27, 12],
	[1000, "tower", 10, 27], [1000, "dig", 5, 37], [1050, "tower", 12, 27], [1100, "tower", 35, 27],
	[1150, "fill", 20, 29], [1160, "fill", 20, 29], [1170, "fill", 20, 29], [1180, "fill", 20, 29],
	[1190, "lower", 20, 29], [1195, "fill", 20, 29], [2000, "hero", 11, 27], [2600, "tower", 21, 9],
	[2700, "tower", 27, 9], [2900, "shock", 0, 0], [3400, "tower", 23, 10], [3600, "tower", 24, 9],
	[4000, "wall", 21, 29], [4020, "wall", 22, 29], [4100, "tower", 9, 28], [4300, "tower", 38, 28],
	[4400, "tower", 18, 14], [4500, "tower", 30, 14], [4520, "shock", 0, 0], [4600, "tower", 26, 8],
	[4620, "hero", 24, 12], [4700, "tower", 22, 8], [4720, "wall", 21, 11], [4740, "wall", 27, 11],
	[4800, "shock", 0, 0], [5000, "remove", 13, 33], [5200, "tower", 20, 10], [5400, "shock", 0, 0],
	[5600, "remove", 35, 31],
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
