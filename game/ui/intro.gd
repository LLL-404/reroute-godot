extends CanvasLayer

# 开屏动画（Intro）：3D 核心晶体特写 → 「改道」金字 → 揭示标题屏。
# 冷启动仅播一次（main._ready 尾部挂接）；探针/selfcheck/headless 自动跳过（main 门控）。
# 确定性状态机：不用 Tween——_process(dt) 累加 t，一切 alpha/位置/转速/光强由 t 解析求值，
# skip 只改推进速率；probe_intro 可 set_process(false) 后手动喂固定 dt 精确断言相位。
# 硬上限 DUR_MAX=4.0（用户口径：动画 4 秒以内）；本设计终值 DUR=3.4s。
# 性能口径（2026-10-17 提速）：① 主世界停画（第 1 帧暖机后隐藏，T_P3 恢复）；
# ② 子视口 0.7× 降分辨率拉伸；③ 首拍预热一帧（材质/泛光管线编译藏进黑场）。

const ModelsScript = preload("res://game/view/models.gd")
const UiStyle = preload("res://game/ui/ui_style.gd")
const F_SERIF: FontFile = preload("res://assets/fonts/NotoSerifSC-Bold-Sub.ttf")
const F_SANS: FontFile = preload("res://assets/fonts/NotoSansSC-Regular.otf")

# 相位边界（累计秒）：P0 黑场辉光 → P1 晶体浮现 → P2 金字+金线 → P3 副标语 → P4 淡出
const T_P1 := 0.5
const T_P2 := 1.8
const T_P3 := 2.5
const T_P4 := 2.8
const DUR := 3.4
const DUR_MAX := 4.0
const SKIP_FAST := 25.0 # skip 后时间快进倍率（剩余淡出 <0.2s 压完）
const UI_FADE := 0.6 # P4 整体淡出时长（解析引用 DUR-T_P4，勿改两者不一致）
const SUB_SCALE := 0.7 # 子视口渲染分辨率倍率（软画场景：晶体/泛光/金尘；3D pass 像素省 ~51%）

const COL_JADE := Color8(96, 255, 208)
const COL_GOLD_HI := Color8(224, 198, 140)
const COL_GOLD := Color8(200, 168, 108)
const COL_MUTED := Color8(176, 164, 132)
const CRYSTAL_H := 1.8 # 取景目标高（世界单位；相机 fov45 距 3.3 时占屏高约 68%）
const YAW_SPEED := 0.32 # rad/s

var t := 0.0 # 状态机累计时间（探针可读/手动推进）
var skipping := false # 已触发跳过
var done := false # queue_free 已发出
var on_done := Callable() # 释放回调（main 清引用；探针可空）

var _root: Control = null
var _black: ColorRect = null
var _tex: TextureRect = null
var _sub: SubViewport = null
var _char_labels: Array = [] # 「改」「道」逐字 Label（绝对定位，非容器——容器会顶掉 y 动画）
var _char_base_y: Array[float] = [] # 逐字驻点 y（浮现动画在其上做 -8px 升起）
var _rule: ColorRect = null
var _tagline: Label = null
var _old_mouse: int = -1
var _vp_w := 1280
var _vp_h := 720
var _dark: Dictionary = {} # 色板（外部注入 hud.DARK；缺 key 回退内置默认）
var _world: Node3D = null # 主世界 3D 挂点（main.view；探针直挂 root 时为 null → 停画逻辑跳过）
var _world_hidden := false # 当前是否处于主世界停画窗口
var _prewarmed := false # 首拍预热帧已下发
var _ticks := 0 # _process 拍数（第 2 拍起停画主世界）


## 初始化：层级 30（HUD 10 / 壳 20 之上，整屏覆盖）
func _init() -> void:
	layer = 30 # HUD(10) / 壳(20) 之上，整屏覆盖


