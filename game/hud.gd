extends Control

const UiStyle = preload("res://game/ui_style.gd")

# HUD（移植 reroute/scripts/hud.lua）：顶栏（核心血条/波次倒计时/供给/热层钮/暂停钮）
# + 右下操作模式列 + 技能钮 + 波次横幅 + 击杀赏金浮字池。
# 纯展示层：只读模拟状态；按钮回调由 main 注入。布局为绝对像素（S 缩放口径同母版），
# 窗口尺寸变化时 _layout() 重算 S 并重排；hit_regions() 是点击排除的唯一来源（main 消费）。

var S := 1.0

# 安全区（Android 刘海/挖孔/手势条）：逻辑像素内边距 (左, 上, 右, 下)；桌面恒 0。
# _safe_override 为探针注入口（Vector4(-1,-1,-1,-1) = 恢复平台自动）。
var safe := Vector4.ZERO
var _safe_override := Vector4(-1.0, -1.0, -1.0, -1.0)

# 几何常量（与母版一致）：hud 布局与 main 点击排除共用这一份
const BTN_H := 42.0
const BTN_GAP := 7.0
const COL_W := 128.0
const EDGE := 16.0
const TOP_H := 56.0
const TOP_STRIP_H := 64.0 # 点击排除条高（56 + 留白）
const HINT_TEXT := "放墙改道 · 怪绕得越远死时赏金越高——修运河，别只堵路"
const CORNER_N := 7
const CORNER_W := EDGE + COL_W + EDGE # 160
const CORNER_H := EDGE + CORNER_N * BTN_H + (CORNER_N - 1) * BTN_GAP + BTN_GAP + BTN_H + EDGE # 417
const FLOAT_N := 10 # 浮字池
const FLOAT_LIFE := 18 # 0.9s（tick）
const FLOAT_RISE := 1.4 # 每 tick 上浮像素
const BANNER_LIFE := 40 # 横幅驻留 2s（tick）

# 帝王金黑色板（v2.1 改版，docs/UI-REDESIGN-20261017.md §2）：
# 旧暗蓝板（Style.dark 迁移）换文明 6 式暖金调；key 全保留（探针按 key 动态取值），
# 新增 gold 系 token 供壳层（screens.gd）与本地样式共用。
var DARK := {
	"bar": Color8(18, 16, 9, 224),
	"card": Color8(20, 15, 8, 232),
	"text": Color8(242, 232, 216, 255),
	"muted": Color8(176, 164, 132, 255),
	"hp": Color8(64, 200, 176, 255),
	"supply": Color8(200, 168, 108, 255),
	"danger": Color8(228, 92, 72, 255),
	"border": Color8(150, 120, 76, 255),
	"active": Color8(200, 168, 108, 255),
	"active_border": Color8(224, 198, 140, 255),
	"btn": Color8(24, 18, 10, 220),
	"btn_hover": Color8(36, 27, 16, 236),
	"btn_pressed": Color8(15, 11, 6, 250),
	"gold": Color8(200, 168, 108, 255),
	"gold_hi": Color8(224, 198, 140, 255),
	"gold_lo": Color8(96, 76, 44, 255),
	"edge_hi": Color8(236, 208, 150, 120),
	"shadow": Color8(0, 0, 0, 150),
	"track": Color8(10, 8, 5, 220),
	"warn": Color8(180, 96, 44, 255),
	"on_gold": Color8(43, 32, 16, 255),
}

var callbacks: Dictionary = {}
var mode := "wall"
var CORE_HP := 1200
var WAVE_NAMES := {}
var MODE_LABELS: Array = []

# 控件
var top_bar: Panel
var hp_bar: ProgressBar
var hp_text: Label
var wave_text: Label
var supply_text: Label
var heat_btn: Button
var pause_btn: Button
var mode_buttons: Dictionary = {}
var skill_btn: Button
var banner_root: Control
var banner_card: PanelContainer
var banner_title: Label
var banner_sub: Label
var hint_panel: PanelContainer
var hint_label: Label
var floats: Array = []
var _toplevel: Array = []

