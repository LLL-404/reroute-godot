# 《改道》Godot 版 · 素材许可与署名台账（CREDITS）

> 管什么：包内每一个素材的**来源、许可、署名义务**，以及外部素材的准入规则。
> 不管什么：素材的观感值与命名（`cashline/docs/specs/visuals-spec.md`）、音频触发与音量
> （`specs/audio-spec.md`）、库存与包体（`specs/store-spec.md`）、AI 参与度的对外披露措辞
> （`cashline/docs/AI-ASSETS.md`）。
> 权威来源：`assets/` 目录实测（`find`/`ls`）+ 各素材来源页的许可声明。
> 更新触发：**每加或删一个外部素材当天改本文**；这是法律台账，漏登记等于没许可。
> 口径：数量类陈述一律以 `assets/` 实测为准，不凭记忆。

> 新鲜度：self :: 许可不明一律不准进包
> 新鲜度：code reroute-godot/game/ui/ui_style.gd :: res://assets/fonts/NotoSansSC-Regular.otf
> 新鲜度：code reroute-godot/game/app/selfcheck.gd :: 中文字体打进包且关键字形存在

---

## 一、登记规则（外部素材准入）

**每进一个外部素材，必须在下表登记一行，缺字段不准合入。**

| 字段 | 要求 |
|---|---|
| 文件路径 | 仓库内相对路径，精确到文件 |
| 来源 URL | 素材详情页完整 URL，不是站点首页 |
| 作者 | 署名人名或机构名 |
| 许可标识 | 精确到版本：`CC0-1.0` / `CC-BY-4.0` / `CC-BY-SA-4.0` / `OFL-1.1` / `Fab Standard` / `自定义` |
| 署名义务 | `无` 或**逐字可粘贴的署名文本** |
| 是否修改 | CC-BY 类要求标注 "modified"，改过就写改了什么 |
| 登记日期 / 决策人 | 便于回溯 |

### 三条硬规则

1. **许可不明一律不准进包。** 免费 ≠ 可商用，可下载 ≠ 可再分发。看不懂条款就别用。
2. **登记 ≠ 履行。** CC-BY / OFL 的署名文本必须**实际出现在交付物里**（游戏内署名屏、或随包附件）。
   只在本文登了、交付物里没有，等于没署名。登记当天必须确认落点。
3. **不准混风格。** 本作美术基准是自有 AI 管线出的低模 + PBR D/N（见
   `cashline/docs/AI-ASSETS.md` §一）。外部素材**只在风格中性时**才准进。风格不统一的
   代价远大于省下的那点建模时间。

---

## 二、外部素材源裁决表

| 源 | 许可模型 | 可用性 | 本项目结论 |
|---|---|---|---|
| **kenney.nl** | 全站 **CC0-1.0** | ✅ 可商用、免署名、可修改 | 许可无任何负担，**风格是唯一门槛**。风格中性项（UI 图标、粒子/贴图、音效）直接可用；3D 模型需与 §一 规则 3 的既有美术基准对齐后才准进 |
| **polyhaven.com** | 全站 **CC0-1.0** | ✅ 可商用、免署名、可修改 | 许可无任何负担。**HDRI 环境贴图风格中性、收益最直接**（PBR 流程直接接）；模型可用但需过风格关 |
| **ambientcg.com** | 全站 **CC0-1.0** | ✅ 可商用、免署名、可修改 | 许可无任何负担。**PBR 表面贴图（土壤/岩石/砖石）风格中性、收益最直接**——不参与造型，只参与材质。10-17 已引入 2 组（见 §3.7）；直链 `https://ambientcg.com/get?file=<ID>` 无需账号 |
| **sketchfab.com** | **逐模型不同**：CC0 / CC-BY / CC-BY-SA / Store 自定义 | ⚠️ 有条件 | 仅 `CC0` 免义务；`CC-BY` 必须署名；**`CC-BY-SA` 本项目禁用**（传染性：衍生作品须同许可）；Store 模型按各自 EULA，**不逐个读完条款不准进**。风格覆盖面极广，低模/卡通/体素包都有 |
| **fab.com**（Epic） | **逐商品不同**；标准许可**不限引擎**，Godot 可用 | ⚠️ 有条件 | ① 每个商品页必须看 License 标签，**不看不用**；② **免费 Quixel Megascans 属 Epic Content License，限制 Unreal Engine 专用 → Godot 版禁用**；③ 部分商品须经 Epic 启动器领取，且 Quixel 免费额度已大幅缩水（1.8 万 → 约 1500）。风格覆盖极广，**不只有写实**：低模 / 风格化 / 卡通 / 体素包均有大量供应 |
| 自建 AI 管线 | AI 多视图生成（Tripo 系）+ 程序烘焙 | ✅ 无外部义务 | 本作美术**主力**，见 `cashline/docs/AI-ASSETS.md` |

