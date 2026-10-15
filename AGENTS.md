# 《改道》Godot 工程 — AI 开发入口

> **权威文档永远是 [`docs/DEVELOPMENT-PLAN.md`](docs/DEVELOPMENT-PLAN.md)**。本文件只是给 AI 的
> **速查表与红线**，不复制权威文档内容；冲突时以方案为准。

48×48 塔防，核心机制「放墙改道」：敌人绕得越远、死时赏金越高（`reward + traveled>>3`）。
Engineering 保真度极高：模拟核心是**确定性**的，有 16 指纹黄金基线锁死行为。

---

## 一、目录（2026-10-15 整理后）

| 路径 | 管什么 |
|---|---|
| `sim/` | 模拟核心十模块，纯逻辑、**无浮点、无渲染**：`lua64`(语义 shim) / `canon` / `rng` / `grid` / `flowfield` / `scenario` / `sim`(数值表) / `world` / `verify` / `golden_baseline` |
| `game/` | 表现层，只读模拟：`main`(主循环/输入) / `view`(3D 门面) + 组件 `view_core`/`view_terrain`/`view_entities`/`view_audio`（D5-1 拆分 2026-10-15） / `models` / `blueprint` / `hud` / `screens` / `selfcheck` |
| `tests/` | 单测 83 例 + **17 个验收探针**（`tests/probes/`，公共夹具 `probe_kit.gd`，D5-2 2026-10-15） |
| `tools/` | Python 工具：`check_shots.py` / `convert_all.py` / `umd2_to_gltf.py` / `verify_glb.py` |
| `assets/` | `audio/sfx`(19 mp3) / `fonts`(Noto Sans SC) / `models`(glb) |
| `docs/` | 开发方案（权威）、审计报告、`devlogs/` |
| `shots/` | 验收截图产物（已 `exclude_filter` 排除出包） |
| `logs/` | 闸的 stdout/exit 证据 |

## 二、分层纪律（**单向，不许反向**）

```
sim/   ←──  game/            （表现层读模拟，模拟层不知道表现层存在）
sim/   ←──  tests/           （单测驱动模拟）
game/  ←──  tests/probes/    （探针驱动表现层与整机）
```

- `sim/` **禁止** `require`/`preload` 任何 `game/` 下的文件。
- 唯一的写路径是 `main.gd` 调 `world.apply_command(...)`；`view.gd` 及其四组件绝对不许回写模拟状态。
- `view_entities.gd` 的插值缓存（`unit_nodes` 的 `px/py`、`death_fx`、`_height_rev`）是派生态，**不进指纹**。
- 白盒直写（`w.supply = ...`）只允许出现在 `tests/`，生产代码禁止。

## 三、跑闸（先读这个再动手）

```bash
GODOT="D:/G/game/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe"
P="D:/G/game/games/reroute-godot"

# headless 安全：单测 + 模拟模块探针 + 场景构建
"$GODOT" --headless --path "$P" -s res://tests/run_tests.gd                    # 83 单测
for p in golden scene sim grid flow scenario world; do
  "$GODOT" --headless --path "$P" -s res://tests/probes/probe_$p.gd
done

# 必须窗口模式（涉及屏幕坐标/渲染纹理，headless 下必然失败或空转不退出）
for p in sync input hud ui_flow smoke shots audio asset model orient; do
  "$GODOT" --path "$P" -s res://tests/probes/probe_$p.gd
done

python tools/check_shots.py    # 截图像素校验
```

**改完代码必须跑对应闸**，不要只跑能跑的那个。改 `sim/` 必须跑 `probe_golden`。

## 四、两条必须记住的铁律

1. **无头 CLI 用 `_console.exe` 变体**，普通 `.exe` 不输出 stdout。
2. **`--headless` 下根视口只有 64×64**。凡涉及屏幕坐标或渲染纹理的探针
   （`sync` / `input` / `hud` / `ui_flow` / `smoke` / `shots` / `audio` /
   `asset` / `model` / `orient`）**必须窗口模式运行**。

## 五、调试陷阱（都会伪装成「挂起」）

- **越界读会中止 `_initialize` → `quit()` 不执行 → 无头引擎空转**。判「挂起」前
  **stderr 必须重定向到文件**再看，别靠肉眼看窗口有没有反应。
- GDScript 数组越界是**硬报错**，不像 Lua 母版靠 nil-on-越界兜底。

## 六、基线冻结纪律（**最高优先级**）

以下三者是「判据即产品」，**禁止为了让某个探针变绿而修改它们**：

