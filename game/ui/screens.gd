extends CanvasLayer

# 界面壳（移植 reroute/scripts/screens.lua + ScreenManager 的页栈语义）：标题 / 暂停 / 结算
# / 存档（3 槽，读|存双模式）/ 设置（音频 / 显示 / 画质 / 性能 四组）五屏 + 通用确认弹窗。
# 游戏流转即屏状态：进行中 = current_page()==""；暂停 = "pause"；结算 = "gameover"；
# 标题 = "title"；存档页 = "slots"；设置页 = "settings"。
# 页面懒建缓存复用；切换带 0.18s 淡入；按钮回调由 main 注入；存档/设置模块直接 preload。
# 口径说明：母版 Shell.resume 走 ScreenManager:Back()，而 Back 在"栈<=1 拒绝"的保护下
# 无法弹出单元素栈（对局=空栈模型下的疑点）；本版按 Shell 自身注释"弹栈到空"语义实现 resume=close_all。

const SaveIO = preload("res://game/core/save_io.gd")
const UserSettings = preload("res://game/core/user_settings.gd")
# 隐私政策完整说明（独立托管页；合规要求玩家随时可查，Android/PC 均走系统浏览器）
const PRIVACY_URL := "https://lll-404.github.io/reroute-privacy/privacy.html"
const UiStyle = preload("res://game/ui/ui_style.gd")
# 标题衬线字（Noto Serif SC Bold 子集 13.8KB，31 字形；许可与加工见 CREDITS.md §3.3）。
# 子集只含屏标题用字（改道暂停读档存档设置防线守住…），正文/按钮仍走主题默认 Noto Sans SC。
const F_SERIF: FontFile = preload("res://assets/fonts/NotoSerifSC-Bold-Sub.ttf")

# 五页面场景路径（结构在 .tscn，样式/尺寸/回调由 _bind_* 注入）
const PAGE_PATHS := {
	"title": "res://game/ui/pages/title.tscn",
	"pause": "res://game/ui/pages/pause.tscn",
	"gameover": "res://game/ui/pages/gameover.tscn",
	"slots": "res://game/ui/pages/slots.tscn",
	"settings": "res://game/ui/pages/settings.tscn",
}

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
var _chips: Dictionary = {} # 设置页选项钮：key（"fps"/"quality"…）→ {值: Button}（选中态刷新用）
var _ui_dirty := false # UI 缩放改动后待重建（拖动滑块中不拆自己，离页/关页时统一重建）

# 确认弹窗
var confirm_layer: Control = null
var confirm_text: Label = null
var _confirm_cb := Callable()

# 全屏黑幕（重活/开局过渡用；在页面之上，不参与页栈）
var veil_root: Control = null
var veil_label: Label = null


## 初始化：注入回调、HUD 引用、缩放、层级，并绑定壳场景节点（结构在 screens.tscn）
func init(callbacks: Dictionary, hud_ref) -> void:
	cb = callbacks
	hud = hud_ref
	C = UiStyle.DARK # v2.3：色板真源归 UiStyle（壳层不再依赖 hud 取色）
	_recalc_s()
	layer = 20 # 壳在 HUD（layer 10）之上
	host = $ScreenHost
	host.theme = UiStyle.build_theme(C, S)
	veil_root = $Veil
	veil_label = $Veil/VeilLabel
	confirm_layer = $ConfirmLayer
	confirm_text = $ConfirmLayer/Center/Card/Margin/Col/ConfirmText
	_bind_veil()
	_bind_confirm()


## 绑定开局过渡黑幕（结构在 screens.tscn；颜色/字号按 S 注入）；
## 独立于页栈，close_all 不会收起它。
func _bind_veil() -> void:
	var bg: ColorRect = veil_root.get_node("Bg")
	bg.color = Color(C["track"], 1.0)
	_dress_label(veil_label, 16.0 * S, C["muted"]) # 正文用无衬线（衬线子集只含屏标题字，别用）
	veil_root.modulate.a = 0.0


## 显示黑幕：fade=0 立即全黑（用于构建前先出帧），>0 淡入；显示期间吞掉指针。
func veil_show(text: String, fade: float = 0.0) -> void:
	if veil_root == null:
		return
	veil_label.text = text
	veil_root.visible = true
	veil_root.mouse_filter = Control.MOUSE_FILTER_STOP
	veil_root.modulate.a = 0.0 if fade > 0.0 else 1.0
	if fade > 0.0:
		create_tween().tween_property(veil_root, "modulate:a", 1.0, fade)


## 淡出黑幕（构建完成后揭示标题/战场）。
func veil_fade_out(dur: float = 0.25) -> void:
	if veil_root == null or not veil_root.visible:
		return
	veil_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := create_tween()
	t.tween_property(veil_root, "modulate:a", 0.0, dur)
	t.tween_callback(_hide_veil)


