extends SceneTree

# 投稿视频选点辅助（非闸）：打印种子地图 ASCII（通行/岩石/矿/核心/出怪口）+ 敌1路径。
# 跑法：PROMO_RUN=0 godot --headless --path . -s res://tests/probes/probe_promo_map.gd


func _initialize() -> void:
	var run := int(OS.get_environment("PROMO_RUN"))
	var seed := 20261003 + run
	var sc := Scenario.new(seed)
	var w := World.new(sc, seed)
	for _i in 5:
		w.tick() # 让流场摊开（摊销补场）

	var core := sc.core
	var spawns: Array = sc.spawns
	print("[MAP] run=", run, " seed=", seed, " core=", core, " spawns=", spawns, " chokes=", sc.chokes, " ridge_y=", sc.ridge_y, " template=", sc.template_id)

	# 敌1 路径（沿 dist 递减）
	var path_cells: Dictionary = {}
	var cur := Vector2i(spawns[0].x, spawns[0].y)
	for _i in 400:
		path_cells[cur] = true
		if cur.x == core.x and cur.y == core.y:
			break
		var best := -1
		var best_d := 1 << 30
		for k in 6:
			var nx: int = Grid.nx(cur.x, cur.y, k)
			var ny: int = Grid.ny(cur.x, cur.y, k)
			if not w.grid.passable(nx, ny):
				continue
			var d: int = w.field.dist_at(nx, ny)
			if d >= 0 and d < best_d:
				best_d = d
				best = k
		if best < 0:
			break
		cur = Vector2i(Grid.nx(cur.x, cur.y, best), Grid.ny(cur.x, cur.y, best))
	print("[MAP] path1 len=", w.field.dist_at(spawns[0].x, spawns[0].y), " traced=", path_cells.size())

	# 敌2 路径
	var path2: Dictionary = {}
	cur = Vector2i(spawns[1].x, spawns[1].y)
	for _i in 400:
		path2[cur] = true
		if cur.x == core.x and cur.y == core.y:
			break
		var best2 := -1
		var best_d2 := 1 << 30
		for k in 6:
			var nx: int = Grid.nx(cur.x, cur.y, k)
			var ny: int = Grid.ny(cur.x, cur.y, k)
			if not w.grid.passable(nx, ny):
				continue
			var d: int = w.field.dist_at(nx, ny)
			if d >= 0 and d < best_d2:
				best_d2 = d
				best2 = k
		if best2 < 0:
			break
		cur = Vector2i(Grid.nx(cur.x, cur.y, best2), Grid.ny(cur.x, cur.y, best2))

	var ore := {}
	for o in sc.ore_cells:
		ore[o.x * 1000 + o.y] = true

	var lines: PackedStringArray = []
	for y in sc.h:
		var row := ""
		for x in sc.w:
			var ch := "."
			if not w.grid.passable(x, y):
				ch = "#"
			if ore.has(x * 1000 + y):
				ch = "o"
			if path_cells.has(Vector2i(x, y)):
				ch = "*"
			if path2.has(Vector2i(x, y)):
				ch = "+"
			if x == core.x and y == core.y:
				ch = "C"
			for s in spawns:
				if s.x == x and s.y == y:
					ch = "S"
			row += ch
		lines.append(row)
	print("[MAP] rows y=0..%d (top=0):" % (sc.h - 1))
	for i in lines.size():
		print("%02d %s" % [i, lines[i]])
	quit(0)
