class_name MapGen
extends RefCounted

# 玩法地图布局生成器（2026-10-19 世界生成 2.0：非默认种子走「彻底自由化」噪声路径）。
# 三条生成路径（冻结纪律）：
#   · _generate_default：DEFAULT_SEED 专用，参数流字节级冻结（2026-10-16 第三次基线重录口径），
#     恒为 T0 横脊 —— 保剧本指纹 0x7dea2b02 与黄金脚本口径不被本轮改动扰动；
#   · _generate_freeform（盐 0..47）：其余种子主路径——核心/2~3 主口/盆地陷阱/岩群/微丘
#     全部由种子决定（整数值噪声 fBm + 约束采样；结构不变量由 Scenario 校验）；
#   · _generate_varied_legacy（盐 48..63）：旧五模板池，仅作自由路径不收敛时的兜底保险。
# 纪律：纯整数、唯一随机源 = sim Rng；同 (seed, salt, is_default) 恒等输出；
# 产物 = 布局参数字典（不建 Grid），结构不变量由 Scenario 侧校验（含裸图路径长带）。
# 模板几何静态面（legacy 专用）：band_rows（列屏障行）/ gate_rows（咽喉口行）/ extra_walls（附壁）/ carved（缺口）。
# 咽喉宽度恒 3（口心 ±1）；漏斗墙行等脚本行口径 = 「咽喉口行 c.y」相对（见 verify.gd）。

const TEMPLATE_COUNT := 5
const TEMPLATE_NAMES := ["横脊", "错行双脊", "弧脊", "斜壁", "獠牙翼"]
const CHOKE_HALF := 1
const CHOKE_MIN_GAP := 15 # 双咽喉中心最小间距

# 弧脊抛物线分母：v(x) = (x-1)(62-x) 在 x∈1..62 上最大 930（中点对称）。
const ARC_V_MAX := 930

# ============ 世界生成 2.0（自由路径）标定常量 ============
const FREEFORM_SALT_MAX := 48 # 盐 0..47 = 自由世界；48..63 = 旧模板池兜底（16 盐余量）
const CORE_MARGIN := 6 # 核心位距边留白（山头半径 4 + 余量）
const MAIN_D_MIN := 47 # 主口 ↔ 核心六边距离下限（直连 ≥ 47 步 = 470 > 标定带下沿 466）
const MAIN_D_MAX := 54 # 上限（留绕行余量 → 630 以内）
const MAIN_GAP_MIN := 14 # 主口彼此最小六边距离
const PERIPH_BAND := 14 # 周缘带宽度（x/y 距边 ≤ 14 视为周缘出怪区）
const SPAWN_CLEAR := 2 # 出怪口净空（3×3 再留一圈缓冲）
const CORE_CLEAR := 5 # 核心山头净空六边半径（岩/丘/散土都不进）
const BASIN_GAP_CORE := 3 # 盆地矩形外扩（不得触及核心山头）
const BASIN_GAP_SPAWN := 2 # 盆地矩形外扩（不得触及主口净空）
const BASIN_TRIES := 24
const ROCK_LO_PERM := 60 # 岩群占比带（千分比）
const ROCK_HI_PERM := 220
const MOUND_LO_PERM := 20 # 微丘占比带（千分比）
const MOUND_HI_PERM := 160
const SPARSE_MIN := 5 # 散土格数带
const SPARSE_MAX := 9
const ROCK_T := 46500 # 岩群阈值（65535 量程；0..65535 值噪声）
const MOUND_LO_T := 42000 # 微丘噪声带（实测标定：面占比中位 ≈95‰，直方图定带法）
const MOUND_HI_T := 47000

# ============ 地形生成常量（2026-10-23 Task 4-5） ============
# 基地地貌三选一（由种子哈希决定，不用三级同心山头）。
const TERRAIN_PLAIN := 0
const TERRAIN_CLIFF := 1
const TERRAIN_SLOPE := 2
const TERRAIN_COUNT := 3
# 统计带（千分比，按 64×64 全格计）：非零 150..450‰、负高度 20..100‰、h≥3 至少 1 格。
const TERRAIN_NZ_LO := 150
const TERRAIN_NZ_HI := 450
const TERRAIN_NEG_LO := 20
const TERRAIN_NEG_HI := 100
const TERRAIN_HI_MIN := 1
# 基础场分位目标（千分比）：每张图按自身 m 场的分位取阈值。
# 2026-10-23 Task 6b：低频场的整体均值随盐漂移很大（不同盐的中位可差 3k），
# 固定绝对阈值会让部分地图非零占比冲到 60%+ → 改为逐图分位标定（仍纯整数、确定性）。
const BASE_NEG2_PERM := 15
const BASE_NEG1_PERM := 65
const BASE_H1_PERM := 700 # 非零基础目标 ≈30%（成片丘陵；太低压不住大片空白，太高会满图台阶）
const BASE_H2_PERM := 940 # ≥h2 ≈6%
const BASE_H3_PERM := 985 # ≥h3 ≈1.5%（保证平原/山腰也有自然高点）
const BASE_H4_PERM := 998


## 默认种子冻结路径（禁改：数值、常量、抽取顺序全部复刻 2026-10-16 口径）。
static func _generate_default(seed: int, salt: int) -> Dictionary:
	var rng := Rng.new(seed + salt * 1000003)
	var core_x := 30 + rng.next_int(5) # 30..34
	var ridge_y := 40 + rng.next_int(3) # 40..42
	var wx := 16 + rng.next_int(7) # 西咽喉中心 16..22
	var ex := 41 + rng.next_int(7) # 东咽喉中心 41..47
	if ex - wx < CHOKE_MIN_GAP:
		ex = wx + CHOKE_MIN_GAP
	var bx0 := 2 + rng.next_int(3) # 盆地贴西南角 2..4
	var by0 := 52 + rng.next_int(3) # 52..54
	var bw := 7 + rng.next_int(2) # 7..8
	var bh := 8 + rng.next_int(2) # 8..9
	var plug_dx := 2 + rng.next_int(bw - 3) # 上缘第 2..bw-2 列（避角）
	var mid_y := 19 + rng.next_int(3) # 19..21
	var sparse_phase := 2 + rng.next_int(5) # 2..6
	# 微丘（2×2 h1，南场）：避开两侧咽喉柱 ±5；行域 ridge_y+5..48 自动隔离盆地/矿带/出怪口
	var mesa_x := -1
	var mesa_y := -1
	for _try in 16:
		var mx := 9 + rng.next_int(45) # 9..53
		var my := ridge_y + 5 + rng.next_int(48 - (ridge_y + 5) + 1) # ridge_y+5..48
		if absi(mx - wx) <= 5 or absi(mx - ex) <= 5:
			continue
		mesa_x = mx
		mesa_y = my
		break
	if mesa_x < 0: # 兜底：双咽喉正中（间距 ≥15 时必满足 ±5 约束外）
		mesa_x = clampi((wx + ex) / 2 - 1, 9, 53)
		mesa_y = ridge_y + 5
	return {
		"template": 0,
		"core_x": core_x,
		"ridge_y": ridge_y,
		"choke_west": wx,
		"choke_east": ex,
		"basin_x0": bx0,
		"basin_y0": by0,
		"basin_w": bw,
		"basin_h": bh,
		"plug_dx": plug_dx,
		"mid_y": mid_y,
		"sparse_phase": sparse_phase,
		"mesa_x": mesa_x,
		"mesa_y": mesa_y,
	}