## 立即收起黑幕（开屏动画自己的黑场接管时用，避免双重淡出）。
func veil_hide() -> void:
	if veil_root == null:
		return
	veil_root.visible = false
	veil_root.modulate.a = 0.0


func _hide_veil() -> void:
	veil_root.visible = false


## snake_case 键 → PascalCase 节点名（场景节点已对齐官方命名规范，动态拼接统一走此口）。
static func _pn(s: String) -> String:
	var out := ""
	for part in s.split("_"):
		if not part.is_empty():
			out += part[0].to_upper() + part.substr(1)
	return out


# ---------------- UI 缩放（设置页「UI 缩放」滑块） ----------------

## 按当前视口与玩家 UI 倍率重算 S（初始化 / 页面重建共用）。
func _recalc_s() -> void:
	S = clampf(get_viewport().get_visible_rect().size.y / 816.0, 1.0, 1.6) * UserSettings.ui_scale


## UI 缩放应用：无页面时立即重算并换主题；已有页面时标记脏（离开设置页时统一重建，
## 避免拖动滑块过程中拆掉当前页）。
func apply_ui_scale(pct: int) -> void:
	UserSettings.ui_scale = clampf(float(pct) / 100.0, 0.8, 1.3)
	if pages.is_empty():
		_recalc_s()
		if host != null:
			host.theme = UiStyle.build_theme(C, S)
	else:
		_ui_dirty = true


## 按新 S 重建全部页面（旧页 queue_free 延迟回收；后续按需惰建）。
func _rebuild_pages() -> void:
	for k in pages:
		pages[k].queue_free()
	pages.clear()
	_chips.clear()
	_ui_dirty = false
	_recalc_s()
	host.theme = UiStyle.build_theme(C, S)


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
	if _ui_dirty:
		_rebuild_pages() # UI 缩放待重建：直接弃页，回对局后按需惰建
	else:
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
	var head: Label = pages["slots"].find_child("LabelSlotHead", true, false)
	head.text = "读档" if mode == "load" else "存档"
	var status: Label = pages["slots"].find_child("LabelSlotStatus", true, false)
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


## 绑定全局确认弹窗层（场景内 ConfirmLayer 晚于页面节点 → 永在最上）；
## 幕色/氛围层/卡片样式按 S 注入，弹窗文案与按钮顺序不变。
func _bind_confirm() -> void:
	var veil: ColorRect = confirm_layer.get_node("ConfirmVeil")
	veil.color = UiStyle.VEIL_HEAVY
	UiStyle.overlay_fx(confirm_layer.get_node("Fx")) # A5+A4（层级在卡片之下）
	var card: PanelContainer = confirm_layer.get_node("Center/Card")
	card.custom_minimum_size = Vector2(300.0 * S, 0)
	card.theme_type_variation = UiStyle.CARD_VAR
	UiStyle.corner_dress(card, C["gold_lo"]) # C 饰线
	_dress_margins(confirm_layer.get_node("Center/Card/Margin"), 22.0)
	var col: VBoxContainer = confirm_layer.get_node("Center/Card/Margin/Col")
	col.add_theme_constant_override("separation", int(16 * S))
	_dress_label(confirm_text, 15.0 * S, C["text"])
	confirm_text.custom_minimum_size = Vector2(256.0 * S, 0)
	var row: HBoxContainer = confirm_layer.get_node("Center/Card/Margin/Col/Row")
	row.add_theme_constant_override("separation", int(12 * S))
	_dress_button(confirm_layer.get_node("Center/Card/Margin/Col/Row/BtnConfirmOk"), true, 116.0 * S, 40.0 * S, 12.0 * S, func() -> void:
		_resolve_confirm(true))
	_dress_button(confirm_layer.get_node("Center/Card/Margin/Col/Row/BtnConfirmCancel"), false, 116.0 * S, 40.0 * S, 12.0 * S, func() -> void:
		_resolve_confirm(false))


# ---------------- 页面绑定辅助（结构在 scenes，样式/尺寸按 S 注入） ----------------

## 标签样式：字号/字色/可选衬线字体 + 金字辉光；沿用原工厂的居中缩小语义。
func _dress_label(l: Label, fs: float, color: Color, serif := false, glow := false) -> void:
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", int(fs))
	l.add_theme_color_override("font_color", color)
	if serif:
		l.add_theme_font_override("font", F_SERIF)
	l.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if glow:
		l.add_theme_color_override("font_shadow_color", UiStyle.GLOW_GOLD)
		l.add_theme_constant_override("shadow_offset_x", 0)
		l.add_theme_constant_override("shadow_offset_y", 1)


