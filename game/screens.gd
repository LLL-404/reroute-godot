extends CanvasLayer

# 界面壳（移植 reroute/scripts/screens.lua + ScreenManager 的页栈语义）：标题 / 暂停 / 结算
# / 存档（3 槽，读|存双模式）/ 设置（音量+全屏）五屏 + 通用确认弹窗。
# 游戏流转即屏状态：进行中 = current_page()==""；暂停 = "pause"；结算 = "gameover"；
# 标题 = "title"；存档页 = "slots"；设置页 = "settings"。
# 页面懒建缓存复用；切换带 0.18s 淡入；按钮回调由 main 注入；存档/设置模块直接 preload。
# 口径说明：母版 Shell.resume 走 ScreenManager:Back()，而 Back 在"栈<=1 拒绝"的保护下
# 无法弹出单元素栈（对局=空栈模型下的疑点）；本版按 Shell 自身注释"弹栈到空"语义实现 resume=close_all。

const SaveIO = preload("res://game/save_io.gd")
const UserSettings = preload("res://game/user_settings.gd")
const UiStyle = preload("res://game/ui_style.gd")
# 标题衬线字（Noto Serif SC Bold 子集 13.8KB，31 字形；许可与加工见 CREDITS.md §3.3）。
# 子集只含屏标题用字（改道暂停读档存档设置防线守住…），正文/按钮仍走主题默认 Noto Sans SC。
const F_SERIF: FontFile = preload("res://assets/fonts/NotoSerifSC-Bold-Sub.ttf")

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

# 存档页状态
var slots_mode := "load" # load | save
var slots_from := "title" # 返回目标页
# 设置页状态
var settings_from := "title"
var _cfg: Dictionary = {}

# 确认弹窗
var confirm_layer: Control = null
var confirm_text: Label = null
var _confirm_cb := Callable()


## 初始化：注入回调、HUD 引用、缩放、层级、宿主控件、确认弹窗
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
	host.theme = UiStyle.build_theme(C, S)
	add_child(host)
	_build_confirm()


# ---------------- 公开 API（对齐母版 Shell） ----------------

## 打开标题页：懒建 + 刷新「读档存档」可用性 + 淡入
func open_title() -> void:
	_ensure("title")
	_refresh_title()
	_show("title")


## 打开暂停页（懒建 + 淡入）
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
	_hide_confirm()


## 打开结算页：注入胜负标题（色 = hp|danger）与统计文案
func open_gameover(won: bool, world) -> void:
	_ensure("gameover")
	go_title.text = "防线守住了！" if won else "防线失守"
	go_title.add_theme_color_override("font_color", C["hp"] if won else C["danger"])
	go_body.text = hud.build_stats(world)
	_show("gameover")


## 存档页（mode: "load" 读档（标题进入） / "save" 存档（暂停进入）；from = 返回目标页）
func open_slots(mode: String, from: String) -> void:
	_ensure("slots")
	slots_mode = mode
	slots_from = from
	var head: Label = pages["slots"].find_child("label_slot_head", true, false)
	head.text = "读档" if mode == "load" else "存档"
	var status: Label = pages["slots"].find_child("label_slot_status", true, false)
	status.text = "选择槽位开始对局" if mode == "load" else "选择槽位保存当前进度"
	_refresh_slots()
	_show("slots")


## 设置页（from = 返回目标页）
func open_settings(from: String) -> void:
	_ensure("settings")
	settings_from = from
	_load_settings_into_ui()
	_show("settings")


## 退出确认（标题「退出游戏」按钮 / Android 返回键共用）
func open_quit_confirm() -> void:
	open_confirm("确定退出游戏？", func() -> void: cb["quit"].call())


## 当前页名（"" = 对局中；main 消费做流转判定）
func current_page() -> String:
	return current


## Esc 路由：确认弹窗=取消；暂停=继续；进行中=暂停；存档/设置=回上级；
## 标题/结算不响应。返回 true 表示已消费。
func handle_key(keycode: int) -> bool:
	if keycode != KEY_ESCAPE:
		return false
	if confirm_open():
		close_confirm()
		return true
	if current == "pause":
		cb["resume"].call()
		return true
	elif current == "":
		cb["pause"].call()
		return true
	elif current == "slots":
		_show(slots_from)
		return true
	elif current == "settings":
		_show(settings_from)
		return true
	return false


