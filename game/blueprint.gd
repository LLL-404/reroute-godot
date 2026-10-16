extends RefCounted

# 程序化地形蓝图（移植 reroute/scripts/terrain_blueprint.lua）：蓝图 = 声明式图层配方，
# 视图层按配方组装地形高度与配色。积木全部是显式 seed 的纯函数。
# 隔离纪律：本系统的视图种子绝不进 sim/；战场高度对仿真与黄金指纹不存在。
# 本文件不使用 class_name；调用方以 preload 引用（规避 class_name 自引用类风险）。
# 2026-10-16 世界重做②（视觉，方案 §11.16）：场外重做「群山台地环抱」——紧贴场沿的环山体
# （周向崖顶起伏 + 南面出怪口豁口）+ 中距块状台地原 + 远山剪影；旧「缓降坡 + 极缓远降」删除。
# 场内高度肌理不动；整张蓝图仍为纯视觉（不进 sim/指纹）。
# 2026-10-16 视觉算法升级（对齐 shots/store 峡谷宣传图）：
#   ① vnoise 五次插值（C² 连续）→ 去格子感；
#   ② 域扭曲 fBm（p' = p + A·fbm(p)）→ 蜿蜒有机的肌理；
#   ③ 岩脊地标改「脊状 fBm 调制」（1-|2n-1|）→ 锯齿状山脊而非香肠形；
#   ④ 平滑台地量化（floor + smoothstep 立沿）→ 层层砂岩台地；
#   ⑤ 阈值化拉普拉斯扩散侵蚀（崖脚塌积；场内 0.5m 预烘焙网格 + 双线性采样）；
#   位置锚点接口：compose(bp, seed, anchor) 可把岩脊/盆地/前哨峰对齐到当局 Scenario。

const HALF := 32.0 # 与 view.CELL_N/2 同源；蓝图地标用格子坐标，composer 换算世界坐标

# ============ 积木库（纯函数） ============

## 64 位整数哈希。Lua 口径：乘加（回绕）+ 两级掩码；`~`=异或、`>>`=逻辑移。
## GDScript 整数同 64 位补码回绕（R1 探针已验），正数算术移 = 逻辑移；常量用十进制。
static func ihash(x: int, z: int, seed: int) -> float:
	var n: int = x * 374761393 + z * 668265263 + seed * 1013904223
	n = n & 9223372036854775807 # 0x7fffffffffffffff
	n = ((n ^ (n >> 13)) * 1274126177) & 2147483647 # 0x7fffffff
	return float(n) / 2147483647.0


static func vnoise(x: float, z: float, seed: int) -> float:
	var ix := int(floor(x))
	var iz := int(floor(z))
	var fx := x - float(ix)
	var fz := z - float(iz)
	var sx := fx * fx * fx * (fx * (fx * 6.0 - 15.0) + 10.0) # 五次插值（C² 连续，去格子感）
	var sz := fz * fz * fz * (fz * (fz * 6.0 - 15.0) + 10.0)
	var a := ihash(ix, iz, seed)
	var b := ihash(ix + 1, iz, seed)
	var c := ihash(ix, iz + 1, seed)
	var d := ihash(ix + 1, iz + 1, seed)
	return a + (b - a) * sx + (c - a) * sz + (a - b - c + d) * sx * sz


## 分形噪声：x/z 为预乘坐标（调用方先乘基频，offset 也在预乘空间），oct 各层倍频
## 2.07、逐层换 seed 防关联（与母版 ground_h 的 fbm 语义逐字一致）。
static func fbm(x: float, z: float, oct: int, seed: int) -> float:
	var sum := 0.0
	var amp := 0.5
	var f := 1.0
	var norm := 0.0
	for i in oct:
		sum += amp * vnoise(x * f, z * f, seed + (i + 1) * 7919)
		norm += amp
		amp *= 0.5
		f *= 2.07
	return sum / norm


static func gauss(d: float, s: float) -> float:
	return exp(-(d * d) / (2.0 * s * s))


static func smooth01(t: float) -> float:
	var tt := clampf(t, 0.0, 1.0)
	return tt * tt * (3.0 - 2.0 * tt)


# ============ composer：蓝图 + 种子 → 高度函数 ============

