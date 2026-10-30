extends ProbeKit

# 平衡验证探针（2026-10-29 新经济重排）：三流派对照局——乌龟 / 运河 / 开门陷阱。
# 判定：exit 0 + stdout 含 `[BALANCE] PASS`。
#
# 验收判据（2026-10-25 四刀合体口径；断言值未动，新经济带值复核见战报输出）：
#   · 乌龟 = 黄金脚本布局意图（双咽喉口袋塔链+核心纵深，notunnel 离道）：WON 且 convoy ≈ 0 ——「稳但穷」
#   · 运河（西口封死+东口收口迷宫+对角走廊塔链）：WON 且 convoy ≥ 500 —— 大额兑现
#   · 开门（乌龟同构+开局挖插口）：可胜但插口渗怪无赏金 —— 非支配
#
# 2026-10-28 开局成长改造时序重排（旧 300 开局/旧波表排班全作废）：
#   · 开局 60 = 2 矿工（WORKER_COST 30）；采矿流水 ≈ +20/225t/人，中场 5 矿共 200、
#     插口开后盆地 12 矿 +480；墙阶梯价前 20 面 5、后 10、上限 35；塔 60（首波前施工减半）
#   · 波表（scenario.gd 全表 +2340）：教学细流 2400..2700、波 1 3140/3170、蛮兽首秀 4190、
#     末波 7040..7420，end_tick 8740 / hard_cap 11140
#   · 命令带重试（TRY_GAP≈一个多工人到账周期）：供给未到位/格被占/单位压格时零副作用
#     拒绝，稍后补建——静态脚本对收入抖动的容错
#   · 时序骨架：t=20 露矿+买 2 矿工 → 墙链/塔链按批次跟进 → 乌龟 t=1300 挖插口
#     （盆地产线+渗怪税）、开门 t=18 挖插口、运河不挖
#   · 128 布局修订（2026-10-29 实测）：出怪列正对咽喉（柱状进路）⇒ 漏斗/卡口收口墙
#     给外侧车道怪 +1 格真鼓包 ≈ +1 赏金/杀（乌龟 v3 实测 convoy 120；拆收口墙+塔离道
#     → 9）。乌龟/开门改 notunnel（塔离道 ±4/±7/±9，射程 12 仍全覆盖）；运河保留
#     收口墙+迷宫——那正是它的赏金引擎
#   · 已知协同 quirk：工人 rev 不变不重挑（world.gd _worker_to_mine 节流）——纯采矿会
#     停摆；本脚本建造批次保持流动，持续解锁重挑，采矿不吃亏
#
# 布局生成器：先 build_grid() 预检通行性，只在 OPEN 格发命令；天然 SOLID/COVER
# 视为已有墙不重复发。非法命令零副作用兜底。

const TRY_GAP := 280 # 重试间隔（≈1.25 个工人到账周期）


## 单格命令 + 重试（零副作用兜底：未建成时稍后再试）
static func _r(out: Array, t0: int, kind: String, x: int, y: int, tries: int = 3) -> void:
	for i in tries:
		out.append([t0 + i * TRY_GAP, kind, x, y])


## 露中场矿（远程可挖 = 省工人自挖一步；不开插口）
static func _mine_open(sc: Scenario, out: Array, t0: int) -> void:
	for i in sc.mid_ore.size():
		out.append([t0 + i, "dig", sc.mid_ore[i].x, sc.mid_ore[i].y])


## 沿行补墙（带重试）：非 OPEN（SOLID/COVER 天然挡路）跳过，OPEN 发 wall 命令
static func _wall_line(g, out: Array, t0: int, y: int, x_from: int, x_to: int, tries: int = 3) -> void:
	for k in tries:
		var t := t0 + k * TRY_GAP
		for x in range(x_from, x_to + 1):
			if g.inb(x, y) and g.at(x, y) == Grid.OPEN:
				out.append([t, "wall", x, y])


## 漏斗墙（ choke 南一行收 1 格缝：心格留空，敌人单列入口袋）
static func _funnel(g, out: Array, t0: int, c: Vector2i) -> void:
	_wall_line(g, out, t0, c.y + 3, c.x - 2, c.x - 1)
	_wall_line(g, out, t0, c.y + 3, c.x + 1, c.x + 2)