## 构建并开始（main 传 sfx 播放回调与色板；probe 可只传其一）。
func begin(sfx_cb: Callable = Callable(), dark: Dictionary = {}) -> void:
	_dark = dark
	var vw := get_viewport().get_visible_rect().size
	if vw.x > 1.0 and vw.y > 1.0:
		_vp_w = int(vw.x)
		_vp_h = int(vw.y)

	# 主世界 3D 挂点：main.view（Node3D）。停画不在 begin 立即做——第 1 帧留给它把
	# 材质/阴影管线编译进启动帧（口径如旧），第 2 拍起隐藏（_process）。
	var hp := get_parent()
	if hp != null:
		var w = hp.get("view")
		if w is Node3D:
			_world = w

	_root = $IntroRoot
	_tex = _root.get_node("IntroTex")
	_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tex.stretch_mode = TextureRect.STRETCH_SCALE # 子视口 0.7× 拉伸回全屏（默认线性过滤）
	_black = _root.get_node("IntroBlack")
	_black.color = Color(0.0, 0.0, 0.0, 1.0)
	_sub = _root.get_node("IntroWorld")
	_sub.size = Vector2i(maxi(1, int(float(_vp_w) * SUB_SCALE)), maxi(1, int(float(_vp_h) * SUB_SCALE)))
	_sub.render_target_update_mode = SubViewport.UPDATE_DISABLED # 首拍 _process 预热一帧后回关，P1 起常开
	_build_3d()
	_tex.texture = _sub.get_texture()

	_bind_ui()

	if not sfx_cb.is_null():
		sfx_cb.call("intro_stinger.mp3", 0.9)


## 构建 3D 子场景：晶体 + 固定机位 + 三灯 + 环境泛光 + 玉色光团 + 金尘（meta 寄存供 _process 驱动）
func _build_3d() -> void:
	var world := Node3D.new()
	world.name = "World"
	_sub.add_child(world)

	# 晶体：等比缩放到目标高 + 包围盒居中（口径同 spawn_building core；本机位固定 LOD0）
	var models = ModelsScript.new()
	var packed := models.scene(ModelsScript.BUILDING_SCENES["core"])
	var inst: Node3D = packed.instantiate()
	var box := models.mesh_aabb(inst)
	models.bind_lod(inst, 0.5 * CRYSTAL_H) # 裸实例化只显 LOD0
	var u: float = CRYSTAL_H / box.size.y
	var wrap := Node3D.new()
	wrap.name = "Crystal"
	wrap.add_child(inst)
	inst.scale = Vector3(u, u, u)
	var c := box.get_center()
	inst.position = Vector3(-c.x * u, -box.position.y * u, -c.z * u)
	world.add_child(wrap)
	_sub.set_meta("crystal", wrap)

	# 相机：固定机位轻推近（z 3.3 → 2.9）
	var cam := Camera3D.new()
	cam.fov = 45.0
	world.add_child(cam)
	cam.current = true
	_sub.set_meta("cam", cam)

	# 灯光三件：暖金 key + 晶体内部玉光 + 金色背光（energy 由 _process 按 t 解析）
	var key := DirectionalLight3D.new()
	key.light_color = Color8(255, 235, 200)
	key.rotation_degrees = Vector3(-38.0, 42.0, 0.0)
	world.add_child(key)
	_sub.set_meta("key", key)

	var inner := OmniLight3D.new()
	inner.light_color = COL_JADE
	inner.omni_range = 5.0
	inner.position = Vector3(0.0, 0.5, 0.0)
	world.add_child(inner)
	_sub.set_meta("inner", inner)

	var back := OmniLight3D.new()
	back.light_color = Color8(255, 200, 120)
	back.omni_range = 6.0
	back.position = Vector3(0.4, 1.2, -2.2)
	world.add_child(back)
	_sub.set_meta("back", back)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.0, 0.0, 0.0)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.18, 0.2, 0.2)
	e.ambient_light_energy = 0.18
	e.glow_enabled = true
	e.glow_intensity = 0.8
	e.glow_bloom = 0.12
	e.glow_hdr_threshold = 1.1 # 高阈值：只有晶体亮部泛光，黑场不被抬亮
	env.environment = e
	world.add_child(env)

	# 玉色光环（兜底辉光，渲染器无关）：运行时烘焙径向 Image（GradientTexture2D 径向
	# alpha 在 Sprite3D 上实测不衰减成硬边矩形，弃用），平方衰减软光团 + 加法混合
	var halo := Sprite3D.new()
	var him := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	var hc := Vector2(64.0, 64.0)
	for hy in 128:
		for hx in 128:
			var hd: float = (Vector2(hx + 0.5, hy + 0.5) - hc).length() / 64.0
			var ha := clampf(1.0 - hd, 0.0, 1.0)
			him.set_pixel(hx, hy, Color(1.0, 1.0, 1.0, ha * ha))
	halo.texture = ImageTexture.create_from_image(him)
	halo.pixel_size = 0.010 # 128px → 1.28m 基座（晶体后的小软光团）
	halo.shaded = false
	halo.transparent = true
	halo.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	halo.modulate = COL_JADE
	halo.position = Vector3(0.0, 0.6, -0.35)
	world.add_child(halo)
	_sub.set_meta("halo", halo)

	# 金尘上扬（CPU 粒子：GL 兼容口径）
	var dust := CPUParticles3D.new()
	dust.amount = 96
	dust.lifetime = 1.6
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	dust.emission_box_extents = Vector3(1.4, 1.4, 0.9)
	dust.direction = Vector3(0, 1, 0)
	dust.spread = 12.0
	dust.gravity = Vector3(0, 0.25, 0)
	dust.initial_velocity_min = 0.16
	dust.initial_velocity_max = 0.42
	dust.scale_amount_min = 0.012
	dust.scale_amount_max = 0.03
	dust.color = COL_GOLD
	dust.position = Vector3(0.0, 0.4, 0.2)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	dm.vertex_color_use_as_albedo = true
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	quad.material = dm
	dust.mesh = quad
	world.add_child(dust)
	_sub.set_meta("dust", dust)


