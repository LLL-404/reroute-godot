class_name World
extends RefCounted

# 世界状态机：照搬 warden/Warden.Core/World.cs 的切片语义 + reroute/scripts/sim/world.lua。
# 铁律（全部照抄母体）：
#   · 一切状态变更只经 apply_command；非法命令零状态副作用；
#   · 终局后整体冻结（tick 与命令都不再改变状态）；
#   · 一 tick 固定次序：①摊销补场 ②波次导演 ③单位移动/啃建筑 ③b 英雄步进 ④塔开火与施工 ⑤清尸 ⑥胜负判定；
#   · 无浮点无 libm；Rng 只在波次抖动里被调用。
# 改道经济：击杀赏金 = 敌基础赏金 + (绕行路程 >> CONVOY_SHIFT)；traveled 在 ③ 推进时累积
# （英雄击退不计），只有塔火击杀能兑现。
const RUNNING := 0
const WON := 1
const LOST := 2
const INT64_MAX := 9223372036854775807

var sc: Scenario
var seed: int
var rebuild_budget: int
var grid: Grid
var rng: Rng
var tick_count: int
var supply: int
var outcome: int
var route_opened: bool
var kills: int
var convoy_earned: int
var buildings_lost: int
var units: Array # 活表：追加 + 稳定压缩 ⇒ 顺序恒等于 id 升序
var buildings: Array
var by_cell: Dictionary # idx -> building
var next_unit_id: int
var next_building_id: int
var core: Dictionary

# 主场（目标=核心格）+ 围攻场（惰性，目标=全部存活建筑格）
var field: FlowField
var field_goals: Array
var field_rev: int
var rebuilding: bool

# 围攻场
var siege: FlowField
var siege_rev: int
var siege_stamp: int

# 英雄（不进 units/buildings，独立实体；英雄场是派生态，不进指纹）
var hero: Dictionary
var hero_field: FlowField
var hero_field_rev: int
var hero_goal_tx: int
var hero_goal_ty: int


## 初始化世界状态：建网格、放核心、建主场流场
func _init(psc: Scenario, pseed: int, prebuild_budget: int = 2048) -> void:
	sc = psc
	seed = pseed
	rebuild_budget = prebuild_budget
	grid = sc.build_grid()
	rng = Rng.new(seed)
	tick_count = 0
	supply = Sim.START_SUPPLY
	outcome = RUNNING
	route_opened = false
	kills = 0
	convoy_earned = 0
	buildings_lost = 0
	units = []
	buildings = []
	by_cell = {}
	next_unit_id = 1
	next_building_id = 1
	core = {}

	field = FlowField.new(grid)
	field_goals = [Vector2i(sc.core.x, sc.core.y)]
	field_rev = -1
	rebuilding = false
	_rebuild_field_sync()

	siege = null
	siege_rev = -1
	siege_stamp = -1

	hero = { "x": sc.hero_spawn.x, "y": sc.hero_spawn.y, "tx": -1, "ty": -1, "skill_cd": 0 }
	hero_field = FlowField.new(grid, true) # 英雄翻崖：无视高度
	hero_field_rev = -1
	hero_goal_tx = -1
	hero_goal_ty = -1
	place_building(Sim.B_CORE, sc.core.x, sc.core.y)


## 同步重建主场流场（初始化时调用；运行时走摊销补场）
func _rebuild_field_sync() -> void:
	field.begin(field_goals)
	while not field.done():
		field.step(1 << 30)
	field_rev = grid.rev
	rebuilding = false


# ---------------- 唯一变更入口 ----------------