| 冻结物 | 位置 |
|---|---|
| 16 个黄金指纹 | `sim/golden_baseline.gd` |
| 剧本指纹 `0x12715062` | `Scenario.fingerprint()` |
| `STATE_SCHEMA = 5` | `canon.gd` / `world.canonical_bytes()` |

漂移了先怀疑**实现**，不是怀疑基线。真要改：先说明为何必须改 → 重跑 `probe_golden` 采新值
→ **同一次提交里**更新基线 + 写决策记录。

## 七、移植/编码硬约束

- **类内禁自引用**：`class_name X` 的脚本内禁止 `X.new(...)` / `load("res://自身路径")`，
  Godot 4.7.2 分析器会编译期无限递归。自测/自检放类外。
- **`pad_idx` 用规范公式** `(y+1)*stride+(x+1)`（Lua 母版多 +1 靠 nil 兜底，此处不能）。
- **禁 `:=` 推断无类型 Array 访问**：一律显式类型或先判 `size()`。
- **数组原地 compact 会报类型错误**：建新数组，别 `arr[i]=arr[j]` + `resize`。
- **保留字/撞名**：`pass`→`pmap`、`set`→`set_cell`；Lua `--`→`#`；大 hex 字面量（≥2^63）
  被钳位报错 → 用带符号十进制。
- **语义 shim**（`sim/lua64.gd`）：`%`→`Lua64.mod`（向下取整）、`//`→`idiv`、
  `>>`→`Lua64.lshr`（逻辑移）。`*`/`+`/`<<`/位运算回绕与 Lua 一致，可直译。
- **确定性**：随机源只有 `World.rng`，禁 `randi()`/`randf()`；`sim/` 内禁浮点。

## 八、命名规范

| 对象 | 规范 |
|---|---|
| 文件 | `snake_case.gd` |
| 类名 | `PascalCase`（`class_name`） |
| 常量 | `UPPER_SNAKE` |
| 变量/函数 | `snake_case` |
| 私有成员 | 前缀 `_` |
| 探针 | `probe_<领域>.gd` → **`tests/probes/`** |
| 单测 | `test_<模块>.gd` → `tests/` |

## 九、已知待办

- `view.gd` 拆分（D5-1）**已完成（2026-10-15）**：972 行 → 206 行门面（`_ready` 组装 + 公共面转发）
  + 四组件 `view_core`(246) / `view_terrain`(243) / `view_entities`(418) / `view_audio`(116)。
  机制 = 组合 + 转发属性，外部 `view.xxx` 访问零变化、探针无需改路径；验收 = 拆分前后
  `probe_sync` 输出逐字节一致（已通过：SHA256 相同；全 19 闸 post 比照 pre 全绿）。
- 探针规整（D5-2）**已完成（2026-10-15）**：新增公共夹具 `tests/probes/probe_kit.gd`
  （`class_name ProbeKit extends SceneTree`：`check`/`fail`/`cmp_int`/`cmp_approx`/`cmp_v3`/`cmp_rect`/`finish`），
  17 探针全部 `extends ProbeKit`，输出统一为 `[TAG] checks=N bad=M` + `[TAG] PASS|FAIL`；
  重构前后 checks 数逐项一致（`probe_sync` 输出 SHA256 逐字节相同）；
  全 19 闸绿（证据 `logs/gates-20261015-d52/post/`）。夹具改动后需 `--import` 刷类缓存。
- 拖拽预览逐格（D5-3）**已完成（2026-10-15）**：`view_entities.show_ghost` 由「首尾单拉伸盒」
  改为**逐格方块**（各自贴合所在柱顶；`ghost_mi` 仍指首格）；斜线拖拽不再覆盖线外格。
  `probe_sync` 幽灵断言重写（盒数=格数 + 逐格世界位/缩放/染色；直连+斜线），
  负对照实跑（旧实现 + 新断言 = `bad=2 FAIL`）；`shots/ghost.png` 改斜线目视件（对角阶梯绿格）。
- 窗口缩放一致性（D5-4）**已完成（2026-10-15）**：`hud._layout()` 开头重算 `S`
  （布局与 `hit_regions()` 均取当前视口、恒同步，缩放后点击排除不再错位）；
  `probe_hud` 新增缩放断言 7 条（checks 56→63），负对照实跑（旧 hud + 新断言 = `bad=4 FAIL`）。
- 历史审计报告（`docs/*-20261015.md`）按**快照原则保持原样**，不要顺着结构整理去改它们。

---

*改动本文件前先确认没有和 `DEVELOPMENT-PLAN.md` 打架；两处都改。*