# 状态缓存（口径同母版）
var _tick := 0
var _supply = null
var _supply_tick := -99
var _ws_key := ""
var _ws_text := ""
var _next_w = null
var _route_shown := false
var _behemoth_intro := false
var _banner_until = null
var _skill_shown := -1
var _banner_tween: Tween = null


## 初始化：全屏铺底、监听窗口变化
func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_viewport().size_changed.connect(_layout)


## 由 main 注入回调并一次性构建：callbacks = { on_mode(m), on_pause(), on_heat(), on_skill() }
func build(cb: Dictionary) -> void:
	callbacks = cb
	var win := get_viewport().get_visible_rect().size
	S = clampf(win.y / 816.0, 1.0, 1.6)
	CORE_HP = int(Sim.BUILDINGS[Sim.B_CORE - 1]["hp"])
	WAVE_NAMES = { Sim.E_SWARM: "虫群", Sim.E_BEHEMOTH: "蛮兽" }
	MODE_LABELS = [
		{ "key": "wall", "label": "墙 ×" + str(int(Sim.BUILDINGS[Sim.B_WALL - 1]["cost"])) },
		{ "key": "tower", "label": "塔 ×" + str(int(Sim.BUILDINGS[Sim.B_TOWER - 1]["cost"])) },
		{ "key": "dig", "label": "挖矿" },
		{ "key": "fill", "label": "填高 ×" + str(Sim.FILL_COST) },
		{ "key": "lower", "label": "挖低 ×" + str(Sim.LOWER_COST) },
		{ "key": "remove", "label": "拆" },
		{ "key": "hero", "label": "英雄" },
	]

	# 字体主题（Godot 默认字体无 CJK 字形，必须装中文字体）。
	# 用 Noto Sans SC（SIL OFL 1.1，许可证随包见 assets/fonts/OFL.txt）。
	# 不可用 SimHei / 微软雅黑等系统商业字体：其授权不含随软件再分发。见 CREDITS.md R-1。
	# 主题由样式工厂单源生成（发射器 a；与 shell 共享同一实例）。
	self.theme = UiStyle.build_theme(DARK, S)

	_build_top_bar()
	_build_hint()
	_build_mode_col()
	_build_skill_btn()
	_build_banner()
	_build_floats()
	set_mode(mode)
	_reset_caches()
	_layout()


# ---------------- 构建 ----------------

func _flat(bg: Color, border: Color, radius: int, border_w: int = 1) -> StyleBoxFlat:
	return UiStyle.flat(bg, border, radius, border_w) # 委托样式工厂（唯一真源 ui_style.gd）


func _style_button(b: Button, w: float, h: float, fs: float) -> void:
	b.custom_minimum_size = Vector2(w, h)
	b.size = Vector2(w, h)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", int(fs))
	var st := UiStyle.button_states(DARK, false) # 四态+字色全由工厂派生
	b.add_theme_color_override("font_color", st["font_color"])
	b.add_theme_color_override("font_hover_color", st["font_hover_color"])
	b.add_theme_color_override("font_pressed_color", st["font_pressed_color"])
	b.add_theme_color_override("font_disabled_color", st["font_disabled_color"])
	b.add_theme_stylebox_override("normal", st["normal"])
	b.add_theme_stylebox_override("hover", st["hover"])
	b.add_theme_stylebox_override("pressed", st["pressed"])
	b.add_theme_stylebox_override("disabled", st["disabled"])
	b.set_meta("sb_normal", st["normal"])
	UiStyle.edge_dress(b, DARK["edge_hi"], UiStyle.RULE) # A1 光边


func _make_label(text: String, fs: float, color: Color, glow: bool = false) -> Label:
	return UiStyle.label(text, fs, color, null, false, glow)


