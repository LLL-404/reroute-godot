extends SceneTree

# 窗口渲染 + 截屏管线可行性探针：开真窗口渲染 20 帧，读回视口图像存 PNG。
# 判定：exit 0 + PNG 存在且非纯色。这是表现层"渲染出帧"验证路径的地基。


func _initialize() -> void:
	print("[WINDOW] display=", DisplayServer.get_name(), " renderer=", RenderingServer.get_video_adapter_name())
	for i in 20:
		await process_frame
	var vp := root
	var img := vp.get_texture().get_image()
	img.save_png("res://window_test.png")
	print("[WINDOW] size=", vp.size, " img=", img.get_width(), "x", img.get_height())
	quit(0)
