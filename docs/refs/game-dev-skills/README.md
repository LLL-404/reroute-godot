# 游戏开发参考技能库（本地参考，不自动加载）

> 2026-10-20 建立。来源 = skills.sh 上 5 个 GitHub 仓库的技能原文（浅克隆后抽出，默认分支）。
> **不是技能**：不进 `C:\Users\23501\.agents\skills` 扫描、不占会话上下文；只在需要时查阅。
> 本目录带 `.gdignore`，不会被 Godot 当资源扫描/打进包。

## 使用规则（迭代优先，不整包安装）

1. 需要时先查这里：每个技能一个目录，入口 `SKILL.md`；`scripts/` 是可抄改的参考实现，`references/` 是细则。
2. 提炼出的规则/代码，优先并入本仓文档（`docs/DEVELOPMENT-PLAN.md`、`docs/UI-REDESIGN-*` 等）或改造现有技能 —— **按需迭代，不新增技能包**。
3. 若某项反复用、值得常驻：先试读 → `npx skills add <owner>/<repo> --skill <名> -g` 装进 hub → 14 天后查会话日志，未被加载即退役。
4. 本库已剔除 `godot-master`（1735 文件 / 4.6MB 的枢纽件）；需要时用 `npx skills add thedivergentai/game-dev-agentic-skills -l` 现查。

## 索引（19 个）

### thedivergentai/game-dev-agentic-skills（Godot 4.7 专属，带 GDScript 参考实现）

| 目录 | 内容 | 何时查 |
|---|---|---|
| `godot-genre-tower-defense/` | ★ 塔防核心：mazing 封路校验（`map_get_path` 预检 + worker 线程烘焙）、目标优先级、波次资源化、经济规则 | 改玩法循环 / 放墙规则 / 塔行为 |
| `godot-navigation-pathfinding/` | 异步动态烘焙、卡死检测、低层避障（4 个脚本） | 寻路 / 避障 / 动态改图 |
| `godot-game-loop-waves/` | Wave-State 模式、密度决策树、组合式生成 | 波次编排 / 难度缩放 |
| `godot-economy-system/` | 货币表示决策树、商店 / 定价 / 通胀 / 掉落表 | 改道经济 / 供给与消耗 |
| `godot-monte-carlo-balancer/` | 5 阶段平衡实验室（审计→抽源→模拟→分析→经济留存；需 Rust+rayon） | 赛后做数值校准 |

### gamedev-skills/awesome-gamedev-agent-skills（引擎中立，模板型）

| 目录 | 内容 | 何时查 |
|---|---|---|
| `godot-export/` | ★ 双端导出：preset 对齐、headless CLI、数据包分离 | 出包 / 导出报错 |
| `performance-optimization/` | 帧预算数学 → profiler 判读 → 对象池 / 批处理 | 掉帧 / 移动端性能 |
| `game-ui-ux/` | 锚点 + 容器、安全区 / 刘海、焦点导航（含 4.7 片段） | UI 布局 / 多屏适配 |
| `input-systems/` | 动作映射、触屏 + 手柄多设备、死区、输入缓冲 | 触控 / 输入手感 |
| `game-feel/` | trauma 震屏、顿帧、挤压拉伸、分层反馈 | 打击感 / 反馈打磨 |
| `procedural-gen/` | 种子确定性 RNG、fBm 噪声、掉落表 | 地形 / 地图生成 |
| `tower-defense/` | 塔防通用蓝图：波次生成器、必配系统、设计旋钮 | 玩法结构对照 |
| `create-game-assets/` | 美术资产生产 / 溯源 / 规范 / QA 门（11 文件） | 美术管线（赛后） |

### Donchitos/Claude-Code-Game-Studios（文档工作流型）

| 目录 | 内容 | 何时查 |
|---|---|---|
| `balance-check/` | 数值审查四域；缺数据输出 `NOT ASSESSED`（与六件套纪律同源） | 平衡审查 |
| `art-bible/` | 美术圣经 8 节（视觉身份 / 形状语言 / 色系 / 生产指南） | 新项目 / 美术方向 |
| `asset-spec/` | 逐资产规格 + AI 生成提示词 | 资产外包 / AI 生成 |

### 其它

| 目录 | 来源 | 何时查 |
|---|---|---|
| `godot-gdscript-patterns/` | wshobson/agents | GDScript 模式速查（信号 / 导出 / 生命周期） |
| `design-action-combat/` | mengto/skills | 动作战斗原则清单（薄，30 行） |
| `tune-enemy-ai/` | mengto/skills | 敌人 AI 调校原则（薄，29 行） |

## 补充来源（现取现用）

```powershell
npx skills add <owner>/<repo> -l                            # 列出仓库全部技能
npx skills use <owner>/<repo>@<skill>                       # 免安装试读 prompt
git clone --depth 1 https://github.com/<owner>/<repo>.git   # 取原文
```

- https://github.com/thedivergentai/game-dev-agentic-skills
- https://github.com/gamedev-skills/awesome-gamedev-agent-skills
- https://github.com/Donchitos/Claude-Code-Game-Studios
- https://github.com/wshobson/agents
- https://github.com/mengto/skills
