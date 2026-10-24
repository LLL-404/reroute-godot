extends CanvasLayer

# 海克斯式三选一（LOL Arena / ARAM 强化选择手感）：
#   ① 全屏压暗 + 暗角，战场退到背景
#   ② 三张竖版卡按稀有度描边，错峰从下方浮起（透明→实、0.82→1.0 倍、RETURN 缓动）
#   ③ 悬停：卡片上浮 16px、放大 1.07、稀有度光晕点亮（0.45→0.95）
#   ④ 选中：该卡放大到 1.22 并向屏幕中心飞入后淡出，其余两张缩小淡出，压暗层同时退场
#   ⑤ 底部工具行：刷新（供给价）/ 跳过（+50）
# 只读 RunState 的 offers；一切动作经 on_pick / on_refresh / on_skip 交回 main。
# 层级 12：压在 run_ui(11) 与 hud(10) 之上，低于 shell(20)。

const UiStyle = preload("res://game/ui/ui_style.gd")
const HexCardScene = preload("res://game/ui/hex_card.tscn") # 卡片骨架场景（结构在 tscn）

# 稀有度配色（银 / 金 / 棱彩），LOL 口径
const RARITY := {
	"common": { "edge": Color(0.66, 0.69, 0.74), "glow": Color(0.43, 0.48, 0.54), "name": "普通" },
	"rare": { "edge": Color(0.84, 0.65, 0.29), "glow": Color(0.54, 0.42, 0.13), "name": "稀有" },
	"legend": { "edge": Color(0.50, 0.77, 1.00), "glow": Color(0.63, 0.47, 1.00), "name": "棱彩" },
}

const KIND_ICON := {
	"tower": "tower",
	"relic": "ore",
	"talent": "hero",
	"terrain": "fill",
}

const KIND_NAME := {
	"tower": "防御塔",
	"relic": "遗物",
	"talent": "天赋",
	"terrain": "地形牌",
}

# 动画时长（秒）：入场 / 悬停 / 选中
const T_IN := 0.40
const T_STAGGER := 0.085
const T_HOVER := 0.14
const T_PICK := 0.30

var C: Dictionary = {}
var S := 1.0
var sfx: Callable = Callable()

var root: Control
var dim: ColorRect
var vignette: TextureRect
var title: Label
var card_layer: Control
var foot: HBoxContainer

var _cards: Array = []
var _base: Array = [] # 每张卡的基准位置
var _idx_of: Dictionary = {} # holder -> index
var _hover := -1
var _busy := false
var _entering := false
var _cb: Dictionary = {}
var _hud = null
var _open := false


func init(callbacks: Dictionary, _hud_ref) -> void:
	sfx = callbacks.get("sfx", Callable())
	_hud = _hud_ref
	C = UiStyle.DARK
	layer = 12
	_recalc_s()
	_bind()
	visible = false


func _recalc_s() -> void:
	S = clampf(get_viewport().get_visible_rect().size.y / 816.0, 1.0, 1.6)


## 绑定场景骨架（结构在 hex_picker.tscn）；颜色/纹理/位置/边距按 S 注入
func _bind() -> void:
	root = $HexRoot

	dim = root.get_node("dim")
	dim.color = Color(0.03, 0.025, 0.015, 0.0) # 压暗层起始全透，动画拉到 0.72
	dim.mouse_filter = Control.MOUSE_FILTER_STOP # 吃掉点击，防穿透到战场

	vignette = root.get_node("vignette")
	vignette.texture = UiStyle.vignette_tex()
	vignette.stretch_mode = TextureRect.STRETCH_SCALE

	title = root.get_node("title")
	title.add_theme_font_size_override("font_size", int(13.0 * S))
	title.add_theme_color_override("font_color", C["muted"])
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, int(54.0 * S))

	card_layer = root.get_node("card_layer")
	card_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE

	foot = root.get_node("foot")
	foot.add_theme_constant_override("separation", int(14 * S))
	foot.anchor_left = 0.5
	foot.anchor_right = 0.5
	foot.anchor_top = 1.0
	foot.anchor_bottom = 1.0
	foot.offset_left = -180.0 * S
	foot.offset_right = 180.0 * S
	foot.offset_top = -74.0 * S
	foot.offset_bottom = -30.0 * S


# ---------------- 对外接口 ----------------