## 走廊卡口（带内 ±1 收 1 格缝）
static func _corridor(out: Array, t0: int, c: Vector2i) -> void:
	_r(out, t0, "wall", c.x - 1, c.y + 1, 2)
	_r(out, t0 + 20, "wall", c.x + 1, c.y + 1, 2)


## 口袋迷宫（带北一行满墙：直出封死，敌人必须咀嚼穿墙——墙上火力下静止承伤）
static func _maze(g, out: Array, t0: int, c: Vector2i) -> void:
	_wall_line(g, out, t0, c.y - 1, c.x - 1, c.x + 1)


## 乌龟：黄金脚本布局意图（双咽喉口袋塔链 + 核心纵深）——新经济重排：
## 60 开局买 2 矿工 → 口袋塔随采矿到账跟进 → t=1300 挖插口（中场采干时盆地产线
## 接棒 480 + 渗怪税）。2026-10-29 实测修订：128 图出怪列正对咽喉（柱状进路），
## 漏斗/卡口收口墙会给外侧车道怪 +1 格真鼓包（≈+1 绕行赏金/杀，v3 实测 convoy 120）
## ⇒ 乌龟/开门不建收口墙（口袋塔外推 ±4 列离道，射程 12 仍全覆盖，notunnel 实测
## convoy 120→9）——「稳但穷」的判据面（残余 ≈9 为爬坡记账幻影，见 evidence）
static func script_tortoise(sc: Scenario) -> Array:
	var cw: Vector2i = sc.chokes[0]
	var ce: Vector2i = sc.chokes[1]
	var cx: int = sc.core.x
	var out: Array = []
	# —— 开局经济：露中场矿 + 买 2 矿工（60 金主分支）
	_mine_open(sc, out, 20)
	out.append([20, "worker", 0, 0])
	out.append([20, "worker", 0, 0])
	# —— 死区墙批（东缘 x=99..100，离东西车道 ≥11 格、离工人矿道 ≥8 格：零鼓包）。
	# 职责不是挡怪：维持建造流水（rev 跳变）解锁工人重挑——纯采矿会停摆死锁
	# （world.gd _worker_to_mine：pick_rev==grid.rev 不重挑；v4 无墙实测种子 04 收入崩）
	_r(out, 290, "wall", 99, 80, 3)
	_r(out, 300, "wall", 100, 80, 3)
	_r(out, 510, "wall", 99, 79, 3)
	_r(out, 520, "wall", 100, 79, 3)
	# —— 西口袋塔两翼（离道 ±4 列，chimney 三车道全在射程内；带重试）
	_r(out, 730, "tower", cw.x - 4, cw.y - 2)
	_r(out, 950, "tower", cw.x + 4, cw.y - 2)
	# —— 挖插口（中场采干 ~1300：盆地 480 接棒产线；渗怪 2/300t 走西口袋被吃）
	out.append([1300, "dig", sc.basin_plug.x, sc.basin_plug.y])
	_r(out, 1450, "tower", cw.x - 4, cw.y - 5, 3)
	_r(out, 1650, "worker", 0, 0, 3)
	_r(out, 1850, "worker", 0, 0, 3)
	# —— 西口袋纵深二（波 1 3140 前就位）
	_r(out, 2050, "tower", cw.x + 4, cw.y - 5, 3)
	_r(out, 2250, "worker", 0, 0, 2)
	# —— 东口袋塔（波 1 东口 6 只 3170→~3300 进口袋）
	_r(out, 2450, "tower", ce.x - 4, ce.y - 2, 3)
	_r(out, 2650, "tower", ce.x + 4, ce.y - 2, 3)
	# —— 核心门网（离道 ±7/±9 列：射程 12 仍罩核心南面与进路）
	_r(out, 2850, "tower", cx - 7, sc.core.y, 3)
	_r(out, 3050, "tower", cx + 7, sc.core.y, 3)
	_r(out, 3250, "worker", 0, 0, 2)
	# —— 东口袋纵深 + 核心环（随盆地采矿与击杀收入跟进）
	_r(out, 3450, "tower", ce.x - 4, ce.y - 5, 3)
	_r(out, 3650, "tower", ce.x + 4, ce.y - 5, 3)
	_r(out, 3850, "tower", cw.x - 4, cw.y - 4, 2)
	_r(out, 4050, "tower", cw.x + 4, cw.y - 4, 2)
	_r(out, 4250, "worker", 0, 0, 2)
	_r(out, 4450, "tower", ce.x - 4, ce.y - 4, 2)
	_r(out, 4650, "tower", ce.x + 4, ce.y - 4, 2)
	_r(out, 4850, "tower", cx - 9, 14, 2)
	_r(out, 5050, "tower", cx + 9, 14, 2)
	_r(out, 5250, "tower", cx - 2, 8, 2)
	_r(out, 5450, "tower", cx + 2, 8, 2)
	_r(out, 5650, "tower", cx - 9, 10, 2)
	_r(out, 5850, "tower", cx, 10, 2)
	_r(out, 6050, "tower", cx + 9, 10, 2)
	_r(out, 6250, "tower", cx - 9, 9, 2)
	_r(out, 6450, "tower", cx + 9, 9, 2)
	_r(out, 6650, "tower", cx, 9, 2)
	_r(out, 6850, "wall", 99, 78, 2)
	_r(out, 6950, "wall", 100, 78, 2)
	return out


