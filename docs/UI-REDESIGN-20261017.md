# UI/UX 改版设计稿 v2.1（2026-10-17 · 文明 6 风定稿）

> 状态：**用户已批准**（文明 6 风 + 左对齐菜单列 + Noto Serif SC 衬线标题）。
> 本文为实施依据；批准流程：重出 4 张 mockup → 用户目视拍板 → 实现。
> 相对 v2 的修订：皮肤由"暖色圆角卡 + 运河青绿"改为**文明 6「帝王金黑」体系**；
> 标题屏按钮列改左对齐；标题字体改 Noto Serif SC Bold（替代毛笔体）。
> 范围：B（换肤+质感）+ C（布局重排，限 §4 锁死表以外的标明区）。

---

## 0. 设计参照：文明 6 UI 核心 trait

- 直角/微切角（半径 0–2）半透明深色面板，透出下层画面
- 1px 金线双边框系统（外金线 + 顶缘亮高光），面板四角 L 形角标
- 金色标题条/金色标题字（衬线），字距加大
- 金底深字主按钮（"下一回合"式）；次按钮 = 透明深底 + 金细边，hover 提亮
- 数字一律金色，正文暖白，细金分隔线
- 功能色（血/危/胜）独立于金色体系

## 1. 逐屏评审（现状，未变）

来自 `shots/` 8 张实机截图（2026-10-16 mapgen 版）：

| 屏 | 问题 |
|---|---|
| title | 全屏均匀灰遮罩把战场压灰；标题无层次；五按钮同宽同灰 |
| game | 顶栏信息裸排无分组；血条单一绿块；右侧 8 钮选中态仅底色差异 |
| heat | 同 game |
| slots | 与暂停/设置共用同一张灰卡；槽位状态仅靠文字 |
| settings | 同一张灰卡；滑杆行裸排 |
| gameover | 胜负仅标题换色；统计行小、无层级 |
| pause | 同灰卡 |
| narrow / 20:9 | 结构正常（D1-5 已过），改版保持该约束 |

全局：flat 圆角卡 + 1px 边框；三态仅提亮；无投影、无装饰——"程序员风"。

## 2. 设计 Token v2.1

### 2.1 `hud.DARK` 色板映射（key 不动，数值换）

| key | v1（现） | v2.1 | 语义 |
|---|---|---|---|
| `bar` | 0F131DD8 | `Color8(18,16,9,224)` | 顶栏半透明黑棕 |
| `card` | 121722F4 | `Color8(20,15,8,232)` | 面板体（保持透战场） |
| `text` | EBEFF7FF | `Color8(242,232,216,255)` | 暖白 |
| `muted` | 94AEB0FF | `Color8(176,164,132,255)` | 次要文字 |
| `hp`（胜/核心） | 52C8A0FF | `Color8(64,200,176,255)` | 功能青绿（保留） |
| `supply` | E2B254FF | `Color8(200,168,108,255)` | 金（与主色统一） |
| `danger` | E26054FF | `Color8(228,92,72,255)` | 危险红（保留） |
| `border` | 3E4658FF | `Color8(150,120,76,255)` | 金暗（边框基线） |
| `active`（选中底） | 5569E8 | `Color8(200,168,108,255)` | 金底（选中/主钮） |
| `active_border` | 8294F0 | `Color8(224,198,140,255)` | 金亮 |
| `btn` | 1E2432E6 | `Color8(24,18,10,220)` | 次钮透明深底 |
| `btn_hover` | 2C3448E6 | `Color8(36,27,16,236)` | hover 提亮 |
| `btn_pressed` | 38425CE6 | `Color8(15,11,6,250)` | pressed 压黑 |

> 探针核对：`probe_hud._check_btn_color`、`probe_ui_flow` 胜负标题色均为动态取 `DARK[key]`，换数值安全；浮字 α 算式绑 `FLOAT_LIFE` 不动。
> 注意：`supply` 与 `active` 同为金 `C8A86C`——供给数字金大字与选中钮视觉统一（文明 6 式数字金即如此）。

### 2.2 新增 token（纯新增常量）

