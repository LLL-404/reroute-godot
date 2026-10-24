# 界面全量场景化验收清单

- 对应规格：[SCENE-MIGRATION-SPEC-20261022.md](SCENE-MIGRATION-SPEC-20261022.md)
- 用法：每项完成即打勾；带「闸」的项必须附命令与输出摘要。
- 原则：任一闸红先查实现，禁止改基线/断言/阈值修绿。

## A 全局纪律

- [x] A1 未修改 `sim/`、`golden_baseline.gd`、`Scenario.fingerprint()`、`STATE_SCHEMA`
- [x] A2 未改动 16 个黄金指纹与剧本指纹 `0x7dea2b02`
- [x] A3 未改动任何探针断言、阈值、截图文件名（仅按 D4 修改组件的实例化入口：privacy/intro/hud/input/sync 五支）
- [x] A4 未改动前序已验收的诊断修复、启动过渡、地形多线程采样、取景光照改动
- [x] A5 新增/修改的 `.tscn` 不含样式资源、`theme_override_*`、`custom_minimum_size`
- [x] A6 所有节点名、父子层级、兄弟顺序与改造前逐位一致
- [x] A7 样式仍只经 `ui_style.gd`；S 仍只由 `_recalc_s()/apply_ui_scale()` 计算
- [x] A8 未新增 autoload、未改 `project.godot` 的输入/渲染设置
- [x] A9 关键逻辑有简明中文注释；无临时调试文件残留
- [x] A10 `check_ui_lint.py` 的 L4 已生效且通过

## B Phase 0 基线取证

- [x] B1 `git status` 清单已记录，确认前序未提交改动范围
- [x] B2 单测通过并留存输出（实际 `passed=107 failed=0`）
- [x] B3 `probe_scene` 通过并留存输出
- [x] B4 `check_shots.py` 通过并留存输出
- [x] B5 `check_ui_lint.py` 通过并留存输出
- [x] B6 `shots/*.png` 的 md5 清单已记录到 `logs/gates-20261022-scene-baseline/`
- [x] B7 冷启动与开局耗时基线已记录（约 3.7s / 2202ms）
- [x] B8 L4 检查实现完成：扫描 `game/**/*.tscn` 的禁止 token，输出 `[UI-LINT] PASS`
- [x] B9 L4 对现有 `main.tscn` 无违规

## C Phase 1 隐私门 + 开屏

### C1 隐私门

- [x] C1-1 新增 `game/privacy_gate.tscn`，根 CanvasLayer 挂 `privacy_gate.gd`
- [x] C1-2 节点 `PrivacyRoot/bg/card/title/body/btn_privacy_link/btn_privacy_agree/btn_privacy_decline` 齐全
- [x] C1-3 `privacy_gate.gd` 删除结构构造，`_ready()` 只做绑定、S 化样式、信号连接
- [x] C1-4 标题文案、正文长度 ≥120、同意/拒绝信号行为不变
- [x] C1-5 `main.gd` 用 `preload("res://game/privacy_gate.tscn").instantiate()`
- [x] C1-6 `probe_privacy.gd` 仅改实例化入口，断言零改动
- [x] C1-7 闸：`probe_privacy` PASS

### C2 开屏

- [x] C2-1 新增 `game/intro.tscn`，根 CanvasLayer 挂 `intro.gd`
- [x] C2-2 UI 节点 `IntroRoot/IntroTex/IntroBlack/IntroWorld/IntroUi/GoldRule/Tagline` 齐全
- [x] C2-3 `_build_ui()` 的结构构造删除；逐字「改」「道」仍在场景中，字号运行时设置
- [x] C2-4 `_build_3d()` 保留脚本装配，字段 `_sub/_black/_char_labels/_tagline/_rule` 绑定不变
- [x] C2-5 `main.gd` 用场景实例化；`_play_intro()` 时机不变
- [x] C2-6 `probe_intro.gd` 五个实例全部改为场景实例化，断言零改动
- [x] C2-7 闸：`probe_intro` PASS
- [x] C2-8 闸：106 单测 + `probe_scene` + `check_ui_lint` PASS

## D Phase 2 HUD

- [x] D1 新增 `game/hud.tscn`，根 Control 挂 `hud.gd`
- [x] D2 顶栏节点齐全：`top_bar/lbl_core/lbl_wave/hp_bar/hp_text/divider/wave_text/supply_caption/supply_text/heat_btn/pause_btn` + 两个 `UiIcon`
- [x] D3 提示、指挥盘、撤销、横幅、10 个浮字节点齐全；指挥盘 8 格结构完整
- [x] D4 `build(cb)` 改为绑定 + 统一样式注入；回调字典五项不变
- [x] D5 `_layout()` 公式与 `hit_regions()` 返回矩形**零改动**
- [x] D6 `set_visible_hud/set_mode/_paint_rows/_update_affordability/_paint_skill/_update_hint/float_bounty/banner` 行为不变
- [x] D7 `main.gd` 用场景实例化，`hud_layer` 层级 10 与挂载顺序不变
- [x] D8 闸：`probe_hud` PASS（含 34 组 checks）
- [x] D9 闸：`probe_input` + `probe_sync` PASS
- [x] D10 闸：`probe_touch` PASS（HUD 暂停钮触屏链路）
- [x] D11 闸：`probe_smoke` + `probe_shots` + `check_shots` PASS