## 对齐母版 Shell.update 的调用点（Godot 信号模型无需延迟队列，保留空实现）。
func update() -> void:
	pass


# ---------------- 确认弹窗 ----------------

## 确认弹窗是否开启
func confirm_open() -> bool:
	return confirm_layer != null and confirm_layer.visible


## 关闭确认弹窗（等同取消，不触发回调）
func close_confirm() -> void:
	_hide_confirm()


## 打开确认弹窗：文本 + 确定回调（取消即丢弃）
func open_confirm(text: String, fn: Callable) -> void:
	confirm_text.text = text
	_confirm_cb = fn
	confirm_layer.visible = true


## 隐藏弹窗并清空回调（幂等）
func _hide_confirm() -> void:
	if confirm_layer != null:
		confirm_layer.visible = false
	_confirm_cb = Callable()


## 弹窗结果路由：ok 且回调有效才执行
func _resolve_confirm(ok: bool) -> void:
	var fn := _confirm_cb
	_hide_confirm()
	if ok and fn.is_valid():
		fn.call()


## 构建全局确认弹窗层（晚于 host 加入 → 永在最上）
func _build_confirm() -> void:
	confirm_layer = Control.new()
	confirm_layer.name = "ConfirmLayer"
	confirm_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	confirm_layer.mouse_filter = Control.MOUSE_FILTER_STOP # 吃指针：弹窗下页面不可点
	confirm_layer.visible = false
	var veil := ColorRect.new()
	veil.color = UiStyle.VEIL_HEAVY
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	confirm_layer.add_child(veil)
	UiStyle.overlay_fx(confirm_layer) # A5+A4
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	confirm_layer.add_child(center)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(300.0 * S, 0)
	card.theme_type_variation = UiStyle.CARD_VAR
	UiStyle.corner_dress(card, C["gold_lo"]) # C 饰线
	center.add_child(card)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, int(22 * S))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", int(16 * S))
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(col)
	confirm_text = _label("", 15.0 * S, C["text"])
	confirm_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	confirm_text.custom_minimum_size = Vector2(256.0 * S, 0)
	confirm_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(confirm_text)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", int(12 * S))
	var okb := _button("确定", true, 116.0 * S, 40.0 * S, 12.0 * S, func() -> void:
		_resolve_confirm(true))
	okb.name = "btn_confirm_ok"
	var canc := _button("取消", false, 116.0 * S, 40.0 * S, 12.0 * S, func() -> void:
		_resolve_confirm(false))
	canc.name = "btn_confirm_cancel"
	row.add_child(okb)
	row.add_child(canc)
	col.add_child(row)
	card.add_child(margin)
	add_child(confirm_layer) # 晚于 host 添加 → 永远盖在页面之上


# ---------------- 页面构建 ----------------

## 样式盒快捷构造：委托 ui_style 工厂（唯一真源）
func _flat(bg: Color, border: Color, radius: int, border_w: int = 1) -> StyleBoxFlat:
	return UiStyle.flat(bg, border, radius, border_w) # 委托样式工厂（唯一真源 ui_style.gd）


## 标签快捷构造：serif=true 走 Noto Serif 子集（屏标题专用）
func _label(text: String, fs: float, color: Color, serif := false, glow := false) -> Label:
	return UiStyle.label(text, fs, color, F_SERIF if serif else null, true, glow)


## 衬线隔字标题：逐字 Label + 等宽间隔（子集无空格字形，用布局实现字距）。
func _serif_title(text: String, fs: float, color: Color, gap: float = 12.0) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", int(gap * S))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for ch in text:
		row.add_child(_label(ch, fs, color, true, true))
	return row


## 卡片内金标题条（文明 6 式：暗底 + 衬线金字 + 底缘金线）。
func _title_bar(label: Label, bar_h: float = 38.0) -> Panel:
	var p := Panel.new()
	p.theme_type_variation = UiStyle.TITLEBAR_VAR
	p.custom_minimum_size = Vector2(0, bar_h * S)
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_FILL
	p.add_child(label)
	return p


