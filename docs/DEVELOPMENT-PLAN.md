# 《改道》Godot 版 · 开发方案（AI 交接权威文档）

> 本文是 **reroute-godot** 的唯一开发权威。任何 AI 或人类接手开发，先读本文，再读
> `README.md`（项目速览）与各源文件头部注释。
>
> 文档版本：v2.2（2026-10-14 晚：v2.1 曾放弃全程参与奖赛道，同日经用户重新评估后
> **恢复**；并修正「试玩次数时间窗」的推断错误。见 §0.3 D 与 §11.2b）
> 对应代码状态：`master` 分支，当日整理改动**已提交**（见 §11 变更台账）
> 引擎：Godot 4.7.2 stable **mono**（Windows）
>
> **文档冲突处理顺序**：本文 > 源文件注释 > `README.md`。数值一律以 `sim/sim.gd`
> 与 `sim/scenario.gd` 代码为准，本文的数值表是它们的镜像，二者不一致时以代码为准并
> 立即回改本文。

---

## 交付上下文（v2.0 新增，决定一切优先级）

| 项 | 内容 |
|---|---|
| 赛事 | 2026 TapTap 聚光灯 21 天游戏创作挑战（第三届），主题「涌现」 |
| 开发期 | **2026-10-01 ~ 10-21** |
| 官方建议提交时间 | **10-18 之前**（官方原文：「提交和审核之间有时间差，建议选手在 18 日之前就把作品提交上去，留出充分的时间应对突发情况」） |
| 试玩评审期 | 2026-10-25 ~ 12-03（41 天） |
| 颁奖 | 2027 年 1 月 |
| 倒排基准 | **10-18 提交 / 10-21 硬截止**（官方口径，与用户原定目标一致） |
| 目标平台 | **Android + Windows 双端**（同一游戏页面同时勾选两端） |
| 目标奖项 | **最佳双端游戏奖（¥80,000，共 1 个）** + 全程参与奖（瓜分 ¥200,000）+ 其他 |
| 提交渠道 | TapTap 开发者中心 → 添加游戏 → 上传包体 → 提审 → 活动页投稿 |
| 引擎限制 | **无**（官方：「0️⃣ 参赛门槛、🈚️引擎限制」） |

### 0.1 已核实的赛事规则（2026-10-14 从官方帖查证）

**参赛资格与引擎**
- **无引擎限制、无参赛门槛**。官方置顶帖明写「0️⃣ 参赛门槛、🈚️引擎限制、总奖金超百万」。
  → **Godot 版完全合规**，不必再纠结「非制造作品能否参赛」。
- 需完成**开发者认证**：主体类型选**个人主体**；认证姓名必须与身份证完全一致；
  厂商名称提交前先在站内搜一遍避免重名（定了再改要走工单）；联系地址精确到门牌号。

**双端奖的硬性要求（决定 Android 怎么做）**
- 「最佳双端游戏奖 ¥80,000，共 1 个」——奖励同时适配移动端 & PC 端的优质游戏。
- **上传时需同时勾选 Android 和 Windows 两个平台**。官方教程原文：
  「❗想参与双端奖，手机端和电脑端必须全选（手机端勾 Android APK 下载，电脑端勾
  TapTap Windows 版），**只勾一端就评不了双端奖**」。
- 「双端奖要求**同一个游戏能在双端运行，请不要在两个端口中上传不同的游戏**」。
- ❗手机端**别勾「小游戏」**；❗电脑端**别勾「Steam 平台」**。
- 上架方式统一选「**常规发布**」，**选完之后改不了**。

**全程参与奖的三个硬条件（¥200,000 奖池，最容易漏）**
1. 投稿截止日期前上传 demo，且 demo 能展示**核心玩法循环**（含目标 / 规则 / 挑战 / 反馈四要素）
2. **开发周期内公开发表 ≥5 次开发者日志**：不可一天内连续发布（需按开发进度写）；
   每篇至少 1 张开发过程截图或短视频；必须带 `#聚光灯gamejam开发者日志` 标签；
   空洞重复 / 拆分灌水 / 与作品无关的内容不计数
3. **试玩评审期结束前，被试玩人数（去重去水下载量）≥ 50**

**投稿必须提交的材料**
- 讲解视频（宣传片）、游戏实机录屏、游戏截图素材
- **AI 资产比例声明**（官方原文：「在投稿时提交 AI 资产比例声明，遵循自己对 AI 资产的
  定义提交即可」；另有一条规则：AI 生成的美术资产占比 >50% 不能参与最佳美术评选）

**其他已确认**
- **赛期禁止加广告**。官方在评论区回复：「活动期间不能给游戏加广告哦，试玩评审结束后可以」。
- **H5 是第三类可提交平台**（安卓 / PC / H5），本作不做（见 §1.2 非目标）。
- 开发者日志可先发在自己的动态或聚光灯论坛，等游戏页面创建后再挪回去。

**上传操作要点（PC + Android）**
- PC 包：上传 **.zip 或 .7z**，**必须填「可执行文件」**（填错会被退回）；等状态变「解析通过」。
- Android 包：上传 **APK**，版本号必须 > 0 且不低于线上版本。
- **版本设置**：填一个比线上版本大的版本号（示例 1.0.0）→ **平台支持多版本，即包体可更新**。
- 上传后先点「**自测**」确认能正常启动，再提交审核。
- 防沉迷能力：**安卓与 PC 一律选「此次上传的包体未接入防沉迷能力」**（审核通过后平台自动套用通用系统）。
- 勾选了 Android → **必须完成 TapPlay 测试**，且隐私说明选「使用 TapTap 通用声明」/「免安装，使用平台托管」。
- 游戏发布状态设为「**开放试玩 / 开放式发布**」。
- 提审前有 8 项检查清单，全部打勾才能提交。
- 提交后走站内信通知审核结果；**提交完成 ≠ 审核完成**。

> ⚠️ **唯一仍未证实的点**：**投稿截止日期之后是否还允许更新包体**。官方帖未明写。
> 间接证据：① 版本号机制（「填一个比线上版本大的版本号」）说明平台支持覆盖更新；
> ② 2024 届完赛清单写「审核修改后上传包体时间放宽到 10 月 30 日 0 点」说明审核不通过可重传。
>
> **结论与纪律**：**不要赌「截止后还能补传」。** 把双端包在 **10-18 之前一次性传好**，
> 这是官方建议的时间点。§0.2 第 4 条的「PC 保底 + Android 追加」降级为**应急方案**，
> 不是默认路径。

### 0.2 时间预算与取舍纪律

4 天到官方建议提交点（10-18），7 天到硬截止（10-21）。必须完成六类工作：Android 出包、
触屏、可玩性验证与数值定稿、**开发者日志 ×5**、结构整理、双端包与上传。**不可能全做完。**

> **2026-10-14 晚 裁定记录（含一次反复，如实留存）**
> 曾一度裁定**放弃**「全程参与奖」赛道，理由是该奖第 ③ 条「试玩次数 ≥50」作为个人作品
> 不可达 → 三条件并列、缺一即出局 → 日志随之失去意义。
> 随后用户重新评估：**试玩次数是累计值，统计窗口约 45 天（游戏上线 ~ 12-03），主要靠平台
> 自然流量**，判断可达 → **裁定恢复该赛道**，日志任务随之恢复。
> 详见 §0.3 D 与 §11.2b。**本次恢复为最终决定，不要再反复。**

已裁定的排序原则（用户 2026-10-14 确认）：

1. **「结构整理」后置到数值定稿之后**。理由：它是唯一不改变交付物任何外部可观测属性的
   工作——不改变好不好玩、不影响能否交上，却会动到与基线相关的代码。
2. **Android 导出提到最前**。理由：唯一可能因环境问题（SDK/JDK/keystore）吃掉好几天的
   未知项，必须最早暴露。
3. **基线重录只做一次，与数值定稿绑定**。现在重录、定稿后再重录 = 探针断言重跑两遍。
4. **双端一次性传好（10-18 前）**。「PC 保底 + Android 追加」仅在 Android 卡死时启用，
   且需注意双端奖要求两端都在同一页面、同一游戏。
5. **开发者日志从 D0 起每天 1 篇，不许攒**。规则明确禁止一天内连发，7 天内必须攒够 5 篇。
6. **探针允许改断言**，但每条改动必须在提交信息里写明「原断言为何是错的」。

### 0.3 赛事交付材料与合规清单（照单打勾，缺一项就少一笔钱）

**A. 后台与账号（D0 完成，越早越好）**

- [ ] 开发者认证通过（个人主体、实名与身份证一致、厂商名不重名、地址到门牌号）
- [ ] 报名已确认（队长报名 + 队员加入）
- [ ] 站内信审核结果已关注

**B. 包体（D4 提交日）**

- [ ] Android APK：版本号 > 0 且不低于线上版本
- [ ] Windows 包：**.zip 或 .7z** + **填写可执行文件**（填错会被退回）
- [ ] 双端**同时勾选**：手机端 Android APK 下载 + 电脑端 TapTap Windows 版
- [ ] ❗手机端未勾「小游戏」；❗电脑端未勾「Steam 平台」
- [ ] 上架方式 = 「常规发布」（**选完不能改**）
- [ ] 防沉迷：安卓与 PC 均选「未接入」
- [ ] **Android：安卓包体处勾选「使用 TapPlay」**
- [ ] **Android：隐私协议处勾选「通用隐私协议」** ← 不勾会**卡审核**（官方群公告）
- [ ] Android：TapPlay 测试已完成
- [ ] 两端发布状态 = 「开放试玩 / 开放式发布」
- [ ] 包体列表先点「**自测**」确认能启动，再提审
- [ ] 提审前 8 项检查清单全部打勾
- [ ] **提审时弹出的「投稿弹窗」务必填写**——内容没备齐就**先写占位文字**，
      官方明确「后续是可以改的」，但**这一步必须投稿**

**C. 投稿材料（D4 至少占位，D7 补齐）**

- [ ] 讲解视频（宣传片）
- [ ] 游戏实机视频（录屏）
- [ ] **五图素材**（截图）
- [ ] **素材使用声明（含 AI 生成资产说明）** —— 官方模板：
      `https://xd.feishu.cn/docx/R53mdcCfMouOjPxB5PrcHJ4znOc`
      覆盖素材类型：视觉（角色/场景/UI/图标）、音频（音乐/音效/配音）、字体、
      引擎或插件内置资源、其他
- [ ] 注意规则：**AI 生成的美术资产占比 >50% 不能参评最佳美术**
- [ ] 活动页投稿（TapTap 开发者服务 → 活动中心 → 聚光灯 → 投稿 → 选游戏 → 填信息）

**D. 全程参与奖（瓜分 ¥200,000 奖池）**

**前置条件**——官方原文：「全程参与奖**除需要满足按时上传符合规范的讲解视频、实机视频、
五图素材外**，还需满足：」。这三样与 §0.3 C 组投稿材料重叠，**本来就要做**：

- [ ] 讲解视频（宣传片）、实机视频、五图素材，均**按时上传且符合规范**

**三个并列条件**（缺一即整条出局）：

