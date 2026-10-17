extends RefCounted
# UI 样式工厂（v2.2 起）：全部 Control 样式的唯一构造入口。
# - 参数表：按钮四态 / 标题条 / 饰线 / veil 档位全集中在此调参（今后质感 pass 只改本文件）。
# - 调色板仍归 hud.DARK（探针引用面），工厂只持「结构常量」：veil 档位、标题条底、主钮按下金档。
# - 规约：hud.gd / screens.gd 禁止裸 Color8 构造样式（tools/check_ui_lint.py 守规，白名单=DARK 定义区）。
# - 两个发射器：a=运行时 Theme + type variations（screens 面）；b=逐钮 override/meta（hud 探针面）。
#   两路由同一份参数派生，永远一致；探针退役时删发射器 b，样式定义零重写。

const GOLD_PRESSED := Color8(168, 138, 84, 255) # 主钮按下档：帝王金暗一阶
const TITLE_BAR_BG := Color8(10, 8, 5, 160)     # 卡内衬线标题条底
const RULE := Color8(150, 120, 76, 140)         # 1px 金分隔线（rule）
const VEIL_SOFT := Color8(10, 9, 6, 150)        # 页面 veil：战场透出较多（暂停）
const VEIL_PAGE := Color8(10, 9, 6, 170)        # 页面 veil：存档/设置
const VEIL_HEAVY := Color8(10, 9, 6, 200)       # 页面 veil：结算/确认弹窗
const TITLE_VEIL_TOP := Color8(10, 9, 6, 0)     # 标题页幕布渐变（顶→底：透→暗）
const TITLE_VEIL_MID := Color8(10, 9, 6, 107)
const TITLE_VEIL_BOTTOM := Color8(10, 9, 6, 240)

# —— 发射器 a：type variations 名（screens 面：按钮/卡片/标题条/滑杆只写名字接入主题） ——
const BTN_PRIMARY_VAR := "PrimaryButton"   # 主钮：金底深字 + 底缘 3px 暗金压边
const BTN_MENU_VAR := "MenuButton"         # 次钮/菜单钮：深底金细边 + hover 亮金字
const CARD_VAR := "DarkCard"               # 菜单卡片面板
const TITLEBAR_VAR := "TitleBar"           # 卡内衬线标题条
const SLIDER_VAR := "GoldSlider"           # HSlider 三件套（暗槽/亮金已过段）

const NO_BORDER := Color(0, 0, 0, 0)
const FONT_PATH := "res://assets/fonts/NotoSansSC-Regular.otf"

static var _theme: Theme = null  # 按 S 缓存的共享主题（hud 与 shell 同源单实例）
static var _theme_s := -1.0
static var _font: FontFile = null


## 共享主题实例访问器（供逐实例改动前 duplicate 样式盒：UiStyle.get_theme().get_stylebox(...)）。
static func get_theme() -> Theme:
	return _theme


## 运行时主题（发射器 a）：默认字体 + 变体样式。S 变化时重建（窗口 resize 由调用方重入）。
## 注意：返回共享实例——逐实例改动（如 pad_left）必须 duplicate 样式盒后走 override。
static func build_theme(C: Dictionary, S: float) -> Theme:
	if _theme != null and is_equal_approx(_theme_s, S):
		return _theme
	var t := Theme.new()
	if _font == null:
		_font = load(FONT_PATH)
	t.default_font = _font
	t.default_font_size = int(11 * S)
	# 按钮：主/次两组变体（样式盒 + 全部字色由 button_states 派生，与 hud 探针面同参数）
	for pair in [[BTN_PRIMARY_VAR, true], [BTN_MENU_VAR, false]]:
		var varname: String = pair[0]
		var st := button_states(C, pair[1])
		t.set_type_variation(varname, "Button")
		for k in ["normal", "hover", "pressed", "disabled"]:
			t.set_stylebox(k, varname, st[k])
		t.set_color("font_color", varname, st["font_color"])
		t.set_color("font_hover_color", varname, st["font_hover_color"])
		t.set_color("font_pressed_color", varname, st["font_pressed_color"])
		t.set_color("font_disabled_color", varname, st["font_disabled_color"])
	# 卡片 / 标题条 / 滑杆
	t.set_type_variation(CARD_VAR, "Panel")
	t.set_stylebox("panel", CARD_VAR, flat(C["card"], C["gold_lo"], 2, 1))
	t.set_type_variation(TITLEBAR_VAR, "Panel")
	t.set_stylebox("panel", TITLEBAR_VAR, flat(TITLE_BAR_BG, C["gold_lo"], 2, 1))
	t.set_type_variation(SLIDER_VAR, "HSlider")
	t.set_stylebox("slider", SLIDER_VAR, flat(C["track"], C["gold_lo"], 2, 1))
	t.set_stylebox("grabber_area", SLIDER_VAR, flat(C["gold"], NO_BORDER, 2, 0))
	t.set_stylebox("grabber_area_highlight", SLIDER_VAR, flat(C["gold_hi"], NO_BORDER, 2, 0))
	_theme = t
	_theme_s = S
	return t



## 基础 StyleBoxFlat：纯色 + 边框 + 圆角（沿用 v2.1 口径）。
static func flat(bg: Color, border: Color, radius: int, border_w: int = 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	return sb


## 按钮四态样式盒 + 字色（hud 探针面与 screens 菜单面共用同一参数）：
## primary=金底深字 + 底缘 3px 暗金压边；secondary/普通=深底金细边 + hover 亮金字。
## 返回 {"normal","hover","pressed","disabled","font_color","font_hover_color","font_pressed_color","font_disabled_color"}。
static func button_states(C: Dictionary, primary: bool) -> Dictionary:
	var st := {}
	if primary:
		var sb_n := flat(C["active"], C["gold_lo"], 2)
		sb_n.border_width_bottom = 3
		var sb_h := flat(C["active_border"], C["gold_lo"], 2)
		sb_h.border_width_bottom = 3
		var sb_p := flat(GOLD_PRESSED, C["gold_lo"], 2)
		sb_p.border_width_bottom = 3
		st["normal"] = sb_n
		st["hover"] = sb_h
		st["pressed"] = sb_p
		st["font_color"] = C["on_gold"]
		st["font_hover_color"] = C["on_gold"]
	else:
		st["normal"] = flat(C["btn"], C["border"], 2)
		st["hover"] = flat(C["btn_hover"], C["active_border"], 2)
		st["pressed"] = flat(C["btn_pressed"], C["gold_lo"], 2)
		st["font_color"] = C["text"]
		st["font_hover_color"] = C["gold_hi"]
	st["disabled"] = flat(C["btn"], C["border"], 2)
	st["font_pressed_color"] = st["font_color"]
	st["font_disabled_color"] = C["muted"]
	return st


## 标签构造：字体可注衬线；shrink_center 对应 screens 版行为（hud 版不缩）。
static func label(text: String, fs: float, color: Color, font: Font = null, shrink_center: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", int(fs))
	l.add_theme_color_override("font_color", color)
	if font != null:
		l.add_theme_font_override("font", font)
	if shrink_center:
		l.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return l