## 金分隔线（1px）。
func _rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = UiStyle.RULE
	r.custom_minimum_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## 按钮快捷构造：主题变体（发射器 a）+ A1 光边；pad_left ≥0 时复制样式盒加左距
func _button(text: String, primary: bool, w: float, h: float, fs: float, fn: Callable, pad_left: float = -1.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, h)
	b.size = Vector2(w, h)
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_size_override("font_size", int(fs))
	# 发射器 a：字色/四态样式盒全走主题变体（UiStyle.build_theme），不再逐钮 override
	b.theme_type_variation = UiStyle.BTN_PRIMARY_VAR if primary else UiStyle.BTN_MENU_VAR
	UiStyle.edge_dress(b, C["edge_hi"], UiStyle.RULE) # A1 光边
	if pad_left >= 0.0: # 逐实例左距：复制共享样式盒成专用副本（避免污染主题）
		for k in ["normal", "hover", "pressed"]:
			var sb: StyleBoxFlat = UiStyle.get_theme().get_stylebox(k, b.theme_type_variation).duplicate()
			sb.content_margin_left = pad_left
			b.add_theme_stylebox_override(k, sb)
	b.pressed.connect(fn)
	return b


## 页面底板：全屏吃指针 + 幕色 + 氛围层（A5 暗角 + A4 噪粒）
func _page_base(veil: Color) -> Control:
	var page := Control.new()
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.mouse_filter = Control.MOUSE_FILTER_STOP # 全屏吃指针：防穿透到战场/HUD
	var bg := ColorRect.new()
	bg.color = veil
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(bg)
	UiStyle.overlay_fx(page) # A5 暗角 + A4 噪粒（在 bg 上、内容下）
	return page


## 滑杆金化：暗槽 + 古金边 + 已过段亮金（grabber 图标走默认主题，不引贴图）。
func _style_slider(s: HSlider) -> void:
	s.theme_type_variation = UiStyle.SLIDER_VAR


