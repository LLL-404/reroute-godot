extends ProbeKit

# R5 验证探针：scenario 程序化布局（默认种子锚点 / 高度模板 / 建图结构 / 生成校验读取面 /
# 裸图流场路径合同 / 指纹守门 / 波次表 / 自由世界全扫 / 出怪点解析）。
# 判定：exit 0 + stdout 含 `[SCENARIO] PASS`。


func _initialize() -> void:
	var sc := Scenario.new()

	# --- 锚点（默认种子 20261003 全量钉死）---
	check(Scenario.DEFAULT_SEED == 20261003 and sc.seed == Scenario.DEFAULT_SEED, "default seed")
	check(sc.template_id == 0, "default template 0 (frozen ridge)")
	check(sc.w == 64 and sc.h == 64, "dims 64x64")
	check(sc.core == Vector2i(33, 6), "core")
	check(sc.hero_spawn == Vector2i(33, 8), "hero_spawn")
	check(sc.spawns.size() == 3, "spawns count")
	check(sc.spawns.size() >= 3 and sc.spawns[0] == Vector2i(21, 56) and sc.spawns[1] == Vector2i(45, 56) and sc.spawns[2] == Vector2i(6, 57), "spawns anchors")
	check(sc.ridge_y == 42, "ridge_y")
	check(sc.chokes.size() == 2 and sc.chokes[0] == Vector2i(22, 42) and sc.chokes[1] == Vector2i(46, 42), "chokes")
	check(sc.basin_plug == Vector2i(8, 53), "basin_plug")
	check(sc.basin_rect == Rect2i(3, 53, 7, 8), "basin_rect")
	check(sc.mesa == Rect2i(16, 48, 2, 2), "mesa")
	check(sc.sparse_phase == 2, "sparse_phase")
	check(sc.resample_salt == 0, "resample_salt")
	check(sc.end_tick == 6400 and sc.hard_cap_tick == 8800 and sc.trickle_every == 300, "timing")
	check(sc.wave_scale_pct == 100, "wave_scale_pct")
	check(Scenario.PATH_REF == 548 and Scenario.PATH_LO == 466 and Scenario.PATH_HI == 630, "path band consts")

	# 越界护栏：锚点若破例（数组变短），后续读取退化为显式坏值而不是硬崩。
	var spawn0: Vector2i = sc.spawns[0] if sc.spawns.size() > 0 else Vector2i(-1, -1)
	var spawn1: Vector2i = sc.spawns[1] if sc.spawns.size() > 1 else Vector2i(-1, -1)
	var spawn2: Vector2i = sc.spawns[2] if sc.spawns.size() > 2 else Vector2i(-1, -1)
	var choke0: Vector2i = sc.chokes[0] if sc.chokes.size() > 0 else Vector2i(-1, -1)
	var choke1: Vector2i = sc.chokes[1] if sc.chokes.size() > 1 else Vector2i(-1, -1)

	# --- 波次表（不随布局变奏）---
	var waves_ok := true
	var total := 0
	var first := 1 << 30
	var last := 0
	var max_batch := 0
	var finale := 0
	for wv in sc.waves:
		if wv.size() < 4 or wv[1] < 1 or wv[1] > 2:
			waves_ok = false
			continue
		var t: int = wv[0]
		var cnt: int = wv[3]
		total += cnt
		if t < first:
			first = t
		if t > last:
			last = t
		if cnt > max_batch:
			max_batch = cnt
		if t >= 4600:
			finale += cnt
	check(waves_ok, "waves shape")
	check(sc.waves.size() == 25, "waves count")
	check(total == 200 and first == 60 and last == 4860 and max_batch == 14 and finale == 82, "waves contract")

	# --- height_at 锚点 ---
	var cx: int = sc.core.x
	check(sc.height_at(cx, 6) == 3, "h core peak")
	check(sc.height_at(cx, 12) == 2, "h core step mid")
	check(sc.height_at(cx + 2, 12) == 2, "h core step edge")
	check(sc.height_at(cx + 3, 12) == 1, "h north bank")
	check(sc.height_at(cx, 20) == 1, "h bank mid")
	check(sc.height_at(choke0.x, sc.ridge_y) == 1, "h choke west mouth")
	check(sc.height_at(choke1.x, sc.ridge_y) == 1, "h choke east mouth")
	# 咽喉下沿 h0：height_at 只在 y == ridge_y 的咽喉列给 h1（任务书 ridge_y+1 == 1 与实现不符，见报告）。
	check(sc.height_at(choke1.x, sc.ridge_y + 1) == 0, "h choke east south h0")
	check(sc.height_at(cx, sc.ridge_y) == 0, "h ridge at core x")
	check(sc.height_at(cx, sc.ridge_y + 1) == 0, "h south of ridge")
	check(sc.height_at(cx, 56) == 0, "h south lowland")
	check(sc.height_at(sc.mesa.position.x, sc.mesa.position.y) == 1 \
		and sc.height_at(sc.mesa.end.x - 1, sc.mesa.position.y) == 1 \
		and sc.height_at(sc.mesa.position.x, sc.mesa.end.y - 1) == 1 \
		and sc.height_at(sc.mesa.end.x - 1, sc.mesa.end.y - 1) == 1, "h mesa corners")
	check(sc.height_at(0, 0) == 1, "h north bank corner")

	# --- build_grid 结构 ---
	var g := sc.build_grid()
	var border_ok := true
	for x in sc.w:
		if g.at(x, 0) != Grid.SOLID or g.at(x, sc.h - 1) != Grid.SOLID:
			border_ok = false
	for y in sc.h:
		if g.at(0, y) != Grid.SOLID or g.at(sc.w - 1, y) != Grid.SOLID:
			border_ok = false
	check(border_ok, "border solid")
	check(g.at(sc.core.x, sc.core.y) == Grid.SOLID, "core solid")
	check(g.at(sc.hero_spawn.x, sc.hero_spawn.y) == Grid.OPEN, "hero spawn open")
	check(g.at(spawn0.x, spawn0.y) == Grid.OPEN, "spawn1 open")
	check(g.at(spawn1.x, spawn1.y) == Grid.OPEN, "spawn2 open")
	check(g.at(spawn2.x, spawn2.y) == Grid.COVER, "spawn3 on ore cover")
	var choke_ok := true
	for c in [choke0, choke1]:
		var cell: Vector2i = c
		for dy in 3:
			for dx in range(-1, 2):
				if g.at(cell.x + dx, cell.y + dy) != Grid.OPEN:
					choke_ok = false
	check(choke_ok, "choke aisle open x3 rows")
	var mx: int = (choke0.x + choke1.x) / 2
	check(absi(mx - choke0.x) > 1 and absi(mx - choke1.x) > 1, "ridge mid-span x premise")
	check(g.at(mx, sc.ridge_y) == Grid.SOLID and g.at(mx, sc.ridge_y + 1) == Grid.SOLID and g.at(mx, sc.ridge_y + 2) == Grid.SOLID, "ridge mid-span solid")
	var b := sc.basin_rect
	var bx1: int = b.position.x + b.size.x - 1
	var by1: int = b.position.y + b.size.y - 1
	check(g.at(b.position.x, b.position.y) == Grid.SOLID and g.at(bx1, b.position.y) == Grid.SOLID \
		and g.at(b.position.x, by1) == Grid.SOLID and g.at(bx1, by1) == Grid.SOLID \
		and g.at(b.position.x + 1, b.position.y) == Grid.SOLID, "basin ring solid samples")
	check(g.at(sc.basin_plug.x, sc.basin_plug.y) == Grid.COVER, "plug cover")
	check(g.at(b.position.x + 1, b.position.y + 1) == Grid.OPEN, "basin interior open")
	var ore_ok := true
	for o in sc.ore_cells:
		var oc: Vector2i = o
		if g.at(oc.x, oc.y) != Grid.COVER:
			ore_ok = false
	check(ore_ok, "all ore cells cover")
	check(g.at(sc.sparse_phase, 17) == Grid.COVER, "sparse row cover")
	check(g.at(sc.sparse_phase + 1, 17) == Grid.OPEN, "sparse row neighbor open")
	check(g.get_h(sc.core.x, sc.core.y) == 3 and g.get_h(sc.core.x, 12) == 2 \
		and g.get_h(choke0.x, sc.ridge_y) == 1 and g.get_h(sc.mesa.position.x, sc.mesa.position.y) == 1, "heights landed")

	# --- 生成校验读取面（每次传新鲜网格）+ 负对照 ---
	var cg := sc.check_grid(sc.build_grid())
	check(cg == "", "check_grid legal: " + cg)
	var pg := sc.check_plug_open(sc.build_grid())
	check(pg == "", "check_plug_open legal: " + pg)
	var opened := sc.build_grid()
	sc.check_plug_open(opened)
	check(sc.check_grid(opened) != "", "check_grid rejects opened plug")

	# --- 裸图流场路径合同（核心 → 主口 ∈ 标定带；盆地口封闭不可达）---
	var ff := FlowField.new(sc.build_grid(), false)
	ff.begin([sc.core])
	while not ff.done():
		ff.step(1 << 20)
	var d0: int = ff.dist_at(spawn0.x, spawn0.y)
	var d1: int = ff.dist_at(spawn1.x, spawn1.y)
	var d2: int = ff.dist_at(spawn2.x, spawn2.y)
	check(ff.done() and ff.dist_at(sc.core.x, sc.core.y) == 0, "flowfield from core done")
	check(d0 >= Scenario.PATH_LO and d0 <= Scenario.PATH_HI, "path spawn1 in band d0=%d" % d0)
	check(d1 >= Scenario.PATH_LO and d1 <= Scenario.PATH_HI, "path spawn2 in band d1=%d" % d1)
	check(d0 == d1, "main spawn paths equal d0=%d d1=%d" % [d0, d1])
	check(d2 == -1, "spawn3 unreachable closed d2=%d" % d2)

	# --- 指纹守门（0x7dea2b02）+ 确定性 + 负对照 ---
	var canon := Canon.new()
	var fp: int = sc.fingerprint(canon)
	check(fp == 0x7dea2b02, "fingerprint baseline (got 0x%x)" % fp)
	check(fp == sc.fingerprint(canon), "fingerprint repeat call")
	check(fp == Scenario.new().fingerprint(Canon.new()), "fingerprint fresh instance")
	var mut := Scenario.new()
	mut.wave_scale_pct = 90
	check(fp != mut.fingerprint(canon), "fingerprint neg wave_scale")
	check(fp != Scenario.new(20261004).fingerprint(Canon.new()), "fingerprint neg seed")

	# --- 矿数据 ---
	check(sc.mid_ore.size() == 5 and sc.basin_ore.size() == 12, "ore counts")
	check(sc.ore_cells.size() == sc.basin_ore.size() + sc.mid_ore.size(), "ore_cells size")
	check(sc.ore_cells.size() == 17 and sc.basin_ore.size() == 12 and sc.mid_ore.size() == 5 \
		and sc.ore_cells[0] == sc.basin_ore[0] and sc.ore_cells[12] == sc.mid_ore[0], "ore_cells order basin->mid")
	check(sc.mid_ore.size() == 5 and sc.mid_ore[0] == Vector2i(31, 21) and sc.mid_ore[4] == Vector2i(35, 21), "mid ore span")
	check(sc.basin_ore.size() == 12 and sc.basin_ore[0] == Vector2i(5, 56) and sc.basin_ore[11] == Vector2i(7, 59), "basin ore span")
	check(sc.is_ore(33, 21) and sc.is_ore(5, 56) and sc.is_ore(7, 59), "is_ore true")
	check(not sc.is_ore(sc.basin_plug.x, sc.basin_plug.y) and not sc.is_ore(4, 54) and not sc.is_ore(0, 0), "is_ore false plug/interior/border")

	# --- 自由世界全扫（2026-10-19 世界生成 2.0：自由盐内收敛 + 各局校验合法 + 指纹互异）---
	var fps := {}
	var sweep_ok := true
	var salt_max := 0
	var mains3 := 0
	for i in 48:
		var s := 20261004 + i
		var sx := Scenario.new(s)
		if sx.resample_salt > salt_max:
			salt_max = sx.resample_salt
		if sx.resample_salt >= 48:
			sweep_ok = false # 落入 legacy 兜底 = 自由路径回归
		if sx.check_grid(sx.build_grid()) != "":
			sweep_ok = false
		if sx.check_plug_open(sx.build_grid()) != "":
			sweep_ok = false
		if sx.spawns.size() == 4:
			mains3 += 1
		fps[sx.fingerprint(canon)] = true
	check(sweep_ok, "自由世界全扫合法（盐峰 %d）" % salt_max)
	check(fps.size() >= 46, "布局指纹互异 %d/48 局" % fps.size())
	check(mains3 >= 3, "三主口样本 %d/48" % mains3)

	# --- 出怪点解析（wave_cell / basin_cell；三主口按表序轮转、双主口同历史口径）---
	var two := Scenario.new(20261004)
	check(two.wave_cell(0) == two.spawns[two.waves[0][1] - 1], "双主口 wave_cell 历史口径")
	check(two.basin_cell() == two.spawns[two.spawns.size() - 1], "basin_cell 恒末位")
	var three: Scenario = null
	for i in 48:
		var sj := Scenario.new(20261004 + i)
		if sj.spawns.size() == 4:
			three = sj
			break
	check(three != null, "样本含三主口局")
	if three != null:
		var seen := {}
		var only_mains := true
		for ei in three.waves.size():
			var wc: Vector2i = three.wave_cell(ei)
			var is_main := false
			for j in 3:
				if wc == three.spawns[j]:
					is_main = true
			if not is_main:
				only_mains = false
			seen[wc] = true
		check(only_mains, "三主口波次只落主口")
		check(seen.size() == 3, "三主口轮转覆盖 %d/3" % seen.size())

	finish("SCENARIO", 70, "d0=%d d1=%d d2=%d fp=0x%x salt=%d m3=%d" % [d0, d1, d2, fp, salt_max, mains3])