| token | 值 | 用途 |
|---|---|---|
| `gold` | `Color8(200,168,108,255)` | 金线/标题字/数字（=active 别名） |
| `gold_hi` | `Color8(224,198,140,255)` | hover 线/选中边 |
| `gold_lo` | `Color8(96,76,44,255)` | 按钮底缘厚度 |
| `edge_hi` | `Color8(224,198,140,46)` | 面板顶缘高光/标题条底 |
| `shadow` | `Color8(0,0,0,80)` | 面板投影（shadow_size=10*S、offset(0,4)） |
| `track` | `Color8(10,8,5,220)` | 血条底槽 |
| `warn` | `Color8(180,96,44,255)` | 血条 <30% / 波次警戒 / 损坏档 |

### 2.3 组件规格

- **面板**：圆角 2；外 1px `border` 金线；顶缘 1px `edge_hi`（border_width_top 用亮色 = 双边感）；shadow_size 10*S + offset(0, 4*S)；四角 L 形角标（仅标题/pause/结算卡的中央卡做，HUD 分格不做）。
- **标题条**：面板顶部一行（高 ≈ 30*S）`edge_hi` 半透明金底 + 标题字金色（衬线）字距 2，条下 1px 金线 40%。
- **主按钮**：金底 `active` + 深字 `Color8(43,32,16,255)` + 底缘 `gold_lo` 3px（border_width_bottom）；hover 金亮底 + 边转 `gold_hi`；pressed 深金。
- **次按钮**：`btn` 透明深底 + 1px `border` 金边 + 暖白字；hover 底提亮 + 边转 `gold_hi`；pressed 压黑。
- **分隔线**：1px `gold` 40%。
- **字体**：标题大字 + 各屏标题条/面板头 = **Noto Serif SC Bold**（OFL 1.1；入库时核验授权文件 + 登记 CREDITS.md）；按钮/正文/数字 = Noto Sans SC（现有资源不动）。
- **字阶**：标题大字 54/S 字距 10；副标 14；卡片题 20（衬线）；顶栏数值 14 金；按钮 12–14；正文 11；注释 9。

## 3. 逐屏布局（v2.1 定稿）

### title（文明 6 主菜单式）
- 背景：战场全透可见（无全屏轻纱）+ 底部 55% **垂直渐压暗**：TextureRect 锚 y0.45–1.0，GradientTexture2D (0,0)→(0,1) 正向（实测行 0=顶），α 0@顶 → 107@中 → 240@底（Color8 口径，浮点 Color() 会白化）
- 标题块在菜单列顶部（x=屏宽 18%，offset_top=110·S）：`改道`（Serif Bold 54·S，逐字 Label 字距 26，子集无全角空格字形故不走空格法）+ 细金分隔线 + 副标 12
- 菜单**左对齐竖列**（宽 240·S）：开始对局（主钮金底 240×48）→ **读档存档**（原「继续对局」改名，避免与新局语义混淆；btn_continue 控件名不变，探针/API 不受影响）→ 设置 → 玩法说明 → 退出游戏；直角钮、文字左对齐、主钮底缘 3px 金边，hover 换金底亮字
- tips：页面层绝对定位（x=240 右侧 +24，y=110），`reset_size` 打开，鼠标透传
- 页脚：**左下**角小字（GameJam 2026 · 聚光灯主题「涌现」）

### game（HUD）
- 顶栏保持 `TOP_H=56` 直角黑棕半透明 + 底缘 1px 金线；三分组留隙：
  - 左格：`核心` 金字 + 血条（`track` 黑槽 + 1px 金边 + hp 青绿填充 + 25/50/75 三细刻度）+ `1200/1200` 金数字
  - 中格：`波次` 金字 + 状态暖白
  - 右格：供给金字大号（14→16）+ `热层`/`暂停` 直角次钮
- 提示横幅：直角黑棕 + 金左边条
- 模式列（COL_W 不变）：直角钮；选中 = **金底深字**（`set_mode` 机制不变）+ `gold_hi` 1px 边；未选 = `btn` 底 + 金边 + `muted` 字；skill 钮同列
- 浮字：金白色带阴影（α 算式逻辑不动）

### gameover
- 中央面板：标题条（胜=金底金字 / 败=暗红底条）+ 黑棕体 + 金边 + 角标；统计两行网格（名 `muted` / 值暖白 14），标题下金分隔线；主钮金底`再来一局` + 次钮`回标题`
- 胜负色语义保持：标题色 = `DARK[hp]` / `DARK[danger]`（探针绑死）