## 卡片内边距统一注入（四边同值 × S）。
func _dress_margins(m: MarginContainer, px: float) -> void:
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, int(px * S))


## 金分隔线（1px）。
func _dress_rule(r: ColorRect) -> void:
	r.color = UiStyle.RULE
	r.custom_minimum_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE


## 弹性空档（VBox 内定高占位）。
func _dress_gap(c: Control, h: float) -> void:
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE


## 种子输入框（标题屏）：最小主题注入（底板/边框走 UiStyle.flat 工厂，字色走色板 token）。
func _dress_seed_input(e: LineEdit) -> void:
	e.custom_minimum_size = Vector2(0, 30.0 * S)
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.add_theme_font_size_override("font_size", int(13.0 * S))
	e.add_theme_color_override("font_color", C["text"])
	e.add_theme_color_override("font_placeholder_color", C["muted"])
	e.add_theme_color_override("caret_color", C["gold_hi"])
	e.add_theme_stylebox_override("normal", UiStyle.flat(C["btn"], C["border"], 2, 1))
	e.add_theme_stylebox_override("focus", UiStyle.flat(C["btn_hover"], C["active_border"], 2, 1))


## 按钮样式：主题变体（发射器 a）+ A1 光边；pad_left ≥0 时复制样式盒加左距。
func _dress_button(b: Button, primary: bool, w: float, h: float, fs: float, fn: Callable, pad_left: float = -1.0) -> void:
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


## 标题菜单文字行：序号 + 名称 + 1px 下划线；主行常亮左金条，其余 hover 才亮。
func _dress_menu_row(b: Button, idx: int, primary: bool, fn: Callable) -> void:
	var h := (54.0 if primary else 48.0) * S
	var w := 300.0 * S
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(w, h)
	b.size = Vector2(w, h)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", int((16.0 if primary else 13.5) * S))
	b.theme_type_variation = UiStyle.BTN_ROW_PRIMARY_VAR if primary else UiStyle.BTN_ROW_VAR
	b.pressed.connect(fn)
	var num: Label = b.get_node("Num")
	num.text = "%02d" % idx
	_dress_label(num, 10.0 * S, C["gold_hi"] if primary else C["muted"])
	num.reset_size()
	num.position = Vector2(20.0 * S, (h - num.size.y) / 2.0)
	var bar: ColorRect = b.get_node("Bar")
	bar.color = C["gold_hi"] if primary else C["gold"]
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.position = Vector2.ZERO
	bar.size = Vector2(2.0 * S, h)
	bar.visible = primary
	b.mouse_entered.connect(func() -> void: bar.visible = true)
	b.mouse_exited.connect(func() -> void: bar.visible = primary)


## 卡片内金标题条（文明 6 式：暗底 + 衬线金字 + 底缘金线）。
func _dress_title_bar(bar: Panel, lbl: Label, bar_h: float) -> void:
	bar.theme_type_variation = UiStyle.TITLEBAR_VAR
	bar.custom_minimum_size = Vector2(0, bar_h * S)
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.size_flags_horizontal = Control.SIZE_FILL
	_dress_label(lbl, 24.0 * S, C["gold_hi"], true)


## 卡片页底板绑定：幕色 + 氛围层（A5 暗角 + A4 噪粒）+ 卡片宽/边距/列距；返回列容器。
func _dress_card_page(p: Control, veil: Color, card_w: float, margin_px: float, sep: float) -> VBoxContainer:
	var bg: ColorRect = p.get_node("Bg")
	bg.color = veil
	UiStyle.overlay_fx(p.get_node("Fx")) # A5 暗角 + A4 噪粒（在 bg 上、内容下）
	var card: PanelContainer = p.get_node("Center/Card")
	card.custom_minimum_size = Vector2(card_w * S, 0)
	card.theme_type_variation = UiStyle.CARD_VAR
	UiStyle.corner_dress(card, C["gold_lo"]) # C 饰线
	_dress_margins(p.get_node("Center/Card/Margin"), margin_px)
	var col: VBoxContainer = p.get_node("Center/Card/Margin/Col")
	col.add_theme_constant_override("separation", int(sep * S))
	return col


## 滑杆金化：暗槽 + 古金边 + 已过段亮金（grabber 图标走默认主题，不引贴图）。
func _style_slider(s: HSlider) -> void:
	s.theme_type_variation = UiStyle.SLIDER_VAR


