extends RefCounted

# 《改道》相机操作层：把鼠标 / 键盘 / 触摸手势翻译成相机意图。
# 只调用 view 暴露的 camera_* 转发接口；不引用 sim/，也不反向引用 main（单向依赖）。
# 「能否操控」（标题/暂停/结算冻结）由 main 注入；HUD 命中区判定仍留在 main。

const PAN_SPEED := 24.0 # WASD 平移速度（世界单位/秒）
const ROT_SPEED := 1.5 # Q/E 旋转速度（rad/s）
const KEYS := [KEY_W, KEY_A, KEY_S, KEY_D, KEY_Q, KEY_E] # 相机键（不参与对局操作）
const PINCH_STEP := 0.14 # 双指缩放单帧变化上限（防抖动跳变）
const ROT_DEADZONE := 0.04 # 双指旋转单帧死区（rad；滤手指抖动）
const ROT_LIMIT := 0.5 # 双指旋转单帧上限（rad；两指接近重合时角度噪声过大）
# 中键拖拽灵敏度（rad/px）：上下拖调俯仰、左右拖调偏航，方向都是「跟手」——
# 向下拖 = 俯角变大（更陡，看得到立面）；向右拖 = 场景顺时针转。
const PITCH_STEP := 0.005
const YAW_STEP := 0.005

var view = null # 视图门面（只需 camera_pan / camera_pan_pixels / camera_rotate / camera_zoom / update_shake）
var can_control: Callable # main._camera_free：标题/暂停/结算时冻结

var keys := {} # 按下的相机键（事件驱动，无 OS 轮询）
var panning := false # 右键拖拽平移中
var last := Vector2.ZERO # 右键拖拽上一帧位置（用位置差算位移，不依赖 relative）
var mmb := false # 中键拖拽中（上下俯仰 / 左右旋转）
var mmb_last := Vector2.ZERO # 中键拖拽上一帧位置
var g_prev := Vector2.ZERO # 双指上一帧中点
var g_dist := 1.0 # 双指上一帧间距
var g_ang := 0.0 # 双指上一帧连线夹角


## 组装注入：视图门面 + 能否操控判定（由 main 提供）。
func _init(p_view, p_can_control: Callable) -> void:
	view = p_view
	can_control = p_can_control


## 每帧推进：WASD 平移 / QE 旋转 / 震屏沉降（口径原样搬自 main._update_camera）。
## 震屏放最后：pan/rotate 各自会重摆相机，震动必须叠在它们之上，否则被覆盖。
func update(dt: float) -> void:
	if not can_control.call():
		return
	var mvx := 0.0
	var mvy := 0.0
	if keys.has(KEY_D):
		mvx += 1.0
	if keys.has(KEY_A):
		mvx -= 1.0
	if keys.has(KEY_W):
		mvy += 1.0
	if keys.has(KEY_S):
		mvy -= 1.0
	if mvx != 0.0 or mvy != 0.0:
		view.camera_pan(mvx, mvy, PAN_SPEED * dt)
	var rot := 0.0
	if keys.has(KEY_Q):
		rot += 1.0
	if keys.has(KEY_E):
		rot -= 1.0
	if rot != 0.0:
		view.camera_rotate(rot * ROT_SPEED * dt)
	view.update_shake(dt)


## 键盘按下：只记相机键（其余键由 main 的路由处理）。
func key_down(code: int) -> void:
	if KEYS.has(code):
		keys[code] = true


## 键盘抬起：无条件清除（与原实现一致，抬手事件不再向后续路由传播）。
func key_up(code: int) -> void:
	keys.erase(code)


## 右键按下/抬起：记录是否处于拖拽；HUD 区内不启动。位置始终刷新，
## 保证下次按下取的是本次落点（原实现同样在每次右键事件后写 rmb_last）。
func rmb_button(pressed: bool, pos: Vector2, hud_blocked: bool) -> void:
	panning = pressed and not hud_blocked
	last = pos


## 中键按下/抬起：记录是否处于拖拽；HUD 区或冻结态不启动。
## 位置始终刷新，保证下次按下取的是本次落点。
func mmb_button(pressed: bool, pos: Vector2, hud_blocked: bool) -> void:
	mmb = pressed and not hud_blocked and can_control.call()
	mmb_last = pos


## 鼠标移动：右键拖拽按像素差平移（抓取感：内容跟手）；中键拖拽叠俯仰 + 偏航。
## 两者互不清除状态，可同时生效。
func motion(pos: Vector2) -> void:
	if panning:
		var d := pos - last
		last = pos
		if d != Vector2.ZERO:
			view.camera_pan_pixels(d.x, d.y)
	if mmb:
		var dm := pos - mmb_last
		mmb_last = pos
		if dm != Vector2.ZERO:
			view.camera_pitch_by(dm.y * PITCH_STEP) # 向下拖 = 俯角变大（更陡）；向上拖 = 更平
			view.camera_rotate(dm.x * YAW_STEP) # 向右拖 = 场景顺时针转（跟手）


## 滚轮缩放一步：上滚 0.9 拉近 / 下滚 1.1 拉远；可用性与 HUD 排除由 main 判定。
func wheel_step(up: bool) -> void:
	view.camera_zoom(0.9 if up else 1.1)


## 双指基线（按手指 index 升序取前两根）。
func gesture_reset(points: Dictionary) -> void:
	var ks := points.keys()
	ks.sort()
	if ks.size() < 2:
		return
	var a: Vector2 = points[ks[0]]
	var b: Vector2 = points[ks[1]]
	g_prev = (a + b) * 0.5
	g_dist = maxf(a.distance_to(b), 1.0)
	g_ang = atan2(b.y - a.y, b.x - a.x)


## 双指增量：中点位移 = 平移；间距比 = 缩放（拉开 = 拉近）；连线转角 = 旋转。
## 单帧幅度都夹住，防抖（口径原样搬自 main._gesture_update）。
func gesture_update(points: Dictionary) -> void:
	var ks := points.keys()
	ks.sort()
	if ks.size() < 2:
		return
	var a: Vector2 = points[ks[0]]
	var b: Vector2 = points[ks[1]]
	var c := (a + b) * 0.5
	var d := maxf(a.distance_to(b), 1.0)
	var ang := atan2(b.y - a.y, b.x - a.x)
	if can_control.call():
		var dp := c - g_prev
		if dp != Vector2.ZERO:
			view.camera_pan_pixels(dp.x, dp.y)
		var r := clampf(d / g_dist, 1.0 - PINCH_STEP, 1.0 + PINCH_STEP)
		if absf(r - 1.0) > 0.002:
			view.camera_zoom(1.0 / r) # 间距变大 = 拉近
		var da := wrapf(ang - g_ang, -PI, PI)
		if absf(da) > ROT_DEADZONE and absf(da) < ROT_LIMIT:
			view.camera_rotate(da)
	g_prev = c
	g_dist = d
	g_ang = ang
