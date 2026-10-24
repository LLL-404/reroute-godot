# 界面全量场景化任务拆解

- 对应规格：[SCENE-MIGRATION-SPEC-20261022.md](SCENE-MIGRATION-SPEC-20261022.md)
- 对应清单：[SCENE-MIGRATION-CHECKLIST-20261022.md](SCENE-MIGRATION-CHECKLIST-20261022.md)
- 执行前提：**用户明确批准本规格**；未批准不执行任何任务。
- 顺序：T0 → T1 → T2 → T3 → T4/T5/T6 → T7/T8 → T9；T10 需另行拍板。

## 0. 通用约定

### 0.1 场景创建方式

- 全部 `.tscn` 手工编写（`Write`），不依赖编辑器 GUI。
- `[gd_scene load_steps=N format=3]`，`ext_resource` 用 `path`，不写 `uid`。
- 首次被 Godot 加载后，编辑器可能补 `uid` 与 `.uid` 文件，保留即可。
- 场景只含结构，禁止项见规格 D1；每个场景写完立即跑 L4。

### 0.2 绑定层统一模板

每个组件按同一顺序改造（示例为 HUD）：

```gdscript
# 1) 场景常量：启动期预加载，避免运行时 load 抖动
const HUD_SCENE := preload("res://game/hud.tscn")

# 2) 实例化后立即绑定（此时子节点已存在，尚未入树）
func build(cb: Dictionary) -> void:
	_bind_nodes()        # 取引用，字段名保持不变
	_apply_theme()       # 样式仍走 UiStyle（主题变体/光边/字号 × S）
	_connect(cb)         # 信号与回调字典不变
	_layout()            # 原公式布局，一字不改
```

纪律：`_bind_nodes()` 只做 `get_node`/`find_child` 与字段赋值；任何尺寸、字号、颜色
不得写入 `.tscn`。

### 0.3 每阶段收尾

- 跑该阶段闸门（见规格第 6 节），输出存 `logs/gates-20261022-scene-<phase>/`。
- 自检 `git diff --stat`，确认只含本阶段文件。
- 不创建 commit（除非用户另行授权）。

## T0 基线取证与 L4 守卫

| 编号 | 动作 | 文件 | DoD |
|---|---|---|---|
| T0-1 | 记录 `git status --short` 与未提交改动范围 | - | 清单存 `logs/gates-20261022-scene-baseline/status.txt` |
| T0-2 | 跑 106 单测、`probe_scene`、`check_shots`、`check_ui_lint` | - | 四项 PASS，输出留档 |
| T0-3 | 记录 `shots/*.png` md5 | - | `md5.txt` 留档 |
| T0-4 | 记录冷启动/开局耗时 | - | 数值写入 `baseline.md` |
| T0-5 | 新增 L4 规则 | `tools/check_ui_lint.py` | 扫描 `game/**/*.tscn`，禁用 token 命中即 FAIL；现有 `main.tscn` PASS |

闸门：T0-2 四项全绿；T0-5 后 `check_ui_lint` PASS。

## T1 隐私门场景化

| 编号 | 动作 | 文件 | DoD |
|---|---|---|---|
| T1-1 | 新建场景，根 CanvasLayer 挂 `privacy_gate.gd` | `game/privacy_gate.tscn` | `PrivacyRoot/bg/card/title/body/btn_privacy_link/btn_privacy_agree/btn_privacy_decline` 齐全 |
| T1-2 | 删除 `_build()` 的结构构造，改 `_bind()` | `game/privacy_gate.gd` | 只保留绑定、S 化样式、信号；`agreed/declined` 行为不变 |
| T1-3 | 改 main 实例化入口 | `game/main.gd` `_show_privacy_gate()` | 用 `preload(...tscn).instantiate()`，时机不变 |
| T1-4 | 改探针实例化入口 | `tests/probes/probe_privacy.gd` | 仅入口改，断言零改动 |

闸门：`probe_privacy` PASS；106 单测 + `probe_scene` + `check_ui_lint` PASS。

## T2 开屏场景化