## 选项行绑定：96 宽标签 + 一排互斥钮（选中态由 _refresh_chips 切主题变体）；
## supported = 当前平台可选档，candidates = 场景内全部候选钮（其余隐藏）。
func _dress_option_row(body: VBoxContainer, key: String, supported: Array, candidates: Array) -> HBoxContainer:
	var row: HBoxContainer = body.get_node(_pn("row_" + key))
	row.add_theme_constant_override("separation", int(8 * S))
	var lbl: Label = row.get_node("Lbl")
	_dress_label(lbl, 12.5 * S, C["muted"])
	lbl.custom_minimum_size = Vector2(96.0 * S, 0)
	var map: Dictionary = {}
	for v in candidates:
		var b: Button = row.get_node(_pn("btn_%s_%d" % [key, v]))
		_dress_button(b, false, 60.0 * S, 40.0 * S, 11.5 * S, _on_video_chip.bind(key, int(v)))
		var on := supported.has(v)
		b.visible = on
		if on:
			map[v] = b
	_chips[key] = map
	return row


## 设置页分组标题绑定：左金标 + 组名 + 右侧通栏细线。
func _dress_group_header(row: HBoxContainer) -> void:
	row.add_theme_constant_override("separation", int(9 * S))
	var tick: ColorRect = row.get_node("Tick")
	tick.color = C["gold"]
	tick.custom_minimum_size = Vector2(3.0 * S, 12.0 * S)
	tick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dress_label(row.get_node("Title"), 12.0 * S, C["gold"])
	var line: ColorRect = row.get_node("Line")
	_dress_rule(line)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER


## 设置页滑杆行绑定：96 宽标签 + 滑杆 + 读数（命名 sld_<key> / lbl_<key>_val）。
func _dress_slider_row(body: VBoxContainer, key: String, vmin: int, vmax: int, fn: Callable) -> void:
	var row: HBoxContainer = body.get_node(_pn("row_" + key))
	row.add_theme_constant_override("separation", int(10 * S))
	var lbl: Label = row.get_node("Lbl")
	_dress_label(lbl, 12.5 * S, C["muted"])
	lbl.custom_minimum_size = Vector2(96.0 * S, 0)
	var sld: HSlider = row.get_node(_pn("sld_" + key))
	sld.min_value = vmin
	sld.max_value = vmax
	sld.step = 1
	sld.custom_minimum_size = Vector2(240.0 * S, 26.0 * S)
	sld.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_style_slider(sld)
	sld.value_changed.connect(fn)
	var val: Label = row.get_node(_pn("lbl_%s_val" % key))
	_dress_label(val, 12.5 * S, C["gold_hi"])
	val.custom_minimum_size = Vector2(40.0 * S, 0)
	val.text = str(vmax)