- [ ] ① 按时上传 demo，且 demo 能展示核心玩法循环（目标 / 规则 / 挑战 / 反馈四要素齐备）
- [ ] ② **开发者日志 ≥5 篇**，且：
      · **每篇间隔不得低于 1 天**（不能最后一天连写几篇；官方原话「日志必须跟着进度更新」）
      · **每篇必须含三段：本期进展 / 问题与风险 / 下期计划**
      · 每篇 ≥1 张开发过程截图或短视频
      · 带 `#聚光灯gamejam开发者日志` 标签
      · 空洞重复、拆分灌水或与作品无关的内容不计数
- [ ] ③ **游戏被试玩次数不少于 50 次**

> ⚠️ **第 ③ 条的时间窗——官方原文没有写。** 2026 版《社区运营指南》原文只有
> 「游戏被试玩次数不少于 50 次」一句，**未说明统计起止**。
> **合理读法（推断，非原文）**：试玩次数是**累计值**，游戏上线（约 10-18 ~ 10-21）后
> 一直累积到试玩评审期结束（12-03），窗口约 45 天，主要靠平台自然流量。
> 本方案此前写的「试玩评审期结束前 ≥50」**属推断**，现已按此标注。
> → **对执行的影响：第 ③ 条不需要你现在做任何事。**
>
> ⚠️ **第 ② 条才是硬约束**：日志必须「跟着进度更新」，而创作期 **10-21 结束**。
> 从 10-14 起算只剩 **8 天**窗口要凑 5 篇，且每篇间隔 ≥1 天 → **今天不发第 1 篇就少一天**。
> 另：日志与第 ③ 条**正相关**（日志拉曝光 → 拉试玩），放弃日志会同时削弱第 ③ 条。

**E. 合规红线**

- [ ] **赛期不加广告**（官方确认；试玩评审结束后才可接）
- [ ] 开发者日志不一天连发、不灌水
- [ ] 素材不用过场动画 / 读条 / 菜单截图

**F. 加分项（不硬性，但值钱）**

- [ ] 最佳社区运营奖（¥10,000 × 5）：持续在自己游戏论坛与玩家互动
- [ ] 配置**制作人员认证号**（队员也能认证，展示在游戏详情页，便于社区运营）
- [ ] 论坛版主权限 / 抽奖工具（运营手段）
- [ ] 内容同步**小红书**，优质内容有官方额外流量扶持

> **开发者日志是本次最容易漏的硬任务**：规则要求「每篇间隔不得低于 1 天」，等于
> **每天最多 1 篇**，而开发期到 10-21 结束。从 10-14 起算只有 8 天窗口，必须
> **从 D0 起每天写一篇**。写法规范见 §0.4。
> `cashline/docs/devlogs/` 有 3 篇旧草稿（参赛宣言 / 性能实测 / 流场移植），是 Maker 版
> 口径，需按 Godot 版重写并补齐三段结构；还需新写 2 篇以上。

### 0.4 开发者日志写法规范（硬格式，不合规不计数）

官方对「全程参与奖」的日志有明确格式要求，**不是随便发帖就行**：

| 要求 | 具体 |
|---|---|
| 篇数 | ≥5 篇 |
| 间隔 | **每篇间隔 ≥1 天**（严禁最后一天连发） |
| 每篇结构 | **① 本期进展 ② 问题与风险 ③ 下期计划** |
| 每篇配图 | ≥1 张**开发过程**截图或短视频 |
| 标签 | `#聚光灯gamejam开发者日志` |
| 内容 | 与作品相关、非空洞重复、非拆分灌水 |
| 发布位置 | 可先发在**聚光灯论坛**（`https://www.taptap.cn/app/710826/topic`），
游戏页面建好后**编辑挪到自己游戏论坛** |

**建议排期（每篇一个主题，正好覆盖 D0–D4）**

| 篇 | 主题建议 | 素材 |
|---|---|---|
| ① | 参赛宣言 + 玩法一句话（为什么做「放墙改道」） | 放墙前后流场对比截图 |
| ② | 从 UrhoX+Lua 迁到 Godot：确定性模拟怎么搬的 | 黄金回放指纹对拍终端截图 |
| ③ | Android 移植踩坑（触屏、DPI、TapPlay） | 真机运行截图 |
| ④ | 真人试玩的第一批反馈与数值调整 | 试玩记录 / 数据 |
| ⑤ | 双端上线 + 一次改完基线（确定性验证怎么做） | 双端包截图 |

> 已有草稿 `cashline/docs/devlogs/01-参赛宣言.md`、`02-性能实测.md`、`03-流场移植.md`
> 可复用骨架，但**必须改成 Godot 口径**并补上三段结构与配图。

### 0.5 已有材料盘点与改造要求（2026-10-14 实查）

**① 开发日志草稿 3 篇**（`cashline/docs/devlogs/`，共约 12 KB）

| 文件 | 现状 | 必须改什么 |
|---|---|---|
| `01-参赛宣言.md` | 讲玩法与涌现 | 改 Godot 口径；补官方三段结构 |
| `02-性能实测.md` | 讲 UrhoX 下 500 只单位实测 | **整篇是 Maker 引擎数据，Godot 版需重测重写** |
| `03-流场移植.md` | 讲「把流场搬进 Lua」 | **改成「搬进 GDScript」**；正文有 3 处需修正（见下） |

`03-流场移植.md` 已发现的具体问题：
- 标题与正文通篇是「搬进 Lua」，与 Godot 版不符
- 结尾「游戏在 TapTap 可以试玩了（链接占位）」——**占位未填**
- 结尾「修运河比堵路更赚」——文件自身注释已标注**该表述在当前代码里不成立**
- 结构是「前情 / 坑一 / 坑二 / 坑三 / 挑刺环节 / 现状」，**不是**官方要求的三段结构

→ 结论：**3 篇都只能当素材库，不能直接发。** 每篇需按 §0.4 的三段结构重排。

**② AI 资产说明**（`cashline/docs/AI-ASSETS.md`，45 行）

这份**质量很高、可直接改造**，结构与官方「素材使用声明」高度对应：

| 现有章节 | 对应官方模板 |
|---|---|
| 一、AI 生成资产（类别/内容/工具来源/人工加工 四列表） | 素材类型 × AI 生成说明 |
| 二、程序生成资产 | 其他 |
| 三、AI 辅助编写 | 其他 |
| 四、纯人工部分 | 其他 |
| 五、引擎与第三方 | 引擎或插件内置资源 |

**⚠️ 必须改的硬错误**：§五 写的是「引擎：**UrhoX**（TapTap Maker 官方运行时）」
——**Godot 版必须改成 Godot 4.7.2 stable (mono)**，否则与提交物不符。

其余待核对：音效条数（文中写 18 条，Godot 工程 `assets/audio/sfx/` 实测 19 个 mp3，
含 BGM）；模型数量（文中按 Maker 口径，Godot 侧为 10 个 glb）。**数字必须以 Godot
工程实测为准重新点数。**

**③ 素材现状（Godot 工程实测）**

- 音频：`assets/audio/sfx/` 19 个 mp3（18 音效 + 1 BGM）
- 模型：`assets/models/` 10 个 glb（zerg_worker / zerg_blade / zerg_king / gold_pile×4 /
  rubble×3）+ 配套 D/N 贴图
- 字体：`assets/fonts/simhei.ttf`（**商用授权需自查**，提交前确认）
- 截图：`shots/` 13 张（`game/heat/ghost/title/gameover/hud/asset_*/model_*/orient_cross/
  smoke_*`）→ **五图素材可直接从这批里选**

---

## 0. 一句话定义

48×48 网格塔防，核心机制是**「放墙改道」**：玩家不靠堆输出，而是用墙、塔、地形改造
把敌人推上更长的路；敌人绕行越远，被击杀时赏金越高（`reward + traveled>>3`）。地图自带
一个「暗门陷阱」——挖开西南盆地的插口会拿到矿，但也会打开第三个出怪口。

---

## 1. 目标与非目标

### 1.1 目标

| 编号 | 目标 | 判据 |
|---|---|---|
| G1 | 一局 4–6 分钟，20Hz 固定步长，全程确定性可复现 | 黄金回放 16 指纹逐位一致 |
| G2 | 玩家所有状态变更只经 `World.apply_command` | 非法命令零副作用（指纹不变） |
| G3 | 表现层只读模拟状态，绝不回写 | `probe_sync` 视图/世界逐位对拍 |
| G4 | 导出包可自证（资源齐备 + 核心正确 + 场景可建） | `--headless --selfcheck` exit 0 |
| G5 | 所有量化闸带正/负对照，画面证据肉眼过一遍 | 见 §9 验收矩阵 |
| **G6** | **Android + Windows 双端可出包、可玩** | 双端包各自自测通过 + 真机/模拟器目视；**同一游戏页面同时勾选两端** |
| **G7** | **触屏可完成全部核心操作**（放墙拖线、点地指挥、模式切换、技能） | 新增 `probe_touch.gd`：触摸路径与鼠标路径状态一致 |
| **G8** | **10-18 前完成双端提交**（官方建议点），10-21 硬截止 | 后台显示已提交/审核中；提审前 8 项检查清单全勾 |
| **G9** | **满足全程参与奖条件** | 前置：讲解视频/实机视频/五图素材按时上传；三条并列：① demo 展示核心循环 ② **开发者日志 ≥5 篇**（非同日、每篇带图、带标签）③ **试玩次数 ≥50**（累计，窗口约 45 天） |

### 1.2 非目标（明确不做，防止 AI 自行发挥）

- ❌ 不做联网 / 多人（本工程为纯单机，无网络模块，也不引入）
- ❌ 不做内购、账号、云存档（赛期规则禁止接广告；变现不在本轮范围）
- ❌ 不参评「最佳 TapTap 制造奖」（本作非制造平台作品，无资格）
- ❌ 不引入浮点进模拟层（sim/ 内禁 `float`/`sqrt`/三角函数，`FlowField` 纯整数）
- ❌ 不让视图种子污染仿真种子（`blueprint.gd` 的种子必须与 `sim` 完全隔离）
- ❌ 不擅自修改 `golden_baseline.gd` 的 16 个指纹值（见 §5.4 冻结纪律）
- ❌ 本轮不做 iOS / Web / Linux 导出
- ❌ 本轮不做手柄支持（Android 只做触屏）

---

## 2. 事实基线（2026-10-14 实测）

所有数据均为本次会话在 `D:/G/game/games/reroute-godot` 下实跑所得。