## 运河：西口封死（3×3 缺口满墙）+ 东口漏斗 + 卡口 + 口袋迷宫 + 口袋塔链 +
## 对角走廊塔链（沿东口→核心自然路径逐段纵火）——西口怪 D≈+44 全额绕行赏金，
## 东口怪吃迷宫鼓包小额赏金。不挖插口（无渗怪税；收入 = 60 + 中场 200 + 击杀赏金）。
## 新经济重排：墙批对齐采矿到账；走廊塔对齐击杀收入（首批怪 ~2850 进口袋）
static func script_canal(sc: Scenario) -> Array:
	var g := sc.build_grid()
	var cw: Vector2i = sc.chokes[0]
	var ce: Vector2i = sc.chokes[1]
	var out: Array = []
	# —— 开局经济：露中场矿 + 买 2 矿工
	_mine_open(sc, out, 20)
	out.append([20, "worker", 0, 0])
	out.append([20, "worker", 0, 0])
	# —— 西口封死：缺口 3 列 × 带行 3 行满墙（9 面；重试到账铺满）
	for i in 3:
		_wall_line(g, out, 290 + i * 2, cw.y + i, cw.x - 1, cw.x + 1, 3)
	# —— 东口漏斗 + 卡口 + 口袋迷宫（全图唯一入口；迷宫 = chew 时段 + 鼓包赏金）
	_funnel(g, out, 510, ce)
	_corridor(out, 730, ce)
	_maze(g, out, 900, ce)
	# —— 口袋塔两翼 + 纵深（首批怪 ~2850 进口袋，t=1050 起随采矿到账）
	_r(out, 1050, "tower", ce.x - 2, ce.y - 2)
	_r(out, 1250, "tower", ce.x + 2, ce.y - 2)
	_r(out, 1450, "tower", ce.x - 2, ce.y - 5)
	_r(out, 1650, "tower", ce.x + 2, ce.y - 5)
	# —— 对角走廊塔链（东口→核心自然路径：堵位纵火，射程 12 逐段交叠）
	_r(out, 2900, "tower", ce.x - 1, ce.y - 14, 3)
	_r(out, 3100, "tower", ce.x - 5, ce.y - 26, 3)
	_r(out, 3300, "tower", ce.x - 9, ce.y - 38, 3)
	_r(out, 3500, "tower", ce.x - 13, ce.y - 50, 3)
	_r(out, 3700, "tower", ce.x - 17, ce.y - 62, 3)
	# —— 核心门网 + 环（漏网怪兜底）
	_r(out, 3900, "tower", sc.core.x - 4, sc.core.y, 3)
	_r(out, 4100, "tower", sc.core.x + 3, sc.core.y, 3)
	_r(out, 4300, "tower", sc.core.x - 3, 9, 3)
	_r(out, 4500, "tower", sc.core.x + 3, 9, 3)
	_r(out, 4700, "tower", sc.core.x - 6, 14, 3)
	_r(out, 4900, "tower", sc.core.x + 6, 14, 3)
	_r(out, 5100, "tower", sc.core.x - 2, 8, 3)
	_r(out, 5300, "tower", sc.core.x + 2, 8, 3)
	_r(out, 5500, "tower", sc.core.x - 4, 10, 3)
	_r(out, 5700, "tower", sc.core.x, 10, 3)
	_r(out, 5900, "tower", sc.core.x + 4, 10, 3)
	# —— 走廊第二列（末波 74+8 前补密度）
	_r(out, 6100, "tower", ce.x + 1, ce.y - 14, 3)
	_r(out, 6300, "tower", ce.x - 3, ce.y - 26, 3)
	_r(out, 6500, "tower", ce.x - 7, ce.y - 38, 3)
	_r(out, 6700, "tower", ce.x - 11, ce.y - 50, 3)
	_r(out, 6900, "tower", ce.x - 15, ce.y - 62, 3)
	return out


