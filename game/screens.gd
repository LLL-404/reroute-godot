extends CanvasLayer

# 界面壳（移植 reroute/scripts/screens.lua + ScreenManager 的页栈语义，砍掉未用的弹窗/toast）：
# 标题 / 暂停 / 结算三屏。游戏流转即屏状态：进行中 = current_page()==""；
# 暂停 = "pause"；结算 = "gameover"；回标题 = "title"。
# 页面懒建缓存复用；切换带 0.18s 淡入；按钮回调由 main 注入。
# 口径说明：母版 Shell.resume 走 ScreenManager:Back()，而 Back 在"栈<=1 拒绝"的保护下
# 无法弹出单元素栈（对局=空栈模型下的疑点）；本版按 Shell 自身注释"弹栈到空"语义实现 resume=close_all。

var S := 1.0
var cb: Dictionary = {}
var hud = null # HUD 实例（复用它的大盘色板/build_stats/theme）
var C: Dictionary = {}
var host: Control
var pages: Dictionary = {} # name -> Control
var current := ""

var tips_panel: PanelContainer
var go_title: Label
var go_body: Label


func init(callbacks: Dictionary, hud_ref) -> void:
	cb = callbacks
	hud = hud_ref
	C = hud.DARK
	S = clampf(get_viewport().get_visible_rect().size.y / 816.0, 1.0, 1.6)
	layer = 20 # 壳在 HUD（layer 10）之上
	host = Control.new()
	host.name = "ScreenHost"
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.theme = hud.theme
	add_child(host)


# ---------------- 公开 API（对齐母版 Shell） ----------------

func open_title() -> void:
	_ensure("title")
	_show("title")


func open_pause() -> void:
	_ensure("pause")
	_show("pause")


## 从暂停回到对局（弹栈到空）。
func resume() -> void:
	close_all()


## 清空到对局（空栈）。也可用于从结算直接回对局。
func close_all() -> void:
	for k in pages:
		pages[k].visible = false
	current = ""


func open_gameover(won: bool, world) -> void:
	_ensure("gameover")
	go_title.text = "防线守住了！" if won else "防线失守"
	go_title.add_theme_color_override("font_color", C["hp"] if won else C["danger"])
	go_body.text = hud.build_stats(world)
	_show("gameover")


func current_page() -> String:
	return current


## Esc 路由：暂停屏=继续；进行中（空态）=暂停；标题/结算不响应。返回 true 表示已消费。
func handle_key(keycode: int) -> bool:
	if keycode != KEY_ESCAPE:
		return false
	if current == "pause":
		cb["resume"].call()
		return true
	elif current == "":
		cb["pause"].call()
		return true
	return false


## 对齐母版 Shell.update 的调用点（Godot 信号模型无需延迟队列，保留空实现）。
func update() -> void:
	pass


# ---------------- 页面构建 ----------------

