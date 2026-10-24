extends SceneTree

# 单测入口（cwd=reroute-godot）：godot --headless -s res://tests/run_tests.gd
# 保真闸（rng 向量 / FNV 锚点 / 流场语义）+ 七模块用例。exit 0 = 全绿。
func _initialize() -> void:
	var kit := TestKit.new()

	kit.module("fidelity")
	kit.test("rng-vectors", func():
		var r := Rng.new(12345)
		kit.eq(r.next_u64(), -6625294847243934029, "seed=12345 i=1")
		kit.eq(r.next_u64(), 278976177861657314, "seed=12345 i=2")
		kit.eq(r.next_u64(), 6221043495009484855, "seed=12345 i=3")
		var r0 := Rng.new(0)
		kit.eq(r0.next_u64(), -5093384982049193912, "seed=0 i=1"))
	kit.test("canon-anchors", func():
		var b := Canon.buffer()
		kit.eq(b.fingerprint(), Canon.FNV_OFFSET, "FNV 空串锚点")
		var fb := Canon.buffer()
		for i in "foobar".length():
			fb.put_u8("foobar".unicode_at(i))
		kit.eq(fb.fingerprint(), 3214735720, "FNV foobar 锚点"))

	preload("res://tests/test_rng.gd").new().register(kit)
	preload("res://tests/test_seed_codec.gd").new().register(kit)
	preload("res://tests/test_canon.gd").new().register(kit)
	preload("res://tests/test_grid.gd").new().register(kit)
	preload("res://tests/test_flowfield.gd").new().register(kit)
	preload("res://tests/test_mapgen.gd").new().register(kit)
	preload("res://tests/test_scenario.gd").new().register(kit)
	preload("res://tests/test_world.gd").new().register(kit)
	preload("res://tests/test_save.gd").new().register(kit)
	preload("res://tests/test_verify.gd").new().register(kit)

	var ok := kit.run()
	quit(0 if ok else 1)