| 项 | 证据 | 命令 |
|---|---|---|
| 单测 83 例全绿 | `[UNIT-DONE] passed=83 failed=0` + `[UNIT-ALL-GREEN]` | `<godot> --headless --path <P> -s res://tests/run_tests.gd` |
| 黄金回放 16 指纹逐位一致 | `[R7-PROBE] PASS` | `<godot> --headless --path <P> -s res://probe_golden.gd` |
| 主场景构建对拍 | `[SCENE] PASS field=2304 ring=4384 solids=338/338 covers=23/23` | `<godot> --headless --path <P> -s res://probe_scene.gd` |
| 视觉同步逐位对拍 1749 断言 | `[SYNC] checks=1749 bad=0 moved=42 match=100` | `<godot> --path <P> -s res://probe_sync.gd`（**窗口模式**） |
| 输入闭环 41 断言 | `[INPUT] checks=41 bad=0` | `<godot> --path <P> -s res://probe_input.gd`（**窗口模式**） |
| 三屏流转 39 断言 | `[FLOW] checks=39 bad=0` | `<godot> --path <P> -s res://probe_ui_flow.gd`（**窗口模式**） |
| HUD 56 断言 | `[HUD] checks=56 bad=0` | `<godot> --path <P> -s res://probe_hud.gd`（**窗口模式**） |
| 全局冒烟一局到底 | `[SMOKE] PASS outcome=LOST tick=4139 kills=116 peak_units=28 towers=6 skills=4` | `<godot> --path <P> -s res://probe_smoke.gd`（**窗口模式**） |
| 三张验收截图可出 | `[SHOT] done shots=3 misses=0` | `<godot> --path <P> -s res://probe_shots.gd`（**窗口模式**） |
| 截图像素校验 | `[SHOTS] checks=15 fail=0` `warm=751573 teal=2835 red=158640 green=3214` | `python tools/check_shots.py` |
| 资产 57 断言 | `[ASSET] checks=57 bad=0` | `<godot> --path <P> -s res://probe_asset.gd`（**窗口模式**） |
| 模型动画齐备 | `blade/worker/king anims: Attack/Crawl/Death/Hurt/Idle` | `<godot> --path <P> -s res://probe_model.gd`（**窗口模式**） |
| 朝向截面图 | `[ORIENT] cross shot saved` | `<godot> --path <P> -s res://probe_orient.gd`（**窗口模式**） |
| 音频 38 断言 | `[AUDIO] checks=38 bad=0` | `<godot> --path <P> -s res://probe_audio.gd`（**窗口模式**） |
| 模拟模块 5 探针 | `[R2/R3/R4/R5/R6-PROBE] PASS` | `probe_sim/grid/flow/scenario/world.gd`（headless） |
| Windows 导出可用 | exit 0，`export/game.exe` 109 MB + `game.pck` 72 MB | `<godot> --headless --path <P> --export-release "Windows Desktop" <P>/export/game.exe` |
| 导出包自证 | `[SELFCHECK] checks=22 bad=0` + `[SELFCHECK] PASS` + exit 0 | `./export/game.exe --headless --selfcheck` |

- `<godot>` = `D:/G/game/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe`
- `<P>` = `D:/G/game/games/reroute-godot`
- 无头 CLI **必须用 `_console.exe` 变体**，普通 `.exe` 不输出 stdout。

### 2.1 ⚠️ 头号环境陷阱（务必先看）

**`--headless` 下 SceneTree 根视口只有 64×64**，凡依赖屏幕坐标或渲染纹理的探针
（`probe_input` / `probe_sync` / `probe_hud` / `probe_ui_flow` / `probe_shots` /
`probe_smoke` / `probe_audio` / `probe_asset` / `probe_model` / `probe_orient`）
在 headless 下必然失败或空转。**这些探针必须窗口模式运行**。

本次会话中实测：
- `probe_input.gd` 在 headless 下 8 项断言失败；窗口模式下 41 项全绿。
- `probe_asset.gd` / `probe_model.gd` / `probe_orient.gd` 在 headless 下
  `get_texture()` 返回 null → `Cannot call method 'save_png' on a null value`，
  进程不退出（空转）；窗口模式下分别 PASS / 出图正常。

代码里部分文件已有注释，但 `README.md` 未写明。**派活时必须显式写明「窗口模式」。**

纯逻辑探针（`probe_sim` / `probe_grid` / `probe_flow` / `probe_scenario` /
`probe_world` / `probe_golden` / `run_tests`）与场景构建（`probe_scene`）可安全 headless。

---

## 3. 核心玩法规格

### 3.1 棋盘与地形

- 网格 `48×48`（`Scenario.w/h`），格子三态：`OPEN=0`（通行）/ `COVER=1`（覆盖层，
  不可通行、**可挖开**）/ `SOLID=2`（实心，不可挖）。
- 高度层 `0..5` 整数（`Sim.H_MIN/H_MAX`）。单位跨边规则：**爬升 ≤1、下降任意**
  （单向崖）；英雄无视高度。视觉换算 `H_STEP = 1.2 m/级`。
- 边界外恒 `SOLID`；`Grid` 另存一份加帧镜像 `pmap`（通行）/`hp`（高度），供流场做
  纯下标邻域运算。

### 3.2 地图要素（`Scenario._init` / `build_grid`）

| 要素 | 坐标 | 说明 |
|---|---|---|
| 核心 | `(24, 6)` | 1200 HP，占地 `SOLID`，不可拆 |
| 英雄出生 | `(24, 8)` | 强制 `OPEN` |
| 出怪口 1 | `(12, 40)` | 西咽喉外，主口 |
| 出怪口 2 | `(36, 40)` | 东咽喉外，主口 |
| 出怪口 3 | `(5, 41)` | 盆地内，**仅在挖开插口后生效** |
| 盆地插口 | `(5, 37)` | 唯一的盆地覆盖格，挖开即 `route_opened = true` |
| 岩脊 | `y=30..32, x=1..46` | 除两个咽喉口外全 `SOLID` |
| 盆地内矿 | `x∈[4,6], y∈[40,43]` | 诱饵：挖插口才够得着 |
| 中场矿 | `x∈[22,26], y=20` | 安全保底 |
| 稀疏表土 | `y∈(12,26) ∧ x%9==4 ∧ y%11==6` | 可挖、不给矿 |

### 3.3 玩家命令（唯一入口 `World.apply_command`）

| kind | 参数 | 前置守卫 | 效果 |
|---|---|---|---|
| `dig` | x,y | 目标格为 `COVER` | 变 `OPEN`；矿格 `+25` 供给；插口格置 `route_opened` |
| `wall` | x,y | 供给 ≥10；可通行；无建筑；无单位；不在英雄脚下 | 扣 10，落地即 `SOLID` |
| `tower` | x,y | 同上，供给 ≥60 | 扣 60，施工 120 tick（首波前减半），竣工后开火 |
| `remove` | x,y | 有建筑且非核心 | 退款：即时 50%、施工中 80% |
| `hero` | x,y | 目标可通行且非原地 | 设英雄移动目标 |
| `shock` | — | 技能冷却为 0 | 半径 3（平方距离 ≤9）内敌人沿背离方向击退 1 格 |
| `fill` | x,y | 可通行、无建筑、无单位、非英雄格、`h<5`、供给 ≥15 | `h+1`，扣 15 |
| `lower` | x,y | 同上、`h>0`、供给 ≥10 | `h-1`，扣 10 |
| `spawn` | x,y[,speed,kind_id] | 目标可通行 | 生成单位（**仅供内部/探针使用**） |

未知 `kind` = 空操作。终局后**所有命令**零副作用。

### 3.4 数值表（镜像 `sim/sim.gd`，改这里必须改代码且重录基线）

```
TICK_HZ = 20          ORE_YIELD = 25        START_SUPPLY = 300
H_MIN=0  H_MAX=5      FILL_COST = 15        LOWER_COST = 10
CONVOY_SHIFT = 3      HERO = {speed_ticks:3, skill_radius:3, skill_cooldown:400}

建筑   wall  : cost 10  hp 120  build_ticks 0    range 0   damage 0   shoots false
       tower : cost 60  hp 200  build_ticks 120  range 12  damage 16  cooldown 20  shoots true
       core  : cost 0   hp 1200 build_ticks 0

敌军   swarm    : hp 30   speed_ticks 4  damage 8   cooldown 12  reward 3
       behemoth : hp 240  speed_ticks 8  damage 60  cooldown 24  reward 14
```

- 波次：25 条表定条目，表定敌军约 200 只；`end_tick = 6400`（5'20"）、
  `hard_cap_tick = 8800`；开门后每 `trickle_every = 300` tick 从盆地渗 2 只虫群。
- 单位出生 `speed_ticks = 表值 + rng.next_int(2)`（唯一消耗 RNG 的地方）。

### 3.5 胜负与冻结

- `judge()`：`tick ≥ end_tick` 且场上无单位 → `WON`；`tick ≥ hard_cap_tick` → `LOST`。
- 核心被啃到 0 → 立即 `LOST`。
- 终局后 `tick()` 与 `apply_command()` 全部早退，状态**纹丝不动**（`verify.gd` 有
  200 tick + 20 条建造命令的冻结自证）。

### 3.6 一 tick 固定次序（**不得重排**）

```
① 摊销补场（流场重建，固定预算 2048）
② 波次导演 run_waves()
③ 单位移动 / 啃建筑 move_units()
③b 英雄步进 hero_tick()
④ 塔开火与施工 towers_and_build()
⑤ 清尸 compact()
⑥ 胜负判定 judge()
```

次序即语义：改次序 = 改指纹 = 改基线。

---

## 4. 模块划分与职责边界

### 4.1 目录结构

```
reroute-godot/
├─ project.godot            主场景 = res://game/main.tscn
├─ export_presets.cfg       Windows Desktop 导出预设
├─ sim/                     ★ 模拟核心（纯逻辑，无渲染、无浮点）
│   ├─ lua64.gd             Lua 语义 shim：mod / idiv / lshr
│   ├─ canon.gd             大端编码缓冲 + FNV-1a/32 指纹；STATE_SCHEMA=5
│   ├─ rng.gd               与 Lua 母版逐位一致的 PRNG（唯一随机源）
│   ├─ grid.gd              三态 + 高度层 + 加帧镜像 + rev / height_rev
│   ├─ flowfield.gd         多目标 Dijkstra（直10/斜14，贴角禁穿，单向崖）
│   ├─ scenario.gd          地图夹具 + 波次表 + 剧本指纹
│   ├─ sim.gd               数值表（建筑/敌军/英雄/常量）
│   ├─ world.gd             世界状态机（唯一变更入口）
│   ├─ verify.gd            验证闸宿主（黄金回放 + 不变式看门狗 + 冻结自证）
│   └─ golden_baseline.gd   16 个黄金指纹（**冻结数据**）
├─ game/                    表现层（只读模拟状态）
│   ├─ main.gd              主循环 / 输入分发 / 对局生命周期
│   ├─ view.gd              3D 渲染 / 拾取 / 相机 / 实体同步 / 音频
│   ├─ models.gd            真实资产（glb）实例管理
│   ├─ blueprint.gd         程序化地形蓝图（**视图种子与仿真隔离**）
│   ├─ hud.gd               顶栏 / 模式列 / 技能 / 横幅 / 赏金浮字
│   ├─ screens.gd           标题 / 暂停 / 结算三屏
│   └─ selfcheck.gd         导出包自证
├─ tests/                   单测（83 例）
│   ├─ kit.gd               记录式断言框架
│   ├─ run_tests.gd         入口
│   ├─ stub_scenario.gd     小图夹具（行为断言用）
│   └─ test_{rng,canon,grid,flowfield,scenario,world}.gd
├─ probe_*.gd               验收探针（见 §9）
├─ assets/{audio,fonts,models,image}
├─ shots/                   验收截图产物
└─ tools/                   Python 工具（check_shots / umd2_to_gltf / verify_glb）
```