## 绑定场景骨架（intro.tscn）：只取引用、注入色/字体/字号（S 缩放）与锚点，不建结构。
## 逐字用绝对定位（不用容器——容器每帧重排会顶掉位置动画）。
func _bind_ui() -> void:
	var ui: Control = _root.get_node("IntroUi")
	var s := _S()

	# 金线（先绑，_layout_chars 要摆它）
	_rule = ui.get_node("GoldRule")
	_rule.color = UiStyle.RULE
	_rule.anchor_left = 0.5
	_rule.anchor_right = 0.5
	_rule.anchor_top = 0.655
	_rule.anchor_bottom = 0.655
	_rule.offset_top = 0.0
	_rule.offset_bottom = 2.0
	_rule.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_rule.offset_left = 0.0
	_rule.offset_right = 0.0

	# 副标语（静态文案在场景里）
	_tagline = ui.get_node("Tagline")
	_tagline.add_theme_font_override("font", F_SANS)
	_tagline.add_theme_font_size_override("font_size", int(13.0 * s))
	_tagline.add_theme_color_override("font_color", _col("muted"))
	_tagline.anchor_left = 0.5
	_tagline.anchor_right = 0.5
	_tagline.anchor_top = 0.70
	_tagline.anchor_bottom = 0.70
	_tagline.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_tagline.grow_vertical = Control.GROW_DIRECTION_BOTH
	_tagline.modulate.a = 0.0

	# 衬线逐字（场景只存两个静态字，字号随 S 运行时注入）
	for i in 2:
		var lbl: Label = ui.get_node("Char%d" % (i + 1))
		lbl.add_theme_font_override("font", F_SERIF)
		lbl.add_theme_font_size_override("font_size", int(76.0 * s))
		lbl.add_theme_color_override("font_color", _col("gold_hi"))
		lbl.modulate.a = 0.0
		_char_labels.append(lbl)
	_layout_chars()
	for i in _char_labels.size():
		_char_base_y.append((_char_labels[i] as Label).position.y)


