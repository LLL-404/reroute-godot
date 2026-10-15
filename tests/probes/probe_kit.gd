class_name ProbeKit
extends SceneTree

# 探针公共夹具（D5-2 统一）：断言收集 + 统一收口输出。
# 用法：探针 `extends ProbeKit`；正文用 check/cmp_int/cmp_approx/cmp_v3/cmp_rect 断言、
# fail() 报无条件失败；末尾 finish(TAG[, min_checks[, extra]]) 统一输出并退出。
#
# 统一输出协议（收尾固定）：
#   [TAG] checks=N bad=M [extra]
#   [TAG] fail: <msg>（最多 12 条，仅失败时）
#   [TAG] PASS | [TAG] FAIL
# 退出码：0 = PASS，1 = FAIL。min_checks 为断言数下限（结构性护栏，缺省 0）；
# 不足时按失败收口（不虚报 bad 数，仅追加一条 fail 说明）。

const FAIL_SHOW_MAX := 12

var checks := 0 # 已执行断言数
var bad := 0 # 失败断言数
var fail_list: Array = [] # 失败信息（收口时统一打印）


## 布尔断言。
func check(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		bad += 1
		fail_list.append(what)


## 无条件失败（不占断言数）。
func fail(what: String) -> void:
	bad += 1
	fail_list.append(what)


## 整数相等。
func cmp_int(got: int, want: int, what: String) -> void:
	checks += 1
	if got != want:
		bad += 1
		fail_list.append(what + " got=%d want=%d" % [got, want])


## 浮点近似相等（is_equal_approx）。
func cmp_approx(got: float, want: float, what: String) -> void:
	checks += 1
	if not is_equal_approx(got, want):
		bad += 1
		fail_list.append(what + " got=%.4f want=%.4f" % [got, want])


## Vector3 逐轴 0.01 容差。
func cmp_v3(got: Vector3, want: Vector3, what: String) -> void:
	checks += 1
	if absf(got.x - want.x) > 0.01 or absf(got.y - want.y) > 0.01 or absf(got.z - want.z) > 0.01:
		bad += 1
		fail_list.append(what + " got=%s want=%s" % [str(got), str(want)])


## Rect2 逐边 0.01 容差。
func cmp_rect(got: Rect2, want: Rect2, what: String) -> void:
	checks += 1
	if absf(got.position.x - want.position.x) > 0.01 or absf(got.position.y - want.position.y) > 0.01 or absf(got.size.x - want.size.x) > 0.01 or absf(got.size.y - want.size.y) > 0.01:
		bad += 1
		fail_list.append(what + " got=%s want=%s" % [str(got), str(want)])


## 收口：打印汇总 + 失败明细 + 判定，然后退出。
func finish(tag: String, min_checks: int = 0, extra: String = "") -> void:
	var msgs: Array = fail_list.duplicate()
	if checks < min_checks:
		msgs.append("检查数不足 checks=%d min=%d" % [checks, min_checks])
	var all_ok := bad == 0 and checks >= min_checks
	var line := "[%s] checks=%d bad=%d" % [tag, checks, bad]
	if extra != "":
		line += " " + extra
	print(line)
	for i in mini(msgs.size(), FAIL_SHOW_MAX):
		print("[%s] fail: %s" % [tag, msgs[i]])
	print("[%s] %s" % [tag, "PASS" if all_ok else "FAIL"])
	quit(0 if all_ok else 1)
