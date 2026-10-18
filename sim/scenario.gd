class_name Scenario
extends RefCounted

# 数值表 + 64² 程序化布局（2026-10-16 世界生成：手搓夹具 → MapGen 变奏级生成；
# 2026-10-17 G2：MapGen 升级五模板池，本文件负责按参数建图/校验，结构面见 mapgen.gd）。
# 固定结构元素：核心在北岸中上；屏障带横贯（双咽喉口 ±1 宽 3，形状随模板 T0..T4）；
# 南岸双出怪口；西南盆地密闭岩环（插口是唯一覆盖格，内部藏矿）= 开门陷阱；中场安全矿；南场 2×2 微丘。
# 生成纪律：布局纯整数（sim Rng 采样，见 mapgen.gd）；本文件负责「采样 → 结构不变量校验 →
# 失败换盐重采样 ≤64 次」。校验口径（check_grid / check_plug_open）同时是测试的读取面。
# 波次表与固定节奏（end_tick/trickle 等）不参与变奏。

const DEFAULT_SEED := 20261003
# 裸图路径长标定（2026-10-16 手搓夹具实测，FlowField 直/斜 10/14 口径）：两主口 = 548。
# 生成地图两主口路径长必须落在 ±15% 带内（难度不许因布局漂移）。
const PATH_REF := 548
const PATH_LO := 466 # PATH_REF × 0.85
const PATH_HI := 630 # PATH_REF × 1.15
const RESAMPLE_MAX := 64

# 布局缓存：同 seed 的「已校验参数」进程内复用（校验含两次流场全展开，不便宜）。
static var _layout_cache: Dictionary = {}

var seed: int
var w: int
var h: int
var core: Vector2i
var hero_spawn: Vector2i
var spawns: Array # 出怪口下标 1 基：1=西咽喉外、2=东咽喉外、3=盆地内（玩家自己挖开插口才生效）
var basin_plug: Vector2i
var basin_rect: Rect2i # 盆地外环矩形（含环：四周各一圈）
var mid_ore: Array # 中场矿（安全保底，北岸）
var basin_ore: Array # 盆地矿（诱饵：挖插口才够得着；盆地口压在矿格上）
var ore_cells: Array # = basin_ore + mid_ore（指纹与 is_ore 读取序）
var waves: Array # 条目 = [tick, 出怪口(1基), 敌型, 数量]
var end_tick: int
var hard_cap_tick: int
var trickle_every: int
var wave_scale_pct: int
var template_id: int # 布局模板（0 横脊 / 1 错行双脊 / 2 弧脊 / 3 斜壁 / 4 獠牙翼；不进指纹，形状已由高度/咽喉入口径覆盖）
var ridge_y: int # 屏障基准行：T0/T4 = 屏障首行；T1 = 西带首行；T2/T3 = 列行公式基点（中列附近）
var chokes: Array # [Vector2i(口心 x, 口行 y) × 2]（西、东；口行 = 该列屏障顶行）
var sparse_phase: int # 表土纹理相位（y=17 行，x % 9 == phase 为覆盖格）
var mesa: Rect2i # 南场微丘（2×2，h1）
var resample_salt: int # 实际采用的盐（诊断用；不进指纹：布局由参数完全决定）
var _p: Dictionary # 本局布局参数（MapGen 产物；模板几何静态面的查询源）
var _barrier: Dictionary # 屏障 SOLID 集合（已扣咽喉缺口；"x,y" 键）


## 构造剧本：固定节拍/波表常量 + 按 seed 生成布局参数（MapGen）并自校验
func _init(p_seed: int = DEFAULT_SEED) -> void:
	seed = p_seed
	w = 64
	h = 64
	end_tick = 6400
	hard_cap_tick = 8800
	trickle_every = 300 # 开门后每 300 tick 从盆地渗 2 只虫群（开门有代价，但可守）
	wave_scale_pct = 100
	# 同波多条目错开 15~30 tick：怪列成"流"而不是团（总量 200 只；不随布局变奏）
	waves = [
		[60, 1, Sim.E_SWARM, 1],
		[160, 1, Sim.E_SWARM, 1],
		[260, 1, Sim.E_SWARM, 1],
		[360, 1, Sim.E_SWARM, 1],
		[800, 1, Sim.E_SWARM, 10],
		[830, 2, Sim.E_SWARM, 6],
		[1700, 1, Sim.E_SWARM, 14],
		[1700, 2, Sim.E_SWARM, 10],
		[1850, 2, Sim.E_BEHEMOTH, 1],
		[2700, 1, Sim.E_SWARM, 14],
		[2700, 2, Sim.E_SWARM, 12],
		[2850, 1, Sim.E_SWARM, 4],
		[2850, 2, Sim.E_BEHEMOTH, 2],
		[3700, 1, Sim.E_SWARM, 14],
		[3700, 2, Sim.E_SWARM, 14],
		[3850, 1, Sim.E_SWARM, 10],
		[3850, 2, Sim.E_BEHEMOTH, 3],
		[4700, 1, Sim.E_SWARM, 14],
		[4715, 1, Sim.E_SWARM, 14],
		[4730, 1, Sim.E_SWARM, 12],
		[4700, 2, Sim.E_SWARM, 12],
		[4715, 2, Sim.E_SWARM, 12],
		[4730, 2, Sim.E_SWARM, 10],
		[4860, 1, Sim.E_BEHEMOTH, 4],
		[4860, 2, Sim.E_BEHEMOTH, 4],
	]
	if Scenario._layout_cache.has(p_seed):
		var cached: Array = Scenario._layout_cache[p_seed]
		_apply_layout(cached[0])
		resample_salt = cached[1]
		return
	for attempt in RESAMPLE_MAX:
		var params := MapGen.generate(p_seed, attempt, p_seed == DEFAULT_SEED)
		_apply_layout(params)
		if _validate_layout():
			resample_salt = attempt
			Scenario._layout_cache[p_seed] = [params, attempt]
			return
	assert(false, "[scenario] 布局 %d 次重采样仍不合法 seed=%d（生成器/不变量坏了）" % [RESAMPLE_MAX, p_seed])