## 采样一份布局参数（is_default=true 走冻结路径）。
## 旧公共字段（legacy）：template / core_x / ridge_y / choke_west / choke_east（谷口中心 x）
## basin_x0 / basin_y0 / basin_w / basin_h / plug_dx（插口 = 上缘第 plug_dx 列）
## mid_y（中场矿带行）/ sparse_phase（表土纹理相位）/ mesa_x / mesa_y（2×2 微丘左上角）
## 模板专属（legacy）：T1 split_x（错行分界列）/ T2 bow（弧脊垂幅）/ T3 slope_dy（斜壁斜率行差，带符号）/ T4 wing_len（獠牙翼长）。
## 自由路径（freeform）字段表见 _generate_freeform 头注。
## 2026-10-23 起统一附加地形段：terrain_kind / heights（64×64）/ terrain_valid。
## 默认种子布局恒以 salt=0 抽取（字节冻结）；salt 只作用于地形，供 Scenario 换盐重采样。
static func generate(seed: int, salt: int = 0, is_default: bool = false) -> Dictionary:
	return attach_terrain(seed, salt, generate_layout(seed, salt, is_default), is_default)


## 只采样布局参数（不含地形段）。布局自检 valid=false 的盐注定被换盐替换，
## 先出布局即可筛掉这批废盐，省下每次的地形场计算（选盐与产物不变）。
static func generate_layout(seed: int, salt: int = 0, is_default: bool = false) -> Dictionary:
	if is_default:
		return _generate_default(seed, 0)
	elif salt < FREEFORM_SALT_MAX:
		return _generate_freeform(seed, salt)
	return _generate_varied_legacy(seed, salt - FREEFORM_SALT_MAX)


## 给已采样的布局补地形段（terrain_kind / heights / terrain_valid），就地写回并返回同一字典。
static func attach_terrain(seed: int, salt: int, p: Dictionary, is_default: bool = false) -> Dictionary:
	var ter := _generate_terrain(seed, salt, p, is_default)
	p["terrain_kind"] = int(ter["terrain_kind"])
	p["heights"] = ter["heights"]
	p["terrain_valid"] = bool(ter["terrain_valid"])
	return p


## 旧模板池兜底采样（盐 0..15 域内语义）：RNG(seed+salt·1000003) 抽参数（咽喉错位/盆地/插口/矿带/微丘 16 次重试）
static func _generate_varied_legacy(seed: int, salt: int) -> Dictionary:
	var rng := Rng.new(seed + salt * 1000003)
	var core_x := 28 + rng.next_int(11) # 28..38
	var ridge_y := 39 + rng.next_int(5) # 39..43
	var wx := 15 + rng.next_int(12) # 西咽喉中心 15..26
	var ex := 38 + rng.next_int(14) # 东咽喉中心 38..51
	if ex - wx < CHOKE_MIN_GAP:
		ex = wx + CHOKE_MIN_GAP
	var bx0 := 1 + rng.next_int(5) # 盆地贴西南角 1..5
	var by0 := 50 + rng.next_int(3) # 50..52
	var bw := 6 + rng.next_int(4) # 6..9
	var bh := 7 + rng.next_int(3) # 7..9
	var plug_dx := 2 + rng.next_int(bw - 3) # 上缘第 2..bw-2 列（避角）
	var mid_y := 18 + rng.next_int(6) # 18..23
	var sparse_phase := 2 + rng.next_int(6) # 2..7
	# 微丘（2×2 h1）：避开两侧咽喉柱 ±5；行域 ridge_y+5..48
	var mesa_x := -1
	var mesa_y := -1
	for _try in 16:
		var mx := 7 + rng.next_int(49) # 7..55
		var my := ridge_y + 5 + rng.next_int(48 - (ridge_y + 5) + 1) # ridge_y+5..48
		if absi(mx - wx) <= 5 or absi(mx - ex) <= 5:
			continue
		mesa_x = mx
		mesa_y = my
		break
	if mesa_x < 0:
		mesa_x = clampi((wx + ex) / 2 - 1, 7, 55)
		mesa_y = ridge_y + 5
	var template := rng.next_int(TEMPLATE_COUNT) # 0..4
	var p := {
		"template": template,
		"core_x": core_x,
		"ridge_y": ridge_y,
		"choke_west": wx,
		"choke_east": ex,
		"basin_x0": bx0,
		"basin_y0": by0,
		"basin_w": bw,
		"basin_h": bh,
		"plug_dx": plug_dx,
		"mid_y": mid_y,
		"sparse_phase": sparse_phase,
		"mesa_x": mesa_x,
		"mesa_y": mesa_y,
	}
	match template:
		1: # 错行双脊：西带 [ry..ry+2]、东带 [ry+2..ry+4]，分界列并集无缝
			p["split_x"] = 26 + rng.next_int(11) # 26..36
		2: # 弧脊：屏障中段上拱、两缘下垂 bow 行（v(x)=(x-1)(62-x)，中点对称）
			p["bow"] = 2 + rng.next_int(4) # 2..5
		3: # 斜壁：屏障行随列线性升降（带符号，±5 行内）
			var sdy := 5 + rng.next_int(8) # 5..12
			if rng.next_int(2) == 0:
				sdy = -sdy
			p["slope_dy"] = sdy
		4: # 獠牙翼：双咽喉外侧垂壁挂角（崖底向南延伸 wing_len 格）
			p["wing_len"] = 4 + rng.next_int(4) # 4..7
	return p


# ============ 模板几何静态面（Scenario 建图/校验/高度共用；与 generate 同源纪律） ============

## 该列的屏障行范围 [y0, y1]（含端点）；x 在墙体内或越界 = 无屏障（空数组）。
static func band_rows(p: Dictionary, x: int) -> Array:
	if x < 1 or x > 62:
		return []
	var ry: int = p["ridge_y"]
	match int(p["template"]):
		1:
			if x <= int(p["split_x"]):
				return [ry, ry + 2]
			return [ry + 2, ry + 4]
		2:
			var v: int = (x - 1) * (62 - x)
			var row: int = ry + int(p["bow"]) - int(p["bow"]) * v / ARC_V_MAX
			return [row, row + 2]
		3:
			var row2: int = ry + int(p["slope_dy"]) * (2 * x - 63) / 124
			return [row2, row2 + 2]
		_:
			return [ry, ry + 2]


## 双咽喉口行（西、东）：口心所在列屏障顶行（T0/T4 = ridge_y；T2/T3 随列）。
static func gate_rows(p: Dictionary) -> Array:
	var wr: Array = band_rows(p, int(p["choke_west"]))
	var er: Array = band_rows(p, int(p["choke_east"]))
	return [int(wr[0]), int(er[0])]


## 该格是否属于咽喉缺口（口心 ±1 列 × 该列屏障行）。
static func carved(p: Dictionary, x: int, y: int) -> bool:
	if absi(x - int(p["choke_west"])) > 1 and absi(x - int(p["choke_east"])) > 1:
		return false
	var rows: Array = band_rows(p, x)
	return rows.size() == 2 and y >= int(rows[0]) and y <= int(rows[1])


## 模板附壁（T4 獠牙翼；盆地矩形内不加，交给盆地逻辑）。
static func extra_walls(p: Dictionary) -> Array:
	if int(p["template"]) != 4:
		return []
	var ry: int = p["ridge_y"]
	var bx: int = p["basin_x0"]
	var by: int = p["basin_y0"]
	var bw: int = p["basin_w"]
	var bh: int = p["basin_h"]
	var out: Array = []
	for x in [int(p["choke_west"]) - 3, int(p["choke_east"]) + 3]:
		for i in int(p["wing_len"]):
			var y: int = ry + 3 + i
			if x >= bx and x < bx + bw and y >= by and y < by + bh:
				continue
			out.append(Vector2i(x, y))
	return out


