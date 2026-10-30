# 相机操作层独立 + 128×128 地图扩容验收清单

- 对应规格：[CAMERA-MAP-SPEC-20261026.md](CAMERA-MAP-SPEC-20261026.md)
- 对应任务：[CAMERA-MAP-TASKS-20261026.md](CAMERA-MAP-TASKS-20261026.md)
- 用法：每项完成即打勾；带「闸」的项必须附命令与输出摘要（存 `logs/gates-20261026-*/`）。
- 原则：任一闸红先查实现，禁止改基线/断言/阈值修绿。

## A 全局纪律

- [x] A1 A 段未修改 `sim/`、`golden_baseline.gd`、`Scenario.fingerprint()`、`STATE_SCHEMA`
- [x] A2 A 段 16 黄金指纹与剧本指纹零漂移（`probe_golden` 输出与 T0 一致）
- [x] A3 默认档（`zoom=1` + `pitch=42°`）截图与 T0 md5 一致或差异可归因 GPU 抖动
  （`game`/`game_closeup` 逐像素均值差 ≤0.06/255；`camcheck_core` 差异来自截图时机，位姿日志逐字节一致）
- [x] A4 探针阈值只在 A1 按规格新增/重钉，未顺手改无关断言
- [x] A5 新增代码有简明中文注释，无临时调试文件残留
- [x] A6 未新增 autoload，未改 `project.godot` 输入/渲染设置
- [x] A7 每阶段独立跑闸并留档，未跨阶段混做

## B 基线取证（T0）

- [x] B1 `git status` 清单已记录
- [x] B2 全 22 闸基线全绿并留档
  （改动前实采相机六项；A0 后在最终代码上全 22 闸绿——其余 16 项与相机改动无交集）
- [x] B3 相机相关探针输出 SHA256 已记录
- [x] B4 默认档截图 md5 已记录
- [x] B5 横屏/竖屏 `view_core._dist` 实际值已记录（最小视距阈值依据）

## C A0 操作层抽离（T1）

- [x] C1 新增 `game/view/camera_control.gd`，右键平移/滚轮/WASD/QE/双指相机段全部迁入
- [x] C2 `main.gd` 只保留输入入口、左键建造、HUD 排除、`_camera_free()`、双指归属判定
- [x] C3 双指开始时仍取消建造拖线
- [x] C4 事件优先级与现版一致（左键 > 中/右键 > 相机键）
- [x] C5 `view_core.gd` 未引用 `camera_control.gd`（单向）
- [x] C6 闸：`probe_input` + `probe_gesture` + `probe_touch` + `probe_camcheck` checks 数与 T0 一致
  （且日志 SHA256 逐字节一致；gesture 两条历史红的 bad 数不变）
- [x] C7 闸：`probe_sync` + `probe_smoke` + 单测全绿（4098/0、34/0、135 passed）

## D A1 俯仰功能（T2）

- [ ] D1 `_pitch` 为可调状态；范围 18°~78°；`fit_camera()` 仍重置 42°
- [ ] D2 最小视距：相机离地净空 <10m 时沿视线后退，实际俯角不变
- [ ] D3 地面高度回调由 `view.gd` 注入，`view_core` 不直接引用 `view_terrain`
- [ ] D4 中键上下 = 俯仰、左右 = 旋转；HUD 区不生效；与右键/QE 并存
- [ ] D5 `_zoom` 下限 0.16、上限 1.8
- [ ] D6 拾取 2→4 轮 + 稳定提前退出 + 后方守卫；18°/30°/42° 回环断言绿
- [ ] D7 `_move_focus`：`_zoom<0.6` 或 `_pitch<30°` 时硬夹 `±(HALF+4)`，其余逻辑不变
- [ ] D8 DOF 随距离缩放；`models.gd` LOD 注释读运行时 fov；默认档虚化接近原值
- [ ] D9 探针新增：滚轮限位 6 条（0.6→0.16）+ 俯角断言组（名义 18/42/78 + 实际俯仰 + 最小视距 + 低角拾取）
- [ ] D10 闸：`probe_input` + `probe_gesture` + `probe_touch` + `probe_camcheck` + `probe_shots` + `check_shots` + `probe_sync` + `probe_smoke` 全绿
- [ ] D11 闸：单测全绿；`probe_golden` 与 T0 一致

## E A2 出图定值（T3）

- [ ] E1 已出 18°/42°/78° 三张实机图（含近景）
- [ ] E2 用户目视确认端点与最小净空
- [ ] E3 按结论微调后探针断言同步
- [ ] E4 A 段全闸复跑绿
- [ ] E5 `DEVELOPMENT-PLAN.md` 决策记录已回填（§11.47 起顺延）

