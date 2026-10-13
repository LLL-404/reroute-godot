class_name Rng
extends RefCounted

# SplitMix64，逐字照搬 warden/Warden.Core/Rng.cs（含它的乘数常量——
# 第一个乘数与教科书 SplitMix64 不同，确定性只要求两边同式，以母体为准）。
# 常量已转带符号十进制（GDScript 大 hex 字面量钳位，见 lua64.gd 头注）：
#   GAMMA = 0x9E3779B97F4A7C15 / MULT1 = 0xBF036339283177D5 / MULT2 = 0x94D049BB133111EB
# GDScript int64 加法/乘法越界回绕、位运算位型一致，与 Lua 5.4 / C# unchecked ulong 逐位对齐；
# 右移经 Lua64.lshr 补LogicZero。模拟层唯一随机源；禁止任何全局/时间种子。
const GAMMA := -7046029254386353131
const MULT1 := -4682790090396567595
const MULT2 := -7723592293110705685

# 自检向量：warden 同式算法独立生成（seed 12345 前 3 个 + seed 0 前 1 个）。
const VECTORS := [
	{
		"seed": 12345,
		"values": [-6625294847243934029, 278976177861657314, 6221043495009484855],
	},
	{
		"seed": 0,
		"values": [-5093384982049193912],
	},
]

var state: int


func _init(seed: int) -> void:
	state = seed


func restore(s: int) -> void:
	state = s


func next_u64() -> int:
	var s := state + GAMMA # 加法自然回绕 = ulong 语义
	state = s
	var z := s
	z = (z ^ Lua64.lshr(z, 30)) * MULT1
	z = (z ^ Lua64.lshr(z, 27)) * MULT2
	z = z ^ Lua64.lshr(z, 31)
	return z


## [0, maxExclusive)；maxExclusive <= 1 时返回 0（照搬母体口径）。
func next_int(max_exclusive: int) -> int:
	if max_exclusive <= 1:
		return 0
	return Lua64.mod(next_u64(), max_exclusive)


## 自检：向量这组数错任何一个 = 64 位语义在移植中坏了，不是测试写错了。
static func selftest() -> Array:
	for tv in VECTORS:
		var r := Rng.new(tv["seed"])
		for i in tv["values"].size():
			var want: int = tv["values"][i]
			var got := r.next_u64()
			if got != want:
				return [false, "rng 向量不符 seed=%d i=%d" % [tv["seed"], i]]
	return [true, ""]
