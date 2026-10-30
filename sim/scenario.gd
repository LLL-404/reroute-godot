class_name Scenario
extends RefCounted

# 数值表 + 64² 程序化布局（2026-10-16 世界生成：手搓夹具 → MapGen 变奏级生成；
# 2026-10-19 世界生成 2.0：非默认种子走 MapGen 自由路径——核心/2~3 主口/盆地陷阱/岩群/微丘
# 全部由种子决定；本文件负责按参数建图/校验（自由路径走 _apply_freeform + _check_freeform）。
# 不变量（自由路径）：核心六边半径 2/3/4 三级山头 + 主口 3×3 净空（h0）+ 裸图路径长标定带；
# 盆地密闭岩环（插口是唯一覆盖格、内部藏矿、盆地口压块心）= 开门陷阱；中场安全矿 5 格；
# 岩群/微丘占比带（生成器自检）+ 净空蒙版（生成器保证，Scenario 只读）。
# 生成纪律：布局纯整数（sim Rng 采样，见 mapgen.gd）；本文件负责「采样 → 结构不变量校验 →
# 失败换盐重采样 ≤64 次」。校验口径（check_grid / check_plug_open）同时是测试的读取面。
# 波次表与固定节奏（end_tick/trickle 等）不参与变奏。
# 默认种子（20261003）走 _generate_default + 旧结构校验：剧本指纹 0x7dea2b02 与黄金脚本零影响。

const DEFAULT_SEED := 20261003
# 裸图路径长标定（2026-10-16 手搓夹具实测，FlowField 直/斜 10/14 口径）：两主口 = 548。
# 生成地图两主口路径长必须落在 ±15% 带内（难度不许因布局漂移）。
const PATH_REF := 990 # 128 图 sweep 实测定案（六边距离度量非线性，见 §11.48）
const PATH_LO := 840 # PATH_REF × 0.85
const PATH_HI := 1140 # PATH_REF × 1.15
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
var gen_failed := false # 换盐耗尽仍无合法布局（本实例已回落到默认图；玩家种子由调用方顺延）
var terrain_kind: int # 基地地貌（MapGen.TERRAIN_PLAIN/CLIFF/SLOPE）
var _height: Array = [] # 生成高度数组（64×64；空 = 旧模板回落）
var _terrain_valid := false # 生成器地形统计自检结果（false = 换盐重采样）
var _p: Dictionary # 本局布局参数（MapGen 产物；模板几何静态面的查询源）
var _barrier: Dictionary # 屏障 SOLID 集合（已扣咽喉缺口；"x,y" 键；legacy 专用）
var _freeform := false # 自由路径标记（默认/legacy = false；分派 build/校验/指纹/出怪点）
var _gen_invalid := false # 生成器自检未过（仅盐重采样信号；apply 仍写全字段保证不崩）
var _rock_arr: Array = [] # 自由路径：岩群格（生成序，进指纹）
var _hill_arr: Array = [] # 自由路径：微丘格（h1；生成序，进指纹）
var _sparse_arr: Array = [] # 自由路径：散土格（生成序，进指纹）
var _rock := {} # 岩群 O(1) 查询表（build/校验热路径）
var _hill := {} # 微丘 O(1) 查询表
var _sparse := {} # 散土 O(1) 查询表