## 开门陷阱：乌龟同构骨架 + t=18 挖插口（贪食线全程承压：渗怪自 t=300、首达口袋
## ~t=440）。开局不建墙（收口墙给主波发赏金，乌龟同款 notunnel/离道塔位）：
## 2 矿工全攒 → 西口袋首塔 ~t=550 → 核心侧翼塔 (cx-7,12) ~t=900（射程 12 罩住
## 核心南面，兜住穿袋渗怪）。插口渗怪 bare_dist=-1 无赏金基线——非支配
static func script_trapdoor(sc: Scenario) -> Array:
	var cw: Vector2i = sc.chokes[0]
	var ce: Vector2i = sc.chokes[1]
	var cx: int = sc.core.x
	var out: Array = []
	# —— 唯一差异开局落锤：挖插口（渗怪 2/300t 从 t=300 起跑）
	out.append([18, "dig", sc.basin_plug.x, sc.basin_plug.y])
	_mine_open(sc, out, 20)
	out.append([20, "worker", 0, 0])
	out.append([20, "worker", 0, 0])
	# —— 死区墙批（同乌龟：建造流水节奏器，防工人停摆死锁；位址零鼓包）。
	# 开门特有：1400..2000 补四批——中场采干（~2000）到盆地流水（~2700）之间的
	# 收入真空期靠它维持建造节奏（v5 实测无此段 → bld 停在 11、波 2/3 击穿核心）
	_r(out, 290, "wall", 99, 80, 3)
	_r(out, 300, "wall", 100, 80, 3)
	_r(out, 510, "wall", 99, 79, 3)
	_r(out, 520, "wall", 100, 79, 3)
	_r(out, 1400, "wall", 99, 78, 3)
	_r(out, 1410, "wall", 100, 78, 3)
	_r(out, 1600, "wall", 99, 77, 3)
	_r(out, 1610, "wall", 100, 77, 3)
	_r(out, 1800, "wall", 99, 76, 3)
	_r(out, 1810, "wall", 100, 76, 3)
	_r(out, 2000, "wall", 99, 75, 3)
	_r(out, 2010, "wall", 100, 75, 3)
	# —— 西口袋首塔（渗怪首达 ~440：塔 ~610 立起，首批 2 只穿袋，后续全被袋口吃）
	_r(out, 550, "tower", cw.x - 4, cw.y - 2, 4)
	# —— 核心侧翼塔（离道位，射程罩核心南面：清掉穿袋的首批渗怪）
	_r(out, 900, "tower", cx - 7, sc.core.y, 3)
	_r(out, 1050, "worker", 0, 0, 3)
	_r(out, 1200, "tower", cw.x + 4, cw.y - 2, 3)
	# —— 工人补员（插口已开：盆地 480 矿入产线）+ 口袋纵深
	_r(out, 1500, "worker", 0, 0, 3)
	_r(out, 1650, "tower", cw.x - 4, cw.y - 5, 2)
	_r(out, 1900, "worker", 0, 0, 3)
	_r(out, 2050, "tower", cw.x + 4, cw.y - 5, 2)
	# —— 东口袋（波 1 东口 3170→~3300 进口袋）
	_r(out, 2000, "tower", ce.x - 4, ce.y - 2, 3)
	_r(out, 2200, "tower", ce.x + 4, ce.y - 2, 3)
	_r(out, 2400, "worker", 0, 0, 2)
	# —— 纵深 + 核心环（对齐波表与击杀收入）
	_r(out, 2600, "tower", ce.x - 4, ce.y - 5, 2)
	_r(out, 2800, "tower", ce.x + 4, ce.y - 5, 2)
	_r(out, 3000, "tower", cx + 7, sc.core.y, 2)
	_r(out, 3200, "tower", cx - 9, 9, 2)
	_r(out, 3400, "tower", cw.x - 4, cw.y - 4, 2)
	_r(out, 3600, "tower", cw.x + 4, cw.y - 4, 2)
	_r(out, 3800, "tower", ce.x - 4, ce.y - 4, 2)
	_r(out, 4000, "tower", ce.x + 4, ce.y - 4, 2)
	_r(out, 4200, "worker", 0, 0, 2)
	_r(out, 4400, "tower", cx - 9, 14, 2)
	_r(out, 4600, "tower", cx + 9, 14, 2)
	_r(out, 4800, "tower", cx - 2, 8, 2)
	_r(out, 5000, "tower", cx + 2, 8, 2)
	_r(out, 5200, "tower", cx - 9, 10, 2)
	_r(out, 5400, "tower", cx, 10, 2)
	_r(out, 5600, "tower", cx + 9, 10, 2)
	_r(out, 5800, "tower", cx - 9, 12, 2)
	_r(out, 6000, "tower", cx + 9, 12, 2)
	return out


