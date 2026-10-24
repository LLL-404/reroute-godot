extends CanvasLayer

# 肉鸽模式 HUD：层/波进度、阶段操作条（开波 / 三选一 / 进入下一层）、地形牌手牌。
# 独立 CanvasLayer（layer 11），不侵入 game/hud.gd 与 game/screens.gd 的既有结构。
# 只读 RunState，不发命令；所有动作经 cb 回调交回 main。

const UiStyle = preload("res://game/ui/ui_style.gd")

var C: Dictionary = {}
var S := 1.0
var cb: Dictionary = {}
var run = null

var root: Control
var head: Label
var bar: PanelContainer
var bar_body: VBoxContainer
var hand_row: HBoxContainer
var toast: Label


func init(callbacks: Dictionary, _hud) -> void:
	cb = callbacks
	C = UiStyle.DARK
	layer = 11
	_recalc_s()
	_bind()
	visible = false


func _recalc_s() -> void:
	S = clampf(get_viewport().get_visible_rect().size.y / 816.0, 1.0, 1.6)


## 绑定场景骨架（结构在 run_ui.tscn）；位置/尺寸/边距/主题变体按 S 注入
func _bind() -> void:
	root = $RunRoot

	# 顶部层/波条（位置按 S 运行时注入，场景只保证节点层级）
	var top: PanelContainer = root.get_node("top")
	top.theme_type_variation = UiStyle.CARD_VAR
	top.position = Vector2(int(24.0 * S), int(18.0 * S))
	top.custom_minimum_size = Vector2(int(360.0 * S), int(34.0 * S))
	var m: MarginContainer = top.get_node("Margin")
	m.add_theme_constant_override("margin_left", int(14 * S))
	m.add_theme_constant_override("margin_right", int(14 * S))
	m.add_theme_constant_override("margin_top", int(6 * S))
	m.add_theme_constant_override("margin_bottom", int(6 * S))
	head = m.get_node("head")
	head.add_theme_font_size_override("font_size", int(13.0 * S))
	head.add_theme_color_override("font_color", C["gold_hi"])

	# 底部容器：全屏 VBox 贴底对齐，bar 与手牌都在里面按内容高度排
	var holder: VBoxContainer = root.get_node("BottomHolder")
	holder.add_theme_constant_override("separation", int(8 * S))
	var hand_pad: MarginContainer = holder.get_node("hand_pad")
	hand_pad.add_theme_constant_override("margin_left", int(24 * S))
	hand_row = hand_pad.get_node("hand_row")
	hand_row.add_theme_constant_override("separation", int(8 * S))

	# 阶段条：居中 + 按内容撑高
	var bar_wrap: HBoxContainer = holder.get_node("bar_wrap")
	bar = bar_wrap.get_node("bar")
	bar.theme_type_variation = UiStyle.CARD_VAR
	var bm: MarginContainer = bar.get_node("bm")
	for side in ["left", "right", "top", "bottom"]:
		bm.add_theme_constant_override("margin_" + side, int(18 * S))
	bar_body = bm.get_node("bar_body")
	bar_body.add_theme_constant_override("separation", int(10 * S))
	var pad: Control = holder.get_node("pad_bottom")
	pad.custom_minimum_size = Vector2(0, int(24 * S))

	# 浮字提示
	toast = root.get_node("toast")
	toast.add_theme_font_size_override("font_size", int(12.0 * S))
	toast.add_theme_color_override("font_color", C["muted"])
	toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast.position = Vector2(0, int(64.0 * S))
	toast.visible = false


## 进入肉鸽局：显示 HUD 并刷新
func show_run(r) -> void:
	run = r
	visible = true
	refresh()


func hide_run() -> void:
	visible = false
	run = null