## 标题逐字布局：衬线子集无空格字形 → 手动字距；金线与副标语同步定位
func _layout_chars() -> void:
	var s := _S()
	var gap := 26.0 * s
	var total := 0.0
	var ws: Array[float] = []
	for lbl in _char_labels:
		var w: float = (lbl as Label).get_minimum_size().x
		ws.append(w)
		total += w
	total += gap * float(_char_labels.size() - 1)
	var x := float(_vp_w) * 0.5 - total * 0.5
	for i in _char_labels.size():
		var lbl: Label = _char_labels[i]
		lbl.position = Vector2(x, float(_vp_h) * 0.585 - lbl.get_minimum_size().y * 0.5)
		x += ws[i] + gap
	var w := 260.0 * s
	_rule.anchor_left = 0.5
	_rule.offset_left = -w * 0.5
	_rule.offset_right = w * 0.5
	_rule.position.y = float(_vp_h) * 0.655
	_tagline.position.x = float(_vp_w) * 0.5 - _tagline.get_minimum_size().x * 0.5
	_tagline.position.y = float(_vp_h) * 0.70 - _tagline.get_minimum_size().y * 0.5


## 色板：外部注入（hud.DARK）优先，缺 key 回退内置默认。
func _col(k: String) -> Color:
	if _dark.has(k) and _dark[k] is Color:
		return _dark[k]
	if k == "gold_hi":
		return COL_GOLD_HI
	if k == "muted":
		return COL_MUTED
	return COL_GOLD


## 全局缩放系数：按视口高换算（816 基准，钳 1.0..1.6）
func _S() -> float:
	return clampf(float(_vp_h) / 816.0, 1.0, 1.6)


## 当前相位 0..4：P0 黑场 / P1 晶体 / P2 金字 / P3 标语 / P4 淡出（探针断言用）
func phase() -> int:
	# 0..4：P0 黑场 / P1 晶体 / P2 金字 / P3 标语 / P4 淡出（skip 语义归 P4）
	if t < T_P1:
		return 0
	if t < T_P2:
		return 1
	if t < T_P3:
		return 2
	if t < T_P4:
		return 3
	return 4


## 全局淡出系数（P4 与跳过共用）：skip 把剩余淡出压缩进 SKIP_FAST 速率。
func _out_alpha() -> float:
	if skipping:
		return 1.0 - clampf(t - T_P4, 0.0, 1.0)
	return 1.0 - clampf((t - T_P4) / (DUR - T_P4), 0.0, 1.0)


