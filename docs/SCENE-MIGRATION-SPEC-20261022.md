# 界面全量场景化规格（方案 C）

- 日期：2026-10-22
- 状态：待评审（**批准前不改任何代码**）
- 关联：[DEVELOPMENT-PLAN.md](DEVELOPMENT-PLAN.md)、[UI-REDESIGN-20261017.md](UI-REDESIGN-20261017.md)、[AGENTS.md](../AGENTS.md)
- 范围：`game/` 表现层中由代码动态搭建的全部界面结构

## 1. 背景与现状

当前只有 `game/main.tscn`（Main + View）是场景文件，所有界面都由脚本在运行时用
`Control.new()` / `Label.new()` / `Button.new()` 逐个拼出来，编辑器中看不到结构。
用户诉求：**每个按钮打开的界面都应是 `.tscn` 场景**，可在编辑器中查看与编辑。

现状盘点：

| 组件 | 脚本 | 根类型 | 层级 | 构建入口 | 当前实例化方式 | 探针直连 |
|---|---|---|---|---|---|---|
| 界面壳（5 页 + 确认弹窗 + 黑幕） | `screens.gd` 986 行 | CanvasLayer | 20 | `init()` → `_build_*` | `preload(...).new()` | 否（经 main） |
| HUD | `hud.gd` 756 行 | Control | 10 | `build(cb)` | `preload(...).new()` | 否（经 main） |
| 肉鸽 HUD | `run_ui.gd` 193 行 | CanvasLayer | 11 | `init()` | `preload(...).new()` | 否（经 main） |
| 三选一面板 | `hex_picker.gd` 398 行 | CanvasLayer | 12 | `init()` / `open()` | `preload(...).new()` | 否（经 main） |
| 隐私门 | `privacy_gate.gd` 168 行 | CanvasLayer | 40 | `_ready()` → `_build()` | `load(...).new()` | **是**（probe_privacy） |
| 开屏动画 | `intro.gd` 414 行 | CanvasLayer | 30 | `begin()` → `_build_ui/_build_3d` | `load(...).new()` | **是**（probe_intro） |
| 危险暗角 | `danger_vignette.gd` 64 行 | CanvasLayer | 9 | `_ready()` | `preload(...).new()` | 否 |
| 图标原子控件 | `ui_icon.gd` | Control | - | `_draw()` 自绘 | `UiIcon.new()` | 否 |

关键约束（来自现有探针与闸门）：

- 节点名与层级被 `find_child` 逐位依赖（`btn_start`、`btn_slotN`、`sld_*`、`lbl_*_val`、`page_*` 等）。
- HUD 的 `_layout()` 公式布局、`hit_regions()` 矩形被 `probe_hud` 逐像素断言。
- 按钮矩阵被 `probe_touch` 要求恰为 56 个，且每个满足 `custom_minimum_size` 下限。
- 16 个黄金指纹、剧本指纹 `0x7dea2b02`、`STATE_SCHEMA=6` 全部冻结。
- `check_ui_lint.py` 要求样式只经 `ui_style.gd` 工厂。
- headless 根视口 64×64 铁律；`-s` 模式首帧时序铁律。

## 2. 目标

- G1 每个页面/面板/门/开屏拥有独立 `.tscn`，节点树在编辑器完整可见、可编辑。
- G2 场景内节点类型、名称、父子层级、兄弟顺序与现状逐位一致。
- G3 运行时时序、页栈 API（`pages`/`current`/`_ensure`/`_show`）、公开字段全部不变。
- G4 探针只改「实例化入口」，断言与阈值零改动；黄金指纹/剧本指纹/STATE_SCHEMA 零改动。
- G5 样式仍只由 `ui_style.gd` 生成；S 缩放与布局仍只由脚本计算。
- G6 全部正式闸门通过，UI 截图与改造前逐像素一致。

## 3. 非目标

- N1 不改 `sim/` 与任何模拟逻辑；不改唯一写路径 `main.gd → world.apply_command()`。
- N2 不改视觉外观、配色、字体、文案、动效参数（本规格只搬迁结构）。
- N3 不改 `S = clamp(viewport.y/816, 1.0, 1.6) * ui_scale` 口径与 `_layout()` 公式。
- N4 动态内容仍由脚本生成：槽位行文案、结算文案、选项选中态、手牌、阶段条、三选一卡片内容、飘字、提示文案。
- N5 3D 模型校准（`models.gd` 的 AABB/缩放/LOD）与 intro 的 3D 演出子世界不进场景。
- N6 `danger_vignette.gd`（单 ColorRect + 内联 Shader）与 `ui_icon.gd`（自绘原子控件）不场景化。
- N7 不改发布流程、商店素材、版本号。

