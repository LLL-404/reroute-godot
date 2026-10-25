class_name World
extends RefCounted

# 世界状态机：照搬 warden/Warden.Core/World.cs 的切片语义 + reroute/scripts/sim/world.lua。
# 2026-10-17 六边形化：网格 = 尖顶六边 odd-r（grid.gd），流场六向等权；移动/围攻/击退
# 全部经 Grid.nx/ny 方向表落地；震荡波击退 = 轴向主轴符号（六向）。
# 铁律（全部照抄母体）：
#   · 一切状态变更只经 apply_command；非法命令零状态副作用；
#   · 终局后整体冻结（tick 与命令都不再改变状态）；
#   · 一 tick 固定次序：①摊销补场 ②波次导演 ③单位移动/啃建筑 ③b 英雄步进 ④塔开火与施工 ⑤清尸 ⑥胜负判定；
#   · 无浮点无 libm；Rng 只在波次抖动里被调用。
# 改道经济（2026-10-25 换轨）：击杀赏金 = 敌基础赏金 + 有效绕行折算（effdetour >> CONVOY_SHIFT，
# 封顶 2×基础）；effdetour = traveled + 死位主场剩余距离 − 出生格裸图基线，任一端不可达记 0
# ——堵死（死位不可达）与开门陷阱（出生口裸图不可达）都拿不到绕行钱；只有塔火击杀能兑现。
const RUNNING := 0
const WON := 1
const LOST := 2
const INT64_MAX := 9223372036854775807
# 建造撤销窗口（tick，5s）：只允许撤销刚落下的建筑并全额退款。
# 仅主循环/HUD 用；placed_tick 不进 canonical_bytes，不影响黄金指纹。
const UNDO_WINDOW_TICKS := 100

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

# ---- 肉鸽模式扩展点（经典模式全部保持默认值 ⇒ 16 指纹零漂移） ----
# btab 为空 = 用 Sim.BUILDINGS（经典）；非空 = 8 种塔的扩展表（肉鸽）。
# bounty_shift / hero_radius / hero_cd_max 默认取 Sim 常量；肉鸽遗物/天赋覆写。
# wave_driver 非空时接管 run_waves()：肉鸽模式由 RunState 按波内节奏发怪。
# 以上字段均不进 canonical_bytes（不参与指纹），故不影响经典基线。
var btab: Array = []
var bounty_shift: int = 0
var hero_radius: int = 0
var hero_cd_max: int = 0
var wave_driver: Callable = Callable()
var tower_cap: int = -1 # 塔位上限；-1 = 不限（经典模式）。肉鸽按层给出

# 主场（目标=核心格）：虫群场 + 蛮兽场（爬升上限不同）
var field: FlowField
var field_goals: Array
var field_rev: int
var rebuilding: bool
var rebuild_rev: int # 本轮摊销 begin 时的 grid.rev（中途变则整轮重启）
var field_heavy: FlowField
var field_heavy_rev: int
var rebuilding_heavy: bool
var rebuild_rev_heavy: int

# 裸图基线场（开局布局、无任何玩家改动的距离场；派生态不进指纹，算完即冻结不随 rev 重建）
var bare_field: FlowField
var bare_field_heavy: FlowField

# 围攻场（按兵种爬升上限各一份）
var siege: FlowField
var siege_rev: int
var siege_stamp: int
var siege_heavy: FlowField
var siege_heavy_rev: int
var siege_heavy_stamp: int

# 英雄（不进 units/buildings，独立实体；英雄场是派生态，不进指纹）
var hero: Dictionary
var hero_field: FlowField
var hero_field_rev: int
var hero_goal_tx: int
var hero_goal_ty: int

