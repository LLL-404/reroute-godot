extends Control

const UiStyle = preload("res://game/ui/ui_style.gd")
const UserSettings = preload("res://game/core/user_settings.gd")

# HUD（移植 reroute/scripts/hud.lua）：顶栏（核心血条/波次倒计时/供给/热层钮/暂停钮）
# + 右下操作模式列 + 技能钮 + 波次横幅 + 击杀赏金浮字池。
# 纯展示层：只读模拟状态；按钮回调由 main 注入。布局为绝对像素（S 缩放口径同母版），
# 窗口尺寸变化时 _layout() 重算 S 并重排；hit_regions() 是点击排除的唯一来源（main 消费）。

var S := 1.0

# 安全区（Android 刘海/挖孔/手势条）：逻辑像素内边距 (左, 上, 右, 下)；桌面恒 0。
# _safe_override 为探针注入口（Vector4(-1,-1,-1,-1) = 恢复平台自动）。
var safe := Vector4.ZERO
var _safe_override := Vector4(-1.0, -1.0, -1.0, -1.0)

# 几何常量：hud 布局与 main 点击排除共用这一份（v2.5 图标指挥盘：3 行 2/3/3 格）
const CELL_W := 72.0      # 格宽
const CELL_H := 68.0      # 格高（图标 22 + 名称 10 + 成本 9）
const CELL_GAP := 8.0     # 同行格距
const ROW_GAP := 10.0     # 行距
const DOCK_PAD := 10.0    # 盘内边距
const DOCK_COLS := 3
const DOCK_W := CELL_W * DOCK_COLS + CELL_GAP * (DOCK_COLS - 1) + DOCK_PAD * 2 # 252
const DOCK_H := CELL_H * 3 + ROW_GAP * 2 + DOCK_PAD * 2 # 244
const DOCK_ROWS := [["wall", "tower"], ["dig", "fill", "lower"], ["skill", "remove", "hero"]]
const EDGE := 16.0
const TOP_H := 56.0
const TOP_STRIP_H := 64.0 # 点击排除条高（56 + 留白）
const HINT_LIFE := 400 # 提示条驻留 tick（20s）后淡出
const FS_NAME := 11.0    # 盘内名称字号（×S；_layout 每帧重设，平板窗口同比例）
const FS_COST := 9.5     # 盘内成本字号
const FS_TOP := 12.0     # 顶栏小标字号
const FS_SEED := 10.5    # 种子标签字号（顶栏下沿右端常驻）
const CORNER_W := EDGE + DOCK_W # 268
const CORNER_H := EDGE + DOCK_H # 260
const FLOAT_N := 10 # 浮字池
const FLOAT_LIFE := 18 # 0.9s（tick）
const FLOAT_RISE := 1.4 # 每 tick 上浮像素
const BANNER_LIFE := 40 # 横幅驻留 2s（tick）

# 帝王金黑色板（v2.1 改版 → v2.3 归位 ui_style.gd）：本处保留 **兼容别名**，
# 探针与历史引用按 hud.DARK[key] 取色零改动；真源 = UiStyle.DARK（样式系统唯一口）。
const DARK := UiStyle.DARK

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
var undo_panel: Button # 撤销 pill（5s 撤销窗内可见；main._update_undo_ui 驱动）
var _undo_on := false # 撤销窗开关的归口状态（set_visible_hud 复显时按此还原）
var dock: Panel
var dock_caps: Array = []
var dock_rows: Array = [] # 3 行控件（2/3/3），_layout 逐格定位
var row_cost: Dictionary = {} # key → 格内成本/冷却 Label（底部居中）
var row_name: Dictionary = {} # key → 格内名称 Label（底部居中）
var row_icon: Dictionary = {} # key → 图标 Control
var supply_caption: Label
var core_icon: Control
var supply_icon: Control
var banner_root: Control
var banner_card: PanelContainer
var banner_title: Label
var banner_sub: Label
var hint_panel: PanelContainer
var hint_label: Label
var seed_label: Label # 当前种子（Task 4：两种模式都可见，故挂在根下而非 top_bar）
var floats: Array = []
var _toplevel: Array = []
var _hint_hidden := false

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
var _hint_tween: Tween = null


## 初始化：全屏铺底、监听窗口变化
func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_viewport().size_changed.connect(_layout)