const FINE_N := 129 # 场内 0.5m 采样线（-32..32）；侵蚀烘焙网格分辨率
const FINE_STEP := 0.5


## 地标位置锚定：把预设地标（岩脊/盆地/前哨峰）的坐标对齐到当局 Scenario。
## anchor 键：ridge_y（岩脊行）/ basin_y（盆地中心行，float）/ core（Vector2i）。
## 缺省空字典 → 全用预设坐标（探针/自检的固定图口径不变）。
static func _anchored_landmarks(bp: Dictionary, anchor: Dictionary) -> Array:
	var out: Array = []
	for lm0 in bp["landmarks"]:
		var lm: Dictionary = (lm0 as Dictionary).duplicate()
		match String(lm["kind"]):
			"ridge":
				if anchor.has("ridge_y"):
					lm["y"] = int(anchor["ridge_y"])
			"basin":
				if anchor.has("basin_y"):
					lm["y"] = float(anchor["basin_y"])
			"peak":
				if anchor.has("core"):
					var c: Vector2i = anchor["core"]
					lm["x"] = c.x
					lm["y"] = c.y
		out.append(lm)
	return out


## 阈值化拉普拉斯扩散侵蚀：曲率高处（崖脚/立沿）平滑、平坦处不动（塌积观感）。
## 预烘焙场内 129² 网格（0.5m）；返回双线性采样函数，场外用解析原式（边界 Neumann 钳制无缝）。
static func _bake_eroded(base: Callable, iters: int) -> Callable:
	var n := FINE_N
	var g := PackedFloat64Array()
	g.resize(n * n)
	for j in n:
		var wz := -HALF + float(j) * FINE_STEP
		for i in n:
			g[j * n + i] = base.call(-HALF + float(i) * FINE_STEP, wz)
	for _it in iters:
		var ng := g.duplicate()
		for j in range(1, n - 1):
			var row := j * n
			for i in range(1, n - 1):
				var v := g[row + i]
				var lap := (g[row + i - 1] + g[row + i + 1] + g[row - n + i] + g[row + n + i]) * 0.25 - v
				var wgt := smooth01((absf(lap) - 0.04) / 0.18)
				ng[row + i] = v + lap * wgt * 0.85
		g = ng
	return func(wx: float, wz: float) -> float:
		if wx < -HALF or wx > HALF or wz < -HALF or wz > HALF:
			return base.call(wx, wz)
		var fx := (wx + HALF) / FINE_STEP
		var fz := (wz + HALF) / FINE_STEP
		var i0 := clampi(int(floor(fx)), 0, n - 1)
		var j0 := clampi(int(floor(fz)), 0, n - 1)
		var i1 := mini(i0 + 1, n - 1)
		var j1 := mini(j0 + 1, n - 1)
		var tx := clampf(fx - float(i0), 0.0, 1.0)
		var tz := clampf(fz - float(j0), 0.0, 1.0)
		var a := g[j0 * n + i0]
		var b := g[j0 * n + i1]
		var c := g[j1 * n + i0]
		var d := g[j1 * n + i1]
		return a + (b - a) * tx + (c - a) * tz + (a - b - c + d) * tx * tz