## 构建标题页：底部渐暗帷幕 + 左列式菜单 + 玩法说明浮层
func _build_title() -> Control:
	var page := Control.new()
	page.name = "page_title"
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.mouse_filter = Control.MOUSE_FILTER_STOP # 全屏吃指针：防穿透到战场/HUD

	# 底部 55% 渐暗帷幕（战场全景可见，向下渐入帝王金黑）
	# 口径坑实录：Color() 浮点分量 >1 会钳成白；GradientTexture2D 行 0=矩形顶。
	var veil := TextureRect.new()
	veil.name = "title_veil"
	veil.texture = UiStyle.title_veil_tex()
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veil.anchor_left = 0.0
	veil.anchor_right = 1.0
	veil.anchor_top = 0.45
	veil.anchor_bottom = 1.0
	page.add_child(veil)
	UiStyle.overlay_fx(page) # A5+A4

	# 左对齐菜单列（x=18% 宽度 240，文明 6 主菜单口径）
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", int(12 * S))
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.anchor_left = 0.18
	col.anchor_right = 0.18
	col.anchor_top = 0.0
	col.anchor_bottom = 1.0
	col.offset_left = 0
	col.offset_right = int(240.0 * S)
	col.offset_top = int(110.0 * S)
	col.offset_bottom = int(-64.0 * S)
	page.add_child(col)

	var title_row := _serif_title("改道", 54.0 * S, C["gold_hi"], 26.0)
	title_row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(title_row)
	var tagline := _label("放墙改道 · 修运河，别只堵路", 12.0 * S, C["muted"])
	tagline.size_flags_horizontal = Control.SIZE_FILL
	col.add_child(tagline)
	col.add_child(_rule())

	var btn_start := _button("开始对局", true, 240.0 * S, 48.0 * S, 15.0 * S, func() -> void:
		cb["start_match"].call(), 14.0 * S)
	btn_start.name = "btn_start"
	btn_start.alignment = HORIZONTAL_ALIGNMENT_LEFT
	col.add_child(btn_start)

	var btn_continue := _button("读档存档", false, 240.0 * S, 42.0 * S, 12.0 * S, func() -> void:
		open_slots("load", "title"), 14.0 * S)
	btn_continue.name = "btn_continue"
	btn_continue.alignment = HORIZONTAL_ALIGNMENT_LEFT
	col.add_child(btn_continue)

	var btn_settings := _button("设置", false, 240.0 * S, 42.0 * S, 12.0 * S, func() -> void:
		open_settings("title"), 14.0 * S)
	btn_settings.name = "btn_settings"
	btn_settings.alignment = HORIZONTAL_ALIGNMENT_LEFT
	col.add_child(btn_settings)

	var btn_tips := _button("玩法说明", false, 240.0 * S, 42.0 * S, 12.0 * S, func() -> void:
		tips_panel.visible = not tips_panel.visible, 14.0 * S)
	btn_tips.name = "btn_tips"
	btn_tips.alignment = HORIZONTAL_ALIGNMENT_LEFT
	col.add_child(btn_tips)

	var btn_quit := _button("退出游戏", false, 240.0 * S, 42.0 * S, 12.0 * S, func() -> void:
		open_quit_confirm(), 14.0 * S)
	btn_quit.name = "btn_quit"
	btn_quit.alignment = HORIZONTAL_ALIGNMENT_LEFT
	col.add_child(btn_quit)

	# 玩法说明浮层（菜单列右侧；默认隐藏，切换不影响列布局）
	tips_panel = PanelContainer.new()
	tips_panel.name = "panel_tips"
	tips_panel.custom_minimum_size = Vector2(340.0 * S, 0)
	tips_panel.visible = false
	tips_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tips_panel.theme_type_variation = UiStyle.CARD_VAR
	UiStyle.corner_dress(tips_panel, C["gold_lo"]) # C 饰线
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
	page.add_child(tips_panel)
	tips_panel.reset_size()
	var vw := get_viewport().get_visible_rect().size.x
	tips_panel.position = Vector2(vw * 0.18 + 264.0 * S, 110.0 * S)

	# 版本 / 赛事行（左下角）
	var jam := _label("GameJam 2026 · 聚光灯主题「涌现」", 9.0 * S, C["muted"])
	jam.anchor_left = 0.0
	jam.anchor_right = 0.0
	jam.anchor_top = 1.0
	jam.anchor_bottom = 1.0
	jam.offset_left = int(20.0 * S)
	jam.offset_right = int(340.0 * S)
	jam.offset_top = int(-30.0 * S)
	jam.offset_bottom = int(-14.0 * S)
	jam.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	jam.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	jam.size_flags_horizontal = Control.SIZE_FILL
	page.add_child(jam)
	return page


## 构建暂停页（继续 / 保存进度 / 设置 / 重开本局 / 回标题）
func _build_pause() -> Control:
	var page := _page_base(UiStyle.VEIL_SOFT)
	page.name = "page_pause"
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(center)
	var pcard := PanelContainer.new()
	pcard.custom_minimum_size = Vector2(320.0 * S, 0)
	pcard.theme_type_variation = UiStyle.CARD_VAR
	UiStyle.corner_dress(pcard, C["gold_lo"]) # C 饰线
	center.add_child(pcard)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, int(26 * S))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", int(11 * S))
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(_title_bar(_label("暂停", 22.0 * S, C["gold_hi"], true)))
	col.add_child(_rule())
	var btn_resume := _button("继续", true, 240.0 * S, 44.0 * S, 14.0 * S, func() -> void:
		cb["resume"].call())
	btn_resume.name = "btn_resume"
	col.add_child(btn_resume)
	var btn_save := _button("保存进度", false, 240.0 * S, 42.0 * S, 12.0 * S, func() -> void:
		open_slots("save", "pause"))
	btn_save.name = "btn_save"
	col.add_child(btn_save)
	var btn_settings := _button("设置", false, 240.0 * S, 42.0 * S, 12.0 * S, func() -> void:
		open_settings("pause"))
	btn_settings.name = "btn_settings_pause"
	col.add_child(btn_settings)
	var btn_restart := _button("重开本局", false, 240.0 * S, 42.0 * S, 12.0 * S, func() -> void:
		cb["restart"].call())
	btn_restart.name = "btn_restart"
	col.add_child(btn_restart)
	var btn_title := _button("回标题", false, 240.0 * S, 42.0 * S, 12.0 * S, func() -> void:
		cb["to_title"].call())
	btn_title.name = "btn_to_title"
	col.add_child(btn_title)
	margin.add_child(col)
	pcard.add_child(margin)
	return page


