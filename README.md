# 改道 · Godot 工程（reroute-godot）

《改道》从 UrhoX + Lua 迁移到 **Godot 4.7.2 stable (mono)** 的工程。

> **当前状态（2026-10-14）**：模拟核心与表现层**均已完成**，游戏可完整游玩
> （标题 → 对局 → 暂停/结算三屏闭环，3D 视图 + HUD + 音频 + 真实模型资产）。
>
> **交付目标**：2026 TapTap 聚光灯 21 天游戏创作挑战（主题「涌现」）。
> 官方建议 **10-18 前提交**，硬截止 **10-21**。目标 **Android + Windows 双端**
> （冲「最佳双端游戏奖」¥80,000）+ 主奖项。
> 当前处于 **D0–D7 倒排冲刺**，日程、交付材料清单与砍单顺序见开发方案 §0 / §7。
>
> ⚠️ **只服务两条赛道**：最佳双端游戏奖 + 主奖项，二者均按游戏质量评审。
> **全程参与奖 / 社区运营赛道已于 2026-10-14 放弃**（该奖要求 ≥50 试玩，个人作品不可达）
> → **不写开发者日志，不追试玩数**，冲刺期没有任何按天重复的运营任务。理由见方案 §0.3 D。
>
> **开发权威文档：[`docs/DEVELOPMENT-PLAN.md`](docs/DEVELOPMENT-PLAN.md)** —— 接手开发
> 先读它。本文件只做速览。

## 一、跑起来

```bash
GODOT="D:/G/game/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe"
P="D:/G/game/games/reroute-godot"

# 玩：直接开编辑器/窗口跑主场景
"$GODOT" --path "$P"

# 全部自动化闸（窗口模式的必须去掉 --headless）
"$GODOT" --headless --path "$P" -s res://tests/run_tests.gd   # 83 单测
"$GODOT" --headless --path "$P" -s res://probe_golden.gd      # 黄金回放 16 指纹
"$GODOT" --headless --path "$P" -s res://probe_scene.gd       # 主场景构建
"$GODOT" --path "$P" -s res://probe_sync.gd                   # 视觉同步对拍
"$GODOT" --path "$P" -s res://probe_input.gd                  # 输入闭环
"$GODOT" --path "$P" -s res://probe_hud.gd                    # HUD
"$GODOT" --path "$P" -s res://probe_ui_flow.gd                # 三屏流转
"$GODOT" --path "$P" -s res://probe_smoke.gd                  # 全局冒烟（跑完整一局）
```

### ⚠️ 两条必须记住的规矩

1. **无头 CLI 用 `_console.exe` 变体**，普通 `.exe` 不输出 stdout。
2. **`--headless` 下根视口只有 64×64**。凡涉及屏幕坐标或渲染纹理的探针
   （`probe_input` / `probe_sync` / `probe_hud` / `probe_ui_flow` / `probe_smoke` /
   `probe_shots` / `probe_audio` / `probe_asset` / `probe_model` / `probe_orient`）
   **必须窗口模式运行**，否则必然失败或空转不退出。

## 二、目录

| 路径 | 管什么 |
|---|---|
| `sim/` | 模拟核心十模块：`lua64`(语义 shim) / `canon` / `rng` / `grid` / `flowfield` / `scenario` / `sim`(数值表) / `world` / `verify` / `golden_baseline`。纯逻辑、无渲染、无浮点 |
| `game/` | 表现层：`main`(主循环/输入) / `view`(3D) / `models`(资产) / `blueprint`(程序化地形) / `hud` / `screens` / `selfcheck` |
| `tests/` | 单测套件：`kit.gd`(记录式断言) + `run_tests.gd`(入口) + 6 模块用例 + `stub_scenario` 夹具 |
| `probe_*.gd` | 验收探针，同时是全链路冒烟入口 |
| `assets/` | 音频 19 个 mp3、中文字体、10 个 glb 模型 |
| `tools/` | Python 工具：`check_shots.py`(截图像素校验) / `umd2_to_gltf.py` / `verify_glb.py` |
| `docs/` | 开发方案（权威） |
| `export_presets.cfg` | Windows Desktop 导出预设 |

## 三、玩法一句话

48×48 塔防，核心机制「放墙改道」：用墙/塔/地形改造把敌人推上更长的路，
绕行越远赏金越高（`reward + traveled>>3`）。挖开西南盆地插口能拿到矿，
但也会打开第三个出怪口。撑到 6400 tick 且场上清空即胜。

## 四、移植纪律（全部从踩坑中来，改代码前必读）

1. **类内禁自引用**：`class_name` 脚本内禁止 `自身类名.new(...)` 或 `load("res://自身路径")`
   —— Godot 4.7.2 分析器会编译期无限递归（现象：实例化挂起且零输出）。**自检/自测试放类外**。
2. **`pad_idx` 用规范公式** `(y+1)*stride+(x+1)`：Lua 母版多 +1（内格右移一列）靠 nil-on-越界
   兜底；GDScript 数组越界直接报错。图与母版同构，距离/指纹一致。
3. **禁 `:=` 推断无类型 Array 访问**（`head[i]`/`off[k]`/`dist[p]`/`c[4]`）：一律显式类型或先判 `size()`。
4. **越界读会伪装成「挂起」**：运行时错误中止 `_initialize` → `quit()` 不执行 → 无头引擎空转。
   调试时 **stderr 必须重定向到文件**再判「挂起」。
5. **保留字/撞名**：`pass`→`pmap`、`set`→`set_cell`；Lua `--` 注释→`#`；
   大 hex 字面量（≥2^63）钳位报错→带符号十进制。
6. **语义 shim**（`sim/lua64.gd`）：`%` 截尾→`mod`（向下取整）、无 `//`→`idiv`、
   `>>` 算术移→`lshr`（逻辑移）。`*`/`+`/`<<`/位运算回绕与 Lua 一致，直译。
7. **数组原地 compact**（`arr[i]=arr[j]` + `resize`）触发类型错误→建新数组。
8. **基线冻结**：`sim/golden_baseline.gd` 的 16 指纹、剧本指纹 `0x12715062`、
   `STATE_SCHEMA=5` 都是判据。改动必须走「记录 + 重录」流程，**禁止为了修绿探针而改基线**。