### 4.2 分层与依赖方向（**单向，不许反向**）

```
sim/   ←──  game/            （表现层读模拟，模拟层不知道表现层存在）
sim/   ←──  tests/           （单测驱动模拟）
game/  ←──  probe_*.gd       （探针驱动表现层与整机）
```

- `sim/` **禁止** `require`/`preload` 任何 `game/` 下的文件。
- `game/` 只允许调用 `World` / `Grid` / `FlowField` / `Scenario` / `Sim` 的**只读**
  成员；唯一的写路径是 `main.gd` 调 `world.apply_command(...)`。
- `view.gd` 的插值缓存（`unit_nodes` 里的 `px/py`、`death_fx`、`_height_rev` 等）
  是**派生态**，绝不进指纹。

### 4.3 各模块职责与规模（2026-10-14 实测行数）

| 文件 | 行数 | 职责 | 备注 |
|---|---:|---|---|
| `game/view.gd` | 960 | 渲染/拾取/相机/实体/音频 | ⚠️ 逼近拆分阈值，见 §7.9 D6-1 |
| `game/hud.gd` | 581 | HUD 全部控件 | |
| `sim/world.gd` | 576 | 世界状态机 | 核心，改动需最高谨慎 |
| `tests/test_world.gd` | 481 | world 单测 35 例 | |
| `game/main.gd` | 357 | 主循环/输入 | |
| `probe_input.gd` | 350 | 输入验收 | |
| `game/screens.gd` | 298 | 三屏 | |
| 其余 | <300 | | |

---

## 5. 关键实现要点（踩坑换来的，务必遵守）

### 5.1 GDScript / Godot 4.7.2 硬约束

1. **类内禁自引用**：`class_name X` 的脚本内禁止 `X.new(...)` 或 `load("res://自身路径")`，
   分析器会编译期无限递归（实例化挂起、零输出）。自测/自检放**类外**（探针或 `tests/`）。
2. **禁 `:=` 推断无类型数组访问**（`head[i]` / `off[k]` / `dist[p]`）：一律显式类型或
   先判 `size()`。
3. **越界读会伪装成「挂起」**：运行时错误中止 `_initialize` → `quit()` 不执行 → 无头引擎
   空转。调试时 **stderr 必须重定向到文件**再判「挂起」。
4. **保留字/撞名**：`pass` → `pmap`、`set` → `set_cell`；Lua `--` 注释 → `#`；
   大 hex 字面量（≥2^63）钳位报错 → 用带符号十进制。
5. **数组原地 compact 会报类型错误**：`arr[i]=arr[j]` + `resize` 不可用，**建新数组**
   （见 `world.gd compact()`）。
6. **`pad_idx` 用规范公式** `(y+1)*stride+(x+1)`。Lua 母版多 +1（内格右移一列）靠
   nil-on-越界兜底；GDScript 越界直接报错。图与母版同构，距离/指纹一致。

### 5.2 `sim/lua64.gd` 语义 shim

| Lua 运算符 | GDScript 替代 | 原因 |
|---|---|---|
| `%` | `Lua64.mod(a,b)` | Lua 取模向下取整，GDScript `%` 截尾 |
| `//` | `Lua64.idiv(a,b)` | GDScript 无整除运算符 |
| `>>` | `Lua64.lshr(a,n)` | Lua 是逻辑右移，GDScript `>>` 是算术右移 |

`*` / `+` / `<<` / 位运算的回绕行为与 Lua 一致，可直译。

### 5.3 确定性纪律

- 随机数**只有一个来源**：`World.rng`（`Rng` 类）。禁止 `randi()` / `randf()`。
- RNG 只在 `emit_wave()` 里被调用（波次抖动），且**出生点找不到空格时不消耗 RNG**
  （母版同口径）。
- `sim/` 内**禁浮点**。`flowfield.gd` 的松弛全程整数。
- 指纹覆盖：`STATE_SCHEMA | tick | rng.state | 网格三态 | 高度层 | 供给 | 结局 |
  开门 | 击杀 | 失墙 | 单位表(id升序) | 建筑表(id升序) | 英雄 | 绕行赏金`。
  流场是派生态，**不进指纹**。

### 5.4 基线冻结纪律（**最高优先级**）

以下三者是「判据即产品」，改动必须走「记录 + 重录」流程：

| 冻结物 | 位置 | 改动流程 |
|---|---|---|
| 16 个黄金指纹 | `sim/golden_baseline.gd` | 先说明为何必须改 → 重跑 `probe_golden` 采集新值 → 同一次提交里更新 `golden_baseline.gd` 与决策记录 |
| 剧本指纹 `0x12715062` | `Scenario.fingerprint()` | 改地图/波次/高度夹具后必须换基线 |
| `STATE_SCHEMA = 5` | `canon.gd` / `world.canonical_bytes()` | 改编码字段 = 升 schema 号 + 换基线 |

**禁止**为了让某个探针变绿而修改基线值。探针失败优先怀疑实现。

### 5.5 视图同步口径

- `view.sync(world)` 每帧调一次；`main._process` 内固定顺序：
  `tick 推进 → view.sync → update_ghost → hud.update → shell.update`。
- 单位插值：`frac = (tick + uid) % speed_ticks / speed_ticks`，在 `prev` 格与当前格之间
  线性插值（`probe_sync` 逐位对拍此公式）。
- 建筑施工期视觉压扁 `scale.y = 0.35`；竣工 `1.0`。
- 地形柱带的重建触发条件 = `grid.height_rev` 变化（**不是**高度总和，见 §10.1）。
- 热层按 `grid.rev` 变化重建。

### 5.6 音频

- 三件套：4 路轮换 SFX 池（避免同帧互相掐断）+ 常驻环境音 + 对局 BGM。
- `headless` 下 `audio_on = false`，只计数不实际播放（`sfx_log` 供探针断言）。
- **退出前必须** `view.stop_all_audio()` + `await create_timer(0.5)`，否则会报
  Playback 泄漏 + "resources still in use"。

---

## 6. 输入输出与依赖约定

### 6.1 模拟层对外契约（表现层/测试只能依赖这些）

```gdscript
# 构造
World.new(sc: Scenario, seed: int, rebuild_budget: int = 2048)

# 唯一写入口（Dictionary 命令）
world.apply_command({ "kind": "wall", "x": 12, "y": 20 })
world.apply_command({ "kind": "shock" })
world.apply_command({ "kind": "spawn", "x": 12, "y": 40, "speed": 5, "kind_id": Sim.E_SWARM })

# 推进（20Hz）
world.tick()

# 只读状态
world.tick_count : int
world.supply     : int
world.outcome    : int      # World.RUNNING / WON / LOST
world.kills / convoy_earned / buildings_lost : int
world.route_opened : bool
world.units      : Array[Dictionary]   # id/x/y/speed_ticks/stuck_ticks/kind/hp/atk_cd/atk_target/traveled
world.buildings  : Array[Dictionary]   # id/kind/x/y/hp/build_left/cooldown
world.hero       : Dictionary          # x/y/tx/ty/skill_cd
world.core       : Dictionary
world.grid       : Grid
world.field      : FlowField           # 派生态
world.building_at(x, y) -> Dictionary|nil
world.cell_vacant(x, y) -> bool
world.fingerprint() -> int
world.canonical_bytes() -> Canon.Buf
```

**约定**：
- 所有命令字典必须有 `kind` 键（String）。坐标键 `x`/`y` 为 int。
- 非法命令**不抛异常、不返回错误**，静默零副作用。调用方不得依赖返回值。
- `units` / `buildings` 的顺序恒等于 `id` 升序（`compact()` 保证）。
- 白盒直写（`w.supply = ...`）**只允许出现在 `tests/` 与 `probe_*.gd`**，生产代码禁止。

### 6.2 `Grid` 契约

```gdscript
Grid.new(w, h, fill := OPEN)
g.at(x,y) -> int            # 界外恒 SOLID
g.passable(x,y) -> bool     # 界内且 OPEN
g.set_cell(x,y,cell)        # 同值不 bump rev
g.get_h(x,y) -> int
g.set_h(x,y,v)              # 同值不 bump；异值 bump rev 与 height_rev
g.init_h(x,y,v)             # 建图期专用，不 bump 任何 rev
g.idx(x,y) -> int           # 未加帧下标
g.pad_idx(x,y) -> int       # 加帧下标，流场热路径
g.rev : int                 # 拓扑版本（三态 + 高度）
g.height_rev : int          # 仅高度版本（视图地面重建用）
```

### 6.3 表现层接口

```gdscript
# view.gd（节点：Main/View）
view.apply_blueprint(bp, seed)     # 换蓝图（每局一次）
view.build_terrain(grid)           # 铺动态内容（每局一次）
view.sync(world)                   # 每帧
view.pick_cell(sx, sy) -> Vector2i # 屏幕 → 格；屏外返回 (-1,-1)
view.cell_to_world(x, y) -> Vector3
view.ground_y(x, y) -> float       # 蓝图高度 + sim 高度层
view.show_ghost(cells: Array, bad: bool)
view.set_heat(on: bool) / view.heat_enabled() -> bool
view.play_sound(file, vol) / view.bgm(on) / view.stop_all_audio()
view.debug_stats() -> Dictionary   # 探针用：field/ring/solids/covers/units/buildings/hero/heat/...
view.on_float : Callable           # 击杀赏金浮字回调（HUD 注入）

# hud.gd
hud.build(callbacks) / hud.reset() / hud.update(world)
hud.set_visible_hud(vis) / hud.set_mode(m) / hud.set_heat_vis(on)
hud.hit_regions() -> Array[Rect2]  # main 点击排除的唯一来源
hud.float_bounty(sx, sy, text) / hud.build_stats(world) -> String

# screens.gd
shell.init(callbacks, hud) / shell.open_title() / open_pause() / open_gameover(won, world)
shell.close_all() / shell.resume() / shell.current_page() -> String
shell.handle_key(keycode) -> bool  # 返回 true = 已消费
```

### 6.4 对局生命周期（`main.gd` 状态机）

```
启动 → new_game() → open_title()（paused=true，静态战场被标题压住）
  「开始对局」→ start_match()  ：paused=false，HUD 显示，BGM 开，页栈空
  HUD「暂停」/ ESC → pause_game() → open_pause()
      「继续」/ ESC → resume_game() → 页栈空
      「重开本局」→ restart_game() = new_game() + start_match()
      「回标题」→ to_title() = new_game() + open_title()
  终局（WON/LOST）→ _process 检测到 → over_shown=true → open_gameover()
      「再来一局」→ restart_game()
      「回标题」→ to_title()
```

`current_page() == ""` 即「进行中」。ESC 在标题/结算屏**不响应**。

### 6.5 外部依赖

