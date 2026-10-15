extends Control

# HUD（移植 reroute/scripts/hud.lua）：顶栏（核心血条/波次倒计时/供给/热层钮/暂停钮）
# + 右下操作模式列 + 技能钮 + 波次横幅 + 击杀赏金浮字池。
# 纯展示层：只读模拟状态；按钮回调由 main 注入。布局为绝对像素（S 缩放口径同母版），
# 窗口尺寸变化时 _layout() 重排；hit_regions() 是点击排除的唯一来源（main 消费）。

var S := 1.0

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

# 暗色板（Style.dark 迁移，数值同母版）
var DARK := {
	"bar": Color8(15, 19, 29, 216),
	"card": Color8(18, 23, 34, 244),
	"text": Color8(235, 239, 247, 255),
	"muted": Color8(148, 158, 176, 255),
	"hp": Color8(82, 200, 160, 255),
	"supply": Color8(232, 178, 84, 255),
	"danger": Color8(232, 96, 84, 255),
	"border": Color8(62, 70, 88, 255),
	"active": Color8(85, 105, 232, 255),
	"active_border": Color8(130, 148, 240, 255),
	"btn": Color8(30, 36, 50, 230),
	"btn_hover": Color8(44, 52, 72, 230),
	"btn_pressed": Color8(56, 66, 92, 230),
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

	# 字体主题（Godot 默认字体无 CJK 字形，必须装中文字体）
	# 用 Noto Sans SC（SIL OFL 1.1，许可证随包见 assets/fonts/OFL.txt）。
	# 不可用 SimHei / 微软雅黑等系统商业字体：其授权不含随软件再分发。见 CREDITS.md R-1。
	var theme := Theme.new()
	var font: FontFile = load("res://assets/fonts/NotoSansSC-Regular.otf")
	theme.default_font = font
	theme.default_font_size = int(11 * S)
	self.theme = theme

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
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	return sb


func _style_button(b: Button, w: float, h: float, fs: float) -> void:
	b.custom_minimum_size = Vector2(w, h)
	b.size = Vector2(w, h)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", int(fs))
	b.add_theme_color_override("font_color", DARK["text"])
	b.add_theme_color_override("font_hover_color", DARK["text"])
	b.add_theme_color_override("font_pressed_color", DARK["text"])
	b.add_theme_color_override("font_disabled_color", DARK["muted"])
	var sb_n := _flat(DARK["btn"], DARK["border"], 9)
	var sb_h := _flat(DARK["btn_hover"], DARK["border"], 9)
	var sb_p := _flat(DARK["btn_pressed"], DARK["border"], 9)
	b.add_theme_stylebox_override("normal", sb_n)
	b.add_theme_stylebox_override("hover", sb_h)
	b.add_theme_stylebox_override("pressed", sb_p)
	b.add_theme_stylebox_override("disabled", _flat(DARK["btn"], DARK["border"], 9))
	b.set_meta("sb_normal", sb_n)


func _make_label(text: String, fs: float, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", int(fs))
	l.add_theme_color_override("font_color", color)
	return l


func _build_top_bar() -> void:
	top_bar = Panel.new()
	top_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	top_bar.add_theme_stylebox_override("panel", _flat(DARK["bar"], Color(0, 0, 0, 0), 0, 0))
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
	hp_bar.add_theme_stylebox_override("background", _flat(Color(0, 0, 0, 90), Color(0, 0, 0, 0), 5, 0))
	hp_bar.add_theme_stylebox_override("fill", _flat(DARK["hp"], Color(0, 0, 0, 0), 5, 0))
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

	supply_text = _make_label("供给 %d" % Sim.START_SUPPLY, 15.0 * S, DARK["supply"])
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
	hint_panel.add_theme_stylebox_override("panel", _flat(Color8(16, 18, 24, 200), Color(0, 0, 0, 0), 8, 0))
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
	banner_card.add_theme_stylebox_override("panel", _flat(DARK["card"], DARK["active_border"], 12))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", int(14 * S))
	margin.add_theme_constant_override("margin_right", int(14 * S))
	margin.add_theme_constant_override("margin_top", int(14 * S))
	margin.add_theme_constant_override("margin_bottom", int(14 * S))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", int(4 * S))
	banner_title = _make_label("", 17.0 * S, DARK["text"])
	banner_sub = _make_label("", 11.0 * S, DARK["muted"])
	col.add_child(banner_title)
	col.add_child(banner_sub)
	margin.add_child(col)
	banner_card.add_child(margin)
	banner_root.add_child(banner_card)


func _build_floats() -> void:
	floats = []
	for _i in FLOAT_N:
		var el := _make_label("", 13.0 * S, DARK["supply"])
		el.visible = false
		add_child(el)
		floats.append({ "el": el, "active": false, "sx": 0.0, "sy": 0.0, "born": 0 })


# ---------------- 布局（绝对像素，S 缩放） ----------------

func _layout() -> void:
	if top_bar == null:
		return
	var win := get_viewport().get_visible_rect().size
	# 顶栏
	top_bar.position = Vector2.ZERO
	top_bar.size = Vector2(win.x, TOP_H * S)
	var row_h := TOP_H * S
	var gap := 18.0 * S
	var x := 20.0 * S
	var lbl_core: Label = top_bar.get_node("lbl_core")
	var lbl_wave: Label = top_bar.get_node("lbl_wave")
	var divider: ColorRect = top_bar.get_node("divider")
	for c in [lbl_core, hp_bar, hp_text, divider, lbl_wave, wave_text]:
		var ctl: Control = c
		ctl.reset_size()
		ctl.position = Vector2(x, (row_h - ctl.size.y) / 2.0)
		x += ctl.size.x + gap
	# 供给 + 两钮右对齐（右起：暂停钮、热层钮、供给）
	var right := win.x - 20.0 * S
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
	hint_panel.position = Vector2(16.0 * S, 64.0 * S)

	# 模式列（右下角，从下往上排）
	var col_w := COL_W * S
	var btn_h := BTN_H * S
	var btn_gap := BTN_GAP * S
	var bx := win.x - (EDGE + COL_W) * S
	for i in MODE_LABELS.size():
		var key: String = MODE_LABELS[i]["key"]
		var btn: Button = mode_buttons[key]
		var by := win.y - (EDGE + CORNER_N * (BTN_H + BTN_GAP) - BTN_GAP) * S + i * (btn_h + btn_gap)
		btn.position = Vector2(bx, by)

	# 技能钮（模式列上方：底边距底 = EDGE + CORNER_N*(BTN_H+BTN_GAP)，按钮高 42）
	var skill_y := win.y - (EDGE + CORNER_N * (BTN_H + BTN_GAP) + BTN_H) * S
	skill_btn.position = Vector2(bx, skill_y)

	# 横幅（顶部居中）
	banner_card.reset_size()
	var by2 := 110.0 * S
	banner_card.position = Vector2((win.x - banner_card.size.x) / 2.0, by2)


# ---------------- 命中区（main 点击排除的唯一来源） ----------------

func hit_regions() -> Array:
	var win := get_viewport().get_visible_rect().size
	var regions: Array = [
		Rect2(0, 0, win.x, floorf(TOP_STRIP_H * S)),
		Rect2(win.x - floorf(CORNER_W * S), win.y - floorf(CORNER_H * S), floorf(CORNER_W * S), floorf(CORNER_H * S)),
	]
	# 提示徽章宽度按字数估算（CJK 全角 ≈ 字号），略宽无害
	var chars := HINT_TEXT.length()
	var hw := floorf((16.0 + 8.0 + chars * 9.0 + 8.0) * S)
	regions.append(Rect2(0, floorf(64.0 * S), hw, floorf(36.0 * S)))
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
		var sb: StyleBoxFlat = btn.get_meta("sb_normal")
		sb.bg_color = DARK["active"] if key == m else DARK["btn"]
		sb.border_color = DARK["active_border"] if key == m else DARK["border"]


## 热层钮点亮态（TAB / 按钮两种入口共用）。
func set_heat_vis(on: bool) -> void:
	var sb: StyleBoxFlat = heat_btn.get_meta("sb_normal")
	sb.bg_color = DARK["active"] if on else DARK["btn"]
	sb.border_color = DARK["active_border"] if on else DARK["border"]


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
				el.add_theme_color_override("font_color", Color(DARK["supply"].r, DARK["supply"].g, DARK["supply"].b, a))


## 事件横幅（波次 / 暗门）：入场动画 + tick 驻留，update 到点熄灭。
func banner(title: String, sub: String, danger: bool = false) -> void:
	if banner_root == null:
		return
	banner_title.text = title
	banner_title.add_theme_color_override("font_color", DARK["danger"] if danger else DARK["text"])
	banner_sub.text = sub
	var sb: StyleBoxFlat = banner_card.get_theme_stylebox("panel")
	sb.border_color = DARK["danger"] if danger else DARK["active_border"]
	banner_root.visible = true
	var base_y := banner_card.position.y
	banner_card.modulate = Color(1, 1, 1, 0)
	banner_card.position.y = base_y - 14.0 * S
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	_banner_tween = create_tween()
	_banner_tween.set_parallel(true)
	_banner_tween.tween_property(banner_card, "modulate:a", 1.0, 0.22)
	_banner_tween.tween_property(banner_card, "position:y", base_y, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_banner_until = _tick + BANNER_LIFE


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


## 结算统计文案（R6 结算屏复用）。
func build_stats(world: World) -> String:
	return "坚持 %d:%02d · 击杀 %d · 失墙 %d · 剩余供给 %d · 绕行赏金 +%d" % [
		world.tick_count / 1200,
		(world.tick_count / 20) % 60,
		world.kills,
		world.buildings_lost,
		world.supply,
		world.convoy_earned,
	]


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


func reset() -> void:
	_reset_caches()
	if _toplevel.size() > 0 and banner_root != null:
		banner_root.visible = false
	for f in floats:
		f["active"] = false
		var el: Label = f["el"]
		el.visible = false
	set_mode(mode)