func _build_top_bar() -> void:
	top_bar = Panel.new()
	top_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb_bar := _flat(DARK["bar"], DARK["gold_lo"], 0, 1)
	sb_bar.set_border_width_all(0)
	sb_bar.border_width_bottom = 1 # 底缘 1px 古金线（文明 6 式分组界）
	top_bar.add_theme_stylebox_override("panel", sb_bar)
	add_child(top_bar)
	_toplevel.append(top_bar)

	var sep1 := _make_label("核心", 12.0 * S, DARK["muted"])
	sep1.name = "lbl_core"
	top_bar.add_child(sep1)
	var sep2 := _make_label("波次", 12.0 * S, DARK["muted"])
	sep2.name = "lbl_wave"
	top_bar.add_child(sep2)

	hp_bar = ProgressBar.new()
	hp_bar.custom_minimum_size = Vector2(210.0 * S, 13.0 * S)
	hp_bar.size = Vector2(210.0 * S, 13.0 * S)
	hp_bar.max_value = float(CORE_HP)
	hp_bar.value = float(CORE_HP)
	hp_bar.show_percentage = false
	hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_bar.add_theme_stylebox_override("background", _flat(DARK["track"], DARK["gold_lo"], 2, 1))
	hp_bar.add_theme_stylebox_override("fill", _flat(DARK["hp"], UiStyle.NO_BORDER, 2, 0))
	# 25/50/75% 三道刻度线（纯装饰，随条缩放）
	for frac in [0.25, 0.5, 0.75]:
		var tick := ColorRect.new()
		tick.color = UiStyle.SHADOW_TICK
		tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tick.anchor_left = frac
		tick.anchor_right = frac
		tick.anchor_top = 0.0
		tick.anchor_bottom = 1.0
		tick.offset_left = 0.0
		tick.offset_right = 1.0
		hp_bar.add_child(tick)
	top_bar.add_child(hp_bar)

	hp_text = _make_label("%d/%d" % [CORE_HP, CORE_HP], 11.0 * S, DARK["text"])
	top_bar.add_child(hp_text)

	var divider := ColorRect.new()
	divider.color = DARK["border"]
	divider.custom_minimum_size = Vector2(1, 26.0 * S)
	divider.size = Vector2(1, 26.0 * S)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	divider.name = "divider"
	top_bar.add_child(divider)

	wave_text = _make_label("准备中", 11.0 * S, DARK["text"])
	top_bar.add_child(wave_text)

	supply_text = _make_label("供给 %d" % Sim.START_SUPPLY, 15.0 * S, DARK["supply"], true)
	top_bar.add_child(supply_text)

	heat_btn = Button.new()
	heat_btn.text = "热层"
	_style_button(heat_btn, 56.0 * S, 30.0 * S, 11.0 * S)
	heat_btn.pressed.connect(func() -> void:
		if callbacks.has("on_heat"):
			callbacks["on_heat"].call())
	top_bar.add_child(heat_btn)

	pause_btn = Button.new()
	pause_btn.text = "暂停"
	_style_button(pause_btn, 56.0 * S, 30.0 * S, 11.0 * S)
	pause_btn.pressed.connect(func() -> void:
		if callbacks.has("on_pause"):
			callbacks["on_pause"].call())
	top_bar.add_child(pause_btn)


func _build_hint() -> void:
	hint_panel = PanelContainer.new()
	hint_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	hint_panel.add_theme_stylebox_override("panel", _flat(DARK["card"], DARK["gold_lo"], 2, 1))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", int(8 * S))
	margin.add_theme_constant_override("margin_right", int(8 * S))
	margin.add_theme_constant_override("margin_top", int(8 * S))
	margin.add_theme_constant_override("margin_bottom", int(8 * S))
	hint_label = _make_label(HINT_TEXT, 9.0 * S, DARK["muted"])
	margin.add_child(hint_label)
	hint_panel.add_child(margin)
	add_child(hint_panel)
	_toplevel.append(hint_panel)


func _build_mode_col() -> void:
	mode_buttons = {}
	for m in MODE_LABELS:
		var btn := Button.new()
		btn.text = str(m["label"])
		_style_button(btn, COL_W * S, BTN_H * S, 11.0 * S)
		var key: String = m["key"]
		btn.pressed.connect(func() -> void:
			if callbacks.has("on_mode"):
				callbacks["on_mode"].call(key))
		add_child(btn)
		mode_buttons[key] = btn
		_toplevel.append(btn)