## 由 main 注入回调并一次性构建：callbacks = { on_mode(m), on_pause(), on_heat(), on_skill() }
func build(cb: Dictionary) -> void:
	callbacks = cb
	var win := get_viewport().get_visible_rect().size
	S = clampf(win.y / 816.0, 1.0, 1.6) * UserSettings.ui_scale
	CORE_HP = int(Sim.BUILDINGS[Sim.B_CORE - 1]["hp"])
	WAVE_NAMES = { Sim.E_SWARM: "虫群", Sim.E_BEHEMOTH: "蛮兽" }
	MODE_LABELS = [
		{ "key": "wall", "label": "墙", "cost": int(Sim.BUILDINGS[Sim.B_WALL - 1]["cost"]) },
		{ "key": "tower", "label": "塔", "cost": int(Sim.BUILDINGS[Sim.B_TOWER - 1]["cost"]) },
		{ "key": "dig", "label": "挖矿", "cost": 0 },
		{ "key": "fill", "label": "填高", "cost": int(Sim.FILL_COST) },
		{ "key": "lower", "label": "挖低", "cost": int(Sim.LOWER_COST) },
		{ "key": "remove", "label": "拆", "cost": 0 },
		{ "key": "hero", "label": "英雄", "cost": 0 },
	]

	# 字体主题（Godot 默认字体无 CJK 字形，必须装中文字体）。
	# 用 Noto Sans SC（SIL OFL 1.1，许可证随包见 assets/fonts/OFL.txt）。
	# 不可用 SimHei / 微软雅黑等系统商业字体：其授权不含随软件再分发。见 CREDITS.md R-1。
	# 主题由样式工厂单源生成（发射器 a；与 shell 共享同一实例）。
	self.theme = UiStyle.build_theme(DARK, S)

	_bind_top_bar()
	_bind_seed()
	_bind_hint()
	_bind_dock()
	_bind_undo()
	_bind_banner()
	_bind_floats()
	set_mode(mode)
	_reset_caches()
	_layout()


# ---------------- 绑定（结构在 hud.tscn，样式/尺寸/信号在此注入） ----------------

## 样式盒快捷构造：委托 ui_style 工厂（唯一真源）
func _flat(bg: Color, border: Color, radius: int, border_w: int = 1) -> StyleBoxFlat:
	return UiStyle.flat(bg, border, radius, border_w) # 委托样式工厂（唯一真源 ui_style.gd）


## 按钮成套样式：尺寸/字体 + HUD 变体接入（发射器 a，v2.3 起不再逐钮 override/meta）+ A1 光边
func _style_button(b: Button, w: float, h: float, fs: float) -> void:
	b.custom_minimum_size = Vector2(w, h)
	b.size = Vector2(w, h)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", int(fs))
	b.theme_type_variation = UiStyle.BTN_HUD_VAR
	UiStyle.edge_dress(b, DARK["edge_hi"], UiStyle.RULE) # A1 光边


## 场景标签样式注入：字号/字色 + glow（A3 金字投影），与 UiStyle.label 运行时口径一致
func _dress_label(l: Label, fs: float, color: Color, glow: bool = false) -> void:
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", int(fs))
	l.add_theme_color_override("font_color", color)
	if glow:
		l.add_theme_color_override("font_shadow_color", UiStyle.GLOW_GOLD)
		l.add_theme_constant_override("shadow_offset_x", 0)
		l.add_theme_constant_override("shadow_offset_y", 1)