### pause / slots / settings / 确认弹窗
- 统一"标题条 + 黑棕体 + 金边"面板；存档槽位钮文字分层（有效=暖白、空=`muted`、损坏=`warn`）、删除钮 62×36 直角金边；设置滑杆：金轨道 + 圆金钮 + 右值金字稳定网格；全屏 CheckButton 保持格线对齐

## 4. 锁死表（动 = 连带改探针 + 负对照 + 用户裁决）

| 锁死物 | 锁死者 |
|---|---|
| `BTN_H=42 / COL_W=128 / CORNER_*`、`hit_regions()` 语义 | `probe_hud` 布局、`probe_touch` 22 钮 ≥36px、main 点击排除 |
| `set_mode` 机制：normal stylebox bg == `DARK[active]/[btn]`（v2.3 起 = `HudButtonActive`/`HudButton` 变体；探针读 effective stylebox） | `probe_hud._check_btn_color` |
| `FLOAT_LIFE=18` / 浮字 α 算式 | `probe_hud` |
| 控件名全集（`btn_slot%d`、`btn_confirm_ok`…） | `probe_ui_flow` / `probe_touch` / `probe_save` / `main` |
| `hud.safe` 四元组与 `_layout()` 重算 S | `probe_hud`（D5-4） |
| 五屏页流转 API（`open_title/open_pause/...`） | `probe_ui_flow` / `main` |

顶栏重排在 `TOP_H/TOP_STRIP_H` 语义内调整；本次方案不触碰锁死区。

## 5. 实施顺序

1. 字体入库：Noto Serif SC Bold（核验 OFL + 登记 CREDITS.md）
2. `screens.gd`：token + 样式工厂（直角面板/标题条/角标/主次钮三态/分隔线）→ 五屏 + 确认弹窗（一提交）
3. `hud.gd`：顶栏分组 + 血条重设计 + 模式列金色化 + 横幅/浮字样式（一提交；`FLOAT_LIFE/BANNER_LIFE` 等逻辑量不动）
4. 全 21 闸 + `check_shots.py`；重出 `shots/` 目视件；窄屏/20:9 复查
5. 决策记录入 `DEVELOPMENT-PLAN.md` 新 §11 节
6. 风险预案：闸跑不平或超 10-18 → 回退 C 保 B（纯换肤，零断言风险）先上传

## 6. 效果图

文明 6 风 mockup（AI 改图，仅供拍板，非最终渲染）：

- `docs/mockups/title_v21.png` / `game_v21.png` / `gameover_v21.png` / `settings_v21.png`
- v2 旧图 `*_v2.png` 保留作对照

## 7. v2.2 质感层 + 样式工厂（2026-10-17 实装）

**判据起点**：skill 数据（Skeuomorphism 阴影差 30–50%、渐变 8–12 档；Gaming 反模式 =
Minimalist + Static assets）⇒ A 档六件套 + C 饰线全量，B 档（颜色过渡/点击音/glow）
割爱守探针契约。参数全部集中在 `game/ui_style.gd`（唯一真源）：

| 项 | 落点 | 参数 |
|---|---|---|
| A1 光边 | `edge_dress()` draw 闭包（顶层 2px + 底缘 3px 金） | tip 色 = DARK.edge_hi（α120）；底 = RULE |
| A2 投影 | 主钮 6px/4px/α110；卡片 int(12S)/int(4S)/DARK.shadow(α150) | SHADOW_BTN 常量 |
| A3 金字影 | `label(glow:=true)`：GLOW_GOLD α140@(0,1) | 衬线全题/banner/go_title/浮字/供给数 |
| A4 噪粒 | `grain_tex()` 256² 无缝 + modulate α0.05 TILE | 种子 20260415（确定性） |
| A5 暗角 | `vignette_tex()` 径向 0→0@0.78→α0.31 | 有意写在 (0.5,0.02) 半径 |
| A6 按压 | pressed content_margin_top+2 | selfcheck 断言锁 |
| C 饰线 | `corner_dress()` 8px L 金 | 六面板（确认/说明/暂停/结算/存档/设置） |

**氛围层挂点**：五覆盖页 + 确认弹窗（`_page_base`/title/confirm）；**game 页禁挂**
（check_shots 像素契约不受任何影响）。