| 依赖 | 版本/路径 | 用途 | 状态 |
|---|---|---|---|
| Godot | 4.7.2 stable **mono** | 引擎 | ✅ 已装 |
| Godot console 变体 | `.../Godot_v4.7.2-stable_mono_win64_console.exe` | 无头 CLI 取 stdout | ✅ 已装 |
| 导出模板（Windows） | `4.7.2.stable.mono` | `--export-release` | ✅ 已装 |
| **导出模板（Android）** | `4.7.2.stable.mono` | Android 出包 | ❓ D0 清点 |
| **Android SDK** | platform-tools + build-tools | Android 出包 | ❓ D0 清点 |
| **JDK** | 17（Godot 4.x 要求） | Android 出包 | ❓ D0 清点 |
| **Android keystore** | debug 签名即可（赛期不走商店审核） | 签名 | ❓ D0 生成 |
| **adb** | 随 platform-tools | 安装与日志 | ❓ D0 清点 |
| Python | 3.13+ | `tools/*.py` | ✅ 已装 |
| Pillow | `pillow` | `tools/check_shots.py` 像素校验 | ✅ 已装于隔离环境 |

- Pillow 隔离环境：`C:/Users/23501/.workbuddy-ai/binaries/python/envs/default/Scripts/python.exe`
- `tools/umd2_to_gltf.py` / `tools/verify_glb.py` 是资产转换链（UrhoX UMD2/UANI → glTF），
  一次性工具，除非新增模型否则不动。
- **分辨率策略**（Android 必需）：`project.godot` 当前为 1280×720 固定视口。
  Android 需改为 `canvas_items` 拉伸模式 + `expand` 宽高比策略，并处理 DPR 与安全区。
  HUD 的 `S` 缩放基准（`win.y / 816.0`，clamp 1.0–1.6）在窄屏/长屏下需重新校准。

---

## 7. 开发流程与阶段划分（v2.0：按 10-18 提交 / 10-21 截止倒排）

### 7.0 阶段总览

历史阶段 S0–S2 全部完成，不再重复实现。**当前进入倒排冲刺 D0–D7**。

| 阶段 | 内容 | 状态 |
|---|---|---|
| S0 | 工程骨架 + 导出预设 + 探针框架 | ✅ 完成 |
| S1 | 模拟核心十模块移植 | ✅ 完成 |
| S2 | 表现层 R1–R9（视图/输入/HUD/三屏/音频/资产/冒烟/导出自证） | ✅ 完成 |
| **D0**（10-14） | 赛事规则确认 + Android 环境清点 + **开发者日志 ①** | 🔜 立即 |
| **D1**（10-15） | Android 导出管线跑通 + 触屏输入 + **日志 ②** | ⏳ |
| **D2**（10-16） | 双端可玩包 + 首次真人试玩 + **日志 ③** | ⏳ |
| **D3**（10-17） | 数值定稿 + 缺陷全修（E/B/C）+ **一次性重录基线** + **日志 ④** | ⏳ |
| **D4**（10-18） | **双端包提交**（官方建议点）+ **日志 ⑤** | ⏳ |
| **D5**（10-19） | 结构整理（`view.gd` 拆分 / 探针规整） | ⏳ |
| **D6**（10-20） | 缺陷 A/D + 全闸重跑 + 终版包 | ⏳ |
| **D7**（10-21） | 终版补传 + 投稿材料（视频/录屏/截图/AI 声明）+ 合规核对 | ⏳ |

**横切任务（每天必做，不许攒）**：**开发者日志每天 1 篇**。规则明确「每篇间隔不得低于
1 天」，开发期到 10-21 结束，从 10-14 起只有 8 天窗口，要凑够 5 篇就必须每天写。
**每篇必须含三段结构：本期进展 / 问题与风险 / 下期计划 + ≥1 张开发过程截图**（见 §0.4）。
这是全程参与奖（¥200,000 奖池）的硬条件，也是最容易被技术型 AI 忽略的一项。

**排序理由**（见 §0.2）：Android 是最大未知，最早暴露；**10-18 是官方建议提交点**，
倒排把提交定在 D4；结构整理不改变可观测属性，压到最后；基线重录与数值定稿绑定，只做一次。

### 7.1 每个任务的通用流程（AI 必须照做）

```
1. 读本文 §5 实现要点与 §8 代码规范
2. 跑一遍基线闸，确认改动前是绿的：
     run_tests / probe_golden / probe_scene / probe_sync / probe_input
   基线不绿 → 先修基线，不要叠加新功能
3. 改代码（一次只做一件事）
4. 重跑受影响的闸（见 §9.3 影响矩阵）
5. 若动了 sim/ → 必须重跑 probe_golden；指纹变了 → 停手，按 §5.4 走流程
6. 更新源文件头部注释与本文相关章节
7. 提交：`<类型>: <一句话>`（feat/fix/refactor/docs/test/build/chore）
```

**冲刺期附加纪律**：
- **每次改动后立刻提交**，不攒批。7 天里没有回滚余量。
- **D4 之后冻结 `sim/`**：任何数值改动都要连带重录基线，不允许。
- 若某日任务未完成，**不加班补，直接按 §7.11 砍单**。

### 7.2 S0–S2 已完成项（不要再重复实现）

模拟核心：`lua64 / canon / rng / grid / flowfield / scenario / sim / world / verify /
golden_baseline` 十模块 + 83 例单测。

表现层：3D 视图与拾取、拖拽放墙（Bresenham，上限 12 格）、幽灵预览、威胁热层、
HUD 全部控件、标题/暂停/结算三屏、三件套音频、真实 glb 资产接入（10 个模型）、
程序化地形蓝图 3 预设轮换、导出包自证（`--selfcheck`）、Windows 导出。

### 7.3 D0（10-14）· 赛事确认 + Android 环境 + 开发者日志 ①

| 任务 | 产出 |
|---|---|
| D0-1 赛事确认 | 已由本方案 §0.1 完成（官方帖查证）。仍需从队长群确认**认证是否已通过**、**报名厂商名是否已定** |
| D0-2 开发者认证 | 个人主体、实名与身份证一致、厂商名不重名、地址到门牌号 |
| D0-3 Android 环境清点 | Godot Android 导出模板（`4.7.2.stable.mono`）、Android SDK（platform-tools + build-tools）、JDK 17、adb 是否就位；缺什么装什么 |
| D0-4 keystore | 生成 debug keystore（本轮用 debug 签名即可） |
| D0-5 **开发者日志 ①** | 按 §0.4 三段结构（本期进展 / 问题与风险 / 下期计划）+ ≥1 张配图 + 标签。素材底稿见 §0.5 ①，**不能直接发，必须重排结构** |
| D0-6 素材使用声明初稿 | 按官方飞书模板重排 `cashline/docs/AI-ASSETS.md`（见 §0.5 ②）。**先修 §五 的引擎错误：UrhoX → Godot 4.7.2**；数字按 Godot 工程重新点数 |

**出口**：Android 环境清单确认完毕；日志 ① 已发（三段结构 + 标签 + 配图）；素材声明已修引擎项。

### 7.4 D1（10-15）· Android 导出管线 + 触屏输入 + 日志 ②

| 任务 | 范围 | 验收 |
|---|---|---|
| D1-1 Android 导出预设 | `export_presets.cfg` 增加 Android 预设（arm64-v8a 必选，x86_64 供模拟器）；**先出空场景包**验证管线，再出全量包 | APK 生成成功，能装能启动 |
| D1-2 触屏输入 | `main._unhandled_input` 增加 `InputEventScreenTouch` / `InputEventScreenDrag` 分支，映射到现有 `pointer_down` / `pointer_up` / `mouse_pos` 更新。**复用现有逻辑，不新写一套** | 新增 `probe_touch.gd`：注入触摸事件 → 世界状态变化与鼠标路径逐项一致 |
| D1-3 HUD 触屏可点 | 确认 HUD 的 Control 按钮在触屏下可点；确认 `_unhandled_input` 不会被 UI 吞掉导致战场点击失效 | 真机/模拟器手动确认全部 7 个模式钮 + 技能 + 暂停 + 热层可点 |
| D1-4 触屏拖线 | 拖拽放墙/塔在触屏下可用（按下 → 拖动 → 抬起） | `probe_touch` 覆盖拖线路径 |
| D1-5 DPI 与安全区 | 按 §6.5 的分辨率策略处理 Android 的 DPR 与刘海/手势区；HUD `S` 缩放需在窄屏下不越界 | 至少在 1 个 16:9 与 1 个 20:9 分辨率下目视截图 |
| D1-6 **日志 ②** | 建议：Android 移植 / 触屏适配的踩坑记录 | 已发（带标签 + 配图） |

**出口**：Android 全量包可启动、可操作、可完成一局。**若 D1 结束仍跑不通 → 触发 §7.11 预案。**

### 7.5 D2（10-16）· 双端可玩包 + 首次真人试玩 + 日志 ③

| 任务 | 范围 | 验收 |
|---|---|---|
| D2-1 双端包 | PC exe + Android APK 各出一份 | 两端各自能启动完成一局 |
| D2-2 包体裁剪 | `export_presets.cfg` 设 `exclude_filter` 排除 `shots/*,tests/*,probe_*.gd,tools/*`（当前全被打进包，见 §7.12） | 包体下降，功能不受影响 |
| D2-3 真人试玩 | **至少 2 人各玩 2 局**，记录：卡在哪、什么时候看不懂、哪一步最无聊、第一局结局 | 书面记录（这决定 D3 的全部内容） |
| D2-4 引导复核 | 确认左下提示徽章与标题屏「玩法说明」是否足够；试玩者是否 5 秒内看懂「放墙改道」 | 试玩记录里的原话 |
| D2-5 **日志 ③** | 建议：真人试玩的第一批反馈 | 已发（带标签 + 配图） |

**出口**：可玩包能发给别人；有 2 人以上的试玩记录。

### 7.6 D3（10-17）· 数值定稿 + 缺陷全修 + 一次性重录基线 + 日志 ④

**这是唯一允许改动基线的一天。** 顺序不能反：

1. **数值定稿**：按 D2 试玩记录调 `sim/sim.gd` 与 `sim/scenario.gd`。
   判据：`probe_smoke` 的 `outcome` 与 `tick` 落在设计区间（LOST 于 3500–5000 tick
   或 WON 于 6400 tick 附近），`peak_units ≤ 60`；试玩者能复述核心规则。
   **定稿后即冻结，之后不允许再改 `sim/` 数值。**
2. **缺陷全修**（§10.2）：按 E → B → C 顺序（最安全到最危险）。
   A、D 若当天来不及，移到 D6。
3. **一次性重录基线**：
   - `sim/golden_baseline.gd` 的 16 指纹 → 用 `probe_golden` 采集新值
   - 剧本指纹（若地图/波次有改动）→ 用 `probe_scenario` 采集
   - `STATE_SCHEMA` 若编码字段有变 → 升号
4. 更新所有依赖旧值的单测与探针断言。
5. 全闸重跑（§9.1 全部）。
6. **日志 ④**：建议：一次改完基线（讲确定性验证怎么做）。

**出口**：全闸绿 + 提交信息写明「为何必须重录、新旧值对照、受影响断言清单」。