## 布局参数 → 实例字段（纯赋值，不校验）。屏障蒙版 = 模板带 − 咽喉缺口 + 附壁。
func _apply_layout(p: Dictionary) -> void:
	var cx: int = p["core_x"]
	_p = p
	template_id = int(p.get("template", 0))
	ridge_y = p["ridge_y"]
	var gr: Array = MapGen.gate_rows(p)
	chokes = [Vector2i(p["choke_west"], int(gr[0])), Vector2i(p["choke_east"], int(gr[1]))]
	core = Vector2i(cx, 6)
	hero_spawn = Vector2i(cx, 8) # 核心门前两格（build_grid 强制 OPEN）
	spawns = [
		Vector2i(cx - 12, 56), # 西咽喉外
		Vector2i(cx + 12, 56), # 东咽喉外
		Vector2i(p["basin_x0"] + 3, p["basin_y0"] + 4), # 盆地内（压在矿格上）
	]
	basin_rect = Rect2i(p["basin_x0"], p["basin_y0"], p["basin_w"], p["basin_h"])
	basin_plug = Vector2i(p["basin_x0"] + p["plug_dx"], p["basin_y0"])
	basin_ore = []
	for x in range(p["basin_x0"] + 2, p["basin_x0"] + 5):
		for y in range(p["basin_y0"] + 3, p["basin_y0"] + 7):
			basin_ore.append(Vector2i(x, y))
	mid_ore = []
	for x in range(cx - 2, cx + 3):
		mid_ore.append(Vector2i(x, p["mid_y"]))
	ore_cells = []
	ore_cells.append_array(basin_ore)
	ore_cells.append_array(mid_ore)
	sparse_phase = p["sparse_phase"]
	mesa = Rect2i(p["mesa_x"], p["mesa_y"], 2, 2)
	_barrier = {}
	for x in range(1, w - 1):
		var rows: Array = MapGen.band_rows(p, x)
		if rows.size() != 2:
			continue
		for y in range(int(rows[0]), int(rows[1]) + 1):
			if MapGen.carved(p, x, y):
				continue
			if x == basin_plug.x and y == basin_plug.y:
				continue # 插口是覆盖门：屏障让位（罕见贴环情形）
			_barrier[str(x) + "," + str(y)] = true
	for c in MapGen.extra_walls(p):
		_barrier[str(c.x) + "," + str(c.y)] = true


## 该列的咽喉口行（口心 ±1 列内，取其咽喉 c.y；否则 -1）。
func _gate_row_at(x: int) -> int:
	for c in chokes:
		if absi(x - c.x) <= 1:
			return c.y
	return -1


## 该列屏障顶行（无屏障列回退 ridge_y，保 x=0/63 边缘口径与 T0 逐位一致）。
func _barrier_top(x: int) -> int:
	var rows: Array = MapGen.band_rows(_p, x)
	if rows.size() == 2:
		return int(rows[0])
	return ridge_y


## 高度模板：北岸台地 h1；核心山头 h3 + 南向两级台阶（h2）；咽喉口行爬出 h1（随列屏障顶行，
## 北岸台地边界随之弯曲/升降）；南岸低地/咽喉谷道/盆地坑 h0；南场微丘（2×2）h1。
func height_at(x: int, y: int) -> int:
	if y <= 9 and x >= core.x - 3 and x <= core.x + 3:
		return 3
	if y <= 12 and x >= core.x - 2 and x <= core.x + 2:
		return 2
	if y == _gate_row_at(x):
		return 1 # 咽喉口
	if y <= _barrier_top(x) - 1:
		return 1
	if mesa.has_point(Vector2i(x, y)):
		return 1
	return 0