## 返回 [h_fn: Callable(wx, wz) -> float, palette: Dictionary]。
## 地标用格子坐标换算：wz_c = y - HALF + 0.5。
## 场外四层（g 门控渐入）：中频起伏 → 环山体（南面出怪口豁口）→ 台地原 → 远山剪影，
## 与场内无缝衔接；gate_x（世界坐标 x 列表）来自 anchor（当局 spawn 列）或预设缺省。
static func compose(bp: Dictionary, seed: int, anchor: Dictionary = {}) -> Array:
	var world: Dictionary = bp["world"]
	var micro: Dictionary = bp["micro"]
	var landmarks: Array = _anchored_landmarks(bp, anchor)
	var slope_w := float(world["slope_w"])
	var und_amp := float(world["und_amp"])
	var und_freq := float(world["und_freq"])
	var und_oct := int(world["und_oct"])
	var rim_h := float(world["rim_h"]) # 环山体高度（紧贴场沿隆起）
	var rim_w := float(world["rim_w"]) # 环山体外坡宽
	var rim_north := float(world.get("rim_north", 1.0)) # 北面背景山加高倍率（峡谷屏风）
	var mouth_s := float(world.get("mouth_s", 0.0)) # 南面出怪口豁口强度（0=整圈闭合）
	var mesa_h := float(world["mesa_h"]) # 中距台地原高度
	var mesa_freq := float(world["mesa_freq"])
	var mesa_start := float(world["mesa_start"])
	var mesa_w := float(world["mesa_w"])
	var sky_h := float(world["sky_h"]) # 远山剪影高度
	var sky_start := float(world["sky_start"])
	var sky_w := float(world["sky_w"])
	var gates: Array = anchor.get("gate_x", world.get("gate_x", []))
	var erode_iter := int(world.get("erode_iter", 0))
	var freq := float(micro["freq"])
	var off0 := float(micro["offset"][0])
	var off1 := float(micro["offset"][1])
	var amp_f := float(micro["amp_field"])
	var amp_e := float(micro["amp_edge"])
	var warp_a := float(micro.get("warp", 0.0)) # 域扭曲幅度（预乘空间）
	var m_oct := int(micro.get("oct", 2))
	var t_step := float(micro.get("terrace", 0.0)) # 台地量化步长（0=关）
	var h_fn := func(wx: float, wz: float) -> float:
		var d := maxf(absf(wx), absf(wz)) - (HALF - 0.5)
		var g := smooth01(d / slope_w) # 场外门控：0=场内 1=场外完全过渡
		var h := 0.0
		# 地表肌理：域扭曲 fBm（场内高频小起伏，向场外压低；远场淡出后跳过采样——成本门控）
		var m_fade := 1.0 - smooth01((g - 0.82) / 0.18) # g≥1 → 0（与 g 连续，无接缝）
		if m_fade > 0.003:
			var mx := wx * freq + off0
			var mz := wz * freq + off1
			var amp := (amp_f + (amp_e - amp_f) * g) * m_fade
			var m := 0.0
			if warp_a > 0.0:
				var wq := (fbm(mx * 0.47 + 17.3, mz * 0.47 - 9.4, 2, seed + 991) - 0.5) * 2.0
				var wr := (fbm(mx * 0.47 - 5.9, mz * 0.47 + 6.7, 2, seed + 992) - 0.5) * 2.0
				m = (fbm(mx + wq * warp_a, mz + wr * warp_a, m_oct, seed + 53) - 0.5) * amp
			else:
				m = (fbm(mx, mz, m_oct, seed + 53) - 0.5) * amp
			h = m
		# 平滑台地量化：floor 定层 + smoothstep 立沿（近场外淡出，避免与旷野抢戏）
		if t_step > 0.0:
			var q: float = floor(h / t_step) * t_step
			var fr: float = (h - q) / t_step
			var hv: float = q + t_step * smooth01(fr)
			h = h + (hv - h) * (1.0 - g * 0.7)
		if g > 0.0:
			# 场外四层（全部由 g 渐入）：中频起伏 / 环山体 / 台地原 / 远山剪影
			h += (fbm(wx * und_freq, wz * und_freq, und_oct, seed + 31) - 0.5) * und_amp * g
			var gv := fbm(wx * 0.021, wz * 0.021, 2, seed + 671)
			h -= 2.2 * smooth01(0.14 - absf(gv - 0.5)) * smooth01((d - 2.0) / 4.0)
			var g_rim := smooth01((d - 0.4) / rim_w)
			if g_rim > 0.0:
				var ra := fbm(wx * 0.017, wz * 0.017, 2, seed + 57)
				var rn := 1.0 - absf(2.0 * ra - 1.0)
				var crest := 0.75 + 0.40 * rn * rn
				var rscale := 1.0
				if mouth_s > 0.0 and wz > 2.0:
					var m := 0.0
					for gx in gates:
						var u := (wx - float(gx)) / 5.0
						m = maxf(m, exp(-u * u))
					rscale = 1.0 - mouth_s * m * smooth01((wz - 2.0) / 7.0) # 南面出怪口豁口
				var nb := 1.0 + (rim_north - 1.0) * smooth01((-wz - 4.0) / 14.0) # 北面加高（峡谷背景屏风）
				var rise := rim_h * g_rim * crest * rscale * nb
				var tq: float = floor(rise / 4.5) * 4.5
				var tf: float = (rise - tq) / 4.5
				h += tq + 4.5 * smooth01(tf * 1.6 - 0.3)
			var g_mesa := smooth01((d - mesa_start) / mesa_w)
			if g_mesa > 0.0:
				var mv := fbm(wx * mesa_freq, wz * mesa_freq, 3, seed + 811)
				var qv := smooth01((floor(mv * 5.0) * 0.2 - 0.28) / 0.30) # 平顶分层台地
				h += mesa_h * g_mesa * qv * (0.70 + 0.60 * fbm(wx * 0.031, wz * 0.031, 2, seed + 812))
			var g_sky := smooth01((d - sky_start) / sky_w)
			if g_sky > 0.0:
				h += sky_h * g_sky * (0.45 + 0.55 * fbm(wx * 0.011, wz * 0.011, 3, seed + 913))
		# 战场地标（位置可由 anchor 对齐当局 Scenario；幅度/形状由蓝图定）
		for lm in landmarks:
			if lm["kind"] == "peak":
				var dx := wx - (float(lm["x"]) - HALF + 0.5)
				var dz := wz - (float(lm["y"]) - HALF + 0.5)
				h += float(lm["amp"]) * gauss(sqrt(dx * dx + dz * dz), float(lm["sigma"]))
			elif lm["kind"] == "ridge":
				var rz := wz - (float(lm["y"]) - HALF + 0.5)
				var rr := gauss(rz, float(lm["sigma"]))
				if rr > 0.02: # 远处不采样脊状调制（成本门控）
					var rid := float(lm.get("ridged", 0.0))
					if rid > 0.0:
						var ra := fbm(wx * float(lm.get("rf", 0.075)) + 3.1, wz * float(lm.get("rf", 0.075)) - 1.7, 3, seed + 331)
						var rn := 1.0 - absf(2.0 * ra - 1.0) # 脊状调制：山脊沿走向起伏、锯齿化
						h += float(lm["amp"]) * rr * (1.0 - rid + rid * rn)
					else:
						h += float(lm["amp"]) * rr
			else:
				h += float(lm["amp"]) * gauss(wz - (float(lm["y"]) - HALF + 0.5), float(lm["sigma"]))
		return h
	if erode_iter <= 0:
		return [h_fn, bp["palette"]]
	return [_bake_eroded(h_fn, erode_iter), bp["palette"]]