## 展开三选一。meta = { title, supply, refresh_cost, can_refresh }；
## cb = { pick(idx), refresh(), skip() }
func open(offers: Array, meta: Dictionary, cb: Dictionary) -> void:
	_recalc_s()
	_cb = cb
	_busy = false
	_hover = -1
	_open = true
	visible = true
	if _hud != null:
		_set_dock_visible(false)
	_clear_cards()
	title.text = String(meta.get("title", ""))
	if offers.is_empty():
		return
	var vw: float = get_viewport().get_visible_rect().size.x
	var vh: float = get_viewport().get_visible_rect().size.y
	var cw: float = 242.0 * S
	var ch: float = 306.0 * S
	var gap: float = 36.0 * S
	var n: int = offers.size()
	var total: float = cw * n + gap * (n - 1)
	var x0: float = (vw - total) * 0.5
	var y0: float = (vh - ch) * 0.5 + 10.0 * S
	for i in n:
		var holder: Control = _make_card(i, offers[i], cw, ch)
		var bx: float = x0 + float(i) * (cw + gap)
		var by: float = y0 + (12.0 * S if i != 1 else -10.0 * S) # 中卡略高，形成轻微弧形
		holder.position = Vector2(bx, by + 48.0 * S)
		holder.modulate.a = 0.0
		holder.scale = Vector2(0.82, 0.82)
		card_layer.add_child(holder)
		_cards.append(holder)
		_base.append(Vector2(bx, by))
		_idx_of[holder] = i
	_play_intro()
	_build_foot(meta)
	foot.modulate.a = 0.0


func close() -> void:
	if not _open:
		visible = false
		return
	_open = false
	_busy = false
	var tw := create_tween()
	tw.tween_property(dim, "color:a", 0.0, 0.16)
	tw.parallel().tween_property(title, "modulate:a", 0.0, 0.12)
	for c in _cards:
		var t2 := create_tween()
		t2.tween_property(c, "modulate:a", 0.0, 0.14)
	visible = false
	if _hud != null:
		_set_dock_visible(true)
	_clear_cards()


func is_open() -> bool:
	return _open


# ---------------- 动画 ----------------

func _play_intro() -> void:
	_entering = true
	var tw := create_tween()
	tw.tween_property(dim, "color:a", 0.72, 0.24)
	var tv := create_tween()
	tv.tween_property(vignette, "modulate:a", 1.0, 0.24).from(0.0)
	if sfx.is_valid():
		sfx.call("room_door_open.mp3", 0.45)
	for i in _cards.size():
		var c: Control = _cards[i]
		var d: float = 0.06 + float(i) * T_STAGGER
		var t := create_tween().set_parallel(true)
		t.tween_property(c, "modulate:a", 1.0, 0.26).set_delay(d)
		t.tween_property(c, "scale", Vector2.ONE, T_IN).set_delay(d).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(c, "position", _base[i], T_IN).set_delay(d).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		c.set_meta("tw", t)
	await get_tree().create_timer(0.08 + float(_cards.size() - 1) * T_STAGGER + T_IN).timeout
	_entering = false
	var tf := create_tween()
	tf.tween_property(foot, "modulate:a", 1.0, 0.18).from(0.0)


