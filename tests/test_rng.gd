extends RefCounted

# rng 单测（移植自 reroute/tests/test_rng.lua）：向量 + next_int 边界 + restore + 同种子同流。


func register(kit: TestKit) -> void:
	kit.module("rng")

	kit.test("vectors", func():
		var r := Rng.new(12345)
		kit.eq(r.next_u64(), -6625294847243934029, "seed=12345 i=1")
		kit.eq(r.next_u64(), 278976177861657314, "seed=12345 i=2")
		kit.eq(r.next_u64(), 6221043495009484855, "seed=12345 i=3")
		var r0 := Rng.new(0)
		kit.eq(r0.next_u64(), -5093384982049193912, "seed=0 i=1"))

	kit.test("next-int-range", func():
		var r := Rng.new(42)
		for _i in 500:
			var v := r.next_int(10)
			kit.ok(v >= 0 and v < 10, "next_int(10) 越界: " + str(v)))

	kit.test("next-int-degenerate", func():
		var r := Rng.new(7)
		kit.eq(r.next_int(1), 0, "next_int(1)")
		kit.eq(r.next_int(0), 0, "next_int(0)")
		kit.eq(r.next_int(-5), 0, "next_int(-5)"))

	kit.test("next-int-big", func():
		var r := Rng.new(9)
		var m := 1 << 40
		for _i in 50:
			var v := r.next_int(m)
			kit.ok(v >= 0 and v < m, "next_int(2^40) 越界: " + str(v)))

	kit.test("same-seed-same-stream", func():
		var a := Rng.new(20261003)
		var b := Rng.new(20261003)
		for _i in 20:
			kit.eq(a.next_u64(), b.next_u64(), "同种子流分叉"))

	kit.test("restore", func():
		var r := Rng.new(5)
		var snap := r.state # 存档：初始状态
		var want := []
		for i in 5:
			want.append(r.next_u64())
		for _i in 7:
			r.next_u64()
		r.restore(snap)
		for i in 5:
			kit.eq(r.next_u64(), want[i], "restore 后重放不一致 i=" + str(i)))
