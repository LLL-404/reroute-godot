class_name SeedCode
extends RefCounted

# 世界种子编解码（2026-10-24 种子入口）：玩家输入的文字 ↔ 布局/世界用的 31 位正整数种子。
# 纪律：纯整数、无浮点、不依赖 game/；同文字恒等输出（回归锚点见 tests/test_seed_codec.gd）。
# 约定：from_text 返回 0 = 「调用方当作随机种子」，不进哈希；其余结果恒 ≥ 1。

const MAX_LEN := 24 # 可见字符上限（超长截断，避免玩家粘一长串把哈希拖成无意义值）
# FNV-1a/32 常量（与 sim/canon.gd 同源：offset basis 0x811C9DC5、prime 0x01000193）。
const FNV_OFFSET := 2166136261
const FNV_PRIME := 16777619


## 文字 → 种子。空/全空白返回 0（0 = 随机，不进哈希）；数字直通，其余走 FNV-1a/32。
static func from_text(text: String) -> int:
	var s := text.strip_edges()
	if s.length() > MAX_LEN:
		s = s.substr(0, MAX_LEN) # 只取前 MAX_LEN 个字符（字符而非字节，中文不会被切坏）
	if s.is_empty():
		return 0 # 空输入 = 交给调用方摇随机种子；这里返回 0 而不哈希，避免「空串也有一张固定图」
	if is_numeric(s):
		# 数字种子直通玩家本意；只留低 31 位（与 randi() 的 31 位口径一致，且恒为正）。
		# 低 31 位恰好为 0 时返回 1：0 已被「随机」占用，不能当成有效种子。
		var v := s.to_int() & 0x7FFFFFFF
		return 1 if v == 0 else v
	var h := FNV_OFFSET
	for i in s.length():
		# FNV-1a：先异或字符码点再乘质数，每步截回 32 位（中文码点 > 255 也按码点参与）。
		h = ((h ^ s.unicode_at(i)) * FNV_PRIME) & 0xFFFFFFFF
	h = h & 0x7FFFFFFF # 取 31 位保正数（MapGen/Rng 的种子口径）
	return 1 if h == 0 else h # 同数字分支：0 是「随机」保留值


## 是否为纯数字（去首尾空白后非空、只含 ASCII '0'..'9'；全角数字不算）。
static func is_numeric(text: String) -> bool:
	var s := text.strip_edges()
	if s.is_empty():
		return false
	for i in s.length():
		var c := s.unicode_at(i)
		if c < 48 or c > 57: # '0'..'9'
			return false
	return true


## 种子 → 文本（HUD / 日志 / 设置回填用）。
static func to_text(seed: int) -> String:
	return str(seed)