| 编号 | 动作 | 文件 | DoD |
|---|---|---|---|
| T2-1 | 新建场景，根 CanvasLayer 挂 `intro.gd`；UI 节点齐全，「改」「道」逐字 Label 入场景 | `game/intro.tscn` | `IntroRoot/IntroTex/IntroBlack/IntroWorld/IntroUi/GoldRule/Tagline` 齐全 |
| T2-2 | 删除 `_build_ui()` 结构构造，改绑定；字号仍按 S 设置 | `game/intro.gd` | `_char_labels/_tagline/_rule/_sub/_black` 字段保持 |
| T2-3 | 保留 `_build_3d()` 脚本装配 | `game/intro.gd` | 相机/灯光/环境/粒子/光团逻辑不变 |
| T2-4 | 改 main 实例化入口 | `game/main.gd` `_play_intro()` | 场景实例化，`begin()` 参数不变 |
| T2-5 | 改探针五个实例入口 | `tests/probes/probe_intro.gd` | 仅入口改，36 项断言零改动 |

闸门：`probe_intro` PASS；106 单测 + `probe_scene` + `check_ui_lint` PASS。

## T3 HUD 场景化

| 编号 | 动作 | 文件 | DoD |
|---|---|---|---|
| T3-1 | 新建场景，根 Control 挂 `hud.gd`；顶栏/提示/指挥盘 8 格/撤销/横幅/10 浮字入场景 | `game/hud.tscn` | 节点名按规格 D3；格按钮含 `UiIcon` 占位节点 |
| T3-2 | `build(cb)` 改「绑定 + 样式 + 连接」；删除 `_build_top_bar/_build_hint/_build_dock/_build_undo/_build_banner/_build_floats` 的节点构造 | `game/hud.gd` | 回调字典五项不变；`mode_buttons/dock_rows/row_name/row_cost` 结构不变 |
| T3-3 | 保留 `_layout()` 与 `hit_regions()` | `game/hud.gd` | 公式与返回矩形零改动 |
| T3-4 | 改 main 实例化入口 | `game/main.gd` `_setup_hud()` | `const preload`；layer 10 与顺序不变 |

闸门：`probe_hud`、`probe_input`、`probe_sync`、`probe_touch`、`probe_smoke`、`probe_shots`、`check_shots`、`check_ui_lint` 全 PASS。

## T4 壳场景（ScreenHost / Veil / Confirm）

| 编号 | 动作 | 文件 | DoD |
|---|---|---|---|
| T4-1 | 新建壳场景，根 CanvasLayer 挂 `screens.gd`；子节点顺序 `ScreenHost` → `Veil` → `ConfirmLayer` | `game/screens.tscn` | 确认层在页面之上；两者默认隐藏 |
| T4-2 | `init()` 改为绑定场景节点 + 设主题；删除 `_build_veil/_build_confirm` 构造 | `game/screens.gd` | `host/veil_root/veil_label/confirm_layer/confirm_text` 字段不变 |
| T4-3 | 保留 `open_confirm/close_confirm/_resolve_confirm` 行为 | `game/screens.gd` | 确认弹窗文案与按钮顺序不变 |
| T4-4 | 改 main 实例化入口 | `game/main.gd` `_setup_shell()` | 回调字典 11 项不变；layer 20 |

闸门：本阶段结束随 T5/T6 一起跑壳相关闸。

## T5 五页面场景化

| 编号 | 动作 | 文件 | DoD |
|---|---|---|---|
| T5-1 | 标题页场景 | `game/pages/title.tscn` | `page_title/title_veil/btn_rogue/btn_start/btn_continue/btn_settings/btn_tips/btn_quit/panel_tips` |
| T5-2 | 暂停页场景 | `game/pages/pause.tscn` | `page_pause/btn_resume/btn_save/btn_settings_pause/btn_restart/btn_to_title` |
| T5-3 | 结算页场景 | `game/pages/gameover.tscn` | `page_gameover/go_title/go_body/btn_again/btn_to_title2` |
| T5-4 | 存档页场景 | `game/pages/slots.tscn` | `label_slot_head/btn_slotN/btn_slot_delN/pad_slot_delN/label_slot_status/btn_slots_back` |
| T5-5 | 设置页场景 | `game/pages/settings.tscn` | 四组 + 关于组，全部 `row_/btn_/sld_/lbl_*_val` |
| T5-6 | `_ensure` 改 `load(scene).instantiate()`；`_build_*` 改 `_bind_*` | `game/screens.gd` | `pages` 懒建、`visible=false`、`host.add_child` 顺序不变 |
| T5-7 | 样式注入收敛：按钮/滑杆/卡片/标题条/分隔线统一 `_dress_*`；删除仅用于建页面的工厂 | `game/screens.gd` | 无重复构造；`_chips` 填充逻辑不变 |
| T5-8 | 保留刷新与业务函数 | `game/screens.gd` | `_refresh_title/_refresh_slots/_on_slot_pressed/_do_save/_on_slot_delete/_load_settings_into_ui/_apply_settings/_refresh_chips` 等不变 |