# 工人采运（2026-10-25 采矿改形 C）：矿不即时入账，工人沿流场搬运回核心结算。
# 独立实体（同英雄：不进 units/buildings，敌人不索敌、互相穿行、脚下不可建造）；
# 行走沿主战场口径（爬 2 级），玩家放墙/改地形实时改写矿车行程——经济与「放墙」咬死。
# 状态/载量/矿格余量进指纹（影响供给序列）；流场是派生态不进指纹。
var workers: Array # { id, x, y, state, target, carrying, mine_cd, field, field_rev, field_goal, pick_rev }
var ore_left: Dictionary # grid.idx -> 剩余储量（sc.ore_cells 全集初始化；位置序进指纹）


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
	field_heavy = FlowField.new(grid, false, 1) # 蛮兽：只能爬 1 级
	field_heavy_rev = -1
	rebuilding_heavy = false
	_rebuild_field_sync()

	# 裸图基线场：开局布局（无玩家建筑/挖填）按兵种口径各一张，一次性算完冻结
	var bare_grid := sc.build_grid()
	var bare_goals := [Vector2i(sc.core.x, sc.core.y)]
	bare_field = FlowField.new(bare_grid)
	bare_field.begin(bare_goals)
	while not bare_field.done():
		bare_field.step(1 << 30)
	bare_field_heavy = FlowField.new(bare_grid, false, 1)
	bare_field_heavy.begin(bare_goals)
	while not bare_field_heavy.done():
		bare_field_heavy.step(1 << 30)

	siege = null
	siege_rev = -1
	siege_stamp = -1
	siege_heavy = null
	siege_heavy_rev = -1
	siege_heavy_stamp = -1

	hero = { "x": sc.hero_spawn.x, "y": sc.hero_spawn.y, "tx": -1, "ty": -1, "skill_cd": 0 }
	hero_field = FlowField.new(grid, true) # 英雄翻崖：无视高度
	hero_field_rev = -1
	hero_goal_tx = -1
	hero_goal_ty = -1
	# 肉鸽扩展点默认值：与经典常量逐位一致
	bounty_shift = Sim.CONVOY_SHIFT
	hero_radius = int(Sim.HERO["skill_radius"])
	hero_cd_max = int(Sim.HERO["skill_cooldown"])
	wave_driver = Callable()
	tower_cap = -1
	place_building(Sim.B_CORE, sc.core.x, sc.core.y)
	# 工人与矿格余量（核心落地后出生：第 id 个可行邻格，都是核心山头通行格）
	ore_left = {}
	for i in sc.ore_cells.size():
		ore_left[grid.idx(sc.ore_cells[i].x, sc.ore_cells[i].y)] = Sim.ORE_STORE
	workers = []
	for i in Sim.WORKER_COUNT:
		_spawn_worker(i)


## 同步重建两个主场流场（初始化/存档前调用；运行时走摊销补场）
func _rebuild_field_sync() -> void:
	field.begin(field_goals)
	while not field.done():
		field.step(1 << 30)
	field_rev = grid.rev
	rebuild_rev = grid.rev
	rebuilding = false
	field_heavy.begin(field_goals)
	while not field_heavy.done():
		field_heavy.step(1 << 30)
	field_heavy_rev = grid.rev
	rebuild_rev_heavy = grid.rev
	rebuilding_heavy = false


# ---------------- 唯一变更入口 ----------------

## 终局即整体冻结；非法命令零状态副作用（守卫全部在变更之前）。
func apply_command(cmd: Dictionary) -> void:
	if outcome != RUNNING:
		return
	var kind: String = cmd["kind"]
	if kind == "dig":
		if grid.at(cmd["x"], cmd["y"]) == Grid.COVER:
			grid.set_cell(cmd["x"], cmd["y"], Grid.OPEN)
			# 采矿改形 C：挖开只露矿不开钱——入账由工人搬运回核心结算
			if cmd["x"] == sc.basin_plug.x and cmd["y"] == sc.basin_plug.y:
				route_opened = true
	elif kind == "wall" or kind == "tower":
		var bkind := Sim.B_WALL if kind == "wall" else Sim.B_TOWER
		try_build(bkind, cmd["x"], cmd["y"])
	elif kind == "build":
		# 肉鸽模式：按显式 bkind 建造（8 种塔）。经典模式不发此命令 ⇒ 基线不变。
		try_build(int(cmd["bkind"]), cmd["x"], cmd["y"])
	elif kind == "remove":
		try_remove(cmd["x"], cmd["y"])
	elif kind == "undo_build":
		try_undo_build(cmd["x"], cmd["y"])
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
		"climb_wait": 0,
		"bare_dist": bare_field_for(kind).dist_at(x, y), # v8：出生格裸图基线（不可达 -1）
		"stun": 0, # v10：震荡波眩晕剩余 tick（0=无）
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


## 建筑定义查询：经典模式（btab 空）恒走 Sim.BUILDINGS；肉鸽模式走扩展表。
## 越界返回空字典——调用方必须先保证 bkind 合法（apply_command 的守卫链已保证）。
func bdef(bkind: int) -> Dictionary:
	var i: int = bkind - 1
	if btab.is_empty():
		if i < 0 or i >= Sim.BUILDINGS.size():
			return {}
		return Sim.BUILDINGS[i]
	if i < 0 or i >= btab.size():
		return {}
	return btab[i]


## 存活建筑数（不含核心）——塔位上限判定用
func live_buildings() -> int:
	var n := 0
	for i in buildings.size():
		var b: Dictionary = buildings[i]
		if b["hp"] > 0 and int(b["kind"]) != Sim.B_CORE:
			n += 1
	return n


## 存活墙数——墙阶梯价判定用
func live_walls() -> int:
	var n := 0
	for i in buildings.size():
		var b: Dictionary = buildings[i]
		if b["hp"] > 0 and int(b["kind"]) == Sim.B_WALL:
			n += 1
	return n