## 构造剧本：固定节拍/波表常量 + 按 seed 生成布局参数（MapGen）并自校验
func _init(p_seed: int = DEFAULT_SEED) -> void:
	seed = p_seed
	w = Dims.MAP_N # 2026-10-27 B1 尺寸单点化（sim/dims.gd 唯一真源）
	h = Dims.MAP_N
	end_tick = 8740 # 2026-10-28 开局成长改造：全表平移 +2340，自然终局 5:20→7:17
	hard_cap_tick = 11140 # 超时判负 9:17
	trickle_every = 300 # 开门后每 300 tick 从盆地渗 2 只虫群（开门有代价，但可守）
	wave_scale_pct = 100
	# 同波多条目错开 15~30 tick：怪列成"流"而不是团（总量 200 只；不随布局变奏）。
	# 2026-10-28 开局成长改造：全表 +2340（首波 3 秒→2 分钟），间隔与构成一字未动——
	# 开局 60 供给只够 2 矿工或 1 塔，采矿成长期需要这段窗。
	waves = [
		[2400, 1, Sim.E_SWARM, 1],
		[2500, 1, Sim.E_SWARM, 1],
		[2600, 1, Sim.E_SWARM, 1],
		[2700, 1, Sim.E_SWARM, 1],
		[3140, 1, Sim.E_SWARM, 10],
		[3170, 2, Sim.E_SWARM, 6],
		[4040, 1, Sim.E_SWARM, 14],
		[4040, 2, Sim.E_SWARM, 10],
		[4190, 2, Sim.E_BEHEMOTH, 1],
		[5040, 1, Sim.E_SWARM, 14],
		[5040, 2, Sim.E_SWARM, 12],
		[5190, 1, Sim.E_SWARM, 4],
		[5190, 2, Sim.E_BEHEMOTH, 2],
		[6040, 1, Sim.E_SWARM, 14],
		[6040, 2, Sim.E_SWARM, 14],
		[6190, 1, Sim.E_SWARM, 10],
		[6190, 2, Sim.E_BEHEMOTH, 3],
		# 末波阶段化（2026-10-25 刀③）：82 只拉到 380t 窗口（批间隔 80t）、
		# 蛮兽殿后——「末波是几何题不是经济题」的修正：分散的运河塔阵也有时间磨完
		[7040, 1, Sim.E_SWARM, 12],
		[7120, 1, Sim.E_SWARM, 12],
		[7200, 1, Sim.E_SWARM, 12],
		[7040, 2, Sim.E_SWARM, 12],
		[7120, 2, Sim.E_SWARM, 12],
		[7200, 2, Sim.E_SWARM, 14],
		[7340, 1, Sim.E_BEHEMOTH, 4],
		[7420, 2, Sim.E_BEHEMOTH, 4],
	]
	if _resolve_layout(p_seed):
		return
	# 换盐耗尽：不崩对象（玩家种子由调用方顺延），标记失败并回落到默认图保证实例可用；
	# 此时本图 ≠ 请求种子，调用方应提示实际采用的种子。
	gen_failed = true
	push_error("[scenario] 布局 %d 次重采样仍不合法 seed=%d" % [RESAMPLE_MAX, p_seed])
	_resolve_layout(DEFAULT_SEED)


## 按 seed 解析布局：缓存命中直接应用；否则逐盐生成 → 生成器自检筛 → 附地形 → 应用 → 校验，
## 成功写缓存并记 resample_salt 返回 true；64 盐耗尽返回 false（不 assert、不写缓存）。
func _resolve_layout(p_seed: int) -> bool:
	if Scenario._layout_cache.has(p_seed):
		var cached: Array = Scenario._layout_cache[p_seed]
		_apply_layout(cached[0])
		resample_salt = cached[1]
		return true
	for attempt in RESAMPLE_MAX:
		var params := MapGen.generate_layout(p_seed, attempt, p_seed == DEFAULT_SEED)
		# 2026-10-24 性能：生成器自检（岩/丘/散土占比）与地形无关，先用它筛掉这批废盐
		# （实测约占失败盐的八成）→ 省掉每次约 150ms 的地形场计算；选盐与产物完全不变。
		if not bool(params.get("valid", true)):
			continue
		params = MapGen.attach_terrain(p_seed, attempt, params, p_seed == DEFAULT_SEED)
		_apply_layout(params)
		if _validate_layout():
			resample_salt = attempt
			Scenario._layout_cache[p_seed] = [params, attempt]
			return true
	return false


## 该种子能否长出合法布局（开局选种用；命中缓存时几乎零成本）。
## 用临时实例探一次：失败实例已回落到默认图并置 gen_failed，故只看标记。
static func usable(p_seed: int) -> bool:
	return not Scenario.new(p_seed).gen_failed


## 布局参数 → 实例字段（纯赋值，不校验）。自由路径与旧模板分派。
func _apply_layout(p: Dictionary) -> void:
	if bool(p.get("freeform", false)):
		_apply_freeform(p)
		return
	_apply_legacy(p)


