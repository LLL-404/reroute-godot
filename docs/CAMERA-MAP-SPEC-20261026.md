# 相机操作层独立 + 地图 128×128 扩容规格

- 日期：2026-10-26
- 状态：待评审（**批准前不改任何代码**）
- 关联：[DEVELOPMENT-PLAN.md](DEVELOPMENT-PLAN.md)、[AGENTS.md](../AGENTS.md)
- 范围：`game/` 相机操控与操作层、`sim/`+`game/` 地图尺寸派生、`tests/probes/` 探针口径

## 0. 摘要

两段独立交付，不混做：

- **A 段（纯表现层）**：把相机操控从 `main.gd` 抽成独立操作层 `game/view/camera_control.gd`；
  相机俯仰改为**可调状态**（《冰汽时代》式独立俯仰：滚轮只缩放，中键拖拽上下调俯仰、左右旋转）。
- **B 段（大工程）**：地图 64×64 → 128×128，分四段推进，每段闸绿再进下一段。

A 段零指纹影响；B 段必然重录黄金基线（第十二次）。

## 1. 背景与现状

| 项 | 现状 | 位置 |
|---|---|---|
| 相机俯仰 | `_pitch` 只在 `fit_camera()` 时定死 42°，操控不改 | `game/view/view_core.gd` |
| 相机距离/缩放 | `d = _dist * _zoom`，`_zoom` 夹 [0.6, 1.8] | 同上 |
| 右键 | 跟手平移 | `game/app/main.gd` |
| 滚轮 | 缩放 | 同上 |
| WASD / QE | 平移 / 水平旋转 | 同上 |
| 中键 | **未使用**（可直接承载俯仰拖拽） | 同上 |
| 触屏双指 | 中点=平移、间距=缩放、转角=旋转（三维度已占满） | 同上 |
| 地图尺寸 | `CELL_N=64` / `HALF=32.0`，多处字面量 | `view_core` / `scenario` / `blueprint` / `main` |
| mapgen 尺寸耦合 | 约 96 处 `4096` / `y*64+x` / 63 边界 | `sim/mapgen.gd` |
| 地形网格重建 | 全量 `_compute_cell_top` + `_rebuild_hex`（单线程、单 mesh） | `game/view/view_terrain.gd` |
| 基线 | 16 指纹第十一次重录；`STATE_SCHEMA=11`；38 探针 / 22 闸 | `sim/golden_baseline.gd` / `sim/canon.gd` / AGENTS.md |

## 2. 目标

- **G1** 相机俯仰成为玩家可调状态：默认 42°，范围 18°~78°，滚轮不再改俯仰。
- **G2** 操作层独立：鼠标/键盘/触摸到相机意图的映射集中在一个模块，`view_core` 只留相机数学。
- **G3** 默认口径零漂移：`fit_camera()` 仍重置为 42° / `zoom=1`；默认档截图与现有探针口径不变。
- **G4** 低俯角不穿模：相机离地净空不足时沿视线后退，不改变实际俯仰角。
- **G5** 地图 128×128：尺寸常量单点化，game 只单向引用 sim。
- **G6** 128 下开图性能：默认种子 <1.2s、单盐 <0.8s（现 251/210ms 的 ≤4 倍线性预算）。
- **G7** A 段不触碰 `sim/`、指纹、探针断言阈值。

## 3. 非目标

- **N1** 不做流场数据结构与出桶顺序改动（保黄金回放）。
- **N2** 本期不做触屏独立俯仰手势（触屏锁 42°，后续另行评估三指方案）。
- **N3** 不做分块网格（保留为 B3 实测不达标时的升级触发条件）。
- **N4** 不重做波次结构（扩容口径 = 接受更大更长的局；`wave_scale_pct` 为唯一补偿旋钮）。
- **N5** 不改建造输入、HUD 排除、UI 路由、安卓返回的归属（仍留 `main.gd`）。
- **N6** 不改发布流程、商店素材、版本号。

## 4. 架构决策

### D1 两段独立交付

A 段先独立交付并全闸绿，再进 B1。B 段内部四小段各自闸绿。理由：A 段纯表现层可零指纹验证；
B 段任何失败都可停在原地，不影响线上版本。

### D2 操作层边界

```
main.gd（宿主：输入入口 + 左键建造 + HUD 排除 + UI 路由）
  └─ camera_control.gd（新：鼠标/键盘/触摸 → 相机意图）
        └─ view_core.gd（相机数学：focus/yaw/pitch/zoom、取景、投影）
```

`camera_control.gd` 收：右键平移、滚轮缩放、WASD/QE、中键拖拽、双指手势的相机部分、
俯仰范围与最小视距约束。

`main.gd` 留：左键建造、`in_hud_region`、`_camera_free()` 判定、安卓返回、单指/双指手势的
**开始与归属判定**（因为双指开始要取消建造拖线）。