## 4. 架构决策

### D1 场景承载结构，脚本承载行为

`.tscn` 只允许写入：

- 节点类型、`name`、父子关系与兄弟顺序
- `anchors_preset` / `anchor_*`（仅全屏或容器内语义锚点）
- `size_flags_*`、`mouse_filter`、`visible`、`clip_contents`
- 容器语义：`alignment`、`autowrap_mode`、`scroll_*`、`horizontal_alignment`、`vertical_alignment`
- **静态** `text`（按钮标题、页面标题、固定说明）
- `focus_mode`、`unique_name_in_owner`

`.tscn` 禁止写入（由脚本运行时注入）：

- `custom_minimum_size`、`size`、`position`、`offset_*`（全屏锚点除外）
- `theme`、`theme_type_variation`、`theme_override_*`（含字体、字号、颜色、常量）
- `ColorRect.color`、任何 `StyleBoxFlat` / `Theme` / `Gradient*` / `NoiseTexture2D` / `ShaderMaterial` / `sub_resource` 样式资源

理由：上述数值全部随 `S`（窗口尺寸 × UI 缩放）变化；写进场景会在缩放、平板目视件、
`probe_hud` 矩形断言与 `probe_touch` 尺寸矩阵上漂移。

### D2 场景清单与挂载点

| 场景 | 根 | 挂脚本 | 挂载点 | 说明 |
|---|---|---|---|---|
| `game/screens.tscn` | CanvasLayer | `screens.gd` | `main._setup_shell()` | 子：`ScreenHost` / `Veil` / `ConfirmLayer` |
| `game/pages/title.tscn` | Control | 无 | `ScreenHost` | 根名 `page_title` |
| `game/pages/pause.tscn` | Control | 无 | `ScreenHost` | 根名 `page_pause` |
| `game/pages/gameover.tscn` | Control | 无 | `ScreenHost` | 根名 `page_gameover` |
| `game/pages/slots.tscn` | Control | 无 | `ScreenHost` | 根名 `page_slots` |
| `game/pages/settings.tscn` | Control | 无 | `ScreenHost` | 根名 `page_settings` |
| `game/hud.tscn` | Control | `hud.gd` | `HudLayer` | 顶栏/提示/指挥盘/撤销/横幅/浮字 |
| `game/run_ui.tscn` | CanvasLayer | `run_ui.gd` | Main | 顶部层/手牌行/阶段条/toast |
| `game/hex_picker.tscn` | CanvasLayer | `hex_picker.gd` | Main | 暗幕/暗角/标题/卡层/页脚 |
| `game/hex_card.tscn` | Control | 无 | `card_layer` | 根名 `cardN`，含 `glow` |
| `game/privacy_gate.tscn` | CanvasLayer | `privacy_gate.gd` | Main | 卡片/正文/三个按钮 |
| `game/intro.tscn` | CanvasLayer | `intro.gd` | Main | 仅 UI 层；3D 子世界仍脚本装配 |

页面场景不挂脚本：结构在场景，引用绑定、S 化、信号、刷新逻辑全部留在 `screens.gd`。

### D3 节点名契约

场景节点名必须与现状一致，至少以下被探针或脚本 `find_child` 依赖：

- 壳：`ScreenHost`、`Veil`、`ConfirmLayer`、`btn_confirm_ok`、`btn_confirm_cancel`
- 标题：`page_title`、`title_veil`、`btn_rogue`、`btn_start`、`btn_continue`、`btn_settings`、`btn_tips`、`btn_quit`、`panel_tips`
- 暂停：`page_pause`、`btn_resume`、`btn_save`、`btn_settings_pause`、`btn_restart`、`btn_to_title`
- 结算：`page_gameover`、`go_title`、`go_body`、`btn_again`、`btn_to_title2`
- 存档：`page_slots`、`label_slot_head`、`btn_slot1..3`、`btn_slot_del1..3`、`pad_slot_del1..3`、`label_slot_status`、`btn_slots_back`
- 设置：`page_settings`、`settings_scroll_wrap`、`settings_scroll`、`settings_body`、`row_<key>`、`btn_<key>_<v>`、`sld_<key>`、`lbl_<key>_val`、`btn_privacy_policy`、`btn_settings_back`
- HUD：`top_bar`、`lbl_core`、`lbl_wave`、`hp_bar`、`hp_text`、`divider`、`wave_text`、`supply_caption`、`supply_text`、`heat_btn`、`pause_btn`、`hint_panel`、`hint_label`、`dock`、`undo_panel`、`banner_root`、`banner_card`、`banner_title`、`banner_sub`、`floats`
- 隐私门：`PrivacyRoot`、`bg`、`card`、`title`、`body`、`btn_privacy_link`、`btn_privacy_agree`、`btn_privacy_decline`
- 开屏：`IntroRoot`、`IntroTex`、`IntroBlack`、`IntroWorld`、`IntroUi`、`GoldRule`、`Tagline`

