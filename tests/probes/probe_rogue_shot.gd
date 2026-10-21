extends ProbeKit

# 肉鸽模式截图探针（窗口模式）：出 INTRO 与 PICK 两个阶段的实机图，供验收与宣传。
# 跑法：godot --path . -s res://tests/probes/probe_rogue_shot.gd
# 产出：shots/rogue_intro.png / shots/rogue_pick.png


func _initialize() -> void:
	var packed: PackedScene = load("res://game/main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	for _i in 5:
		await process_frame
	main.set_process(false)

	main.start_rogue()
	for _i in 8:
		await process_frame
	root.get_texture().get_image().save_png("res://shots/rogue_intro.png")
	check(main.run.phase == RunState.PHASE_INTRO, "INTRO 截图已存")

	# 建两座塔让画面不空
	var cx: int = int(main.sc.core.x)
	main.apply_mode_at("tower", cx - 1, int(main.sc.core.y) + 4)
	main.apply_mode_at("tower", cx + 2, int(main.sc.core.y) + 5)

	# 推进到 PICK
	main._run_start_wave()
	var guard := 0
	while main.run.phase == RunState.PHASE_WAVE and guard < 600:
		guard += 1
		main._process(0.25)
	for _i in 6:
		await process_frame
	check(main.run.phase == RunState.PHASE_PICK, "已到 PICK（实际 %s）" % main.run.phase_name())
	root.get_texture().get_image().save_png("res://shots/rogue_pick.png")

	finish("ROGUE_SHOT")