### 结论

> **这四个站都有大量风格化 / 低模 / 卡通 / 体素资源，不是「只有写实」。**
> 真正的约束是**风格一致性**：本作现有 10 个模型出自同一套自有 AI 管线，造型语言、
> 比例、贴图风格是自洽的。混入第三方的模型，除非能接上这套语言，否则还是两种东西——
> 这与来源无关，Kenney 的低模同样会冲突。
>
> 因此判断顺序是：**先看许可（能不能用）→ 再看风格（能不能混）→ 最后看工期（值不值得）**。
> 许可上最省事的是 Kenney 与 Poly Haven（全站 CC0，零署名义务）；风格上最省事的是
> **HDRI 这类不参与造型的素材**。

**分工边界**：涉及账号登录的下载（Fab / Sketchfab 商店）由作者手动完成，落盘后交给 AI 做格式转换、
缩放对齐、材质与场景接线。AI 不持有、不使用作者的任何平台账号凭证。

---

## 三、现有素材台账（`assets/` 实测）

### 3.1 模型 `assets/models/` —— 14 个 glb + 配套贴图

| 文件 | 内容 | 来源 | 许可 | 署名义务 |
|---|---|---|---|---|
| `zerg_worker.glb` / `zerg_blade.glb` / `zerg_king.glb` | 虫族三形态（幼生工虫 / 镰爪战虫 / 重甲虫王） | 自有 AI 多视图生成管线 | 项目自有 | 无 |
| `gold_pile_full.glb` / `gold_pile_partial.glb` / `gold_pile_small.glb` / `gold_pile_low.glb` | 砂金堆四档耗损 | 同上 | 项目自有 | 无 |
| `rubble_brown.glb` / `rubble_gray.glb` / `rubble_sand.glb` | 瓦砾堆三变体 | 同上 | 项目自有 | 无 |
| `gold_ore.glb` | 矿格砂金矿块（10-17 新建，multiview 直出） | 同上 | 项目自有 | 无 |
| `wall_barrier.glb` / `tower_ballista.glb` / `core_jade.glb` | 建筑三件：石砌矮墙 / 石砌金帽塔 / 青玉晶体核心（10-17 新建，文本直出） | 同上 | 项目自有 | 无 |
| `*_00_D.jpg` / `*_00_N.png`（9 组） | PBR 漫反射 / 法线贴图 | 同上 | 项目自有 | 无 |

### 3.2 音频 `assets/audio/sfx/` —— 29 个 mp3

| 文件 | 内容 | 来源 | 许可 | 署名义务 |
|---|---|---|---|---|
| `bgm_reroute.mp3` | 对局 BGM（循环） | 自有 AI 云端音乐生成 | 项目自有 | 无 |
| `zerg_death` / `zerg_hurt` / `zerg_step` / `zerg_worker_chitter` / `zerg_blade_attack` / `zerg_king_roar` | 虫族 6 条 | 自有 AI 云端音效生成 | 项目自有 | 无 |
| `orc_death` / `orc_hurt` / `orc_step` / `orc_worker_effort` / `orc_warrior_attack` / `orc_chief_roar` | 兽人族 6 条 | 同上 | 项目自有 | 无 |
| `gold_collect` / `mining_gold_hit` / `build_stone_place` / `room_door_open` / `room_fire_loop` / `dungeon_ambience` | 场景与环境 6 条 | 同上 | 项目自有 | 无 |
| `wall_place` / `building_remove` / `terrain_fill` / `terrain_lower` / `wave_horn` / `core_hit` / `tower_shot` / `match_win` / `match_lose` | D1-7 补齐 9 条（放墙 / 拆除 / 填高 / 挖低 / 波次号角 / 核心受击 / 塔开火 / 胜负） | 自有 AI 云端音效生成（TapTap Maker 制造积分） | 项目自有 | 无 |
| `bgm_settlement.mp3` | 结算 BGM（循环；D2-6 提前完成） | 自有 AI 云端音乐生成（TapTap Maker 制造积分） | 项目自有 | 无 |
| `intro_stinger.mp3` | 开屏动画音效（水晶击点 stinger，2026-10-17 §11.24） | 自有 AI 云端音效生成（TapTap Maker 制造积分） | 项目自有 | 无 |

