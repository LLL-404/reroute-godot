class_name Canon
extends RefCounted

# 规范字节编码 + FNV-1a/32 指纹，照搬 warden/Warden.Core/Canon.cs 的口径：
# 大端、字段定序、集合按 id 升序。本作 STATE_SCHEMA 独立从 1 起。
# v6（2026-10-17）：六边形拓扑上线——字段布局不变，但移动/寻路语义变 ⇒ 旧档（v5 方形）拒载。
# 常量来源：Lua 版 scripts/sim/canon.lua 逐行对照；>=2^63 的期望值已转带符号十进制
# （GDScript 大 hex 字面量会被钳位，见 lua64.gd 头注）。
const STATE_SCHEMA := 6
const FNV_OFFSET := 2166136261 # 0x811C9DC5
const FNV_PRIME := 16777619 # 0x01000193
const MASK32 := 4294967296 # 0x100000000


class Buf extends RefCounted:
	var data := PackedByteArray()

	func put_u8(v: int) -> void:
		data.append(Lua64.mod(v, 256)) # 负数/超宽值统一取位型低 8 位

	func put_u32(v: int) -> void: # 32 位位型，大端
		var u := Lua64.mod(v, MASK32)
		data.append((u >> 24) & 0xFF)
		data.append((u >> 16) & 0xFF)
		data.append((u >> 8) & 0xFF)
		data.append(u & 0xFF)

	func put_i32(v: int) -> void: # 有符号 32 位 = 其位型
		put_u32(Lua64.mod(v, MASK32))

	func put_u64(v: int) -> void: # 64 位位型，大端（v 可为负：回绕后的位型）
		data.append(Lua64.lshr(v, 56) & 0xFF)
		data.append(Lua64.lshr(v, 48) & 0xFF)
		data.append(Lua64.lshr(v, 40) & 0xFF)
		data.append(Lua64.lshr(v, 32) & 0xFF)
		data.append(Lua64.lshr(v, 24) & 0xFF)
		data.append(Lua64.lshr(v, 16) & 0xFF)
		data.append(Lua64.lshr(v, 8) & 0xFF)
		data.append(v & 0xFF)

	func fingerprint() -> int:
		return Canon.fnv1a32(data, data.size())


## 新建编码缓冲（Buf 工厂；put_* 系列按字段序书写）
static func buffer() -> Canon.Buf:
	return Canon.Buf.new()


## FNV-1a/32。锚点：空串 = 811c9dc5，"foobar" = bf9cf968（母体 Canon.cs 同款自检）。
static func fnv1a32(bytes: PackedByteArray, n: int = -1) -> int:
	if n < 0:
		n = bytes.size()
	var h := FNV_OFFSET
	for i in n:
		h = (h ^ bytes[i]) % MASK32
		h = (h * FNV_PRIME) % MASK32
	return h


## 自检：双锚点 + 负对照（改一个字节指纹必须变）。
static func selftest() -> Array:
	var b := buffer()
	if b.fingerprint() != FNV_OFFSET:
		return [false, "FNV 锚点失败：空串"]
	var fb := buffer()
	for i in "foobar".length():
		fb.put_u8("foobar".unicode_at(i))
	if fb.fingerprint() != 3214735720: # 0xBF9CF968
		return [false, "FNV 锚点失败：foobar"]
	var a := buffer()
	a.put_u32(123456)
	var c := buffer()
	c.put_u32(123457)
	if a.fingerprint() == c.fingerprint():
		return [false, "FNV 负对照失败：不同内容同指纹"]
	return [true, ""]
