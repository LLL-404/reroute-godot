# 改道 · Godot 移植仓（reroute-godot）

《改道》从 UrhoX + Lua 迁移到 Godot 4.7.2 的工程。**当前状态：模拟核心 100% 移植并逐位验证，表现层未开始**（游戏尚不可"看见与游玩"）。

## 已验事实（2026-10-13）

| 项 | 证据 | 命令 |
|---|---|---|
| 无头可运行 | exit 0 | `<godot> --headless -s res://tests/run_tests.gd` |
| 83 例单测全绿（86 例 Lua 套件等价物，差 3 例见 tests/ 注释） | `[UNIT-DONE] passed=83 failed=0` + `[UNIT-ALL-GREEN]` | 同上 |
| **黄金回放逐位一致**（seed 20261003，16 指纹 = reroute/scripts/sim/golden_baseline.lua） | `[R7-PROBE] PASS` | `<godot> --headless -s res://probe_golden.gd` |
| 剧本指纹对拍引擎现值 0x12715062 | `[R5-PROBE] PASS` | `<godot> --headless -s res://probe_scenario.gd` |
| Windows 导出可用 | exit 0，export/game.exe 109MB | `<godot> --headless --export-release "Windows Desktop" export/game.exe` |

Godot 二进制：`D:/G/game/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe`（无头 CLI 用 console 变体；导出模板 4.7.2.stable.mono 已装）。

## 目录

| 路径 | 管什么 |
|---|---|
| `sim/` | 模拟核心十模块：lua64（语义 shim）/ canon / rng / grid / flowfield / scenario / sim（数值表）/ world / verify / golden_baseline |
| `tests/` | 单测套件：kit.gd（记录式断言）+ run_tests.gd（入口）+ 6 模块用例 + StubScenario 夹具 |
| `probe_*.gd` | 各轮验收探针（sim/grid/flow/scenario/world/golden），同时是全链路冒烟入口 |
| `export_presets.cfg` | Windows Desktop 导出预设 |

## 移植纪律（全部从踩坑中来，改代码前必读）

1. **类内禁自引用**：class_name 脚本内禁止 `自身类名.new(...)` 或 `load("res://自身路径")` —— Godot 4.7.2 分析器会编译期无限递归（现象：实例化挂起且零输出）。**自检/自测试放类外**（探针或 tests/）。
2. **`pad_idx` 用规范公式** `(y+1)*stride+(x+1)`：Lua 母版多 +1（内格右移一列）靠 Lua 的 nil-on-越界兜底；GDScript 数组越界直接报错。图与母版同构，距离/指纹一致。
3. **禁 `:=` 推断无类型 Array 访问**（`head[i]`/`off[k]`/`dist[p]`/`c[4]`）：一律显式类型或先判 `size()`。
4. **越界读会伪装成"挂起"**：Godot 运行时错误中止 `_initialize` → `quit()` 不执行 → 无头引擎空转。调试时 **stderr 必须重定向到文件**再判"挂起"。
5. 保留字/撞名：`pass`→`pmap`、`set`→`set_cell`；Lua `--` 注释→`#`；大 hex 字面量（≥2^63）钳位报错→带符号十进制。
6. 语义 shim（`sim/lua64.gd`）：`%` 截尾→`mod`（向下取整）、无 `//`→`idiv`、`>>` 算术移→`lshr`（逻辑移）。`*`/`+`/`<<`/位运算回绕与 Lua 一致，直译。
7. 数组原地 compact（`arr[i]=arr[j]` + `resize`）触发类型错误→建新数组。

## 下一步（表现层，建议另立 goal）

3D 视图（view3d.lua 移植）、HUD、三屏 UI、键鼠/触屏输入、音效 BGM、真实资产导入（`../reroute/assets/` 的 .mdl/.ani 是 UrhoX 专有格式，png/jpg/mp3 可直用；.mdl 需转换或经 Tripo 重建）。竣工判据建议：主场景无头加载零报错 + MovieMaker 渲染出帧 + 人工目视对照 Maker 版截图。