## 旧模板路径 → 实例字段。屏障蒙版 = 模板带 − 咽喉缺口 + 附壁。
func _apply_legacy(p: Dictionary) -> void:
	var cx: int = p["core_x"]
	_p = p
	# 重采样可能先试过自由路径：回落到 legacy 时必须清掉自由路径标记与地貌集合，
	# 否则 build_grid/校验/指纹会拿上一轮的自由地貌当 legacy 用。
	_freeform = false
	_gen_invalid = false
	_rock_arr = []
	_hill_arr = []
	_sparse_arr = []
	_rock = {}
	_hill = {}
	_sparse = {}
	terrain_kind = int(p.get("terrain_kind", MapGen.TERRAIN_PLAIN))
	_height = p.get("heights", [])
	_terrain_valid = bool(p.get("terrain_valid", false))
	template_id = int(p.get("template", 0))
	ridge_y = p["ridge_y"]
	var gr: Array = MapGen.gate_rows(p)
	chokes = [Vector2i(p["choke_west"], int(gr[0])), Vector2i(p["choke_east"], int(gr[1]))]
	core = Vector2i(cx, 12)
	hero_spawn = Vector2i(cx, 16) # 核心门前两格（build_grid 强制 OPEN；128 锚 ×2）
	spawns = [
		Vector2i(cx - 24, 112), # 西咽喉外
		Vector2i(cx + 24, 112), # 东咽喉外
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


## 自由路径参数 → 实例字段（纯赋值；valid=false 只置标记，校验直接拒）。
## 出怪口约定：spawns 末位恒为盆地口（波次 id 1/2 打主口、渗怪走末位）。
func _apply_freeform(p: Dictionary) -> void:
	_freeform = true
	_gen_invalid = not bool(p.get("valid", true))
	_p = p
	terrain_kind = int(p.get("terrain_kind", MapGen.TERRAIN_PLAIN))
	_height = p.get("heights", [])
	_terrain_valid = bool(p.get("terrain_valid", false))
	template_id = -1
	ridge_y = -1 # 自由路径无单一脊线（视觉锚点回落预设，见 main._visual_anchor）
	chokes = []
	core = Vector2i(int(p["core_x"]), int(p["core_y"]))
	hero_spawn = Vector2i(int(p["hero_x"]), int(p["hero_y"]))
	spawns = []
	for m in p["mains"]:
		spawns.append(Vector2i(m.x, m.y))
	spawns.append(Vector2i(p["basin_spawn"].x, p["basin_spawn"].y))
	basin_rect = Rect2i(int(p["basin_x0"]), int(p["basin_y0"]), int(p["basin_w"]), int(p["basin_h"]))
	basin_plug = Vector2i(int(p["plug_x"]), int(p["plug_y"]))
	basin_ore = []
	for o in p["basin_ore"]:
		basin_ore.append(Vector2i(o.x, o.y))
	mid_ore = []
	for o in p["mid_ore"]:
		mid_ore.append(Vector2i(o.x, o.y))
	ore_cells = []
	ore_cells.append_array(basin_ore)
	ore_cells.append_array(mid_ore)
	sparse_phase = -1
	mesa = Rect2i(-1, -1, 0, 0)
	_barrier = {}
	_rock_arr = []
	_hill_arr = []
	_sparse_arr = []
	_rock = {}
	_hill = {}
	_sparse = {}
	for c in p["rocks"]:
		_rock_arr.append(Vector2i(c.x, c.y))
		_rock[str(c.x) + "," + str(c.y)] = true
	for c in p["hills"]:
		_hill_arr.append(Vector2i(c.x, c.y))
		_hill[str(c.x) + "," + str(c.y)] = true
	for c in p["sparse"]:
		_sparse_arr.append(Vector2i(c.x, c.y))
		_sparse[str(c.x) + "," + str(c.y)] = true


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


## 高度读取：生成期高度数组优先（2026-10-23 随机地形）；数组缺失时保留旧模板口径作保险。
func height_at(x: int, y: int) -> int:
	if _height.size() == w * h:
		return int(_height[y * w + x])
	if _freeform:
		var d := Grid.hex_dist(x, y, core.x, core.y)
		if d <= 2:
			return 3
		if d == 3:
			return 2
		if d == 4:
			return 1
		if _hill.has(str(x) + "," + str(y)):
			return 1
		return 0
	if y <= 18 and x >= core.x - 6 and x <= core.x + 6:
		return 3
	if y <= 24 and x >= core.x - 4 and x <= core.x + 4:
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
			elif _rock.has(str(x) + "," + str(y)):
				g.set_cell(x, y, Grid.SOLID) # 自由路径岩群（legacy 路径 _rock 恒空）
			elif _barrier.has(str(x) + "," + str(y)):
				g.set_cell(x, y, Grid.SOLID)
			elif basin_rect.has_point(Vector2i(x, y)):
				# 盆地：密闭岩环（只有插口是覆盖层），内部空腔藏矿与第三出怪口
				var ring := x == basin_rect.position.x or x == basin_rect.position.x + basin_rect.size.x - 1 \
					or y == basin_rect.position.y or y == basin_rect.position.y + basin_rect.size.y - 1
				if ring:
					g.set_cell(x, y, Grid.COVER if (x == basin_plug.x and y == basin_plug.y) else Grid.SOLID)
			elif _sparse.has(str(x) + "," + str(y)):
				g.set_cell(x, y, Grid.COVER) # 自由路径散土（legacy 路径 _sparse 恒空）
			elif not _freeform and y == 34 and x % 9 == sparse_phase:
				g.set_cell(x, y, Grid.COVER) # 稀疏表土纹理：可挖但不给矿，不遮挡咽喉与建造走廊
	g.set_cell(core.x, core.y, Grid.SOLID) # 核心占地
	g.set_cell(hero_spawn.x, hero_spawn.y, Grid.OPEN) # 英雄落位格恒通行
	for i in range(0, spawns.size() - 1): # 主出怪口保持通行（末位盆地口不在此列）
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


# ============ 出怪点解析（世界波次/渗怪共用） ============

## 波次表条目 entry_index 的出怪格。旧路径 = 历史口径逐位一致（id 1/2 → spawns[0/1]）。
## 三主口自由路径 = 按表序轮转三个主口（波表总量不变，负载均摊）。
func wave_cell(entry_index: int) -> Vector2i:
	var id: int = waves[entry_index][1]
	if not _freeform:
		return spawns[id - 1]
	var nm: int = spawns.size() - 1
	if nm <= 2:
		return spawns[id - 1]
	return spawns[entry_index % nm]


## 盆地口（spawns 末位）：渗怪与开门陷阱用。
func basin_cell() -> Vector2i:
	return spawns[spawns.size() - 1]


## 自由路径岩群格快照（生成序）：视觉层山体锚点用（只读拷贝；legacy 路径恒空）。
func rock_cells() -> Array:
	return _rock_arr.duplicate()


# ============ 生成校验（不变量） ============

## 结构 + 连通性校验（生成重采样与测试共用；返回 "" = 合法）。
## 口径：边框实心属 build_grid 常量；凡「布局可观测」的玩意都在这里管。
## 自由路径走 _check_freeform（同签名，测试读取面不变）。
func check_grid(g: Grid) -> String:
	if _freeform:
		return _check_freeform(g)
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
	# 3) 主出怪口 3×3 净空、英雄位通行、核心占位
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


## 自由路径结构校验（返回 "" = 合法）：主口净空/高度/间距、核心山头、矿数与可达、
## 盆地密闭（环 + 内腔 + 盆地口）、裸图路径标定带（所有主口）、生成器自检标记。
func _check_freeform(g: Grid) -> String:
	if _gen_invalid:
		return "生成器自检未过"
	var nm: int = spawns.size() - 1 # 主口数（末位 = 盆地口）
	# 1) 主口：3×3 净空、h0、彼此间距
	for i in nm:
		var s: Vector2i = spawns[i]
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if g.at(s.x + dx, s.y + dy) != Grid.OPEN:
					return "出怪口 %d 净空破例 (%d,%d)" % [i + 1, s.x + dx, s.y + dy]
		if g.get_h(s.x, s.y) != 0:
			return "出怪口 %d 高度破例" % [i + 1]
		for j in range(i + 1, nm):
			var t: Vector2i = spawns[j]
			if Grid.hex_dist(s.x, s.y, t.x, t.y) < MapGen.MAIN_GAP_MIN - 2:
				return "主口间距过近 %d-%d" % [i + 1, j + 1]
	# 2) 英雄位 / 核心山头
	if g.at(hero_spawn.x, hero_spawn.y) != Grid.OPEN:
		return "英雄位被封 (%d,%d)" % [hero_spawn.x, hero_spawn.y]
	if g.at(core.x, core.y) != Grid.SOLID:
		return "核心格非实心"
	# 3) 矿：数目 / 占格 / 不压岩
	if mid_ore.size() != 5 or basin_ore.size() < 10:
		return "矿数破例 mid=%d basin=%d" % [mid_ore.size(), basin_ore.size()]
	for o in ore_cells:
		if g.at(o.x, o.y) != Grid.COVER:
			return "矿格非覆盖 (%d,%d)" % [o.x, o.y]
		if _rock.has(str(o.x) + "," + str(o.y)):
			return "矿格压岩 (%d,%d)" % [o.x, o.y]
	# 3b) 地貌落格：岩群实心 / 散土覆盖 / 微丘 h1（生成器 ↔ 建图分工的读取面）
	if _rock_arr.is_empty() or _hill_arr.is_empty():
		return "地貌为空（岩/丘至少各一格）"
	for c in _rock_arr:
		if g.at(c.x, c.y) != Grid.SOLID:
			return "岩群格非实心 (%d,%d)" % [c.x, c.y]
	for c in _sparse_arr:
		if g.at(c.x, c.y) != Grid.COVER:
			return "散土格非覆盖 (%d,%d)" % [c.x, c.y]
	for c in _hill_arr:
		if g.get_h(c.x, c.y) != 1:
			return "微丘高度破例 (%d,%d)" % [c.x, c.y]
	# 4) 盆地环：一圈实心、插口唯一覆盖格
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
	# 5) 连通与路径（核心为源）：内腔/盆地口密闭、主口在标定带、中场矿邻格可达
	var ff := _dist_from_core(g)
	var probe := Vector2i(b.position.x + 1, b.position.y + b.size.y - 2)
	if ff.dist_at(probe.x, probe.y) != -1:
		return "盆地内腔未密闭 (%d,%d)" % [probe.x, probe.y]
	if ff.dist_at(spawns[nm].x, spawns[nm].y) != -1:
		return "盆地口未密闭"
	for i in nm:
		var d := ff.dist_at(spawns[i].x, spawns[i].y)
		if d < 0:
			return "主出怪口 %d 不可达" % [i + 1]
		if d < PATH_LO or d > PATH_HI:
			return "路径长越界 %d: %d ∉ [%d,%d]" % [i + 1, d, PATH_LO, PATH_HI]
	for o in mid_ore:
		var ok := false
		for k in 6:
			var ox := Grid.nx(o.x, o.y, k)
			var oy := Grid.ny(o.x, o.y, k)
			if g.passable(ox, oy) and ff.dist_at(ox, oy) >= 0:
				ok = true
				break
		if not ok:
			return "中场矿不可达 (%d,%d)" % [o.x, o.y]
	return ""


## 全开门（插口 + 盆地矿全部挖开）后：盆地口（或其邻格）必须可达。
## 破坏性：会就地挖开插口与盆地矿（调用方传一次性网格）。
func check_plug_open(g: Grid) -> String:
	g.set_cell(basin_plug.x, basin_plug.y, Grid.OPEN)
	for o in basin_ore:
		g.set_cell(o.x, o.y, Grid.OPEN)
	var ff := _dist_from_core(g)
	var bs: Vector2i = spawns[spawns.size() - 1] # 盆地口（末位）
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var c := Vector2i(bs.x + dx, bs.y + dy)
			if g.passable(c.x, c.y) and ff.dist_at(c.x, c.y) >= 0:
				return ""
	return "插口挖开后盆地口仍不可达"


## 核心为源的等权步数场（ignore_h=true，布局自校验的距离场）：
## 路径长/连通性/盆地密闭一律用「步数」口径，不吃爬坡代价（难度标定不漂移）。
func _dist_from_core(g: Grid) -> FlowField:
	var ff := FlowField.new(g, true)
	ff.begin([core])
	while not ff.done():
		ff.step(1 << 20)
	return ff


## 地形专项校验（公开读取面；返回 "" = 合法）：
## 生成器自检标记、统计带（非零/负值/h≥3）、基地地貌断言、虫群与蛮兽双可达、矿可采。
func check_terrain(g: Grid) -> String:
	if _gen_invalid or not _terrain_valid:
		return "地形自检未过"
	var nz := 0
	var neg := 0
	var hi := 0
	for y in h:
		for x in w:
			var v := height_at(x, y)
			if v != 0:
				nz += 1
			if v < 0:
				neg += 1
			if v >= 3:
				hi += 1
	var nz_perm := nz * 1000 / (w * h)
	var neg_perm := neg * 1000 / (w * h)
	if nz_perm < MapGen.TERRAIN_NZ_LO or nz_perm > MapGen.TERRAIN_NZ_HI:
		return "地形非零占比越带 %d‰" % nz_perm
	if neg_perm < MapGen.TERRAIN_NEG_LO or neg_perm > MapGen.TERRAIN_NEG_HI:
		return "地形负高度占比越带 %d‰" % neg_perm
	if hi < MapGen.TERRAIN_HI_MIN:
		return "地形无 h≥3 格"
	# 基地地貌断言
	var plain_zero := true
	var cliff_high := false
	var slope_nonzero := false
	for y in h:
		for x in w:
			var d := Grid.hex_dist(x, y, core.x, core.y)
			var v2 := height_at(x, y)
			if terrain_kind == MapGen.TERRAIN_PLAIN and d <= 5 and v2 != 0:
				plain_zero = false
			if terrain_kind == MapGen.TERRAIN_CLIFF and d >= 4 and d <= 6 and v2 >= 3:
				cliff_high = true
			if terrain_kind == MapGen.TERRAIN_SLOPE and d <= 3 and v2 != 0:
				slope_nonzero = true
	if terrain_kind == MapGen.TERRAIN_PLAIN and not plain_zero:
		return "平原核心 5 圈非全 0"
	if terrain_kind == MapGen.TERRAIN_CLIFF and not cliff_high:
		return "崖旁核心 4..6 圈无 h≥3"
	if terrain_kind == MapGen.TERRAIN_SLOPE and not slope_nonzero:
		return "山腰核心 3 圈全 0"
	# 双兵种可达：核心流场跑到收敛，所有主口（不含盆地口）dist ≥ 0
	var nm: int = spawns.size() - 1
	for climb in [2, 1]:
		var ff := FlowField.new(g, false, climb)
		ff.begin([core])
		while not ff.done():
			ff.step(1 << 20)
		for i in nm:
			var sp: Vector2i = spawns[i]
			if ff.dist_at(sp.x, sp.y) < 0:
				return "主口 %d 不可达（climb=%d）" % [i + 1, climb]
	# 矿可采：六邻至少一格可通行且虫群可达；盆地矿在「只挖开插口」的临时图上复核
	var swarm := FlowField.new(g, false, 2)
	swarm.begin([core])
	while not swarm.done():
		swarm.step(1 << 20)
	for o in mid_ore:
		if not _ore_open(swarm, o):
			return "中场矿不可采 (%d,%d)" % [o.x, o.y]
	var g2 := build_grid()
	g2.set_cell(basin_plug.x, basin_plug.y, Grid.OPEN)
	var swarm2 := FlowField.new(g2, false, 2)
	swarm2.begin([core])
	while not swarm2.done():
		swarm2.step(1 << 20)
	for o in basin_ore:
		if not _ore_open(swarm2, o):
			return "盆地矿不可采 (%d,%d)" % [o.x, o.y]
	# 矿台渐变带与矿口（2026-10-25）：中场矿 d=2 环高度 ∈ [-1,2]（矿带边界恒坡不崖），
	# 且带中心六方向各走 5 格至少 2 向无 h≥2 墙（坡肩不许连圈把矿围成碗）
	for o in mid_ore:
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var gx: int = o.x + dx
				var gy: int = o.y + dy
				if gx < 0 or gy < 0 or gx >= w or gy >= h:
					continue
				if Grid.hex_dist(gx, gy, o.x, o.y) == 2:
					var hv: int = height_at(gx, gy)
					if hv < -1 or hv > 2:
						return "矿台渐变带破例 (%d,%d) h=%d" % [gx, gy, hv]
	var ctr: Vector2i = mid_ore[2]
	var open_dirs := 0
	for k in 6:
		var cx := ctr.x
		var cy := ctr.y
		var walled := false
		for _step in 5:
			cx = Grid.nx(cx, cy, k)
			cy = Grid.ny(cx, cy, k)
			if cx < 0 or cy < 0 or cx >= w or cy >= h or height_at(cx, cy) >= 2:
				walled = true
				break
		if not walled:
			open_dirs += 1
	if open_dirs < 2:
		return "中场矿台被围死（开向 %d/6）" % open_dirs
	return ""


## 矿格可采：沿矿格簇（同一片连续矿）找六邻中「可通行且虫群可达」的一格。
## 单格六邻口径对 3×4 矿块的中心格必然为矿（不可通行），故按矿簇连通判定：
## 先挖外圈、再挖内芯——与游戏「英雄需站到邻格」的挖矿规则一致。
func _ore_open(ff: FlowField, o: Vector2i) -> bool:
	var seen := {}
	var q: Array = [o]
	var head := 0
	seen[str(o.x) + "," + str(o.y)] = true
	while head < q.size():
		var c: Vector2i = q[head]
		head += 1
		for k in 6:
			var ox := Grid.nx(c.x, c.y, k)
			var oy := Grid.ny(c.x, c.y, k)
			if not ff.grid.inb(ox, oy):
				continue
			if ff.grid.passable(ox, oy):
				if ff.dist_at(ox, oy) >= 0:
					return true
			elif ff.grid.at(ox, oy) == Grid.COVER and is_ore(ox, oy):
				var key := str(ox) + "," + str(oy)
				if not seen.has(key):
					seen[key] = true
					q.append(Vector2i(ox, oy))
	return false


## 布局自校验：建图合法 + 地形合法 + 插口挖开后盆地口可达（默认种子必须全过）
func _validate_layout() -> bool:
	if check_grid(build_grid()) != "":
		return false
	if check_terrain(build_grid()) != "":
		return false
	return check_plug_open(build_grid()) == ""


## 剧本指纹：静态数据的 FNV-1a（换剧本/换布局种子必须换 baseline 的守门数据）。
## 2026-10-16 布局生成化后与 Lua 固定布局不再逐位同构；字段序 = seed 前置 + 原序 + 布局参数段。
func fingerprint(canon: Canon) -> int:
	var b := canon.buffer()
	if _freeform:
		return _fingerprint_freeform(b)
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
	b.put_u8(terrain_kind)
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


## 自由路径指纹（字段序独立分支；默认种子不受影响——冻结规则见 AGENTS 第六节）。
## b = Canon.buffer()（不注类型，避免嵌套类引用噪音）。
func _fingerprint_freeform(b) -> int:
	b.put_i32(seed)
	b.put_i32(w)
	b.put_i32(h)
	b.put_i32(core.x)
	b.put_i32(core.y)
	b.put_i32(hero_spawn.x)
	b.put_i32(hero_spawn.y)
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
	b.put_u32(basin_ore.size())
	for o in basin_ore:
		b.put_i32(o.x)
		b.put_i32(o.y)
	b.put_u32(mid_ore.size())
	for o in mid_ore:
		b.put_i32(o.x)
		b.put_i32(o.y)
	b.put_u32(_rock_arr.size())
	for c in _rock_arr:
		b.put_i32(c.x)
		b.put_i32(c.y)
	b.put_u32(_hill_arr.size())
	for c in _hill_arr:
		b.put_i32(c.x)
		b.put_i32(c.y)
	b.put_u32(_sparse_arr.size())
	for c in _sparse_arr:
		b.put_i32(c.x)
		b.put_i32(c.y)
	b.put_i32(end_tick)
	b.put_i32(hard_cap_tick)
	b.put_i32(trickle_every)
	b.put_i32(wave_scale_pct)
	b.put_u8(terrain_kind)
	for y in h: # 高度（生成地形 + 微丘）入指纹
		for x in w:
			b.put_u8(height_at(x, y))
	b.put_u32(waves.size())
	for wv in waves:
		b.put_i32(wv[0])
		b.put_i32(wv[1])
		b.put_i32(wv[2])
		b.put_i32(wv[3])
	return b.fingerprint()