# ============ 世界生成 2.0：自由路径（整数值噪声 + 约束采样） ============
# 产物字段（Scenario._apply_freeform 消费）：
#   core_x/core_y、hero_x/hero_y、mains（2..3 个主口 Vector2i）、
#   basin_x0/y0/w/h、plug_edge(0上/1下/2左/3右)/plug_x/plug_y、basin_ore（3×4 块）、
#   basin_spawn（压块心矿格）、mid_ore（5 格横排）、rocks/hills/sparse（自由地貌格集）、
#   valid=false 表示占比自检未过（交 Scenario 换盐重采样）。
# 噪声口径：64 位哈希 → 16 位格点值（双线性 + 三次平滑，Q8 定点）；fBm = 三倍频加权；
# 岩群 = fBm 阈值（x 向拉长 13:9 → 链状起伏）；微丘 = 中频噪声带（h1 可爬坡）。
# 净空蒙版（岩/丘/散土都不进）：主口 2 圈 / 核心山头 5 圈 / 矿格 1 圈 / 盆地矩形 / 插口外侧 1 圈 / 英雄位。
# 纪律：纯整数（除法/取模一律 Lua64 shim），无浮点无 libm；同 (seed, salt) 恒等输出。


## 64 位整数哈希 → 16 位值（x/y/seed 混入；掩码保非负参与后续乘法）。
static func _hash16(x: int, y: int, s: int) -> int:
	var n: int = x * 374761393 + y * 668265263 + s * 1013904223
	n = n & 9223372036854775807
	n = n ^ Lua64.lshr(n, 13)
	n = (n * 1274126177) & 9223372036854775807
	n = n ^ Lua64.lshr(n, 16)
	return n & 65535


## 值噪声（格距 cx/cy ≥ 2；x,y ≥ 0 场内坐标；输出 0..65535）。
## tx = (x % cx)·256/cx ∈ [0,256)，三次平滑 s(t) = t²(3·256−2t)/65536 ∈ [0,256]。
static func _vnoise(x: int, y: int, cx: int, cy: int, s: int) -> int:
	var lx := Lua64.idiv(x, cx)
	var ly := Lua64.idiv(y, cy)
	var tx := Lua64.idiv(Lua64.mod(x, cx) * 256, cx)
	var ty := Lua64.idiv(Lua64.mod(y, cy) * 256, cy)
	tx = Lua64.idiv(tx * tx * (768 - 2 * tx), 65536)
	ty = Lua64.idiv(ty * ty * (768 - 2 * ty), 65536)
	var v00 := _hash16(lx, ly, s)
	var v10 := _hash16(lx + 1, ly, s)
	var v01 := _hash16(lx, ly + 1, s)
	var v11 := _hash16(lx + 1, ly + 1, s)
	var a := v00 + Lua64.idiv((v10 - v00) * tx, 256)
	var b := v01 + Lua64.idiv((v11 - v01) * tx, 256)
	return a + Lua64.idiv((b - a) * ty, 256)


## fBm（三倍频加权，0..65535）：宏观岩群场。倍频常数注入盐域 → 逐盐去相关。
static func _fbm3(x: int, y: int, ns: int) -> int:
	var lo := _vnoise(x, y, 13, 9, ns + 101) * 3
	var mid := _vnoise(x, y, 7, 7, ns + 211) * 2
	var hi := _vnoise(x, y, 3, 3, ns + 307) * 3
	return (lo + mid + hi) / 8


## 自由世界生成（盐 0..47）。任何约束抽不满只回落保守值，合法性由 Scenario 全量校验决定。
static func _generate_freeform(seed: int, salt: int) -> Dictionary:
	var ns := seed + salt * 1000003
	var rng := Rng.new(ns)
	# ① 核心位（留边 CORE_MARGIN..63-CORE_MARGIN）
	var core_x := CORE_MARGIN + rng.next_int(63 - CORE_MARGIN * 2 + 1)
	var core_y := CORE_MARGIN + rng.next_int(63 - CORE_MARGIN * 2 + 1)
	var side := 1 if core_y <= 31 else -1 # 朝场地内侧方向（英雄位/中场矿都朝内）
	# ② 主出怪口 2..3 个（周缘带 + 与核心距离带 + 彼此间距）
	var n_mains := 2
	if rng.next_int(10) < 3:
		n_mains = 3
	var mains := _pick_mains(rng, core_x, core_y, n_mains)
	# ③ 中场矿：核心偏内侧 4..7 行处一横排 5 格（先定矿，盆地/地貌净空协商它）
	var mid_y := core_y + side * (4 + rng.next_int(4))
	var mid_x0 := clampi(core_x - 2, 2, 56)
	var mid_ore: Array = []
	for i in 5:
		mid_ore.append(Vector2i(mid_x0 + i, mid_y))
	# ④ 盆地陷阱（矩形 6..9 × 7..9；位置试抽 + 兜底扫描；避开核心/主口/中场矿）
	var bw := 6 + rng.next_int(4)
	var bh := 7 + rng.next_int(3)
	var bx0 := 2
	var by0 := 2
	var placed := false
	for _try in BASIN_TRIES:
		var tx := 2 + rng.next_int(61 - bw)
		var ty := 2 + rng.next_int(61 - bh)
		if _basin_clear(tx, ty, bw, bh, core_x, core_y, mains, mid_ore):
			bx0 = tx
			by0 = ty
			placed = true
			break
	if not placed:
		for ty2 in range(2, 63 - bh):
			var hit := false
			for tx2 in range(2, 63 - bw):
				if _basin_clear(tx2, ty2, bw, bh, core_x, core_y, mains, mid_ore):
					bx0 = tx2
					by0 = ty2
					placed = true
					hit = true
					break
			if hit:
				break
	# ⑤ 插口：任意边中部（避角）
	var plug_edge := rng.next_int(4)
	var plug_x := bx0
	var plug_y := by0
	if plug_edge == 0 or plug_edge == 1:
		plug_x = bx0 + 2 + rng.next_int(bw - 4) # 边缘中部：两端各避 2 格（修正 off-by-one）
		plug_y = by0 if plug_edge == 0 else by0 + bh - 1
	else:
		plug_y = by0 + 2 + rng.next_int(bh - 4)
		plug_x = bx0 if plug_edge == 2 else bx0 + bw - 1
	# ⑥ 盆地矿块（+2..+4 × +3..+6 共 12 格；盆地口压块心）
	var basin_ore: Array = []
	for ox in range(bx0 + 2, bx0 + 5):
		for oy in range(by0 + 3, by0 + 7):
			basin_ore.append(Vector2i(ox, oy))
	var basin_spawn := Vector2i(bx0 + 3, by0 + 4)
	var hero_x := core_x
	var hero_y := core_y + side * 2
	# ⑦ 净空蒙版（岩/丘/散土都不进）
	var prot := {}
	for m in mains:
		for dy in range(-SPAWN_CLEAR, SPAWN_CLEAR + 1):
			for dx in range(-SPAWN_CLEAR, SPAWN_CLEAR + 1):
				prot[str(m.x + dx) + "," + str(m.y + dy)] = true
	for dy in range(-CORE_CLEAR, CORE_CLEAR + 1):
		for dx in range(-CORE_CLEAR, CORE_CLEAR + 1):
			if Grid.hex_dist(core_x + dx, core_y + dy, core_x, core_y) <= CORE_CLEAR:
				prot[str(core_x + dx) + "," + str(core_y + dy)] = true
	for o in mid_ore:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				prot[str(o.x + dx) + "," + str(o.y + dy)] = true
	for y in range(by0, by0 + bh):
		for x in range(bx0, bx0 + bw):
			prot[str(x) + "," + str(y)] = true
	var ex := plug_x
	var ey := plug_y
	if plug_edge == 0:
		ey = by0 - 1
	elif plug_edge == 1:
		ey = by0 + bh
	elif plug_edge == 2:
		ex = bx0 - 1
	else:
		ex = bx0 + bw
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			prot[str(ex + dx) + "," + str(ey + dy)] = true
	prot[str(hero_x) + "," + str(hero_y)] = true
	prot[str(core_x) + "," + str(core_y)] = true
	# ⑧ 岩群（fBm 阈值）与微丘（噪声带）：只落净空蒙版之外，互斥（岩优先）
	var rocks: Array = []
	var hills: Array = []
	var area := 0
	for y in range(1, 63):
		for x in range(1, 63):
			var key := str(x) + "," + str(y)
			if prot.has(key):
				continue
			area += 1
			if _fbm3(x, y, ns) >= ROCK_T:
				rocks.append(Vector2i(x, y))
				continue
			var hv := _vnoise(x, y, 9, 7, ns + 503)
			if hv >= MOUND_LO_T and hv <= MOUND_HI_T:
				hills.append(Vector2i(x, y))
	# ⑨ 散土（可挖装饰障碍 5..9 格；避开净空/岩/丘，彼此切比雪夫距 ≥2）
	var sparse: Array = []
	var want := SPARSE_MIN + rng.next_int(SPARSE_MAX - SPARSE_MIN + 1)
	for _try in 64:
		if sparse.size() >= want:
			break
		var sx := 2 + rng.next_int(60)
		var sy := 2 + rng.next_int(60)
		var key2 := str(sx) + "," + str(sy)
		if prot.has(key2):
			continue
		if _fbm3(sx, sy, ns) >= ROCK_T:
			continue
		var hv2 := _vnoise(sx, sy, 9, 7, ns + 503)
		if hv2 >= MOUND_LO_T and hv2 <= MOUND_HI_T:
			continue
		var near := false
		for c in sparse:
			if maxi(absi(sx - c.x), absi(sy - c.y)) < 2:
				near = true
				break
		if near:
			continue
		sparse.append(Vector2i(sx, sy))
	# ⑩ 自检：占比带 + 主口数（不过 → valid=false，Scenario 换盐重采样）
	var valid := true
	var rock_perm := rocks.size() * 1000 / maxi(area, 1)
	var mound_perm := hills.size() * 1000 / maxi(area, 1)
	if rock_perm < ROCK_LO_PERM or rock_perm > ROCK_HI_PERM:
		valid = false
	if mound_perm < MOUND_LO_PERM or mound_perm > MOUND_HI_PERM:
		valid = false
	if mains.size() < 2:
		valid = false
	return {
		"freeform": true,
		"valid": valid,
		"core_x": core_x,
		"core_y": core_y,
		"hero_x": hero_x,
		"hero_y": hero_y,
		"mains": mains,
		"basin_x0": bx0,
		"basin_y0": by0,
		"basin_w": bw,
		"basin_h": bh,
		"plug_edge": plug_edge,
		"plug_x": plug_x,
		"plug_y": plug_y,
		"basin_ore": basin_ore,
		"basin_spawn": basin_spawn,
		"mid_ore": mid_ore,
		"rocks": rocks,
		"hills": hills,
		"sparse": sparse,
	}


