extends CanvasLayer

# 核心低血警告（2026-10-21，体验细节 B 档）：屏幕边缘暗红渐晕，血量越低越浓、呼吸越急。
#
# 为什么独立成节点而不写进 hud.gd：
#   ① hud.gd 有外部并发写入史（改前必须重读），能外部驱动的就不要再写进去；
#   ② 渐晕属于屏幕后处理层，跟 HUD 的布局/安全区逻辑完全无关，混进去只会让 hud 更难改。
#
# 层级 9：压住 3D 场景，但在 HUD（10）之下 —— 警告只能染环境，不能染顶栏血条与按钮文字，
# 否则"血量越低越看不清血量"。
# 壳/暂停/结算（20+）压在两者之上，开菜单时警告不该还在闪。

const Sim = preload("res://sim/sim.gd")

const THRESHOLD := 0.35 # 血量比低于此值开始出现
const MAX_STRENGTH := 0.75 # 强度上限（血量趋 0 时）
const PULSE_HZ := 1.9 # 基准呼吸频率（Hz；越危险越快）

const SHADER_CODE := """
shader_type canvas_item;
render_mode unshaded;

uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(0.62, 0.06, 0.05, 1.0);
uniform float softness : hint_range(0.05, 0.6) = 0.14;

void fragment() {
	vec2 uv = UV - 0.5;
	// 椭圆化：宽屏时上下边缘比左右更早起晕，读起来更像镜头暗角而不是加了个边框
	vec2 e = uv * vec2(1.0, 1.35);
	float d = length(e);
	float v = smoothstep(0.5 - softness, 0.62, d);
	COLOR = vec4(tint.rgb, tint.a * v * strength);
}
"""

var _rect: ColorRect = null
var _mat: ShaderMaterial = null
var _strength := 0.0
var _t := 0.0
var _hp_max := 1


func _ready() -> void:
	layer = 9
	var sh := Shader.new()
	sh.code = SHADER_CODE
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_mat.set_shader_parameter("strength", 0.0)
	_rect = ColorRect.new()
	_rect.name = "Vignette"
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE # 绝不能吃掉点击：它盖满全屏
	_rect.material = _mat
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_rect)
	_hp_max = int(Sim.BUILDINGS[Sim.B_CORE - 1]["hp"])


## 每帧驱动。hp = 核心当前血量；suppressed = 标题/暂停/终局 → 立即淡出。
## 进快出慢：危险来得急（rate 6），解除要缓（rate 2.2），血量在阈值附近抖动时不会闪。
func update_hp(hp: int, dt: float, suppressed: bool) -> void:
	var target := 0.0
	if not suppressed and _hp_max > 0:
		var ratio := clampf(float(hp) / float(_hp_max), 0.0, 1.0)
		if ratio < THRESHOLD:
			target = MAX_STRENGTH * (THRESHOLD - ratio) / THRESHOLD
	var rate := 6.0 if target > _strength else 2.2
	_strength = move_toward(_strength, target, rate * dt)
	_t += dt * PULSE_HZ * (1.0 + _strength) # 越危险呼吸越急
	var pulse := 0.78 + 0.22 * sin(_t * TAU)
	_mat.set_shader_parameter("strength", _strength * pulse)


## 诊断态（探针断言用；生产无害）
func debug_state() -> Dictionary:
	return { "strength": _strength, "max_hp": _hp_max, "threshold": THRESHOLD }
