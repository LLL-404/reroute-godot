extends SceneTree

func _initialize() -> void:
	var packed: PackedScene = load("res://game/app/main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	for _i in 10:
		await process_frame
	main.start_match()
	var view = main.view
	var world = main.world
	var cw: Vector3 = view.cell_to_world(int(world.sc.core.x), int(world.sc.core.y))
	view.core.focus = Vector3(cw.x, 0.0, cw.z)
	view.core._zoom = 0.40
	view.core._apply_cam()
	for _i in 6:
		await process_frame
	var img: Image = root.get_texture().get_image()
	img.save_png("res://shots/camcheck_core.png")
	print("[CAM] core=", world.sc.core, " world=", cw, " size=", img.get_width(), "x", img.get_height())
	quit(0)