## 绑定标题页：底部渐暗帷幕 + 左列式菜单 + 玩法说明浮层（结构在 pages/title.tscn）
func _bind_title(p: Control) -> void:
	var veil: TextureRect = p.get_node("TitleVeil")
	veil.texture = UiStyle.title_veil_tex()
	UiStyle.overlay_fx(p.get_node("Fx")) # A5+A4

	# 左列：金条 + 衬线标题 + 菜单文字行（v2.5：去盒化，序号/下划线/左金条）
	var col: VBoxContainer = p.get_node("Col")
	col.add_theme_constant_override("separation", 0)
	col.offset_left = 0
	col.offset_right = int(300.0 * S)
	col.offset_top = int(96.0 * S)
	col.offset_bottom = int(-64.0 * S)

	var head: HBoxContainer = p.get_node("Col/Head")
	head.add_theme_constant_override("separation", int(14.0 * S))
	var accent: ColorRect = p.get_node("Col/Head/Accent")
	accent.color = C["gold"]
	accent.custom_minimum_size = Vector2(3.0 * S, 0)
	var hcol: VBoxContainer = p.get_node("Col/Head/Hcol")
	hcol.add_theme_constant_override("separation", int(7.0 * S))
	var title_row: HBoxContainer = p.get_node("Col/Head/Hcol/TitleRow")
	title_row.add_theme_constant_override("separation", int(26.0 * S))
	title_row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	for ch in title_row.get_children():
		_dress_label(ch, 62.0 * S, C["gold_hi"], true, true)
	_dress_label(p.get_node("Col/Head/Hcol/Tagline"), 13.0 * S, C["muted"])
	_dress_gap(p.get_node("Col/Gap1"), 18.0 * S)
	_dress_rule(p.get_node("Col/Rule"))
	_dress_gap(p.get_node("Col/Gap2"), 12.0 * S)

	# 种子行（Task 3）：留空 = 每局随机；改动即写设置，开局时把原文交给 main
	_dress_gap(p.get_node("Col/SeedGap"), 10.0 * S)
	var seed_row: HBoxContainer = p.get_node("Col/SeedRow")
	seed_row.add_theme_constant_override("separation", int(8.0 * S))
	var seed_lbl: Label = seed_row.get_node("SeedLbl")
	_dress_label(seed_lbl, 12.0 * S, C["muted"])
	seed_lbl.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN # 左对齐（_dress_label 默认居中）
	seed_lbl.custom_minimum_size = Vector2(40.0 * S, 0)
	var seed_input: LineEdit = seed_row.get_node("SeedInput")
	_dress_seed_input(seed_input)
	seed_input.text = String(cb["get_seed_text"].call()) # 回填上次保存的种子文本
	seed_input.text_changed.connect(func(t: String) -> void:
		cb["seed_changed"].call(t))

	_dress_menu_row(p.get_node("Col/BtnRogue"), 1, true, func() -> void:
		cb["start_rogue"].call(seed_input.text))
	_dress_menu_row(p.get_node("Col/BtnStart"), 2, false, func() -> void:
		cb["start_match"].call(seed_input.text))
	_dress_menu_row(p.get_node("Col/BtnContinue"), 3, false, func() -> void:
		open_slots("load", "title"))
	_dress_menu_row(p.get_node("Col/BtnSettings"), 4, false, func() -> void:
		open_settings("title"))
	_dress_menu_row(p.get_node("Col/BtnTips"), 5, false, func() -> void:
		tips_panel.visible = not tips_panel.visible)
	_dress_menu_row(p.get_node("Col/BtnQuit"), 6, false, func() -> void:
		open_quit_confirm())

	# 玩法说明浮层（菜单列右侧；默认隐藏，切换不影响列布局）
	tips_panel = p.get_node("PanelTips")
	tips_panel.custom_minimum_size = Vector2(360.0 * S, 0)
	tips_panel.theme_type_variation = UiStyle.CARD_VAR
	UiStyle.corner_dress(tips_panel, C["gold_lo"]) # C 饰线
	_dress_margins(tips_panel.get_node("Margin"), 18.0)
	var tips_col: VBoxContainer = tips_panel.get_node("Margin/TipsCol")
	tips_col.add_theme_constant_override("separation", int(9.0 * S))
	for line in tips_col.get_children():
		_dress_label(line, 11.0 * S, C["muted"])
	tips_panel.reset_size()
	var vw := get_viewport().get_visible_rect().size.x
	tips_panel.position = Vector2(vw * 0.18 + 324.0 * S, 96.0 * S)

	# 版本 / 赛事行（左下角）
	var jam: Label = p.get_node("Jam")
	_dress_label(jam, 10.0 * S, C["muted"])
	jam.offset_left = int(24.0 * S)
	jam.offset_right = int(380.0 * S)
	jam.offset_top = int(-34.0 * S)
	jam.offset_bottom = int(-16.0 * S)
	jam.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	jam.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	jam.size_flags_horizontal = Control.SIZE_FILL


## 绑定暂停页（继续 / 保存进度 / 设置 / 重开本局 / 回标题；结构在 pages/pause.tscn）
func _bind_pause(p: Control) -> void:
	_dress_card_page(p, UiStyle.VEIL_SOFT, 340.0, 28.0, 12.0)
	var base := "Center/Card/Margin/Col"
	_dress_title_bar(p.get_node(base + "/TitleBar"), p.get_node(base + "/TitleBar/Title"), 44.0)
	_dress_rule(p.get_node(base + "/Rule"))
	_dress_button(p.get_node(base + "/BtnResume"), true, 260.0 * S, 46.0 * S, 14.0 * S, func() -> void:
		cb["resume"].call())
	_dress_button(p.get_node(base + "/BtnSave"), false, 260.0 * S, 44.0 * S, 12.5 * S, func() -> void:
		open_slots("save", "pause"))
	_dress_button(p.get_node(base + "/BtnSettingsPause"), false, 260.0 * S, 44.0 * S, 12.5 * S, func() -> void:
		open_settings("pause"))
	_dress_button(p.get_node(base + "/BtnRestart"), false, 260.0 * S, 44.0 * S, 12.5 * S, func() -> void:
		cb["restart"].call())
	_dress_button(p.get_node(base + "/BtnToTitle"), false, 260.0 * S, 44.0 * S, 12.5 * S, func() -> void:
		cb["to_title"].call())


## 绑定结算页（胜负标题 + 统计文案 + 再来一局 / 回标题；结构在 pages/gameover.tscn）
func _bind_gameover(p: Control) -> void:
	_dress_card_page(p, UiStyle.VEIL_HEAVY, 440.0, 30.0, 16.0)
	var base := "Center/Card/Margin/Col"
	# 胜负标题：文本/颜色由 open_gameover 注入（探针断言 色=hp|danger）；衬线字形已进子集
	go_title = p.get_node(base + "/GoTitle")
	_dress_label(go_title, 36.0 * S, C["danger"], true, true)
	go_body = p.get_node(base + "/GoBody")
	_dress_label(go_body, 13.5 * S, C["text"])
	go_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	go_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	go_body.custom_minimum_size = Vector2(380.0 * S, 0)
	_dress_button(p.get_node(base + "/BtnAgain"), true, 240.0 * S, 46.0 * S, 14.0 * S, func() -> void:
		cb["restart"].call())
	_dress_button(p.get_node(base + "/BtnToTitle2"), false, 240.0 * S, 44.0 * S, 12.5 * S, func() -> void:
		cb["to_title"].call())


