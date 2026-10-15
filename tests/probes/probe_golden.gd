extends ProbeKit

# R7 验证探针：黄金回放（C3）——GDScript sim 核逐位复现引擎录制的 16 个基线指纹。
# 判定：exit 0 + stdout 含 `[GOLDEN] PASS`。


func _initialize() -> void:
	var sc := Scenario.new()
	print("[GOLDEN] golden replay running (seed=" + str(GoldenBaseline.SEED) + ", cmds=" + str(Verify.SCRIPT_COMMANDS.size()) + ")...")
	var res := Verify.run_world(sc, GoldenBaseline.SEED, Verify.SCRIPT_COMMANDS, GoldenBaseline.EVERY, true)
	var samples = res[0]
	var err = res[1]
	if err != "":
		check(false, "run_world error: " + str(err))
	else:
		check(samples.size() == GoldenBaseline.FPS.size(), "sample count " + str(samples.size()))
		for i in GoldenBaseline.FPS.size():
			if i < samples.size():
				var want: Array = GoldenBaseline.FPS[i]
				var got: Array = samples[i]
				if got[0] != want[0] or got[1] != want[1]:
					check(false, "tick " + str(want[0]) + ": 得 " + str(got[1]) + " 期 " + str(want[1]))
		print("[GOLDEN] all " + str(samples.size()) + " fingerprints compared")

	# 确定性复跑：同种子同命令流，两遍逐位一致
	var res2 := Verify.run_world(Scenario.new(), GoldenBaseline.SEED, Verify.SCRIPT_COMMANDS, GoldenBaseline.EVERY, false)
	if res2[1] != "":
		check(false, "rerun error: " + str(res2[1]))
	else:
		var same: bool = res2[0].size() == samples.size()
		for i in samples.size():
			if res2[0][i][1] != samples[i][1]:
				same = false
		check(same, "determinism rerun")

	finish("GOLDEN")
