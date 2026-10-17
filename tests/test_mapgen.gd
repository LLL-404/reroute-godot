extends RefCounted

# mapgen 单测（2026-10-16 世界生成 / 2026-10-17 G2 模板池）：参数域契约、64 种子全扫、
# 模板覆盖、确定性（缓存路径同值）、check_grid / check_plug_open 负对照（结构校验必须真拒坏图）。


func register(kit: TestKit) -> void:
	kit.module("mapgen")

	kit.test("64-seed-sweep", func():
		var sigs := {}
		var tpl_seen := {}
		for i in 64:
			var s := 20261004 + i # 默认种子走冻结窄域（锚点由 probe_scenario 钉死），此处扫变幅域
			var sc := Scenario.new(s)
			tpl_seen[sc.template_id] = true
			kit.ok(sc.resample_salt <= 8, "种子 %d 重采样 %d 次（参数窗收窄？tpl=%d）" % [s, sc.resample_salt, sc.template_id])
			kit.ok(sc.core.x >= 28 and sc.core.x <= 38, "core_x 越域 s=%d" % s)
			kit.ok(sc.ridge_y >= 39 and sc.ridge_y <= 43, "ridge_y 越域 s=%d" % s)
			var cw: Vector2i = sc.chokes[0]
			var ce: Vector2i = sc.chokes[1]
			kit.ok(cw.x >= 15 and cw.x <= 26 and ce.x >= 38 and ce.x <= 51, "咽喉位越域 s=%d" % s)
			kit.ok(ce.x - cw.x >= 15, "咽喉间距越域 s=%d" % s)
			kit.ok(cw.y >= sc.ridge_y - 5 and cw.y <= sc.ridge_y + 5, "西咽喉行越域 s=%d" % s)
			kit.ok(ce.y >= sc.ridge_y - 5 and ce.y <= sc.ridge_y + 5, "东咽喉行越域 s=%d" % s)
			var b: Rect2i = sc.basin_rect
			kit.ok(b.position.x >= 1 and b.position.x <= 5 and b.position.y >= 50 and b.position.y <= 52, "盆地角越域 s=%d" % s)
			kit.ok(b.size.x >= 6 and b.size.x <= 9 and b.size.y >= 7 and b.size.y <= 9, "盆地尺寸越域 s=%d" % s)
			var plug_dx: int = sc.basin_plug.x - b.position.x
			kit.ok(plug_dx >= 2 and plug_dx <= b.size.x - 2, "插口列越域 s=%d" % s)
			kit.eq(sc.basin_plug.y, b.position.y, "插口在上缘")
			kit.eq(sc.mid_ore.size(), 5, "中场矿数")
			kit.eq(sc.basin_ore.size(), 12, "盆地矿数")
			kit.ok(sc.sparse_phase >= 2 and sc.sparse_phase <= 7, "表土相位越域 s=%d" % s)
			for my in range(sc.mesa.position.y, sc.mesa.position.y + 2):
				for mx in range(sc.mesa.position.x, sc.mesa.position.x + 2):
					kit.ok(mx >= 7 and mx <= 56 and my >= sc.ridge_y + 5 and my <= 49, "微丘域越域 s=%d" % s)
					kit.ok(absi(mx - cw.x) > 1 and absi(mx - ce.x) > 1, "微丘压咽喉走廊 s=%d" % s)
			sigs["T%d|%s|%d|%s|%s|%s|%d" % [sc.template_id, str(sc.core), sc.ridge_y, str(cw), str(ce), str(sc.mesa), sc.sparse_phase]] = true
		kit.ok(tpl_seen.size() >= 5, "模板覆盖不足：仅 %d/5 种 / 64 种子" % tpl_seen.size())
		kit.ok(sigs.size() >= 40, "布局多样性不足：仅 %d 种签名 / 64 种子" % sigs.size()))

	kit.test("determinism-fresh-vs-cache", func():
		var seed := 20261231 # 第一次走生成+校验，第二次走进程缓存
		var a := Scenario.new(seed)
		var fa := a.fingerprint(Canon.new())
		var ga := a.build_grid()
		var ha := 0
		for i in a.w * a.h:
			ha = (ha * 31 + ga.cells[i] * 7 + ga.hgt[i]) % 1000000007
		var b := Scenario.new(seed)
		kit.eq(b.fingerprint(Canon.new()), fa, "缓存路径指纹与新鲜路径不一致")
		kit.eq(b.core, a.core, "缓存路径 core 不一致")
		kit.eq(b.chokes[0], a.chokes[0], "缓存路径 chokes 不一致")
		kit.eq(b.resample_salt, a.resample_salt, "缓存路径盐不一致")
		kit.seq(b.mid_ore, a.mid_ore, "缓存路径矿表不一致")
		var gb := b.build_grid()
		var hb := 0
		for i in b.w * b.h:
			hb = (hb * 31 + gb.cells[i] * 7 + gb.hgt[i]) % 1000000007
		kit.eq(hb, ha, "缓存路径网格内容不一致"))

	kit.test("check-grid-negative-controls", func():
		var sc := Scenario.new()
		kit.eq(sc.check_grid(sc.build_grid()), "", "默认图基线不绿")
		kit.eq(sc.check_plug_open(sc.build_grid()), "", "默认图插口开门不可达")
		# 1) 封西咽喉口 → 脊带形态校验必须拒
		var g1 := sc.build_grid()
		g1.set_cell(sc.chokes[0].x, sc.ridge_y, Grid.SOLID)
		kit.ok(sc.check_grid(g1) != "", "封咽喉未被拒")
		# 2) 插口挪位（原插口填实、邻格改覆盖）→ 环位校验必须拒
		var g2 := sc.build_grid()
		g2.set_cell(sc.basin_plug.x, sc.basin_plug.y, Grid.SOLID)
		g2.set_cell(sc.basin_plug.x + 1, sc.basin_plug.y, Grid.COVER)
		kit.ok(sc.check_grid(g2) != "", "插口挪位未被拒")
		# 3) 盆地破环（环上开洞）→ 密闭校验必须拒
		var g3 := sc.build_grid()
		g3.set_cell(sc.basin_rect.position.x, sc.basin_rect.position.y + 3, Grid.OPEN)
		kit.ok(sc.check_grid(g3) != "", "盆地破环未被拒")
		# 4) 咽喉口降高 → 高度校验必须拒
		var g4 := sc.build_grid()
		g4.init_h(sc.chokes[1].x, sc.ridge_y, 0)
		kit.ok(sc.check_grid(g4) != "", "咽喉降高未被拒")
		# 5) 矿格被填实（数据/地形失配）→ 矿校验必须拒
		var g5 := sc.build_grid()
		g5.set_cell(sc.mid_ore[0].x, sc.mid_ore[0].y, Grid.SOLID)
		kit.ok(sc.check_grid(g5) != "", "矿格失配未被拒")
		# 6) 矿数据压脊 → 矿校验必须拒
		var sc2 := Scenario.new()
		sc2.ore_cells.append(Vector2i(sc2.core.x, sc2.ridge_y))
		kit.ok(sc2.check_grid(sc2.build_grid()) != "", "矿压脊未被拒")
		# 7) 盆地内腔封死（即使插口与矿全开也不可达）→ plug_open 必须拒
		var g7 := sc.build_grid()
		var b: Rect2i = sc.basin_rect
		for x in range(b.position.x + 1, b.position.x + b.size.x - 1):
			g7.set_cell(x, b.position.y + 1, Grid.SOLID)
			g7.set_cell(x, b.position.y + 2, Grid.SOLID)
		kit.ok(sc.check_plug_open(g7) != "", "死盆地未被拒"))