## 终局即整体冻结；非法命令零状态副作用（守卫全部在变更之前）。
func apply_command(cmd: Dictionary) -> void:
	if outcome != RUNNING:
		return
	var kind: String = cmd["kind"]
	if kind == "dig":
		if grid.at(cmd["x"], cmd["y"]) == Grid.COVER:
			grid.set_cell(cmd["x"], cmd["y"], Grid.OPEN)
			if sc.is_ore(cmd["x"], cmd["y"]):
				supply += Sim.ORE_YIELD
			if cmd["x"] == sc.basin_plug.x and cmd["y"] == sc.basin_plug.y:
				route_opened = true
	elif kind == "wall" or kind == "tower":
		var bkind := Sim.B_WALL if kind == "wall" else Sim.B_TOWER
		try_build(bkind, cmd["x"], cmd["y"])
	elif kind == "remove":
		try_remove(cmd["x"], cmd["y"])
	elif kind == "hero":
		# 点地移动：目标须可通行且不是原地；被墙截断时英雄场重建自动续路
		if grid.passable(cmd["x"], cmd["y"]) and not (cmd["x"] == hero["x"] and cmd["y"] == hero["y"]):
			hero["tx"] = cmd["x"]
			hero["ty"] = cmd["y"]
	elif kind == "shock":
		if hero["skill_cd"] == 0:
			cast_shock()
	elif kind == "fill" or kind == "lower":
		# 地形改造：填高 +1 / 挖低 −1（守卫全在变更前，非法零副作用）
		var x: int = cmd["x"]
		var y: int = cmd["y"]
		if grid.passable(x, y) and by_cell.get(grid.idx(x, y)) == null and cell_vacant(x, y) and not (x == hero["x"] and y == hero["y"]):
			var cur := grid.get_h(x, y)
			if kind == "fill":
				if cur < Sim.H_MAX and supply >= Sim.FILL_COST:
					supply -= Sim.FILL_COST
					grid.set_h(x, y, cur + 1)
			else:
				if cur > Sim.H_MIN and supply >= Sim.LOWER_COST:
					supply -= Sim.LOWER_COST
					grid.set_h(x, y, cur - 1)
	elif kind == "spawn":
		if grid.passable(cmd["x"], cmd["y"]):
			spawn_unit(cmd["x"], cmd["y"], cmd.get("speed", 0), cmd.get("kind_id", Sim.E_SWARM))
	# 未知命令 = Nop：零副作用


## 生成一个敌人单位（含波次缩放 HP、速度抖动）
func spawn_unit(x: int, y: int, speed_ticks: int, kind: int) -> void:
	var e: Dictionary = Sim.ENEMIES[kind - 1]
	var hp: int = e["hp"]
	var pct: int = sc.wave_scale_pct
	if pct != 100:
		hp = Lua64.idiv(hp * pct, 100)
		if hp < 1:
			hp = 1
	var unit := {
		"id": next_unit_id,
		"x": x,
		"y": y,
		"speed_ticks": e["speed_ticks"] if speed_ticks == 0 else speed_ticks,
		"stuck_ticks": 0,
		"kind": kind,
		"hp": hp,
		"atk_cd": 0,
		"atk_target": -1,
		"traveled": 0,
	}
	next_unit_id += 1
	units.append(unit)


## 该格是否有单位占据
func cell_vacant(x: int, y: int) -> bool:
	for i in units.size():
		var u: Dictionary = units[i]
		if u["x"] == x and u["y"] == y:
			return false
	return true


## 放置建筑（含施工时间、立即挡路）；核心额外记录
func place_building(bkind: int, x: int, y: int) -> Dictionary:
	var def: Dictionary = Sim.BUILDINGS[bkind - 1]
	# 第 1 波之前施工时间减半（切片 1 的教学让步）
	var build: int = def["build_ticks"]
	if sc.waves.size() > 0 and tick_count < sc.waves[0][0]:
		build = Lua64.idiv(build, 2)
	var b := {
		"id": next_building_id,
		"kind": bkind,
		"x": x,
		"y": y,
		"hp": def["hp"],
		"build_left": build,
		"cooldown": 0,
	}
	next_building_id += 1
	buildings.append(b)
	by_cell[grid.idx(x, y)] = b
	grid.set_cell(x, y, Grid.SOLID) # 施工即挡路：改道当场发生
	if bkind == Sim.B_CORE:
		core = b
	return b