## 抽 2..3 个周缘主口：候选 = [3..60]² 且贴边 ≤PERIPH_BAND、与核心六边距 ∈ [MAIN_D_MIN, MAIN_D_MAX]。
## 抽不满（候选池被距离约束血洗）就少装几口回落，合法性交 Scenario 校验。
static func _pick_mains(rng: Rng, cx: int, cy: int, n: int) -> Array:
	var cand: Array = []
	for y in range(3, 61):
		for x in range(3, 61):
			if x > PERIPH_BAND and x < 63 - PERIPH_BAND and y > PERIPH_BAND and y < 63 - PERIPH_BAND:
				continue
			var d := Grid.hex_dist(x, y, cx, cy)
			if d < MAIN_D_MIN or d > MAIN_D_MAX:
				continue
			cand.append(Vector2i(x, y))
	var out: Array = []
	if cand.size() > 0:
		out.append(cand[rng.next_int(cand.size())])
	else:
		out.append(Vector2i(cx, 56)) # 兜底（几乎必被校验拒 → 换盐）
	while out.size() < n:
		var pick: Array = []
		for c in cand:
			var cok := true
			for m in out:
				if Grid.hex_dist(c.x, c.y, m.x, m.y) < MAIN_GAP_MIN:
					cok = false
					break
			if cok:
				pick.append(c)
		if pick.is_empty():
			break
		out.append(pick[rng.next_int(pick.size())])
	return out


## 盆地净空：矩形外扩不复用核心山头 / 主口净空，且中场矿不入矩形（外扩 1）。
static func _basin_clear(x0: int, y0: int, w: int, h: int, cx: int, cy: int, mains: Array, mid_ore: Array) -> bool:
	var around_core := Rect2i(x0 - BASIN_GAP_CORE, y0 - BASIN_GAP_CORE, w + BASIN_GAP_CORE * 2, h + BASIN_GAP_CORE * 2)
	if around_core.has_point(Vector2i(cx, cy)):
		return false
	var around := Rect2i(x0 - BASIN_GAP_SPAWN, y0 - BASIN_GAP_SPAWN, w + BASIN_GAP_SPAWN * 2, h + BASIN_GAP_SPAWN * 2)
	for m in mains:
		if around.has_point(Vector2i(m.x, m.y)):
			return false
	var ore_guard := Rect2i(x0 - 1, y0 - 1, w + 2, h + 2)
	for o in mid_ore:
		if ore_guard.has_point(Vector2i(o.x, o.y)):
			return false
	return true


# ============ 地形生成（2026-10-23 Task 4-5：随机高度 + 矿可采硬条件） ============
# 纪律：纯整数、无浮点、无 libm；哈希/噪声盐域与布局生成分开（见 _generate_terrain 的 ts）。
# 不建 Grid：净空塑形与低地走廊全部在高度数组上完成；可达性由 Scenario.check_terrain 校验。
# heights[y*64+x]，值域 -2..5。terrain_valid=false 由 Scenario 换盐重采样（布局字段不动）。
# 走廊口径：沿「忽略高度后的真实可通行最短路」压成 0/1（不是几何直线），
# 保证蛮兽（climb_max=1）从主口可一路走到核心邻格。


