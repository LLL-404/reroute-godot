# 《改道》Godot 版 · 素材许可与署名台账（CREDITS）

> 管什么：包内每一个素材的**来源、许可、署名义务**，以及外部素材的准入规则。
> 不管什么：素材的观感值与命名（`cashline/docs/specs/visuals-spec.md`）、音频触发与音量
> （`specs/audio-spec.md`）、库存与包体（`specs/store-spec.md`）、AI 参与度的对外披露措辞
> （`cashline/docs/AI-ASSETS.md`）。
> 权威来源：`assets/` 目录实测（`find`/`ls`）+ 各素材来源页的许可声明。
> 更新触发：**每加或删一个外部素材当天改本文**；这是法律台账，漏登记等于没许可。
> 口径：数量类陈述一律以 `assets/` 实测为准，不凭记忆。

> 新鲜度：self :: 许可不明一律不准进包
> 新鲜度：code reroute-godot/game/hud.gd :: res://assets/fonts/NotoSansSC-Regular.otf
> 新鲜度：code reroute-godot/game/selfcheck.gd :: 中文字体打进包且关键字形存在

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

### 3.1 模型 `assets/models/` —— 10 个 glb + 配套贴图

| 文件 | 内容 | 来源 | 许可 | 署名义务 |
|---|---|---|---|---|
| `zerg_worker.glb` / `zerg_blade.glb` / `zerg_king.glb` | 虫族三形态（幼生工虫 / 镰爪战虫 / 重甲虫王） | 自有 AI 多视图生成管线 | 项目自有 | 无 |
| `gold_pile_full.glb` / `gold_pile_partial.glb` / `gold_pile_small.glb` / `gold_pile_low.glb` | 砂金堆四档耗损 | 同上 | 项目自有 | 无 |
| `rubble_brown.glb` / `rubble_gray.glb` / `rubble_sand.glb` | 瓦砾堆三变体 | 同上 | 项目自有 | 无 |
| `*_00_D.jpg` / `*_00_N.png`（8 组） | PBR 漫反射 / 法线贴图 | 同上 | 项目自有 | 无 |

### 3.2 音频 `assets/audio/sfx/` —— 19 个 mp3

| 文件 | 内容 | 来源 | 许可 | 署名义务 |
|---|---|---|---|---|
| `bgm_reroute.mp3` | 对局 BGM（循环） | 自有 AI 云端音乐生成 | 项目自有 | 无 |
| `zerg_death` / `zerg_hurt` / `zerg_step` / `zerg_worker_chitter` / `zerg_blade_attack` / `zerg_king_roar` | 虫族 6 条 | 自有 AI 云端音效生成 | 项目自有 | 无 |
| `orc_death` / `orc_hurt` / `orc_step` / `orc_worker_effort` / `orc_warrior_attack` / `orc_chief_roar` | 兽人族 6 条 | 同上 | 项目自有 | 无 |
| `gold_collect` / `mining_gold_hit` / `build_stone_place` / `room_door_open` / `room_fire_loop` / `dungeon_ambience` | 场景与环境 6 条 | 同上 | 项目自有 | 无 |

合计 19 条（1 BGM + 18 音效）。

### 3.3 字体 `assets/fonts/` —— 2 个文件

| 文件 | 来源 | 许可 | 署名义务 | 状态 |
|---|---|---|---|---|
| `NotoSansSC-Regular.otf` | Google / Noto 项目（版权 © 2014–2020 Adobe） | **`OFL-1.1`** —— 字体自身 name 表自证：`This Font Software is licensed under the SIL Open Font License, Version 1.1.` | 见下 | ✅ 已合规 |
| `OFL.txt` | 随字体分发的许可证全文（含 Adobe 版权头） | 同字体 | — | ✅ 随包 |

**OFL-1.1 的履行方式**：OFL **不要求**把署名写进游戏内，但要求**再分发时附带许可证文本**。
已随包放在 `assets/fonts/OFL.txt`（与字体同目录）。未对字体做任何修改，故不触发
OFL 的「保留字体名称（Reserved Font Name）」条款。

> 前身：`simhei.ttf`（中易黑体 SimHei，微软 Windows 系统字体）——**商业字体，授权面向系统内
> 使用，不含随软件嵌入/再分发**。已于 2026-10-14 替换为 Noto Sans SC。详见 §四 R-1。

### 3.4 截图 `shots/` —— 15 张

自产运行截图（`game` / `heat` / `ghost` / `title` / `gameover` / `hud` / `asset_close` /
`asset_game` / `model_blade_close` / `model_render` / `model_render_top` / `models_all` /
`orient_cross` / `smoke_end` / `smoke_mid`）。来源：本机实跑。许可：项目自有。署名义务：无。

> 数量更正：本文初版写 13 张，系照抄 `docs/DEVELOPMENT-PLAN.md` 而未实测。
> `ls shots/*.png | wc -l` = **15**。已同步修正开发方案。教训即本文 §一 的口径——
> 数量类陈述一律以实测为准。

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
  | `tests/probes/probe_golden.gd` | 16 指纹 PASS |
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

### R-3 🟢 低 · 第三方素材面已收敛为「仅字体」

替换后包内第三方素材只剩 **1 项字体（OFL，义务已履行）**。保持这个状态。
倒排只剩 4 天（10-18 提交），引入任何需要读 EULA、需要署名落点、需要风格适配的
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
  - 音频 **19 条**（AI-ASSETS.md 文中写 18 条，需按实测口径修正）
  - 模型 **10 个 glb**
  - AI-ASSETS.md §五 目前写「引擎：UrhoX」，**Godot 版必须改成 Godot 4.7.2 stable (mono)**
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