### 7.7 D4（10-18）· 双端包提交（官方建议点）+ 日志 ⑤

**这一天以「东西上线」为唯一目标，不做任何代码改动。**

1. 双端出 release 包，各自自测确认能启动完成一局
2. TapTap 后台：添加游戏 → **同时勾选 Android APK 下载 + TapTap Windows 版**
   （❗只勾一端就评不了双端奖；❗手机端别勾小游戏、电脑端别勾 Steam）
3. PC 包传 .zip/.7z 并**填可执行文件**；Android 传 APK，版本号 > 0
4. 防沉迷一律「未接入」；**Android 勾「使用 TapPlay」+ 隐私协议勾「通用隐私协议」**
   （不勾会卡审核）；完成 **TapPlay 测试**
5. 包体列表点「**自测**」确认能启动
6. 提审前 8 项检查清单全勾 → 提交审核
7. **提审时弹出的「投稿弹窗」必须填**：内容没备齐就写占位文字（官方明确后续可改），
   但**这一步不能跳过**
8. 活动页投稿（开发者服务 → 活动中心 → 聚光灯 → 投稿）
9. **日志 ⑤**

**出口**：后台显示双端包已提交/审核中；投稿完成。

### 7.8 D5（10-19）· 结构整理

| 任务 | 范围 | 验收 |
|---|---|---|
| D5-1 `view.gd` 拆分 | 960 行 → `view_core`（坐标/相机/拾取）+ `view_terrain`（蓝图/柱带/环带/热层）+ `view_entities`（单位/建筑/英雄/死亡/幽灵）+ `view_audio`。**纯搬移，零行为变化** | 拆分前后 `probe_sync` 输出逐字节一致（1749 断言、`match=100`） |
| D5-2 探针规整 | 统一输出格式、抽公共夹具（`_chk`/`_cmp` 重复实现在 10+ 个文件里）、补文件头注释。**允许改断言，但每条改动必须在提交信息里写明「原断言为何是错的」**（规范见 §9.5） | 全闸绿；提交信息含逐条断言变更说明 |
| D5-3 拖拽预览逐格绘制 | `view.show_ghost` 目前把首尾格画成**单个矩形**，斜线会覆盖非目标格 | `probe_sync` 增加斜线 ghost 断言；目视截图确认 |
| D5-4 窗口缩放一致性 | HUD 的 `S` 只在 `build()` 算一次，窗口变化时 `_layout()` 只重排不重算比例 | 新增断言：改变视口尺寸后 `S` 与 `hit_regions()` 同步更新 |

**注意**：这一天**不许改 `sim/`**。改动只限表现层与测试层。若 D5 的改动影响到已提交的
包体质量，D7 有补传窗口。

### 7.9 D6（10-20）· 缺陷 A/D + 全闸重跑 + 终版包

- 缺陷 **A**（命令表排序）：若 D3 未做，今天做；必然要重录指纹 → 与 D3 的基线口径一致处理
- 缺陷 **D**（围攻评分）：需先定设计意图；时间不够则留档（见 §7.11）
- 全闸重跑（§9.1 全部）+ 双端各出一次包 + 目视
- 更新 §10 缺陷清单状态

**出口**：全闸绿 + 终版双端包就绪。

### 7.10 D7（10-21）· 终版补传 + 投稿材料 + 合规核对

1. 终版双端包补传（若 D5/D6 有改动）
2. 投稿材料补齐：**讲解视频（宣传片）、实机录屏、截图素材、AI 资产比例声明**
3. 按 §0.3 清单逐项打勾（A–E 全部）
4. 试玩运营准备：确认试玩评审期（10-25 起）的推广动作，目标去重去水下载量 ≥50
5. 提交前**再跑一遍全部闸**（§9.1）

**出口**：双端包在线、投稿完成、材料齐全、§0.3 清单全勾。

### 7.11 失败预案（砍单顺序，从先砍到后砍）

按此顺序放弃，**不要临时自行决定**：

1. **探针规整（D5-2）** —— 不影响交付物，最先砍
2. **`view.gd` 拆分（D5-1）** —— 同上
3. **拖拽预览逐格（D5-3）/ 窗口缩放（D5-4）** —— 观感问题，不影响能否交
4. **缺陷 A / D** —— 留档，但注意 A 影响基线的诚实性，能修尽量修
5. **Android 整体** —— 退为单端 PC 提交（保住交付，**放弃双端奖 ¥80,000**）

**绝不砍**：模拟核心正确性、双端包能跑、真人试玩验证、**开发者日志 5 篇**、提交本身。

> ⚠️ 第 5 条要慎重：双端奖要求「同一个游戏能在双端运行」，且上传时**同时勾选**两端。
> 若退为单端，等于放弃 ¥80,000 的双端奖，但全程参与奖（¥200,000 奖池）仍可拿。
> 只有在 D1 结束时 Android 完全跑不通才走这条路。

### 7.12 性能与包体（横切，贯穿 D0–D7）

- 指标：PC 1280×720 稳定 60fps；Android 中端机可玩（不设硬帧率门槛，但不得卡到无法操作）。
- `probe_smoke` 全程无卡顿（`stalled == 0` 已有断言）。
- **包体**：当前 PC `export/game.exe` 109 MB + `game.pck` 72 MB。`export_presets.cfg` 的
  `export_filter="all_resources"` 且 `exclude_filter=""`，导致 **`shots/` 的 13 张截图、
  `tests/`、`probe_*.gd` 全被打进包**。设 `exclude_filter` 排除
  `shots/*,tests/*,probe_*.gd,tools/*`，预计可省 10 MB+。Android 侧尤其重要。
- 手段（按性价比）：排除非运行资源 → 纹理压缩（`s3tc_bptc` 已开）→ 音频流化 → MultiMesh 合并。

---

## 8. 统一代码规范

### 8.1 文件与命名

| 对象 | 规范 | 示例 |
|---|---|---|
| 文件 | `snake_case.gd` | `flowfield.gd` |
| 类名 | `PascalCase`（`class_name`） | `class_name FlowField` |
| 常量 | `UPPER_SNAKE` | `const H_STEP := 1.2` |
| 变量/函数 | `snake_case` | `func apply_command(cmd)` |
| 私有成员 | 前缀 `_` | `var _height_rev := -1` |
| 探针 | `probe_<领域>.gd`，根目录 | `probe_input.gd` |
| 单测 | `test_<模块>.gd`，`tests/` | `test_world.gd` |

### 8.2 格式

- 缩进 **Tab**（Godot 默认），行宽 ≤ 100。
- 字符串统一双引号。
- 提交前 `git diff --check` 必须无空白错误。
- **换行符 LF**（`git diff` 会提示 CRLF 转换警告，属正常，不要手工改）。

### 8.3 注释

- 每个文件**头部块注释**：说明职责 + 来源（移植自哪个母版文件）+ 关键口径。
- 每个 `func` 上方用 `##` 写一句话职责；复杂函数补「为什么」而非「做什么」。
- 任何**与母版有意差异**的地方，必须写明差异原因（例：`hud.gd` 波次序号口径）。
- 移植代码保留母版出处（`照搬 warden/Warden.Core/World.cs`）。

### 8.4 类型与安全

- 能用 `:=` 推断的用 `:=`；数组元素访问、字典取值一律**显式类型标注**。
- 空值变量必须标注：`---@type Scene` / `var world: World = null`。
- 禁止 `get_node("../../X")` 硬路径跨层访问；用 `@onready` 或注入。
- 对外 API 加参数校验（越界、负值、空字典），失败**早退**而非抛异常。

### 8.5 日志

- 开发期多打 `print`，稳定后清理。保留：启动信息 `[Game] 新对局 run=... seed=...`、
  探针汇总行 `[XXX] PASS/FAIL`。
- 探针输出格式统一：`[标签] checks=N bad=M` + 逐条 `fail: ...` + `[标签] PASS|FAIL`。
- 禁止在 `sim/` 里打日志（污染确定性输出的排查）。

### 8.6 提交规范

`<类型>: <一句话>`，类型 ∈ `feat|fix|refactor|docs|test|build|chore|style`。
动了基线必须在正文说明。

---

## 9. 验收标准

### 9.1 闸清单（每次改动后按范围跑）

| 闸 | 命令 | 通过判据 | 需窗口 |
|---|---|---|---|
| 单测 | `run_tests.gd` | `passed=83 failed=0` + `[UNIT-ALL-GREEN]` | 否 |
| 黄金回放 | `probe_golden.gd` | `[R7-PROBE] PASS`（16 指纹） | 否 |
| 模拟模块 | `probe_sim/grid/flow/scenario/world.gd` | 各自 `PASS` | 否 |
| 场景构建 | `probe_scene.gd` | `[SCENE] PASS field=2304 ring=4384` | 否 |
| 视觉同步 | `probe_sync.gd` | `[SYNC] PASS match=100 bad=0` | **是** |
| 输入闭环 | `probe_input.gd` | `[INPUT] PASS bad=0` | **是** |
| HUD | `probe_hud.gd` | `[HUD] PASS bad=0` | **是** |
| 三屏流转 | `probe_ui_flow.gd` | `[FLOW] PASS bad=0` | **是** |
| 全局冒烟 | `probe_smoke.gd` | `[SMOKE] PASS` | **是** |
| 资产/模型 | `probe_asset.gd` / `probe_model.gd` / `probe_orient.gd` | 各自 PASS（后两者出图） | **是** |
| 音频 | `probe_audio.gd` | `[AUDIO] PASS bad=0` | **是** |
| 截图像素 | `probe_shots.gd` + `python tools/check_shots.py` | `[SHOTS] PASS` | **是** |
| 导出自证 | `export/game.exe --headless --selfcheck` | `[SELFCHECK] PASS` + exit 0 | 否 |
| **触屏闭环** | `probe_touch.gd`（D1 新建） | 触摸路径与鼠标路径世界状态逐项一致 | **是** |
| **Android 可玩** | `adb install` + 启动 + 手动完成一局 | 无崩溃、`adb logcat` 无 ERROR、7 个模式钮 + 技能 + 暂停 + 热层全部可点 | 真机/模拟器 |
| **Android 自证（自动）** | `adb shell am start ... --es -- --selfcheck` 或 logcat 抓 `[SELFCHECK] PASS` | `[SELFCHECK] PASS` + exit 0 | — |

### 9.2 通用验收要求

1. **stdout 必须出现 `PASS` 且进程 exit 0**；两者缺一不算通过。
2. **stderr 不得有 `ERROR`**（WARNING 允许，但新增 WARNING 需说明）。
3. 量化闸必须带**正对照**：对照读零要输出 `INVALID` 而不是 `PASS`。
4. **证据要自证实机**：任何「画面正常」的结论必须有人看过截图，不能只看日志。
   这条来自历史事故：曾出现「日志全绿、像素是假的」。
5. 断言必须**落在可观测状态上**，不能只断言中间变量。
6. **双端分别验收**：PC 通过不等于 Android 通过。Android 必须真机/模拟器实跑。

### 9.3 修改影响矩阵（改哪跑哪）

