extends SceneTree

# 临时诊断：定位屏幕黑块 —— 打印横幅状态 + 隐藏候选后截图对拍。
# 跑法（窗口模式）：GODOT --path P -s res://tests/_diag_blackbox.gd

func _initialize() -> void:
	var packed: PackedScene = load("res://game/main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	for _i in 10:
		await process_frame
	main.start_match()
	for _i in 3:
		await process_frame
	print("[BB] banner_root.visible=", main.hud.banner_root.visible, " until=", main.hud._banner_until, " title='", main.hud.banner_title.text, "' sub='", main.hud.banner_sub.text, "'")
	print("[BB] banner_card pos=", main.hud.banner_card.position, " size=", main.hud.banner_card.size, " visible=", main.hud.banner_root.visible)
	var img0 := root.get_texture().get_image()
	img0.save_png("res://shots/_diag_bb_before.png")
	main.hud.banner_root.visible = false
	for _i in 3:
		await process_frame
	var img1 := root.get_texture().get_image()
	img1.save_png("res://shots/_diag_bb_after.png")
	# 逐像素差异范围
	var minx := 99999
	var miny := 99999
	var maxx := -1
	var maxy := -1
	for y in range(0, img0.get_height(), 2):
		for x in range(0, img0.get_width(), 2):
			var c0 := img0.get_pixel(x, y)
			var c1 := img1.get_pixel(x, y)
			if absf(c0.r - c1.r) + absf(c0.g - c1.g) + absf(c0.b - c1.b) > 0.02:
				minx = mini(minx, x)
				miny = mini(miny, y)
				maxx = maxi(maxx, x)
				maxy = maxi(maxy, y)
	print("[BB] diff box x=", minx, "..", maxx, " y=", miny, "..", maxy)
	quit()