## 构建结算页（胜负标题 + 统计文案 + 再来一局 / 回标题）
func _build_gameover() -> Control:
	var page := _page_base(UiStyle.VEIL_HEAVY)
	page.name = "page_gameover"
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(center)
	var pcard := PanelContainer.new()
	pcard.custom_minimum_size = Vector2(400.0 * S, 0)
	pcard.theme_type_variation = UiStyle.CARD_VAR
	UiStyle.corner_dress(pcard, C["gold_lo"]) # C 饰线
	center.add_child(pcard)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, int(26 * S))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", int(14 * S))
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	# 胜负标题：文本/颜色由 open_gameover 注入（探针断言 色=hp|danger）；衬线字形已进子集
	go_title = _label("", 34.0 * S, C["danger"], true, true)
	col.add_child(go_title)
	go_body = _label("", 13.0 * S, C["text"])
	go_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	go_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	go_body.custom_minimum_size = Vector2(400.0 * S - 52.0 * S, 0)
	col.add_child(go_body)
	var btn_again := _button("再来一局", true, 220.0 * S, 44.0 * S, 14.0 * S, func() -> void:
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


## 构建存档页（3 槽：读档|存档双模式 + 删除 + 状态行）
func _build_slots() -> Control:
	var page := _page_base(UiStyle.VEIL_PAGE)
	page.name = "page_slots"
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(center)
	var pcard := PanelContainer.new()
	pcard.custom_minimum_size = Vector2(440.0 * S, 0)
	pcard.theme_type_variation = UiStyle.CARD_VAR
	UiStyle.corner_dress(pcard, C["gold_lo"]) # C 饰线
	center.add_child(pcard)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, int(24 * S))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", int(10 * S))
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	# 动态标题（读档/存档）：open_slots 改 text，衬线字体常驻
	var head := _label("读档", 22.0 * S, C["gold_hi"], true)
	head.name = "label_slot_head"
	col.add_child(_title_bar(head))
	col.add_child(_rule())
	for i in range(1, SaveIO.SLOT_N + 1):
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", int(8 * S))
		var b := _button("槽 %d · 空" % i, false, 300.0 * S, 36.0 * S, 11.0 * S, _on_slot_pressed.bind(i), 12.0 * S)
		b.name = "btn_slot%d" % i
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.add_child(b)
		var del := _button("删除", false, 62.0 * S, 36.0 * S, 10.0 * S, _on_slot_delete.bind(i))
		del.name = "btn_slot_del%d" % i
		row.add_child(del)
		col.add_child(row)
	var status := _label("", 10.0 * S, C["muted"])
	status.name = "label_slot_status"
	col.add_child(status)
	var btn_back := _button("返回", false, 220.0 * S, 40.0 * S, 12.0 * S, func() -> void:
		_show(slots_from))
	btn_back.name = "btn_slots_back"
	col.add_child(btn_back)
	margin.add_child(col)
	pcard.add_child(margin)
	return page


