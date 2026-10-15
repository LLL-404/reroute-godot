# CLAUDE.md

本工程的 AI 开发入口是 **[`AGENTS.md`](AGENTS.md)**——请先读它。

权威文档是 [`docs/DEVELOPMENT-PLAN.md`](docs/DEVELOPMENT-PLAN.md)；`AGENTS.md` 与本文
都是速查表，冲突时以方案为准。

三个最常被踩的点（详见 `AGENTS.md` 第三、四、六节）：

1. 跑闸要区分 **headless** 与 **窗口模式**，涉及屏幕坐标的探针必须窗口模式。
2. 判「挂起」前先把 stderr 重定向到文件——越界读会中止 `_initialize` 并让引擎空转。
3. **禁止为修绿探针而改基线**（`golden_baseline.gd` 的 16 指纹 / `0x12715062` / `STATE_SCHEMA=5`）。
