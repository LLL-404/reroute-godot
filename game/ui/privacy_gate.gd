extends CanvasLayer

# 隐私政策首启门（PrivacyGate）：冷启动、任何本地数据读写之前展示，用户明确同意后才进入游戏。
# 合规口径（对齐国内应用市场「安装包隐私合规检测」常见必查项）：
#   ① 同意之前不创建 HUD / 界面壳 / 开屏动画，也不读写 user://settings.cfg（本层不引用 UserSettings）；
#   ② 必须提供「不同意」路径且可真正退出，不允许只能同意；
#   ③ 完整隐私政策可跳转浏览器查看（独立网页，非站内页）；
#   ④ 同意结果由 main 持久化到 user://settings.cfg 的 privacy/agreed，下次启动不再弹。
# 层级 40：高于开屏 intro(30) / 壳(20) / HUD(10)；未同意时 main 根本不建那三层。
# 本文件不使用 class_name；调用方以 load("res://game/ui/privacy_gate.gd") 引用。

signal agreed
signal declined

const F_SANS: FontFile = preload("res://assets/fonts/NotoSansSC-Regular.otf")
const PRIVACY_URL := "https://lll-404.github.io/reroute-privacy/privacy.html"

const COL_BG := Color8(10, 12, 14)
const COL_CARD := Color8(24, 28, 32)
const COL_EDGE := Color8(200, 168, 108)
const COL_GOLD := Color8(224, 198, 140)
const COL_TEXT := Color8(216, 212, 202)
const COL_MUTED := Color8(150, 144, 130)
const COL_OK := Color8(96, 255, 208)

const BODY := """《改道》是一款离线单机游戏，不需要联网即可游玩。

【我们收集的信息】
本游戏不收集、不上传任何个人信息。你在游戏内的设置、存档与游玩局数仅保存在本机，不会离开你的设备。

【第三方服务】
游戏内未接入任何第三方统计、广告、登录或支付 SDK。

【权限说明】
游戏运行不需要通讯录、位置、相机、麦克风、存储读写等敏感权限。

【你的权利】
你可以随时在「设置 → 隐私政策」查看完整说明。卸载游戏即删除全部本地数据。

点击「同意并继续」，表示你已阅读并同意《隐私政策》。"""

var _card_w := 560.0
var _root: Control = null


## 层级 40：整屏覆盖，压过开屏与所有界面
func _init() -> void:
	layer = 40


func _ready() -> void:
	_bind()


## 绑定场景骨架（privacy_gate.tscn）：只取引用、注入样式与尺寸、接线，不再建结构
func _bind() -> void:
	_root = $PrivacyRoot
	var bg: ColorRect = _root.get_node("bg")
	bg.color = COL_BG

	var card: PanelContainer = _root.get_node("CenterContainer/card")
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_CARD
	sb.border_color = COL_EDGE
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(28)
	card.add_theme_stylebox_override("panel", sb)
	_card_w = clampf(_viewport_size().x * 0.86, 320.0, 560.0)
	card.custom_minimum_size = Vector2(_card_w, 0)

	var box: VBoxContainer = card.get_node("VBoxContainer")
	box.add_theme_constant_override("separation", 14)

	var title: Label = box.get_node("title")
	_style_label(title, 26, COL_GOLD)

	var rule: ColorRect = box.get_node("ColorRect")
	rule.color = COL_EDGE
	rule.custom_minimum_size = Vector2(0, 1)

	var body: Label = box.get_node("body")
	body.text = BODY # 长正文属内容数据，留脚本常量，避免与场景双源漂移
	body.custom_minimum_size = Vector2(_card_w - 56.0, 0)
	_style_label(body, 14, COL_TEXT)

	var link: Button = box.get_node("btn_privacy_link")
	_style_button(link, false)
	link.pressed.connect(_on_open_link)

	var agree: Button = box.get_node("btn_privacy_agree")
	_style_button(agree, true)
	agree.pressed.connect(_on_agree)

	var decline: Button = box.get_node("btn_privacy_decline")
	_style_button(decline, false)
	decline.pressed.connect(_on_decline)


## 视口尺寸：优先 DisplayServer 实际窗口（_ready 时 viewport 可能还没跟着窗口刷新），
## 过小则回退 1280×720，避免卡片被压到最小宽度。
func _viewport_size() -> Vector2:
	var vp := get_viewport()
	var s := Vector2.ZERO
	if vp != null:
		s = vp.get_visible_rect().size
	if s.x < 480.0 or s.y < 320.0:
		var ws := DisplayServer.window_get_size()
		if ws.x >= 480 and ws.y >= 320:
			s = Vector2(ws)
	if s.x <= 0.0 or s.y <= 0.0:
		return Vector2(1280, 720)
	return s


## 统一字体与颜色
func _style_label(l: Label, size: int, col: Color) -> void:
	l.add_theme_font_override("font", F_SANS)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)


## 注入按钮样式：primary = 金底深字，否则描边暗底（节点与文案由场景承载）
func _style_button(b: Button, primary: bool) -> void:
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 44 if primary else 38)
	b.add_theme_font_override("font", F_SANS)
	b.add_theme_font_size_override("font_size", 16 if primary else 14)

	var normal := StyleBoxFlat.new()
	normal.set_corner_radius_all(4)
	normal.set_border_width_all(1)
	if primary:
		normal.bg_color = COL_EDGE
		normal.border_color = COL_GOLD
		b.add_theme_color_override("font_color", Color8(18, 20, 22))
		b.add_theme_color_override("font_hover_color", Color8(18, 20, 22))
		b.add_theme_color_override("font_pressed_color", Color8(18, 20, 22))
	else:
		normal.bg_color = Color8(0, 0, 0, 0)
		normal.border_color = Color8(90, 86, 78)
		b.add_theme_color_override("font_color", COL_MUTED)
		b.add_theme_color_override("font_hover_color", COL_TEXT)
		b.add_theme_color_override("font_pressed_color", COL_OK)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = COL_GOLD if primary else Color8(255, 255, 255, 12)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = COL_OK if primary else Color8(96, 255, 208, 24)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


## 打开完整隐私政策（外部浏览器；无浏览器时静默失败，不阻断流程）
func _on_open_link() -> void:
	if OS.has_method("shell_open"):
		OS.shell_open(PRIVACY_URL)


## 同意：发信号，由 main 落盘并继续启动
func _on_agree() -> void:
	agreed.emit()
	_close()


## 不同意：发信号，由 main 退出应用
func _on_decline() -> void:
	declined.emit()


func _close() -> void:
	if is_instance_valid(_root):
		_root.queue_free()
	queue_free()


## 拒绝 Android 返回键关闭（必须显式二选一）
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		pass