## 初始地形：三态一次性写入（命令层之后才登场）。
func build_grid() -> Grid:
	var g := Grid.new(w, h)
	var ore := {}
	for o in ore_cells:
		ore[str(o.x) + "," + str(o.y)] = true
	for y in h:
		for x in w:
			if x == 0 or y == 0 or x == w - 1 or y == h - 1:
				g.set_cell(x, y, Grid.SOLID)
			elif ore.has(str(x) + "," + str(y)):
				g.set_cell(x, y, Grid.COVER) # 矿格先于屏障判定，否则会被写成不可挖的实心
			elif _barrier.has(str(x) + "," + str(y)):
				g.set_cell(x, y, Grid.SOLID)
			elif basin_rect.has_point(Vector2i(x, y)):
				# 盆地：密闭岩环（只有插口是覆盖层），内部空腔藏矿与第三出怪口
				var ring := x == basin_rect.position.x or x == basin_rect.position.x + basin_rect.size.x - 1 \
					or y == basin_rect.position.y or y == basin_rect.position.y + basin_rect.size.y - 1
				if ring:
					g.set_cell(x, y, Grid.COVER if (x == basin_plug.x and y == basin_plug.y) else Grid.SOLID)
			elif y == 17 and x % 9 == sparse_phase:
				g.set_cell(x, y, Grid.COVER) # 稀疏表土纹理：可挖但不给矿，不遮挡咽喉与建造走廊
	g.set_cell(core.x, core.y, Grid.SOLID) # 核心占地
	g.set_cell(hero_spawn.x, hero_spawn.y, Grid.OPEN) # 英雄落位格恒通行
	for i in range(0, 2): # 主出怪口保持通行（盆地口不在此列）
		g.set_cell(spawns[i].x, spawns[i].y, Grid.OPEN)
	for y in h: # 高度模板（建图期写入，不参与 rev 计数口径）
		for x in w:
			g.init_h(x, y, height_at(x, y))
	return g


## 该格是否为矿格（静态数据，不进状态）。
func is_ore(x: int, y: int) -> bool:
	for o in ore_cells:
		if o.x == x and o.y == y:
			return true
	return false


# ============ 生成校验（不变量） ============

## 结构 + 连通性校验（生成重采样与测试共用；返回 "" = 合法）。
## 口径：边框实心属 build_grid 常量；凡「布局可观测」的玩意都在这里管。
func check_grid(g: Grid) -> String:
	# 1) 屏障形态：蒙版全实心；咽喉缺口（口心 ±1 × 该列屏障行）全通行、口心 h1
	for key in _barrier:
		var parts: PackedStringArray = String(key).split(",")
		if g.at(int(parts[0]), int(parts[1])) != Grid.SOLID:
			return "屏障格非实心 " + key
	for c in chokes:
		for dx in range(-1, 2):
			var rows: Array = MapGen.band_rows(_p, c.x + dx)
			if rows.size() != 2:
				continue
			for y in range(int(rows[0]), int(rows[1]) + 1):
				if not MapGen.carved(_p, c.x + dx, y):
					continue
				if g.at(c.x + dx, y) != Grid.OPEN:
					return "咽喉缺口未开 (%d,%d)" % [c.x + dx, y]
		if g.get_h(c.x, c.y) != 1:
			return "咽喉口高度破例 x=%d" % c.x
	# 3) 主出怪口 3×3 净空、英雄位通行、核心占位与山头
	for i in range(0, 2):
		var s: Vector2i = spawns[i]
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if g.at(s.x + dx, s.y + dy) != Grid.OPEN:
					return "出怪口 %d 净空破例 (%d,%d)" % [i + 1, s.x + dx, s.y + dy]
		if g.get_h(s.x, s.y) != 0:
			return "出怪口 %d 高度破例" % [i + 1]
	if g.at(hero_spawn.x, hero_spawn.y) != Grid.OPEN:
		return "英雄位被封 (%d,%d)" % [hero_spawn.x, hero_spawn.y]
	if g.at(core.x, core.y) != Grid.SOLID:
		return "核心格非实心"
	if g.get_h(core.x, core.y) != 3:
		return "核心山头 h3 破例"
	# 4) 矿：数目 / 占格 / 不压脊
	if mid_ore.size() != 5 or basin_ore.size() < 10:
		return "矿数破例 mid=%d basin=%d" % [mid_ore.size(), basin_ore.size()]
	for o in ore_cells:
		if g.at(o.x, o.y) != Grid.COVER:
			return "矿格非覆盖 (%d,%d)" % [o.x, o.y]
		if _barrier.has(str(o.x) + "," + str(o.y)):
			return "矿格压脊 (%d,%d)" % [o.x, o.y]
	# 5) 盆地环：周围一圈全实心、插口唯一覆盖格
	var b := basin_rect
	for y in range(b.position.y, b.position.y + b.size.y):
		for x in range(b.position.x, b.position.x + b.size.x):
			var edge := x == b.position.x or x == b.position.x + b.size.x - 1 \
				or y == b.position.y or y == b.position.y + b.size.y - 1
			if not edge:
				continue
			var want := Grid.SOLID
			if x == basin_plug.x and y == basin_plug.y:
				want = Grid.COVER
			if g.at(x, y) != want:
				return "盆地环破例 (%d,%d)" % [x, y]
	# 6) 内腔密闭（内腔任意非矿开格不可达 + 盆地口不可达）
	var ff := _dist_from_core(g)
	var probe := Vector2i(b.position.x + 1, b.position.y + b.size.y - 2)
	if ff.dist_at(probe.x, probe.y) != -1:
		return "盆地内腔未密闭 (%d,%d)" % [probe.x, probe.y]
	if ff.dist_at(spawns[2].x, spawns[2].y) != -1:
		return "盆地口未密闭"
	# 7) 主口路径长（裸图）：可达且落在标定带内
	for i in range(0, 2):
		var d := ff.dist_at(spawns[i].x, spawns[i].y)
		if d < 0:
			return "主出怪口 %d 不可达" % [i + 1]
		if d < PATH_LO or d > PATH_HI:
			return "路径长越界 %d: %d ∉ [%d,%d]" % [i + 1, d, PATH_LO, PATH_HI]
	return ""