新增节点（如页面内的中间容器）允许命名，但不得插入会改变 `find_child(..., true)` 命中的同名节点。

### D4 探针适配策略

只改实例化入口，不改断言：

| 探针 | 现状 | 改为 |
|---|---|---|
| `probe_privacy.gd` | `load(GATE_PATH).new()` | `load("res://game/privacy_gate.tscn").instantiate()` |
| `probe_intro.gd` | `IntroScript.new()` ×5 | `load("res://game/intro.tscn").instantiate()` ×5 |
| 其余正式探针 | 经 `main.tscn` 间接使用 | **不改** |

`probe_intro` 依赖的字段 `_sub`、`_black`、`_char_labels`、`_tagline`、`_rule` 由
`intro.gd` 在绑定时从场景节点取引用，字段名保持不变。

### D5 新增 L4 守规检查

在 `tools/check_ui_lint.py` 增加 L4：扫描 `game/**/*.tscn`，命中以下任一即 FAIL：

- `StyleBoxFlat`、`type="Theme"`、`GradientTexture2D`、`NoiseTexture2D`、`ShaderMaterial`
- `theme_type_variation`、`theme_override_`
- `custom_minimum_size`

作用：防止样式与 S 尺寸从 `.gd` 迁移到 `.tscn` 后绕过 L1–L3。改动约 15–20 行。

### D6 main 接线保持现状

`main.gd` 的 `_setup_hud/_setup_shell/_setup_run_ui/_show_privacy_gate/_play_intro` 顺序、
`add_child` 顺序、回调字典、layer 号全部不变；只把 `.new()` 换成
`preload("res://....tscn").instantiate()`（场景常量用 `const` preload，保留启动性能）。

### D7 惰建与重建语义不变

- `pages` 懒建：`_ensure(name)` 时 `load(page_scene).instantiate()`，`visible=false` 后挂 `host`。
- `apply_ui_scale` 仍只标记 `_ui_dirty`；`_rebuild_pages()` 仍 `queue_free` 旧页、清空 `pages/_chips`、重算 S、换主题。
- `_show` 的 0.18s 淡入、`close_all`、`handle_key` 全部不变。

### D8 目录与文件格式

- 场景平铺在 `game/`（与 `main.tscn` 一致），页面集中在 `game/pages/`。
- 手写 `format=3`；`ext_resource` 用 `path`（与 `main.tscn` 一致）；不手写 `uid`，交由编辑器补全。
- 新增场景若由编辑器保存生成 `.uid`/`.import`，一并保留，不手工编辑。

## 5. 分阶段计划

### Phase 0 基线取证与守规前置

- 跑现有全闸，记录输出到 `logs/gates-20261022-scene-baseline/`；记录 `shots/*.png` 的 md5 清单。
- 记录当前未提交改动清单（`git status`），确保后续不误改前序修复。
- 增加 L4 检查并通过。

### Phase 1 隐私门 + 开屏（最小闭环）

- 新增 `privacy_gate.tscn`、`intro.tscn`；删除 `_build()`/`_build_ui()` 的结构构造。
- 改 `main.gd` 两处实例化；改 `probe_privacy.gd`、`probe_intro.gd` 入口。
- 闸门：`probe_privacy`、`probe_intro`、`probe_scene`、106 单测、`check_ui_lint`。

### Phase 2 HUD

- 新增 `hud.tscn`；`build(cb)` 改为绑定 + 统一样式注入；`_layout()`/`hit_regions()` 一字不改。
- 闸门：`probe_hud`、`probe_input`、`probe_sync`、`probe_touch`、`probe_smoke`、`probe_shots`、`check_shots`、`check_ui_lint`。

### Phase 3 界面壳（5 页 + 确认 + 黑幕）

- 新增 `screens.tscn` 与 `game/pages/*.tscn` 五页。
- `_build_title/pause/gameover/slots/settings` 改为 `_bind_*`；`_build_confirm/_build_veil` 改为绑定。
- 删除仅用于构造页面的工厂函数（`_menu_row`、`_option_row`、`_slider_row`、`_group_header`、`_title_bar`、`_serif_title` 等），样式注入统一收敛到 `_dress_*`。
- 闸门：`probe_ui_flow`、`probe_save`、`probe_touch`（56 按钮矩阵）、`probe_smoke`、`probe_shots`、`check_shots`、`check_ui_lint`。