## 绑定顶栏：核心血条（三道刻度线）+ 波次 + 供给 + 热层/暂停钮
func _bind_top_bar() -> void:
	top_bar = $TopBar
	var sb_bar := _flat(DARK["bar"], DARK["gold_lo"], 0, 1)
	sb_bar.set_border_width_all(0)
	sb_bar.border_width_bottom = 1 # 底缘 1px 古金线（文明 6 式分组界）
	top_bar.add_theme_stylebox_override("panel", sb_bar)
	_toplevel.append(top_bar)

	core_icon = $TopBar/CoreIcon
	core_icon.setup("shield", DARK["gold"])
	supply_icon = $TopBar/SupplyIcon
	supply_icon.setup("coin", DARK["supply"])

	var lbl_core: Label = $TopBar/CoreCaption
	_dress_label(lbl_core, 11.0 * S, DARK["muted"])
	var lbl_wave: Label = $TopBar/WaveCaption
	_dress_label(lbl_wave, 11.0 * S, DARK["muted"])

	hp_bar = $TopBar/HpBar
	hp_bar.custom_minimum_size = Vector2(180.0 * S, 10.0 * S)
	hp_bar.size = Vector2(180.0 * S, 10.0 * S)
	hp_bar.max_value = float(CORE_HP)
	hp_bar.value = float(CORE_HP)
	hp_bar.show_percentage = false
	hp_bar.add_theme_stylebox_override("background", _flat(DARK["track"], DARK["gold_lo"], 2, 1))
	hp_bar.add_theme_stylebox_override("fill", _flat(DARK["hp"], UiStyle.NO_BORDER, 2, 0))
	# 25/50/75% 三道刻度线（纯装饰，随条缩放）
	var fracs := [0.25, 0.5, 0.75]
	var tick_names := ["Tick25", "Tick50", "Tick75"]
	for i in 3:
		var tick: ColorRect = hp_bar.get_node(tick_names[i])
		tick.color = UiStyle.SHADOW_TICK
		tick.anchor_left = fracs[i]
		tick.anchor_right = fracs[i]
		tick.offset_left = 0.0
		tick.offset_right = 1.0

	hp_text = $TopBar/HpText
	hp_text.text = "%d/%d" % [CORE_HP, CORE_HP]
	_dress_label(hp_text, 12.0 * S, DARK["text"])

	var divider: ColorRect = $TopBar/Divider
	divider.color = DARK["border"]
	divider.custom_minimum_size = Vector2(1, 26.0 * S)
	divider.size = Vector2(1, 26.0 * S)

	wave_text = $TopBar/WaveText
	_dress_label(wave_text, 12.0 * S, DARK["text"])

	supply_caption = $TopBar/SupplyCaption
	_dress_label(supply_caption, 10.0 * S, DARK["muted"])
	supply_text = $TopBar/SupplyText
	_dress_label(supply_text, 17.0 * S, DARK["supply"], true)
	supply_text.text = str(Sim.START_SUPPLY)

	heat_btn = $TopBar/HeatButton
	_style_button(heat_btn, 60.0 * S, 30.0 * S, 11.0 * S)
	heat_btn.pressed.connect(func() -> void:
		if callbacks.has("on_heat"):
			callbacks["on_heat"].call())

	pause_btn = $TopBar/PauseButton
	_style_button(pause_btn, 60.0 * S, 30.0 * S, 11.0 * S)
	pause_btn.pressed.connect(func() -> void:
		if callbacks.has("on_pause"):
			callbacks["on_pause"].call())


## 绑定种子标签（Task 4）：右上角常驻小字；显隐并入 _toplevel，跟随 HUD 整体收起/复显。
## 位置在顶栏下沿（y ≥ TOP_STRIP_H·S）→ 不进 hit_regions，不影响战场点击。
func _bind_seed() -> void:
	seed_label = $SeedLabel
	_dress_label(seed_label, FS_SEED * S, DARK["muted"])
	seed_label.text = ""
	_toplevel.append(seed_label)


## 绑定左上提示徽章（放墙改道提示；点击排除第三区）
func _bind_hint() -> void:
	hint_panel = $HintPanel
	hint_panel.add_theme_stylebox_override("panel", _flat(DARK["card"], DARK["gold_lo"], 2, 1))
	var margin: MarginContainer = $HintPanel/Margin
	margin.add_theme_constant_override("margin_left", int(9 * S))
	margin.add_theme_constant_override("margin_right", int(11 * S))
	margin.add_theme_constant_override("margin_top", int(5 * S))
	margin.add_theme_constant_override("margin_bottom", int(5 * S))
	var row: HBoxContainer = $HintPanel/Margin/Row
	row.add_theme_constant_override("separation", int(8 * S))
	var tag: Label = row.get_node("Tag")
	_dress_label(tag, 9.0 * S, DARK["gold"])
	var sep: ColorRect = row.get_node("Separator")
	sep.color = DARK["gold_lo"]
	sep.custom_minimum_size = Vector2(1, 10)
	sep.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hint_label = row.get_node("HintLabel")
	_dress_label(hint_label, 10.0 * S, DARK["muted"])
	_toplevel.append(hint_panel)


