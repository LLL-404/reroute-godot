class_name MapGen
extends RefCounted

# 玩法地图布局生成器（2026-10-17 G2 模板池：玩法结构逐局变幅）。
# 两条生成路径（冻结纪律）：
#   · _generate_default：DEFAULT_SEED 专用，参数流字节级冻结（2026-10-16 第三次基线重录口径），
#     恒为 T0 横脊 —— 保剧本指纹 0x7dea2b02 与黄金脚本口径不被 V1 改动扰动；
#   · _generate_varied：其余种子，五模板池（T0..T4）+ 加宽参数域 + 模板专属参数。
# 结构：北岸台地 + 核心山头、横向屏障（形状随模板）、西南盆地插口陷阱、南岸双出怪口。
# 纪律：纯整数、唯一随机源 = sim Rng；同 (seed, salt, is_default) 恒等输出；
# 产物 = 布局参数字典（不建 Grid），结构不变量由 Scenario 侧校验（含裸图路径长带）。
# 模板几何静态面：band_rows（列屏障行）/ gate_rows（咽喉口行）/ extra_walls（附壁）/ carved（缺口）。
# 咽喉宽度恒 3（口心 ±1）；漏斗墙行等脚本行口径 = 「咽喉口行 c.y」相对（见 verify.gd）。

const TEMPLATE_COUNT := 5
const TEMPLATE_NAMES := ["横脊", "错行双脊", "弧脊", "斜壁", "獠牙翼"]
const CHOKE_HALF := 1
const CHOKE_MIN_GAP := 15 # 双咽喉中心最小间距

# 弧脊抛物线分母：v(x) = (x-1)(62-x) 在 x∈1..62 上最大 930（中点对称）。
const ARC_V_MAX := 930


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
## 公共字段：template / core_x / ridge_y / choke_west / choke_east（谷口中心 x）
## basin_x0 / basin_y0 / basin_w / basin_h / plug_dx（插口 = 上缘第 plug_dx 列）
## mid_y（中场矿带行）/ sparse_phase（表土纹理相位）/ mesa_x / mesa_y（2×2 微丘左上角）
## 模板专属：T1 split_x（错行分界列）/ T2 bow（弧脊垂幅）/ T3 slope_dy（斜壁斜率行差，带符号）/ T4 wing_len（獠牙翼长）。
static func generate(seed: int, salt: int = 0, is_default: bool = false) -> Dictionary:
	if is_default:
		return _generate_default(seed, salt)
	return _generate_varied(seed, salt)


static func _generate_varied(seed: int, salt: int) -> Dictionary:
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
