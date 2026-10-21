extends ProbeKit

# M2-a 判定（DIGGING-SPEC §2.3 / §4）：矿格不接受隔空开挖，英雄站到邻格才挖得开。
# 跑法（cwd=reroute-godot）：godot --headless -s res://tests/probes/probe_dig_intent.gd
# 判定：exit 0 + stdout 含 [DIG] PASS + stderr 无 ERROR。
#
# 本探针只覆盖 M2-a（纯 main.gd 意图层，sim 零改动）。M2-b 的进度条 / 打断 / 回退
# 由 probe_dig.gd 覆盖（尚未实现）。

func _initialize() -> void:
	var packed: PackedScene = load("res://game/main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	for _i in 5:
		await process_frame

	var world = main.world
	var sc = main.sc

	# ---- ① 矿格隔空点挖：拒绝，且零副作用 ----
	var ore: Vector2i = sc.mid_ore[0]
	check(world.grid.at(ore.x, ore.y) == Grid.COVER, "矿格初始为 COVER")
	var sup0: int = world.supply
	main.apply_mode_at("dig", ore.x, ore.y)
	check(world.grid.at(ore.x, ore.y) == Grid.COVER, "隔空点挖被拒（格子仍 COVER）")
	cmp_int(world.supply, sup0, "隔空点挖零扣费")
	check(not main._ore_intent.is_empty(), "已记录开挖意图")
	cmp_int(int(main._ore_intent["ore"].x), ore.x, "意图矿格 x")
	cmp_int(int(main._ore_intent["ore"].y), ore.y, "意图矿格 y")

	# ---- ② 站位选择：必须是可通行、无建筑的六邻 ----
	var stand: Vector2i = main._pick_ore_stand(ore.x, ore.y)
	check(stand.x >= 0 and stand.y >= 0, "存在可站邻格")
	check(world.grid.passable(stand.x, stand.y), "站位可通行")
	check(world.building_at(stand.x, stand.y) == null, "站位无建筑")
	check(Grid.hex_dist(stand.x, stand.y, ore.x, ore.y) == 1, "站位与矿格六邻距离=1")

	# ---- ③ 未到场：不发命令 ----
	world.hero["x"] = stand.x + 6
	world.hero["y"] = stand.y
	world.hero["tx"] = -1
	world.hero["ty"] = -1
	main._tick_ore_intent()
	check(world.grid.at(ore.x, ore.y) == Grid.COVER, "英雄未到场 → 矿格不动")
	check(not main._ore_intent.is_empty(), "英雄未到场 → 意图保留")

	# ---- ④ 到场：挖开 + 产出 ----
	world.hero["x"] = stand.x
	world.hero["y"] = stand.y
	main._tick_ore_intent()
	check(world.grid.at(ore.x, ore.y) == Grid.OPEN, "到场后矿格挖开")
	cmp_int(world.supply, sup0 + Sim.ORE_YIELD, "产出 = ORE_YIELD（%d）" % Sim.ORE_YIELD)
	check(main._ore_intent.is_empty(), "意图已消费")

	# ---- ⑤ 普通土方仍可隔空挖 ----
	var plain := Vector2i(-1, -1)
	for y in world.grid.h:
		for x in world.grid.w:
			if world.grid.at(x, y) == Grid.COVER and not sc.is_ore(x, y):
				plain = Vector2i(x, y)
				break
		if plain.x >= 0:
			break
	check(plain.x >= 0, "存在普通覆盖层")
	if plain.x >= 0:
		var sup1: int = world.supply
		main.apply_mode_at("dig", plain.x, plain.y)
		check(world.grid.at(plain.x, plain.y) == Grid.OPEN, "普通土方仍可隔空挖")
		cmp_int(world.supply, sup1, "M2-a 阶段土方仍免费（M1 才收紧为 15）")

	# ---- ⑥ 换操作即放弃意图 ----
	main.apply_mode_at("dig", sc.mid_ore[1].x, sc.mid_ore[1].y)
	check(not main._ore_intent.is_empty(), "第二个矿格意图已记录")
	main.apply_mode_at("fill", plain.x, plain.y)
	check(main._ore_intent.is_empty(), "换成其它操作 → 矿格意图作废")

	finish("DIG", 18)