纪律：`camera_control` 不引用 `sim/`；`view_core` 不引用 `camera_control`（单向）。

### D3 相机模型：独立俯仰

- `_pitch` 由 `fit_camera()` 时定死改为**可变状态**，初始 42°。
- 新增 `PITCH_MIN_DEG=18.0` / `PITCH_MAX_DEG=78.0` / `PITCH_STEP_RAD_PER_PX≈0.005`。
- `fit_camera()` 仍重置 `_pitch=PITCH_DEG(42°)`、`_zoom=1.0`、`yaw=0`、重算 `focus`。
- 删除原计划中的 zoom→pitch 分段线性耦合映射（不再需要）。

### D4 输入映射

| 平台 | 输入 | 行为 |
|---|---|---|
| PC | 滚轮 | 只改 `_zoom`（0.6~1.8），不改俯仰 |
| PC | 中键按住 + 上下拖 | `_pitch`（向上拖 = 俯角变小 / 更平；向下拖 = 更陡） |
| PC | 中键按住 + 左右拖 | `yaw`（与 QE 并存） |
| PC | 右键拖 | 平移（不变） |
| PC | WASD / QE | 平移 / 旋转（不变） |
| PC | `zoom` 下限 | 0.6 → 0.16（近景观赏需要）；上限 1.8 不变 |
| 触屏 | 双指中点 / 间距 / 转角 | 平移 / 缩放 / 旋转（**不变**） |
| 触屏 | 俯仰 | 不做，锁 42° |

中键拖拽在 `in_hud_region` 内不生效，与滚轮同口径。

### D5 防穿模：最小视距

- 常量 `CAM_CLEAR_H := 10.0`（米，初始值；A2 实测后微调）。
- `_apply_cam()` 内：先按名义 `d=_dist*_zoom` 求相机位置，取该位置地面高度 + 净空作为下限；
  若 `d*sin(_pitch) < 下限` 且 `sin(_pitch)>0.01`，令 `d = 下限 / sin(_pitch)`（沿视线后退）。
- 实际俯仰角**不变**；只改距离。探针区分「名义俯仰」与「实际相机俯仰」两个量。
- 地面高度查询由 `view.gd` 组装时注入回调（`view_terrain.ground_h`），`view_core` 不直接引用 terrain。

### D6 默认口径冻结

- 默认档 = `zoom=1` + `_pitch=42°` + 最小视距不触发（`_dist≈80m`，`80m*sin42°≈54m > 10m`）。
`probe_shots`、`check_shots`、`probe_camcheck` 的默认档口径应零变化；若因最小视距触发了默认档，
视为实现 bug。

### D7 地图尺寸单点化

- 新建 `sim/dims.gd`：`MAP_N` / `MAP_HALF`，**B1 阶段值仍为 64**（零行为变化）。
- `scenario.w/h`、`view_core.CELL_N/HALF`、`blueprint.HALF/FINE_N`、`main.gd` 三处 `-31.5`、
  `verify.gd:82` 的 `>4096`、`probe_sync._edge_verts_expect` 的 `4096/13` 全部派生。
- 方向：`sim/` 不引用 `game/`；`game/` 引用 `sim/dims.gd`。

### D8 扩容玩法口径

用户裁定：**接受更大更长的局**。波次结构不动。

- 已知数学：路径长 ≈×2 → 同速怪物存活时间 ×2 → 同时在场怪数 ≈×2；塔位 ×4。
- 难度方向取决于矿位与经济是否随面积扩张。`wave_scale_pct` 保留为唯一补偿旋钮，
  在 B2 完成后按 `probe_balance` 实测再定，不在参数化阶段凭感觉改。
- `probe_balance` 三流派的胜负结论在 128 上是**新结果，不是回归失败**，需写入决策记录。

### D9 性能策略：先量后做

B1 之后先做 @128 空跑实测（B0），拿 `_compute_cell_top` / `_rebuild_hex` / 开图三项真实数字，
再决定 B3 用异步、降顶点还是分块。禁止按估值直接开工。

### D10 基线与存档

128 后默认图必须在 128 网格上重新设计并冻结（64 的字节冻结不可保留），因此：

- 16 指纹第十二次重录 + 剧本指纹重钉；
- `STATE_SCHEMA` 11 → 12（旧档自然拒载）；
- 存档门槛只走 `Canon.STATE_SCHEMA`，规格中不引入 `SAVE_FORMAT` 旧称。

## 5. 详细规格

### 5.1 相机数学

- `view_core` 新增：`_pitch` 可变、`pitch_by(delta)`、`set_pitch(rad)`（夹 18°~78°）。
- `_flat_forward()`、`pan_pixels()`、`_apply_cam()`、`_update_fit_cache()` 全部读当前 `_pitch`。
- `_map_visible_ratio()` 与 `_move_focus()`：
  - 当 `_zoom < 0.6`（近距）或 `_pitch < 30°`（低角）时，75% 判据不成立（地图必然出屏或四角
    在相机后方），放弃二分，改硬夹 focus 于 `±(HALF+4)`；
  - 其余情况保持现有 75% 二分回退逻辑不变。