## 全开门（插口 + 盆地矿全部挖开）后：盆地口（或其邻格）必须可达。
## 破坏性：会就地挖开插口与盆地矿（调用方传一次性网格）。
func check_plug_open(g: Grid) -> String:
	g.set_cell(basin_plug.x, basin_plug.y, Grid.OPEN)
	for o in basin_ore:
		g.set_cell(o.x, o.y, Grid.OPEN)
	var ff := _dist_from_core(g)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var c := Vector2i(spawns[2].x + dx, spawns[2].y + dy)
			if g.passable(c.x, c.y) and ff.dist_at(c.x, c.y) >= 0:
				return ""
	return "插口挖开后盆地口仍不可达"


## 核心为源的临时流场跑到收敛（布局自校验的距离场）
func _dist_from_core(g: Grid) -> FlowField:
	var ff := FlowField.new(g, false)
	ff.begin([core])
	while not ff.done():
		ff.step(1 << 20)
	return ff


## 布局自校验：建图合法 + 插口挖开后盆地口可达（默认种子必须全过）
func _validate_layout() -> bool:
	if check_grid(build_grid()) != "":
		return false
	return check_plug_open(build_grid()) == ""


## 剧本指纹：静态数据的 FNV-1a（换剧本/换布局种子必须换 baseline 的守门数据）。
## 2026-10-16 布局生成化后与 Lua 固定布局不再逐位同构；字段序 = seed 前置 + 原序 + 布局参数段。
func fingerprint(canon: Canon) -> int:
	var b := canon.buffer()
	b.put_i32(seed)
	b.put_i32(w)
	b.put_i32(h)
	b.put_i32(core.x)
	b.put_i32(core.y)
	b.put_i32(hero_spawn.x)
	b.put_i32(hero_spawn.y)
	b.put_i32(ridge_y)
	b.put_u32(chokes.size())
	for c in chokes:
		b.put_i32(c.x)
		b.put_i32(c.y)
	b.put_u32(spawns.size())
	for s in spawns:
		b.put_i32(s.x)
		b.put_i32(s.y)
	b.put_i32(basin_plug.x)
	b.put_i32(basin_plug.y)
	b.put_i32(basin_rect.position.x)
	b.put_i32(basin_rect.position.y)
	b.put_i32(basin_rect.size.x)
	b.put_i32(basin_rect.size.y)
	b.put_i32(sparse_phase)
	b.put_i32(mesa.position.x)
	b.put_i32(mesa.position.y)
	b.put_i32(end_tick)
	b.put_i32(hard_cap_tick)
	b.put_i32(trickle_every)
	b.put_i32(wave_scale_pct)
	for y in h: # 高度模板入指纹（换地形必须换基线）
		for x in w:
			b.put_u8(height_at(x, y))
	b.put_u32(ore_cells.size())
	for o in ore_cells:
		b.put_i32(o.x)
		b.put_i32(o.y)
	b.put_u32(waves.size())
	for wv in waves:
		b.put_i32(wv[0])
		b.put_i32(wv[1])
		b.put_i32(wv[2])
		b.put_i32(wv[3])
	return b.fingerprint()