## 墙当前单价（阶梯价）：<20 面 5，之后基准价 10；达 35 面上限返回 -1（不可再建）。
## 拆墙回收名额（存活数口径），拆建循环因退款折半而无利可图。
func wall_price() -> int:
	var n := live_walls()
	if n >= Sim.WALL_TIER_CAP:
		return -1
	return Sim.WALL_TIER_CHEAP_COST if n < Sim.WALL_TIER_CHEAP else int(Sim.BUILDINGS[Sim.B_WALL - 1]["cost"])


## 建筑当前造价（墙走阶梯价，其余走表价）；-1 = 不可建（墙数上限）
func build_price(bkind: int) -> int:
	if bkind == Sim.B_WALL:
		return wall_price()
	var def: Dictionary = bdef(bkind)
	return int(def.get("cost", -1))


## 放置建筑（含施工时间、立即挡路）；核心额外记录。paid = 实付造价（墙为阶梯价当次值）
func place_building(bkind: int, x: int, y: int, paid: int = -1) -> Dictionary:
	var def: Dictionary = bdef(bkind)
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
		"placed_tick": tick_count, # 仅撤销窗口用；不进 canonical/save
		"paid": int(def["cost"]) if paid < 0 else paid, # v9：实付造价（退款口径）
	}
	next_building_id += 1
	buildings.append(b)
	by_cell[grid.idx(x, y)] = b
	grid.set_cell(x, y, Grid.SOLID) # 施工即挡路：改道当场发生
	if bkind == Sim.B_CORE:
		core = b
	return b


## 尝试建造（供给/通行/占用/英雄守卫通过后扣费放置；墙走阶梯价、达上限拒建）
func try_build(bkind: int, x: int, y: int) -> void:
	if tower_cap >= 0 and bkind != Sim.B_CORE and live_buildings() >= tower_cap:
		return # 肉鸽塔位已满（经典模式 tower_cap=-1，此分支永不触发）
	var cost := build_price(bkind)
	if cost < 0:
		return # 墙数达上限（WALL_TIER_CAP）
	if supply < cost:
		return
	if not grid.passable(x, y):
		return
	if by_cell.get(grid.idx(x, y)) != null:
		return
	if not cell_vacant(x, y):
		return # 任何时刻不得有单位处于阻挡格内
	if x == hero["x"] and y == hero["y"]:
		return # 不得压在英雄脚下
	for wk in workers:
		if int(wk["x"]) == x and int(wk["y"]) == y:
			return # 不得压在工人脚下（矿车实体同英雄口径）
	supply -= cost
	place_building(bkind, x, y, cost)


## 拆除建筑（核心不可拆；施工完退实付价 50%，否则退 80%）
func try_remove(x: int, y: int) -> void:
	var b = building_at(x, y)
	if b == null or b["kind"] == Sim.B_CORE or b["hp"] <= 0:
		return
	var paid := int(b.get("paid", int(bdef(int(b["kind"]))["cost"])))
	var refund := Lua64.idiv(paid * (50 if b["build_left"] <= 0 else 80), 100)
	supply += refund
	by_cell.erase(grid.idx(x, y))
	grid.set_cell(x, y, Grid.OPEN)
	b["hp"] = 0 # 待清理；已付的建造时间不退


## 撤销刚落下的建筑（5 秒窗口、未受损、非核心）：按实付价全额退款并恢复通行。
## 只由 main 的「撤销上一步」调用；不进黄金回放命令表，故不影响 16 指纹。
func try_undo_build(x: int, y: int) -> void:
	var b = building_at(x, y)
	if b == null or int(b["kind"]) == Sim.B_CORE or int(b["hp"]) <= 0:
		return
	var placed := int(b.get("placed_tick", -UNDO_WINDOW_TICKS - 1))
	if tick_count - placed > UNDO_WINDOW_TICKS:
		return
	var def: Dictionary = bdef(int(b["kind"]))
	if int(b["hp"]) < int(def["hp"]):
		return # 已被啃过：走普通拆除退款，避免满血价撤销
	supply += int(b.get("paid", int(def["cost"])))
	by_cell.erase(grid.idx(x, y))
	grid.set_cell(x, y, Grid.OPEN)
	b["hp"] = 0


# ---------------- 一 tick ----------------