## 地形几何面（从布局参数推算，不改布局字段）：核心/英雄位/主口/盆地/插口/矿表。
static func _terrain_geom(p: Dictionary) -> Dictionary:
	if bool(p.get("freeform", false)):
		var fm: Array = []
		for m in p["mains"]:
			fm.append(Vector2i(m.x, m.y))
		var fo: Array = []
		for o in p["basin_ore"]:
			fo.append(Vector2i(o.x, o.y))
		var mo: Array = []
		for o in p["mid_ore"]:
			mo.append(Vector2i(o.x, o.y))
		return {
			"core": Vector2i(int(p["core_x"]), int(p["core_y"])),
			"hero": Vector2i(int(p["hero_x"]), int(p["hero_y"])),
			"mains": fm,
			"basin": Rect2i(int(p["basin_x0"]), int(p["basin_y0"]), int(p["basin_w"]), int(p["basin_h"])),
			"plug": Vector2i(int(p["plug_x"]), int(p["plug_y"])),
			"basin_ore": fo,
			"mid_ore": mo,
		}
	var cx: int = p["core_x"]
	var bx: int = p["basin_x0"]
	var by: int = p["basin_y0"]
	var bor: Array = []
	for ox in range(bx + 2, bx + 5):
		for oy in range(by + 3, by + 7):
			bor.append(Vector2i(ox, oy))
	var mor: Array = []
	for ox2 in range(cx - 2, cx + 3):
		mor.append(Vector2i(ox2, p["mid_y"]))
	return {
		"core": Vector2i(cx, 6),
		"hero": Vector2i(cx, 8),
		"mains": [Vector2i(cx - 12, 56), Vector2i(cx + 12, 56)],
		"basin": Rect2i(bx, by, int(p["basin_w"]), int(p["basin_h"])),
		"plug": Vector2i(bx + int(p["plug_dx"]), by),
		"basin_ore": bor,
		"mid_ore": mor,
	}


## 基础势场 m（0..65535）：极低频值噪声 + 域扭曲。
## 参考 Inigo Quilez 2002《Domain Warping》(iquilezles.org/articles/warp)：
## 用一份低频噪声位移采样坐标（f(p + g(p))），让等值线自然弯曲而不增加频率。
## 关键尺度约束：基频波长 32 格、次频 20 格 —— 一个台地/丘陵的最小宽度就是这个量级。
## 高度带的边界总长与噪声频率成正比，频率越低碎块越少（这正是「满屏小凸台」的成因）。
static func _terrain_m(x: int, y: int, ts: int) -> int:
	var wx := Lua64.idiv(_vnoise(x + 53, y + 17, 40, 40, ts + 501) - 32767, 8192) # ±4 格
	var wy := Lua64.idiv(_vnoise(x + 17, y + 53, 40, 40, ts + 601) - 32767, 8192)
	var px: int = x + wx + 32
	var py: int = y + wy + 32
	var lo := _vnoise(px, py, 32, 32, ts + 101)
	var mid := _vnoise(px, py, 20, 20, ts + 211)
	return Lua64.idiv(lo * 3 + mid, 4)


## 地形特征摆放：2..4 座山丘 + 1..2 个洼地（中心/半径/幅度全由种子决定）。
## 参考 RimWorld / 文明类的「区域高程 + 局部特征」分层：先摆大尺度地貌，再叠细节，
## 而不是让逐格噪声去决定哪里有山 —— 特征摆放天然形成大片连通台地。
## 保护格（核心山头/主口/盆地/插口/矿邻位/布局岩丘散土/已放特征）不进特征范围。
static func _terrain_features(seed: int, salt: int, geom: Dictionary, p: Dictionary) -> Array:
	var prot: Array = []
	for i in 4096:
		prot.append(false)
	var core: Vector2i = geom["core"]
	for y in range(maxi(core.y - 9, 0), mini(core.y + 10, 64)):
		for x in range(maxi(core.x - 9, 0), mini(core.x + 10, 64)):
			if Grid.hex_dist(x, y, core.x, core.y) <= 7:
				_terrain_mark(prot, x, y)
	for m in geom["mains"]:
		for dy in range(-5, 6):
			for dx in range(-5, 6):
				_terrain_mark(prot, int(m.x) + dx, int(m.y) + dy)
	var b: Rect2i = geom["basin"]
	for y in range(b.position.y - 1, b.position.y + b.size.y + 1):
		for x in range(b.position.x - 1, b.position.x + b.size.x + 1):
			_terrain_mark(prot, x, y)
	var plug: Vector2i = geom["plug"]
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			_terrain_mark(prot, plug.x + dx, plug.y + dy)
	for o in geom["mid_ore"]:
		_terrain_mark(prot, int(o.x), int(o.y))
		for k in 6:
			_terrain_mark(prot, Grid.nx(o.x, o.y, k), Grid.ny(o.x, o.y, k))
	for o in geom["basin_ore"]:
		_terrain_mark(prot, int(o.x), int(o.y))
		for k in 6:
			_terrain_mark(prot, Grid.nx(o.x, o.y, k), Grid.ny(o.x, o.y, k))
	if bool(p.get("freeform", false)):
		for c in p["rocks"]:
			_terrain_mark(prot, int(c.x), int(c.y))
		for c in p["hills"]:
			_terrain_mark(prot, int(c.x), int(c.y))
		for c in p["sparse"]:
			_terrain_mark(prot, int(c.x), int(c.y))
	else:
		var mx: int = p["mesa_x"]
		var my: int = p["mesa_y"]
		if mx >= 0:
			for dy in 2:
				for dx in 2:
					_terrain_mark(prot, mx + dx, my + dy)
	var feats: Array = []
	var wants := [2 + Lua64.mod(_hash16(seed, salt, 9311), 3),
		1 + Lua64.mod(_hash16(seed, salt, 9313), 2)]
	for pass_i in 2:
		var placed := 0
		for t in 40:
			if placed >= int(wants[pass_i]):
				break
			var hx: int = 3 + Lua64.mod(_hash16(seed, salt * 7 + t, 9323 + pass_i * 31), 58)
			var hy: int = 3 + Lua64.mod(_hash16(seed, salt * 7 + t, 9337 + pass_i * 31), 58)
			var r: int = 0
			var amp: int = 0
			if pass_i == 0:
				r = 6 + Lua64.mod(_hash16(hx, hy, 9341), 5) # 半径 6..10
				amp = 15000 + Lua64.mod(_hash16(hx, hy, 9343), 9000)
			else:
				r = 4 + Lua64.mod(_hash16(hx, hy, 9347), 3) # 半径 4..6
				amp = -(13000 + Lua64.mod(_hash16(hx, hy, 9349), 7000))
			var ok := true
			for y in range(maxi(hy - r - 1, 0), mini(hy + r + 2, 64)):
				for x in range(maxi(hx - r - 1, 0), mini(hx + r + 2, 64)):
					if Grid.hex_dist(x, y, hx, hy) <= r + 1 and bool(prot[y * 64 + x]):
						ok = false
						break
				if not ok:
					break
			if not ok:
				continue
			for f in feats: # 特征彼此错开，避免山丘与洼地互相抵消
				if Grid.hex_dist(hx, hy, f["c"].x, f["c"].y) < int(f["r"]) + r + 3:
					ok = false
					break
			if not ok:
				continue
			feats.append({"c": Vector2i(hx, hy), "r": r, "amp": amp})
			placed += 1
	return feats


## 特征叠加到势场：按六边距离线性衰减（峰心最高、外缘归零）。
## 扰动必须用「平滑噪声」而不是逐格哈希 —— 逐格抖动与量化梯度同量级时会在阈值附近
## 产生豹纹式碎斑（这是上一版满屏小凸台的直接原因）。
static func _terrain_apply_features(ms: Array, feats: Array) -> void:
	for f in feats:
		var c: Vector2i = f["c"]
		var r: int = int(f["r"])
		var amp: int = int(f["amp"])
		for y in range(maxi(c.y - r, 0), mini(c.y + r + 1, 64)):
			for x in range(maxi(c.x - r, 0), mini(c.x + r + 1, 64)):
				var d: int = Grid.hex_dist(x, y, c.x, c.y)
				if d > r:
					continue
				var jitter := Lua64.idiv(_vnoise(x, y, 12, 12, 9361) - 32767, 40) # ±819，12 格波长
				var add: int = Lua64.idiv(amp * (r - d + 1), r + 1) + jitter
				var i: int = y * 64 + x
				ms[i] = clampi(int(ms[i]) + add, 0, 65535)