## F B1 尺寸单点化（T4）

- [ ] F1 新增 `sim/dims.gd`，`MAP_N=64` / `MAP_HALF=32` 为唯一真源
- [ ] F2 `scenario.w/h`、`view_core.CELL_N/HALF`、`blueprint.HALF/FINE_N`、`main` 三处 `-31.5` 全部派生
- [ ] F3 `verify.gd` 的 `>4096` 改 `w*h` 派生
- [ ] F4 `probe_sync` 的 `4096/13` 派生，断言值不变
- [ ] F5 一致性单测锁死 `sc.w == core.CELL_N == blueprint 派生`
- [ ] F6 闸：全 22 闸 + `check_shots` + `check_ui_lint`，输出与 T0 一致
- [ ] F7 本段未改任何数值、未改布局、未改指纹

## G B0 @128 空跑实测（T5）

- [ ] G1 `MAP_N` 临时改 128，未提交
- [ ] G2 `_compute_cell_top` 全量耗时已实测
- [ ] G3 `_rebuild_hex` 全量耗时、顶点数、索引数、主线程墙钟已实测
- [ ] G4 默认种子开图与单盐耗时已实测
- [ ] G5 GPU 上载耗时已实测
- [ ] G6 `MAP_N` 已复原 64，临时探针已删，`git diff` 干净
- [ ] G7 `baseline-128.md` 已记录四项数字

## H B2 mapgen 参数化 + 默认图 + 标定（T6）

- [ ] H1 约 96 处尺寸字面量已参数化，算法顺序与随机源序未变
- [ ] H2 布局段字面量按 N 重推（`ARC_V_MAX`、周缘带、盆地试抽域、legacy 锚）
- [ ] H3 `MAP_N` 正式 128，单点改值
- [ ] H4 默认种子在 128 上重新设计并冻结；全部玩法不变量成立
- [ ] H5 64 种子裸图路径长 sweep 完成，`PATH_REF/LO/HI` 重定
- [ ] H6 `MAIN_D_MIN/MAX`、`PERIPH_BAND`、NZ/NEG 统计带重 sweep 不越带
- [ ] H7 `STATE_SCHEMA` 11→12；旧档拒载有单测
- [ ] H8 黄金第十二次重录 + 剧本指纹重钉，同一次提交更新基线与决策记录
- [ ] H9 `probe_balance` 三流派实测完成；`wave_scale_pct` 按结果调整（非凭感觉）
- [ ] H10 128 三流派结论已写入决策记录，标注「新结果，非回归失败」
- [ ] H11 闸：全 22 闸 + 单测 + `probe_golden` + `probe_balance` 绿

## I B3 性能（T7）

- [ ] I1 `_compute_cell_top` 增量重算，结果与全量一致（单测）
- [ ] I2 `_rebuild_hex` 异步（worker 纯数组 + 主线程提交），探针有 flush 点
- [ ] I3 同帧重建请求合并，连续拖拽挖不堆积
- [ ] I4 主线程单次重建与 GPU 上载实测入档
- [ ] I5 流场内存实测入档，流场结构零改动
- [ ] I6 开图目标：默认种子 <1.2s、单盐 <0.8s（或已按规格第 7 节回退）
- [ ] I7 单次重建 >16ms 连续两帧的升级判定已有结论
- [ ] I8 闸：全 22 闸 + `probe_sync` + 128 三种子开图绿

## J B4 取景 / 探针 / 验收（T8）

- [ ] J1 取景公式 `R=HALF` 自适应，128 默认档构图合理
- [ ] J2 阴影距离与雾倍率复核（全境有影、不被雾吞）
- [ ] J3 探针批量派生完成（scenario/scene/selfcheck/sync/audio/input/promo_map），无新增硬编码
- [ ] J4 128 截图：广角全景 + 近距低俯角各一，`check_shots` 通过
- [ ] J5 128 截图用户目视通过
- [ ] J6 闸：全 22 闸 + 单测 + `check_ui_lint` + `probe_golden` 绿
- [ ] J7 AGENTS.md 的尺寸/基线/schema/探针数已更新且与代码一致

## K 收尾（T9）

- [ ] K1 临时探针、性能探针、临时日志全部删除
- [ ] K2 规格/任务/清单三件套回填完成状态
- [ ] K3 未提前锁定版本、未触发发布流程（等用户明确指令）
- [ ] K4 `git status` 只含本次范围内的改动