## E Phase 3 界面壳（5 页 + 确认 + 黑幕）

- [x] E1 新增 `game/screens.tscn`：`ScreenHost` / `Veil` / `ConfirmLayer` 层级与顺序正确
- [x] E2 新增 `game/pages/title.tscn`，节点名符合 D3 契约
- [x] E3 新增 `game/pages/pause.tscn`，节点名符合 D3 契约
- [x] E4 新增 `game/pages/gameover.tscn`，`go_title/go_body` 为 Label 且可绑定
- [x] E5 新增 `game/pages/slots.tscn`，3 行槽位与删除钮、占位 `pad_slot_delN` 齐全
- [x] E6 新增 `game/pages/settings.tscn`，四组 + 关于组、全部 `row_/btn_/sld_/lbl_` 节点齐全
- [x] E7 `_build_*` 改为 `_bind_*`；`pages` 字典、`current`、`_ensure/_show` 语义不变
- [x] E8 `_build_confirm` 改绑定；`confirm_layer/confirm_text/btn_confirm_ok/btn_confirm_cancel` 字段不变
- [x] E9 `_build_veil` 改绑定；`veil_root/veil_label` 字段与淡入淡出不变
- [x] E10 `_page_base` 的幕色与 `UiStyle.overlay_fx()` 仍运行时注入
- [x] E11 删除仅用于构建的工厂函数；保留的样式注入统一收敛，无重复构造
- [x] E12 `apply_ui_scale/_rebuild_pages/_recalc_s` 行为不变（滑动中不拆当前页）
- [x] E13 闸：`probe_ui_flow` PASS
- [x] E14 闸：`probe_save` PASS（含设置滑杆、覆盖/删除确认、退出 spy、安卓返回）
- [x] E15 闸：`probe_touch` PASS，按钮矩阵**恰为 56**且尺寸下限全达标
- [x] E16 闸：`probe_smoke` PASS（标题→开战→结算→冻结）
- [x] E17 闸：`probe_shots` + `check_shots` PASS；`title/slots/settings/gameover` 截图无异常
- [x] E18 闸：`check_ui_lint` PASS

## F Phase 4 肉鸽 UI

- [x] F1 新增 `game/run_ui.tscn`，静态容器 `RunRoot/BottomHolder/hand_row/bar/bar_body/toast` 齐全
- [x] F2 `run_ui.gd` 的 `init()` 只绑定；`refresh()` 动态生成行为不变
- [x] F3 新增 `game/hex_picker.tscn`，`HexRoot/dim/vignette/title/card_layer/foot` 齐全
- [x] F4 新增 `game/hex_card.tscn`，根 `cardN` + `glow` 子节点
- [x] F5 `open()` 实例化三张卡，入场/悬停/选中 Tween 与 `_set_dock_visible` 不变
- [x] F6 `main.gd` 用场景实例化，layer 11/12 与挂载顺序不变
- [x] F7 闸：`probe_rogue_ui` + `probe_rogue_shot` + `probe_hex_shot` PASS
- [x] F8 闸：`probe_touch` + `check_ui_lint` PASS

## G Phase 5 全闸回归

- [x] G1 全部正式 headless 闸通过
- [x] G2 全部正式窗口闸通过
- [x] G3 `check_shots.py` PASS（checks=44；该脚本为关键色统计判定，非逐像素，见 baseline.md）
- [x] G4 `check_ui_lint.py` PASS（L1–L4）
- [x] G5 16 个黄金指纹与剧本指纹未变
- [x] G6 md5 差异来源已查明（地面美术改动导致背景整体变亮，截图体积增大），6 张 UI 截图已逐张目视确认布局正常；记录见 `logs/gates-20261022-scene-final/status.txt`
- [x] G7 迁移直接新增开销 24~34ms（冷启动 ≤0.8%、开局约 1%）≤5% 通过；绝对值受蓝图预设与机器状态影响，见 status.txt 第四节
- [x] G8 `git status` 中本次新增/修改均为规格内文件与证据日志；`_tmp_*` 临时探针与日志已全部清理（其余条目为前序未提交改动）
- [x] G9 三份规格文档与本清单同步更新（如有决策变更）

## H 场景静态审查（每个新增 .tscn 逐项）

- [x] H1 无 `custom_minimum_size`、`size`、`position`、`offset_*`（全屏锚点除外）
- [x] H2 无 `theme_type_variation`、`theme_override_*`、`theme =`
- [x] H3 无 `StyleBoxFlat`、`type="Theme"`、`GradientTexture2D`、`NoiseTexture2D`、`ShaderMaterial`
- [x] H4 无硬编码颜色（`Color(...)`）与字号
- [x] H5 `ext_resource` 只用 `path`，脚本路径正确
- [x] H6 节点名与 D3 契约逐字一致
- [x] H7 根节点类型与挂脚本正确
- [x] H8 `L4` lint 对全部新增场景 PASS

## I 交付

- [x] I1 规格、清单、任务三份文档评审通过并保持同步
- [x] I2 每阶段闸门输出留存于 `logs/gates-20261022-scene-*`
- [x] I3 未获「发铺」指令不启动版本冻结/导出/提审
- [x] I4 未获授权不创建 commit