## 按当前阶段重建底部操作条
func refresh() -> void:
	if run == null:
		return
	var sm: Dictionary = run.summary()
	head.text = "第 %d/%d 层 · 第 %d/%d 波 · 供给 %d" % [
		int(sm["layer"]), int(sm["layer_max"]), int(sm["wave"]), int(sm["wave_max"]),
		int(sm["supply"])]
	_clear(bar_body)
	_clear(hand_row)
	var ph: int = int(sm["phase"])
	if ph == RunState.PHASE_INTRO:
		_add_label("第 %d 层 · %s" % [int(sm["layer"]), String(run.threat_info.get("note", ""))], C["gold_hi"], 15.0)
		_add_action("开始第 %d 波" % (int(sm["wave"]) + 1), true, func() -> void: cb["start_wave"].call())
	elif ph == RunState.PHASE_PICK:
		# 三选一由 hex_picker 全屏接管；这里只留一行状态，不画卡
		_add_label("强化选择中 · 已选 %d 项构筑" % (int(sm["relics"]) + int(sm["talents"]) + int(sm["unlocked"])), C["muted"], 12.0)
	elif ph == RunState.PHASE_LAYER_CLEAR:
		_add_label("第 %d 层守住 · 累计击杀 %d" % [int(sm["layer"]), run.world.kills], C["hp"], 15.0)
		_add_action("进入第 %d 层" % (int(sm["layer"]) + 1), true, func() -> void: cb["advance"].call())
	elif ph == RunState.PHASE_WAVE:
		var left: int = maxi(0, run.wave_end - run.world.tick_count)
		_add_label("第 %d 波进行中 · 场上 %d 只 · 剩余 %d 秒" % [
			int(sm["wave"]), run.world.units.size(), ceili(float(left) / 20.0)], C["muted"], 12.0)
	# 手牌
	_add_hand()


func _add_hand() -> void:
	if run.hand.is_empty():
		return
	var lbl := UiStyle.label("手牌", 10.0 * S, C["muted"])
	hand_row.add_child(lbl)
	for cid in run.hand:
		var card: Dictionary = RewardPool.by_id(String(cid))
		if card.is_empty():
			continue
		var b := _small(String(card["name"]), func() -> void: cb["use_card"].call(String(cid)))
		b.custom_minimum_size = Vector2(int(84.0 * S), int(30.0 * S))
		hand_row.add_child(b)


func _card_button(idx: int, card: Dictionary) -> Button:
	var b := Button.new()
	b.text = "%s\n%s" % [String(card["name"]), String(card["desc"])]
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.custom_minimum_size = Vector2(int(236.0 * S), int(104.0 * S))
	b.add_theme_font_size_override("font_size", int(12.0 * S))
	b.add_theme_color_override("font_color", C["text"])
	b.add_theme_color_override("font_hover_color", C["gold_hi"])
	var st := UiStyle.flat(C["btn"], C["gold_lo"], int(4 * S))
	b.add_theme_stylebox_override("normal", st)
	b.add_theme_stylebox_override("hover", UiStyle.flat(C["btn_hover"], C["gold"], int(4 * S)))
	b.add_theme_stylebox_override("pressed", UiStyle.flat(C["btn_pressed"], C["gold_hi"], int(4 * S)))
	b.pressed.connect(func() -> void: cb["pick"].call(idx))
	return b


func _add_label(text: String, color: Color, fs: float) -> void:
	var l := UiStyle.label(text, fs * S, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar_body.add_child(l)


func _add_action(text: String, primary: bool, fn: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(int(240.0 * S), int(40.0 * S))
	b.add_theme_font_size_override("font_size", int(15.0 * S))
	b.add_theme_color_override("font_color", C["on_gold"] if primary else C["text"])
	var bg: Color = C["gold"] if primary else C["btn"]
	var bd: Color = C["gold_hi"] if primary else C["gold_lo"]
	b.add_theme_stylebox_override("normal", UiStyle.flat(bg, bd, int(4 * S)))
	b.add_theme_stylebox_override("hover", UiStyle.flat(C["gold_hi"], C["edge_hi"], int(4 * S)))
	b.add_theme_stylebox_override("pressed", UiStyle.flat(UiStyle.GOLD_PRESSED, bd, int(4 * S)))
	b.pressed.connect(fn)
	var wrap := HBoxContainer.new()
	wrap.alignment = BoxContainer.ALIGNMENT_CENTER
	wrap.add_child(b)
	bar_body.add_child(wrap)


func _small(text: String, fn: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(int(110.0 * S), int(32.0 * S))
	b.add_theme_font_size_override("font_size", int(12.0 * S))
	b.add_theme_color_override("font_color", C["text"])
	b.add_theme_stylebox_override("normal", UiStyle.flat(C["btn"], C["gold_lo"], int(3 * S)))
	b.add_theme_stylebox_override("hover", UiStyle.flat(C["btn_hover"], C["gold"], int(3 * S)))
	b.add_theme_stylebox_override("pressed", UiStyle.flat(C["btn_pressed"], C["gold_hi"], int(3 * S)))
	b.pressed.connect(fn)
	return b


func _clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


## 短提示（刷新失败/手牌耗尽等）
func flash(text: String) -> void:
	toast.text = text
	toast.visible = true
	var t := get_tree().create_timer(2.0)
	t.timeout.connect(func() -> void: toast.visible = false)