func _hover_on(i: int) -> void:
	if _busy or _hover == i:
		return
	_hover = i
	var c: Control = _cards[i]
	_kill(c)
	var t := create_tween().set_parallel(true)
	t.tween_property(c, "scale", Vector2(1.07, 1.07), T_HOVER).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(c, "position", _base[i] + Vector2(0, -16.0 * S), 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var g: CanvasItem = c.get_node("glow")
	t.tween_property(g, "modulate:a", 0.95, T_HOVER)
	c.set_meta("tw", t)
	if sfx.is_valid():
		sfx.call("orc_step.mp3", 0.2)


func _hover_off(i: int) -> void:
	if _busy or _hover != i:
		return
	_hover = -1
	var c: Control = _cards[i]
	_kill(c)
	var t := create_tween().set_parallel(true)
	t.tween_property(c, "scale", Vector2.ONE, T_HOVER)
	t.tween_property(c, "position", _base[i], 0.16)
	var g: CanvasItem = c.get_node("glow")
	t.tween_property(g, "modulate:a", 0.45, T_HOVER)
	c.set_meta("tw", t)


## 选中：该卡飞入中心并淡出，其余缩退；结束后回调
func _select(i: int) -> void:
	if _busy or i < 0 or i >= _cards.size():
		return
	_busy = true
	if sfx.is_valid():
		sfx.call("gold_collect.mp3", 0.9)
	var vw: float = get_viewport().get_visible_rect().size.x
	var vh: float = get_viewport().get_visible_rect().size.y
	var c: Control = _cards[i]
	var cw: float = c.size.x
	var ch: float = c.size.y
	_kill(c)
	var center := Vector2((vw - cw) * 0.5, (vh - ch) * 0.5 - 20.0 * S)
	var t := create_tween().set_parallel(true)
	t.tween_property(c, "position", center, T_PICK).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(c, "scale", Vector2(1.22, 1.22), T_PICK).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(c, "modulate:a", 0.0, 0.18).set_delay(T_PICK - 0.12)
	var g: CanvasItem = c.get_node("glow")
	t.tween_property(g, "modulate:a", 1.0, 0.14)
	c.set_meta("tw", t)
	for j in _cards.size():
		if j == i:
			continue
		var o: Control = _cards[j]
		_kill(o)
		var t2 := create_tween().set_parallel(true)
		t2.tween_property(o, "scale", Vector2(0.86, 0.86), 0.18)
		t2.tween_property(o, "modulate:a", 0.0, 0.18)
	var td := create_tween()
	td.tween_property(dim, "color:a", 0.0, 0.22).set_delay(T_PICK - 0.16)
	var tf := create_tween()
	tf.tween_property(foot, "modulate:a", 0.0, 0.12)
	await get_tree().create_timer(T_PICK + 0.04).timeout
	_open = false
	visible = false
	_clear_cards()
	if _hud != null:
		_set_dock_visible(true)
	var fn: Callable = _cb.get("pick", Callable())
	if fn.is_valid():
		fn.call(i)


func _skip() -> void:
	if _busy:
		return
	_busy = true
	var fn: Callable = _cb.get("skip", Callable())
	close()
	if fn.is_valid():
		fn.call()


func _refresh() -> void:
	if _busy:
		return
	var fn: Callable = _cb.get("refresh", Callable())
	if fn.is_valid():
		fn.call()


# ---------------- 卡片 ----------------

func _make_card(i: int, def: Dictionary, cw: float, ch: float) -> Control:
	var rar: String = String(def.get("rarity", "common"))
	var rc: Dictionary = RARITY.get(rar, RARITY["common"])
	# 骨架来自 hex_card.tscn；尺寸/稀有度配色/文本在运行时注入
	var holder: Control = HexCardScene.instantiate()
	holder.name = "card%d" % i
	holder.size = Vector2(cw, ch)
	holder.pivot_offset = Vector2(cw * 0.5, ch * 0.5)
	holder.mouse_filter = Control.MOUSE_FILTER_STOP
	holder.mouse_entered.connect(func() -> void: _hover_on(i))
	holder.mouse_exited.connect(func() -> void: _hover_off(i))
	holder.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton:
			var mb: InputEventMouseButton = ev
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				_select(i))

	# 稀有度光晕（比卡大一圈，悬停点亮）
	var gc: Color = rc["glow"]
	var glow: Panel = holder.get_node("glow")
	glow.position = Vector2(-12.0 * S, -12.0 * S)
	glow.size = Vector2(cw + 24.0 * S, ch + 24.0 * S)
	glow.add_theme_stylebox_override("panel", UiStyle.flat(Color(gc.r, gc.g, gc.b, 0.26), Color(0, 0, 0, 0), int(10 * S), 0))
	glow.modulate.a = 0.45

	# 卡面
	var ec: Color = rc["edge"]
	var card: PanelContainer = holder.get_node("face")
	card.add_theme_stylebox_override("panel", UiStyle.flat(Color(0.075, 0.06, 0.035, 0.97), ec, int(6 * S), 2))

	var m: MarginContainer = card.get_node("Margin")
	for side in ["left", "right"]:
		m.add_theme_constant_override("margin_" + side, int(16 * S))
	m.add_theme_constant_override("margin_top", int(14 * S))
	m.add_theme_constant_override("margin_bottom", int(14 * S))
	var v: VBoxContainer = m.get_node("col")
	v.add_theme_constant_override("separation", int(9 * S))

	var bar: ColorRect = v.get_node("bar")
	bar.color = ec
	bar.custom_minimum_size = Vector2(0, int(3 * S))

	var kind_l: Label = v.get_node("kind")
	kind_l.text = String(KIND_NAME.get(String(def.get("kind", "")), ""))
	kind_l.add_theme_font_size_override("font_size", int(10.0 * S))
	kind_l.add_theme_color_override("font_color", C["muted"])

	var name_l: Label = v.get_node("card_name")
	name_l.text = String(def.get("name", ""))
	name_l.add_theme_font_size_override("font_size", int(22.0 * S))
	name_l.add_theme_color_override("font_color", ec)
	name_l.add_theme_color_override("font_shadow_color", UiStyle.GLOW_GOLD)
	name_l.add_theme_constant_override("shadow_offset_x", 0)
	name_l.add_theme_constant_override("shadow_offset_y", 1)

	var ic = v.get_node("icon") # 挂 ui_icon.gd 脚本：无静态类型才能调 setup
	ic.custom_minimum_size = Vector2(int(84.0 * S), int(84.0 * S))
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ic.setup(String(KIND_ICON.get(String(def.get("kind", "")), "skill")), Color(ec.r, ec.g, ec.b, 0.88))

	var d: Label = v.get_node("desc")
	d.text = String(def.get("desc", ""))
	d.add_theme_font_size_override("font_size", int(13.0 * S))
	d.add_theme_color_override("font_color", C["text"])
	d.custom_minimum_size = Vector2(cw - 34.0 * S, 0)

	var rule: ColorRect = v.get_node("rule")
	rule.color = Color(ec.r, ec.g, ec.b, 0.35)
	rule.custom_minimum_size = Vector2(0, 1)

	var rar_l: Label = v.get_node("rarity")
	rar_l.text = String(rc["name"])
	rar_l.add_theme_font_size_override("font_size", int(10.0 * S))
	rar_l.add_theme_color_override("font_color", ec)

	return holder


