extends RefCounted
# UI 样式工厂（v2.2 起）：全部 Control 样式的唯一构造入口。
# - 参数表：色板 / 按钮四态 / 标题条 / 饰线 / veil 档位全集中在此调参（质感 pass 只改本文件）。
# - v2.3 起色板归位本文件（DARK 唯一真源）；`hud.DARK` 为兼容别名（探针/旧引用按 key 取色零影响）。
# - 规约：hud.gd / screens.gd 禁止裸 Color8 构造样式（tools/check_ui_lint.py 守规）。
# - 发射器 a：运行时 Theme + type variations（screens 面 + HUD 模式钮，v2.3 全量收编）；
#   逐钮 override/meta 机制已退役。

## 帝王金黑色板（v2.1 改版，docs/UI-REDESIGN-20261017.md §2；v2.3 迁入本文件 = 样式系统唯一真源）：
## 旧暗蓝板（Style.dark 迁移）换文明 6 式暖金调；key 全保留（探针按 key 动态取值）。
const DARK := {
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
const BTN_MENU_VAR := "UiMenuButton"       # 次钮/菜单钮（避内置 MenuButton 类：4.7.2 变体名禁撞内置类）
const BTN_HUD_VAR := "HudButton"           # HUD 模式钮常态：深底金细边（字 text）
const BTN_HUD_ACTIVE_VAR := "HudButtonActive" # HUD 模式钮点亮态：金底深字
const CARD_VAR := "DarkCard"               # 菜单卡片面板
const TITLEBAR_VAR := "TitleBar"           # 卡内衬线标题条
const SLIDER_VAR := "GoldSlider"           # HSlider 三件套（暗槽/亮金已过段）

const NO_BORDER := Color(0, 0, 0, 0)
const CLEAR := Color(1, 1, 1, 0)              # 动画起始全透白（横幅淡入初值）
const FONT_PATH := "res://assets/fonts/NotoSansSC-Regular.otf"

# —— v2.2 质感层常量（A 档参数口，集中调噪点/投影/饰线档位） ——
const SHADOW_BTN := Color8(0, 0, 0, 110)      # A2 主钮小投影（卡片用调色板 shadow token）
const SHADOW_TICK := Color8(0, 0, 0, 110)     # HUD 顶栏 hp 刻底的小影线（同档黑）
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
	# 按钮：主/次 + HUD 常态/点亮 四组变体（样式盒 + 全部字色由状态函数派生，参数唯一源）
	var sets: Array = [
		[BTN_PRIMARY_VAR, button_states(C, true)],
		[BTN_MENU_VAR, button_states(C, false)],
		[BTN_HUD_VAR, hud_button_states(C, false)],
		[BTN_HUD_ACTIVE_VAR, hud_button_states(C, true)],
	]
	for pair in sets:
		var varname: String = pair[0]
		var st: Dictionary = pair[1]
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



## HUD 模式钮两组变体状态（v2.3：退役 override+meta，改 variation 切换）。
## 字色口径沿 v2.1 运行时实况：三态同色（text / on_gold）——hover 不走亮金（与菜单钮不同）。
static func hud_button_states(C: Dictionary, active: bool) -> Dictionary:
	var st := button_states(C, false)
	if active:
		st["normal"] = flat(C["active"], C["active_border"], 2)
		st["font_color"] = C["on_gold"]
		st["font_hover_color"] = C["on_gold"]
		st["font_pressed_color"] = C["on_gold"]
	else:
		st["font_hover_color"] = C["text"]
	return st


## 基础 StyleBoxFlat：纯色 + 边框 + 圆角（沿用 v2.1 口径）。
static func flat(bg: Color, border: Color, radius: int, border_w: int = 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	return sb


## 按钮四态样式盒 + 字色（四组按钮变体同源：primary=金底深字 + 底缘 3px 暗金压边；
## secondary/菜单=深底金细边 + hover 亮金字）。
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


## 标题页渐暗帷幕（TextureRect 用；texture 行 0=顶部，(0,0)→(0,1) 顶透→底暗——实测口径）。
static func title_veil_tex() -> GradientTexture2D:
	if _veil == null:
		var g := Gradient.new()
		g.colors = PackedColorArray([TITLE_VEIL_TOP, TITLE_VEIL_MID, TITLE_VEIL_BOTTOM])
		g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill_from = Vector2(0, 0)
		t.fill_to = Vector2(0, 1)
		t.width = 64
		t.height = 256
		_veil = t
	return _veil


# —— A4/A5 覆盖层纹理（确定性：固定种子；懒生成缓存） ——

static var _grain: NoiseTexture2D = null
static var _vign: GradientTexture2D = null
static var _veil: GradientTexture2D = null


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


## 设置页滚动条：暗轨道 + 金滑块（默认主题灰条与金黑面板不合；宽 6S）。
static func scrollbar(scroll: ScrollContainer, C: Dictionary, S: float) -> void:
	var bar := scroll.get_v_scroll_bar()
	bar.custom_minimum_size.x = int(6.0 * S)
	var track := flat(C["track"], C["track"], int(3 * S), 0)
	bar.add_theme_stylebox_override("scroll", track)
	var grab := flat(C["gold_lo"], C["gold_lo"], int(3 * S), 0)
	bar.add_theme_stylebox_override("grabber", grab)
	var hl := flat(C["gold"], C["gold"], int(3 * S), 0)
	bar.add_theme_stylebox_override("grabber_highlight", hl)
	bar.add_theme_stylebox_override("grabber_pressed", hl)