## 绑定存档页（3 槽：读档|存档双模式 + 删除 + 状态行；结构在 pages/slots.tscn）
func _bind_slots(p: Control) -> void:
	_dress_card_page(p, UiStyle.VEIL_PAGE, 520.0, 26.0, 10.0)
	var base := "Center/Card/Margin/Col"
	# 动态标题（读档/存档）：open_slots 改 text，衬线字体常驻
	_dress_title_bar(p.get_node(base + "/TitleBar"), p.get_node(base + "/TitleBar/LabelSlotHead"), 44.0)
	_dress_rule(p.get_node(base + "/Rule"))
	for i in range(1, SaveIO.SLOT_N + 1):
		var row: HBoxContainer = p.get_node(base + "/SlotRow%d" % i)
		row.add_theme_constant_override("separation", int(8 * S))
		var b: Button = row.get_node(_pn("btn_slot%d" % i))
		_dress_button(b, false, 380.0 * S, 52.0 * S, 12.5 * S, _on_slot_pressed.bind(i), 16.0 * S)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		# 删除钮位（v2.4）：同宽占位块与删除钮互斥显示，隐藏时栅格不塌（槽条横向对齐恒定）
		_dress_button(row.get_node(_pn("btn_slot_del%d" % i)), false, 64.0 * S, 52.0 * S, 10.0 * S, _on_slot_delete.bind(i))
		var pad: Control = row.get_node(_pn("pad_slot_del%d" % i))
		pad.custom_minimum_size = Vector2(64.0 * S, 52.0 * S)
		pad.visible = false
	_dress_label(p.get_node(base + "/LabelSlotStatus"), 11.0 * S, C["muted"])
	_dress_button(p.get_node(base + "/BtnSlotsBack"), false, 240.0 * S, 44.0 * S, 12.5 * S, func() -> void:
		_show(slots_from))


## 绑定设置页（音频 / 显示 / 画质 / 性能 四组 + 关于；结构在 pages/settings.tscn）
func _bind_settings(p: Control) -> void:
	_dress_card_page(p, UiStyle.VEIL_PAGE, 540.0, 24.0, 10.0)
	var base := "Center/Card/Margin/Col"
	_dress_title_bar(p.get_node(base + "/TitleBar"), p.get_node(base + "/TitleBar/Title"), 44.0)
	_dress_rule(p.get_node(base + "/Rule1"))

	# 滚动体（v2.4）：外层 Control 承载「底缘渐隐」，行被裁切时给出可滚动暗示；
	# 滚动区与底部「返回」用 1px 金线分隔，避免旧版内容像被按钮压住。
	var wrap: Control = p.get_node(base + "/SettingsScrollWrap")
	wrap.custom_minimum_size = Vector2(0, minf(get_viewport().get_visible_rect().size.y * 0.66, 640.0 * S))
	wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var scroll: ScrollContainer = p.get_node(base + "/SettingsScrollWrap/SettingsScroll")
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	UiStyle.scrollbar(scroll, C, S)
	var body: VBoxContainer = p.get_node(base + "/SettingsScrollWrap/SettingsScroll/SettingsBody")
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", int(12 * S))
	var fade: TextureRect = p.get_node(base + "/SettingsScrollWrap/ScrollFade")
	fade.texture = UiStyle.fade_tex(C["card"])
	fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fade.stretch_mode = TextureRect.STRETCH_SCALE
	fade.offset_top = -26.0 * S
	fade.offset_bottom = 0.0

	var android := OS.get_name() == "Android"
	for g in ["audio", "display", "quality", "perf", "about"]:
		_dress_group_header(body.get_node(_pn("group_" + g)))

	# —— 音频 ——
	_dress_slider_row(body, "music", UserSettings.VOL_MIN, UserSettings.VOL_MAX, _on_music_changed)
	_dress_slider_row(body, "sfx", UserSettings.VOL_MIN, UserSettings.VOL_MAX, _on_sfx_changed)

	# —— 显示 ——（安卓恒全屏：显示模式/分辨率隐藏，渲染精度走「性能」组渲染缩放）
	_dress_option_row(body, "display_mode", [0, 1, 2], [0, 1, 2]).visible = not android
	_dress_option_row(body, "res_idx", [0, 1, 2, 3, 4], [0, 1, 2, 3, 4]).visible = not android
	_dress_option_row(body, "vsync", [0, 1], [0, 1])
	var fps_supported: Array = []
	for v in UserSettings.fps_opts():
		fps_supported.append(int(v))
	_dress_option_row(body, "fps", fps_supported, [0, 30, 60, 120])

	# —— 画质 ——（预设 = 一键模板；子项可单独改，改动即时生效）
	_dress_option_row(body, "quality", [0, 1, 2, 3], [0, 1, 2, 3])
	_dress_option_row(body, "shadow_q", [0, 1, 2], [0, 1, 2])
	_dress_option_row(body, "fx_q", [0, 1, 2], [0, 1, 2])
	var aa_supported: Array = []
	for v in UserSettings.aa_opts():
		aa_supported.append(int(v))
	_dress_option_row(body, "aa", aa_supported, [0, 1, 2])
	_dress_option_row(body, "post_q", [0, 1, 2], [0, 1, 2])
	_dress_option_row(body, "dof", [0, 1], [0, 1])

	# —— 性能 ——
	_dress_slider_row(body, "render_pct", 50, 100, _on_render_changed)
	_dress_slider_row(body, "ui_pct", 80, 130, _on_ui_changed)
	_dress_slider_row(body, "bright_pct", 70, 130, _on_bright_changed)

	# —— 关于 ——（隐私政策入口：合规要求玩家随时可查；Android/PC 均走系统浏览器）
	var prow: HBoxContainer = body.get_node("RowPrivacy")
	prow.add_theme_constant_override("separation", int(8 * S))
	var plbl: Label = prow.get_node("Lbl")
	_dress_label(plbl, 12.5 * S, C["muted"])
	plbl.custom_minimum_size = Vector2(96.0 * S, 0)
	_dress_button(prow.get_node("BtnPrivacyPolicy"), false, 132.0 * S, 40.0 * S, 11.5 * S, func() -> void:
		OS.shell_open(PRIVACY_URL))

	_dress_gap(p.get_node(base + "/Gap"), 4.0 * S)
	_dress_rule(p.get_node(base + "/Rule2"))
	_dress_button(p.get_node(base + "/BtnSettingsBack"), false, 240.0 * S, 44.0 * S, 12.5 * S, func() -> void:
		_show(settings_from))