| 改动位置 | 必跑 |
|---|---|
| `sim/**` | 单测 + 全部 headless 探针 + `probe_golden` |
| `game/main.gd` | `probe_input` + `probe_ui_flow` + `probe_smoke` + `probe_touch` |
| `game/view.gd` | `probe_sync` + `probe_scene` + `probe_shots`/`check_shots` |
| `game/hud.gd` / `screens.gd` | `probe_hud` + `probe_ui_flow` + `probe_touch`（触屏可点） |
| `assets/**` | `probe_asset` + `probe_model` + `selfcheck` |
| `tests/**` | 单测 |
| `export_presets.cfg` | 双端各出一次包 + `--selfcheck` |
| `sim/golden_baseline.gd` | 单测 + `probe_golden` + 所有依赖指纹的断言 |

### 9.4 目视验收（每次交付必须）

打开 `shots/game.png`、`shots/heat.png`、`shots/ghost.png`，确认：
- 地形暖色石质、有高度层次，无空洞/黑块
- 核心青玉发光可见，单位贴地不悬空、不陷地
- 热层红→蓝渐变可辨；幽灵预览绿板落在合法格
- HUD 文字完整不重叠、中文无豆腐块

Android 额外确认：
- 7 个模式钮 + 技能钮 + 暂停钮 + 热层钮**全部可点**，无遮挡
- 单指拖线放墙可用；点地指挥英雄可用
- 不同宽高比（16:9 / 20:9）下 HUD 不越界、不出安全区
- 帧率不卡到无法操作

### 9.5 探针断言修改规范（D6-2 适用）

用户裁定：**允许改断言**。但必须遵守：

1. 每条断言改动在提交信息里写明：**原断言是什么、为何它是错的、新断言是什么**。
2. 禁止「把断言改松让它变绿」。改松 = 降低验收标准，等同于删掉验收。
3. 新增断言必须有**负对照**（能失败的情形）。
4. 断言只允许**收紧或修正语义**，不允许为了通过而移除。
5. 改断言后必须重跑该探针的**全部**用例，不能只跑改动的那条。

> 理由：探针是唯一的验收手段。改探针 = 同时改验收标准与被测对象，是本项目最高风险操作。

---

## 10. 已知缺陷与风险清单

> 以下均基于代码证据，**尚未修复**。修复前先按 §9.3 跑对应闸。

### 10.1 已修复（本次会话）

| # | 问题 | 位置 | 修复 |
|---|---|---|---|
| 1 | 视图地面柱带不含 sim 高度，与 `ground_y` 口径不一致（单位「浮」在柱顶之上） | `view.gd _rebuild_field` | 柱高改为 `field_h + grid.get_h * H_STEP` |
| 2 | 改高检测用「高度总和」，**等量反向改高（+1/−1）漏检**，地貌不刷新 | `view.gd sync` | 新增 `Grid.height_rev`，按版本号触发 |
| 3 | 改高走 `build_terrain()` 全量重建，**清空单位/建筑视觉缓存** | `view.gd sync` | 只调 `_rebuild_field()` |
| 4 | 重开一局只重置 `heat_on` 标志，热层网格与 HUD 按钮不熄灭 | `main.gd new_game` | 补 `view.set_heat(false)` + `hud.set_heat_vis(false)` |
| 5 | 建造预览（幽灵）不检查英雄占格，模拟层却拒建 → 预览显示绿色但点击无效 | `main.gd mode_valid` | 补英雄占格守卫 |
| 6 | `set_mode` 有两条路径，HUD 高亮可能不同步 | `main.gd` | 统一走 `set_mode()` |
| 7 | `run_tests` 退出时报 14 个对象泄漏 + 8 个资源占用 | `tests/kit.gd` | 用例执行完 `tests.clear()` 解循环引用 |

### 10.2 本轮必修（D4 一天内全修，修完一次性重录基线）

用户 2026-10-14 裁定：**全修，允许重录基线。**

| # | 问题 | 位置 | 修法 |
|---|---|---|---|
| A | 黄金命令表**未按 tick 排序**：[1150..1195] 与 [30..461] 的条目排在 5600 之后，执行器只顺序消费 → 这些命令实际延后执行 | `verify.gd SCRIPT_COMMANDS` | ① 先补「命令实际执行 tick」测试；② 按 tick 稳定排序（同 tick 保持原相对序）；③ 重录 16 指纹 |
| B | 流场距离上界 `max_d = 14*(w+h)+16 = 1360`，`push` 超界**静默丢弃**。蛇形长廊理论路径可达 `w*h*14 = 32256` | `flowfield.gd:44,130-132` | ① 加长廊单测暴露问题；② 上界改为可证明的值（或改可增长队列）；③ 若上界只增不减且现有地图未触及，指纹应不变——**必须实测确认** |
| C | 摊销补场期间若再次改图，不会重新 `begin`，完成时却记录**最新** `grid.rev` → 可能把混合拓扑当已同步 | `world.gd:239-247` | 记录启动时的 rev；若中途 rev 变化则重启 `begin`。加「小预算连续改图」单测 |
| D | 围攻目标与核心不连通时建筑评分保持 `INT64_MAX`，严格小于比较使邻接敌人选不到它（现有测试固定了「贴墙不啃」行为） | `world.gd:410-435` / `test_world.gd:233-254` | 先明确设计意图（敌人该不该啃全围死的建筑），再改评分与断言。**时间不够可砍（见 §7.11）** |
| E | HUD 的 `S` 只在 `build()` 算一次，窗口缩放后比例不重算 | `hud.gd:91-92,300-306` | `_layout()` 内重算 `S` 并刷新字体/控件尺寸。纯表现层，**不影响指纹** |

**修复顺序**：E（最安全）→ B（加测试 + 上界）→ C（加测试 + 修竞态）→ A（排序 + 重录）
→ D（需先定意图）。

**重录纪律**：A 必然改变 16 指纹；B/C 可能改变。**一次修完再统一重录，不要边修边重录。**
提交信息必须写明：为何必须重录、新旧值对照、受影响断言清单。

---

## 11. 变更台账（2026-10-14）

### 11.1 代码改动（已提交）

本次会话在 `master` 上的改动，已落两个提交：

| commit | 内容 |
|---|---|
| `528650e` | `fix: 修正地形刷新、实体缓存与建造预览守卫`（含 `shots/*.png` 重出图） |
| `c331ca3` | `docs: 重写 README 并新增开发方案` |
| `e9b8451` | `chore: 同步 Godot MCP 插件的 res:// 路径拼接修复` |
| `12c1ff1` | `docs: 放弃全程参与奖 / 社区运营赛道，方案升 v2.1`（**已被 v2.2 撤销**） |

本次会话在 `master` 工作树上的改动：

```
game/main.gd       | 15 +++---   模式统一 / 热层复位 / 建造预览守卫
game/view.gd       | 23 +++---   height_rev 触发 + 地面柱含 sim 高度 + 不再清实体缓存
probe_input.gd     | 53 +++++++  新增 4 组断言（预览守卫 / 地形刷新 / 重开复位）+ 空值防护
sim/grid.gd        |  3 +++    height_rev
tests/kit.gd       |  2 ++     解循环引用
tests/test_grid.gd |  8 +++++- height_rev 覆盖
README.md          | 重写      旧版称「表现层未开始」，与实际严重不符
docs/DEVELOPMENT-PLAN.md | 新增  本文
```

**非人工改动（Godot 自动重写，保留）**：`project.godot` 在导出时被引擎补上了标准头注释、
`config/features=PackedStringArray("4.7")` 与 mono 的 `[dotnet] project/assembly_name` 段。
这三项是 Godot 4.7.2 mono 的正常产物，**不要手工回退**（下次导出还会写回）。
`shots/*.png` 全部更新是 §10.1 第 1 项（地面柱含 sim 高度）的预期视觉变化。

验证结果（全部实跑）：单测 83/83、`probe_golden` PASS、`probe_scene` PASS、
`probe_sim/grid/flow/scenario/world` 全 PASS、`probe_sync` 1749 断言 PASS、
`probe_input` 41 断言 PASS、`probe_hud` 56 断言 PASS、`probe_ui_flow` 39 断言 PASS、
`probe_audio` 38 断言 PASS、`probe_asset` 57 断言 PASS、`probe_model` 出图正常、
`probe_orient` 出图正常、`probe_smoke` PASS、`check_shots.py` 15 项 PASS、
导出 + `--selfcheck` 22 项 PASS。
**未改动任何基线数据，16 个黄金指纹与剧本指纹保持不变。**

> 注：本次改动**尚未提交**，留在 `master` 工作树上。

### 11.2 方案重排（v1.0 → v2.0）

2026-10-14 与用户逐条对齐后的变更：

| 变更 | 原因 |
|---|---|
| 新增 §0 交付上下文 | v1.0 按「长期打磨」写，未反映 10-21 硬截止与双端要求 |
| 阶段从 S3–S6 改为 **D0–D7 倒排** | 7 个自然日，必须按天分配而不是按阶段 |
| **结构整理从最前挪到最后（D6）** | 唯一不改变交付物可观测属性的工作；放前面会挤掉 Android 与试玩 |
| **Android 提到最前（D1）** | 唯一可能因环境问题吃掉数天的未知项，必须最早暴露 |
| **基线重录绑定数值定稿（D4）** | 原计划「先重录」会在数值改动后再重录一次，探针断言重跑两遍 |
| 5 个缺陷从「待裁定」改为「D4 必修」 | 用户裁定全修 |
| 新增 §9.5 探针断言修改规范 | 用户裁定允许改断言，但需防「改松断言让它变绿」 |
| 新增 §7.11 失败预案砍单顺序 | 7 天里必须预先定好砍什么，避免临时决策 |
| 新增触屏 / Android 验收闸 | 双端奖要求 |
| **新增 §0.3 赛事交付材料与合规清单** | 查到官方对包体、材料、开发者日志、合规的全部硬要求 |
| **新增 §0.4 开发者日志写法规范** | 官方要求三段结构（进展/风险/计划）+ 配图 + 间隔 ≥1 天，不合规不计数 |
| **新增 §0.5 已有材料盘点与改造要求** | 实查 3 篇草稿与 AI 资产说明，发现「引擎写成 UrhoX」等必须改的错误 |
| **新增 §11.4 队长群公告与补充材料** | 隐私协议卡审核解法、投稿弹窗可占位后改、素材使用声明飞书模板 |
| **新增「开发者日志 ×5」为横切每日任务** | 全程参与奖（¥200,000）硬条件；规则禁止一天连发，是最易漏项 |
| **D4 从「重录基线」改为「双端包提交」** | 官方建议 10-18 前提交，提交日必须单独占一天且不写代码 |
| 提交策略从「PC 保底 + Android 追加」降级为应急 | 双端奖要求**同时勾选**两端、同一游戏；不赌截止后补传 |

### 11.2b v2.1 → v2.2 变更（2026-10-14 晚）

**背景**：v2.1 曾整体放弃「全程参与奖 / 社区运营」赛道。用户随后重新评估试玩次数的
统计方式，判断该奖可达，遂**恢复**该赛道。本节如实记录这次反复，避免后续接手者困惑。

