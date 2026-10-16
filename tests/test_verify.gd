extends RefCounted

# verify（闸宿主）语义单测：命令按「声明 tick 开始前生效」的消耗规则执行、与数组顺序无关；
# 黄金命令表的「按 tick 非降序」是基线成立前提（缺陷 A 的回归锁，见方案 §10.2）。


func register(kit: TestKit) -> void:
	kit.module("verify")

	kit.test("sorted-commands-stable", func():
		var cmds := [[50, "wall", 5, 5], [20, "wall", 3, 3], [20, "dig", 4, 4], [35, "remove", 3, 3]]
		var out := Verify.sorted_commands(cmds)
		kit.eq(out.size(), 4, "数量不变")
		kit.eq(out[0][0], 20, "首条 tick=20")
		kit.eq(out[1][0], 20, "次条 tick=20")
		kit.ok(out[0] == cmds[1] and out[1] == cmds[2], "同 tick 保持原相对序（按引用透传）")
		kit.eq(out[2][0], 35, "随后 tick=35")
		kit.eq(out[3][0], 50, "最后 tick=50"))

	kit.test("commands-apply-at-declared-tick", func():
		# 乱序输入与有序输入的运行结果必须逐样本一致；并与「手工按声明 tick 喂入」的参照实现一致。
		var cmds := [[50, "wall", 3, 3], [20, "wall", 5, 5], [80, "remove", 3, 3], [150, "wall", 6, 6]]
		var sc := StubScenario.new({ "size": 10, "end_tick": 200, "hard_cap_tick": 1000 })
		var r1 := Verify.run_world(sc, 42, cmds, 10, false)
		kit.eq(r1[1], "", "run_world 正常收口")
		var sorted := Verify.sorted_commands(cmds)
		var r2 := Verify.run_world(sc, 42, sorted, 10, false)
		kit.eq(r2[0].size(), r1[0].size(), "样本数一致")
		var same := true
		for i in r1[0].size():
			if r1[0][i][1] != r2[0][i][1]:
				same = false
		kit.ok(same, "乱序输入与有序输入逐样本一致")
		# 参照实现：手工步进，命令在声明 tick 开始前喂入（消耗规则见 verify.gd 头注释）
		var w := World.new(sc, 42)
		var ri := 0
		var ref := []
		while w.tick_count < sc.hard_cap_tick and w.outcome == World.RUNNING:
			while ri < sorted.size() and sorted[ri][0] <= w.tick_count + 1:
				var c: Array = sorted[ri]
				w.apply_command({ "kind": c[1], "x": c[2], "y": c[3] })
				ri += 1
			w.tick()
			if w.tick_count % 10 == 0:
				ref.append([w.tick_count, "%08x" % w.fingerprint()])
		kit.eq(ref.size(), r1[0].size(), "参照样本数一致")
		var same2: bool = ref.size() == r1[0].size()
		if same2:
			for i in ref.size():
				if ref[i][1] != r1[0][i][1]:
					same2 = false
		kit.ok(same2, "run_world 与「声明 tick 生效」参照实现逐样本一致"))

	kit.test("golden-script-sorted", func():
		var sc := Verify.script_for(Scenario.new())
		var bad := ""
		for i in range(1, sc.size()):
			if sc[i][0] < sc[i - 1][0]:
				bad = "第 %d 条 tick=%d 排在 tick=%d 之后" % [i, sc[i][0], sc[i - 1][0]]
				break
		kit.eq(bad, "", "script_for 按 tick 非降序（黄金指纹基线成立的前提）"))