## 绑定右下指挥盘（v2.5）：3 行 2/3/3 格（建造 / 地形 / 指令），格内 = 图标 + 名称 + 成本。
## Button 文本清空，图标/名称/成本均为子节点（随按钮三态由 _paint_rows 统一换色）。
func _bind_dock() -> void:
	dock = $ActionLayer/DockPlate
	dock.add_theme_stylebox_override("panel", _flat(DARK["bar"], DARK["gold_lo"], 3, 1))
	UiStyle.corner_dress(dock, DARK["gold_lo"]) # 四角铜线托角（游戏面板感）
	_toplevel.append(dock)

	mode_buttons = {}
	dock_rows = []
	row_name = {}
	row_cost = {}
	row_icon = {}
	# 每格动态规格：成本取自模拟表、图标键固定（名称文本在场景里）
	var specs := {
		"wall": { "cost": int(Sim.BUILDINGS[Sim.B_WALL - 1]["cost"]), "icon": "wall" },
		"tower": { "cost": int(Sim.BUILDINGS[Sim.B_TOWER - 1]["cost"]), "icon": "tower" },
		"dig": { "cost": 0, "icon": "ore" },
		"fill": { "cost": int(Sim.FILL_COST), "icon": "fill" },
		"lower": { "cost": int(Sim.LOWER_COST), "icon": "lower" },
		"skill": { "cost": 0, "icon": "skill" },
		"remove": { "cost": 0, "icon": "remove" },
		"hero": { "cost": 0, "icon": "hero" },
	}
	for keys in DOCK_ROWS:
		var row: Array = []
		for key in keys:
			var spec: Dictionary = specs[key]
			var btn: Button = get_node("ActionLayer/Btn" + str(key).capitalize())
			_style_button(btn, CELL_W * S, CELL_H * S, 10.0 * S)
			if key == "skill":
				btn.pressed.connect(func() -> void:
					if callbacks.has("on_skill"):
						callbacks["on_skill"].call())
				skill_btn = btn
			else:
				btn.pressed.connect(func() -> void:
					if callbacks.has("on_mode"):
						callbacks["on_mode"].call(key))
				mode_buttons[key] = btn
			_toplevel.append(btn)
			btn.set_meta("cost", int(spec["cost"]))
			btn.set_meta("icon", str(spec["icon"]))
			var ic: Control = btn.get_node("Icon")
			ic.setup(str(spec["icon"]), DARK["text"])
			row_icon[key] = ic
			var name_l: Label = btn.get_node("NameLabel")
			_dress_label(name_l, 10.0 * S, DARK["text"])
			row_name[key] = name_l
			var cost_l: Label = btn.get_node("CostLabel")
			_dress_label(cost_l, 9.0 * S, DARK["muted"])
			if int(spec["cost"]) > 0:
				cost_l.text = str(int(spec["cost"]))
			elif key == "skill":
				cost_l.text = "就绪"
			row_cost[key] = cost_l
			row.append(btn)
		dock_rows.append(row)
	_paint_rows()


## 绑定撤销 pill（v2.5 落地：他会话撤销机制的 HUD 侧）。贴指挥坞上沿的小浮钮，
## 5s 撤销窗内由 main `set_undo_vis(true, 剩余秒)` 点亮；点按走 on_undo 回调
## （与 Ctrl+Z / 右键撤销同源命令链）。默认隐藏：不入 _toplevel（显隐归口见 set_undo_vis）。
func _bind_undo() -> void:
	undo_panel = $ActionLayer/UndoPill
	undo_panel.custom_minimum_size = Vector2(140.0 * S, 30.0 * S)
	undo_panel.size = Vector2(140.0 * S, 30.0 * S)
	undo_panel.focus_mode = Control.FOCUS_NONE
	undo_panel.add_theme_font_size_override("font_size", int(11.5 * S))
	undo_panel.theme_type_variation = UiStyle.BTN_HUD_VAR
	UiStyle.edge_dress(undo_panel, DARK["edge_hi"], UiStyle.RULE) # A1 光边
	undo_panel.pressed.connect(func() -> void:
		if callbacks.has("on_undo"):
			callbacks["on_undo"].call())


## 撤销窗显隐 + 倒计时文案。main 每 tick 传剩余秒（`on` 为 false 时无参调用）；
## `secs` 带默认值兼容单参调用。显隐不归 set_visible_hud 管（见 _undo_on 归口）。
func set_undo_vis(on: bool, secs: int = 0) -> void:
	if undo_panel == null:
		return
	_undo_on = on
	undo_panel.visible = on
	if on:
		undo_panel.text = "撤销 · %d s" % maxi(1, int(secs))