## 投票平滑（Spokes, Nathan Fenner《Spokes》generation.ts 的六边平滑规则）：
## 某格 h 的六邻里 h+1 多于 h、且不存在 h-1 邻 → 升到 h+1；反向同理降。
## 「不得有反向邻」是关键：平滑不会把原本可通行的邻接变成不可通行，
## 因此可以放心多跑几遍把 1 格碎凸台并入大台地，大崖（落差 ≥2）自然保留。
static func _terrain_smooth_vote(hs: Array, passes: int) -> Array:
	var cur: Array = hs
	for _p in passes:
		var nxt: Array = cur.duplicate()
		for y in range(1, 63):
			for x in range(1, 63):
				var i: int = y * 64 + x
				var h0: int = int(cur[i])
				var c_up := 0
				var c_same := 0
				var c_dn := 0
				for k in 6:
					var v: int = int(cur[Grid.ny(x, y, k) * 64 + Grid.nx(x, y, k)])
					if v == h0 + 1:
						c_up += 1
					elif v == h0:
						c_same += 1
					elif v == h0 - 1:
						c_dn += 1
				if c_up > c_same and c_dn == 0:
					nxt[i] = h0 + 1
				elif c_dn > c_same and c_up == 0:
					nxt[i] = h0 - 1
		cur = nxt
	return cur


## 小块合并（形态学「去小岛」）：同高度连通分量不足 min_area 格 → 整块并入包围它的众数高度。
## 参考 catlikecoding《Hex Map 24》的侵蚀/搬土思路与通用 tile 地图 remove-small-islands：
## 先把零碎小块吃掉，再谈细节；投票平滑解决不了「0/1 各半的迷宫」，这一步专门解决它。
static func _terrain_merge_small(hs: Array, min_area: int, passes: int) -> Array:
	var cur: Array = hs
	for _p in passes:
		var seen: Array = []
		for i in 4096:
			seen.append(false)
		var nxt: Array = cur.duplicate()
		for i in 4096:
			if bool(seen[i]):
				continue
			var x0: int = Lua64.mod(i, 64)
			var y0: int = Lua64.idiv(i, 64)
			if x0 == 0 or y0 == 0 or x0 == 63 or y0 == 63:
				seen[i] = true
				continue
			var h0: int = int(cur[i])
			var comp: Array = [i]
			var q: Array = [i]
			seen[i] = true
			var head := 0
			while head < q.size():
				var idx: int = q[head]
				head += 1
				var x: int = Lua64.mod(idx, 64)
				var y: int = Lua64.idiv(idx, 64)
				for k in 6:
					var nx_n: int = Grid.nx(x, y, k)
					var ny_n: int = Grid.ny(x, y, k)
					if nx_n < 0 or ny_n < 0 or nx_n >= 64 or ny_n >= 64:
						continue
					var ni: int = ny_n * 64 + nx_n
					if bool(seen[ni]) or int(cur[ni]) != h0:
						continue
					seen[ni] = true
					comp.append(ni)
					q.append(ni)
			if comp.size() >= min_area:
				continue
			var cnt: Dictionary = {}
			for idx2 in comp:
				var x2: int = Lua64.mod(idx2, 64)
				var y2: int = Lua64.idiv(idx2, 64)
				for k2 in 6:
					var nx2: int = Grid.nx(x2, y2, k2)
					var ny2: int = Grid.ny(x2, y2, k2)
					if nx2 < 0 or ny2 < 0 or nx2 >= 64 or ny2 >= 64:
						continue
					var ni2: int = ny2 * 64 + nx2
					var v2: int = int(cur[ni2])
					if v2 == h0:
						continue
					cnt[v2] = int(cnt.get(v2, 0)) + 1
			var best: int = h0
			var best_n := 0
			for v in cnt:
				var n: int = int(cnt[v])
				if n > best_n or (n == best_n and absi(int(v) - h0) < absi(best - h0)):
					best = int(v)
					best_n = n
			if best != h0:
				for idx3 in comp:
					nxt[idx3] = best
		cur = nxt
	return cur


## m → 高度分带 -2/-1/0/1/2/3/4；th = [n2, n1, h1, h2, h3, h4]（本图分位阈值）。
static func _terrain_base(m: int, th: Array) -> int:
	if m <= int(th[0]):
		return -2
	if m <= int(th[1]):
		return -1
	if m >= int(th[5]):
		return 4
	if m >= int(th[4]):
		return 3
	if m >= int(th[3]):
		return 2
	if m >= int(th[2]):
		return 1
	return 0


## 7 点中值滤波：自身 + 六邻共 7 值排序取中位（边框保持；去掉孤立尖点）。
static func _terrain_median(hs: Array) -> Array:
	var out: Array = hs.duplicate()
	for y in range(1, 63):
		for x in range(1, 63):
			var vals: Array = []
			vals.append(int(hs[y * 64 + x]))
			for k in 6:
				vals.append(int(hs[Grid.ny(x, y, k) * 64 + Grid.nx(x, y, k)]))
			vals.sort()
			out[y * 64 + x] = vals[3]
	return out


## 保护格标记（洼地选址用；越界静默忽略）。
static func _terrain_mark(prot: Array, x: int, y: int) -> void:
	if x < 0 or y < 0 or x >= 64 or y >= 64:
		return
	prot[y * 64 + x] = true


## 负高度补足：显式放 2..4 个「洼地」（中心 -2、半径 2 内 -1）。
## 只落不被保护的区域（核心/主口/英雄位/盆地/插口/矿/走廊/地貌），位置由 (seed, salt) 决定。
static func _terrain_depressions(hs: Array, seed: int, salt: int, geom: Dictionary,
		mains: Array, corr: Dictionary, p: Dictionary) -> void:
	var prot: Array = []
	for i in 4096:
		prot.append(false)
	var core: Vector2i = geom["core"]
	for y in range(maxi(core.y - 7, 0), mini(core.y + 8, 64)):
		for x in range(maxi(core.x - 7, 0), mini(core.x + 8, 64)):
			if Grid.hex_dist(x, y, core.x, core.y) <= 6:
				_terrain_mark(prot, x, y)
	for m in mains:
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				_terrain_mark(prot, int(m.x) + dx, int(m.y) + dy)
	var hero: Vector2i = geom["hero"]
	_terrain_mark(prot, hero.x, hero.y)
	var b: Rect2i = geom["basin"]
	for y in range(b.position.y - 1, b.position.y + b.size.y + 1):
		for x in range(b.position.x - 1, b.position.x + b.size.x + 1):
			_terrain_mark(prot, x, y)
	var plug: Vector2i = geom["plug"]
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			_terrain_mark(prot, plug.x + dx, plug.y + dy)
	for o in geom["mid_ore"]:
		_terrain_mark(prot, int(o.x), int(o.y))
		for k in 6:
			_terrain_mark(prot, Grid.nx(o.x, o.y, k), Grid.ny(o.x, o.y, k))
	for o in geom["basin_ore"]:
		_terrain_mark(prot, int(o.x), int(o.y))
		for k in 6:
			_terrain_mark(prot, Grid.nx(o.x, o.y, k), Grid.ny(o.x, o.y, k))
	for key in corr:
		var parts: PackedStringArray = String(key).split(",")
		var px := int(parts[0])
		var py := int(parts[1])
		_terrain_mark(prot, px, py)
		for k in 6:
			_terrain_mark(prot, Grid.nx(px, py, k), Grid.ny(px, py, k))
	if bool(p.get("freeform", false)):
		for c in p["hills"]:
			_terrain_mark(prot, int(c.x), int(c.y))
		for c in p["rocks"]:
			_terrain_mark(prot, int(c.x), int(c.y))
		for c in p["sparse"]:
			_terrain_mark(prot, int(c.x), int(c.y))
	else:
		var mx: int = p["mesa_x"]
		var my: int = p["mesa_y"]
		if mx >= 0:
			for dy in 2:
				for dx in 2:
					_terrain_mark(prot, mx + dx, my + dy)
	var want: int = 2 + Lua64.mod(_hash16(seed, salt, 9301), 3)
	var placed := 0
	for t in range(0, 256):
		if placed >= want:
			break
		var cx: int = 1 + Lua64.mod(_hash16(seed, salt + t, 9303), 62)
		var cy: int = 1 + Lua64.mod(_hash16(seed, salt + t, 9305), 62)
		var ok := true
		for y in range(maxi(cy - 2, 0), mini(cy + 3, 64)):
			for x in range(maxi(cx - 2, 0), mini(cx + 3, 64)):
				if Grid.hex_dist(x, y, cx, cy) <= 2 and bool(prot[y * 64 + x]):
					ok = false
		if not ok:
			continue
		for y in range(maxi(cy - 2, 0), mini(cy + 3, 64)):
			for x in range(maxi(cx - 2, 0), mini(cx + 3, 64)):
				if Grid.hex_dist(x, y, cx, cy) <= 2:
					hs[y * 64 + x] = -1
					prot[y * 64 + x] = true
		hs[cy * 64 + cx] = -2
		placed += 1