func _build_skill_btn() -> void:
	skill_btn = Button.new()
	skill_btn.text = "震荡波"
	_style_button(skill_btn, COL_W * S, BTN_H * S, 11.0 * S)
	skill_btn.pressed.connect(func() -> void:
		if callbacks.has("on_skill"):
			callbacks["on_skill"].call())
	add_child(skill_btn)
	_toplevel.append(skill_btn)


func _build_banner() -> void:
	banner_root = Control.new()
	banner_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_root.visible = false
	add_child(banner_root)
	_toplevel.append(banner_root)

	banner_card = PanelContainer.new()
	banner_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb_ban := _flat(DARK["card"], DARK["gold_lo"], 2, 1)
	sb_ban.border_width_left = 4 # 左侧 4px 金条强调（v2.1 组件规格）
	banner_card.add_theme_stylebox_override("panel", sb_ban)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", int(14 * S))
	margin.add_theme_constant_override("margin_right", int(14 * S))
	margin.add_theme_constant_override("margin_top", int(12 * S))
	margin.add_theme_constant_override("margin_bottom", int(12 * S))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", int(4 * S))
	banner_title = _make_label("", 20.0 * S, DARK["gold_hi"], true)
	banner_sub = _make_label("", 11.0 * S, DARK["muted"])
	col.add_child(banner_title)
	col.add_child(banner_sub)
	margin.add_child(col)
	banner_card.add_child(margin)
	banner_root.add_child(banner_card)


func _build_floats() -> void:
	floats = []
	for _i in FLOAT_N:
		var el := _make_label("", 13.0 * S, DARK["gold_hi"], true)
		el.visible = false
		add_child(el)
		floats.append({ "el": el, "active": false, "sx": 0.0, "sy": 0.0, "born": 0 })


# ---------------- 布局（绝对像素，S 缩放） ----------------

## 探针入口：注入安全区内边距（逻辑像素）；传 Vector4(-1,-1,-1,-1) 恢复平台自动。
func set_safe_insets_override(v: Vector4) -> void:
	_safe_override = v
	_layout()


## 安全区内边距（逻辑像素，canvas_items 拉伸下的可视 rect 坐标系）。
## Android 取显示器安全区（刘海/挖孔/手势条）换算；其余平台恒 0，不打扰桌面。
func _compute_safe() -> Vector4:
	if _safe_override.x >= 0.0:
		return _safe_override
	if OS.get_name() != "Android":
		return Vector4.ZERO
	var scr := DisplayServer.screen_get_size()
	var vp := get_viewport().get_visible_rect().size
	var wpx := get_window().size.x
	if scr.x <= 0 or scr.y <= 0 or vp.x <= 0.0 or wpx <= 0:
		return Vector4.ZERO
	var sa := DisplayServer.get_display_safe_area()
	var sc := float(wpx) / vp.x # 物理→逻辑（等比例拉伸）
	var l := maxf(float(sa.position.x), 0.0) / sc
	var t := maxf(float(sa.position.y), 0.0) / sc
	var r := maxf(float(scr.x - sa.position.x - sa.size.x), 0.0) / sc
	var b := maxf(float(scr.y - sa.position.y - sa.size.y), 0.0) / sc
	return Vector4(l, t, r, b)