# ---------------- 存档页行为 ----------------

## 标题「继续对局」可用性：有任何非空槽位（含损坏档——进列表可删）即亮。
func _refresh_title() -> void:
	var btn: Button = pages["title"].find_child("BtnContinue", true, false)
	btn.disabled = not SaveIO.has_any()


## 按模式刷新槽位：读档空槽禁用；删除钮仅读档且非空时显示
func _refresh_slots() -> void:
	var page: Control = pages["slots"]
	for info in SaveIO.list_slots():
		var slot: int = info["slot"]
		var row: Button = page.find_child(_pn("btn_slot%d" % slot), true, false)
		row.text = _slot_row_text(info)
		var empty: bool = info.get("empty", true)
		row.disabled = empty if slots_mode == "load" else false
		var del: Button = page.find_child(_pn("btn_slot_del%d" % slot), true, false)
		del.visible = slots_mode == "load" and not empty
		var pad: Control = page.find_child(_pn("pad_slot_del%d" % slot), true, false)
		if pad != null:
			pad.visible = not del.visible


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
	var status: Label = pages["slots"].find_child("LabelSlotStatus", true, false)
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

## 设置页回填：读 cfg 填入滑杆/选项钮（no_signal 防触发落盘/应用）
func _load_settings_into_ui() -> void:
	_cfg = UserSettings.load_cfg()
	var page: Control = pages["settings"]
	for key in ["music", "sfx", "render_pct", "ui_pct", "bright_pct"]:
		var sld: HSlider = page.find_child(_pn("sld_" + key), true, false)
		var lbl: Label = page.find_child(_pn("lbl_%s_val" % key), true, false)
		if sld != null:
			sld.set_value_no_signal(int(_cfg.get(key, 100)))
		if lbl != null:
			lbl.text = str(int(_cfg.get(key, 100)))
	_refresh_chips()


## 滑杆读数刷新（lbl_<key>_val）
func _set_val_label(key: String, v: int) -> void:
	var lbl: Label = pages["settings"].find_child(_pn("lbl_%s_val" % key), true, false)
	if lbl != null:
		lbl.text = str(v)


## 音频滑杆改动：应用 bus + 落盘（不触碰视频链路）
func _apply_settings() -> void:
	UserSettings.apply_audio(_cfg)
	UserSettings.save_cfg(_cfg)


