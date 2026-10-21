class_name Threat
extends RefCounted

# 肉鸽模式「威胁升级」：每层开局对网格做一次不可逆改造，并启用一个新出怪口。
# 设计口径（见 docs/ROGUELIKE-SPEC.md §4）：出怪口逐层逼近核心
#   L1 两处咽喉主口（距核心 ~50 格，玩家现有防线有效）
#   L2 盆地插口强制打通（距核心 ~51 格，侧翼，逼分兵）
#   L3 岩脊爆破（距核心 ~36 格，直接穿破咽喉防线）
#   L4 中场裂口（距核心 ~15 格，纵深防线必须重建）
#   L5 核心侧翼裂口（距核心 ~6 格，只剩贴脸防守）
# 全部改造只经 Grid.set_cell / set_h（rev 递增 ⇒ 流场自动全量重建）。


## 执行第 layer 层的威胁升级。返回诊断字典（供 UI/日志/探针断言）：
##   { layer, gate: Vector2i（新增出怪口；-1 表示无）, breach: Array[Vector2i],
##     distance: int（新口到核心的六边距离）, note: String }
static func apply(world: World, layer: int) -> Dictionary:
	var sc: Scenario = world.sc
	var g: Grid = world.grid
	var info: Dictionary = {
		"layer": layer,
		"gate": Vector2i(-1, -1),
		"breach": [],
		"distance": -1,
		"note": "",
	}
	if layer <= 1:
		info["note"] = "两处咽喉主口"
		info["distance"] = Grid.hex_dist(sc.spawns[0].x, sc.spawns[0].y, sc.core.x, sc.core.y)
		return info

	if layer == 2:
		# 盆地插口强制打通：盆地口（spawns 末位）即刻启用。
		var plug: Vector2i = sc.basin_plug
		if g.at(plug.x, plug.y) != Grid.OPEN:
			g.set_cell(plug.x, plug.y, Grid.OPEN)
			info["breach"].append(plug)
		world.route_opened = true
		var gate: Vector2i = sc.spawns[sc.spawns.size() - 1]
		info["gate"] = gate
		info["distance"] = Grid.hex_dist(gate.x, gate.y, sc.core.x, sc.core.y)
		info["note"] = "盆地插口被打穿"
		return info

	# L3+：在屏障带炸开新口，并向核心打一条可走走廊
	var gate_row: int = _gate_row(sc, layer)
	var gate_x: int = _pick_gate_x(sc, g, layer, gate_row)
	var gate := Vector2i(gate_x, gate_row)
	g.set_cell(gate_x, gate_row, Grid.OPEN)
	info["breach"].append(gate)
	var corridor: Array = _carve(g, gate, sc.core)
	for c in corridor:
		info["breach"].append(c)
	# 不写 sc.spawns：末位必须恒为盆地口（sc.basin_cell 的约定）。新口由 RunState 自行登记。
	info["gate"] = gate
	info["distance"] = Grid.hex_dist(gate.x, gate.y, sc.core.x, sc.core.y)
	info["note"] = "屏障被炸开"
	return info


## 各层的爆破行：优先用布局自带的岩脊行；自由图按层线性上移。
static func _gate_row(sc: Scenario, layer: int) -> int:
	if sc.ridge_y >= 0:
		match layer:
			3:
				return sc.ridge_y
			4:
				return maxi(12, sc.ridge_y - 21)
			_:
				return maxi(9, sc.ridge_y - 30)
	return maxi(9, 42 - (layer - 3) * 12)


## 在该行挑一个离核心横向最近的实心格作为爆破点（确定性：从中心向外扫描）。
static func _pick_gate_x(sc: Scenario, g: Grid, layer: int, row: int) -> int:
	var cx: int = sc.core.x
	var best: int = -1
	var best_d: int = 1 << 30
	for x in range(2, g.w - 2):
		if g.at(x, row) != Grid.SOLID:
			continue
		var d: int = absi(x - cx)
		if d < best_d:
			best_d = d
			best = x
	if best >= 0:
		return best
	# 该行无实心格（自由图常见）：退回核心列偏移
	return clampi(cx + (layer * 5) % 13 - 6, 2, g.w - 3)


## 从 from 向 core 打一条单调走廊：先把列差补齐，再逐行上移；高度压平到可爬。
static func _carve(g: Grid, from: Vector2i, core: Vector2i) -> Array:
	var out: Array = []
	var x: int = from.x
	var y: int = from.y
	var guard: int = 0
	while guard < 160:
		guard += 1
		if x == core.x and y <= core.y + 2:
			break
		var nx: int = x
		var ny: int = y
		if absi(core.x - x) > 1:
			nx = x + (1 if core.x > x else -1)
		elif y > core.y + 2:
			ny = y - 1
		else:
			break
		# 高度压平：向下任意走，向上最多 1 级（把过高处削平而不是抬路）
		var h_cur: int = g.get_h(x, y)
		var h_next: int = g.get_h(nx, ny)
		if h_next - h_cur > 1:
			g.set_h(nx, ny, h_cur + 1)
		if g.at(nx, ny) != Grid.OPEN:
			g.set_cell(nx, ny, Grid.OPEN)
			out.append(Vector2i(nx, ny))
		else:
			out.append(Vector2i(nx, ny))
		x = nx
		y = ny
	return out