## 尝试建造（供给/通行/占用/英雄守卫通过后扣费放置）
func try_build(bkind: int, x: int, y: int) -> void:
	var def: Dictionary = Sim.BUILDINGS[bkind - 1]
	if supply < def["cost"]:
		return
	if not grid.passable(x, y):
		return
	if by_cell.get(grid.idx(x, y)) != null:
		return
	if not cell_vacant(x, y):
		return # 任何时刻不得有单位处于阻挡格内
	if x == hero["x"] and y == hero["y"]:
		return # 不得压在英雄脚下
	supply -= def["cost"]
	place_building(bkind, x, y)


## 拆除建筑（核心不可拆；施工完退 50%，否则退 80%）
func try_remove(x: int, y: int) -> void:
	var b = building_at(x, y)
	if b == null or b["kind"] == Sim.B_CORE or b["hp"] <= 0:
		return
	var def: Dictionary = Sim.BUILDINGS[b["kind"] - 1]
	var refund := Lua64.idiv(def["cost"] * (50 if b["build_left"] <= 0 else 80), 100)
	supply += refund
	by_cell.erase(grid.idx(x, y))
	grid.set_cell(x, y, Grid.OPEN)
	b["hp"] = 0 # 待清理；已付的建造时间不退


# ---------------- 一 tick ----------------

## 推进一步模拟（固定次序：摊销补场 → 波次 → 移动 → 英雄 → 塔/施工 → 清尸 → 判定）
func tick() -> void:
	if outcome != RUNNING:
		return
	tick_count += 1

	# ① 摊销补场
	if grid.rev != field_rev or rebuilding:
		if not rebuilding:
			field.begin(field_goals)
			rebuilding = true
		field.step(rebuild_budget) # 每 tick 固定预算，跨 tick 续跑
		if field.done():
			rebuilding = false
			field_rev = grid.rev

	run_waves()
	move_units()
	hero_tick()
	towers_and_build()
	compact()
	judge()


## 波次导演：到点的波次表条目发射；暗门开后定时渗怪
func run_waves() -> void:
	for w in sc.waves:
		if w[0] == tick_count:
			emit_wave(w[1], w[2], w[3])
	if route_opened and sc.trickle_every > 0 and tick_count % sc.trickle_every == 0:
		emit_wave(3, Sim.E_SWARM, 2) # 盆地出怪口（1 基 = 3）


## 发射一波敌人（螺旋找空格 + 速度抖动）
func emit_wave(spawn_idx: int, kind: int, count: int) -> void:
	var sx: int = sc.spawns[spawn_idx - 1].x
	var sy: int = sc.spawns[spawn_idx - 1].y
	for _i in count:
		var cell := _find_spawn_cell(sx, sy)
		if cell.x < 0:
			continue # 无处可放：跳过该单位，且不消耗 Rng（母体同口径）
		var spd: int = Sim.ENEMIES[kind - 1]["speed_ticks"] + rng.next_int(2)
		apply_command({ "kind": "spawn", "x": cell.x, "y": cell.y, "speed": spd, "kind_id": kind })


## 出生点螺旋找空格（r=0..3 切比雪夫环）；找不到回退场；再找不到返回 (-1,-1)。
func _find_spawn_cell(sx: int, sy: int) -> Vector2i:
	var r := 0
	while r <= 3:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) == r:
					var nx := sx + dx
					var ny := sy + dy
					if grid.passable(nx, ny) and cell_vacant(nx, ny):
						return Vector2i(nx, ny)
		r += 1
	var fb := field.fallback_near(sx, sy)
	if fb < 0:
		return Vector2i(-1, -1)
	return Vector2i(Lua64.mod(fb, grid.w), Lua64.idiv(fb, grid.w))


