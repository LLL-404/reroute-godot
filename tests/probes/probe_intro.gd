extends ProbeKit

## 开屏动画探针（窗口模式）：门控（探针模式零出现）+ intro 状态机（确定性相位/吞输入/跳过/自毁）
## + 性能口径（首拍预热帧 / 主世界停画与恢复 / 隐藏态退出安全网）。
## 判定：exit 0 + stdout 含 `[INTRO] PASS`。跑法：godot --path <P> -s res://tests/probes/probe_intro.gd

const IntroScene = preload("res://game/ui/intro.tscn")

var main = null


func _initialize() -> void:
	# ---- A. 门控：探针模式下 main 不建 intro（21 闸既有探针的零影响证明）----
	var packed: PackedScene = load("res://game/app/main.tscn")
	main = packed.instantiate()
	get_root().add_child(main)
	for _i in 5:
		await process_frame # -s 模式 _ready 在首帧才跑
	main.set_process(false)
	check(main._intro == null, "探针模式下 main 无 intro 实例")
	check(main._intro_enabled() == false, "探针模式 _intro_enabled()==false")
	check(main.shell.current_page() == "title", "启动即标题（口经不变）")
	var sh_dec: GDScript = load("res://game/ui/intro.gd")
	check(sh_dec != null, "intro.gd 装载成功")
	main.free()

	# ---- B. 直接实例化 Intro：手动喂 dt，断言相位阶梯 ----
	var intro = IntroScene.instantiate()
	get_root().add_child(intro)
	intro.set_process(false) # 探针独占推进（确定性 dt）
	var snd_calls: Array = []
	intro.begin(Callable(self, "_fake_sfx").bind(snd_calls), {})
	check(intro._sub != null, "子视口建好")
	check(intro._sub.render_target_update_mode == SubViewport.UPDATE_DISABLED, "P0 不渲染（省全屏）")
	check(intro._black.color.a == 1.0, "P0 全黑幕")

	# t=0.3（P0 中段）：黑场不变、渲染仍关、无声（SFX 在 P2 击点前也 OK——本 stinger 进场即放）
	await _drive(intro, 0.3)
	check(intro.phase() == 0, "t=0.3 P0")
	check(intro._sub.render_target_update_mode == SubViewport.UPDATE_DISABLED, "P0 渲染仍关")

	# t=0.3→0.9（P1 前段）：渲染开启、晶房在转、光强爬升、黑幕开始退
	await _drive(intro, 0.6)
	check(intro.phase() == 1, "t=0.9 P1")
	check(intro._sub.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "P1 起渲染常开")
	var y0: float = (intro._sub.get_meta("crystal") as Node3D).rotation.y
	await _drive(intro, 0.4)
	var y1: float = (intro._sub.get_meta("crystal") as Node3D).rotation.y
	check(y1 > y0, "晶体在转 (%.3f→%.3f)" % [y0, y1])
	check((intro._sub.get_meta("key") as DirectionalLight3D).light_energy > 0.0, "key 光已升")
	check(intro._black.color.a < 1.0, "黑幕已开始退")

	# t 前进至 P2（金字起）：渲染截图存证
	await _drive(intro, 0.55) # t≈1.85 P2 初
	check(intro.phase() >= 2, "进入 P2 金字段")
	check((intro._char_labels[0] as CanvasItem).visible, "首字可见")
	var mid_png := get_root().get_texture().get_image()
	check(mid_png != null and mid_png.get_width() > 0, "可取帧")
	mid_png.save_png("res://shots/_tmp_intro_p2.png")

	# t 前进至 P3（标语+金线满）
	await _drive(intro, 0.75)
	check(intro.phase() == 3, "进入 P3 标语段")
	check((intro._tagline as CanvasItem).visible, "标语可见")
	check((intro._rule as CanvasItem).visible, "金线可见")
	check(absf(intro._rule.size.x) > 0.0 or absf(intro._rule.offset_left) < 0.0, "金线已展开")
	var p3_png := get_root().get_texture().get_image()
	p3_png.save_png("res://shots/_tmp_intro_p3.png")

	# ---- C. 吞输入 + 跳过：任意键 → 快速收尾自毁 ----
	check(intro.skipping == false, "未触发跳过")
	var ev := InputEventKey.new()
	ev.keycode = KEY_SPACE
	ev.pressed = true
	get_root().push_input(ev)
	await process_frame
	check(intro.skipping == true, "按键→触发跳过")
	await _drive(intro, 0.02) # 25× 快进 → t≈3.1 ∈ (T_P4, DUR)：落 P4 快收段且仍存活
	check(intro.phase() == 4, "跳过落 P4 快收段")
	await _drive(intro, 0.5)
	var gone := not is_instance_valid(intro)
	check(gone, "跳过后快速自毁")

	# ---- D. 不跳过路径：自动结束 ----
	var intro2 = IntroScene.instantiate()
	get_root().add_child(intro2)
	intro2.set_process(false)
	intro2.begin(Callable(), {})
	await _drive(intro2, DUR_AUTO + 0.05)
	var gone2 := not is_instance_valid(intro2)
	check(gone2, "无输入 t>DUR 自动自毁")

	# ---- E. 预热帧语义：首拍 UPDATE_ONCE（黑幕盖着编译），次拍回关 ----
	var intro3 = IntroScene.instantiate()
	get_root().add_child(intro3)
	intro3.set_process(false)
	intro3.begin(Callable(), {})
	check(intro3._sub.render_target_update_mode == SubViewport.UPDATE_DISABLED, "预热前：P0 关")
	intro3._process(1.0 / 60.0)
	check(intro3._sub.render_target_update_mode == SubViewport.UPDATE_ONCE, "首拍：预热一帧")
	intro3._process(1.0 / 60.0)
	check(intro3._sub.render_target_update_mode == SubViewport.UPDATE_DISABLED, "预热后：回关")
	intro3.free()

	# ---- F. 主世界停画：第 1 拍可见（暖机帧）→ 第 2 拍隐藏 → 安全网/T_P3 恢复 ----
	var main2: Node = load("res://game/app/main.tscn").instantiate()
	get_root().add_child(main2)
	for _i in 5:
		await process_frame
	main2.set_process(false)
	var intro4 = IntroScene.instantiate()
	main2.add_child(intro4)
	intro4.set_process(false)
	intro4.begin(Callable(), {})
	check(intro4._world == main2.view, "挂到主世界 3D 根（main.view）")
	intro4._process(1.0 / 60.0)
	check(main2.view.visible, "第 1 拍主世界仍可见（暖机帧）")
	intro4._process(1.0 / 60.0)
	check(not main2.view.visible, "第 2 拍起主世界停画")
	intro4.free()
	check(main2.view.visible, "隐藏态退出→安全网恢复世界")
	var intro5 = IntroScene.instantiate()
	main2.add_child(intro5)
	intro5.set_process(false)
	intro5.begin(Callable(), {})
	intro5._process(1.0 / 60.0)
	intro5._process(1.0 / 60.0)
	check(not main2.view.visible, "二次实例第 2 拍同样停画")
	await _drive(intro5, 2.6) # t≈2.63 ≥ T_P3
	check(intro5.phase() == 3, "推进到 P3")
	check(main2.view.visible, "T_P3 主世界恢复渲染")
	intro5.free()
	main2.free()

	# ---- 汇总 ----
	finish("INTRO", 36, "")


## 手动推进 dt（确定性）：固定 60Hz 喂 _process，不依赖真实帧时。
func _drive(intro, dt: float) -> void:
	var n := int(round(dt * 60.0))
	for _i in n:
		intro._process(1.0 / 60.0)
	await process_frame # 渲染一帧让 SubViewport 出图


## 假 SFX：只记调用（探针无音频侧）。
func _fake_sfx(snd: String, gain: float, calls: Array) -> void:
	calls.append([snd, gain])


const DUR_AUTO := 3.4 # 与 intro.gd DUR 对齐（探针断言自动结束用）
