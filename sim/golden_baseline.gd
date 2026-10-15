class_name GoldenBaseline
extends RefCounted

# 黄金基线（种子 20261003 + Verify.SCRIPT_COMMANDS，含高度层样本）。
# 2026-10-07 原样转录 reroute/scripts/sim/golden_baseline.lua（v5 + 高度夹具）。
# 2026-10-15 缺陷 A（命令表未按 tick 排序 → 部分命令实际延后执行）修复后重录：
#   命令改按声明 tick 生效 → 世界于 tick 4926 核心被毁判负（LOST）→ 采样 12 条（400..4800）。
#   重录前后：tick 800 一条未变；400..4800 段其余 11 条与旧 16 条的尾部 4 条（5200..6400）不再存在。
#   决策记录见 docs/DEVELOPMENT-PLAN.md §10.2 缺陷 A。
const SEED := 20261003
const EVERY := 400
const FPS := [
	[400, "a857f170"],
	[800, "b3557c68"],
	[1200, "36db8976"],
	[1600, "f59daa55"],
	[2000, "0184d5af"],
	[2400, "8a5521c3"],
	[2800, "b4fb4f0d"],
	[3200, "305a677e"],
	[3600, "05492483"],
	[4000, "ff25f283"],
	[4400, "e78b2cda"],
	[4800, "2e8e16ec"],
]