## 单位移动：沿主场流场走一格；被封分支处理啃建筑/转围攻
func move_units() -> void:
	for ui in units.size():
		var unit: Dictionary = units[ui]
		if unit["atk_cd"] > 0:
			unit["atk_cd"] = unit["atk_cd"] - 1
		if (tick_count + unit["id"]) % unit["speed_ticks"] == 0: # 未到步点则跳过
			var dir := field.dir_at(unit["x"], unit["y"])
			if dir >= 0:
				var nx: int = unit["x"] + FlowField.DX[dir]
				var ny: int = unit["y"] + FlowField.DY[dir]
				if grid.passable(nx, ny):
					unit["x"] = nx
					unit["y"] = ny
					unit["traveled"] = unit["traveled"] + 1
					unit["stuck_ticks"] = 0
					unit["atk_target"] = -1
				else:
					stuck_branch(unit)
			elif field.dist_at(unit["x"], unit["y"]) == 0:
				pass # 已抵达目标格（核心脚下），正常待机
			else:
				stuck_branch(unit)


## 被封分支：贴脸有建筑就啃；啃不到且真被围死 → 沿围攻场推进。
func stuck_branch(unit: Dictionary) -> void:
	unit["stuck_ticks"] = unit["stuck_ticks"] + 1
	unit["atk_target"] = find_attack_target(unit)
	if unit["atk_target"] >= 0:
		if unit["atk_cd"] == 0:
			var e: Dictionary = Sim.ENEMIES[unit["kind"] - 1]
			damage_building(unit["atk_target"], e["damage"])
			unit["atk_cd"] = e["cooldown"]
		return
	# 通往核心的路被彻底封死 → 转围攻：朝最近建筑推进，直到贴脸能啃
	ensure_siege()
	var sdir := siege.dir_at(unit["x"], unit["y"])
	if sdir < 0:
		return # 全场无可攻目标（核心已毁等）→ 原地待命
	var mx: int = unit["x"] + FlowField.DX[sdir]
	var my: int = unit["y"] + FlowField.DY[sdir]
	if grid.passable(mx, my):
		unit["x"] = mx
		unit["y"] = my
		unit["traveled"] = unit["traveled"] + 1 # 被围死后的绕行也是"在玩家地图上走路"，照计路程
		unit["atk_target"] = find_attack_target(unit)


## 围攻场：目标 = 全部存活建筑格（含核心）。拓扑或建筑表变化时才重建。
func ensure_siege() -> void:
	if siege == null:
		siege = FlowField.new(grid)
	var stamp := next_building_id
	if siege_rev == grid.rev and siege_stamp == stamp:
		return
	var goals := []
	for i in buildings.size():
		var b: Dictionary = buildings[i]
		if b["hp"] > 0:
			goals.append(Vector2i(b["x"], b["y"]))
	siege.begin(goals)
	while not siege.done():
		siege.step(1 << 30)
	siege_rev = grid.rev
	siege_stamp = stamp


## 震荡波：半径（平方距离）内敌人沿背离英雄方向击退 1 格；落点须可通行、无单位且高度边合法
## （可震下崖、不可推上崖）。不改地形、不耗 Rng；冷却期命令为 Nop（零副作用）。
func cast_shock() -> void:
	hero["skill_cd"] = Sim.HERO["skill_cooldown"]
	var r2: int = Sim.HERO["skill_radius"] * Sim.HERO["skill_radius"]
	for i in units.size():
		var u: Dictionary = units[i]
		var dx: int = u["x"] - hero["x"]
		var dy: int = u["y"] - hero["y"]
		var d2: int = dx * dx + dy * dy
		if u["hp"] > 0 and d2 > 0 and d2 <= r2:
			var sx := 1 if dx > 0 else (-1 if dx < 0 else 0)
			var sy := 1 if dy > 0 else (-1 if dy < 0 else 0)
			var nx: int = u["x"] + sx
			var ny: int = u["y"] + sy
			if (nx != u["x"] or ny != u["y"]) and grid.passable(nx, ny) and cell_vacant(nx, ny) and grid.get_h(nx, ny) - grid.get_h(u["x"], u["y"]) <= 1:
				u["x"] = nx
				u["y"] = ny


