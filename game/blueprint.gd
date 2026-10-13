extends RefCounted

# 程序化地形蓝图（移植 reroute/scripts/terrain_blueprint.lua）：蓝图 = 声明式图层配方，
# 视图层按配方组装地形高度与配色。积木全部是显式 seed 的纯函数。
# 隔离纪律：本系统的视图种子绝不进 sim/；战场高度对仿真与黄金指纹不存在。
# 本文件不使用 class_name；调用方以 preload 引用（规避 class_name 自引用类风险）。

const HALF := 24.0 # 与 view.CELL_N/2 同源；蓝图地标用格子坐标，composer 换算世界坐标

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
	var sx := fx * fx * (3.0 - 2.0 * fx)
	var sz := fz * fz * (3.0 - 2.0 * fz)
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

## 返回 [h_fn: Callable(wx, wz) -> float, palette: Dictionary]。
## 地标用格子坐标换算：wz_c = y - HALF + 0.5。
static func compose(bp: Dictionary, seed: int) -> Array:
	var world: Dictionary = bp["world"]
	var micro: Dictionary = bp["micro"]
	var warp: Dictionary = world["warp"]
	var shape: Dictionary = world["shape"]
	var landmarks: Array = bp["landmarks"]
	var exponent := float(world.get("exponent", 1.0))
	var h_fn := func(wx: float, wz: float) -> float:
		var d := maxf(absf(wx), absf(wz)) - (HALF - 0.5)
		var t := smooth01(d / float(micro["reach"]))
		# 山体：距离场经噪声扭曲（破方形容差）后隆起
		var dw := d + float(warp["amp"]) * (fbm(wx * float(warp["freq"]) + float(warp["offset"][0]), wz * float(warp["freq"]) + float(warp["offset"][1]), int(warp["oct"]), seed + 11) - 0.5) * 2.0
		var mountain := pow(smooth01(dw / float(world["reach"])), exponent) * (float(shape["base"]) + float(shape["span"]) * fbm(wx * float(world["freq"]), wz * float(world["freq"]), int(world["oct"]), seed + 31))
		# 地表肌理：场内高频小起伏，向场外压低
		var m := (fbm(wx * float(micro["freq"]) + float(micro["offset"][0]), wz * float(micro["freq"]) + float(micro["offset"][1]), 2, seed + 53) - 0.5) * (float(micro["amp_field"]) + (float(micro["amp_edge"]) - float(micro["amp_field"])) * t)
		# 战场地标（位置固定保玩法可读，幅度由蓝图定）
		var h := mountain + m
		for lm in landmarks:
			if lm["kind"] == "peak":
				var dx := wx - (float(lm["x"]) - HALF + 0.5)
				var dz := wz - (float(lm["y"]) - HALF + 0.5)
				h += float(lm["amp"]) * gauss(sqrt(dx * dx + dz * dz), float(lm["sigma"]))
			else:
				h += float(lm["amp"]) * gauss(wz - (float(lm["y"]) - HALF + 0.5), float(lm["sigma"]))
		return h
	return [h_fn, bp["palette"]]


# ============ 预设（配色守"暖沙石+蓝"锚；canyon = 现役参数） ============
# palette 三档高程色：h<band_lo_at 用 ground_lo，h>band_hi_at 用 ground_hi，其余 ground。

const PRESETS := {
	"canyon": {
		"schema": 1,
		"name": "canyon",
		"landmarks": [
			{ "kind": "ridge", "y": 31, "sigma": 2.6, "amp": 1.15 },
			{ "kind": "basin", "y": 40.5, "sigma": 3.6, "amp": -0.9 },
			{ "kind": "peak", "x": 24, "y": 6, "sigma": 5.0, "amp": 0.75 },
		],
		"world": {
			"reach": 42.0,
			"exponent": 1.35,
			"warp": { "freq": 0.045, "amp": 14.0, "oct": 2, "offset": [5.2, -1.3] },
			"shape": { "base": 5.0, "span": 30.0 },
			"freq": 0.021,
			"oct": 3,
		},
		"micro": { "freq": 0.17, "reach": 34.0, "amp_field": 0.45, "amp_edge": 0.17, "offset": [-3.7, 9.1] },
		"palette": {
			"ground_lo": [0.150, 0.140, 0.115],
			"ground": [0.215, 0.205, 0.170],
			"ground_hi": [0.290, 0.280, 0.235],
			"rock": [0.165, 0.155, 0.145],
			"fog": [0.305, 0.285, 0.265],
			"band_lo_at": -0.25,
			"band_hi_at": 0.45,
			"fog_start": 55.0,
			"fog_end": 170.0,
		},
	},
	"shale": {
		"schema": 1,
		"name": "shale",
		"landmarks": [
			{ "kind": "ridge", "y": 31, "sigma": 3.2, "amp": 0.9 },
			{ "kind": "basin", "y": 40.5, "sigma": 4.0, "amp": -0.7 },
			{ "kind": "peak", "x": 24, "y": 6, "sigma": 5.5, "amp": 0.6 },
		],
		"world": {
			"reach": 50.0,
			"exponent": 1.2,
			"warp": { "freq": 0.038, "amp": 18.0, "oct": 2, "offset": [1.9, 7.4] },
			"shape": { "base": 4.0, "span": 22.0 },
			"freq": 0.016,
			"oct": 3,
		},
		"micro": { "freq": 0.13, "reach": 34.0, "amp_field": 0.35, "amp_edge": 0.12, "offset": [8.8, -2.6] },
		"palette": {
			"ground_lo": [0.125, 0.130, 0.145],
			"ground": [0.185, 0.195, 0.215],
			"ground_hi": [0.255, 0.265, 0.290],
			"rock": [0.150, 0.155, 0.175],
			"fog": [0.220, 0.270, 0.360],
			"band_lo_at": -0.20,
			"band_hi_at": 0.40,
			"fog_start": 45.0,
			"fog_end": 150.0,
		},
	},
	"ember": {
		"schema": 1,
		"name": "ember",
		"landmarks": [
			{ "kind": "ridge", "y": 31, "sigma": 2.0, "amp": 1.4 },
			{ "kind": "basin", "y": 40.5, "sigma": 3.2, "amp": -1.0 },
			{ "kind": "peak", "x": 24, "y": 6, "sigma": 4.5, "amp": 0.85 },
		],
		"world": {
			"reach": 38.0,
			"exponent": 1.2,
			"warp": { "freq": 0.052, "amp": 12.0, "oct": 2, "offset": [-6.1, 3.3] },
			"shape": { "base": 7.0, "span": 34.0 },
			"freq": 0.028,
			"oct": 3,
		},
		"micro": { "freq": 0.21, "reach": 34.0, "amp_field": 0.5, "amp_edge": 0.2, "offset": [2.4, 11.7] },
		"palette": {
			"ground_lo": [0.160, 0.115, 0.090],
			"ground": [0.240, 0.180, 0.140],
			"ground_hi": [0.320, 0.245, 0.185],
			"rock": [0.185, 0.150, 0.125],
			"fog": [0.330, 0.280, 0.240],
			"band_lo_at": -0.30,
			"band_hi_at": 0.50,
			"fog_start": 60.0,
			"fog_end": 185.0,
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