## 重排所有控件（窗口尺寸变化时调用；绝对像素布局）。S 在此重算，
## 保证布局与 hit_regions() 始终跟随当前视口（build() 里的初值只服务构造）。
func _layout() -> void:
	if top_bar == null:
		return
	var win := get_viewport().get_visible_rect().size
	S = clampf(win.y / 816.0, 1.0, 1.6)
	safe = _compute_safe()
	var x0 := safe.x
	var x1 := win.x - safe.z
	var y0 := safe.y
	var y1 := win.y - safe.w
	# 顶栏
	top_bar.position = Vector2(x0, y0)
	top_bar.size = Vector2(x1 - x0, TOP_H * S)
	var row_h := TOP_H * S
	var gap := 18.0 * S
	var x := x0 + 20.0 * S
	var lbl_core: Label = top_bar.get_node("lbl_core")
	var lbl_wave: Label = top_bar.get_node("lbl_wave")
	var divider: ColorRect = top_bar.get_node("divider")
	for c in [lbl_core, hp_bar, hp_text, divider, lbl_wave, wave_text]:
		var ctl: Control = c
		ctl.reset_size()
		ctl.position = Vector2(x, (row_h - ctl.size.y) / 2.0)
		x += ctl.size.x + gap
	# 供给 + 两钮右对齐（右起：暂停钮、热层钮、供给）
	var right := x1 - 20.0 * S
	pause_btn.reset_size()
	pause_btn.position = Vector2(right - pause_btn.size.x, (row_h - pause_btn.size.y) / 2.0)
	right -= pause_btn.size.x + 8.0 * S
	heat_btn.reset_size()
	heat_btn.position = Vector2(right - heat_btn.size.x, (row_h - heat_btn.size.y) / 2.0)
	right -= heat_btn.size.x + gap
	supply_text.reset_size()
	supply_text.position = Vector2(right - supply_text.size.x, (row_h - supply_text.size.y) / 2.0)

	# 提示徽章（左上，top 64*S 锚定）
	hint_panel.reset_size()
	hint_panel.position = Vector2(x0 + 16.0 * S, y0 + 64.0 * S)

	# 模式列（右下角，从下往上排）
	var col_w := COL_W * S
	var btn_h := BTN_H * S
	var btn_gap := BTN_GAP * S
	var bx := x1 - (EDGE + COL_W) * S
	for i in MODE_LABELS.size():
		var key: String = MODE_LABELS[i]["key"]
		var btn: Button = mode_buttons[key]
		var by := y1 - (EDGE + CORNER_N * (BTN_H + BTN_GAP) - BTN_GAP) * S + i * (btn_h + btn_gap)
		btn.position = Vector2(bx, by)

	# 技能钮（模式列上方：底边距底 = EDGE + CORNER_N*(BTN_H+BTN_GAP)，按钮高 42）
	var skill_y := y1 - (EDGE + CORNER_N * (BTN_H + BTN_GAP) + BTN_H) * S
	skill_btn.position = Vector2(bx, skill_y)

	# 横幅（顶部居中）
	banner_card.reset_size()
	var by2 := y0 + 110.0 * S
	banner_card.position = Vector2((x0 + x1 - banner_card.size.x) / 2.0, by2)


# ---------------- 命中区（main 点击排除的唯一来源） ----------------

func hit_regions() -> Array:
	var win := get_viewport().get_visible_rect().size
	safe = _compute_safe()
	var x0 := safe.x
	var x1 := win.x - safe.z
	var y0 := safe.y
	var y1 := win.y - safe.w
	var regions: Array = [
		Rect2(x0, y0, x1 - x0, floorf(TOP_STRIP_H * S)),
		Rect2(x1 - floorf(CORNER_W * S), y1 - floorf(CORNER_H * S), floorf(CORNER_W * S), floorf(CORNER_H * S)),
	]
	# 提示徽章宽度按字数估算（CJK 全角 ≈ 字号），略宽无害
	var chars := HINT_TEXT.length()
	var hw := floorf((16.0 + 8.0 + chars * 9.0 + 8.0) * S)
	regions.append(Rect2(x0, y0 + floorf(64.0 * S), hw, floorf(36.0 * S)))
	return regions


# ---------------- 状态更新 ----------------

## HUD 整体显隐（标题/结算时藏，暂停时留）。同时熄灭飞行中的浮字。
func set_visible_hud(vis: bool) -> void:
	for el in _toplevel:
		var c: Control = el
		c.visible = vis
	if not vis:
		for f in floats:
			f["active"] = false
			var el2: Label = f["el"]
			el2.visible = false


func set_mode(m: String) -> void:
	mode = m
	for key in mode_buttons:
		var btn: Button = mode_buttons[key]
		var on: bool = key == m
		var sb: StyleBoxFlat = btn.get_meta("sb_normal")
		sb.bg_color = DARK["active"] if on else DARK["btn"]
		sb.border_color = DARK["active_border"] if on else DARK["border"]
		var fc: Color = DARK["on_gold"] if on else DARK["text"]
		btn.add_theme_color_override("font_color", fc)
		btn.add_theme_color_override("font_hover_color", fc)
		btn.add_theme_color_override("font_pressed_color", fc)