## 英雄步进（固定次序 ③b）：冷却每 tick 走一；有目标且到步点则沿英雄场走一格。
func hero_tick() -> void:
	if hero["skill_cd"] > 0:
		hero["skill_cd"] = hero["skill_cd"] - 1
	if hero["tx"] < 0:
		return
	if (tick_count + 1) % Sim.HERO["speed_ticks"] != 0:
		return
	if hero_field_rev != grid.rev or hero_goal_tx != hero["tx"] or hero_goal_ty != hero["ty"]:
		hero_field.begin([Vector2i(hero["tx"], hero["ty"])])
		while not hero_field.done():
			hero_field.step(1 << 30)
		hero_field_rev = grid.rev
		hero_goal_tx = hero["tx"]
		hero_goal_ty = hero["ty"]
	if hero_field.dist_at(hero["x"], hero["y"]) == 0:
		hero["tx"] = -1
		hero["ty"] = -1 # 已抵达
		return
	var dir := hero_field.dir_at(hero["x"], hero["y"])
	if dir < 0:
		return # 不可达/被围死：原地待命
	var nx: int = hero["x"] + FlowField.DX[dir]
	var ny: int = hero["y"] + FlowField.DY[dir]
	if grid.passable(nx, ny):
		hero["x"] = nx
		hero["y"] = ny


## 邻格里挑"拆掉最划算"的建筑：以该建筑周边的最小场距打分，平手取方向序最小。
func find_attack_target(unit: Dictionary) -> int:
	var best = null
	var best_score := INT64_MAX
	for k in 8:
		var nx: int = unit["x"] + FlowField.DX[k]
		var ny: int = unit["y"] + FlowField.DY[k]
		var b = building_at(nx, ny)
		if b != null and b["hp"] > 0:
			var score := score_around(nx, ny)
			if score < best_score:
				best_score = score
				best = b
	return best["id"] if best != null else -1


func score_around(x: int, y: int) -> int:
	var best := INT64_MAX
	var self_d := field.dist_at(x, y)
	if self_d >= 0:
		best = self_d
	for k in 8:
		var d := field.dist_at(x + FlowField.DX[k], y + FlowField.DY[k])
		if d >= 0 and d < best:
			best = d
	return best


## 界外恒无建筑（复刻 World.At 的口径；grid:idx 对界外会算出环绕碰撞下标，必须先判界）。
func building_at(x: int, y: int):
	if not grid.inb(x, y):
		return null
	return by_cell.get(grid.idx(x, y))


func damage_building(id: int, dmg: int) -> void:
	for i in buildings.size():
		var b: Dictionary = buildings[i]
		if b["id"] == id:
			b["hp"] = b["hp"] - dmg
			if b["hp"] > 0:
				return
			b["hp"] = 0
			if b["kind"] == Sim.B_CORE:
				outcome = LOST
				return
			by_cell.erase(grid.idx(b["x"], b["y"]))
			grid.set_cell(b["x"], b["y"], Grid.OPEN) # 塌墙即改道：流场当 tick 开始追平
			buildings_lost += 1
			return


## 塔开火与建筑施工：施工递减；塔找最近敌人射程内开火；击杀结算赏金
func towers_and_build() -> void:
	for i in buildings.size():
		var b: Dictionary = buildings[i]
		if b["hp"] > 0:
			if b["build_left"] > 0:
				b["build_left"] = b["build_left"] - 1
			else:
				var def: Dictionary = Sim.BUILDINGS[b["kind"] - 1]
				if def["shoots"]:
					if b["cooldown"] > 0:
						b["cooldown"] = b["cooldown"] - 1
					else:
						var best_u = null
						var best_d := INT64_MAX
						for ui in units.size():
							var un: Dictionary = units[ui]
							if un["hp"] > 0:
								var dx: int = un["x"] - b["x"]
								var dy: int = un["y"] - b["y"]
								var d2: int = dx * dx + dy * dy
								if d2 <= def["range"] * def["range"] and d2 < best_d:
									best_d = d2
									best_u = un
						if best_u != null:
							best_u["hp"] = best_u["hp"] - def["damage"]
							b["cooldown"] = def["cooldown"]
							if best_u["hp"] <= 0:
								# 改道经济：赏金 = 基础 + 绕行路程折算；只有塔火能兑现
								var bonus := Lua64.lshr(best_u["traveled"], Sim.CONVOY_SHIFT)
								supply += Sim.ENEMIES[best_u["kind"] - 1]["reward"] + bonus
								convoy_earned += bonus
								kills += 1


