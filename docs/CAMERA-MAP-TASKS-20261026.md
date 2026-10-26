# 相机操作层独立 + 128×128 地图扩容任务拆解

- 对应规格：[CAMERA-MAP-SPEC-20261026.md](CAMERA-MAP-SPEC-20261026.md)
- 对应清单：[CAMERA-MAP-CHECKLIST-20261026.md](CAMERA-MAP-CHECKLIST-20261026.md)
- 执行前提：**用户明确批准本规格**；未批准不执行任何任务。
- 顺序：T0 → T1 → T2 → T3（A 段交付）→ T4 → T5 → T6 → T7 → T8 → T9；每段闸绿再进下一段。

## 0. 通用约定

- 每阶段收尾跑该阶段闸门，输出存 `logs/gates-20261026-<phase>/`。
- A 段禁止改 `sim/`；B1 禁止改任何数值；B2 起才允许改尺寸与参数。
- 任一闸红先查实现，禁止改基线/断言/阈值修绿（AGENTS.md 第六节）。
- 不创建 commit（除非用户另行授权）。

## T0 基线取证

| 编号 | 动作 | 文件 | DoD |
|---|---|---|---|
| T0-1 | 记录 `git status --short` 与未提交改动范围 | - | 存 `logs/gates-20261026-camera-baseline/status.txt` |
| T0-2 | 跑全 22 闸基线 | - | 全绿，输出留档 |
| T0-3 | 记录相机相关探针输出（`probe_input`/`probe_gesture`/`probe_camcheck`/`probe_shots`）SHA256 | - | `sha.txt` 留档 |
| T0-4 | 记录默认档截图 md5 与开图耗时 | - | `baseline.md` |
| T0-5 | 记录 `view_core._dist` 实际值（横屏/竖屏） | - | 写入 `baseline.md`（最小视距阈值依据） |

闸门：T0-2 全绿。

## T1 A0 操作层抽离（纯搬移，零行为变化）

| 编号 | 动作 | 文件 | DoD |
|---|---|---|---|
| T1-1 | 新建 `CameraControl`：收右键平移、滚轮、WASD/QE、双指相机段 | `game/view/camera_control.gd` | 公开方法语义与现 `main.gd` 分支一一对应 |
| T1-2 | `main.gd` 改为转发事件；保留左键建造、HUD 排除、`_camera_free()`、双指归属判定 | `game/app/main.gd` | 事件优先级与现版一致（左键 > 中/右键 > 相机键） |
| T1-3 | 双指手势的相机三动作迁入；建造取消仍在 main | `game/app/main.gd` / `camera_control.gd` | 双指开始仍取消建造拖线 |
| T1-4 | 探针零改动 | `tests/probes/` | `probe_input`/`probe_gesture`/`probe_touch`/`probe_camcheck` 的 checks 数与输出一致 |
| T1-5 | 补简明中文注释 | 两文件 | 无临时调试残留 |

闸门：相机相关探针 + 单测 + `probe_sync` 全绿；输出与 T0-3 SHA 一致（允许无关行号差异时人工比对）。

## T2 A1 俯仰功能

| 编号 | 动作 | 文件 | DoD |
|---|---|---|---|
| T2-1 | `_pitch` 改为可调状态；新增 `PITCH_MIN=18°`/`PITCH_MAX=78°`/`pitch_by()`/`set_pitch()` | `game/view/view_core.gd` | `fit_camera()` 仍重置 42°；默认档零变化 |
| T2-2 | 新增最小视距：`CAM_CLEAR_H=10m`，相机脚下地面高 + 净空，不足则沿视线后退 | `view_core.gd` | 实际俯仰角不变；默认档不触发 |
| T2-3 | 地面高度回调注入 | `game/view/view.gd` | `view_core` 不直接引用 `view_terrain` |
| T2-4 | 中键拖拽：上下 pitch、左右 yaw；HUD 区不生效 | `game/view/camera_control.gd` | 与右键平移、QE 并存不冲突 |
| T2-5 | `_zoom` 下限 0.6 → 0.16 | `view_core.gd` | 上限 1.8 不变 |
| T2-6 | 拾取迭代 2 → 4 + 稳定提前退出 + 后方守卫 | `game/view/view_terrain.gd` | 18°/30°/42° 回环断言全绿 |
| T2-7 | `_move_focus`：`_zoom<0.6` 或 `_pitch<30°` 时硬夹 `±(HALF+4)` | `view_core.gd` | 其余情况 75% 逻辑不变 |
| T2-8 | DOF 随 `d` 缩放；`models.gd` LOD 注释改运行时读 `fov` | `view_core.gd` / `models.gd` | 默认档虚化值接近原 80 |
| T2-9 | 探针重钉：滚轮限位 6 断言（0.6→0.16）+ 俯角耦合组（18/42/78 + 最小视距 + 低角拾取） | `tests/probes/probe_input.gd` 等 | 新断言覆盖名义与实际俯仰 |
| T2-10 | 操作表同步 | `docs/README.tech.md`（若有） | 中键说明入表 |