## 一次性的悬停/位移动画缓存（避免同一张卡上多条 tween 打架）
func _kill(c: Control) -> void:
	if not c.has_meta("tw"): # 未登记过 tween：无需停旧动画（get_meta 缺省 null 会报错）
		return
	var old = c.get_meta("tw")
	if old is Tween and old.is_running():
		old.kill()
	c.set_meta("tw", null)


## 指挥盘整体显隐：不改 hud.gd（该文件存在外部并发写入，改动会被覆盖），
## 直接从 hex 侧遍历 HUD 的公开字段。dock 只是背景板，按钮/装饰是独立顶层控件。
func _set_dock_visible(vis: bool) -> void:
	if _hud == null:
		return
	if _hud.dock != null:
		_hud.dock.visible = vis
	for c in _hud.dock_caps:
		if c != null:
			c.visible = vis
	for key in _hud.mode_buttons:
		var b = _hud.mode_buttons[key]
		if b != null:
			b.visible = vis
	if _hud.skill_btn != null:
		_hud.skill_btn.visible = vis
	for row in _hud.dock_rows:
		for b2 in row:
			if b2 != null:
				b2.visible = vis


func _build_foot(meta: Dictionary) -> void:
	for c in foot.get_children():
		foot.remove_child(c)
		c.queue_free()
	foot.modulate.a = 1.0
	var cost: int = int(meta.get("refresh_cost", 0))
	var can: bool = bool(meta.get("can_refresh", false)) and int(meta.get("supply", 0)) >= cost
	var b_refresh := _foot_btn("刷新  %d" % cost, can)
	b_refresh.pressed.connect(_refresh)
	foot.add_child(b_refresh)
	var b_skip := _foot_btn("跳过  +50", true)
	b_skip.pressed.connect(_skip)
	foot.add_child(b_skip)


func _foot_btn(text: String, enabled: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = not enabled
	b.custom_minimum_size = Vector2(int(150.0 * S), int(36.0 * S))
	b.add_theme_font_size_override("font_size", int(13.0 * S))
	b.add_theme_color_override("font_color", C["text"])
	b.add_theme_color_override("font_disabled_color", C["muted"].darkened(0.35))
	b.add_theme_stylebox_override("normal", UiStyle.flat(C["btn"], C["gold_lo"], int(4 * S)))
	b.add_theme_stylebox_override("hover", UiStyle.flat(C["btn_hover"], C["gold"], int(4 * S)))
	b.add_theme_stylebox_override("pressed", UiStyle.flat(C["btn_pressed"], C["gold_hi"], int(4 * S)))
	return b


func _clear_cards() -> void:
	for c in _cards:
		if is_instance_valid(c):
			_kill(c)
			c.queue_free()
	_cards.clear()
	_base.clear()
	_idx_of.clear()
	for c in foot.get_children():
		foot.remove_child(c)
		c.queue_free()