### Phase 4 肉鸽 UI

- 新增 `run_ui.tscn`、`hex_picker.tscn`、`hex_card.tscn`。
- 静态容器入场景；`refresh()` 的动态内容生成与 `_make_card` 的动画逻辑保留。
- 闸门：`probe_rogue_ui`、`probe_rogue_shot`、`probe_hex_shot`（若为正式闸）、`probe_shots`、`probe_touch`、`check_ui_lint`。

### Phase 5 全闸回归

- 跑 AGENTS.md 闸门矩阵全部正式闸（headless + 窗口 + 像素 + lint）。
- 对照 Phase 0 的指纹、探针 checks 数与截图 md5。
- 冷启动与开局耗时对照（基线约 3.7s / 2202ms，允许 ≤5% 回退，超过则排查）。

### Phase 6（可选，待拍板）

- `models.gd` 的 wrapper 场景化（`unit/gold/rubble/ore/building`）。
- 仅当用户明确要求时执行；校准仍由脚本按 AABB 完成。

## 6. 验收闸门矩阵

| 阶段 | headless | 窗口 | 像素/lint |
|---|---|---|---|
| 0 | 106 单测 + probe_scene | - | `check_shots`、`check_ui_lint` |
| 1 | 106 单测 + probe_scene + probe_privacy | probe_intro | `check_ui_lint` |
| 2 | 106 单测 + probe_scene | probe_hud、probe_input、probe_sync、probe_touch、probe_smoke、probe_shots | `check_shots`、`check_ui_lint` |
| 3 | 106 单测 + probe_scene | probe_ui_flow、probe_save、probe_touch、probe_smoke、probe_shots | `check_shots`、`check_ui_lint` |
| 4 | 106 单测 + probe_scene | probe_rogue_ui、probe_rogue_shot、probe_hex_shot、probe_touch、probe_shots | `check_ui_lint` |
| 5 | 全部正式 headless 闸 | 全部正式窗口闸 | `check_shots`、`check_ui_lint` |

任何一闸红：先怀疑实现（节点名/层级/尺寸/时序），**禁止**改基线、改断言或放宽阈值来修绿。

## 7. 风险与回滚

| 风险 | 触发点 | 对策 |
|---|---|---|
| S 尺寸漂移 | 场景写入 px/字号 | D1 禁止项 + L4 + `probe_hud`/`probe_touch` 即时拦截 |
| 节点名/层级漂移 | 手写场景改错父子顺序 | D3 契约表 + `find_child` 断言 |
| 时序变化 | `_ready` 早于绑定 | 绑定只在 `init/build/begin` 内做；实例化后先 `add_child` 再初始化（保持现状顺序） |
| 启动变慢 | 场景实例化开销 | `const preload`；Phase 5 实测，>5% 回退即排查 |
| 样式绕过工厂 | 编辑器生成 sub_resource | L4 扫描 + 代码评审 |
| 误改前序修复 | 工作区未提交改动 | Phase 0 记录 `git status`；每阶段只改规格内文件 |
| 探针适配扩大 | 顺手改断言 | D4：只改实例化入口；评审 diff |

回滚：每阶段独立可回滚。未获授权不创建 commit；若授权，每阶段末一个 commit，回滚即
`git revert` 对应提交。新增场景可直接删除，脚本恢复原构造函数（改动按阶段留痕）。

## 8. 开放问题（请拍板）

| 编号 | 问题 | 建议 |
|---|---|---|
| Q1 | `models.gd` 的 3D 单位/建筑/金堆/瓦砾/矿石 wrapper 是否纳入本轮？ | **不纳入**：校准依赖运行时 AABB，属模型装配而非界面；列为 Phase 6 可选 |
| Q2 | `intro` 的 3D 演出子世界（相机/灯光/粒子/径向光团）是否入场景？ | **不入**：程序化视觉装配，且探针依赖 `_sub` 字段；仅 UI 层入场景 |
| Q3 | `danger_vignette`（单 ColorRect + 内联 Shader）是否入场景？ | **不入**：唯一子节点，收益近零；Shader 属样式代码 |
| Q4 | 是否允许新增 L4 `.tscn` 守规检查？ | **允许**：约 15–20 行，防止样式/尺寸绕过工厂 |

## 9. 批准门槛

用户明确回复「批准」后，才进入 Phase 0 执行；未批准前本规格不产生任何代码改动。
