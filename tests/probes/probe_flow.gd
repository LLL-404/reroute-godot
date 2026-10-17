extends ProbeKit

# R4 验证探针：flowfield 移植（距离/邻接/平手/预算不变性/边界/回退/单向崖）。
# 2026-10-17 六边形重写：方向序 0E 1NE 2NW 3W 4SW 5SE，六向等权步长 10。
# 贴角用例改写为「门格正邻」语义（六边无对角概念）。
# 判定：exit 0 + stdout 含 `[FLOW] PASS`。


func run_full(f: FlowField) -> void:
	while not f.done():
		f.step(1 << 30)


func _initialize() -> void:
	# 直线/斜线距离
	var g := Grid.new(8, 8)
	var f := FlowField.new(g)
	f.begin([Vector2i(0, 0)])
	run_full(f)
	check(f.dist_at(1, 0) == 10, "straight 1")
	check(f.dist_at(3, 0) == 30, "straight 3")
	check(f.dist_at(1, 1) == 20, "diag (1,1) = 六边距 2 步")
	check(f.dist_at(2, 2) == 30, "diag (2,2) = 六边距 3 步")
	check(f.dist_at(3, 1) == 40, "mixed (3,1) = 六边距 4 步")
	check(f.dist_at(7, 7) == 110, "corner (7,7) = 六边距 11 步")
	check(f.dist_at(0, 0) == 0, "goal")

	# 贴角禁穿
	var g2 := Grid.new(4, 3)
	for x in 4:
		g2.set_cell(x, 1, Grid.SOLID)
	g2.set_cell(1, 1, Grid.OPEN)
	var f2 := FlowField.new(g2)
	f2.begin([Vector2i(1, 0)])
	run_full(f2)
	check(f2.dist_at(1, 2) == 20, "through door")
	check(f2.dist_at(0, 2) == 30, "door west detour (0,2)")
	check(f2.dist_at(2, 2) == 20, "door SE neighbor one step (2,2)")
	check(f2.dist_at(2, 0) == 10, "north straight")
	check(f2.dir_at(1, 2) == 1, "dir to door = 1 (NE)")

	# 平手取序号最小：挡 (1,1) 逼出绕行；(3,2) 处 NW(2)/W(3) 双 30 平手 → NW 先。
	var g3 := Grid.new(5, 5)
	g3.set_cell(1, 1, Grid.SOLID)
	var f3 := FlowField.new(g3)
	f3.begin([Vector2i(0, 0)])
	run_full(f3)
	check(f3.dist_at(2, 1) == 30, "detour east (2,1)")
	check(f3.dist_at(1, 2) == 20, "west shortcut (1,2)")
	check(f3.dist_at(2, 2) == 30, "detour (2,2)")
	check(f3.dist_at(3, 2) == 40, "detour (3,2)")
	check(f3.dir_at(3, 2) == 2, "tie -> lowest index (NW=2)")

	# dir_at 边界
	check(f.dir_at(0, 0) == -1, "dir at goal")
	var g4 := Grid.new(4, 4)
	g4.set_cell(2, 2, Grid.SOLID)
	g4.set_cell(2, 3, Grid.SOLID)
	g4.set_cell(3, 2, Grid.SOLID)
	var f4 := FlowField.new(g4)
	f4.begin([Vector2i(0, 0)])
	run_full(f4)
	check(f4.dir_at(2, 2) == -1, "dir at impassable")
	check(f4.dist_at(3, 3) == -1, "enclosed unreachable")
	check(f4.dir_at(3, 3) == -1, "dir at unreachable")

	# 预算切分不变性
	var fb := FlowField.new(g2)
	fb.begin([Vector2i(1, 0)])
	check(not fb.done(), "not done after begin")
	var guard := 0
	while not fb.done():
		fb.step(1)
		guard += 1
		check(guard < 10000, "budget loop guard")
	var same := fb.dist.size() == f2.dist.size()
	for i in f2.dist.size():
		if fb.dist[i] != f2.dist[i]:
			same = false
	check(same, "budget-split dist identical")
	var dir_same := true
	for y in 3:
		for x in 4:
			if fb.dir_at(x, y) != f2.dir_at(x, y):
				dir_same = false
	check(dir_same, "budget-split dir identical")

	# begin 边界
	var g5 := Grid.new(4, 4)
	var f5 := FlowField.new(g5)
	f5.begin([Vector2i(-1, 0), Vector2i(0, 99)])
	check(f5.done(), "all-OOB goals = empty done")
	check(f5.dist_at(0, 0) == -1, "empty field unreachable")
	f5.begin([Vector2i(0, 0), Vector2i(0, 0)])
	check(f5.pending == 1, "duplicate goals dedup (pending=1)")
	run_full(f5)
	check(f5.dist_at(0, 0) == 0, "goal dist 0")
	check(f5.dist_at(3, 3) == 50, "uniform (3,3) = 5x10 六边距")

	# 目标格可不可通行（核心占地口径）
	var g6 := Grid.new(4, 4)
	g6.set_cell(2, 2, Grid.SOLID)
	var f6 := FlowField.new(g6)
	f6.begin([Vector2i(2, 2)])
	run_full(f6)
	check(f6.dist_at(2, 2) == 0, "impassable goal dist 0")
	check(f6.dist_at(2, 1) == 10, "goal neighbor expandable")

	# 封死回退（(2,2) 六邻全封：E(3,2) W(1,2) NE(2,1) NW(1,1) SW(1,3) SE(2,3)）
	var g7 := Grid.new(5, 5)
	g7.set_cell(1, 2, Grid.SOLID)
	g7.set_cell(3, 2, Grid.SOLID)
	g7.set_cell(2, 1, Grid.SOLID)
	g7.set_cell(2, 3, Grid.SOLID)
	g7.set_cell(1, 1, Grid.SOLID)
	g7.set_cell(1, 3, Grid.SOLID)
	var f7 := FlowField.new(g7)
	f7.begin([Vector2i(0, 0)])
	run_full(f7)
	check(f7.dist_at(2, 2) == -1, "enclosed cell unreachable")
	check(f7.fallback_near(2, 2) == g7.idx(3, 1), "fallback to (3,1)")
	check(f7.fallback_near(1, 0) == g7.idx(1, 0), "r=0 self")
	var g8 := Grid.new(9, 9)
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			if maxi(absi(dx), absi(dy)) >= 1:
				g8.set_cell(4 + dx, 4 + dy, Grid.SOLID)
	var f8 := FlowField.new(g8)
	f8.begin([Vector2i(0, 0)])
	run_full(f8)
	check(f8.dist_at(4, 4) == -1, "3-layer ring enclosed")
	check(f8.fallback_near(4, 4) == -1, "no fallback within r<=3")

	# 单向崖：阶梯 + 断层
	var stair := Grid.new(5, 1)
	stair.init_h(0, 0, 3)
	stair.init_h(1, 0, 2)
	stair.init_h(2, 0, 1)
	stair.init_h(3, 0, 0)
	stair.init_h(4, 0, 0)
	var fs := FlowField.new(stair)
	fs.begin([Vector2i(0, 0)])
	run_full(fs)
	check(fs.dist_at(1, 0) == 10, "stair down step")
	check(fs.dist_at(4, 0) == 40, "stair full")
	var fsr := FlowField.new(stair)
	fsr.begin([Vector2i(4, 0)])
	run_full(fsr)
	check(fsr.dist_at(0, 0) == 40, "stair reverse up")
	var cliff := Grid.new(3, 1)
	cliff.init_h(0, 0, 0)
	cliff.init_h(1, 0, 2)
	cliff.init_h(2, 0, 0)
	var fw := FlowField.new(cliff)
	fw.begin([Vector2i(0, 0)])
	run_full(fw)
	check(fw.dist_at(1, 0) == 10, "cliff top drop-in")
	check(fw.dist_at(2, 0) == -1, "climb 2 banned")
	var fe := FlowField.new(cliff)
	fe.begin([Vector2i(2, 0)])
	run_full(fe)
	check(fe.dist_at(1, 0) == 10, "cliff top drop-in east")
	check(fe.dist_at(0, 0) == -1, "east to west needs climb")

	# 英雄场无视高度
	var fh := FlowField.new(cliff, true)
	fh.begin([Vector2i(2, 0)])
	run_full(fh)
	check(fh.dist_at(0, 0) == 20, "hero ignores height")

	finish("FLOW")