## 绑定波次/暗门横幅（卡片 + 左金条强调 + 标题/副标题两行）
func _bind_banner() -> void:
	banner_root = $BannerRoot
	_toplevel.append(banner_root)

	banner_card = $BannerRoot/Card
	var sb_ban := _flat(DARK["card"], DARK["gold_lo"], 2, 1)
	sb_ban.border_width_left = 4 # 左侧 4px 金条强调（v2.1 组件规格）
	banner_card.add_theme_stylebox_override("panel", sb_ban)
	var margin: MarginContainer = banner_card.get_node("Margin")
	margin.add_theme_constant_override("margin_left", int(12 * S))
	margin.add_theme_constant_override("margin_right", int(14 * S))
	margin.add_theme_constant_override("margin_top", int(7 * S))
	margin.add_theme_constant_override("margin_bottom", int(7 * S))
	var col: VBoxContainer = margin.get_node("Col")
	col.add_theme_constant_override("separation", int(2 * S))
	banner_title = col.get_node("BannerTitle")
	_dress_label(banner_title, 16.0 * S, DARK["gold_hi"], true)
	banner_sub = col.get_node("BannerSub")
	_dress_label(banner_sub, 10.0 * S, DARK["muted"])


## 绑定击杀赏金浮字池（FLOAT_N 个复用 Label，轮转取用）
func _bind_floats() -> void:
	floats = []
	var box: Control = $Floats
	for i in FLOAT_N:
		var el: Label = box.get_node("Float%d" % i)
		_dress_label(el, 13.0 * S, DARK["gold_hi"], true)
		el.visible = false
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


## UI 缩放档应用（设置页滑块实时生效）：写静态倍率 → 重排（S 在 _layout 内重算）→ 主题按新 S 重建。
func apply_ui_scale(pct: int) -> void:
	UserSettings.ui_scale = clampf(float(pct) / 100.0, 0.8, 1.3)
	_layout()
	self.theme = UiStyle.build_theme(DARK, S)


