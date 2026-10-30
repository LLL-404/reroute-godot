class_name Verify
extends RefCounted

# 验证闸宿主（GDScript 移植）：黄金回放 + 确定性浸泡 + 不变式看门狗 + 终局冻结自证。
# 口径照搬 reroute/scripts/sim/verify.lua：每道量化闸带正对照与负对照。

## 黄金回放命令脚本模板（tick, kind, x, y, kind_id）：命令在"该 tick 开始前"生效。
## 2026-10-28 第八次重录（开局成长改造：START_SUPPLY=60 / WORKER_COST=30 / 开局 0 工人 /
## 波表整体 +2340：首波 2400、末波 7420、end_tick=8740、hard_cap=11140）：
##   旧脚本按 300 开局 + 旧波表排班全部作废，按新经济重排（战报口径「稳但穷」）：
##   · 经济：t20 挖开中场 5 矿 + 2 矿工（第 3+ 矿工亏本：矿总量恒 680，多买净收更少）。
##     矿工重挑目标以 grid.rev 变化为闸（_worker_to_mine 的 pick_rev 门），安静期停摆——
##     用表土行 y=34（x%9==相位，非矿不产钱）的免费 dig 做节拍器（~200t 一挖）维持流水。
##     t1500（首波前）挖盆地插口（开门陷阱）并玩家隔空挖开全部 12 盆地矿：矿工全程
##     不挖（波间零 rev bump），只采运——盆地产线 +480 与每 300t 2 虫群渗怪税
##     （bare_dist=-1 恒无赏金）从 ~t2200 起补贴建塔荒期。
##   · 防御：塔全部落在怪流 lane 带（裸图路径 ±3~4，含螺旋出生散布）之外 ≥3 格、
##     用射程 12 的覆盖 blob 罩住路径分段——任何压 lane 的建筑都会让散布怪多走
##     1~2 格（击杀吃绕行赏金，破坏「稳但穷」口径）。分层：W1 西口 + C1 合流走廊
##     （波前基本盘）→ W2 西口二塔（2950）→ C2/E0 双罩合流段 + E1 东口（3620/3960，
##     赶 4040 波）→ W3/C3/E2（5010 批）→ W4/E3（5450 批）→ E4/W5/E5/G（6700 批，
##     末波前收口）→ W6/E6/W7/E7（8350 收尾批）。同批同 tick 单次重算——建塔撞上
##     怪流会让未定稿怪朝最近建筑围攻走 1~2 步吃绕行赏金，故每批都对齐「南区空窗」。
##     每塔 2 次尝试（拒建零副作用）。门侧墙只作 scenario 样本（lane 带外），不做漏斗收窄。
##   · 英雄驻核心门原地 (63,16)，shock 两发均在走廊空窗（只可能命中无赏金渗怪）。
##   · 非法命令样本：界外（wall/dig/tower）+ 永不挖开的 COVER（表土 (2,34) 不在节拍器表；
##     盆地矿 (9,110) t170 时仍 COVER）+ 拆核心 —— 发令时刻均非法（运行实测复核）。
##   · 结局：tick=8870 场清 WON（杀 250、convoy 1、核心余 664、供给余 242、零建筑
##     损失；采样 400..8800 共 22 条，见 golden_baseline 第十三录注；双种子复核
##     20261004 WON@8890 / convoy 5，均 ≤5 达标）。
static func script_for(sc: Scenario) -> Array:
	var cx := sc.core.x
	var cy := sc.core.y
	var cw: Vector2i = sc.chokes[0]
	var ce: Vector2i = sc.chokes[1]
	var wx: int = cw.x
	var wy: int = cw.y # 西咽喉口行
	var ex: int = ce.x
	var ey: int = ce.y # 东咽喉口行
	var out := []
	# ---- 开局：挖开中场 5 矿（工人免挖直采）+ 2 矿工（60=30×2）----
	for o in sc.mid_ore:
		out.append([20, "dig", o.x, o.y])
	out.append([20, "worker", 0, 0])
	out.append([20, "worker", 0, 0])
	# ---- 采矿节拍器：表土行免费 dig（非矿、不产钱），每 ~200t bump grid.rev，
	#      让存金归来的矿工立刻重挑目标（否则安静期停摆到下次建造）----
	var ticklers := [[250, 11], [450, 20], [650, 29], [850, 38], [1050, 47], [1250, 56], [1450, 65], [1650, 74], [1850, 83]]
	for tl in ticklers:
		out.append([tl[0], "dig", tl[1], 34])
	# ---- 非法命令样本（发令时刻非法：界外 / 永不挖开的 COVER / 拆核心）----
	out.append([70, "wall", -5, 12])
	out.append([90, "dig", 200, 200])
	out.append([110, "tower", 99, 300])
	out.append([130, "fill", 2, 34]) # 表土 COVER（刻意不在节拍器表内，永不挖开）
	out.append([150, "wall", 2, 34])
	out.append([170, "wall", sc.basin_ore[9].x, sc.basin_ore[9].y]) # 盆地矿 COVER（t2000 才开门）
	# ---- 门侧布墙样本（避开门侧怪流 lane ≥3 格；前 20 面 5 金阶梯价）----
	# 不做漏斗收窄：任何压 lane 的建筑都会让螺旋出生的散布怪多走 1~2 格（击杀吃绕行
	# 赏金，破坏「稳但穷」口径）——墙只作 scenario 样本，放 lane 带外的空地。
	out.append([1150, "wall", 32, 85])
	out.append([1150, "wall", 33, 85])
	out.append([1160, "wall", 94, 85])
	out.append([1160, "wall", 95, 85])
	# ---- 开门陷阱：挖盆地插口（t1500，首波前）+ 玩家隔空挖开全部 12 盆地矿（t1510-1521）。
	#      玩家代挖是绕行赏金归零的关键：矿工进场只采不挖（否则矿工的自动挖开会
	#      在波间随机 bump grid.rev → 流场重算未定稿区里的怪朝建筑围攻走 1~2 步
	#      → 击杀吃绕行赏金）。插口渗怪每 300t 2 虫群（bare_dist=-1 恒无赏金），
	#      t1600 起渗入、被走廊塔顺路清掉（+3/只渗怪收入）。----
	out.append([1500, "dig", sc.basin_plug.x, sc.basin_plug.y])
	for i in sc.basin_ore.size():
		out.append([1510 + i, "dig", sc.basin_ore[i].x, sc.basin_ore[i].y])
	# ---- 塔链：全部落在怪流 lane 带（裸图路径 ±3~4）之外 ≥3 格、靠射程 12 的覆盖 blob
	#      罩住路径分段——不压 lane 就不会给散布怪加绕行（convoy≈0）。
	#      建 塔 时 序 对 齐 南 区 空 窗 ：任何 set_cell 都会让流场重算（~10t 未定稿区），
	#      未定稿区里的怪会朝建筑围攻走 1~2 步（traveled+1~2 → 击杀吃绕行赏金）——
	#      故所有建塔尝试都排在「波次出怪 +400t 南区疏散完」之后的空窗内，
	#      重试也落在下一空窗。每塔 2 次尝试（供给抖动对冲）。
	# [尝试 tick, x, y]（默认图 seed 20261003；y82-84 为屏障带不可建，已避开）
	# 时序三纪律（绕行赏金归零的实证口径）：
	#   a) 建塔 tick 避开「主路怪在图上」的时段（set_cell → 流场重算 ~10t 未定稿，
	#      未定稿怪朝最近建筑围攻走 1~2 步 → traveled+1~2 → 击杀吃绕行赏金）；
	#      例外：怪已进走廊/核心邻域（bucket 低，1~2t 内定稿）或图上只剩无赏金渗怪；
	#   b) 同一批塔并在同一 tick（只重算一次），把未定稿窗压到一段；
	#   c) 5010 批（波3 蛮兽 5008 前后已被走廊塔清掉、波4 未出）与 6700 批
	#      （波5 蛮兽已进走廊）按此落位；8350 批在末波清场后。
	var towers := [
		[1250, 33, 80], [1500, 33, 80], # W1 西门口（罩门行+北向出口段）
		[1500, 71, 18], [1750, 71, 18], # C1 合流走廊东侧（兼罩核心六邻格，清驻怪）
		[2950, 45, 81], [3060, 45, 81], # W2 西门口二塔（波1 清场后空窗）
		[3620, 59, 14], [3960, 59, 14], # C2 核心门西侧（波2 清场后空窗）
		[3620, 73, 24], [3960, 73, 24], # E0 合流口东侧（与 C1 双罩合流段——散布种子怪团用）
		[3960, 93, 80], [4450, 93, 80], # E1 东门口（4040 波东半进圈前开火）
		[5010, 48, 77], [5450, 48, 77], # W3 西出口段（5010 批：波3 蛮兽已清、波4 未出）
		[5010, 60, 12], [5450, 60, 12], # C3 核心门北侧（走廊第三塔）
		[5010, 81, 81], [5450, 81, 81], # E2 东出口段
		[5450, 52, 70], [6700, 52, 70], # W4 西中场（5450 批与 E3 同 tick 单次重算）
		[5450, 77, 78], [6700, 77, 78], # E3 东中场
		[6700, 91, 67], [8350, 91, 67], # E4 东中场二（6700 批：波5 蛮兽已进走廊低 bucket）
		[6700, 58, 60], [8350, 58, 60], # W5 西中场二
		[6700, 91, 55], [8350, 91, 55], # E5 东中场三
		[6700, 62, 13], [8350, 62, 13], # G 核心门卫塔（主怪流单列走 (63,13)，不压 lane）
		[8350, 63, 51], # W6 西中场三（末波清场后收尾批）
		[8350, 87, 44], # E6 东近场
		[8350, 67, 42], # W7 西近场
		[8350, 82, 34], # E7 东近场
	]
	for tw in towers:
		out.append([tw[0], "tower", tw[1], tw[2]])
	# ---- 英雄与震荡波：驻核心门原地（(63,16)）；两发均在走廊空窗（只可能命中无赏金渗怪）----
	out.append([2350, "hero", cx, cy + 3]) # (63,15) 原地样本
	out.append([2400, "hero", cx, cy + 4]) # 走回 (63,16)
	out.append([2500, "shock", 0, 0])
	out.append([3050, "shock", 0, 0])
	# ---- 地形改造样本（远离双路径与盆地线的空地，填高后挖低还原；8350 批与收尾塔同窗）----
	out.append([8350, "fill", cx - 33, cy + 48]) # (30,60)
	out.append([8360, "lower", cx - 33, cy + 48])
	# ---- 收官：拆一面西门侧墙（拆除/退款路径样本；门口已无怪，改道无影响）----
	out.append([8700, "remove", 32, 85])
	out.append([8600, "remove", cx, cy]) # 非法样本：核心不可拆
	# 按声明 tick 稳定排序返回（金表有序性单测的前提；同 tick 保持上方相对序）
	var dec := []
	for i in out.size():
		dec.append([out[i][0], i, out[i]])
	dec.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	var sorted := []
	for d in dec:
		sorted.append(d[2])
	return sorted


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
		if bd < -1 or bd > world.grid.w * world.grid.h:
			return "不变式6破例：单位 %d 裸图基线 %d 越界 tick=%d" % [u["id"], bd, world.tick_count]
	for b in world.buildings:
		var pd := int(b.get("paid", 0))
		if pd < 0 or pd > 999:
			return "不变式7破例：建筑 %d 实付价 %d 越界 tick=%d" % [int(b["id"]), pd, world.tick_count]
	for u in world.units:
		var st := int(u.get("stun", 0))
		if st < 0 or st > Sim.STUN_TICKS:
			return "不变式8破例：单位 %d 眩晕 %d 越界 tick=%d" % [u["id"], st, world.tick_count]
	for wk in world.workers:
		if not g.passable(int(wk["x"]), int(wk["y"])):
			return "不变式9破例：工人 %d 位于阻挡格 (%d,%d) tick=%d" % [wk["id"], wk["x"], wk["y"], world.tick_count]
		var cg := int(wk["carrying"])
		if cg < 0 or cg > Sim.WORKER_LOAD:
			return "不变式9破例：工人 %d 载量 %d 越界 tick=%d" % [wk["id"], cg, world.tick_count]
	for i in world.sc.ore_cells.size():
		var oc: Vector2i = world.sc.ore_cells[i]
		var ol := int(world.ore_left.get(world.grid.idx(oc.x, oc.y), -1))
		if ol < 0 or ol > Sim.ORE_STORE:
			return "不变式9破例：矿格 %d 余量 %d 越界 tick=%d" % [i, ol, world.tick_count]
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
			var cmd := Command.make(c[1], c[2], c[3]) # 剧本 kind 是动态值，走通用工厂
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
		var cmd2 := Command.make(c2[1], c2[2], c2[3])
		if c2.size() > 4:
			cmd2["kind_id"] = c2[4]
		world.apply_command(cmd2)
		ci += 1
	# 终局冻结自证：再喂 200 tick + 20 条建造命令，指纹必须纹丝不动
	var fp0 := world.fingerprint()
	for _i in 200:
		world.tick()
	for _i in 20:
		world.apply_command(Command.wall(sc.core.x, sc.core.y))
	if world.fingerprint() != fp0:
		return [null, "终局冻结破例：Outcome 后状态仍在变 tick=%d" % world.tick_count]
	if world.outcome == World.RUNNING:
		return [null, "终止看门狗：跑到 hard_cap=%d 仍未收口" % sc.hard_cap_tick]
	return [samples, cmd_fail]
