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

# —— v2.2 质感层常量（A 档参数口，集中调噪点/投影/饰线档位） ——
const SHADOW_BTN := Color8(0, 0, 0, 110)      # A2 主钮小投影（卡片用调色板 shadow token）
const GLOW_GOLD := Color8(178, 142, 82, 140)  # A3 金字投影色
const GRAIN_ALPHA := 0.05                     # A4 噪粒不透明度（5%，糊字可降 0.03）
const VIGNETTE_ALPHA := 0.31                  # A5 暗角峰值（≈α80/255）
const TICK_ARM := 8.0                         # C 四角饰线臂长

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
	var card_sb := flat(C["card"], C["gold_lo"], 2, 1)
	card_sb.shadow_size = int(12 * S) # A2 卡片投影（随 S 重建）
	card_sb.shadow_offset = Vector2(0, int(4 * S))
	card_sb.shadow_color = C["shadow"]
	t.set_type_variation(CARD_VAR, "PanelContainer")
	t.set_stylebox("panel", CARD_VAR, card_sb)
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
	if primary: # A2 主钮小投影（normal/hover），压出浮起感
		st["normal"].shadow_size = 6
		st["normal"].shadow_offset = Vector2(0, 4)
		st["normal"].shadow_color = SHADOW_BTN
		st["hover"].shadow_size = 6
		st["hover"].shadow_offset = Vector2(0, 4)
		st["hover"].shadow_color = SHADOW_BTN
	st["pressed"].content_margin_top = 2 # A6 伪按压：按下文字/内容下沉 2px
	return st


## A1 光边（draw 闭包，零子节点、随尺寸自适应）：顶部 2px 亮金高光 + 可选底缘 3px 金压线。
## top=高光色（调色板 edge_hi，α 由 token 管）；bottom=底压线色（壳层传 RULE≈gold_lo·α140）。
static func edge_dress(c: Control, top: Color, bottom: Color) -> void:
	c.draw.connect(func() -> void:
		var r := c.size
		if r.x >= 4.0 and r.y >= 6.0:
			c.draw_rect(Rect2(1, 1, r.x - 2, 2), top)
			# 底压线避开圆角：内侧收 1px，高 3px
			if bottom.a > 0.0:
				c.draw_rect(Rect2(1, r.y - 3, r.x - 2, 3), bottom)
	)


## C 饰线：控件四角 8px L 形金细线（draw 闭包，画在样式盒之上、内容之下）。
static func corner_dress(c: Control, color: Color) -> void:
	c.draw.connect(func() -> void:
		var s := c.size
		if s.x >= TICK_ARM * 2.0 + 2.0 and s.y >= TICK_ARM * 2.0 + 2.0:
			c.draw_rect(Rect2(0, 0, TICK_ARM, 1), color)
			c.draw_rect(Rect2(0, 0, 1, TICK_ARM), color)
			c.draw_rect(Rect2(s.x - TICK_ARM, 0, TICK_ARM, 1), color)
			c.draw_rect(Rect2(s.x - 1, 0, 1, TICK_ARM), color)
			c.draw_rect(Rect2(0, s.y - 1, TICK_ARM, 1), color)
			c.draw_rect(Rect2(0, s.y - TICK_ARM, 1, TICK_ARM), color)
			c.draw_rect(Rect2(s.x - TICK_ARM, s.y - 1, TICK_ARM, 1), color)
			c.draw_rect(Rect2(s.x - 1, s.y - TICK_ARM, 1, TICK_ARM), color)
	)


## 标签构造：字体可注衬线；shrink_center 对应 screens 版行为（hud 版不缩）；
## glow=A3 金字投影（font_shadow α140 + offset (0,1)，仅金字/衬线大标题用）。
static func label(text: String, fs: float, color: Color, font: Font = null, shrink_center: bool = false, glow: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", int(fs))
	l.add_theme_color_override("font_color", color)
	if font != null:
		l.add_theme_font_override("font", font)
	if shrink_center:
		l.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if glow:
		l.add_theme_color_override("font_shadow_color", GLOW_GOLD)
		l.add_theme_constant_override("shadow_offset_x", 0)
		l.add_theme_constant_override("shadow_offset_y", 1)
	return l


# —— A4/A5 覆盖层纹理（确定性：固定种子；懒生成缓存） ——

static var _grain: NoiseTexture2D = null
static var _vign: GradientTexture2D = null


## A4 噪粒纹理：无缝 256² 颗粒（FastNoiseLite 固定种子，TILE 铺法由调用方定）。
static func grain_tex() -> NoiseTexture2D:
	if _grain == null:
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX
		n.seed = 20260415
		n.frequency = 0.09
		var nt := NoiseTexture2D.new()
		nt.noise = n
		nt.width = 256
		nt.height = 256
		nt.seamless = true
		_grain = nt
	return _grain


## A5 暗角纹理：径向渐变（中心 α0 → 0.78 处 α0 → 边缘 VIGNETTE_ALPHA）。
static func vignette_tex() -> GradientTexture2D:
	if _vign == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.78, 1.0])
		g.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, VIGNETTE_ALPHA)])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(0.5, 0.02) # 半径=半高，全屏拉伸后成椭圆随画幅
		t.width = 256
		t.height = 256
		_vign = t
	return _vign


## A4+A5 页面氛围层：暗角（下一层）+ 5% 黑噪粒（TILE，最上）。仅覆盖页可挂；
## game 页禁挂（check_shots 像素契约不受任何影响）。
static func overlay_fx(page: Control) -> void:
	var v := TextureRect.new()
	v.texture = vignette_tex()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.stretch_mode = TextureRect.STRETCH_SCALE
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(v)
	var n := TextureRect.new()
	n.texture = grain_tex()
	n.set_anchors_preset(Control.PRESET_FULL_RECT)
	n.stretch_mode = TextureRect.STRETCH_TILE
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	n.self_modulate = Color(0, 0, 0, GRAIN_ALPHA)
	page.add_child(n)