## 推进一步模拟（固定次序：摊销补场 → 波次 → 移动 → 英雄 → 塔/施工 → 清尸 → 判定）
func tick() -> void:
	if outcome != RUNNING:
		return
	tick_count += 1

	# ① 摊销补场：补场中途改图（rev 变化）则整轮重启 begin——
	# 旧拓扑下已定稿的距离不能冒充当前拓扑的结果（否则完成时 field_rev 会谎报已同步）
	# 两个主场各自独立摊销；任一 rev 变都只影响它自己那轮的整轮重启。
	if rebuilding and grid.rev != rebuild_rev:
		rebuilding = false
	if grid.rev != field_rev or rebuilding:
		if not rebuilding:
			field.begin(field_goals)
			rebuilding = true
			rebuild_rev = grid.rev
		field.step(rebuild_budget) # 每 tick 固定预算，跨 tick 续跑
		if field.done():
			rebuilding = false
			field_rev = rebuild_rev
	if rebuilding_heavy and grid.rev != rebuild_rev_heavy:
		rebuilding_heavy = false
	if grid.rev != field_heavy_rev or rebuilding_heavy:
		if not rebuilding_heavy:
			field_heavy.begin(field_goals)
			rebuilding_heavy = true
			rebuild_rev_heavy = grid.rev
		field_heavy.step(rebuild_budget)
		if field_heavy.done():
			rebuilding_heavy = false
			field_heavy_rev = rebuild_rev_heavy

	run_waves()
	move_units()
	hero_tick()
	worker_tick()
	towers_and_build()
	compact()
	judge()


## 波次导演：到点的波次表条目发射；暗门开后定时渗怪。
## 出怪点解析走 sc.wave_cell（自由路径三主口按表序轮转；旧路径逐位同历史）。
func run_waves() -> void:
	if wave_driver.is_valid():
		wave_driver.call() # 肉鸽模式：RunState 按波内相对时刻发怪
		return
	for ei in sc.waves.size():
		var w: Array = sc.waves[ei]
		if w[0] == tick_count:
			emit_wave_at(sc.wave_cell(ei), w[2], w[3])
	if route_opened and sc.trickle_every > 0 and tick_count % sc.trickle_every == 0:
		emit_wave_at(sc.basin_cell(), Sim.E_SWARM, 2) # 盆地出怪口（spawns 末位）


## 发射一波敌人（1 基出怪口下标旧签名，测试兼容；内部走 emit_wave_at）
func emit_wave(spawn_idx: int, kind: int, count: int) -> void:
	emit_wave_at(sc.spawns[spawn_idx - 1], kind, count)


## 发射一波敌人（指定出怪格；螺旋找空格 + 速度抖动）
func emit_wave_at(pos: Vector2i, kind: int, count: int) -> void:
	var sx := pos.x
	var sy := pos.y
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


## 兵种爬升上限（climb_max）：单位 kind → 可跨的最大高度差
func climb_max_for(kind: int) -> int:
	return int(Sim.ENEMIES[kind - 1].get("climb_max", 2))


## 按兵种选主场：蛮兽（climb_max ≤ 1）走 field_heavy，其余走 field
func field_for(kind: int) -> FlowField:
	return field_heavy if climb_max_for(kind) <= 1 else field


## 按兵种选裸图基线场（口径与 field_for 对齐）
func bare_field_for(kind: int) -> FlowField:
	return bare_field_heavy if climb_max_for(kind) <= 1 else bare_field


## 有效绕行（decicell 当量）：已走格数×10 + 死位主场剩余距离 − 出生格裸图基线，负值归零。
## 任一端不可达（堵死的死位 / 开门陷阱流的出生口）记 0。平路直走怪严格为 0
## （每走一格剩余减 10、已走加 10）；爬坡边权 20 会引入每坡 ±10 的保守偏差（可接受）。
func effdetour(u: Dictionary) -> int:
	var rest := field_for(int(u["kind"])).dist_at(int(u["x"]), int(u["y"]))
	var base := int(u.get("bare_dist", -1))
	if rest < 0 or base < 0:
		return 0
	return maxi(int(u["traveled"]) * 10 + rest - base, 0)


## 击杀赏金加成：effdetour 折算，封顶 2×基础赏金
func bounty_bonus(u: Dictionary) -> int:
	var cap := int(Sim.ENEMIES[u["kind"] - 1]["reward"]) * Sim.BOUNTY_CAP_MULT
	return mini(Lua64.lshr(effdetour(u), bounty_shift), cap)


## 击杀赏金总额（基础 + 加成；表现层浮字与结算同口径）
func bounty_of(u: Dictionary) -> int:
	return int(Sim.ENEMIES[u["kind"] - 1]["reward"]) + bounty_bonus(u)


