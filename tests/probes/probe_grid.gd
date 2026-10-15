extends SceneTree

# R3 验证探针：grid 移植（三态/镜像/rev/下标/外环）。exit 0 = 全过。
var ok := true


func check(cond: bool, what: String) -> void:
	if not cond:
		ok = false
		print("  FAIL: ", what)


func _initialize() -> void:
	# 常量
	check(Grid.OPEN == 0 and Grid.COVER == 1 and Grid.SOLID == 2, "constants")
	# OPEN 填充
	var g := Grid.new(4, 3)
	check(g.w == 4 and g.h == 3 and g.stride == 6, "dims")
	check(g.rev == 0, "rev=0")
	var all_open := true
	for y in 3:
		for x in 4:
			if g.at(x, y) != Grid.OPEN or not g.passable(x, y) or g.get_h(x, y) != 0:
				all_open = false
	check(all_open, "open fill")
	# SOLID 填充
	var gs := Grid.new(4, 3, Grid.SOLID)
	var all_solid := true
	for y in 3:
		for x in 4:
			if gs.at(x, y) != Grid.SOLID or gs.passable(x, y):
				all_solid = false
	check(all_solid, "solid fill")
	# 下标公式（与 Lua 版同构平移 -1）
	var g5 := Grid.new(5, 4)
	check(g5.idx(0, 0) == 0 and g5.idx(4, 0) == 4 and g5.idx(0, 1) == 5 and g5.idx(4, 3) == 19, "idx")
	check(g5.pad_idx(0, 0) == g5.stride + 1 and g5.pad_idx(4, 3) == 4 * g5.stride + 5, "pad_idx")
	# 界外
	check(not g.inb(-1, 0) and not g.inb(4, 0) and not g.inb(0, 3), "inb")
	check(g.at(-1, 0) == Grid.SOLID and g.at(99, 99) == Grid.SOLID, "oob at")
	check(not g.passable(99, 99) and g.get_h(99, 99) == 0, "oob misc")
	# 三态通行
	var gt := Grid.new(4, 3)
	gt.set_cell(1, 1, Grid.COVER)
	gt.set_cell(2, 1, Grid.SOLID)
	check(gt.passable(0, 0) and not gt.passable(1, 1) and not gt.passable(2, 1), "three states")
	# set：rev + 镜像
	var gm := Grid.new(4, 3)
	var p := gm.pad_idx(1, 1)
	check(gm.pmap[p] == 1, "mirror open")
	gm.set_cell(1, 1, Grid.SOLID)
	check(gm.rev == 1 and gm.pmap[p] == 0, "set bump + mirror 0")
	gm.set_cell(1, 1, Grid.SOLID)
	check(gm.rev == 1, "same value no bump")
	gm.set_cell(1, 1, Grid.OPEN)
	check(gm.rev == 2 and gm.pmap[p] == 1, "set back")
	# padded 外环恒阻挡（mirror 修复的回归点：Lua 版曾 off-by-one）
	var gr := Grid.new(4, 3)
	check(gr.pmap[gr.pad_idx(-1, 0)] == null, "left ring")
	check(gr.pmap[gr.pad_idx(4, 0)] == null, "right ring")
	check(gr.pmap[gr.pad_idx(0, -1)] == null, "top ring")
	check(gr.pmap[gr.pad_idx(0, 3)] == null, "bottom ring")
	# set_h / init_h
	var gh := Grid.new(4, 3)
	gh.set_h(1, 1, 2)
	check(gh.get_h(1, 1) == 2 and gh.rev == 1 and gh.hp[gh.pad_idx(1, 1)] == 2, "set_h")
	gh.set_h(1, 1, 2)
	check(gh.rev == 1, "set_h same no bump")
	var gi := Grid.new(4, 3)
	gi.init_h(1, 1, 3)
	check(gi.get_h(1, 1) == 3 and gi.rev == 0 and gi.hp[gi.pad_idx(1, 1)] == 3, "init_h no bump")
	print("[R3-PROBE] ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