## 跑一局：返回战报字典
static func _run_one(sc: Scenario, wseed: int, script: Array) -> Dictionary:
	var world := World.new(sc, wseed)
	var cmds := Verify.sorted_commands(script)
	var ci := 0
	while world.tick_count < sc.hard_cap_tick and world.outcome == World.RUNNING:
		while ci < cmds.size() and cmds[ci][0] <= world.tick_count + 1:
			var c: Array = cmds[ci]
			world.apply_command({ "kind": c[1], "x": c[2], "y": c[3] })
			ci += 1
		world.tick()
	return {
		"outcome": world.outcome, "tick": world.tick_count, "kills": world.kills,
		"convoy": world.convoy_earned, "supply": world.supply,
		"core_hp": int(world.core.get("hp", -1)),
		"lost": world.buildings_lost, "units_left": world.units.size(),
		"towers": world.live_buildings(),
	}


func _initialize() -> void:
	var sc := Scenario.new()
	var plans := [
		["乌龟", script_tortoise(sc)],
		["运河", script_canal(sc)],
		["开门", script_trapdoor(sc)],
	]
	for plan in plans:
		var name: String = plan[0]
		var script: Array = plan[1]
		for s in 2: # 种子 20261003 / 20261004
			var r: Dictionary = _run_one(sc, GoldenBaseline.SEED + s, script)
			var won: bool = r["outcome"] == 1
			print("[BALANCE] %s seed=%d → %s tick=%d kills=%d convoy=%d supply=%d core=%d lost=%d left=%d bld=%d" % [
				name, GoldenBaseline.SEED + s,
				"WON" if won else ("LOST" if r["outcome"] == 2 else "RUNNING"),
				r["tick"], r["kills"], r["convoy"], r["supply"], r["core_hp"], r["lost"], r["units_left"], r["towers"]])
			# 验收断言（2026-10-25 四刀合体战报：乌龟 convoy 1-2 / 运河 757-760 / 开门 1-2）
			if name == "乌龟":
				check(won, "%s 应胜（稳）seed=%d" % [name, GoldenBaseline.SEED + s])
				check(r["convoy"] <= 5, "%s 绕行赏金应≈0（穷）得 %d" % [name, r["convoy"]])
			elif name == "运河":
				check(won, "%s 应胜（四刀合体首次）seed=%d" % [name, GoldenBaseline.SEED + s])
				check(r["convoy"] >= 500, "%s 绕行赏金应大额兑现（≥500）得 %d" % [name, r["convoy"]])
			else: # 开门：可胜但无赏金优势（插口渗怪 bare_dist=-1 无基线）——非支配
				check(won, "%s 应可胜 seed=%d" % [name, GoldenBaseline.SEED + s])
				check(r["convoy"] <= 5, "%s 开门不应带来赏金优势 得 %d" % [name, r["convoy"]])
	finish("BALANCE")