## 热层钮点亮态（TAB / 按钮两种入口共用）。
func set_heat_vis(on: bool) -> void:
	var sb: StyleBoxFlat = heat_btn.get_meta("sb_normal")
	sb.bg_color = DARK["active"] if on else DARK["btn"]
	sb.border_color = DARK["active_border"] if on else DARK["border"]
	var fc: Color = DARK["on_gold"] if on else DARK["text"]
	heat_btn.add_theme_color_override("font_color", fc)
	heat_btn.add_theme_color_override("font_hover_color", fc)
	heat_btn.add_theme_color_override("font_pressed_color", fc)


## 击杀赏金浮字（view 在击杀时调）：池轮转，update 里按 tick 上浮淡出。
func float_bounty(sx: float, sy: float, text: String) -> void:
	for f in floats:
		if not f["active"]:
			f["active"] = true
			f["sx"] = sx
			f["sy"] = sy
			f["born"] = _tick
			var el: Label = f["el"]
			el.text = text
			el.visible = true
			return


## 更新浮字（按 tick 上浮淡出）
func _update_floats(tick: int) -> void:
	for f in floats:
		if f["active"]:
			var age := tick - int(f["born"])
			var el: Label = f["el"]
			if age >= FLOAT_LIFE:
				f["active"] = false
				el.visible = false
			else:
				var a := 1.0 - float(age) / float(FLOAT_LIFE)
				el.position = Vector2(float(f["sx"]) - 14.0, float(f["sy"]) - 18.0 - float(age) * FLOAT_RISE)
				el.add_theme_color_override("font_color", Color(DARK["gold_hi"].r, DARK["gold_hi"].g, DARK["gold_hi"].b, a))