## 构建设置页（音乐/音效滑杆 + 全屏开关；改值即应用并落盘）
func _build_settings() -> Control:
	var page := _page_base(UiStyle.VEIL_PAGE)
	page.name = "page_settings"
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(center)
	var pcard := PanelContainer.new()
	pcard.custom_minimum_size = Vector2(440.0 * S, 0)
	pcard.theme_type_variation = UiStyle.CARD_VAR
	UiStyle.corner_dress(pcard, C["gold_lo"]) # C 饰线
	center.add_child(pcard)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, int(24 * S))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", int(12 * S))
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(_title_bar(_label("设置", 22.0 * S, C["gold_hi"], true)))
	col.add_child(_rule())

	var row_music := HBoxContainer.new()
	row_music.alignment = BoxContainer.ALIGNMENT_CENTER
	row_music.add_theme_constant_override("separation", int(10 * S))
	var lbl_music := _label("音乐音量", 12.0 * S, C["muted"])
	lbl_music.custom_minimum_size = Vector2(88.0 * S, 0)
	row_music.add_child(lbl_music)
	var sld_music := HSlider.new()
	sld_music.name = "sld_music"
	sld_music.min_value = UserSettings.VOL_MIN
	sld_music.max_value = UserSettings.VOL_MAX
	sld_music.step = 1
	sld_music.custom_minimum_size = Vector2(180.0 * S, 24.0 * S)
	sld_music.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_style_slider(sld_music)
	row_music.add_child(sld_music)
	var val_music := _label("100", 12.0 * S, C["gold_hi"])
	val_music.name = "lbl_music_val"
	val_music.custom_minimum_size = Vector2(38.0 * S, 0)
	row_music.add_child(val_music)
	col.add_child(row_music)

	var row_sfx := HBoxContainer.new()
	row_sfx.alignment = BoxContainer.ALIGNMENT_CENTER
	row_sfx.add_theme_constant_override("separation", int(10 * S))
	var lbl_sfx := _label("音效音量", 12.0 * S, C["muted"])
	lbl_sfx.custom_minimum_size = Vector2(88.0 * S, 0)
	row_sfx.add_child(lbl_sfx)
	var sld_sfx := HSlider.new()
	sld_sfx.name = "sld_sfx"
	sld_sfx.min_value = UserSettings.VOL_MIN
	sld_sfx.max_value = UserSettings.VOL_MAX
	sld_sfx.step = 1
	sld_sfx.custom_minimum_size = Vector2(180.0 * S, 24.0 * S)
	sld_sfx.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_style_slider(sld_sfx)
	row_sfx.add_child(sld_sfx)
	var val_sfx := _label("100", 12.0 * S, C["gold_hi"])
	val_sfx.name = "lbl_sfx_val"
	val_sfx.custom_minimum_size = Vector2(38.0 * S, 0)
	row_sfx.add_child(val_sfx)
	col.add_child(row_sfx)

	var row_fs := HBoxContainer.new()
	row_fs.name = "row_fullscreen"
	row_fs.alignment = BoxContainer.ALIGNMENT_CENTER
	row_fs.add_theme_constant_override("separation", int(10 * S))
	var lbl_fs := _label("全屏", 12.0 * S, C["muted"])
	lbl_fs.custom_minimum_size = Vector2(88.0 * S, 0)
	row_fs.add_child(lbl_fs)
	var chk_fs := CheckButton.new()
	chk_fs.name = "chk_fullscreen"
	chk_fs.focus_mode = Control.FOCUS_NONE
	row_fs.add_child(chk_fs)
	col.add_child(row_fs)

	var btn_back := _button("返回", false, 220.0 * S, 40.0 * S, 12.0 * S, func() -> void:
		_show(settings_from))
	btn_back.name = "btn_settings_back"
	col.add_child(btn_back)
	margin.add_child(col)
	pcard.add_child(margin)

	# 行为接线：滑杆/开关改值即应用 + 落盘（user://settings.cfg）
	sld_music.value_changed.connect(func(v: float) -> void:
		_cfg["music"] = int(v)
		val_music.text = str(int(v))
		_apply_settings())
	sld_sfx.value_changed.connect(func(v: float) -> void:
		_cfg["sfx"] = int(v)
		val_sfx.text = str(int(v))
		_apply_settings())
	chk_fs.toggled.connect(func(on: bool) -> void:
		_cfg["fullscreen"] = on
		UserSettings.apply_video(_cfg)
		UserSettings.save_cfg(_cfg))
	return page


# ---------------- 存档页行为 ----------------

## 标题「继续对局」可用性：有任何非空槽位（含损坏档——进列表可删）即亮。
func _refresh_title() -> void:
	var btn: Button = pages["title"].find_child("btn_continue", true, false)
	btn.disabled = not SaveIO.has_any()


## 按模式刷新槽位：读档空槽禁用；删除钮仅读档且非空时显示
func _refresh_slots() -> void:
	var page: Control = pages["slots"]
	for info in SaveIO.list_slots():
		var slot: int = info["slot"]
		var row: Button = page.find_child("btn_slot%d" % slot, true, false)
		row.text = _slot_row_text(info)
		var empty: bool = info.get("empty", true)
		row.disabled = empty if slots_mode == "load" else false
		var del: Button = page.find_child("btn_slot_del%d" % slot, true, false)
		del.visible = slots_mode == "load" and not empty


