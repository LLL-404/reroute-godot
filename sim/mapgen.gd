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
static func generate(seed: int, salt: int = 0, is_default: bool = false) -> Dictionary:
	if is_default:
		return _generate_default(seed, salt)
	if salt < FREEFORM_SALT_MAX:
		return _generate_freeform(seed, salt)
	return _generate_varied_legacy(seed, salt - FREEFORM_SALT_MAX)


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