## 重排所有控件（窗口尺寸变化时调用；绝对像素布局）。S 在此重算，
## 保证布局与 hit_regions() 始终跟随当前视口（build() 里的初值只服务构造）。
func _layout() -> void:
	if top_bar == null:
		return
	var win := get_viewport().get_visible_rect().size
	S = clampf(win.y / 816.0, 1.0, 1.6) * UserSettings.ui_scale
	safe = _compute_safe()
	var x0 := safe.x
	var x1 := win.x - safe.z
	var y0 := safe.y
	var y1 := win.y - safe.w
	# 顶栏
	top_bar.position = Vector2(x0, y0)
	top_bar.size = Vector2(x1 - x0, TOP_H * S)
	# v2.5：字号随 S 重算（窗口缩放/平板尺寸下格与字同步，不再出现「大格子小字」）
	for key in row_name:
		row_name[key].add_theme_font_size_override("font_size", int(FS_NAME * S))
		row_cost[key].add_theme_font_size_override("font_size", int(FS_COST * S))
	var row_h := TOP_H * S
	var gap := 18.0 * S
	var x := x0 + 20.0 * S
	core_icon.size = Vector2(14.0 * S, 14.0 * S)
	core_icon.position = Vector2(x, (row_h - 14.0 * S) / 2.0)
	x += 20.0 * S
	hp_bar.custom_minimum_size = Vector2(180.0 * S, 10.0 * S)
	hp_bar.size = Vector2(180.0 * S, 10.0 * S)
	var lbl_core: Label = top_bar.get_node("CoreCaption")
	var lbl_wave: Label = top_bar.get_node("WaveCaption")
	var divider: ColorRect = top_bar.get_node("Divider")
	lbl_core.add_theme_font_size_override("font_size", int(FS_TOP * S))
	lbl_wave.add_theme_font_size_override("font_size", int(FS_TOP * S))
	hp_text.add_theme_font_size_override("font_size", int(12.5 * S))
	wave_text.add_theme_font_size_override("font_size", int(12.0 * S))
	supply_caption.add_theme_font_size_override("font_size", int(10.5 * S))
	supply_text.add_theme_font_size_override("font_size", int(18.0 * S))
	heat_btn.add_theme_font_size_override("font_size", int(11.5 * S))
	pause_btn.add_theme_font_size_override("font_size", int(11.5 * S))
	hint_label.add_theme_font_size_override("font_size", int(10.5 * S))
	banner_title.add_theme_font_size_override("font_size", int(16.0 * S))
	banner_sub.add_theme_font_size_override("font_size", int(10.5 * S))
	for c in [lbl_core, hp_bar, hp_text, divider, lbl_wave, wave_text]:
		var ctl: Control = c
		ctl.reset_size()
		ctl.position = Vector2(x, (row_h - ctl.size.y) / 2.0)
		x += ctl.size.x + gap
	# 右簇：供给（小标 + 铜钱图标 + 大数值）+ 热层/暂停
	var right := x1 - 20.0 * S
	pause_btn.custom_minimum_size = Vector2(60.0 * S, 30.0 * S)
	pause_btn.size = Vector2(60.0 * S, 30.0 * S)
	pause_btn.position = Vector2(right - pause_btn.size.x, (row_h - pause_btn.size.y) / 2.0)
	right -= pause_btn.size.x + 8.0 * S
	heat_btn.custom_minimum_size = Vector2(60.0 * S, 30.0 * S)
	heat_btn.size = Vector2(60.0 * S, 30.0 * S)
	heat_btn.position = Vector2(right - heat_btn.size.x, (row_h - heat_btn.size.y) / 2.0)
	right -= heat_btn.size.x + gap
	supply_text.reset_size()
	supply_text.position = Vector2(right - supply_text.size.x, (row_h - supply_text.size.y) / 2.0)
	right -= supply_text.size.x + 5.0 * S
	supply_icon.size = Vector2(13.0 * S, 13.0 * S)
	supply_icon.position = Vector2(right - 13.0 * S, (row_h - 13.0 * S) / 2.0)
	right -= 13.0 * S + 5.0 * S
	supply_caption.reset_size()
	supply_caption.position = Vector2(right - supply_caption.size.x, (row_h - supply_caption.size.y) / 2.0)

	# 提示徽章（左上，top 64*S 锚定；超时淡出后隐藏）
	hint_panel.reset_size()
	hint_panel.position = Vector2(x0 + 16.0 * S, y0 + 64.0 * S)
	_place_seed() # 种子标签（右上，顶栏下沿；不进点击排除区）

	# 指挥盘（右下角）：3 行 2/3/3 格，逐格定位图标/名称/成本
	dock.position = Vector2(x1 - (EDGE + DOCK_W) * S, y1 - (EDGE + DOCK_H) * S)
	dock.size = Vector2(DOCK_W * S, DOCK_H * S)
	var content_w := DOCK_W - DOCK_PAD * 2.0
	for r in dock_rows.size():
		var row: Array = dock_rows[r]
		var row_w := row.size() * CELL_W + (row.size() - 1) * CELL_GAP
		var rx := dock.position.x + (DOCK_PAD + (content_w - row_w) * 0.5) * S
		var ry := dock.position.y + (DOCK_PAD + r * (CELL_H + ROW_GAP)) * S
		for i in row.size():
			var b: Button = row[i]
			b.custom_minimum_size = Vector2(CELL_W * S, CELL_H * S)
			b.size = b.custom_minimum_size
			b.position = Vector2(rx + i * (CELL_W + CELL_GAP) * S, ry)
			var key := str(DOCK_ROWS[r][i])
			var ic: Control = row_icon[key]
			ic.size = Vector2(24.0 * S, 24.0 * S)
			ic.position = Vector2((CELL_W * S - ic.size.x) * 0.5, 7.0 * S)
			var nl: Label = row_name[key]
			nl.reset_size()
			nl.position = Vector2((CELL_W * S - nl.size.x) * 0.5, 32.0 * S)
			var cl: Label = row_cost[key]
			cl.reset_size()
			cl.position = Vector2((CELL_W * S - cl.size.x) * 0.5, 47.0 * S)

	# 撤销 pill：浮在指挥坞上沿居中（仅撤销窗内可见；隐藏时也保持定位防 resize 漂移）
	if undo_panel != null:
		var uw := 140.0 * S
		undo_panel.custom_minimum_size = Vector2(uw, 30.0 * S)
		undo_panel.size = undo_panel.custom_minimum_size
		undo_panel.add_theme_font_size_override("font_size", int(11.5 * S))
		undo_panel.position = Vector2(dock.position.x + (DOCK_W * S - uw) * 0.5, dock.position.y - 36.0 * S)

	# 横幅（顶部居中，v2.4 瘦身）
	banner_card.reset_size()
	banner_card.position = Vector2((x0 + x1 - banner_card.size.x) / 2.0, y0 + 96.0 * S)