## 音乐滑杆：写 cfg → 读数 → 应用+落盘
func _on_music_changed(v: float) -> void:
	_cfg["music"] = int(v)
	_set_val_label("music", int(v))
	_apply_settings()


## 音效滑杆：写 cfg → 读数 → 应用+落盘
func _on_sfx_changed(v: float) -> void:
	_cfg["sfx"] = int(v)
	_set_val_label("sfx", int(v))
	_apply_settings()


## 渲染缩放滑杆：写 cfg → 读数 → 落盘 + 通知 main 立即应用（scaling_3d_scale）
func _on_render_changed(v: float) -> void:
	_cfg["render_pct"] = int(v)
	_set_val_label("render_pct", int(v))
	_commit_video()


## 画面亮度滑杆：写 cfg → 读数 → 落盘 + 通知 main 立即应用（Environment adjustment）
func _on_bright_changed(v: float) -> void:
	_cfg["bright_pct"] = int(v)
	_set_val_label("bright_pct", int(v))
	_commit_video()


## UI 缩放滑杆：落盘 + 通知 main（HUD 立即重排；界面页离开设置页时按新 S 重建）
func _on_ui_changed(v: float) -> void:
	_cfg["ui_pct"] = int(v)
	_set_val_label("ui_pct", int(v))
	UserSettings.save_cfg(_cfg)
	cb["ui_changed"].call(int(v))


## 视频/画质改动统一出口：落盘 + 通知 main 立即应用 + 选项钮/滑杆回填
func _commit_video() -> void:
	UserSettings.save_cfg(_cfg)
	cb["video_changed"].call(_cfg)
	_refresh_chips()
	_sync_video_sliders()


## 滑杆回填（画质预设会改 render_pct；no_signal 防递归）
func _sync_video_sliders() -> void:
	var page: Control = pages["settings"]
	for key in ["render_pct", "ui_pct", "bright_pct"]:
		var sld: HSlider = page.find_child(_pn("sld_" + key), true, false)
		var lbl: Label = page.find_child(_pn("lbl_%s_val" % key), true, false)
		if sld != null:
			sld.set_value_no_signal(int(_cfg.get(key, 100)))
		if lbl != null:
			lbl.text = str(int(_cfg.get(key, 100)))


## 选项钮选中态刷新：与 _cfg 现值相同 = 主钮金样式，其余 = 次钮（主题变体切换，零 override）。
func _refresh_chips() -> void:
	for key in _chips:
		var sel := int(_cfg.get(key, 0))
		var map: Dictionary = _chips[key]
		for v in map:
			var b: Button = map[v]
			b.theme_type_variation = UiStyle.BTN_PRIMARY_VAR if int(v) == sel else UiStyle.BTN_MENU_VAR


## 选项钮点选：写 cfg；画质预设额外套用一键模板（阴影/特效/AA/后期/渲染缩放）；
## 统一落盘 + 通知 main 立即应用 + 回填（fps/显示/画质全走这一条路）。
func _on_video_chip(key: String, val: int) -> void:
	if key == "vsync" or key == "dof":
		_cfg[key] = val != 0
	else:
		_cfg[key] = val
	if key == "quality":
		var preset: Dictionary = UserSettings.QUALITY_PRESETS[clampi(val, 0, UserSettings.QUALITY_PRESETS.size() - 1)]
		for k in preset:
			_cfg[k] = preset[k]
		_cfg["aa"] = UserSettings.aa_level(int(_cfg.get("aa", 1))) # 安卓无 TAA：极高 → FXAA
	_commit_video()


# ---------------- 页切换 ----------------

## 懒建页面（首次调用时从场景实例化并绑定样式，缓存复用）
func _ensure(name: String) -> Control:
	if pages.has(name):
		return pages[name]
	var p: Control = load(PAGE_PATHS[name]).instantiate()
	match name:
		"title":
			_bind_title(p)
		"pause":
			_bind_pause(p)
		"gameover":
			_bind_gameover(p)
		"slots":
			_bind_slots(p)
		"settings":
			_bind_settings(p)
	p.visible = false
	host.add_child(p)
	pages[name] = p
	return p


## 显示指定页面（其余隐藏，0.18s 淡入）；回标题时顺带刷新「继续对局」可用性。
func _show(name: String) -> void:
	if _ui_dirty:
		_rebuild_pages()
		_ensure(name)
	# v2.4：进入存档/设置等模态页时收起教学提示（HUD 仍在暂停页背景可见）
	if hud != null and (name == "slots" or name == "settings"):
		hud.dismiss_hint()
	for k in pages:
		pages[k].visible = (k == name)
	current = name
	if name == "title":
		_refresh_title()
	var p: Control = pages[name]
	p.modulate.a = 0.0
	var t := create_tween()
	t.tween_property(p, "modulate:a", 1.0, 0.18)
