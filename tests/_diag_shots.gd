extends SceneTree

# 临时诊断（拍2）：多自由种子顶视正交截图，目视「岩野山体 / 2D 盆地 / 四侧视觉门」。
# 跑法（窗口模式）：GODOT --path P -s res://tests/_diag_shots.gd

func _initialize() -> void:
	var packed: PackedScene = load("res://game/main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	for _i in 10:
		await process_frame
	main.set_process(false)
	main.start_match()
	main.paused = true
	for seed in [20261004, 20261005, 20261006, 20261012]:
		main.run_index = int(seed) - 20261003 - 1
		main.new_game()
		main.start_match()
		main.paused = true
		main.view.sync(main.world)
		main.view.core.env.fog_enabled = false # 诊断：关雾（仅本脚本，不落库）
		var cam: Camera3D = main.view.core.camera
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = 86.0
		cam.position = Vector3(0.0, 120.0, 0.0)
		cam.look_at(Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.0, -1.0))
		for _i in 4:
			await process_frame
		var img := root.get_texture().get_image()
		img.save_png("res://shots/_diag_%d.png" % int(seed))
		print("[DIAG] shot ", seed)
	quit()