合计 30 条（2 BGM + 28 音效）。

### 3.3 字体 `assets/fonts/` —— 4 个文件

| 文件 | 来源 | 许可 | 署名义务 | 状态 |
|---|---|---|---|---|
| `NotoSansSC-Regular.otf` | Google / Noto 项目（版权 © 2014–2020 Adobe） | **`OFL-1.1`** —— 字体自身 name 表自证：`This Font Software is licensed under the SIL Open Font License, Version 1.1.` | 见下 | ✅ 已合规 |
| `NotoSerifSC-Bold-Sub.ttf` | 同上项目（版权 © 2014–2021 Adobe）；源为本机 `NotoSerifSC-VF.ttf`（Google Fonts 系发行） | `OFL-1.1`（同 Noto 族许可文本，无 RFN 声明） | 见下 | ✅ 已合规 |
| `OFL.txt` | 随字体分发的许可证全文（含 Adobe 版权头） | 同字体 | — | ✅ 随包 |

> **`NotoSerifSC-Bold-Sub.ttf` 的加工与用途（2026-10-17，UI 改版轮）**：
> 源为 25 MB 的可变字体，直接进包违反包体纪律。加工 = fontTools（v4.67）两步——
> ① `varLib.instancer` 实例化 `wght=700`（Bold）；② `subset` 按用字清单子集化
> （31 字形：改道/暂停/读档/存档/设置/防线守住了！/防线失守 + 数字标点）→ **13.8 KB**。
> **是 Modified Version**：OFL 条款 3 触发与否取决于源许可有无 RFN 声明——Noto 项目的
> OFL.txt **未声明保留字体名称**，故子集版保留族名合规；修改事实已在
> `THIRD-PARTY-NOTICES.txt` §1 声明。用途仅限标题大字 + 各屏标题条（衬线），
> 正文/按钮/数字仍用 Noto Sans SC。**若后续标题文案改字，须同步重做子集**（命令在
> `docs/UI-REDESIGN-20261017.md` §5 与 git 记录）。

**OFL-1.1 的履行方式**：OFL **不要求**把署名写进游戏内，但要求**再分发时附带许可证文本**。
已随包放在 `assets/fonts/OFL.txt`（与字体同目录）。未对字体做任何修改，故不触发
OFL 的「保留字体名称（Reserved Font Name）」条款。

> 前身：`simhei.ttf`（中易黑体 SimHei，微软 Windows 系统字体）——**商业字体，授权面向系统内
> 使用，不含随软件嵌入/再分发**。已于 2026-10-14 替换为 Noto Sans SC。详见 §四 R-1。

### 3.4 截图 `shots/` —— 18 张

自产运行截图（`game` / `heat` / `ghost` / `title` / `gameover` / `hud` / `asset_close` /
`asset_game` / `model_blade_close` / `models_all` /
`orient_cross` / `smoke_end` / `smoke_mid` / `slots` / `settings` / `game_20x9` /
`game_narrow` / `game_closeup`）。来源：本机实跑。许可：项目自有。署名义务：无。

> 数量更正：本文初版写 13 张，系照抄 `docs/DEVELOPMENT-PLAN.md` 而未实测。
> `ls shots/*.png | wc -l` = **15**。已同步修正开发方案。教训即本文 §一 的口径——
> 数量类陈述一律以实测为准。10-16 更新：UI 补全轮 +2（`slots`/`settings`）、
> D1 轮 +2（`game_20x9`/`game_narrow`）→ 现 **19**。
> 10-17 清旧 -2（`model_render`/`model_render_top` 为 UMD2 转换期渲染，展示职责由
> `models_all` 承担）→ 现 **17**（`ls shots/*.png | wc -l` 实测）。
> 10-18 自然化 T1 +1（`game_closeup` 改造特写：填两级崖壁+裙脚 / 挖一级坑）→ 现 **18**
> （统计不含未跟踪的 `_tmp_*` 调试件）。

### 3.5 图标 `assets/icon/` —— 5 个文件