## 清尸：移除死亡单位（保留核心建筑）
func compact() -> void:
	# 建新数组而非原地压缩：GDScript 对带推断元素类型的数组做下标赋值会报类型错误
	var kept_u := []
	for i in units.size():
		if units[i]["hp"] > 0:
			kept_u.append(units[i])
	units = kept_u

	var kept_b := []
	for i in buildings.size():
		if buildings[i]["hp"] > 0 or buildings[i]["kind"] == Sim.B_CORE:
			kept_b.append(buildings[i])
	buildings = kept_b


## 胜负判定：到终局 tick 且场上无敌人 = 胜；超时 = 负
func judge() -> void:
	if outcome != RUNNING:
		return # 本 tick 内已分胜负（核心被啃等）不许被改写
	if tick_count >= sc.end_tick and units.size() == 0:
		outcome = WON
	elif tick_count >= sc.hard_cap_tick:
		outcome = LOST # 超时＝敌按时刻表长完，守方判负


# ---------------- 规范状态编码（STATE_SCHEMA=5）----------------
# tick | rng | grid | 供给/结局/开门/战果 | 单位表按 id 升序 | 建筑表按 id 升序。
# 流场是派生态，不进指纹。
func canonical_bytes() -> Canon.Buf:
	var b := Canon.buffer()
	b.put_u32(Canon.STATE_SCHEMA)
	b.put_u64(tick_count)
	b.put_u64(rng.state)
	b.put_i32(grid.w)
	b.put_i32(grid.h)
	for i in grid.w * grid.h:
		b.put_u8(grid.cells[i])
	for i in grid.w * grid.h:
		b.put_u8(grid.hgt[i]) # v5：高度层（玩家可改造，进指纹）
	b.put_i32(supply)
	b.put_u8(outcome)
	b.put_u8(1 if route_opened else 0)
	b.put_i32(kills)
	b.put_i32(buildings_lost)

	b.put_u32(units.size())
	for i in units.size():
		var u: Dictionary = units[i]
		b.put_i32(u["id"])
		b.put_i32(u["x"])
		b.put_i32(u["y"])
		b.put_u8(u["speed_ticks"])
		b.put_u8(u["kind"])
		b.put_i32(u["stuck_ticks"])
		b.put_i32(u["hp"])
		b.put_i32(u["atk_cd"])
		b.put_i32(u["atk_target"])
		b.put_i32(u["traveled"]) # v3：绕行路程

	b.put_u32(buildings.size())
	for i in buildings.size():
		var s: Dictionary = buildings[i]
		b.put_i32(s["id"])
		b.put_u8(s["kind"])
		b.put_i32(s["x"])
		b.put_i32(s["y"])
		b.put_i32(s["hp"])
		b.put_i32(s["build_left"])
		b.put_i32(s["cooldown"])

	b.put_u8(1) # 英雄恒在（Jam 版无死亡）
	b.put_i32(hero["x"])
	b.put_i32(hero["y"])
	b.put_i32(hero["tx"])
	b.put_i32(hero["ty"])
	b.put_i32(hero["skill_cd"])
	b.put_i32(convoy_earned) # v4：绕行赏金累计
	return b


## 计算 FNV-1a 指纹（经 canonical_bytes 编码）
func fingerprint() -> int:
	return canonical_bytes().fingerprint()
