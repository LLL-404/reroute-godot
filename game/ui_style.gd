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