# ============ 预设（配色守"暖沙石+蓝"锚；canyon = 现役参数） ============
# palette 三档高程色：h<band_lo_at 用 ground_lo，h>band_hi_at 用 ground_hi，其余 ground。

const PRESETS := {
	"canyon": {
		"schema": 1,
		"name": "canyon",
		"landmarks": [
			{ "kind": "ridge", "y": 41, "sigma": 2.6, "amp": 1.15, "ridged": 0.85, "rf": 0.075 },
			{ "kind": "basin", "y": 57.5, "sigma": 3.6, "amp": -0.9 },
			{ "kind": "peak", "x": 32, "y": 6, "sigma": 5.0, "amp": 0.75 },
		],
		"world": {
			"slope_w": 16.0,
			"rim_h": 18.0,
			"rim_w": 3.0,
			"rim_north": 1.7,
			"mouth_s": 0.85,
			"gate_x": [-10.5, 13.5, -25.5],
			"mesa_h": 16.0,
			"mesa_freq": 0.042,
			"mesa_start": 16.0,
			"mesa_w": 22.0,
			"sky_h": 52.0,
			"sky_start": 56.0,
			"sky_w": 90.0,
			"und_amp": 2.2,
			"und_freq": 0.050,
			"und_oct": 3,
			"erode_iter": 6,
		},
		"micro": { "freq": 0.17, "amp_field": 1.05, "amp_edge": 0.20, "offset": [-3.7, 9.1], "warp": 0.38, "oct": 3, "terrace": 0.30 },
		"palette": {
			"ground_lo": [0.285, 0.190, 0.115],
			"ground": [0.470, 0.330, 0.185],
			"ground_hi": [0.700, 0.545, 0.360],
			"rock": [0.360, 0.290, 0.215],
			"fog": [0.600, 0.470, 0.340],
			"band_lo_at": -0.25,
			"band_hi_at": 0.45,
			"fog_start": 58.0,
			"fog_end": 235.0,
		},
	},
	"shale": {
		"schema": 1,
		"name": "shale",
		"landmarks": [
			{ "kind": "ridge", "y": 41, "sigma": 3.2, "amp": 0.9, "ridged": 0.70, "rf": 0.06 },
			{ "kind": "basin", "y": 57.5, "sigma": 4.0, "amp": -0.7 },
			{ "kind": "peak", "x": 32, "y": 6, "sigma": 5.5, "amp": 0.6 },
		],
		"world": {
			"slope_w": 20.0,
			"rim_h": 12.5,
			"rim_w": 4.5,
			"rim_north": 1.5,
			"mouth_s": 0.80,
			"gate_x": [-10.5, 13.5, -25.5],
			"mesa_h": 12.0,
			"mesa_freq": 0.048,
			"mesa_start": 20.0,
			"mesa_w": 26.0,
			"sky_h": 36.0,
			"sky_start": 70.0,
			"sky_w": 100.0,
			"und_amp": 2.4,
			"und_freq": 0.042,
			"und_oct": 3,
			"erode_iter": 5,
		},
		"micro": { "freq": 0.13, "amp_field": 0.80, "amp_edge": 0.12, "offset": [8.8, -2.6], "warp": 0.50, "oct": 3, "terrace": 0.22 },
		"palette": {
			"ground_lo": [0.240, 0.260, 0.300],
			"ground": [0.380, 0.420, 0.470],
			"ground_hi": [0.520, 0.570, 0.620],
			"rock": [0.340, 0.370, 0.420],
			"fog": [0.420, 0.500, 0.620],
			"band_lo_at": -0.20,
			"band_hi_at": 0.40,
			"fog_start": 55.0,
			"fog_end": 215.0,
		},
	},
	"ember": {
		"schema": 1,
		"name": "ember",
		"landmarks": [
			{ "kind": "ridge", "y": 41, "sigma": 2.0, "amp": 1.4, "ridged": 0.95, "rf": 0.09 },
			{ "kind": "basin", "y": 57.5, "sigma": 3.2, "amp": -1.0 },
			{ "kind": "peak", "x": 32, "y": 6, "sigma": 4.5, "amp": 0.85 },
		],
		"world": {
			"slope_w": 13.0,
			"rim_h": 21.0,
			"rim_w": 2.5,
			"rim_north": 1.8,
			"mouth_s": 0.85,
			"gate_x": [-10.5, 13.5, -25.5],
			"mesa_h": 18.0,
			"mesa_freq": 0.038,
			"mesa_start": 14.0,
			"mesa_w": 18.0,
			"sky_h": 58.0,
			"sky_start": 48.0,
			"sky_w": 84.0,
			"und_amp": 1.6,
			"und_freq": 0.060,
			"und_oct": 4,
			"erode_iter": 8,
		},
		"micro": { "freq": 0.21, "amp_field": 1.00, "amp_edge": 0.2, "offset": [2.4, 11.7], "warp": 0.30, "oct": 3, "terrace": 0.40 },
		"palette": {
			"ground_lo": [0.330, 0.200, 0.130],
			"ground": [0.500, 0.300, 0.180],
			"ground_hi": [0.640, 0.410, 0.250],
			"rock": [0.420, 0.300, 0.200],
			"fog": [0.620, 0.420, 0.280],
			"band_lo_at": -0.30,
			"band_hi_at": 0.50,
			"fog_start": 60.0,
			"fog_end": 240.0,
		},
	},
}

const ORDER := ["canyon", "shale", "ember"]


## 按名取蓝图（缺名即崩，同母版 assert 口径）。
static func get_preset(name: String) -> Dictionary:
	var bp = PRESETS.get(name)
	assert(bp != null, "[蓝图] 未知预设：" + name)
	return bp


## 逐局轮换：按 run_index 轮预设，并派生独立视图种子（绝不与仿真种子共源共用）。
## 返回 [bp, seed]。
static func pick(run_index: int) -> Array:
	var name: String = ORDER[(run_index - 1) % ORDER.size()]
	return [PRESETS[name], 104729 * run_index + 20261005]
