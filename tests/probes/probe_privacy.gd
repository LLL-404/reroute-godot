extends ProbeKit

# 隐私门探针（合规链路）：验证首启弹窗结构齐全，且「同意 / 拒绝」两条信号都真实可发。
# 合规要点：必须提供可真正退出的「不同意」路径（不能只有同意），因此拒绝链路单独断言。
# 运行：godot --headless -s res://tests/probes/probe_privacy.gd

const GATE_PATH := "res://game/privacy_gate.tscn"


func _initialize() -> void:
	var gate_scene = load(GATE_PATH)
	check(gate_scene != null, "privacy_gate.tscn 可加载")
	if gate_scene == null:
		finish("PRIVACY", 1)
		return

	# ---- 结构：三按钮 + 标题 + 正文 ----
	var g = gate_scene.instantiate()
	get_root().add_child(g)
	await process_frame
	await process_frame

	var btn_agree = g.find_child("btn_privacy_agree", true, false)
	var btn_decline = g.find_child("btn_privacy_decline", true, false)
	var btn_link = g.find_child("btn_privacy_link", true, false)
	check(btn_agree != null, "同意按钮存在")
	check(btn_decline != null, "拒绝按钮存在")
	check(btn_link != null, "隐私政策链接按钮存在")

	var title = g.find_child("title", true, false)
	check(title != null and String(title.text) == "隐私政策", "标题为「隐私政策」")

	var body = g.find_child("body", true, false)
	check(body != null and String(body.text).length() >= 120, "正文非空且含实质说明")

	# ---- 同意链路 ----
	var agreed: Array = [false]
	g.agreed.connect(func() -> void: agreed[0] = true)
	if btn_agree != null:
		btn_agree.pressed.emit()
	await process_frame
	check(agreed[0], "点「同意」发出 agreed 信号")

	# ---- 拒绝链路（重建实例：上一个已 queue_free）----
	var g2 = gate_scene.instantiate()
	get_root().add_child(g2)
	await process_frame
	await process_frame
	var declined: Array = [false]
	g2.declined.connect(func() -> void: declined[0] = true)
	var d2 = g2.find_child("btn_privacy_decline", true, false)
	check(d2 != null, "重建后拒绝按钮仍存在")
	if d2 != null:
		d2.pressed.emit()
	await process_frame
	check(declined[0], "点「不同意」发出 declined 信号")

	finish("PRIVACY", 9)