## 单位移动：沿对应主场流场走一格；封路分支处理啃建筑/转围攻
func move_units() -> void:
	for ui in units.size():
		var unit: Dictionary = units[ui]
		# 眩晕（完全冻结）：不动、不啃、攻击冷却也不走，只递减眩晕计数
		var stun: int = int(unit.get("stun", 0))
		if stun > 0:
			unit["stun"] = stun - 1
			continue
		if unit["atk_cd"] > 0:
			unit["atk_cd"] = unit["atk_cd"] - 1
		# 爬坡后摇：等待期间只递减计数，本 tick 不发步点
		var wait: int = int(unit.get("climb_wait", 0))
		if wait > 0:
			unit["climb_wait"] = wait - 1
			continue
		var spd: int = unit["speed_ticks"]
		var slow_left: int = int(unit.get("slow", 0))
		if slow_left > 0:
			unit["slow"] = slow_left - 1
			spd = spd * 2 # 减速：步点间隔翻倍（经典模式无 slow 键 ⇒ 恒走原值）
		if (tick_count + unit["id"]) % spd == 0: # 未到步点则跳过
			var ufield := field_for(int(unit["kind"]))
			var dir := ufield.dir_at(unit["x"], unit["y"])
			if dir >= 0:
				var nx: int = Grid.nx(unit["x"], unit["y"], dir)
				var ny: int = Grid.ny(unit["x"], unit["y"], dir)
				if grid.passable(nx, ny):
					var dh: int = grid.get_h(nx, ny) - grid.get_h(unit["x"], unit["y"])
					unit["x"] = nx
					unit["y"] = ny
					if dh > 0:
						unit["climb_wait"] = dh * Sim.CLIMB_EXTRA_TICKS
					unit["traveled"] = unit["traveled"] + 1
					unit["stuck_ticks"] = 0
					unit["atk_target"] = -1
				else:
					stuck_branch(unit)
			elif ufield.dist_at(unit["x"], unit["y"]) == 0:
				pass # 已抵达目标格（核心脚下），正常待机
			else:
				stuck_branch(unit)


## 被封分支：贴脸有建筑就啃；啃不到且真被围死 → 沿对应围攻场推进。
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
	var sfield := ensure_siege(int(unit["kind"]))
	var sdir := sfield.dir_at(unit["x"], unit["y"])
	if sdir < 0:
		return # 全场无可攻目标（核心已毁等）→ 原地待命
	var mx: int = Grid.nx(unit["x"], unit["y"], sdir)
	var my: int = Grid.ny(unit["x"], unit["y"], sdir)
	if grid.passable(mx, my):
		var dh: int = grid.get_h(mx, my) - grid.get_h(unit["x"], unit["y"])
		unit["x"] = mx
		unit["y"] = my
		if dh > 0:
			unit["climb_wait"] = dh * Sim.CLIMB_EXTRA_TICKS
		unit["traveled"] = unit["traveled"] + 1 # 被围死后的绕行也是"在玩家地图上走路"，照计路程
		unit["atk_target"] = find_attack_target(unit)


## 围攻场：目标 = 全部存活建筑格（含核心）。按兵种爬升上限选场；拓扑或建筑表变化时才重建。
## @return 该兵种对应的围攻场
func ensure_siege(kind: int) -> FlowField:
	var heavy := climb_max_for(kind) <= 1
	if heavy:
		if siege_heavy == null:
			siege_heavy = FlowField.new(grid, false, 1)
	else:
		if siege == null:
			siege = FlowField.new(grid)
	var f: FlowField = siege_heavy if heavy else siege
	var stamp := next_building_id
	if heavy:
		if siege_heavy_rev == grid.rev and siege_heavy_stamp == stamp:
			return f
	else:
		if siege_rev == grid.rev and siege_stamp == stamp:
			return f
	var goals := []
	for i in buildings.size():
		var b: Dictionary = buildings[i]
		if b["hp"] > 0:
			goals.append(Vector2i(b["x"], b["y"]))
	f.begin(goals)
	while not f.done():
		f.step(1 << 30)
	if heavy:
		siege_heavy_rev = grid.rev
		siege_heavy_stamp = stamp
	else:
		siege_rev = grid.rev
		siege_stamp = stamp
	return f


## 震荡波：半径（平方距离口径，与拓扑无关）内敌人击退 2 格并眩晕（STUN_TICKS 完全冻结）；
## 每步落点须可通行、无单位且高度边合法（可震下崖、不可推上崖），方向按当前位逐格重算。
## 不改地形、不耗 Rng；冷却期命令为 Nop（零副作用）。
## 六边击退方向 = 轴向差的主轴符号（|dq|→|dr|→|ds| 平手优先，确定性）。
func cast_shock() -> void:
	hero["skill_cd"] = hero_cd_max
	var r2: int = hero_radius * hero_radius
	for i in units.size():
		var u: Dictionary = units[i]
		var dx: int = u["x"] - hero["x"]
		var dy: int = u["y"] - hero["y"]
		var d2: int = dx * dx + dy * dy
		if u["hp"] > 0 and d2 > 0 and d2 <= r2:
			u["stun"] = Sim.STUN_TICKS
			for _step in 2:
				var k := _push_dir(u["x"], u["y"])
				var nx: int = Grid.nx(u["x"], u["y"], k)
				var ny: int = Grid.ny(u["x"], u["y"], k)
				if grid.passable(nx, ny) and cell_vacant(nx, ny) and grid.get_h(nx, ny) - grid.get_h(u["x"], u["y"]) <= 1:
					u["x"] = nx
					u["y"] = ny


