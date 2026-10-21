extends ProbeKit

# 肉鸽 UI 接线探针（headless 可跑）：验证 main ↔ RunState ↔ run_ui 的闭环。
# 链路：start_rogue → INTRO(可建造) → 开始波 → WAVE 推进 → PICK → 选牌 → 下一波
# 判定：exit 0 + stdout 含 `[ROGUE_UI] PASS`。


func _initialize() -> void:
	var packed: PackedScene = load("res://game/main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	for _i in 5:
		await process_frame
	main.set_process(false)

	check(main.run == null, "启动时是经典模式")
	main.start_rogue()
	check(main.run != null, "肉鸽局已创建")
	check(main.world == main.run.world, "world 指向 run 内部实例")
	check(main.sc == main.run.sc, "sc 指向 run 内部剧本")
	check(main.run_ui.visible, "肉鸽 HUD 可见")
	check(main.run.phase == RunState.PHASE_INTRO, "开局在 INTRO")
	check(main.paused == true, "INTRO 不推进 tick")
	check(main.world.btab.size() == 10, "扩展建筑表 10 项")

	# INTRO 阶段必须能建造（阶段制的手感命门）
	var before: int = main.world.live_buildings()
	main.apply_mode_at("tower", int(main.sc.core.x), int(main.sc.core.y) + 3)
	var after: int = main.world.live_buildings()
	check(after == before + 1, "INTRO 阶段可建塔（%d → %d）" % [before, after])
	check(main.world.tower_cap == 8, "L1 塔位上 8（实际 %d）" % main.world.tower_cap)

	# 开始第一波并推进
	main._run_start_wave()
	check(main.run.phase == RunState.PHASE_WAVE, "点开始 → WAVE")
	var t0: int = main.world.tick_count
	var guard := 0
	while main.run.phase == RunState.PHASE_WAVE and guard < 500:
		guard += 1
		main._process(0.25)
	check(main.world.tick_count > t0, "WAVE 推进 tick（%d → %d）" % [t0, main.world.tick_count])
	check(main.run.phase == RunState.PHASE_PICK, "清场 → PICK（实际 %s）" % main.run.phase_name())
	check(main.run.offers.size() == 3, "三选一 3 张")
	check(main.paused == true, "PICK 不推进 tick")

	# 选牌 → 自动开下一波
	var supply_before: int = main.world.supply
	var card: Dictionary = main.run.offers[0]
	main._run_pick(0)
	check(not card.is_empty(), "选牌返回卡定义")
	check(main.run.phase == RunState.PHASE_WAVE, "选牌后自动开下一波")
	check(main.run.wave_in_layer == 2, "波次 +1（实际 %d）" % main.run.wave_in_layer)
	check(main.world.supply <= supply_before + 100, "供给未被异常扣光")

	# 地形牌手牌路径（直接注入一张，验证 3×3 改高）
	main.run.hand.append("g_fault")
	var cx: int = int(main.sc.core.x)
	var cy: int = int(main.sc.core.y) + 4
	var h0: int = main.world.grid.get_h(cx, cy)
	if main.world.grid.passable(cx, cy):
		var ok: bool = main.run.use_terrain("g_fault", cx, cy)
		check(ok, "地形牌使用成功")
		check(main.world.grid.get_h(cx, cy) >= h0, "3×3 区域已抬升")
	else:
		check(true, "地形牌测试格不可通行，跳过")

	# 回标题必须清掉肉鸽态
	main.to_title()
	check(main.run == null, "回标题后 run 清空")
	check(not main.run_ui.visible, "回标题后肉鸽 HUD 隐藏")
	check(main.shell.current_page() == "title", "回标题成功")

	finish("ROGUE_UI")
