extends ProbeKit

# 海克斯三选一动画截图（窗口模式）：入场 / 悬停 / 选中 三帧。
# 产出：shots/hex_enter.png / hex_hover.png / hex_pick.png
# 同时验证动画结束后确实落到 RunState.pick。

func _initialize() -> void:
	var packed: PackedScene = load("res://game/app/main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	for _i in 5:
		await process_frame
	main.set_process(false)

	main.start_rogue()
	# 先布两座塔，否则第一波就会打爆核心（探针只验证 UI，不验证平衡）
	var cx: int = int(main.sc.core.x)
	var cy: int = int(main.sc.core.y)
	main.apply_mode_at("tower", cx - 1, cy + 4)
	main.apply_mode_at("tower", cx + 2, cy + 5)
	main._run_start_wave()
	var guard := 0
	while main.run.phase == RunState.PHASE_WAVE and guard < 600:
		guard += 1
		main._process(0.25)
	check(main.run.phase == RunState.PHASE_PICK, "已到 PICK")
	check(main.hex != null and main.hex.is_open(), "海克斯面板已展开")
	check(main.hex._cards.size() == 3, "三张卡已建")

	# 1) 入场进行到约一半
	await create_timer(0.18).timeout
	await process_frame
	root.get_texture().get_image().save_png("res://shots/hex_enter.png")

	# 2) 入场完成 → 悬停中卡
	await create_timer(0.62).timeout
	main.hex._hover_on(1)
	await create_timer(0.22).timeout
	await process_frame
	root.get_texture().get_image().save_png("res://shots/hex_hover.png")

	# 3) 选中 → 飞入
	main.hex._select(1)
	await create_timer(0.16).timeout
	await process_frame
	root.get_texture().get_image().save_png("res://shots/hex_pick.png")

	# 4) 动画收尾后必须真的选牌
	await create_timer(0.40).timeout
	check(main.run.phase == RunState.PHASE_WAVE, "选中后进入下一波（实际 %s）" % main.run.phase_name())
	check(main.run.wave_in_layer == 2, "波次已 +1（实际 %d）" % main.run.wave_in_layer)

	finish("HEX_SHOT")
