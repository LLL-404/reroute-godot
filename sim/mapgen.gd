class_name MapGen
extends RefCounted

# 玩法地图布局生成器（2026-10-16「变奏级 + 高度微变」）：
# 结构模板固定（北岸台地 + 核心山头、双咽喉岩脊、西南盆地插口陷阱、南岸双出怪口），
# 在参数域内逐局变奏。纪律：
#   · 纯整数运算、唯一随机源 = sim Rng（SplitMix64）；同 (seed, salt) 恒等输出；
#   · 产物 = 布局参数字典（不建 Grid），结构不变量由 Scenario 侧校验；
#   · 参数域围绕手搓 64² 夹具标定的可行带（裸图路径长 L_ref=548，FlowField 直/斜 10/14 口径）；
#   · salt = 重采样盐：不变量校验失败时换盐重采，绝不修改产物本身。

# 咽喉宽度恒 3（西/东中心各取 ±1）：保 verify 脚本模板语义稳定。
const CHOKE_HALF := 1
const CHOKE_MIN_GAP := 15 # 双咽喉中心最小间距


## 采样一份布局参数。字段：
## core_x / ridge_y / choke_west / choke_east（谷口中心 x）
## basin_x0 / basin_y0 / basin_w / basin_h / plug_dx（插口 = 上缘第 plug_dx 列）
## mid_y（中场矿带行）/ sparse_phase（表土纹理相位）/ mesa_x / mesa_y（2×2 微丘左上角）
static func generate(seed: int, salt: int = 0) -> Dictionary:
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
