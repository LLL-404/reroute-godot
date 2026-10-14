extends RefCounted

# grid 单测（移植自 reroute/tests/test_grid.lua）。
# 差异：Lua 版有一条 new-guard（断言 >0 尺寸），GDScript 无 pcall 捕获断言，
# 该用例不进套件（断言本身在构造处保留）。


func register(kit: TestKit) -> void:
	kit.module("grid")

	kit.test("constants", func():
		kit.eq(Grid.OPEN, 0, "OPEN")
		kit.eq(Grid.COVER, 1, "COVER")
		kit.eq(Grid.SOLID, 2, "SOLID"))

	kit.test("new-open-fill", func():
		var g := Grid.new(4, 3)
		kit.eq(g.w, 4, "w")
		kit.eq(g.h, 3, "h")
		kit.eq(g.stride, 6, "stride = w+2")
		kit.eq(g.rev, 0, "新图 rev=0")
		kit.eq(g.height_rev, 0, "新图 height_rev=0")
		for y in 3:
			for x in 4:
				kit.eq(g.at(x, y), Grid.OPEN, "初始格应 OPEN")
				kit.ok(g.passable(x, y), "初始格应可通行")
				kit.eq(g.get_h(x, y), 0, "初始高度 0"))

	kit.test("new-solid-fill", func():
		var g := Grid.new(4, 3, Grid.SOLID)
		for y in 3:
			for x in 4:
				kit.eq(g.at(x, y), Grid.SOLID, "SOLID 填充")
				kit.ok(not g.passable(x, y), "SOLID 不可通行"))

	kit.test("idx-formula", func():
		var g := Grid.new(5, 4)
		kit.eq(g.idx(0, 0), 0, "idx(0,0)")
		kit.eq(g.idx(4, 0), 4, "idx(4,0)")
		kit.eq(g.idx(0, 1), 5, "idx(0,1)")
		kit.eq(g.idx(4, 3), 19, "idx(4,3)")
		kit.eq(g.pad_idx(0, 0), g.stride + 1, "pad_idx(0,0)（规范布局）")
		kit.eq(g.pad_idx(4, 3), 4 * g.stride + 5, "pad_idx(4,3)"))

	kit.test("out-of-bounds", func():
		var g := Grid.new(4, 3)
		kit.ok(not g.inb(-1, 0), "inb(-1,0)")
		kit.ok(not g.inb(4, 0), "inb(4,0)")
		kit.ok(not g.inb(0, 3), "inb(0,3)")
		kit.eq(g.at(-1, 0), Grid.SOLID, "界外 at 恒 SOLID")
		kit.eq(g.at(99, 99), Grid.SOLID, "远界外 at 恒 SOLID")
		kit.ok(not g.passable(99, 99), "界外不可通行")
		kit.eq(g.get_h(99, 99), 0, "界外高度 0"))

	kit.test("passable-three-states", func():
		var g := Grid.new(4, 3)
		g.set_cell(1, 1, Grid.COVER)
		g.set_cell(2, 1, Grid.SOLID)
		kit.ok(g.passable(0, 0), "OPEN 可通行")
		kit.ok(not g.passable(1, 1), "COVER 不可通行")
		kit.ok(not g.passable(2, 1), "SOLID 不可通行"))

	kit.test("set-rev-and-mirror", func():
		var g := Grid.new(4, 3)
		var p := g.pad_idx(1, 1)
		kit.eq(g.pmap[p], 1, "OPEN 镜像 1")
		g.set_cell(1, 1, Grid.SOLID)
		kit.eq(g.rev, 1, "set 变更 bump rev")
		kit.eq(g.height_rev, 0, "格子状态不影响高度版本")
		kit.eq(g.pmap[p], 0, "SOLID 镜像 0")
		g.set_cell(1, 1, Grid.SOLID)
		kit.eq(g.rev, 1, "同值 set 不 bump rev")
		g.set_cell(1, 1, Grid.OPEN)
		kit.eq(g.rev, 2, "改回 OPEN 再 bump")
		kit.eq(g.pmap[p], 1, "镜像恢复 1"))

	kit.test("padded-ring-blocked", func():
		var g := Grid.new(4, 3)
		kit.ok(g.pmap[g.pad_idx(-1, 0)] != 1, "左外环应阻挡")
		kit.ok(g.pmap[g.pad_idx(4, 0)] != 1, "右外环应阻挡")
		kit.ok(g.pmap[g.pad_idx(0, -1)] != 1, "上外环应阻挡")
		kit.ok(g.pmap[g.pad_idx(0, 3)] != 1, "下外环应阻挡"))

	kit.test("set-h-rev", func():
		var g := Grid.new(4, 3)
		g.set_h(1, 1, 2)
		kit.eq(g.get_h(1, 1), 2, "set_h 写入")
		kit.eq(g.rev, 1, "set_h bump rev")
		kit.eq(g.height_rev, 1, "set_h bump height_rev")
		kit.eq(g.hp[g.pad_idx(1, 1)], 2, "hp 镜像同步")
		g.set_h(1, 1, 2)
		kit.eq(g.rev, 1, "同值 set_h 不 bump")
		kit.eq(g.height_rev, 1, "同值 set_h 不改变高度版本")
		g.set_h(1, 1, 5)
		kit.eq(g.rev, 2, "异值 set_h 再 bump")
		kit.eq(g.height_rev, 2, "异值 set_h 再 bump 高度版本"))

	kit.test("init-h-no-rev", func():
		var g := Grid.new(4, 3)
		g.init_h(1, 1, 3)
		kit.eq(g.get_h(1, 1), 3, "init_h 写入")
		kit.eq(g.rev, 0, "init_h 不 bump rev")
		kit.eq(g.height_rev, 0, "建图期不 bump height_rev")
		kit.eq(g.hp[g.pad_idx(1, 1)], 3, "hp 镜像同步"))