## 事件横幅（波次 / 暗门）：入场动画 + tick 驻留，update 到点熄灭。
func banner(title: String, sub: String, danger: bool = false) -> void:
	if banner_root == null:
		return
	banner_title.text = title
	banner_title.add_theme_color_override("font_color", DARK["danger"] if danger else DARK["gold_hi"])
	banner_sub.text = sub
	var sb: StyleBoxFlat = banner_card.get_theme_stylebox("panel")
	sb.border_color = DARK["danger"] if danger else DARK["active_border"]
	banner_root.visible = true
	var base_y := banner_card.position.y
	banner_card.modulate = UiStyle.CLEAR
	banner_card.position.y = base_y - 14.0 * S
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	_banner_tween = create_tween()
	_banner_tween.set_parallel(true)
	_banner_tween.tween_property(banner_card, "modulate:a", 1.0, 0.22)
	_banner_tween.tween_property(banner_card, "position:y", base_y, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_banner_until = _tick + BANNER_LIFE


## tick → "分:秒" 文本
func _fmt_time(ticks: int) -> String:
	var s := maxi(0, ceili(float(ticks) / 20.0))
	return "%d:%02d" % [s / 60, s % 60]


## 下一波刷新 tick（null = 波次表已放完）
func _next_wave_tick(world: World, sc: Scenario):
	for w in sc.waves:
		if int(w[0]) > world.tick_count:
			return int(w[0])
	return null


## 横幅内容：波次序号 / 编成 / 是否 Boss 波。
## 口径修正（与母版有意差异）：母版数完整个波次表（且交错序重复计数），第一波会显示
## "第 19 波"；此处取"唯一刷怪 tick ≤ 当前 tick"的真·序号。横幅文本不进指纹，安全。
func _wave_banner_info(sc: Scenario, tick: int) -> Array:
	var ticks := {}
	var parts: Array = []
	var boss := false
	for w in sc.waves:
		var wt := int(w[0])
		if wt == tick:
			parts.append(WAVE_NAMES[int(w[2])] + "×" + str(int(w[3])))
			if int(w[2]) == Sim.E_BEHEMOTH:
				boss = true
		if wt <= tick:
			ticks[wt] = true
	return [ticks.size(), "+".join(parts), boss]


## 波次行文本：下一波倒计时 / 暗门已开 / 最后一波
func _wave_text(world: World, sc: Scenario) -> String:
	var next_w = _next_wave_tick(world, sc)
	if next_w != null:
		var comp: Array = []
		for w2 in sc.waves:
			if int(w2[0]) == int(next_w):
				comp.append(WAVE_NAMES[int(w2[2])] + "×" + str(int(w2[3])))
		var secs := ceili(float(int(next_w) - world.tick_count) / 20.0)
		return "下一波 %ds · %s" % [secs, "+".join(comp)]
	if world.route_opened:
		return "暗门已开 · 终局 " + _fmt_time(sc.end_tick - world.tick_count)
	return "最后一波已出 · 终局 " + _fmt_time(sc.end_tick - world.tick_count)


## 结算统计文案（R6 结算屏复用）。两行排版（v2.1）；探针只断言前缀与「绕行赏金」在文。
func build_stats(world: World) -> String:
	return "坚持 %d:%02d · 击杀 %d · 失墙 %d\n剩余供给 %d · 绕行赏金 +%d" % [
		world.tick_count / 1200,
		(world.tick_count / 20) % 60,
		world.kills,
		world.buildings_lost,
		world.supply,
		world.convoy_earned,
	]


## 每帧更新 HUD：血条 / 波次 / 供给 / 浮字 / 横幅 / 英雄技能冷却
func update(world: World) -> void:
	var sc: Scenario = world.sc
	_tick = world.tick_count
	var hp := maxi(0, int(world.core["hp"]))
	hp_bar.value = float(hp)
	hp_text.text = "%d/%d" % [hp, CORE_HP]

	# 波次行：同 tick 且暗门状态不变才复用缓存
	var ws_key := str(world.tick_count) + "|" + str(world.route_opened)
	if ws_key != _ws_key:
		_ws_key = ws_key
		_ws_text = _wave_text(world, sc)
	wave_text.text = _ws_text

	# 供给跳动：数值变化后 0.25s 内闪白
	if world.supply != _supply:
		_supply = world.supply
		_supply_tick = world.tick_count
	var flash := (world.tick_count - _supply_tick) < 5
	supply_text.text = "供给 %d" % world.supply
	supply_text.add_theme_color_override("font_color", DARK["text"] if flash else DARK["supply"])

	_update_floats(world.tick_count)

	# 波次横幅：上一帧的"下一波 tick"被跨过 = 波次刚刷
	var next_w = _next_wave_tick(world, sc)
	var prev = _next_w
	if prev != null and world.tick_count >= int(prev):
		var info := _wave_banner_info(sc, int(prev))
		if bool(info[2]) and not _behemoth_intro:
			_behemoth_intro = true
			banner("新敌人 · 蛮兽", "皮糙、啃墙狠——别让它贴着核心打", true)
		else:
			var suffix := " · 终波" if next_w == null else ""
			banner("第 %d 波%s" % [int(info[0]), suffix], str(info[1]), bool(info[2]))
	_next_w = next_w
	if world.route_opened and not _route_shown:
		_route_shown = true
		banner("暗门已开", "终局倒计时开始", true)
	if _banner_until != null and world.tick_count >= int(_banner_until) and banner_root != null:
		banner_root.visible = false
		_banner_until = null

	var cd := int(world.hero["skill_cd"])
	var shown := (ceili(float(cd) / 20.0) if cd > 0 else 0)
	if shown != _skill_shown:
		_skill_shown = shown
		if cd > 0:
			skill_btn.disabled = true
			skill_btn.text = "冷却 %ds" % shown
		else:
			skill_btn.disabled = false
			skill_btn.text = "震荡波"


## 重置所有状态缓存（新局/回标题时调用）
func _reset_caches() -> void:
	_skill_shown = -1
	_supply = null
	_supply_tick = -99
	_ws_key = ""
	_ws_text = ""
	_next_w = null
	_route_shown = false
	_behemoth_intro = false
	_banner_until = null


## HUD 重置（新局开始时调用：清浮字、横幅、缓存、模式按钮）
func reset() -> void:
	_reset_caches()
	if _toplevel.size() > 0 and banner_root != null:
		banner_root.visible = false
	for f in floats:
		f["active"] = false
		var el: Label = f["el"]
		el.visible = false
	set_mode(mode)