## 高度数组单点写入 / 区间钳制（越界静默忽略；高度数组口径 64×64）。
static func _terrain_set(hs: Array, x: int, y: int, v: int) -> void:
	if x < 0 or y < 0 or x >= 64 or y >= 64:
		return
	hs[y * 64 + x] = v


static func _terrain_clamp(hs: Array, x: int, y: int, lo: int, hi: int) -> void:
	if x < 0 or y < 0 or x >= 64 or y >= 64:
		return
	hs[y * 64 + x] = clampi(int(hs[y * 64 + x]), lo, hi)


## 可通行蒙版（镜像 Scenario.build_grid 的阻挡口径；只用于走廊寻路，不建 Grid）。
static func _terrain_mask(p: Dictionary, geom: Dictionary) -> Array:
	var blocked: Array = []
	for i in 4096:
		blocked.append(false)
	var b: Rect2i = geom["basin"]
	var plug: Vector2i = geom["plug"]
	# 矿格（覆盖层，不可通行）
	for o in geom["mid_ore"]:
		blocked[int(o.y) * 64 + int(o.x)] = true
	for o in geom["basin_ore"]:
		blocked[int(o.y) * 64 + int(o.x)] = true
	if bool(p.get("freeform", false)):
		for c in p["rocks"]:
			blocked[int(c.y) * 64 + int(c.x)] = true
		for c in p["sparse"]:
			blocked[int(c.y) * 64 + int(c.x)] = true
	else:
		for x in range(1, 63):
			var rows: Array = band_rows(p, x)
			if rows.size() != 2:
				continue
			for y in range(int(rows[0]), int(rows[1]) + 1):
				if carved(p, x, y):
					continue
				if x == plug.x and y == plug.y:
					continue
				blocked[y * 64 + x] = true
		for c in extra_walls(p):
			blocked[int(c.y) * 64 + int(c.x)] = true
	# 盆地岩环（实心/覆盖层都挡路）
	for y in range(b.position.y, b.position.y + b.size.y):
		for x in range(b.position.x, b.position.x + b.size.x):
			var edge: bool = x == b.position.x or x == b.position.x + b.size.x - 1 \
				or y == b.position.y or y == b.position.y + b.size.y - 1
			if edge:
				blocked[y * 64 + x] = true
	if not bool(p.get("freeform", false)):
		var phase: int = int(p["sparse_phase"])
		for x in range(1, 63):
			if Lua64.mod(x, 9) == phase:
				blocked[17 * 64 + x] = true
	# 边框 + 核心
	for x in 64:
		blocked[x] = true
		blocked[63 * 64 + x] = true
	for y in 64:
		blocked[y * 64] = true
		blocked[y * 64 + 63] = true
	var core: Vector2i = geom["core"]
	blocked[core.y * 64 + core.x] = true
	return blocked


## 忽略高度的 BFS 距离场（核心为源，只向可通行格扩张；-1 = 不可达）。
static func _terrain_bfs(mask: Array, core: Vector2i) -> Array:
	var dist: Array = []
	for i in 4096:
		dist.append(-1)
	var q: Array = []
	dist[core.y * 64 + core.x] = 0
	q.append(core.y * 64 + core.x)
	var head := 0
	while head < q.size():
		var idx: int = q[head]
		head += 1
		var x: int = Lua64.mod(idx, 64)
		var y: int = Lua64.idiv(idx, 64)
		var nd: int = int(dist[idx]) + 1
		for k in 6:
			var nx: int = Grid.nx(x, y, k)
			var ny: int = Grid.ny(x, y, k)
			if nx < 0 or ny < 0 or nx >= 64 or ny >= 64:
				continue
			var ni: int = ny * 64 + nx
			if dist[ni] != -1 or _mask_blocked(mask, ni):
				continue
			dist[ni] = nd
			q.append(ni)
	return dist


static func _mask_blocked(mask: Array, i: int) -> bool:
	return bool(mask[i])


## 从 from 沿 BFS 距离逐格下降到核心（六边邻近；平手按 _hash16 抖动 → 走廊形状随盐变化）。
static func _terrain_path(dist: Array, mask: Array, from: Vector2i, core: Vector2i, ts: int) -> Array:
	var path: Array = []
	var cur := Vector2i(from.x, from.y)
	if dist[cur.y * 64 + cur.x] < 0:
		return path
	path.append(cur)
	while cur != core:
		var d: int = int(dist[cur.y * 64 + cur.x])
		var cand: Array = []
		for k in 6:
			var nx: int = Grid.nx(cur.x, cur.y, k)
			var ny: int = Grid.ny(cur.x, cur.y, k)
			if nx < 0 or ny < 0 or nx >= 64 or ny >= 64:
				continue
			var ni: int = ny * 64 + nx
			if int(dist[ni]) != d - 1:
				continue
			if not (nx == core.x and ny == core.y) and _mask_blocked(mask, ni):
				continue
			cand.append(Vector2i(nx, ny))
		if cand.is_empty():
			break
		var pick: Vector2i = cand[_hash16(cur.x, cur.y, ts + 13) % cand.size()]
		cur = pick
		path.append(cur)
	return path


