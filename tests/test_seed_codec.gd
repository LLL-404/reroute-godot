extends RefCounted

# seed 单测（2026-10-24 世界种子入口）：数字直通 / 文字哈希锚点 / 空白=随机 / 截断 /
# 纯数字判定 / Scenario 可用性。锚点：由本实现生成，用于防漂移（重构改哈希须有意同步）。


func register(kit: TestKit) -> void:
	kit.module("seed")

	kit.test("numeric-passthrough", func():
		kit.eq(SeedCode.from_text("20261007"), 20261007, "数字种子直通")
		kit.eq(SeedCode.from_text(" 123 "), 123, "首尾空白剥掉")
		kit.eq(SeedCode.from_text("0007"), 7, "前导零不改变数值")
		kit.eq(SeedCode.to_text(20261007), "20261007", "to_text"))

	kit.test("numeric-zero-clamp", func():
		kit.eq(SeedCode.from_text("0"), 1, "0 是随机保留值 → 1")
		kit.eq(SeedCode.from_text("000"), 1, "全零 → 1")
		kit.eq(SeedCode.from_text("2147483648"), 1, "低 31 位为 0 → 1（2^31）"))

	kit.test("text-anchors", func():
		# 锚点：由本实现生成，用于防漂移（同一文字必须永远同一数字）
		kit.eq(SeedCode.from_text("dragon"), 2014328350, "dragon 锚点")
		kit.eq(SeedCode.from_text("改道"), 1335875493, "改道 锚点（中文码点参与）")
		kit.eq(SeedCode.from_text("Hello World"), 865084711, "Hello World 锚点")
		kit.eq(SeedCode.from_text("dragon"), SeedCode.from_text("dragon"), "同文字两次不一致"))

	kit.test("blank-is-random", func():
		kit.eq(SeedCode.from_text(""), 0, "空串 = 随机（0 不进哈希）")
		kit.eq(SeedCode.from_text("   "), 0, "全空白 = 随机"))

	kit.test("truncate-24", func():
		var s24 := "abcdefghijklmnopqrstuvwx" # 24 个字符 = MAX_LEN
		var s25 := s24 + "y"
		kit.eq(SeedCode.from_text(s25), SeedCode.from_text(s24), "第 25 个字符不参与哈希")
		kit.eq(SeedCode.from_text(s24), 926968317, "24 字符锚点"))

	kit.test("is-numeric", func():
		kit.ok(not SeedCode.is_numeric("12a"), "含字母不算数字")
		kit.ok(not SeedCode.is_numeric("１２"), "全角数字不算（只认 ASCII 0..9）")
		kit.ok(SeedCode.is_numeric("007"), "前导零仍算数字")
		kit.ok(not SeedCode.is_numeric(""), "空串不算数字")
		kit.ok(not SeedCode.is_numeric("   "), "全空白不算数字"))

	kit.test("scenario-usable", func():
		kit.ok(Scenario.usable(Scenario.DEFAULT_SEED), "默认种子可用")
		kit.ok(not Scenario.new(Scenario.DEFAULT_SEED).gen_failed, "默认种子 gen_failed=false"))