## 击退方向：单位与英雄轴向差的主轴符号（背离英雄），平手按 |dq|→|dr|→|ds| 优先
func _push_dir(x: int, y: int) -> int:
	var ua := Grid.to_axial(x, y)
	var ha := Grid.to_axial(hero["x"], hero["y"])
	var dq: int = ua.x - ha.x
	var dr: int = ua.y - ha.y
	var ds: int = -(dq + dr)
	if absi(dq) >= absi(dr) and absi(dq) >= absi(ds):
		return 0 if dq > 0 else 3 # E / W
	elif absi(dr) >= absi(ds):
		return 5 if dr > 0 else 2 # SE / NW
	else:
		return 4 if ds > 0 else 1 # SW / NE


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
	var nx: int = Grid.nx(hero["x"], hero["y"], dir)
	var ny: int = Grid.ny(hero["x"], hero["y"], dir)
	if grid.passable(nx, ny):
		hero["x"] = nx
		hero["y"] = ny


# ---------------- 工人采运（采矿改形 C；固定次序 ③c，英雄步进之后、塔开火之前）----------------

## 出生：第 id 个可行核心邻格（都是核心山头通行格）；worker 字典含派生态
## field/field_rev/field_goal/pick_rev（不进指纹，save 读档后重建）。
func _spawn_worker(id: int) -> void:
	var passables: Array = []
	for k in 6:
		var nx: int = Grid.nx(sc.core.x, sc.core.y, k)
		var ny: int = Grid.ny(sc.core.x, sc.core.y, k)
		if grid.passable(nx, ny):
			passables.append(Vector2i(nx, ny))
	var spot: Vector2i = passables[id % passables.size()] if not passables.is_empty() else Vector2i(sc.core.x, sc.core.y)
	workers.append({
		"id": id + 1,
		"x": spot.x,
		"y": spot.y,
		"state": Sim.W_TO_MINE,
		"target": -1, # sc.ore_cells 下标；-1 = 无活
		"carrying": 0,
		"mine_cd": 0,
		"field": null,
		"field_rev": -1,
		"field_goal": -1,
		"pick_rev": -1,
	})


## 每 tick 推进全部工人（确定性：表序即 id 序）
func worker_tick() -> void:
	for w in workers:
		if int(w["state"]) == Sim.W_MINING:
			_worker_mining(w)
		elif int(w["state"]) == Sim.W_TO_CORE:
			_worker_to_core(w)
		else:
			_worker_to_mine(w)


## MINING：站定在目标矿格上开采；满载或矿枯 → 回城
func _worker_mining(w: Dictionary) -> void:
	var t := int(w["target"])
	if t < 0:
		w["state"] = Sim.W_TO_MINE
		return
	var c: Vector2i = sc.ore_cells[t]
	if int(ore_left.get(grid.idx(c.x, c.y), 0)) <= 0 or grid.at(c.x, c.y) != Grid.OPEN:
		w["state"] = Sim.W_TO_CORE if int(w["carrying"]) > 0 else Sim.W_TO_MINE
		return
	if int(w["carrying"]) >= Sim.WORKER_LOAD:
		w["state"] = Sim.W_TO_CORE
		return
	var cd := int(w["mine_cd"]) - 1
	if cd <= 0:
		var take: int = mini(Sim.ORE_RATE, mini(int(ore_left[grid.idx(c.x, c.y)]), Sim.WORKER_LOAD - int(w["carrying"])))
		ore_left[grid.idx(c.x, c.y)] = int(ore_left[grid.idx(c.x, c.y)]) - take
		w["carrying"] = int(w["carrying"]) + take
		cd = Sim.ORE_RATE_TICKS
	w["mine_cd"] = cd


## TO_CORE：沿主战场回核心；贴邻核心即入账（核心格实心，最近只能站到邻格）
func _worker_to_core(w: Dictionary) -> void:
	if int(w["carrying"]) <= 0:
		w["state"] = Sim.W_TO_MINE
		w["target"] = -1
		return
	if Grid.hex_dist(int(w["x"]), int(w["y"]), sc.core.x, sc.core.y) == 1:
		supply += int(w["carrying"])
		w["carrying"] = 0
		w["state"] = Sim.W_TO_MINE
		w["target"] = -1
		return
	_worker_step(w, field_for(Sim.E_SWARM))