## 地形生成主入口。返回 {"terrain_kind", "heights", "terrain_valid"}。
## 步骤（2026-10-24 Terrain 2.0）：极低频场 + 域扭曲 → 区域特征叠加 → 逐图分位量化
## → Spokes 投票平滑 / 小块合并 / 中值 → 基地地貌三选一 → 自然地形收尾
## → 净空塑形 → 低地走廊 → 微丘/台地最后落定 → 负高度补足 → 统计自检。
## 顺序纪律：一切「玩法标定面」（净空/走廊/微丘）必须晚于平滑类算子，否则会被当小凸台吃掉。
static func _generate_terrain(seed: int, salt: int, p: Dictionary, _is_default: bool) -> Dictionary:
	var ts: int = seed + salt * 7919 + 500009 # 独立盐域：与布局 RNG/噪声域去相关
	var kind: int = _hash16(seed, salt, 9101) % TERRAIN_COUNT
	var geom := _terrain_geom(p)
	var core: Vector2i = geom["core"]
	var mains: Array = geom["mains"]
	var heights: Array = []
	var ms: Array = []
	for y in 64:
		for x in 64:
			ms.append(_terrain_m(x, y, ts))
	# ①' 区域特征叠加（山丘/洼地成片出现）；再按本图分位量化到高度层
	_terrain_apply_features(ms, _terrain_features(seed, salt, geom, p))
	# 逐图分位阈值（m 场整体均值随盐漂移 → 用分位保证基础带稳定）
	var sorted: Array = ms.duplicate()
	sorted.sort()
	var th: Array = []
	th.append(int(sorted[4096 * BASE_NEG2_PERM / 1000]))
	th.append(int(sorted[4096 * BASE_NEG1_PERM / 1000]))
	th.append(int(sorted[4096 * BASE_H1_PERM / 1000]))
	th.append(int(sorted[4096 * BASE_H2_PERM / 1000]))
	th.append(int(sorted[4096 * BASE_H3_PERM / 1000]))
	th.append(int(sorted[4096 * BASE_H4_PERM / 1000]))
	for i in 4096:
		heights.append(_terrain_base(int(ms[i]), th))
	# ② 成片化三连：投票平滑 3 遍（Spokes）→ 小块合并 2 遍（<8 格并入邻块）→ 中值 1 遍（去尖点）
	heights = _terrain_smooth_vote(heights, 3)
	heights = _terrain_merge_small(heights, 8, 2)
	heights = _terrain_median(heights)
	# ③ 基地地貌塑形（允许基地断崖带出现 ≥3 落差）
	var ux := 0
	var uy := 0
	var dl := core.x
	var dr := 63 - core.x
	var dt := core.y
	var db := 63 - core.y
	var mn: int = mini(mini(dl, dr), mini(dt, db))
	if mn == dl:
		ux = -1
	elif mn == dr:
		ux = 1
	elif mn == dt:
		uy = -1
	else:
		uy = 1
	for y in range(maxi(core.y - 8, 0), mini(core.y + 9, 64)):
		for x in range(maxi(core.x - 8, 0), mini(core.x + 9, 64)):
			var i: int = y * 64 + x
			var d: int = Grid.hex_dist(x, y, core.x, core.y)
			if kind == TERRAIN_PLAIN:
				if d <= 5:
					heights[i] = 0
			elif kind == TERRAIN_CLIFF:
				if d <= 2:
					heights[i] = 0
				elif d >= 4 and d <= 6:
					# 朝最近边界半环带（连续断崖）；入口由低地走廊兜底
					if (x - core.x) * ux + (y - core.y) * uy >= 0 and int(heights[i]) < 3:
						heights[i] = 3
			else:
				# 山腰：朝场心单一方向每 3 格降 1（等高线为直线）
				var s: int = (x - core.x) * (-ux) + (y - core.y) * (-uy)
				if s >= 0:
					heights[i] = clampi(2 - Lua64.idiv(s, 3), 0, 2)
	# ④ 自然地形收尾：再吃一遍不足 6 格的小块（基地塑形会再生零碎凸台）。
	# 必须放在所有「玩法塑形」之前——净空/走廊/微丘是标定面，最后落定不许再被平滑改动。
	heights = _terrain_merge_small(heights, 6, 1)
	# ⑤ 净空塑形
	for m in mains:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				_terrain_set(heights, int(m.x) + dx, int(m.y) + dy, 0)
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				if absi(dx) == 2 or absi(dy) == 2:
					_terrain_clamp(heights, int(m.x) + dx, int(m.y) + dy, 0, 1)
	var hero: Vector2i = geom["hero"]
	_terrain_set(heights, hero.x, hero.y, 0)
	var basin: Rect2i = geom["basin"]
	for y in range(basin.position.y + 1, basin.position.y + basin.size.y - 1):
		for x in range(basin.position.x + 1, basin.position.x + basin.size.x - 1):
			_terrain_set(heights, x, y, 0)
	var plug: Vector2i = geom["plug"]
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			_terrain_set(heights, plug.x + dx, plug.y + dy, 0)
	var ores: Array = []
	ores.append_array(geom["mid_ore"])
	ores.append_array(geom["basin_ore"])
	for o in ores:
		_terrain_clamp(heights, int(o.x), int(o.y), 0, 1)
		for k in 6:
			_terrain_clamp(heights, Grid.nx(o.x, o.y, k), Grid.ny(o.x, o.y, k), 0, 1)
	# ⑥ 低地走廊（沿真实可通行最短路；核心邻格抬到 h_core-1 保证蛮兽能进）
	var mask: Array = _terrain_mask(p, geom)
	var bfs: Array = _terrain_bfs(mask, core)
	var corr: Dictionary = {}
	for m in mains:
		var path: Array = _terrain_path(bfs, mask, Vector2i(m.x, m.y), core, ts)
		for c in path:
			corr[str(c.x) + "," + str(c.y)] = true
			if c.x == core.x and c.y == core.y:
				continue
			_terrain_clamp(heights, c.x, c.y, 0, 1)
		for c in path:
			if c.x == core.x and c.y == core.y:
				continue
			for k in 6:
				_terrain_clamp(heights, Grid.nx(c.x, c.y, k), Grid.ny(c.x, c.y, k), 0, 2)
		for c in path:
			if Grid.hex_dist(c.x, c.y, core.x, core.y) == 1:
				heights[c.y * 64 + c.x] = maxi(int(heights[c.y * 64 + c.x]), core_h_min(kind))
	# ⑥a 布局地貌落高（必须放在最后：小块合并会把孤立 h1 微丘/2×2 台地当小凸台吃掉，
	# 而建图校验要求这些格恒为 h1 —— 玩法标定的地貌必须压过视觉平滑）
	if bool(p.get("freeform", false)):
		for hc in p["hills"]:
			heights[int(hc.y) * 64 + int(hc.x)] = 1
	else:
		var mx: int = p["mesa_x"]
		var my: int = p["mesa_y"]
		if mx >= 0:
			for dy in 2:
				for dx in 2:
					_terrain_set(heights, mx + dx, my + dy, 1)
	# ⑦ 负高度补足：限坡会把小坑压平 → 不足 20‰ 时显式放置洼地
	var neg_now := 0
	for i in 4096:
		if int(heights[i]) < 0:
			neg_now += 1
	if neg_now * 1000 / 4096 < TERRAIN_NEG_LO:
		_terrain_depressions(heights, seed, salt, geom, mains, corr, p)
	# ⑧ 统计自检
	var nz := 0
	var neg := 0
	var hi := 0
	for i in 4096:
		var v: int = heights[i]
		if v != 0:
			nz += 1
		if v < 0:
			neg += 1
		if v >= 3:
			hi += 1
	var nz_perm := nz * 1000 / 4096
	var neg_perm := neg * 1000 / 4096
	var valid: bool = nz_perm >= TERRAIN_NZ_LO and nz_perm <= TERRAIN_NZ_HI \
		and neg_perm >= TERRAIN_NEG_LO and neg_perm <= TERRAIN_NEG_HI \
		and hi >= TERRAIN_HI_MIN
	return { "terrain_kind": kind, "heights": heights, "terrain_valid": valid }


## 核心邻格最低允许高度（保证蛮兽从邻格跨入核心时爬升 ≤1）。
static func core_h_min(kind: int) -> int:
	if kind == TERRAIN_SLOPE:
		return 1
	return 0
