extends ProbeKit

# 平衡验证探针（2026-10-25 四刀合体）：三流派对照局——乌龟 / 运河 / 开门陷阱。
# 判定：exit 0 + stdout 含 `[BALANCE] PASS`。
#
# 验收判据（四刀药效）：
#   · 乌龟 = 黄金脚本布局（双咽喉漏斗+塔链+纵深，Verify.script_for 同一份）：
#     WON 且 convoy ≈ 0 ——「稳但穷」（黄金基线第十录实证 convoy=1）
#   · 运河（西口封死+横墙截断东进路+绕行通道塔链）：WON 且 convoy > 0 —— 正式 sim 史上首次
#   · 开门（挖盆地插口+乌龟同构漏斗塔链）：可胜但插口渗怪无赏金 —— 非支配
#
# 布局生成器：先 build_grid() 预检通行性，只在 OPEN 格发命令；天然 SOLID/COVER
# 视为已有墙不重复发。非法命令零副作用兜底。


static func _mine_cmds(sc: Scenario, t0: int) -> Array:
	# 中场 5 矿 + 盆地 12 矿（远程可挖，不开插口）——「高级白嫖线」
	var out := []
	var i := 0
	for o in sc.mid_ore:
		out.append([t0 + i, "dig", o.x, o.y])
		i += 1
	for o in sc.basin_ore:
		out.append([t0 + i, "dig", o.x, o.y])
		i += 1
	return out


## 沿行补墙：非 OPEN（SOLID/COVER 天然挡路）跳过，OPEN 发 wall 命令；返回 [cmds, 墙数]
static func _wall_line(g, out: Array, t0: int, y: int, x_from: int, x_to: int) -> int:
	var n := 0
	var t := t0
	for x in range(x_from, x_to + 1):
		if not g.inb(x, y):
			continue
		if g.at(x, y) == Grid.OPEN:
			out.append([t, "wall", x, y])
			t += 2
			n += 1
	return n


## 沿行布塔：只放 OPEN 格（且不与已放墙/塔同行同格），间隔 step；返回 [cmds, 塔数]
static func _tower_line(g, out: Array, t0: int, y: int, x_from: int, x_to: int, step: int) -> int:
	var n := 0
	var t := t0
	var x := x_from
	while x <= x_to:
		if g.inb(x, y) and g.at(x, y) == Grid.OPEN:
			out.append([t, "tower", x, y])
			t += 40
			n += 1
		x += step
	return n


## 乌龟：黄金脚本布局（双咽喉漏斗 + 塔链 + 核心纵深）——probe_golden 验证过 WON@6400
## （核心余 1080、杀 236、convoy 1）；此处独立跑战报判据，锁「稳但穷」。
static func script_tortoise(sc: Scenario) -> Array:
	return Verify.script_for(sc)


## 运河：西口封死（防啃穿配双塔）；东口大开；两道横墙 Z 字截断——怪被迫
## 南走廊西行 → 绕行口北上 → 二道墙前东折 → 再北上，effdetour 全程兑现；
## 走廊塔链 tick 400 起建（怪 ~830t 进走廊，竣工必须早于敌到）
static func script_canal(sc: Scenario) -> Array:
	var g := sc.build_grid()
	var cw: Vector2i = sc.chokes[0]
	var ce: Vector2i = sc.chokes[1]
	var out: Array = _mine_cmds(sc, 20)
	# 西口封死 + 墙后双塔（tick 220 建，第一波前竣工）
	_wall_line(g, out, 100, cw.y, cw.x - 1, cw.x + 1)
	var tw := _tower_line(g, out, 220, cw.y - 1, cw.x - 2, cw.x + 2, 2)
	if tw == 0:
		_tower_line(g, out, 220, cw.y - 2, cw.x - 2, cw.x + 2, 2)
	# 第一道横墙：东咽喉以北 y=ce.y-8，从 cx+8 到东边界（西端留绕行口）
	var wy2: int = ce.y - 8
	_wall_line(g, out, 320, wy2, sc.core.x + 8, sc.w - 2)
	# 第二道 Z 字墙：绕行口以北 10 行，从 cx-4 向东到 cx+9（东端留口）——逼怪东折再北上
	_wall_line(g, out, 380, wy2 - 10, sc.core.x - 4, sc.core.x + 9)
	# 走廊塔链（横墙南 1-2 格，间隔 4 控预算）：tick 400 起，赶在怪进走廊前竣工
	_tower_line(g, out, 400, wy2 + 1, sc.core.x + 10, sc.w - 4, 4)
	_tower_line(g, out, 520, wy2 + 2, sc.core.x + 12, sc.w - 4, 4)
	# 绕行口与 Z 字折返通道塔
	_tower_line(g, out, 700, wy2 - 1, sc.core.x + 5, sc.core.x + 9, 2)
	# 核心门网（早建：漏网怪最后的拦截线）
	_tower_line(g, out, 500, 10, sc.core.x - 2, sc.core.x + 2, 2)
	_tower_line(g, out, 620, 13, sc.core.x - 4, sc.core.x + 4, 4)
	# 后期纵深（击杀收入滚起来后）
	for i in 3:
		_tower_line(g, out, 2600 + i * 500, 16 + i * 2, sc.core.x - 6, sc.core.x + 6, 4)
	return out


## 开门陷阱：乌龟同构的漏斗塔链 + 挖盆地插口（贪食线）——插口渗怪 bare_dist=-1
## 无赏金基线，验证开门不再支配
static func script_trapdoor(sc: Scenario) -> Array:
	var g := sc.build_grid()
	var script: Array = Verify.script_for(sc) # 乌龟同构骨架
	var extra: Array = []
	extra.append([18, "dig", sc.basin_plug.x, sc.basin_plug.y]) # 唯一差异：开局开门
	# 黄金脚本 tick 1000 才挖插口（开门陷阱段）；提前到 tick 18 = 贪食线全程承压
	var merged := extra + script
	return merged


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
