extends RefCounted

# mapgen 单测（2026-10-16 世界生成 / 2026-10-19 世界生成 2.0 自由路径）：结构不变量 64 种子全扫、
# 布局多样性、确定性（缓存路径同值）、自由路径 + 旧模板 check_grid / check_plug_open 负对照
# （结构校验必须真拒坏图）。


func register(kit: TestKit) -> void:
	kit.module("mapgen")

	kit.test("64-seed-sweep", func():
		var sigs := {}
		var salt_max := 0
		var n3 := 0
		for i in 64:
			var s := 20261004 + i # 默认种子走冻结窄域（锚点由 probe_scenario 钉死），此处扫自由域
			var sc := Scenario.new(s)
			# 收敛纪律：自由盐 0..47 内必收敛（≥48 即落入 legacy 兜底 = 参数域回归）
			kit.ok(sc.resample_salt < 48, "种子 %d 落入 legacy 兜底 salt=%d" % [s, sc.resample_salt])
			if sc.resample_salt > salt_max:
				salt_max = sc.resample_salt
			# 核心位：自由但留边（CORE_MARGIN=6）
			kit.ok(sc.core.x >= 6 and sc.core.x <= 57 and sc.core.y >= 6 and sc.core.y <= 57, "core 越域 s=%d" % s)
			# 出怪口：2..3 主口 + 盆地口（末位）
			kit.ok(sc.spawns.size() >= 3 and sc.spawns.size() <= 4, "出怪口数越域 s=%d" % s)
			if sc.spawns.size() == 4:
				n3 += 1
			# 主口贴周缘带（x/y 任一距边 ≤14）
			for j in sc.spawns.size() - 1:
				var sp: Vector2i = sc.spawns[j]
				kit.ok(sp.x <= 14 or sp.x >= 49 or sp.y <= 14 or sp.y >= 49, "主口离周缘 s=%d #%d %s" % [s, j, str(sp)])
			# 盆地：整矩形场内 + 尺寸域 + 插口棱中（水平边看 x、垂直边看 y，两端各避 2 格）
			var b: Rect2i = sc.basin_rect
			kit.ok(b.position.x >= 2 and b.position.x + b.size.x <= 62 \
				and b.position.y >= 2 and b.position.y + b.size.y <= 62, "盆地越域 s=%d" % s)
			kit.ok(b.size.x >= 6 and b.size.x <= 9 and b.size.y >= 7 and b.size.y <= 9, "盆地尺寸越域 s=%d" % s)
			var pm_x: bool = sc.basin_plug.x >= b.position.x + 2 and sc.basin_plug.x <= b.position.x + b.size.x - 3
			var pm_y: bool = sc.basin_plug.y >= b.position.y + 2 and sc.basin_plug.y <= b.position.y + b.size.y - 3
			kit.ok(pm_x != pm_y, "插口非棱中 s=%d %s" % [s, str(sc.basin_plug)])
			# 矿数契约（中场 5 + 盆地 12；总表盆地在前中场在后与默认图同口径）
			kit.eq(sc.mid_ore.size(), 5, "中场矿数 s=%d" % s)
			kit.eq(sc.basin_ore.size(), 12, "盆地矿数 s=%d" % s)
			kit.eq(sc.ore_cells.size(), 17, "矿总表 s=%d" % s)
			# 地貌带上界复核（生成器自检带 [60,220]/[20,160]‰ → 计数留宽验）
			kit.ok(sc._rock_arr.size() >= 150 and sc._rock_arr.size() <= 900, "岩群计数越界 s=%d n=%d" % [s, sc._rock_arr.size()])
			kit.ok(sc._hill_arr.size() >= 50 and sc._hill_arr.size() <= 640, "微丘计数越界 s=%d n=%d" % [s, sc._hill_arr.size()])
			# 布局签名多样性（核心 + 主口数 + 盆地 + 插口）
			sigs["%s|%d|%s|%s" % [str(sc.core), sc.spawns.size(), str(b), str(sc.basin_plug)]] = true
		kit.ok(salt_max < 48, "盐峰 %d 越自由窗" % salt_max)
		kit.ok(n3 >= 6, "三主口样本不足：%d/64" % n3)
		kit.ok(sigs.size() >= 60, "布局多样性不足：仅 %d 种签名 / 64 种子" % sigs.size()))

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
		kit.seq(b.spawns, a.spawns, "缓存路径出怪口不一致")
		kit.eq(b.basin_plug, a.basin_plug, "缓存路径插口不一致")
		kit.eq(b.resample_salt, a.resample_salt, "缓存路径盐不一致")
		kit.seq(b.mid_ore, a.mid_ore, "缓存路径矿表不一致")
		kit.eq(b._rock_arr.size(), a._rock_arr.size(), "缓存路径岩群数不一致")
		kit.eq(b._hill_arr.size(), a._hill_arr.size(), "缓存路径微丘数不一致")
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
		# 4) 矿格被填实（数据/地形失配）→ 矿校验必须拒
		var g5 := sc.build_grid()
		g5.set_cell(sc.mid_ore[0].x, sc.mid_ore[0].y, Grid.SOLID)
		kit.ok(sc.check_grid(g5) != "", "矿格失配未被拒")
		# 5) 矿数据压脊 → 矿校验必须拒
		var sc2 := Scenario.new()
		sc2.ore_cells.append(Vector2i(sc2.core.x, sc2.ridge_y))
		kit.ok(sc2.check_grid(sc2.build_grid()) != "", "矿压脊未被拒")
		# 6) 盆地内腔封死（即使插口与矿全开也不可达）→ plug_open 必须拒
		var g7 := sc.build_grid()
		var b: Rect2i = sc.basin_rect
		for x in range(b.position.x + 1, b.position.x + b.size.x - 1):
			g7.set_cell(x, b.position.y + 1, Grid.SOLID)
			g7.set_cell(x, b.position.y + 2, Grid.SOLID)
		kit.ok(sc.check_plug_open(g7) != "", "死盆地未被拒"))

	kit.test("freeform-negative-controls", func():
		var sc := Scenario.new(20261004) # 自由路径样本种子（2 主口；结构读数由 scenario.freeform-snapshot 钉死）
		kit.eq(sc.check_grid(sc.build_grid()), "", "自由图基线不绿")
		kit.eq(sc.check_plug_open(sc.build_grid()), "", "自由图插口开门不可达")
		kit.ok(sc._rock_arr.size() > 0 and sc._hill_arr.size() > 0, "样本地貌为空")
		# 1) 主口净空被填 → 拒
		var g1 := sc.build_grid()
		g1.set_cell(sc.spawns[0].x, sc.spawns[0].y + 1, Grid.SOLID)
		kit.ok(sc.check_grid(g1) != "", "主口净空被填未被拒")
		# 2) 岩群格被清 → 拒
		var g2 := sc.build_grid()
		var rc: Vector2i = sc._rock_arr[0]
		g2.set_cell(rc.x, rc.y, Grid.OPEN)
		kit.ok(sc.check_grid(g2) != "", "岩群格被清未被拒")
		# 3) 微丘降平 → 拒
		var g3 := sc.build_grid()
		var hc: Vector2i = sc._hill_arr[0]
		g3.init_h(hc.x, hc.y, 0)
		kit.ok(sc.check_grid(g3) != "", "微丘降平未被拒")
		# 4) 盆地环开洞 → 拒
		var g5 := sc.build_grid()
		g5.set_cell(sc.basin_rect.position.x, sc.basin_rect.position.y + 2, Grid.OPEN)
		kit.ok(sc.check_grid(g5) != "", "盆地环开洞未被拒")
		# 6) 插口填实（唯一覆盖格消失）→ 拒
		var g6 := sc.build_grid()
		g6.set_cell(sc.basin_plug.x, sc.basin_plug.y, Grid.SOLID)
		kit.ok(sc.check_grid(g6) != "", "插口磨损未被拒")
		# 7) 死盆地：内腔只留盆地口 3×3 其余填死 → 全开门也不可达 → plug_open 拒
		var g7 := sc.build_grid()
		var bs := sc.basin_cell()
		var b2: Rect2i = sc.basin_rect
		for yy in range(b2.position.y + 1, b2.position.y + b2.size.y - 1):
			for xx in range(b2.position.x + 1, b2.position.x + b2.size.x - 1):
				if absi(xx - bs.x) <= 1 and absi(yy - bs.y) <= 1:
					continue
				g7.set_cell(xx, yy, Grid.SOLID)
		kit.ok(sc.check_plug_open(g7) != "", "死盆地未被拒"))

	kit.test("rock-cells-readonly", func():
		var sc := Scenario.new(20261004)
		var rc: Array = sc.rock_cells()
		kit.eq(rc.size(), 217, "快照岩群数")
		rc.clear()
		kit.eq(sc.rock_cells().size(), 217, "快照为拷贝（清空不回写）")
		kit.ok(Scenario.new().rock_cells().is_empty(), "默认种子（历史路径）岩群空"))