## 显示当前种子（经典/肉鸽两种模式通用；读档后由 main 传存档种子）。
func set_seed(seed: int) -> void:
	if seed_label == null:
		return
	seed_label.text = "种子 %d" % seed
	_place_seed()


## 种子标签定位（_layout / set_seed 共用）：顶栏下沿右端，宽度随文字自适应。
## y 从 TOP_STRIP_H·S 起 → 不落在点击排除条内（战场点击不受影响）。
func _place_seed() -> void:
	if seed_label == null:
		return
	var win := get_viewport().get_visible_rect().size
	seed_label.add_theme_font_size_override("font_size", int(FS_SEED * S))
	seed_label.reset_size()
	seed_label.position = Vector2(win.x - safe.z - 16.0 * S - seed_label.size.x, safe.y + TOP_STRIP_H * S + 2.0 * S)


# ---------------- 命中区（main 点击排除的唯一来源） ----------------


## 点击排除区（唯一来源）：顶栏条 / 右下角钮区 / 提示徽章三块
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
	# 提示徽章（可见时才占点击排除区；超时淡出后自动让位给战场）
	if hint_panel != null and hint_panel.visible:
		regions.append(Rect2(hint_panel.position, hint_panel.size))
	return regions


# ---------------- 状态更新 ----------------

## HUD 整体显隐（标题/结算时藏，暂停时留）。同时熄灭飞行中的浮字。
## 横幅自管显隐：整层复显不得误亮「空横幅」（否则新局 tick 0 会驻留一张空卡片——2026-10-19 修复）。
func set_visible_hud(vis: bool) -> void:
	for el in _toplevel:
		if el == banner_root:
			continue
		var c: Control = el
		c.visible = vis
	if banner_root != null:
		banner_root.visible = vis and _banner_until != null
	if undo_panel != null: # 撤销 pill：显隐归口 = _undo_on（整层隐藏时不得复显）
		undo_panel.visible = vis and _undo_on
	if not vis:
		for f in floats:
			f["active"] = false
			var el2: Label = f["el"]
			el2.visible = false


## 切换操作模式：点亮对应钮（HUD 变体切换；行内名称/成本同步换色）
func set_mode(m: String) -> void:
	mode = m
	for key in mode_buttons:
		var btn: Button = mode_buttons[key]
		var on: bool = key == m
		btn.theme_type_variation = UiStyle.BTN_HUD_ACTIVE_VAR if on else UiStyle.BTN_HUD_VAR
	_paint_rows()


## 行配色：选中 = 金底深字；常态 = 字色 text + 成本 muted（供给不足时由 update 改红）。
func _paint_rows() -> void:
	for key in mode_buttons:
		var on: bool = key == mode
		var nl: Label = row_name[key]
		var cl: Label = row_cost[key]
		nl.add_theme_color_override("font_color", DARK["on_gold"] if on else DARK["text"])
		if cl.text != "":
			cl.add_theme_color_override("font_color", DARK["on_gold"] if on else DARK["muted"])
		row_icon[key].setup(str(mode_buttons[key].get_meta("icon")), DARK["on_gold"] if on else DARK["text"])


## 成本可负担性：供给不足 → 红字；可负担 → 随行态（点亮深字 / 常态 muted）。
func _update_affordability(supply: int) -> void:
	for key in mode_buttons:
		var cost := int(mode_buttons[key].get_meta("cost"))
		if cost <= 0:
			continue
		var cl: Label = row_cost[key]
		var on: bool = key == mode
		if supply < cost:
			cl.add_theme_color_override("font_color", DARK["danger"])
		else:
			cl.add_theme_color_override("font_color", DARK["on_gold"] if on else DARK["muted"])