闸门：`probe_input`、`probe_gesture`、`probe_touch`、`probe_camcheck`、`probe_shots`、`check_shots`、
`probe_sync`、`probe_smoke` + 单测全绿。

## T3 A2 出图定值

| 编号 | 动作 | 文件 | DoD |
|---|---|---|---|
| T3-1 | 出 18°/42°/78° 三张实机图（广角+近景各一组） | `shots/` | 可目视 |
| T3-2 | 用户目视确认端点与最小净空 | - | 结论写入规格 D4/D5 |
| T3-3 | 按结论微调端点/`CAM_CLEAR_H` | `view_core.gd` | 探针断言同步 |
| T3-4 | A 段收尾记录（决策与证据） | `docs/DEVELOPMENT-PLAN.md` | §11.47（以实际最大编号顺延） |

闸门：A 段全闸复跑绿。

## T4 B1 尺寸单点化（值仍 64，零行为变化）

| 编号 | 动作 | 文件 | DoD |
|---|---|---|---|
| T4-1 | 新建尺寸常量 `MAP_N`/`MAP_HALF`（本段值 64） | `sim/dims.gd` | 只有一处真源 |
| T4-2 | `Scenario.w/h` 派生 | `sim/scenario.gd` | 布局字节不变 |
| T4-3 | `CELL_N`/`HALF` 派生 | `game/view/view_core.gd` | const 依赖方向合法 |
| T4-4 | `blueprint.HALF/FINE_N` 派生 | `game/core/blueprint.gd` | 视觉网格不变 |
| T4-5 | 三处 `-31.5` 派生 | `game/app/main.gd` | 值不变 |
| T4-6 | `bd > 4096` 改 `w*h` 派生 | `sim/verify.gd` | 行为不变 |
| T4-7 | `probe_sync` 的 `4096/13` 派生 | `tests/probes/probe_sync.gd` | 断言值不变 |
| T4-8 | 一致性单测 | `tests/test_scenario.gd` 等 | `sc.w == core.CELL_N == blueprint 派生` 锁死 |

闸门：全 22 闸 + `check_shots` + `check_ui_lint`；输出应与 T0 基线一致。

## T5 B0 @128 空跑实测（先量后做）

| 编号 | 动作 | 文件 | DoD |
|---|---|---|---|
| T5-1 | 临时把 `MAP_N` 改 128（**不提交**） | `sim/dims.gd` | 记录改前改后 |
| T5-2 | 实测 `_compute_cell_top` 全量耗时 | 临时探针 | 数值入 `baseline-128.md` |
| T5-3 | 实测 `_rebuild_hex` 全量耗时（顶点数、索引数、主线程墙钟） | 临时探针 | 同上 |
| T5-4 | 实测默认种子开图与单盐耗时 | 同上 | 同上 |
| T5-5 | 实测 GPU 上载（`add_surface_from_arrays` 前后时间） | 同上 | 同上 |
| T5-6 | 复原 `MAP_N=64`，删除临时探针 | - | `git diff` 干净 |

闸门：T5-1 不产生提交；T5-6 后全闸复绿。

## T6 B2 mapgen 参数化 + 默认图重设计 + 标定