闸门：`probe_ui_flow`、`probe_save`、`probe_touch`（56 按钮）、`probe_smoke`、`probe_shots`、`check_shots`、`check_ui_lint` 全 PASS。

## T6 页面底板与氛围层

| 编号 | 动作 | 文件 | DoD |
|---|---|---|---|
| T6-1 | 页面根的全屏锚点、`mouse_filter=STOP` 写入场景 | `game/pages/*.tscn` | 与 `_page_base` 行为一致 |
| T6-2 | 幕色 ColorRect 只入节点，颜色运行时设置 | `game/pages/*.tscn` + `screens.gd` | 无硬编码颜色 |
| T6-3 | `UiStyle.overlay_fx(page)` 仍在绑定时调用 | `game/screens.gd` | A5 暗角 + A4 噪粒层级在内容之下 |

闸门：随 T5 闸门。

## T7 肉鸽 HUD 场景化

| 编号 | 动作 | 文件 | DoD |
|---|---|---|---|
| T7-1 | 新建场景，根 CanvasLayer 挂 `run_ui.gd` | `game/run_ui.tscn` | `RunRoot/BottomHolder/hand_row/bar/bar_body/toast` 齐全 |
| T7-2 | `init()` 改绑定；`refresh()` 动态生成保留 | `game/run_ui.gd` | 阶段条与手牌行为不变 |
| T7-3 | 改 main 实例化入口 | `game/main.gd` `_setup_run_ui()` | layer 11 |

闸门：`probe_rogue_ui` PASS。

## T8 三选一面板场景化

| 编号 | 动作 | 文件 | DoD |
|---|---|---|---|
| T8-1 | 新建面板场景，根 CanvasLayer 挂 `hex_picker.gd` | `game/hex_picker.tscn` | `HexRoot/dim/vignette/title/card_layer/foot` |
| T8-2 | 新建卡片场景 | `game/hex_card.tscn` | 根 `cardN` + `glow`；内容容器可填 |
| T8-3 | `open()` 改为实例化三张卡；动画与悬停/选中保留 | `game/hex_picker.gd` | 入场/悬停/选中 Tween 参数不变；`_set_dock_visible` 不变 |
| T8-4 | 改 main 实例化入口 | `game/main.gd` `_setup_run_ui()` | layer 12 |

闸门：`probe_rogue_shot`、`probe_hex_shot`、`probe_touch`、`check_ui_lint` PASS。

## T9 全闸回归与收尾

| 编号 | 动作 | DoD |
|---|---|---|
| T9-1 | 跑 AGENTS.md 全部正式 headless 闸 | 全 PASS，输出留档 |
| T9-2 | 跑全部正式窗口闸 | 全 PASS，输出留档 |
| T9-3 | `check_shots.py` + `check_ui_lint.py` | PASS |
| T9-4 | 对照指纹与截图 md5 | 指纹零变化；UI 截图逐张目视确认 |
| T9-5 | 冷启动/开局耗时对照 | 回退 ≤5% |
| T9-6 | 清理临时文件与日志归位 | `git status` 仅规格内文件 |

## T10 可选：3D wrapper 场景化（待拍板）

仅在用户明确纳入后执行：

- 新增 `unit/gold/rubble/ore/building` 五个 wrapper 场景。
- `models.gd` 的 `spawn_*` 改为实例化 wrapper，AABB 校准、缩放、LOD 仍由脚本完成。
- 闸门：`probe_model`、`probe_orient`、`probe_asset`、`probe_shots`、`check_shots`。

## 不做项

- 不改 `sim/`、`ui_style.gd` 的样式数值、`_layout()` 公式、S 口径。
- 不场景化 `danger_vignette.gd`、`ui_icon.gd`（理由见规格 N6/Q3）。
- 不改 intro 的 3D 演出装配（理由见规格 Q2）。
- 不改探针断言、基线、阈值。