- `camera.far` 仍 `max(400, d*2.2)`。

### 5.2 拾取加固（`view_terrain.pick_cell`）

- 迭代上限 2 → 4，命中格连续两次相同则提前退出；
- 新增相机后方守卫（`is_position_behind` 只用于最终结果回环校验，不替代求交）；
- 18°/20°/30° 俯角各做拾取回环断言（含崖壁、盆地、地图边缘）。

### 5.3 视觉随动

- DOF：`dof_blur_far_distance` 由固定 80 改为 `clamp(d*0.85, 40, 240)`；默认档仍需接近原值。
- `models.gd` 的 `LOD_TAN_HALF_FOV` 过期注释改为运行时读 `camera.fov`；阈值口径不变。
- 阴影 `directional_shadow_max_distance` 在 A 段不改（190 够用）；B4 再按 HALF 派生。

### 5.4 地图尺寸派生（B1，值仍 64）

新建 `sim/dims.gd`；所有 `64/32/63/4096/31.5` 常量改为派生；新增单测锁死
`Scenario.w == ViewCore.CELL_N == blueprint 派生值`。本段零行为变化，全闸应输出一致。

### 5.5 mapgen 参数化（B2）

- 约 96 处尺寸字面量改为 `n` 参数化，算法顺序与随机源调用序保持原样（除尺寸带来的必然变化）。
- 布局段字面量按 N 重推：`ARC_V_MAX`、周缘带、盆地试抽域、legacy 锚点。
- 默认种子 `_generate_default` 在 128 网格上重新设计并冻结；全部玩法不变量重新成立。

### 5.6 标定（B2）

- `PATH_REF` / `PATH_LO` / `PATH_HI`：64 种子 × 裸图路径长 sweep 重标（预计 ~×2）。
- `MAIN_D_MIN/MAX`、`PERIPH_BAND`、地形统计带（NZ/NEG 千分比）同步 sweep。
- 默认种子布局冻结后跑 `probe_balance`，只按结果调 `wave_scale_pct`。

### 5.7 性能（B3）

- `_compute_cell_top` 增量化：挖/填只重算受影响格 + 六邻。
- `_rebuild_hex`：worker 只算 `Packed*` 纯数组，主线程 `call_deferred` 提交 mesh；
  同帧多请求合并（只保留最后一次），避免拖拽挖堆积。
- GPU 上载成本单独实测（异步只解决 CPU）。
- 升级触发条件：主线程单次重建 >16ms 连续两帧 → 启用分块网格（另行评审）。

### 5.8 探针重钉（B4）

能派生一律派生，禁止新增硬编码：

| 探针 | 需改处 |
|---|---|
| `probe_scenario` | 尺寸断言 |
| `probe_scene` / `probe_selfcheck` | `field=4096`、`31.5/63` 边界 |
| `probe_sync` | 顶点账目（`4096/13`）、64 循环 |
| `probe_audio` | 63 界 ×7 |
| `probe_input` / `probe_promo_map` | 64 扫描 |
| `probe_save` | schema / 尺寸 |

## 6. 闸门

- A0/A1/A2：`probe_input`、`probe_gesture`、`probe_touch`、`probe_camcheck`、`probe_shots`、
  `check_shots`、`probe_sync`、`probe_smoke`、38 探针里与相机相关者全绿；单测全绿。
- B1：全 22 闸 + `check_shots` + `check_ui_lint`，输出应与 B1 前一致。
- B2/B3：全 22 闸 + 单测 + `probe_golden`（第十二次基线）。
- B4：全 22 闸 + `probe_balance` + `check_shots` + 128 截图目视。

## 7. 风险与回退

| 风险 | 触发信号 | 回退 |
|---|---|---|
| 18° 观感差（大半场外+雾） | 三张实机图目视不过 | 端点收窄到 24°/30° |
| 低角度拾取不收敛 | 专项回环断言红 | 迭代上限提高 + 步进求交 |
| @128 重建超预算 | B0 实测 >1.2s / 单次 >48ms | 先降顶点/减重建频率，再评估分块 |
| WorkerThreadPool 收益低 | 异步墙钟 <20% 改善 | 改分帧切片（主线程每帧一批） |
| 默认图重设计反复 | 不变量校验连续失败 | 固定模板兜底 + 先保证可玩 |
| 128 移动端负载 | 真机帧率/显存不达标 | 缩小视觉网格精度（场内 0.5m → 0.6m） |

## 8. 明确不做

- 流场数据结构 / 出桶顺序（保黄金回放）
- 触屏独立俯仰手势（本期）
- 分块网格（作为 B3 触发条件保留）
- 波次结构重做（只用 `wave_scale_pct` 补偿）
- 建造输入 / UI 路由 / 安卓返回的归属调整
