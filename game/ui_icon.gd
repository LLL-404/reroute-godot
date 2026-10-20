extends Control
# HUD 线面图标（v2.5）：24 单位网格等比绘制；颜色由 HUD 注入（随按钮三态换色）。
# 规约：本文件不构造颜色（lint L1），只消费外部 color。

var kind := ""
var color: Color = Color.WHITE


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


## 设置图形与颜色（HUD 在 _paint_rows / _paint_top_icons 调）
func setup(k: String, c: Color) -> void:
	kind = k
	color = c
	queue_redraw()


func _draw() -> void:
	if size.x <= 0.0 or kind == "":
		return
	var u := size.x / 24.0
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(u, u))
	var lw := 1.8
	match kind:
		"wall":
			for r in 3:
				var y := 5.5 + r * 5.0
				if r % 2 == 0:
					draw_rect(Rect2(3.0, y, 8.0, 4.0), color)
					draw_rect(Rect2(13.0, y, 8.0, 4.0), color)
				else:
					draw_rect(Rect2(3.0, y, 3.5, 4.0), color)
					draw_rect(Rect2(8.5, y, 8.0, 4.0), color)
					draw_rect(Rect2(18.5, y, 2.5, 4.0), color)
		"tower":
			draw_polyline(PackedVector2Array([Vector2(7, 20), Vector2(17, 20), Vector2(15, 9), Vector2(9, 9), Vector2(7, 20)]), color, lw)
			draw_polyline(PackedVector2Array([Vector2(8.6, 9), Vector2(8.6, 5), Vector2(10.4, 5), Vector2(10.4, 9)]), color, lw)
			draw_polyline(PackedVector2Array([Vector2(13.6, 9), Vector2(13.6, 5), Vector2(15.4, 5), Vector2(15.4, 9)]), color, lw)
			draw_line(Vector2(12, 12), Vector2(12, 16), color, lw)
		"ore":
			draw_polyline(PackedVector2Array([Vector2(12, 3), Vector2(20, 9), Vector2(12, 21), Vector2(4, 9), Vector2(12, 3)]), color, lw)
			draw_line(Vector2(4, 9), Vector2(20, 9), color, lw)
			draw_line(Vector2(12, 3), Vector2(8.5, 9), color, lw)
			draw_line(Vector2(12, 3), Vector2(15.5, 9), color, lw)
			draw_line(Vector2(8.5, 9), Vector2(12, 21), color, lw)
			draw_line(Vector2(15.5, 9), Vector2(12, 21), color, lw)
		"fill":
			draw_polyline(PackedVector2Array([Vector2(4, 15), Vector2(12, 6), Vector2(20, 15)]), color, lw)
			draw_line(Vector2(4, 20), Vector2(20, 20), color, lw)
		"lower":
			draw_polyline(PackedVector2Array([Vector2(4, 9), Vector2(12, 18), Vector2(20, 9)]), color, lw)
			draw_line(Vector2(4, 21), Vector2(20, 21), color, lw)
		"skill":
			draw_circle(Vector2(12, 12), 3.2, color)
			for i in 8:
				var a := TAU * float(i) / 8.0
				var r1 := 10.5 if i % 2 == 0 else 8.4
				draw_line(Vector2(12, 12) + Vector2(cos(a), sin(a)) * 6.0, Vector2(12, 12) + Vector2(cos(a), sin(a)) * r1, color, lw)
		"remove":
			draw_line(Vector2(6, 6), Vector2(18, 18), color, lw + 0.4)
			draw_line(Vector2(18, 6), Vector2(6, 18), color, lw + 0.4)
		"hero":
			draw_circle(Vector2(12, 7.4), 3.2, color)
			draw_arc(Vector2(12, 20), 7.2, PI, TAU, 20, color, lw)
		"sun":
			draw_circle(Vector2(12, 12), 3.8, color)
			for i in 8:
				var a := TAU * float(i) / 8.0
				draw_line(Vector2(12, 12) + Vector2(cos(a), sin(a)) * 7.0, Vector2(12, 12) + Vector2(cos(a), sin(a)) * 10.0, color, lw)
		"pause":
			draw_rect(Rect2(7.0, 5.0, 3.4, 14.0), color)
			draw_rect(Rect2(13.6, 5.0, 3.4, 14.0), color)
		"coin":
			draw_arc(Vector2(12, 12), 8.4, 0.0, TAU, 28, color, lw)
			draw_rect(Rect2(9.4, 9.4, 5.2, 5.2), color, false, lw)
		"shield":
			draw_polyline(PackedVector2Array([Vector2(12, 3), Vector2(20, 6), Vector2(18.6, 13), Vector2(12, 21), Vector2(5.4, 13), Vector2(4, 6), Vector2(12, 3)]), color, lw)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