**架构（双发射器；v2.3 起发射器 b 退役 → §8）**：
- 发射器 a：`UiStyle.build_theme(C,S)` → 运行时 Theme + type variations
  （PrimaryButton/MenuButton→v2.3 改名 UiMenuButton/DarkCard/TitleBar/GoldSlider），按 S 缓存、
  hud/shell 共享同一实例；控件接入 = `theme_type_variation` 一行。
- 发射器 b：按钮 override + `sb_normal` meta（HUD 探针面 10 钮专用——probe 只读 meta
  对象 bg_color，与渲染通道解耦；两路由同参数派生永一致）。**已随 v2.3 退役**（见 §8）。
- 赛后遗留：探针面翻转 variation（v2.3 已完成，见 §8）；余 .tscn 场景化（§11.23 治理面）。

**维护三规约（lint 强制）**：L1 裸 Color 只在 DARK 定义区；L2 样式/纹理构造只走工厂；
L3 变体名只用常量、且禁与内置类同名（MenuButton→UiMenuButton，§8）。`python tools/check_ui_lint.py` + selfcheck 33/0（含 8 条工厂一致性 + 2 条 HUD 变体，v2.3 后）。

**调参速查**：噪粒度 GRAIN_ALPHA（糊字降 0.03）·暗角 VIGNETTE_ALPHA ·饰线臂 TICK_ARM ·
金字 GLOW_GOLD ·投影 SHADOW_BTN/Build 卡片 shadow（build_theme 内）·veil 三档常量。

## 8. v2.3 独立化：色板归位 + HUD 变体化（2026-10-20 实装）

具体决策记录 = 方案 §11.30。三条口径（对维护者）：

1. **色板真源**：`DARK` 在 `UiStyle`（唯一真源）。`hud.DARK` 是
   `const DARK := UiStyle.DARK` 兼容别名——旧引用/探针按 key 取色零改；`screens.gd` 壳层
   已改取 `UiStyle.DARK`，**新增取色一律 UiStyle**。`hud.build_stats` 仍在 hud（数据格式化）。
2. **HUD 钮走变体（override 退役）**：`hud_button_states(C, active)` → `HudButton` /
   `HudButtonActive` 两组变体（build_theme 统一发射，hud 与 shell 共享同一 Theme 实例）；
   `set_mode` / `set_heat_vis` = 一行 `theme_type_variation` 切换。探针断言读
   `get_theme_stylebox("normal")`（effective 解析，与渲染通道同源）。
3. **变体名规约**：变体名**禁与 Godot 内置类同名**——4.7.2 起 `set_type_variation` 会
   报 ERROR（样式虽因同名 type 条目仍生效，属隐性雷）；`BTN_MENU_VAR` 已改 `"UiMenuButton"`。

**调参速查补充**：HUD 钮常态/点亮配色 = `hud_button_states()`（改一处、hud 与 shell 同步）；
字色三态沿 v2.1 运行时实况（hover 不走亮金）。

---

## 9. v2.4 指挥坞 + 三屏修缮（2026-10-20 实装）

决策记录 = 方案 §11.33。维护口径：

1. **指挥坞行** = Button（`text=""`）+ `row_name` / `row_cost` 两个子 Label；配色统一由
   `_paint_rows()` / `_update_affordability()` 驱动（选中 `on_gold` / 常态 `muted` /
   供给不足 `danger`）。禁再向单钮挂样式盒 override。
2. **坞几何**：`BTN_H/COL_W/DOCK_PAD/CAP_H/CAP_GAP/GROUP_GAP` → `DOCK_W/DOCK_H` 成组推导；
   行尺寸与子标签位置在 `_layout()` 随 `S` 重算（窗口缩放不再只挪位置）。
3. **提示条**：`HINT_LIFE`（400 tick = 20s）与 `dismiss_hint()` 共用 `_hint_hidden` 单状态；
   `hit_regions()` 仅在提示可见时返回该区（隐藏后点击交还战场）。
4. **滚动渐隐**：一律 `UiStyle.fade_tex`（screens/hud 禁直接构造 `Gradient`/`Color`，
   lint L1/L2 会咬）。
5. **存档删除列**：删除钮与同宽 pad 互斥显隐（62px），读档/存档/空槽栅格恒定；
   save 模式「隐藏删除钮」的探针口径保留。