## 槽位行文本：空 / 无效原因 / 波次 + 时长 + 存档时间
func _slot_row_text(info: Dictionary) -> String:
	var slot: int = info["slot"]
	if info.get("empty", true):
		return "槽 %d · 空" % slot
	if not info.get("ok", false):
		return "槽 %d · %s" % [slot, str(info.get("reason", "无效存档"))]
	var m: Dictionary = info.get("meta", {})
	var wave: int = int(m.get("wave", 0))
	var wtext := "开局" if wave <= 0 else "第 %d 波" % wave
	var t: int = int(m.get("time_s", 0))
	var saved := str(m.get("saved_text", ""))
	var tail := "" if saved == "" else " · " + saved
	return "槽 %d · %s · %d:%02d%s" % [slot, wtext, t / 60, t % 60, tail]


## 更新存档页状态行（操作反馈）
func _set_slot_status(text: String) -> void:
	var status: Label = pages["slots"].find_child("label_slot_status", true, false)
	status.text = text


## 槽位点击：读档走 cb.load_slot；存档走空槽直存或覆盖确认
func _on_slot_pressed(slot: int) -> void:
	var info := SaveIO.slot_info(slot)
	if slots_mode == "load":
		if info.get("empty", true):
			return
		if not info.get("ok", false):
			_set_slot_status(str(info.get("reason", "存档损坏")))
			return
		var ok: bool = cb["load_slot"].call(slot)
		if not ok:
			_set_slot_status("存档损坏或版本不符")
			_refresh_slots()
	else:
		if info.get("empty", true):
			_do_save(slot)
		else:
			open_confirm("覆盖槽 %d 的存档？" % slot, func() -> void:
				_do_save(slot))


## 执行存档并回报状态（覆盖确认 / 空槽直存共用）
func _do_save(slot: int) -> void:
	var ok: bool = cb["save_slot"].call(slot)
	_set_slot_status("已保存到槽 %d" % slot if ok else "存档写入失败")
	_refresh_slots()


## 删除槽位：先弹确认，确认后删除并刷新
func _on_slot_delete(slot: int) -> void:
	open_confirm("删除槽 %d 的存档？" % slot, func() -> void:
		SaveIO.delete_slot(slot)
		_set_slot_status("已删除槽 %d" % slot)
		_refresh_slots())


# ---------------- 设置页行为 ----------------

## 设置页回填：读 cfg 填入滑杆/开关（no_signal 防触发落盘）
func _load_settings_into_ui() -> void:
	_cfg = UserSettings.load_cfg()
	var page: Control = pages["settings"]
	var sld_music: HSlider = page.find_child("sld_music", true, false)
	var sld_sfx: HSlider = page.find_child("sld_sfx", true, false)
	var val_music: Label = page.find_child("lbl_music_val", true, false)
	var val_sfx: Label = page.find_child("lbl_sfx_val", true, false)
	var chk_fs: CheckButton = page.find_child("chk_fullscreen", true, false)
	var row_fs: Control = page.find_child("row_fullscreen", true, false)
	sld_music.set_value_no_signal(_cfg["music"])
	sld_sfx.set_value_no_signal(_cfg["sfx"])
	val_music.text = str(_cfg["music"])
	val_sfx.text = str(_cfg["sfx"])
	chk_fs.set_pressed_no_signal(_cfg["fullscreen"])
	row_fs.visible = OS.get_name() != "Android" # Android 恒全屏，隐藏该行


## 应用音频设置并落盘（滑杆改动回调）
func _apply_settings() -> void:
	UserSettings.apply_audio(_cfg)
	UserSettings.save_cfg(_cfg)


# ---------------- 页切换 ----------------

## 懒建页面（首次调用时构建并缓存）
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
		"slots":
			p = _build_slots()
		"settings":
			p = _build_settings()
	p.visible = false
	host.add_child(p)
	pages[name] = p
	return p


## 显示指定页面（其余隐藏，0.18s 淡入）；回标题时顺带刷新「继续对局」可用性。
func _show(name: String) -> void:
	for k in pages:
		pages[k].visible = (k == name)
	current = name
	if name == "title":
		_refresh_title()
	var p: Control = pages[name]
	p.modulate.a = 0.0
	var t := create_tween()
	t.tween_property(p, "modulate:a", 1.0, 0.18)