| 文件 | 内容 | 来源 | 许可 | 署名义务 |
|---|---|---|---|---|
| `icon_master.png` | 主图 1024×1024（icon2_core 定稿） | 自有 AI 图像生成（TapTap Maker 制造积分） | 项目自有 | 无 |
| `icon_192.png` | 512×512 导出（Android 主图标，Godot 缩放至 192） | 同上 | 项目自有 | 无 |
| `adaptive_fg_432.png` / `adaptive_bg_432.png` | Android 自适应前/后景层 | 同上 | 项目自有 | 无 |
| `icon.ico` | Windows exe 图标（多尺寸） | 同上 | 项目自有 | 无 |

接线：`project.godot config/icon` + `export_presets.cfg`（Windows `icon`/`console_wrapper_icon`、
Android `launcher_icons` 主图 + 自适应前后景）。D1-7 产。

### 3.6 详情页素材 `shots/store/` —— 5 张 AI 图 + 5 张实机图（D2-5）

官方硬要求：详情页**头图 1 + 宣传图 4**。AI 五图全部为自有 AI 图像生成（TapTap Maker
制造积分），1920×1080；原图存 `reroute-maker/assets/image/`（Maker 绑定项目），本仓为
**提审用副本**（`shots/*` 已在 `exclude_filter` 排除，不进 pck）。

| 槽位 | 文件 | 内容 | 原图（reroute-maker） |
|---|---|---|---|
| 头图 | `store_header.png` | 核心与防线全景（封面构图） | `store_header_20261016015528.png` |
| 宣传图 1 | `promo_redirect.png` | 放墙改道（机制表达最佳） | `promo_redirect_20261016015528.png` |
| 宣传图 2 | `promo_economy.png` | 击杀赏金（绕行越远越贵） | `promo_economy_20261016015528.png` |
| 宣传图 3 | `promo_ambush.png` | 挖矿开新口（暗门两难） | `promo_ambush_20261016015528.png` |
| 宣传图 4 | `promo_barrage.png` | 弩塔齐射轰击虫群 | `promo_barrage_20261016030427.png` |

实机图 5 张（自 `shots/` 选定、副本同置，上传时最终确认）：
`game.png` / `heat.png` / `ghost.png` / `smoke_mid.png` / `game_20x9.png`——纯对局画面，
对齐 §0.3 E「不用过场/读条/菜单截图」。

### 3.7 地表纹理 `assets/textures/terrain/` —— 4 张（2026-10-17 新增）

唯一外部实体素材（第 2 项自来水之外）。均为 ambientCG **CC0-1.0**，1024×1024，JPG/PNG：

| 文件 | 内容 | 原资产（ambientCG） |
|---|---|---|
| `ground093c_col.jpg` / `ground093c_nrm.jpg` | 沙地：漫反射 + 法线（NormalGL） | Ground093C |
| `rock061_col.jpg` / `rock061_nrm.jpg` | 岩石：漫反射 + 法线（NormalGL） | Rock061 |

- **接入方式**：`game/terrain_ground.gdshader` 三平面双材质（沙 × Ground093C、岩 × Rock061），
  按顶点色 a 权值（`view_terrain._field_color` 程序化编码）在全球空间混合。纹理**不参与造型**，
  只参与材质——§二「风格中性项」结论的实践案例。
- **裁剪决策**：两组的 Roughness 贴图**未启用、未随包**（shader 端用常量 roughness，
  省移动端每次 6 次采样）。法线取 **NormalGL** 变体（Godot 4 要求 OpenGL 法线约定）。
- **打包**：VRAM 压缩（etc2/astc）+ mipmap，pck 增量实测轻微。
- **义务**：CC0 无署名要求；`THIRD-PARTY-NOTICES.txt` 已随包声明（含「已裁剪」说明）。
- **验证**：`logs/gates-20261017-artfinal/` 全 21 闸绿。

---

## 四、风险台账

### R-1 ✅ 已解决（2026-10-14）· `simhei.ttf` 随包分发

- **问题**：SimHei（中易黑体）是**商业字体**，授权面向 Windows 系统内使用，
  **不包含随软件嵌入/再分发的权利**。从系统里拷出来能跑，不等于能发出去。