func _flat(bg: Color, border: Color, radius: int, border_w: int = 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	return sb


func _label(text: String, fs: float, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", int(fs))
	l.add_theme_color_override("font_color", color)
	l.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return l


func _button(text: String, primary: bool, w: float, h: float, fs: float, fn: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, h)
	b.size = Vector2(w, h)
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_size_override("font_size", int(fs))
	var c_text: Color = Color8(255, 255, 255, 255) if primary else C["text"]
	b.add_theme_color_override("font_color", c_text)
	b.add_theme_color_override("font_hover_color", c_text)
	b.add_theme_color_override("font_pressed_color", c_text)
	var bg_n: Color = Color8(85, 105, 232) if primary else C["btn"]
	var bg_h: Color = Color8(104, 122, 239) if primary else C["btn_hover"]
	var bg_p: Color = Color8(65, 86, 209) if primary else C["btn_pressed"]
	var bd: Color = Color8(85, 105, 232) if primary else C["border"]
	b.add_theme_stylebox_override("normal", _flat(bg_n, bd, 9))
	b.add_theme_stylebox_override("hover", _flat(bg_h, bd, 9))
	b.add_theme_stylebox_override("pressed", _flat(bg_p, bd, 9))
	b.pressed.connect(fn)
	return b


func _page_base(veil: Color) -> Control:
	var page := Control.new()
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.mouse_filter = Control.MOUSE_FILTER_STOP # 全屏吃指针：防穿透到战场/HUD
	var bg := ColorRect.new()
	bg.color = veil
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(bg)
	return page


func _build_title() -> Control:
	var page := _page_base(Color8(8, 10, 16, 150))
	page.name = "page_title"
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", int(16 * S))
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(col)

	col.add_child(_label("改 道", 46.0 * S, C["text"]))
	col.add_child(_label("放墙改道 · 修运河，别只堵路", 13.0 * S, C["muted"]))

	var btn_start := _button("开始对局", true, 220.0 * S, 48.0 * S, 14.0 * S, func() -> void:
		cb["start_match"].call())
	btn_start.name = "btn_start"
	col.add_child(btn_start)

	var btn_tips := _button("玩法说明", false, 220.0 * S, 40.0 * S, 12.0 * S, func() -> void:
		tips_panel.visible = not tips_panel.visible)
	btn_tips.name = "btn_tips"
	col.add_child(btn_tips)

	tips_panel = PanelContainer.new()
	tips_panel.name = "panel_tips"
	tips_panel.custom_minimum_size = Vector2(340.0 * S, 0)
	tips_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	tips_panel.visible = false
	tips_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tips_panel.add_theme_stylebox_override("panel", _flat(C["card"], C["border"], int(12 * S)))
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, int(16 * S))
	var tips_col := VBoxContainer.new()
	tips_col.add_theme_constant_override("separation", int(7 * S))
	for line in [
		"守住核心，撑到终局哨响即胜利",
		"放墙改道：怪绕得越远，死时赏金越高",
		"挖矿得供给；填高 / 挖低能改地形",
		"蛮兽皮糙，先清虫群，别让它贴脸",
		"英雄的震荡波是保命技，冷却长别空放",
	]:
		tips_col.add_child(_label(line, 10.0 * S, C["muted"]))
	margin.add_child(tips_col)
	tips_panel.add_child(margin)
	col.add_child(tips_panel)

	col.add_child(_label("GameJam 2026 · 聚光灯主题「涌现」", 9.0 * S, C["muted"]))
	return page


func _build_pause() -> Control:
	var page := _page_base(Color8(8, 10, 16, 140))
	page.name = "page_pause"
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(center)
	var pcard := PanelContainer.new()
	pcard.custom_minimum_size = Vector2(320.0 * S, 0)
	pcard.add_theme_stylebox_override("panel", _flat(C["card"], C["border"], int(14 * S)))
	center.add_child(pcard)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, int(26 * S))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", int(12 * S))
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(_label("暂停", 22.0 * S, C["text"]))
	var btn_resume := _button("继续", true, 220.0 * S, 42.0 * S, 12.0 * S, func() -> void:
		cb["resume"].call())
	btn_resume.name = "btn_resume"
	col.add_child(btn_resume)
	var btn_restart := _button("重开本局", false, 220.0 * S, 42.0 * S, 12.0 * S, func() -> void:
		cb["restart"].call())
	btn_restart.name = "btn_restart"
	col.add_child(btn_restart)
	var btn_title := _button("回标题", false, 220.0 * S, 42.0 * S, 12.0 * S, func() -> void:
		cb["to_title"].call())
	btn_title.name = "btn_to_title"
	col.add_child(btn_title)
	margin.add_child(col)
	pcard.add_child(margin)
	return page


func _build_gameover() -> Control:
	var page := _page_base(Color8(8, 10, 16, 190))
	page.name = "page_gameover"
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(center)
	var pcard := PanelContainer.new()
	pcard.custom_minimum_size = Vector2(380.0 * S, 0)
	pcard.add_theme_stylebox_override("panel", _flat(C["card"], C["border"], int(14 * S)))
	center.add_child(pcard)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, int(26 * S))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", int(14 * S))
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	go_title = _label("", 28.0 * S, C["danger"])
	col.add_child(go_title)
	go_body = _label("", 12.0 * S, C["muted"])
	go_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	go_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	go_body.custom_minimum_size = Vector2(380.0 * S - 52.0 * S, 0)
	col.add_child(go_body)
	var btn_again := _button("再来一局", true, 220.0 * S, 42.0 * S, 12.0 * S, func() -> void:
		cb["restart"].call())
	btn_again.name = "btn_again"
	col.add_child(btn_again)
	var btn_title2 := _button("回标题", false, 220.0 * S, 42.0 * S, 12.0 * S, func() -> void:
		cb["to_title"].call())
	btn_title2.name = "btn_to_title2"
	col.add_child(btn_title2)
	margin.add_child(col)
	pcard.add_child(margin)
	return page


# ---------------- 页切换 ----------------

func _ensure(name: String) -> Control:
	if pages.has(name):
		return pages[name]
	var p: Control = null
	match name:
		"title":
			p = _build_title()
		"pause":
			p = _build_pause()
		"gameover":
			p = _build_gameover()
	p.visible = false
	host.add_child(p)
	pages[name] = p
	return p


func _show(name: String) -> void:
	for k in pages:
		pages[k].visible = (k == name)
	current = name
	var p: Control = pages[name]
	p.modulate.a = 0.0
	var t := create_tween()
	t.tween_property(p, "modulate:a", 1.0, 0.18)
