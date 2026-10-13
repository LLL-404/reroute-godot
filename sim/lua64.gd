class_name Lua64
extends RefCounted

# Lua 5.4 64 位整数语义仿真层（GDScript int 即 int64，多数直译，三处需修正）。
# 依据 2026-10-13 探针实测（Godot 4.7.2）：
#   * + << & | ^ ~ 与 Lua 位型/回绕一致 → 直译
#   * * 越界回绕（(1<<62)*4=0）→ 直译
#   * >> 对负值是算术移（Lua 逻辑移补零）→ lshr
#   * % 对负被除数是截尾（Lua 向下取整）→ mod
#   * 无 // 运算符 → idiv（sim 内被除数均 < 2^53，float 通道精确）
# 大常量禁用 hex 字面量（>=2^63 会被钳位并报错），一律带符号十进制。


## Lua 5.4 逻辑右移（补零）。z 为 int64 位型（可负），n ∈ [1,63]。
static func lshr(z: int, n: int) -> int:
	if n <= 0:
		return z
	if n >= 64:
		return 0
	var r := z >> n # GDScript 算术移（符号扩展）
	if z < 0:
		r += 1 << (64 - n) # 补回高位；n=1 时 1<<63 回绕成 INT64_MIN，位型上恰为 +2^63
	return r


## Lua 5.4 取模（向下取整，结果符号跟除数）。调用方保证 b > 0。
static func mod(a: int, b: int) -> int:
	var r := a % b
	if r < 0:
		r += b
	return r


## Lua 5.4 整除 //（向下取整）。sim 内被除数绝对值 < 2^53，float 通道精确。
static func idiv(a: int, b: int) -> int:
	return int((a - mod(a, b)) / b)