| 编号 | 动作 | 文件 | DoD |
|---|---|---|---|
| T6-1 | 约 96 处 `4096`/`y*64+x`/63 边界改 `n` 参数化 | `sim/mapgen.gd` | 算法顺序不变；无新增随机源 |
| T6-2 | 布局段字面量按 N 重推（`ARC_V_MAX`、周缘带、盆地试抽域、legacy 锚） | `sim/mapgen.gd` | 生成不崩、结构自检可过 |
| T6-3 | `MAP_N` 正式改 128 | `sim/dims.gd` | 单点改值 |
| T6-4 | 默认种子 `_generate_default` 在 128 上重新设计并冻结 | `sim/scenario.gd` / `mapgen.gd` | 核心山头/主口净空/盆地/中场矿/路径带全部成立 |
| T6-5 | 64 种子裸图路径长 sweep，重定 `PATH_REF/LO/HI` | `sim/scenario.gd` | 带内命中率与 64 版同口径 |
| T6-6 | `MAIN_D_MIN/MAX`、`PERIPH_BAND`、NZ/NEG 统计带重 sweep | `scenario.gd` / `mapgen.gd` | 不越带 |
| T6-7 | `STATE_SCHEMA` 11 → 12 | `sim/canon.gd` | 旧档拒载有单测 |
| T6-8 | 黄金第十二次重录 + 剧本指纹重钉 | `sim/golden_baseline.gd` | 同一次提交内更新基线与决策记录 |
| T6-9 | `probe_balance` 三流派实测；只按结果调 `wave_scale_pct` | `sim/scenario.gd` | 结论写入决策记录（新结果，非回归） |

闸门：全 22 闸 + 单测 + `probe_golden` + `probe_balance` 绿。

## T7 B3 性能

| 编号 | 动作 | 文件 | DoD |
|---|---|---|---|
| T7-1 | `_compute_cell_top` 增量：只重算受影响格 + 六邻 | `view_terrain.gd` | 挖/填后顶部与全量重算一致（单测） |
| T7-2 | `_rebuild_hex` 异步：worker 只算 `Packed*`，主线程 `call_deferred` 提交 | `view_terrain.gd` | 探针有 flush 点（等待完成） |
| T7-3 | 同帧请求合并（只保留最后一次） | `view_terrain.gd` | 连续拖拽挖不堆积 |
| T7-4 | 实测主线程单次重建与 GPU 上载 | - | 写入 `baseline-128.md` |
| T7-5 | 流场内存实测（head 桶 ×4） | `sim/flowfield.gd` 只读 | 数值入档，不改结构 |
| T7-6 | 开场目标验收：默认种子 <1.2s、单盐 <0.8s | - | 达标；不达标按规格第 7 节回退 |
| T7-7 | 升级判定：单次 >16ms 连续两帧 → 启用分块（另行评审） | - | 结论入档 |

闸门：全 22 闸 + `probe_sync` + 128 三种子开图实测通过。

## T8 B4 取景 / 探针 / 验收

| 编号 | 动作 | 文件 | DoD |
|---|---|---|---|
| T8-1 | 取景公式 `R=HALF` 自适应 | `view_core.gd` | 128 默认档构图合理 |
| T8-2 | 阴影 `190→~300`、雾 `_fog_fit_mult` 复核 | `view_core.gd` | 地图全境有影、不被雾吞 |
| T8-3 | 探针批量派生（scenario/scene/selfcheck/sync/audio/input/promo_map） | `tests/probes/` | 无新增硬编码 |
| T8-4 | 128 截图：广角全景 + 近距低俯角 | `shots/` | `check_shots` 通过 + 目视 |
| T8-5 | 全 22 闸 + 单测 + lint | - | 全绿 |
| T8-6 | 决策记录与 AGENTS.md 数据更新（尺寸/基线/schema/探针数） | `docs/DEVELOPMENT-PLAN.md` / `AGENTS.md` | 与代码实际一致 |

闸门：全 22 闸 + `check_shots` + `check_ui_lint` + `probe_golden` 绿。

## T9 收尾

| 编号 | 动作 | DoD |
|---|---|---|
| T9-1 | 删除所有临时探针、性能探针、临时日志 | 仓库干净 |
| T9-2 | 更新 AGENTS.md 的尺寸/基线/schema/探针数 | 无漂移 |
| T9-3 | 规格、任务、清单三件套回填完成状态 | 与实际一致 |
| T9-4 | 用户确认后再打包（包体暂停更新期不触发发布流程） | 未提前锁定版本 |
