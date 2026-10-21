extends SceneTree

# 取景标定（非闸）：先造好西/东咽喉防线 + 刷一队怪，再按多组（focus, zoom）各拍一张。
# 跑法：godot --path . --resolution 1920x1080 -s res://tests/probes/probe_promo_cal.gd

var main = null
var view = null
var world = null
var out_dir := "res://shots/promo_test/"


func _initialize() -> void:
	var packed: PackedScene = load("res://game/main.tscn")
	main = packed.instantiate()
	root.add_child(main)
	for _i in 10:
		await process_frame
	main.run_index = -1
	main.new_game()
	main.start_match()
	view = main.view
	world = main.world
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))

	# 造好防线（西 + 东）
	for c in [[20, 45], [21, 45], [23, 45], [24, 45], [21, 43], [23, 43], [44, 45], [45, 45], [47, 45], [48, 45], [45, 43], [47, 43], [21, 50], [22, 50], [23, 50], [24, 50], [25, 50]]:
		world.apply_command({ "kind": "wall", "x": c[0], "y": c[1] })
	for c in [[21, 40], [23, 40], [20, 41], [45, 40], [47, 40], [44, 41], [29, 12], [36, 12]]:
		world.apply_command({ "kind": "tower", "x": c[0], "y": c[1] })
	for i in 8:
		var x := 20 + (i % 4)
		var y := 52 + (i / 4)
		if world.cell_vacant(x, y) and world.building_at(x, y) == null:
			world.apply_command({ "kind": "spawn", "x": x, "y": y, "speed": 4, "kind_id": Sim.E_SWARM })
	# 等塔建好 + 怪走上路
	var guard := 0
	while world.tick_count < 150 and guard < 100000:
		guard += 1
		await process_frame

	var presets := [
		["w46_055", Vector2i(23, 46), 0.55],
		["w46_062", Vector2i(23, 46), 0.62],
		["w48_070", Vector2i(23, 48), 0.70],
		["w44_062", Vector2i(23, 44), 0.62],
		["w50_062", Vector2i(23, 50), 0.62],
		["e48_062", Vector2i(46, 48), 0.62],
		["wide_095", Vector2i(33, 30), 0.95],
		["wide_085", Vector2i(33, 26), 0.85],
	]
	for p in presets:
		var name: String = p[0]
		var cell: Vector2i = p[1]
		var zoom: float = p[2]
		var w: Vector3 = view.cell_to_world(cell.x, cell.y)
		view.core.focus = Vector3(w.x, 0.0, w.z)
		view.core._zoom = zoom
		view.core._apply_cam()
		await process_frame
		await process_frame
		await process_frame
		var img: Image = root.get_texture().get_image()
		var path := "%scal_%s.png" % [out_dir, name]
		img.save_png(path)
		print("[CAL] ", path, " focus=", cell, " zoom=", zoom)
	quit(0)