## 状态机主拍：t 推进（skip 25× 快进）→ 主世界停画窗口 → 字/线/标语/黑幕按 t 解析 → 3D 灯光/转速/推近 → DUR 释放
func _process(dt: float) -> void:
	if done:
		return
	_ticks += 1
	var step := minf(dt, 0.1) # 钳制长停滞（首帧管线编译/系统卡顿）：相位不跳拍
	if skipping:
		t += step * SKIP_FAST # 快进：剩余淡出按 25× 速率压缩
	else:
		t += step
	t = minf(t, DUR_MAX)

	# 主世界停画窗口：第 2 拍起隐藏（第 1 帧留它暖机，编译进启动帧），T_P3 恢复——
	# 恢复后的首帧重绘/阴影全部盖在开屏底下，P4 揭示时已是熟帧。探针直挂时 _world=null 全跳过。
	if _world != null:
		if _ticks == 2: # 单次触发：第 1 帧暖机后隐藏，避免恢复后再次命中
			_world.visible = false
			_world_hidden = true
		elif _world_hidden and t >= T_P3:
			_world.visible = true
			_world_hidden = false

	# 字/线/标语的几何按 t 解析；skip 时 out 直接压到 0，视觉瞬时收尾
	var out := _out_alpha()
	var chars_on := t >= T_P2 and _char_labels.size() == 2
	for i in _char_labels.size():
		var lbl: Label = _char_labels[i]
		lbl.visible = t >= T_P2
		if lbl.visible:
			var a := clampf((t - T_P2 - 0.12 * i) / 0.35, 0.0, 1.0)
			lbl.modulate.a = a * out
			lbl.position.y = _char_base_y[i] - a * 8.0
	if skipping and _char_labels.size() > 0:
		(_char_labels[0] as Label).visible = t < DUR # skip 后立即随 out 隐去
	# 金线：宽度自中心展开（P2..P3）
	if _rule != null:
		_rule.visible = t >= T_P2 and not done
		var st := clampf((t - T_P2) / (T_P3 - T_P2), 0.0, 1.0)
		_rule.offset_left = -130.0 * _S() * st
		_rule.offset_right = 130.0 * _S() * st
		_rule.modulate.a = st * out
	if _tagline != null:
		_tagline.visible = t >= T_P3
		if _tagline.visible:
			_tagline.modulate.a = clampf((t - T_P3) / 0.35, 0.0, 1.0) * out
	if _tex != null:
		_tex.modulate.a = out
	if _black != null:
		# P1 起黑幕 1→0（晶体自黑暗浮现）；skip/结束段由 out 接管
		var b := 1.0
		if t >= T_P1:
			b = 1.0 - clampf((t - T_P1) / (T_P3 - T_P1), 0.0, 1.0)
		_black.color.a = minf(b, out)

	# 3D：预热/渲染开关/光强/转速/推近（P1 起）
	if _sub != null:
		if t >= T_P1:
			_sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		elif not _prewarmed:
			_prewarmed = true # 首拍预热一帧（黑幕盖着）：晶体材质/泛光管线在 P1 前编译完
			_sub.render_target_update_mode = SubViewport.UPDATE_ONCE
		else:
			_sub.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if t >= T_P1:
		var k := clampf((t - T_P1) / (T_P3 - T_P1), 0.0, 1.0) # 浮现进度
		(_sub.get_meta("key") as DirectionalLight3D).light_energy = 0.8 * k
		(_sub.get_meta("inner") as OmniLight3D).light_energy = 2.6 * k
		(_sub.get_meta("back") as OmniLight3D).light_energy = 0.95 * k
		var halo := _sub.get_meta("halo") as Sprite3D
		halo.scale = Vector3.ONE * (1.0 + 0.4 * k)
		var hm := halo.modulate
		hm.a = 0.3 * k * out
		halo.modulate = hm
		var crystal: Node3D = _sub.get_meta("crystal")
		crystal.rotation.y = YAW_SPEED * (t - T_P1)
		var cam := _sub.get_meta("cam") as Camera3D
		var d := 3.3 - 0.4 * clampf((t - T_P1) / (T_P4 - T_P1), 0.0, 1.0)
		cam.look_at_from_position(Vector3(0.0, 0.9, d), Vector3(0.0, 0.72, 0.0), Vector3.UP)

	if t >= DUR:
		done = true
		if not on_done.is_null():
			on_done.call()
		queue_free()


## 入树：桌面隐藏鼠标（移动端保留触摸指针语义）
func _enter_tree() -> void:
	_old_mouse = int(Input.mouse_mode)
	if not (OS.has_feature("android") or OS.has_feature("ios")):
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN


## 退树：还原鼠标模式 + 安全网恢复主世界渲染（任何退出路径）
func _exit_tree() -> void:
	if _old_mouse >= 0:
		Input.mouse_mode = _old_mouse
	_old_mouse = -1
	# 安全网：任何路径退出（跳过收尾/外部强杀）都必须恢复主世界渲染
	if _world != null and is_instance_valid(_world) and not _world.visible:
		_world.visible = true


## 输入总吞：任意按键/点击/触摸 → 触发跳过；鼠标移动不触发。
## 吞入口径 = _input（早于 GUI 与 _unhandled_input），main 原输入链完全收不到。
func _input(event: InputEvent) -> void:
	var hit := false
	if event is InputEventMouseButton and event.pressed:
		hit = true
	elif event is InputEventKey and event.pressed and not event.echo:
		hit = true
	elif event is InputEventScreenTouch and event.pressed:
		hit = true
	if hit:
		skipping = true
		get_viewport().set_input_as_handled()