## TO_MINE：沿单目标场走向矿格；到场转 MINING；目标失效/不可达时重挑
func _worker_to_mine(w: Dictionary) -> void:
	var t := int(w["target"])
	var t_bad: bool = t < 0 or int(ore_left.get(grid.idx(sc.ore_cells[t].x, sc.ore_cells[t].y), 0)) <= 0 \
			or grid.at(sc.ore_cells[t].x, sc.ore_cells[t].y) != Grid.OPEN
	if t_bad and int(w["pick_rev"]) != grid.rev:
		_worker_pick(w)
		w["pick_rev"] = grid.rev
		t = int(w["target"])
		if t < 0:
			return # 无活可干：原地待命（rev 再变才重挑）
	if int(w["field_rev"]) != grid.rev or int(w["field_goal"]) != t:
		var f := FlowField.new(grid, false, 2) # 工人爬 2 级（虫群口径）
		f.begin([Vector2i(sc.ore_cells[t].x, sc.ore_cells[t].y)])
		while not f.done():
			f.step(1 << 30)
		w["field"] = f
		w["field_rev"] = grid.rev
		w["field_goal"] = t
	var wf: FlowField = w["field"]
	var d: int = wf.dist_at(int(w["x"]), int(w["y"]))
	if d == 0:
		w["state"] = Sim.W_MINING
		w["mine_cd"] = 0
	elif d < 0:
		# 目标被墙隔断：本 rev 内重挑一次（pick 自带可达性校验），仍无解则待命等墙开
		if int(w["pick_rev"]) != grid.rev:
			w["pick_rev"] = grid.rev
			_worker_pick(w)
	else:
		_worker_step(w, wf)


## 选目标：已挖开且有余量的矿格中，取工人位置 hex_dist 最近者（平手取 ore_cells 序）；
## 逐个建单目标场校验可达性（密封盆地/被墙隔断的自动跳过），首个可达者即目标。
func _worker_pick(w: Dictionary) -> void:
	w["target"] = -1
	var cand: Array = []
	for i in sc.ore_cells.size():
		var c: Vector2i = sc.ore_cells[i]
		if int(ore_left.get(grid.idx(c.x, c.y), 0)) > 0 and grid.at(c.x, c.y) == Grid.OPEN:
			cand.append([Grid.hex_dist(int(w["x"]), int(w["y"]), c.x, c.y), i])
	cand.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	for cd in cand:
		var i: int = cd[1]
		var c: Vector2i = sc.ore_cells[i]
		var f := FlowField.new(grid, false, 2)
		f.begin([c])
		while not f.done():
			f.step(1 << 30)
		if f.dist_at(int(w["x"]), int(w["y"])) >= 0:
			w["target"] = i
			w["field"] = f
			w["field_rev"] = grid.rev
			w["field_goal"] = i
			return


## 工人步进（步点口径同单位：(tick+id) % 速度 == 0）；沿给定场走一格（落点必须可通行）
func _worker_step(w: Dictionary, f: FlowField) -> void:
	if (tick_count + int(w["id"])) % Sim.WORKER_SPEED_TICKS != 0:
		return
	var dir: int = f.dir_at(int(w["x"]), int(w["y"]))
	if dir < 0:
		return # 待命（被封路等）
	var nx: int = Grid.nx(int(w["x"]), int(w["y"]), dir)
	var ny: int = Grid.ny(int(w["x"]), int(w["y"]), dir)
	if grid.passable(nx, ny):
		w["x"] = nx
		w["y"] = ny


## 邻格里挑"拆掉最划算"的建筑：以该建筑周边的最小场距打分，平手取方向序最小。
func find_attack_target(unit: Dictionary) -> int:
	var best = null
	var best_score := INT64_MAX
	for k in 6:
		var nx: int = Grid.nx(unit["x"], unit["y"], k)
		var ny: int = Grid.ny(unit["x"], unit["y"], k)
		var b = building_at(nx, ny)
		if b != null and b["hp"] > 0:
			var score := score_around(nx, ny, int(unit["kind"]))
			if score < best_score:
				best_score = score
				best = b
	return best["id"] if best != null else -1


## 围点评分 = 自身与六邻到目标的最小流场距离（NEAREST 塔选围攻点的依据）。
## 距离取该兵种对应的主场场（爬升上限不同 → 场不同）。
func score_around(x: int, y: int, kind: int) -> int:
	var f := field_for(kind)
	var best := INT64_MAX
	var self_d := f.dist_at(x, y)
	if self_d >= 0:
		best = self_d
	for k in 6:
		var d := f.dist_at(Grid.nx(x, y, k), Grid.ny(x, y, k))
		if d >= 0 and d < best:
			best = d
	return best


## 界外恒无建筑（复刻 World.At 的口径；grid:idx 对界外会算出环绕碰撞下标，必须先判界）。
func building_at(x: int, y: int):
	if not grid.inb(x, y):
		return null
	return by_cell.get(grid.idx(x, y))


