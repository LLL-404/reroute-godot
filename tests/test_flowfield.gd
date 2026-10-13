extends RefCounted

# flowfield 单测（移植自 reroute/tests/test_flowfield.lua）。
# 方向序为 0 基：0E 1NE 2N 3NW 4W 5SW 6S 7SE（Lua 版 1 基同构 -1）。


func _run_full(f: FlowField) -> void:
	var guard := 0
	while not f.done():
		f.step(1 << 30)
		guard += 1
		if guard > 64:
			return


func register(kit: TestKit) -> void:
	kit.module("flowfield")

	kit.test("straight-diag-dist", func():
		var g := Grid.new(8, 8)
		var f := FlowField.new(g)
		f.begin([Vector2i(0, 0)])
		_run_full(f)
		kit.eq(f.dist_at(1, 0), 10, "直行一格")
		kit.eq(f.dist_at(3, 0), 30, "直行三格")
		kit.eq(f.dist_at(1, 1), 14, "斜行一格")
		kit.eq(f.dist_at(2, 2), 28, "斜行两格")
		kit.eq(f.dist_at(3, 1), 34, "混合 (3,1)")
		kit.eq(f.dist_at(7, 7), 98, "对角 (7,7)")
		kit.eq(f.dist_at(0, 0), 0, "目标格"))

	kit.test("corner-cut-ban", func():
		var g := Grid.new(4, 3)
		for x in 4:
			g.set_cell(x, 1, Grid.SOLID)
		g.set_cell(1, 1, Grid.OPEN)
		var f := FlowField.new(g)
		f.begin([Vector2i(1, 0)])
		_run_full(f)
		kit.eq(f.dist_at(1, 2), 20, "过门直行 10+10")
		kit.eq(f.dist_at(0, 2), 30, "(0,2) 斜穿被禁绕行")
		kit.eq(f.dist_at(2, 2), 30, "(2,2) 斜穿被禁绕行")
		kit.eq(f.dist_at(2, 0), 10, "北岸直行")
		kit.eq(f.dir_at(1, 2), 6, "(1,2) 下降方向 = 6（朝门）"))

	kit.test("dir-tie-lowest-index", func():
		var g := Grid.new(5, 5)
		g.set_cell(1, 1, Grid.SOLID)
		var f := FlowField.new(g)
		f.begin([Vector2i(0, 0)])
		_run_full(f)
		kit.eq(f.dist_at(2, 1), 30, "(2,1) 绕行距离")
		kit.eq(f.dist_at(1, 2), 30, "(1,2) 绕行距离")
		kit.eq(f.dist_at(2, 2), 40, "(2,2) 距离")
		kit.eq(f.dir_at(2, 2), 4, "平手取序号最小：W(4) 先于 S(6)"))

	kit.test("dir-at-edges", func():
		var g := Grid.new(4, 4)
		var f := FlowField.new(g)
		f.begin([Vector2i(0, 0)])
		_run_full(f)
		kit.eq(f.dir_at(0, 0), -1, "目标格 -1")
		var g2 := Grid.new(4, 4)
		g2.set_cell(2, 2, Grid.SOLID)
		g2.set_cell(2, 3, Grid.SOLID)
		g2.set_cell(3, 2, Grid.SOLID)
		var f2 := FlowField.new(g2)
		f2.begin([Vector2i(0, 0)])
		_run_full(f2)
		kit.eq(f2.dir_at(2, 2), -1, "不可通行格 -1")
		kit.eq(f2.dist_at(3, 3), -1, "围住格不可达")
		kit.eq(f2.dir_at(3, 3), -1, "不可达格 -1"))

	kit.test("budget-split-invariance", func():
		var g := Grid.new(4, 3)
		for x in 4:
			g.set_cell(x, 1, Grid.SOLID)
		g.set_cell(1, 1, Grid.OPEN)
		var fa := FlowField.new(g)
		fa.begin([Vector2i(1, 0)])
		_run_full(fa)
		var fb := FlowField.new(g)
		fb.begin([Vector2i(1, 0)])
		kit.ok(not fb.done(), "begin 后未完成")
		var guard := 0
		while not fb.done():
			fb.step(1)
			guard += 1
			if guard > 10000:
				break
		for i in fa.dist.size():
			kit.eq(fb.dist[i], fa.dist[i], "预算切分后 dist 不一致 i=" + str(i))
		for y in 3:
			for x in 4:
				kit.eq(fb.dir_at(x, y), fa.dir_at(x, y), "dir_at 不一致 (" + str(x) + "," + str(y) + ")"))

	kit.test("begin-edge-cases", func():
		var g := Grid.new(4, 4)
		var f := FlowField.new(g)
		f.begin([Vector2i(-1, 0), Vector2i(0, 99)])
		kit.ok(f.done(), "全界外目标 = 空场即完成")
		kit.eq(f.dist_at(0, 0), -1, "空场不可达")
		f.begin([Vector2i(0, 0), Vector2i(0, 0)])
		kit.eq(f.pending, 1, "重复目标去重（pending=1）")
		_run_full(f)
		kit.eq(f.dist_at(0, 0), 0, "目标距 0")
		kit.eq(f.dist_at(3, 3), 42, "均匀图 (3,3) = 3×14"))

	kit.test("goal-on-impassable", func():
		var g := Grid.new(4, 4)
		g.set_cell(2, 2, Grid.SOLID)
		var f := FlowField.new(g)
		f.begin([Vector2i(2, 2)])
		_run_full(f)
		kit.eq(f.dist_at(2, 2), 0, "不可通行目标格距 0")
		kit.eq(f.dist_at(2, 1), 10, "目标邻格可扩张"))

	kit.test("fallback-near", func():
		var g := Grid.new(5, 5)
		g.set_cell(1, 2, Grid.SOLID)
		g.set_cell(3, 2, Grid.SOLID)
		g.set_cell(2, 1, Grid.SOLID)
		g.set_cell(2, 3, Grid.SOLID)
		var f := FlowField.new(g)
		f.begin([Vector2i(0, 0)])
		_run_full(f)
		kit.eq(f.dist_at(2, 2), -1, "围住格不可达")
		kit.eq(f.fallback_near(2, 2), g.idx(1, 1), "回退到环上首个可达格 (1,1)")
		kit.eq(f.fallback_near(1, 1), g.idx(1, 1), "r=0 自身可达即返回自身"))

	kit.test("fallback-near-none", func():
		var g := Grid.new(9, 9)
		for dy in range(-3, 4):
			for dx in range(-3, 4):
				if maxi(absi(dx), absi(dy)) >= 1:
					g.set_cell(4 + dx, 4 + dy, Grid.SOLID)
		var f := FlowField.new(g)
		f.begin([Vector2i(0, 0)])
		_run_full(f)
		kit.eq(f.dist_at(4, 4), -1, "三层实心环围住")
		kit.eq(f.fallback_near(4, 4), -1, "r<=3 无可达格返回 -1"))

	kit.test("height-one-way-cliff", func():
		var stair := Grid.new(5, 1)
		stair.init_h(0, 0, 3)
		stair.init_h(1, 0, 2)
		stair.init_h(2, 0, 1)
		stair.init_h(3, 0, 0)
		stair.init_h(4, 0, 0)
		var f := FlowField.new(stair)
		f.begin([Vector2i(0, 0)])
		_run_full(f)
		kit.eq(f.dist_at(1, 0), 10, "台阶逐级下行可达")
		kit.eq(f.dist_at(4, 0), 40, "阶梯全程可达")
		var fr := FlowField.new(stair)
		fr.begin([Vector2i(4, 0)])
		_run_full(fr)
		kit.eq(fr.dist_at(0, 0), 40, "反向逐级上行可达（每级只爬 1）")
		var cliff := Grid.new(3, 1)
		cliff.init_h(0, 0, 0)
		cliff.init_h(1, 0, 2)
		cliff.init_h(2, 0, 0)
		var fw := FlowField.new(cliff)
		fw.begin([Vector2i(0, 0)])
		_run_full(fw)
		kit.eq(fw.dist_at(1, 0), 10, "高台跳下进目标可达")
		kit.eq(fw.dist_at(2, 0), -1, "低地爬 2 崖不可达")
		var fe := FlowField.new(cliff)
		fe.begin([Vector2i(2, 0)])
		_run_full(fe)
		kit.eq(fe.dist_at(1, 0), 10, "高台跳下进目标可达（东）")
		kit.eq(fe.dist_at(0, 0), -1, "东低地到西低地要爬崖，不可达"))

	kit.test("ignore-h-hero-field", func():
		var g := Grid.new(3, 1)
		g.init_h(0, 0, 0)
		g.init_h(1, 0, 2)
		g.init_h(2, 0, 0)
		var f := FlowField.new(g, true)
		f.begin([Vector2i(2, 0)])
		_run_full(f)
		kit.eq(f.dist_at(0, 0), 20, "英雄场无视高度：翻崖可达"))
