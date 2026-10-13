class_name TestKit
extends RefCounted

# 单元测试最小框架（GDScript 版，无 io 依赖）。口径同 reroute/tests/test_kit.lua：
# 每用例一行 [UNIT] PASS/FAIL，末行 [UNIT-DONE] 汇总 + [UNIT-ALL-GREEN]/[UNIT-RED]。
# 与 Lua 版的差异：GDScript 无 pcall/error 捕获，断言改为"记录式失败"——
# 失败不中断，用例级标记，汇总时统一输出（比异常式更稳，且失败信息带定位）。

var tests := []
var passed := 0
var failed := 0
var _mod := "?"
var _cur := ""
var _cur_failed := false


func module(name: String) -> void:
	_mod = name


## 注册用例（收集期零副作用，执行期统一跑）。
func test(name: String, fn: Callable) -> void:
	tests.append({ "mod": _mod, "name": name, "fn": fn })


func _begin(name: String) -> void:
	_cur = name
	_cur_failed = false


func _record(what: String) -> void:
	_cur_failed = true
	print("    DETAIL " + _mod + "." + _cur + " : " + what)


## 相等断言（标量）。
func eq(got, want, what: String) -> void:
	if got != want:
		_record(what + "：得 " + str(got) + " 期 " + str(want))


## 条件断言。
func ok(cond: bool, what: String) -> void:
	if not cond:
		_record(what + "：期望成立")


## 序列逐元素相等。
func seq(got: Array, want: Array, what: String) -> void:
	if got.size() != want.size():
		_record(what + "：长度 %d ≠ %d" % [got.size(), want.size()])
		return
	for i in want.size():
		if got[i] != want[i]:
			_record(what + "：[%d] 得 %s 期 %s" % [i, str(got[i]), str(want[i])])
			return


## 执行全部用例并输出行式报告。@return 是否全绿
func run() -> bool:
	for t in tests:
		_begin(t["name"])
		t["fn"].call()
		if _cur_failed:
			failed += 1
			print("[UNIT] FAIL " + t["mod"] + "." + t["name"])
		else:
			passed += 1
			print("[UNIT] PASS " + t["mod"] + "." + t["name"])
	print("[UNIT-DONE] passed=%d failed=%d" % [passed, failed])
	print("[UNIT-ALL-GREEN]" if failed == 0 else "[UNIT-RED]")
	return failed == 0