## 扣建筑血量：归零即拆除（核心毁 = 判负；塌墙恢复 Open，流场当 tick 追平）
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
				var def: Dictionary = bdef(int(b["kind"]))
				if def["shoots"]:
					if b["cooldown"] > 0:
						b["cooldown"] = b["cooldown"] - 1
					else:
						var beh: String = String(def.get("behavior", ""))
						if beh != "":
							fire_behavior(b, def, beh) # 肉鸽扩展塔；经典塔无此字段
							continue
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
								# 改道经济：赏金 = 基础 + 有效绕行折算；只有塔火能兑现
								var bonus := bounty_bonus(best_u)
								supply += Sim.ENEMIES[best_u["kind"] - 1]["reward"] + bonus
								convoy_earned += bonus
								kills += 1


## 单位受伤与击杀结算（肉鸽扩展塔共用）。经典模式不经过本函数，故不进指纹。
## 赏金口径与塔火一致：基础赏金 + 有效绕行折算（封顶 2×基础）。
func damage_unit(u: Dictionary, dmg: int) -> void:
	u["hp"] = u["hp"] - dmg
	if u["hp"] <= 0:
		var bonus := bounty_bonus(u)
		supply += Sim.ENEMIES[u["kind"] - 1]["reward"] + bonus
		convoy_earned += bonus
		kills += 1


## 扩展塔开火（肉鸽模式专用）。经典模式 btab 为空 ⇒ 无任何塔带 behavior 字段，
## 本函数永不被调用，16 指纹零影响。
##   slow   = 命中最近目标并附加减速（目标 slow 剩余 tick = def.slow_ticks）
##   aoe    = 射程内全部目标受同等伤害
##   pierce = 射程内最近 pierce_n 个目标各受一次伤害
func fire_behavior(b: Dictionary, def: Dictionary, beh: String) -> void:
	var r2: int = def["range"] * def["range"]
	var dmg: int = def["damage"]
	var scored: Array = []
	for ui in units.size():
		var un: Dictionary = units[ui]
		if un["hp"] <= 0:
			continue
		var dx: int = un["x"] - b["x"]
		var dy: int = un["y"] - b["y"]
		var d2: int = dx * dx + dy * dy
		if d2 <= r2:
			scored.append([d2, int(un["id"]), un])
	if scored.is_empty():
		return
	scored.sort_custom(func(a: Array, c: Array) -> bool:
		if int(a[0]) != int(c[0]):
			return int(a[0]) < int(c[0])
		return int(a[1]) < int(c[1]))
	if beh == "aoe":
		for it in scored:
			damage_unit(it[2], dmg)
		b["cooldown"] = def["cooldown"]
		return
	var count: int = 1
	if beh == "pierce":
		count = int(def.get("pierce_n", 3))
	for k in mini(count, scored.size()):
		var target: Dictionary = scored[k][2]
		damage_unit(target, dmg)
		if beh == "slow":
			target["slow"] = int(def.get("slow_ticks", 40))
	b["cooldown"] = def["cooldown"]


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


# ---------------- 规范状态编码（STATE_SCHEMA=11）----------------
# tick | rng | grid | 供给/结局/开门/战果 | 单位表按 id 升序 | 建筑表按 id 升序。
# 流场是派生态，不进指纹。
## 规范状态编码：字段序 = tick|rng|grid|供给/结局/开门/战果|单位表|建筑表（指纹口径）
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
		b.put_u8(Grid.h_to_u8(grid.hgt[i])) # 高度层（玩家可改造，进指纹；u8 偏移编码支持负高度）
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
		b.put_i32(u["climb_wait"]) # v7：爬坡后摇剩余 tick
		b.put_i32(u["bare_dist"]) # v8：出生格裸图基线路程（不可达 -1）
		b.put_i32(u["stun"]) # v10：眩晕剩余 tick

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
		b.put_i32(s["paid"]) # v9：实付造价（墙为阶梯价当次值，退款口径）

	b.put_u8(1) # 英雄恒在（Jam 版无死亡）
	b.put_i32(hero["x"])
	b.put_i32(hero["y"])
	b.put_i32(hero["tx"])
	b.put_i32(hero["ty"])
	b.put_i32(hero["skill_cd"])
	b.put_i32(convoy_earned) # v4：绕行赏金累计
	b.put_u32(workers.size()) # v11：工人采运
	for w in workers:
		b.put_i32(w["id"])
		b.put_i32(w["x"])
		b.put_i32(w["y"])
		b.put_u8(w["state"])
		b.put_i32(w["target"])
		b.put_i32(w["carrying"])
		b.put_i32(w["mine_cd"])
	b.put_u32(sc.ore_cells.size()) # v11：矿格余量（sc.ore_cells 位置序）
	for i in sc.ore_cells.size():
		b.put_i32(int(ore_left.get(grid.idx(sc.ore_cells[i].x, sc.ore_cells[i].y), 0)))
	return b


## 计算 FNV-1a 指纹（经 canonical_bytes 编码）
func fingerprint() -> int:
	return canonical_bytes().fingerprint()