| 变更 | 说明 |
|---|---|
| **恢复「全程参与奖」赛道** | 用户重新评估：试玩次数为累计值，窗口约 45 天，靠平台自然流量可达 |
| 恢复 §0.3 D 组（全程参与奖）与 F 组（社区运营加分项） | 同 v2.0 |
| 恢复 §0.4 日志写法规范（去掉了「已放弃」标记） | 重新作为任务执行 |
| 恢复 §0.5 ① 三篇草稿的改造要求 | 需按 Godot 口径重写 + 补三段结构 |
| 恢复 §7.0 全部日志项与横切任务 | 「每天 1 篇」重新生效 |
| 恢复 §7.3–§7.7 各日日志任务；§7.10 试玩运营准备 | 同 v2.0 |
| 恢复 §7.11「绝不砍」中的日志；G9 目标恢复 | 同 v2.0 |
| 删除 §1.2「不做社区运营」条目 | 该裁定已撤销 |
| §13.1 冲刺纪律恢复「日志每天一篇」 | 同 v2.0 |

**本次新增的两处修正（v2.0 的错误）**：

1. **§0.3 D 第 ③ 条的时间窗**：v2.0 写「试玩评审期（10-25 ~ 12-03）结束前 ≥50」——
   **这是推断，官方原文没有写**。2026 版《社区运营指南》原文只有「游戏被试玩次数不少于
   50 次」一句。现已标注为推断，并说明「第 ③ 条不需要现在做任何事」。
2. **§0.3 D 补入前置条件**：官方原文「全程参与奖**除需要满足按时上传符合规范的讲解视频、
   实机视频、五图素材外**，还需满足：」——v2.0 漏了这半句，会让人误以为只要三条并列条件。
   现已在 D 组开头单列。

> **最终口径**：赛道恢复，日志任务恢复，**本次为最终决定，不要再反复**。
> 唯一新增的纪律：**日志第 1 篇必须今天（10-14）发**，否则 8 天窗口凑 5 篇将无余量。

### 11.3 赛事规则查证记录（2026-10-14）

**来源（均为 2026 届官方帖）**
1. 置顶《百万奖金召唤好游戏🎉聚光灯 GameJam 报名启动❗️》
   `https://www.taptap.cn/moment/843821543216645719`
2. 《2026 聚光灯 21 天游戏创作挑战参赛全流程指南》
   `https://www.taptap.cn/moment/843496646862966742`
3. 《2026 聚光灯 21 天游戏创作挑战奖项说明》
   `https://www.taptap.cn/moment/843504338256005704`
4. 《2026 聚光灯｜新版后台安卓、PC、H5 游戏上传教程》
   `https://www.taptap.cn/moment/854478457231377904`
5. 《2026 聚光灯｜旧版后台安卓、PC、H5 游戏上传教程》
   `https://www.taptap.cn/moment/854478404412507237`
6. 辅助：游民星空《第三届 TapTap 聚光灯 GameJam 报名开启》(2026-09-01)、
   2024 届《聚光灯 GameJam 完赛清单》

**结论**
- **无引擎限制、无参赛门槛**（官方原文「0️⃣ 参赛门槛、🈚️引擎限制、总奖金超百万」）
  → **Godot 版完全合规**。此前「非制造作品能否参赛」的顾虑已解除。
- **双端奖硬性要求**：上传时**同时勾选 Android 与 Windows**；同一游戏需双端可运行；
  ❗手机端别勾小游戏、电脑端别勾 Steam；上架方式选「常规发布」（选完不能改）。
- **官方建议 10-18 前提交**（原文：「提交和审核之间有时间差，建议选手在 18 日之前就把
  作品提交上去，留出充分的时间应对突发情况」）→ 与用户原定的 10-18 上传目标一致。
- 2026 赛程：创作期 10-01 ~ 10-21；试玩评审期 10-25 ~ 12-03；颁奖 2027 年 1 月。
- **全程参与奖三条件**：demo 展示核心循环 + **开发者日志 ≥5 篇（非同日、带图、带标签）**
  + 试玩评审期结束前**去重去水下载量 ≥50**。
- **赛期禁广告**（官方评论区回复：「活动期间不能给游戏加广告哦，试玩评审结束后可以」）。
- 投稿需附**讲解视频、实机录屏、截图素材、AI 资产比例声明**。
- H5 是第三类可提交平台；本作不做。
- 包体机制：PC 传 .zip/.7z 且必须填可执行文件；Android 传 APK 且版本号 >0；
  **版本号可递增 → 平台支持覆盖更新**。

**未证实的一点**
- **投稿截止日期之后是否还允许更新包体**，官方帖未明写。间接证据：版本号机制 +
  2024 届「审核修改后上传包体时间放宽到 10 月 30 日 0 点」+ 群公告「投稿弹窗内容后续可以改」。
- **纪律**：不赌补传，双端包在 **10-18 前一次性传好**。

### 11.4 队长群公告与补充材料（2026-10-14 用户提供截图）

**来源**：TapTap 聚光灯 GameJam 队长 QQ 群公告（发布者「全自动烤面包机」）

**① 2026-10-13 15:44 — 隐私协议卡审核的官方解法（重要操作细节）**

> 「上传 apk 包遇到隐私协议问题的开发者注意了。请按照以下方式操作：
> 1. 查看群公告里的上传教程；
> 2. 在安卓包体处勾选「使用 TapPlay」；
> 3. 在隐私协议处勾选「通用隐私协议」；
> 4. 提审的时候会弹出「投稿弹窗」，如果你还没有准备好内容，请写一些占位的文字进去，
>    **后续是可以改的**，这一步务必要投稿。
> 5. 提审，立即上线试玩版。
> 操作完后，就不会因为隐私协议问题卡审核。」

→ 已写入 §0.3 B 清单。**「投稿弹窗内容后续可改」是本项目唯一一条官方明示的「可后补」证据**，
但仍**不推广到包体**。

**② 2026-10-01 18:37 — 开发者日志如何发**

> 「目前因为大家还没有游戏，所以可以把日志发到聚光灯论坛里，记得加上
> `#聚光灯gamejam开发者日志` 这个话题 tag。后续游戏做出来以后可以编辑挪到自己游戏论坛里。」

**③ 2026-10-01 19:44 / 10-08 14:50** — 指向奖项说明与三篇上传教程（本文 §11.3 已收录）

**④ 关于 TapTap 制造积分的公告** —— 与本作（Godot）无关，忽略。

**⑤ 官方「素材使用声明」模板（飞书）**

`https://xd.feishu.cn/docx/R53mdcCfMouOjPxB5PrcHJ4znOc`
标题：《素材使用声明（含 AI 生成资产说明，模板）· 2026 聚光灯 21 天游戏创作挑战》
需填：日期、素材类型（视觉：角色/场景/UI/图标；音频：音乐/音效/配音；字体；
引擎或插件内置资源；其他）与 AI 生成说明。
> 正文为 JS 渲染，工具仅取到表头。**填表时请直接打开飞书链接**。
> 本作已有内容底稿：`cashline/docs/AI-ASSETS.md`（标题即「《改道》AI 资产说明」），
> 按官方模板重排即可。

**⑥ 官方《社区运营指南：如何写好开发者日志？》**
`https://www.taptap.cn/moment/580820744309575140`

2026 更新版全程参与奖条件（比奖项说明更细）：

> 「1. 按时上传了游戏 demo，且 demo 能展示核心玩法循环（目标/规则/挑战/反馈四要素）
> 2. 开发者日志**至少 5 篇，每篇间隔不得低于 1 天**（即不能最后一天连写几篇，日志必须
>    跟着进度更新）；**每篇需包含：本期进展 / 问题与风险 / 下期计划 + 至少 1 张开发过程
>    截图或短视频**；空洞重复、拆分灌水或与作品无关的内容不计数
> 3. 游戏**被试玩次数不少于 50 次**」

- 另明确要求：按时上传符合规范的**讲解视频、实机视频、五图素材**。
- 另有「最佳社区运营奖」5 个 × ¥10,000；鼓励内容同步小红书（官方额外流量扶持）。
- 可配置「制作人员认证号」让队员也能在详情页展示身份，便于社区运营。

→ 已写入 §0.3 D/F 与 §0.4。

---

## 12. AI 任务卡模板（派活时照抄）

```markdown
### 任务：<一句话目标>
- 日程：D0 / D1 / D2 / D3 / D4 / D5 / D6 / D7
- 背景：<为什么要做，关联的已知问题编号>
- 允许改动：<精确文件列表>
- 禁止改动：<默认禁止 sim/golden_baseline.gd、sim/scenario.gd 的指纹字段、STATE_SCHEMA，
            除非任务本身就是 D4 的重录>
- 实现要求：<引用 §5 相关条款>
- 验收命令（注意哪些必须窗口模式，见 §2.1）：
    <godot> --headless --path <P> -s res://tests/run_tests.gd      # 期望 passed=83 failed=0
    <godot> --path <P> -s res://probe_xxx.gd                       # 期望 [XXX] PASS
- 证据要求：stdout 原文 + exit code + （涉及画面时）截图且必须目视
- 失败预案：<该任务在 §7.11 砍单顺序里的位置>
- 完成后：更新源文件头部注释 + 本文对应章节 + 立即提交
```

---

## 13. 快速上手（新 AI 的第一小时）

```bash
# 0. 环境
GODOT="D:/G/game/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe"
P="D:/G/game/games/reroute-godot"

# 1. 建立基线（全绿才动手）
"$GODOT" --headless --path "$P" -s res://tests/run_tests.gd
"$GODOT" --headless --path "$P" -s res://probe_golden.gd
"$GODOT" --headless --path "$P" -s res://probe_scene.gd
"$GODOT" --path "$P" -s res://probe_sync.gd        # 窗口模式！
"$GODOT" --path "$P" -s res://probe_input.gd       # 窗口模式！

# 2. 读代码顺序
sim/sim.gd → sim/scenario.gd → sim/grid.gd → sim/flowfield.gd → sim/world.gd
→ game/main.gd → game/view.gd → game/hud.gd → game/screens.gd

# 3. 改完再跑一遍第 1 步，外加受影响的闸（见 §9.3）
```

**先读 `sim/` 再读 `game/`。** 模拟层是权威，表现层是投影。任何「表现层看起来不对」
的问题，先确认模拟状态本身是否正确。

### 13.1 冲刺期特别提醒

- 今天是 **2026-10-14**。**官方建议 10-18 前提交**，硬截止 10-21。
  先看 §7.0 确认自己站在哪一天。
- **开发者日志每天一篇，不许攒**。规则禁止一天内连发，要凑够 5 篇只能每天写。
  这是全程参与奖（¥200,000 奖池）的硬条件。
- **每次改动后立刻提交**。7 天里没有回滚余量。
- **D3 之后 `sim/` 冻结**，任何数值改动都要连带重录基线，不允许。
- **D4（10-18）只做提交，不写代码。**
- 任何一天任务未完成，**不要加班补，按 §7.11 砍单**。
- 分不清优先级时，问一个问题：**这件事影响「能不能交上」吗？** 不影响就往后放。