- **处置**：已替换为 **Noto Sans SC Regular**（`SIL OFL 1.1`，版权 © 2014–2020 Adobe）。
  - 来源：本机 `C:\Windows\Fonts\Noto Sans SC (TrueType).otf` → `assets/fonts/NotoSansSC-Regular.otf`
  - 许可自证：字体自身 name 表写明 `SIL Open Font License, Version 1.1`
  - 许可文本随包：`assets/fonts/OFL.txt` + 根目录 `THIRD-PARTY-NOTICES.txt`，
	两者均已加入 `export_presets.cfg` 的 `include_filter`（Godot 默认不打包 `.txt`）
  - 代码：`game/hud.gd` 主题字体路径、`game/selfcheck.gd` 断言均已更新
  - 旧字体、其 `.import` 与 `.godot/imported/` 陈旧缓存已删除
- **回归验证**（全部通过，无基线变更）：
  | 闸 | 结果 |
  |---|---|
  | `tests/run_tests.gd` | 全绿 `[UNIT-ALL-GREEN]` |
  | `tests/probes/probe_golden.gd` | 12 指纹 PASS |
  | `tests/probes/probe_scene.gd` | PASS `field=2304 ring=4384 solids=338/338 covers=23/23` |
  | `tests/probes/probe_hud.gd` | 56/56 PASS（HUD 排版断言全过） |
  | `tests/probes/probe_ui_flow.gd` | 39/39 PASS |
  | `tests/probes/probe_smoke.gd` | 31/31 PASS，`mismatch=0` |
  | 导出包 `--selfcheck` | **22 项 PASS**（项数未变） |
  | pck 内 `simhei` 残留 | **0 处** |
  | `shots/hud.png` 与改动前逐像素对比 | 排版零位移（字号 / 按钮位置 / 横幅 / 浮动数字全对齐） |
- **顺带强化**：`selfcheck.gd` 原断言只查「字体能加载」——加载成功但缺 CJK 字形会渲染成
  豆腐块却照样报绿。已改为**实测 12 个关键字形存在性**（`Font.has_char`），项数仍为 22。

### R-2 🟡 低 · 光照可优化（可选）

补一张 Poly Haven CC0 HDRI 做环境光，免署名、零法律成本、PBR 流程直接接。
非必须，时间不够就砍。

### R-3 🟢 低 · 第三方素材面已收敛为「字体 + 4 张 CC0 纹理」

替换后包内第三方素材只剩 **2 类**：字体（OFL，义务已履行；10-17 增标题衬线子集
`NotoSerifSC-Bold-Sub.ttf`，同许可同履行方式，见 §3.3）+ 地表纹理 4 张
（CC0，零义务，10-17 引入，不参与造型）。保持这个状态。
倒排只剩 1 天（10-18 提交），引入任何需要读 EULA、需要署名落点、需要风格适配的
外部素材，都是负收益。

### R-4 ✅ 已解决 · `export_filter` 过宽

原 `export_presets.cfg` 为 `export_filter="all_resources"` 且 `exclude_filter=""`，
把 `shots/`（13 张截图）、`tests/`、`probe_*.gd`（现 `tests/probes/`）全打进 pck（原 74 MB）。
已设 `exclude_filter="tests/*,shots/*,tools/*"`，非运行资源不再进包。见提交 2 的结构整理。

---

## 五、与提审附件的关系

- 本文件是**内部法律台账**，**不等于**提审要交的「素材使用声明」。
- 后者结构见 `cashline/docs/AI-ASSETS.md`（五段式：AI 生成 / 程序生成 / AI 辅助编写 /
  纯人工 / 引擎与第三方），那份是**对外交付件**。
- 两处**必须口径一致**，以 `assets/` 实测数字为准（本文件 §三 即实测值）：
  - 音频 **29 条**（10-16 D1-7 后；AI-ASSETS.md 对外件已**同批**补登记：+10 音频 + 图标套件 + 详情页五图，2026-10-16 收盘）
  - 模型 **11 个 glb**（10-17 +`gold_ore.glb`）
  - 地表纹理 **4 张 CC0**（10-17 外部引入，见 §3.7；AI-ASSETS.md §五 引擎与第三方段**同批**补行）
  - 字体 **2 款**（正文字体 + 标题衬线子集 `NotoSerifSC-Bold-Sub.ttf`，10-17 UI 改版轮；AI-ASSETS.md §五 **同批**补行）
  - 详情页素材 **5 张 AI 图 + 5 张实机图**（10-16 D2-5；副本 `shots/store/`，见 §3.6）
  - AI-ASSETS.md §五 已改「引擎：Godot 4.7.2 stable (mono)」（2026-10-16 核实）