## 技能行配色：冷却禁用 → 名/图标 muted；就绪 → text + 金色「就绪」。
func _paint_skill() -> void:
	var ready := not skill_btn.disabled
	row_name["skill"].add_theme_color_override("font_color", DARK["text"] if ready else DARK["muted"])
	row_cost["skill"].add_theme_color_override("font_color", DARK["supply"] if ready else DARK["muted"])
	row_icon["skill"].setup("skill", DARK["text"] if ready else DARK["muted"])


## 墙钮动态文案（2026-10-25 刀②阶梯价；main 在建/拆成功后驱动，hud 不读世界）：
## -1 = 上限封盘「墙满」；n ≥ 0 =「墙×n」。只改 wall 格的 name/cost 文本与可负担性 meta。
func set_wall_price(price: int) -> void:
	if not mode_buttons.has("wall"):
		return
	var nl: Label = row_name["wall"]
	var cl: Label = row_cost["wall"]
	if price < 0:
		nl.text = "墙满"
		cl.text = ""
		mode_buttons["wall"].set_meta("cost", 1 << 30) # 永不可负担（灰）
	else:
		nl.text = "墙"
		cl.text = str(price)
		mode_buttons["wall"].set_meta("cost", price)
	nl.reset_size()
	cl.reset_size()
	nl.position = Vector2((CELL_W * S - nl.size.x) * 0.5, 32.0 * S)
	cl.position = Vector2((CELL_W * S - cl.size.x) * 0.5, 47.0 * S)


## 教学提示条：驻留 HINT_LIFE tick（20s）后淡出，只触发一次；reset() 恢复。
func _update_hint(tick: int) -> void:
	if _hint_hidden or hint_panel == null or tick < HINT_LIFE:
		return
	_hint_hidden = true
	var tw := create_tween()
	tw.tween_property(hint_panel, "modulate:a", 0.0, 0.5)
	tw.tween_callback(func() -> void:
		hint_panel.visible = false)


## 手动收起教学提示（打开存档/设置等模态页时调用；与 20s 自动淡出同一状态，不再复现）。
func dismiss_hint() -> void:
	if _hint_hidden or hint_panel == null:
		return
	_hint_hidden = true
	hint_panel.visible = false


## 一次性提示（种子顺延等）：复用提示徽章面板，3s 后自动淡出。
## 不动 _hint_hidden（教学提示的 20s 计时照旧，互不抢状态）。
func hint(text: String) -> void:
	if hint_panel == null or hint_label == null:
		return
	hint_label.text = text
	hint_panel.visible = true
	hint_panel.modulate.a = 1.0
	if _hint_tween != null and _hint_tween.is_valid():
		_hint_tween.kill()
	_hint_tween = create_tween()
	_hint_tween.tween_interval(3.0)
	_hint_tween.tween_property(hint_panel, "modulate:a", 0.0, 0.4)
	_hint_tween.tween_callback(func() -> void:
		hint_panel.visible = false)


## 热层钮点亮态（TAB / 按钮两种入口共用）。
func set_heat_vis(on: bool) -> void:
	heat_btn.theme_type_variation = UiStyle.BTN_HUD_ACTIVE_VAR if on else UiStyle.BTN_HUD_VAR


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
			# 立即落位（不等下一 tick 的 _update_floats）：贴顶栏的击杀点不闪现到 HUD 条上
			el.position = Vector2(sx - 14.0, maxf(sy - 18.0, TOP_STRIP_H + 4.0))
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
				# v2.4：浮字不得压到顶栏（击杀点投影到屏幕边缘时会飘进 HUD 条）
				var fy: float = maxf(float(f["sy"]) - 18.0 - float(age) * FLOAT_RISE, TOP_STRIP_H + 4.0)
				el.position = Vector2(float(f["sx"]) - 14.0, fy)
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
	supply_text.text = str(world.supply)
	supply_text.add_theme_color_override("font_color", DARK["text"] if flash else DARK["supply"])
	_update_affordability(world.supply)
	_update_hint(world.tick_count)

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
		skill_btn.disabled = cd > 0
		row_cost["skill"].text = ("%ds" % shown) if cd > 0 else "就绪"
		_paint_skill()


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
	if hint_panel != null:
		hint_panel.visible = true
		hint_panel.modulate.a = 1.0
	_hint_hidden = false
	if undo_panel != null: # 新局撤销窗口天然关闭
		undo_panel.visible = false
		_undo_on = false
	for f in floats:
		f["active"] = false
		var el: Label = f["el"]
		el.visible = false
	set_mode(mode)