- 本文件新增任何外部素材后，AI-ASSETS.md §五 要**同批**补一行。

### 三份文件的分工

| 文件 | 面向谁 | 管什么 |
|---|---|---|
| `CREDITS.md`（本文） | 内部 | 台账与准入规则，含来源 URL、裁决、风险 |
| `THIRD-PARTY-NOTICES.txt` | **对外**（随包 / 提交 zip） | 第三方素材声明，含许可全文落点 |
| `assets/fonts/OFL.txt` | **对外**（随包） | OFL 1.1 许可证逐字全文 |
| `cashline/docs/AI-ASSETS.md` | **对外**（提审附件） | 「素材使用声明」，按官方五段式披露 AI 参与度 |

`THIRD-PARTY-NOTICES.txt` 与 `assets/fonts/OFL.txt` 已加入 `export_presets.cfg` 的
`include_filter`——**Godot 默认不打包 `.txt`**，漏了这一步等于许可证没随包，
OFL 的再分发义务就没履行（本文 §一 规则 2「登记 ≠ 履行」）。

---

## 变更记录

| 日期 | 变更 |
|---|---|
| 2026-10-14 | 建档。登记现有素材三类（10 glb + 19 mp3 + 1 字体 + 13 截图），四源裁决表定稿，R-1（simhei.ttf 随包分发）列为阻塞项 |
| 2026-10-14 | **R-1 已解决**：`simhei.ttf` → `NotoSansSC-Regular.otf`（OFL-1.1）；随包 `OFL.txt` + 新增 `THIRD-PARTY-NOTICES.txt` 并加入 `include_filter`；代码 2 处路径更新、selfcheck 断言强化为字形存在性；全闸回归通过，pck 内 simhei 残留 0 处。§二 修正：Fab/Sketchfab 等站**并非只有写实资源**，风格化/低模/卡通/体素包均大量存在，真实约束是风格一致性而非来源。新增 R-4（export_filter 过宽，待单独裁定） |
| 2026-10-16 | D1-7 制造积分素材入库：+10 mp3（9 音效 + 结算 BGM，台账 19→29）+ 图标套件 `assets/icon/`（icon2_core 定稿，主图/192/自适应前后景/ico）。新增 §3.5；§3.2/§3.4 计数与 §五 口径同步；对外件 `cashline/docs/AI-ASSETS.md` 待同批补行 |
| 2026-10-16 | D2-5 详情页素材归置：`shots/store/` 新增 AI 五图（头图 `store_header` + 宣传 `promo_redirect`/`promo_economy`/`promo_ambush`/`promo_barrage`）+ 实机图 5 张副本；新增 §3.6；§五 口径同步 |
| 2026-10-16 | 对外件收盘：`cashline/docs/AI-ASSETS.md` 按 Godot 交付物全文重写（29 音频 / 10 glb / 图标五件套 / 详情页五图；§五 引擎改 Godot 4.7.2 mono），§五 两条待办勾销 |
| 2026-10-17 | 建筑三件 AI 直出入库（`wall_barrier`/`tower_ballista`/`core_jade`，模型台账 11→14 glb；建筑盒体拼接退役）|
| 2026-10-17 | 美术 pass 外部引入收口：ambientCG 列入 §二裁决表（全站 CC0）；新增 §3.7 地表纹理 4 张（Ground093C/Rock061，Color+NormalGL，Roughness 裁剪不随包）；`THIRD-PARTY-NOTICES.txt` 同步补 CC0 节；模型台账 10→11 glb（`gold_ore.glb` 自有 AI 生成，矿格观感替换）；§五 / R-3 口径同步；全 21 闸绿（`logs/gates-20261017-artfinal/`）；AI-ASSETS.md §五 同批补行 |
| 2026-10-17 | UI 改版轮字体入库：`NotoSerifSC-Bold-Sub.ttf`（Noto Serif SC VF 实例化 wght=700 + 子集 31 字形 → 13.8 KB，**Modified Version**，OFL-1.1 无 RFN 故保留族名合规；`THIRD-PARTY-NOTICES.txt` §1 补栏）；§3.3 台账 2→4 文件、§五/R-3 口径同步；AI-ASSETS.md §五 同批补行 |
