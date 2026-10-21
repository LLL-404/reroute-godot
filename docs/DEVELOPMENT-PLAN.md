# 《改道》Godot 版 · 开发方案（AI 交接权威文档）

> 本文是 **reroute-godot** 的唯一开发权威。任何 AI 或人类接手开发，先读本文，再读
> `README.md`（项目速览）与各源文件头部注释。
>
> 文档版本：v2.4（2026-10-16：世界 64² 重做 + 基线第二次重录（WON@6400），见 §11.7。
> v2.3 为 10-15 新增 §7.4b 制造积分使用——活动积分 95,175 于
> **10-21 12:00 到期**，含生成清单与纪律。v2.2 为 10-14 晚恢复全程参与奖赛道并
> 修正「试玩次数时间窗」推断错误，见 §0.3 D 与 §11.2b）
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

**B2. 教程操作要点（2026-10-16 三篇官帖蒸馏，上传时对照）**

- [ ] 对照自己在用的后台版本：**新版**「添加游戏 → 确认发布计划」一步里同时完成
      「上架方式 + 平台勾选」；**旧版**「发布选择」与「游戏包管理」分开操作
- [ ] 素材区先点「**查看全部**」把全部素材位展开再传；对照右上「查看物料要求」尺寸
- [ ] 包体上传后点「**展开更多**」；状态等「解析成功 / 解析通过」（**需刷新**）再往下走
- [ ] 出现红字「请填写：防沉迷、**版本内容说明**」→ 点「去配置」：
      版本内容说明写一两句（备选文案：「首个版本：完整单局塔防玩法，
      放墙改道 + 经济/波次系统，支持 PC 与安卓双端，含存档、设置与三态 BGM。」）
- [ ] 游戏启动参数**留空**；版本号填 `1.0.0`
- [ ] 实机视频/截图**只用游戏内最精彩画面**（勿用过场动画、读条、菜单；我方 5 张实机图已符合）
- [ ] 提交后**关注站内信**（提交完成 ≠ 审核完成）；官方建议 **18 日前**提交留审核冗余
- [ ] 教程原件：新版后台 `https://www.taptap.cn/moment/854478457231377904`；
      旧版后台 `https://www.taptap.cn/moment/854478404412507237`；
      「TapTap制造」路径 `https://www.taptap.cn/moment/854472244993197015`
      ——**本作不走制造线**（PC/安卓常规发布；Maker 项目仅作素材工厂）
- [ ] **载体注（2026-10-17）**：958251 系制造/关卡型（spark-only），不可承接常规双端包；
      提审改由**新建常规 app「改道」**承接——官方 `taptap-cli` 流水线，决策/步骤见 §11.22

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

**C-2. 制造积分消耗（⚠️ 硬期限 2026-10-21 12:00，过期作废）**

- [ ] 活动积分 **95,175** 于 10-21 12:00 到期，**必须在改道项目内用掉**
- [x] 刚需：**App 图标**（当前完全缺失，Android + Windows + 详情页都要）✅ 2026-10-16 icon2_core 定稿（§11.10）
- [x] 刚需：**补 7 条音效**（放墙 / 拆建筑 / 填高 / 挖低 / 波次开始 / 核心受击 / 胜负）✅ 2026-10-16 实入库 9 音效（§11.10）
- [x] 详情页头图 + 宣传图；结算 BGM 1 首 ✅ 2026-10-16 全部完成（五图 §11.11；BGM §11.10）
- [ ] 生成素材**全部登记进「素材使用声明」**
- [ ] 详见 §7.4b（含单价、路径、纪律）

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

**② AI 资产说明**（`cashline/docs/AI-ASSETS.md`；2026-10-16 已按 Godot 交付物重写，本节保留改造前评估）

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

其余待核对：**模型数量**（文中按 Maker 口径，Godot 侧为 10 个 glb）——须按 Godot
工程实测重新点数。✅ **2026-10-16 已按 Godot 交付物全文重写**（见 D0-6 行）。

> ✅ **音效条数无需修改**（2026-10-15 复核）：本文原写「文中写 18 条，实测 19 个 mp3」
> 是**误判**。`AI-ASSETS.md:24-25` 原文是「音效 全部 **18** 条」**加**「战斗音乐 对局
> BGM **一条**」= **19**，原文自洽。照原话去"修正"会把一个**对的数改错**。
> 已删去该条误判（见 §11.2d）。

**③ 素材现状（Godot 工程实测）**

- 音频：`assets/audio/sfx/` **29 个 mp3**（27 音效 + 2 BGM；10-16 D1-7 后）
- 模型：`assets/models/` 10 个 glb（zerg_worker / zerg_blade / zerg_king / gold_pile×4 /
  rubble×3）+ 配套 D/N 贴图
- 字体：`assets/fonts/NotoSansSC-Regular.otf` + `OFL.txt`（**SIL OFL 1.1，已合规**。
  2026-10-14 替换掉原 `simhei.ttf`——中易黑体是商业字体，授权不含随包再分发。
  台账见 `CREDITS.md`，对外声明见 `THIRD-PARTY-NOTICES.txt`）
- 截图：`shots/` **17 张**（`game/heat/ghost/title/gameover/hud/asset_*/model_*/
  orient_cross/smoke_*` 等；2026-10-17 清旧 -2 = UMD2 期 `model_render(_top)` 移除）；
  详情页五图 + 实机副本另置 `shots/store/`（D2-5）→ **五图素材可直接从这批里选**

---

## 0. 一句话定义

64×64 网格塔防，核心机制是**「放墙改道」**：玩家不靠堆输出，而是用墙、塔、地形改造
把敌人推上更长的路；敌人绕行越远，被击杀时赏金越高（`reward + traveled>>3`）。地图自带
一个「暗门陷阱」——挖开西南盆地的插口会拿到矿，但也会打开第三个出怪口。
（2026-10-16 世界重做由 48² 升至 64²，见 §11.7。）

---

## 1. 目标与非目标

### 1.1 目标

| 编号 | 目标 | 判据 |
|---|---|---|
| G1 | 一局 4–6 分钟，20Hz 固定步长，全程确定性可复现 | 黄金回放 16 指纹逐位一致（2026-10-16 重录） |
| G2 | 玩家所有状态变更只经 `World.apply_command` | 非法命令零副作用（指纹不变） |
| G3 | 表现层只读模拟状态，绝不回写 | `probe_sync` 视图/世界逐位对拍 |
| G4 | 导出包可自证（资源齐备 + 核心正确 + 场景可建） | `--headless --selfcheck` exit 0 |
| G5 | 所有量化闸带正/负对照，画面证据肉眼过一遍 | 见 §9 验收矩阵 |
| **G6** | **Android + Windows 双端可出包、可玩** | 双端包各自自测通过 + 真机/模拟器目视；**同一游戏页面同时勾选两端** |
| **G7** | **触屏可完成全部核心操作**（放墙拖线、点地指挥、模式切换、技能） | `probe_touch.gd`（已建）：触屏可点 + 按钮触达尺寸矩阵；全操作路径 D1 扩展 |
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

## 2. 事实基线（2026-10-19 世界生成 2.0 后全量重核）

所有数据均为此后实跑所得（原始 stdout 见 `logs/gates-20261019-worldgen/`；窗口/无头口径见 §2.1）。

| 项 | 证据 | 命令 |
|---|---|---|
| 单测 106 例全绿 | `[UNIT-DONE] passed=106 failed=0` + `[UNIT-ALL-GREEN]` | `<godot> --headless --path <P> -s res://tests/run_tests.gd` |
| 黄金回放 16 指纹逐位一致 | `[GOLDEN] checks=2 bad=0` + `[GOLDEN] PASS`（默认种子零漂移） | `<godot> --headless --path <P> -s res://tests/probes/probe_golden.gd` |
| 主场景构建对拍 | `[SCENE] checks=16 bad=0` + `[SCENE] PASS`（field=4096 / plain=39820 / solids 499/499 / covers 27/27 对拍 + 单地面网格连续性抽检） | `<godot> --headless --path <P> -s res://tests/probes/probe_scene.gd` |
| 视觉同步逐位对拍 1845 断言 | `[SYNC] checks=1845 bad=0 moved=64 match=100` | `<godot> --path <P> -s res://tests/probes/probe_sync.gd`（**窗口模式**） |
| 输入闭环 58 断言 | `[INPUT] checks=58 bad=0` | `<godot> --path <P> -s res://tests/probes/probe_input.gd`（**窗口模式**） |
| 三屏流转 39 断言 | `[UI_FLOW] checks=39 bad=0` | `<godot> --path <P> -s res://tests/probes/probe_ui_flow.gd`（**窗口模式**） |
| HUD 69 断言 | `[HUD] checks=69 bad=0` | `<godot> --path <P> -s res://tests/probes/probe_hud.gd`（**窗口模式**） |
| 全局冒烟一局到底 | `[SMOKE] checks=34 bad=0` + `[SMOKE] PASS`（run=1 seed=20261004：outcome=LOST tick=2902 kills=52 supply=422 peak_units=29 towers=5 skills=3；frames=146 mismatch=0） | `<godot> --path <P> -s res://tests/probes/probe_smoke.gd`（**窗口模式**） |
| 验收截图可出 | `[SHOTS] checks=6 bad=0`（含 20:9 / 窄屏 / 近景目视件） | `<godot> --path <P> -s res://tests/probes/probe_shots.gd`（**窗口模式**） |
| 截图像素校验 | `[SHOTS] checks=29 fail=0`（game warm=915206 teal=2733） | `python tools/check_shots.py` |
| 资产 63 断言 | `[ASSET] checks=63 bad=0` | `<godot> --path <P> -s res://tests/probes/probe_asset.gd`（**窗口模式**） |
| 蓝图 11 断言 | `[BLUEPRINT] checks=11 bad=0`（pal_min=0.060 / shp_min=0.131） | `<godot> --headless --path <P> -s res://tests/probes/probe_blueprint.gd` |
| 模型动画齐备 | `[MODEL] checks=6 bad=0`（blade/worker/king anims: Attack/Crawl/Death/Hurt/Idle） | `<godot> --path <P> -s res://tests/probes/probe_model.gd`（**窗口模式**） |
| 朝向截面图 | `[ORIENT] checks=1 bad=0` + cross shot saved | `<godot> --path <P> -s res://tests/probes/probe_orient.gd`（**窗口模式**） |
| 音频 56 断言 | `[AUDIO] checks=56 bad=0` | `<godot> --path <P> -s res://tests/probes/probe_audio.gd`（**窗口模式**） |
| 存档/设置/退出/返回 74 断言 | `[SAVE] checks=74 bad=0` 含安卓返回路由 | `<godot> --path <P> -s res://tests/probes/probe_save.gd`（**窗口模式**） |
| 触屏可点 39 断言 | `[TOUCH] checks=39 bad=0`（含按钮触达尺寸矩阵） | `<godot> --path <P> -s res://tests/probes/probe_touch.gd`（**窗口模式**） |
| 开屏 36 断言 | `[INTRO] checks=36 bad=0` + `[INTRO] PASS` | `<godot> --path <P> -s res://tests/probes/probe_intro.gd`（**窗口模式**） |
| 模拟模块 5 探针 | `[SIM/GRID/FLOW/SCENARIO/WORLD]` 各自 `checks=N bad=0` + `PASS`（5/40/53/77/20；scenario 含 48 种子自由域 sweep：盐峰 29 / 三主口 11 / 指纹互异） | `tests/probes/probe_{sim,grid,flow,scenario,world}.gd`（headless） |
| Windows 导出可用 | exit 0，`export/game.exe` 109,551,432 B + `game.pck` 109,800,796 B（2026-10-18 重出；复签 `SIGNED=Valid`） | `<godot> --headless --path <P> --export-release "Windows Desktop" <P>/export/game.exe` |
| 导出包自证 | `[SELFCHECK] checks=31 bad=0` + `[SELFCHECK] PASS` + exit 0（跑法 = 同目录 `game.exe --selfcheck`，见 §11.19 注） | `export/game.exe --selfcheck` |

- `<godot>` = `C:/G/game/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe`
- `<P>` = `C:/Users/Administrator/Documents/默认项目/reroute-godot`
- 无头 CLI **必须用 `_console.exe` 变体**，普通 `.exe` 不输出 stdout。

### 2.1 ⚠️ 头号环境陷阱（务必先看）

**`--headless` 下 SceneTree 根视口只有 64×64**，凡依赖屏幕坐标或渲染纹理的探针
（`probe_input` / `probe_sync` / `probe_hud` / `probe_ui_flow` / `probe_shots` /
`probe_smoke` / `probe_audio` / `probe_asset` / `probe_model` / `probe_orient` /
`probe_save` / `probe_touch`）
在 headless 下必然失败或空转。**这些探针必须窗口模式运行**。

本次会话中实测：
- `probe_input.gd` 在 headless 下 8 项断言失败；窗口模式下 58 项全绿。
- `probe_asset.gd` / `probe_model.gd` / `probe_orient.gd` 在 headless 下
  `get_texture()` 返回 null → `Cannot call method 'save_png' on a null value`，
  进程不退出（空转）；窗口模式下分别 PASS / 出图正常。

代码里部分文件已有注释，但 `README.md` 未写明。**派活时必须显式写明「窗口模式」。**

纯逻辑探针（`probe_sim` / `probe_grid` / `probe_flow` / `probe_scenario` /
`probe_world` / `probe_golden` / `run_tests`）与场景构建（`probe_scene`）可安全 headless。

---

## 3. 核心玩法规格

### 3.1 棋盘与地形

- 网格 `64×64`（`Scenario.w/h`；2026-10-16 由 48² 重做，见 §11.7），格子三态：`OPEN=0`（通行）/ `COVER=1`（覆盖层，
  不可通行、**可挖开**）/ `SOLID=2`（实心，不可挖）。
- 高度层 `0..5` 整数（`Sim.H_MIN/H_MAX`）。单位跨边规则：**爬升 ≤1、下降任意**
  （单向崖）；英雄无视高度。视觉换算 `H_STEP = 1.2 m/级`。
- 边界外恒 `SOLID`；`Grid` 另存一份加帧镜像 `pmap`（通行）/`hp`（高度），供流场做
  纯下标邻域运算。

### 3.2 地图要素（`Scenario` × `sim/mapgen.gd` 生成，2026-10-16 起；2026-10-19 彻底自由化，见 §11.27）

布局不再手搓。**2026-10-19 起为三路生成**（§11.27）：默认种子 20261003 → `_generate_default`
（字节冻结，锚点/指纹零漂移）；其余种子 salt 0..47 → `_generate_freeform`（每局自由核心位 /
2~3 主口 / 盆地 / 岩野 / 微丘；`Scenario` 校验结构不变量后建格，失败换盐重采样）；
salt 48..63 → `_generate_varied_legacy(seed, salt-48)` 兜底（原 G2 模板池，常规不触发）。
**首局种子 = `BASE_SEED` 20261003**，其后每局 `+run_index`（与仿真 RNG 同源、确定性；
`run_index` 跨会话持久化在 `user://settings.cfg`）。下表 = 默认种子 20261003 钉子值
（单测/探针断言面；自由路径的每局不变量 + 样本快照见 §11.27）：

| 要素 | 坐标（seed 20261003） | 说明 |
|---|---|---|
| 核心 | `(33, 6)` | 1200 HP，占地 `SOLID`，不可拆 |
| 英雄出生 | `(33, 8)` | 强制 `OPEN` |
| 出怪口 1 | `(21, 56)` | 西咽喉外，主口 |
| 出怪口 2 | `(45, 56)` | 东咽喉外，主口 |
| 出怪口 3 | `(6, 57)` | 盆地内，**仅在挖开插口后生效** |
| 盆地插口 | `(8, 53)` | 盆地岩环上缘唯一覆盖格，挖开即 `route_opened = true` |
| 岩脊 | `ridge_y=42`（行 42..44） | 咽喉口宽 3：西 `x=22`、东 `x=46`（中心），除口外全 `SOLID` |
| 盆地岩环 | `Rect2i(3, 53, 7, 8)` | 四周各一圈实心环 |
| 盆地内矿 | `x∈[5,7], y∈[56,59]`（12 格） | 诱饵：挖插口才够得着 |
| 中场矿 | `x∈[31,35], y=21`（5 格） | 安全保底；矿格共 17 |
| 稀疏表土 | `y=17 ∧ x%9==2` | `sparse_phase=2`，可挖、不给矿 |
| 南场微丘 | `Rect2i(16, 48, 2, 2)` | 2×2，`h1` |

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
│   ├─ golden_baseline.gd   16 个黄金指纹（**冻结数据**；2026-10-16 世界 64² 重录）
│   └─ save.gd              存档编解码（encode/decode/inspect；确定性补场同步）
├─ game/                    表现层（只读模拟状态）
│   ├─ main.gd              主循环 / 输入分发 / 对局生命周期
│   ├─ view.gd              3D 视图门面：_ready 组装 + 公共面转发（D5-1 拆分）
│   ├─ view_core.gd         视图基建：格子坐标 / 相机取景 / 世界→屏幕
│   ├─ view_terrain.gd      蓝图地貌：连续地面网格（场内 0.5m / 场外旷野）/ 热层 / 拾取
│   ├─ view_entities.gd     实体视觉：单位 / 建筑 / 英雄 / 死亡 / 幽灵
│   ├─ view_audio.gd        音频：SFX 池 / 环境音 / BGM
│   ├─ models.gd            真实资产（glb）实例管理
│   ├─ blueprint.gd         程序化地形蓝图（**视图种子与仿真隔离**）
│   ├─ hud.gd               顶栏 / 模式列 / 技能 / 横幅 / 赏金浮字
│   ├─ screens.gd           标题 / 暂停 / 结算 / 存档 / 设置五屏 + 确认弹窗
│   ├─ save_io.gd           存档槽位 I/O（user://save_slotN.json ×3）
│   ├─ user_settings.gd     设置持久化（user://settings.cfg：音乐 / 音效 / 全屏）
│   └─ selfcheck.gd         导出包自证
├─ tests/                   单测（100 例）+ 验收探针
│   ├─ kit.gd               记录式断言框架
│   ├─ run_tests.gd         入口
│   ├─ stub_scenario.gd     小图夹具（行为断言用）
│   ├─ probes/              19 个验收探针（见 §9）
│   └─ test_{rng,canon,grid,flowfield,scenario,world,save}.gd
├─ assets/{audio,fonts,models,image}
├─ shots/                   验收截图产物
└─ tools/                   Python 工具（check_shots / umd2_to_gltf / verify_glb）
```

### 4.2 分层与依赖方向（**单向，不许反向**）

```
sim/   ←──  game/            （表现层读模拟，模拟层不知道表现层存在）
sim/   ←──  tests/           （单测驱动模拟）
game/  ←──  tests/probes/    （探针驱动表现层与整机）
```

- `sim/` **禁止** `require`/`preload` 任何 `game/` 下的文件。
- `game/` 只允许调用 `World` / `Grid` / `FlowField` / `Scenario` / `Sim` 的**只读**
  成员；唯一的写路径是 `main.gd` 调 `world.apply_command(...)`。
- `view_entities.gd` 的插值缓存（`unit_nodes` 里的 `px/py`、`death_fx`、`_height_rev` 等）
  是**派生态**，绝不进指纹。

### 4.3 各模块职责与规模（2026-10-14 实测行数；`view*` 为 2026-10-15 D5-1 拆分后实测）

| 文件 | 行数 | 职责 | 备注 |
|---|---:|---|---|
| `game/view_entities.gd` | 418 | 单位/建筑/英雄/死亡/幽灵视觉同步 | D5-1 拆分（2026-10-15） |
| `game/view_core.gd` | 246 | 格子坐标/相机取景/渲染基建 | D5-1 拆分（2026-10-15） |
| `game/view_terrain.gd` | 422 | 蓝图地貌/地面网格/热层/拾取 | D5-1 拆分；2026-10-16 世界重做重写 |
| `game/view.gd` | 206 | 视图门面：_ready 组装 + 公共面转发 | D5-1 拆分（2026-10-15） |
| `game/view_audio.gd` | 116 | SFX 池/环境音/BGM | D5-1 拆分（2026-10-15） |
| `game/hud.gd` | 581 | HUD 全部控件 | |
| `sim/world.gd` | 576 | 世界状态机 | 核心，改动需最高谨慎 |
| `tests/test_world.gd` | 481 | world 单测 35 例 | |
| `game/main.gd` | 357 | 主循环/输入 | |
| `tests/probes/probe_input.gd` | 350 | 输入验收 | |
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
| 剧本指纹 `0x7dea2b02` | `Scenario.fingerprint()` | 改地图/波次/高度夹具、或 `sim/mapgen.gd` 参数域后必须换基线（两主口裸图路径长标定 `PATH_REF=548` ∈ [466,630] 同属此列） |
| `STATE_SCHEMA = 5` | `canon.gd` / `world.canonical_bytes()` | 改编码字段 = 升 schema 号 + 换基线 |

**禁止**为了让某个探针变绿而修改基线值。探针失败优先怀疑实现。

### 5.5 视图同步口径

- `view.sync(world)` 每帧调一次；`main._process` 内固定顺序：
  `tick 推进 → view.sync → update_ghost → hud.update → shell.update`。
- 单位插值：`frac = (tick + uid) % speed_ticks / speed_ticks`，在 `prev` 格与当前格之间
  线性插值（`probe_sync` 逐位对拍此公式）。
- 建筑施工期视觉压扁 `scale.y = 0.35`；竣工 `1.0`。
- 地面网格的重建触发条件 = `grid.height_rev` 变化（**不是**高度总和，见 §10.1）。
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
- 白盒直写（`w.supply = ...`）**只允许出现在 `tests/`**（含 `tests/probes/`），生产代码禁止。

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
# view.gd（节点：Main/View；D5-1 拆分后为门面——组装 + 转发，实现见 view_core/_terrain/_entities/_audio）
view.apply_blueprint(bp, seed, anchor := {})  # 换蓝图（每局一次）；anchor 可选 = 视觉锚点 {ridge_y, basin_y, core}
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
shell.open_slots(mode, from)       # mode: "load"|"save"；from = 返回目标页
shell.open_settings(from) / shell.open_quit_confirm()
shell.confirm_open() -> bool / shell.close_confirm() / shell.open_confirm(text, fn)

# save_io.gd（静态；SLOT_N=3，user://save_slotN.json）
SaveIO.slot_path(slot) / SaveIO.list_slots() / SaveIO.slot_info(slot) -> {empty,ok,reason,meta}
SaveIO.has_any() -> bool / SaveIO.slot_meta(slot)
SaveIO.save_slot(slot, world, run_index) -> bool / SaveIO.load_slot(slot) -> World|null
SaveIO.delete_slot(slot)

# user_settings.gd（静态；user://settings.cfg）
UserSettings.load_cfg() / save_cfg(cfg) / apply_all(cfg) / apply_audio / apply_video
```

### 6.4 对局生命周期（`main.gd` 状态机）

```
启动 → new_game() → open_title()（paused=true，静态战场被标题压住）
  「开始对局」→ start_match()  ：paused=false，HUD 显示，BGM 开，页栈空
  「继续对局」→ open_slots("load", "title")（无档禁用）→ 选有效槽位 → load_game(slot)：
      校验四重（格式/schema/剧本指纹/canonical checksum）→ 还原 world/sc →
      Blueprint.pick(存档 run) 重放视觉 → 直接进对局；损坏/版本不符 = 拒载显示原因（可删）
  「设置」→ open_settings(from)：音乐/音效滑杆 + 全屏开关，即改即落盘
  HUD「暂停」/ ESC → pause_game() → open_pause()
      「继续」/ ESC → resume_game() → 页栈空
      「保存进度」→ open_slots("save", "pause") → 空槽直写 / 占用槽先确认覆盖
      「设置」→ open_settings("pause")
      「重开本局」→ restart_game() = new_game() + start_match()
      「回标题」→ to_title() = new_game() + open_title()
  终局（WON/LOST）→ _process 检测到 → over_shown=true → open_gameover()
      「再来一局」→ restart_game()
      「回标题」→ to_title()
  「退出游戏」（仅标题）→ open_quit_confirm() → 确定 → _quit_game()（停音频 + 0.5s 延时退）
  Android 返回 → main._android_back_handle()（GO_BACK 通知 / ui_cancel 动作双入口，80ms 去抖）：
      确认弹窗=取消；暂停↔继续；进行中=暂停；存档/设置=回上级；结算=回标题；标题=退出确认
```

`current_page() == ""` 即「进行中」。ESC 在标题/结算屏**不响应**（返回键在标题 = 退出确认，
是移动端专属路由，不改桌面 ESC 语义）。

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
| **D5**（10-19） | 结构整理（`view.gd` 拆分 / 探针规整） | ⏳（D5-1 ✅ 2026-10-15） |
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
- **D3 之后冻结 `sim/`**：数值定稿即冻结，任何改动都要连带重录基线，不允许。
- 若某日任务未完成，**不加班补，直接按 §7.11 砍单**。

### 7.2 S0–S2 已完成项（不要再重复实现）

模拟核心：`lua64 / canon / rng / grid / flowfield / scenario / sim / world / verify /
golden_baseline` 十模块 + 88 例单测。

表现层：3D 视图与拾取、拖拽放墙（Bresenham，上限 12 格）、幽灵预览、威胁热层、
HUD 全部控件、标题/暂停/结算三屏、三件套音频、真实 glb 资产接入（10 个模型）、
程序化地形蓝图 3 预设轮换、导出包自证（`--selfcheck`）、Windows 导出。

### 7.3 D0（10-14）· 赛事确认 + Android 环境 + 开发者日志 ①

| 任务 | 产出 |
|---|---|
| D0-1 赛事确认 | 已由本方案 §0.1 完成（官方帖查证）。仍需从队长群确认**认证是否已通过**、**报名厂商名是否已定** |
| D0-2 开发者认证 | 个人主体、实名与身份证一致、厂商名不重名、地址到门牌号 |
| D0-3 Android 环境清点 | Godot Android 导出模板（`4.7.2.stable.mono`）、Android SDK（platform-tools + build-tools）、JDK 17、adb 是否就位；缺什么装什么。✅ **2026-10-16 补做**：cmdline-tools + licenses + platform-tools + build-tools 34.0.0/35.0.0 + platforms 34/35 装入 `%LOCALAPPDATA%/Android/Sdk`；JDK 21（Adoptium jdk-21.0.12.101）配入 editor settings（实测可导出，17 亦可） |
| D0-4 keystore | 生成 debug keystore（本轮用 debug 签名即可）。✅ **2026-10-16 补做**：`%APPDATA%/Godot/keystores/debug.keystore`（androiddebugkey），配入 editor settings（预设不内嵌路径，走全局回退） |
| D0-5 **开发者日志 ①** | ✅ **成稿已就绪**：`docs/devlogs/01-开篇-放墙改道.md`（三段结构 + 配图 + 标签齐备，可直接发布）。发布位置：自己的动态 / 聚光灯论坛（`https://www.taptap.cn/app/710826/topic`）；游戏页面建好后可编辑挪回自己游戏论坛 |
| D0-6 素材使用声明初稿 | ✅ **2026-10-16 完成**：`cashline/docs/AI-ASSETS.md` 已按 Godot 交付物全文重写（§五 引擎改 Godot 4.7.2 stable (mono)；数字按 Godot 工程实测：29 音频 / 10 glb / 图标五件套 / 详情页五图；64² 与 21 闸口径，见 §0.5 ②） |

**出口**：Android 环境清单确认完毕；日志 ① 已发（三段结构 + 标签 + 配图）；素材声明已修引擎项。

> **Godot 版日志存放位置**：`reroute-godot/docs/devlogs/`（新）。
> `cashline/docs/devlogs/` 的 3 篇是 Maker 版旧稿，仅作素材库，**不要混用**。
> 已就绪：`01-开篇-放墙改道.md`（D0 用）。

### 7.4 D1（10-15）· Android 导出管线 + 触屏输入 + 日志 ②

| 任务 | 范围 | 验收 |
|---|---|---|
| D1-1 Android 导出预设 | `export_presets.cfg` 增加 Android 预设（arm64-v8a 必选，x86_64 供模拟器）；**先出空场景包**验证管线，再出全量包 | APK 生成成功，能装能启动。✅ **2026-10-16**：debug 测试包导出成功（278MB，apksigner verify 通过）；装机/启动待真机。附带修复：`RerouteGodot.csproj` net8.0→**net9.0**（Android 模板硬性要求）、ETC2/ASTC 开启 |
| D1-2 触屏输入 | `main._unhandled_input` 增加 `InputEventScreenTouch` / `InputEventScreenDrag` 分支，映射到现有 `pointer_down` / `pointer_up` / `mouse_pos` 更新。**复用现有逻辑，不新写一套** | 新增 `probe_touch.gd`：注入触摸事件 → 世界状态变化与鼠标路径逐项一致。✅ **2026-10-16（实现路径微调，见 §11.9）**：实证 `push_input` 旁路引擎换算、`parse_input_event` 走真实链路 → **不写分支**，沿用引擎 `emulate_mouse_from_touch`；相位 6 触屏 vs 鼠标拖线世界逐字节一致（39 断言） |
| D1-3 HUD 触屏可点 | 确认 HUD 的 Control 按钮在触屏下可点；确认 `_unhandled_input` 不会被 UI 吞掉导致战场点击失效 | 真机/模拟器手动确认全部 7 个模式钮 + 技能 + 暂停 + 热层可点。✅ 断言面已由 `probe_touch` 覆盖（22 钮触达尺寸矩阵 ≥36px + 触屏点击驱动全流程）；真机手动确认并入 D2 试玩 |
| D1-4 触屏拖线 | 拖拽放墙/塔在触屏下可用（按下 → 拖动 → 抬起） | `probe_touch` 覆盖拖线路径。✅ **2026-10-16**：相位 6 全链路对拍（4 格墙/-40 供给/drag_start 清空/同 run 逐字节一致） |
| D1-5 DPI 与安全区 | 按 §6.5 的分辨率策略处理 Android 的 DPR 与刘海/手势区；HUD `S` 缩放需在窄屏下不越界 | 至少在 1 个 16:9 与 1 个 20:9 分辨率下目视截图。✅ **2026-10-16**：`stretch=canvas_items+expand` + `hud.safe` 安全区（探针注入制）；`shots/game_20x9.png`（20:9）与 `game_narrow.png`（窄屏 S=1.176）目视过；probe_hud 63→69，负对照 ×2（见 §11.9） |
| D1-6 触屏拖线 | 拖拽放墙/塔在触屏下可用（按下 → 拖动 → 抬起） | `probe_touch` 覆盖拖线路径。✅ 同 D1-4（原文两行重复，一并收口） |
| D1-7 **制造积分消耗** | 按 §7.4b 清单生成刚需素材（**图标 + 音效**），产出落 `.maker/assets/` 后搬入 `assets/` | ✅ **2026-10-16 完成**：Maker 绑定 `reroute-maker`（App「改道」）；图标（icon2_core → `assets/icon/` 五件套 → `config/icon` + 双端导出预设）；9 音效 + 结算 BGM 入库并接线（`probe_audio` 38→56 + 负对照 bad=3 + 全 21 闸绿）。详见 §11.10 |
| D1-8 **日志 ②** | 建议：Android 移植 / 触屏适配的踩坑记录 | ✅ **2026-10-16 17:36 已发**（带标签 + 配图）：https://www.taptap.cn/moment/860212304162064981（moment_id `860212304162064981`，版块·综合）；匿名复访验证通过；成稿 `docs/devlogs/02-触屏刘海与黑屏排查.md` |

**出口**：Android 全量包可启动、可操作、可完成一局。**若 D1 结束仍跑不通 → 触发 §7.11 预案。**

### 7.4b 制造积分使用（**硬期限 2026-10-21 12:00**）

**背景**（2026-10-15 制造后台实查，截图见会话记录）：

| 类型 | 余额 | 用途 | 有效期 |
|---|---|---|---|
| 通用积分 | 23,127 | 全部对话模型 + 美术资产生成 | **长期有效**（不急） |
| **活动积分** | **95,175** | 可用于「改道」 | ⚠️ **2026-10-21 12:00** |

- **活动积分优先消耗** —— 生成时自动先扣活动的，不会浪费长期有效的通用积分。放心用。
- **活动积分绑定「改道」项目** —— 必须在改道项目内生成才能用。
- 单价：音效 **10** / 3D 模型 **40** / 图片 **58** / 音乐 **84** / 视频 **226** / 对话按 token。
- 平台已改订阅制（制造 Max / Ultra），**积分申请流程暂未开放** → 存量用完不会再有新增。

**两条生成路径**：

1. **网页版**：`maker.taptap.cn` → 「改道」项目 → 对话里描述需要的素材。
2. **本地 Maker MCP**（官网「本地开发模式」）：✅ **已接入并绑定（2026-10-16）**——本地项目
   `D:\G\game\games\reroute-maker`（`taptap-maker init` 绑 App「改道」id `aff101b1-…`；
   同机另有通用 maker-game 项目，**勿选**）。参考图路径按 **Maker 项目根**解析，跨目录引用要传绝对路径。

产出落 `reroute-maker/assets/`（PNG / MP3 通用格式）→ 挑选后**复制**进本仓 `assets/`
（音效文件名即接口，`view_audio` 按名加载；**可直接进 Godot**）；
`.mdl` 是 UrhoX 专有格式，需 `tools/umd2_to_gltf.py` 转。

**生成清单（按「改动成本 × 收益」排序）**

| 优先 | 项 | 数量 | 预算 | 改动成本 | 说明 |
|---|---|---|---|---|---|
| ★★★ | **App 图标** | 1（多试 3–5 版） | 58×5=290 | 无 | ✅ **2026-10-16 完成**：9 版候选（icon1–5 + reroute_icon_a–d），用户选定 **icon2_core**；导出套件 `assets/icon/` 接入 `config/icon` + Windows/Android 预设。（原：当前完全缺失，Android/Windows/详情页都要） |
| ★★★ | **音效补齐** | 7 条 | 70 | 极低 | ✅ **2026-10-16 完成**：实做 9 条（原 7 类 + 塔开火/拆除细分，另有 `wave_horn` 替换借用的蛮王吼），接线全绿见 §11.10 |
| ★★☆ | **详情页素材** | 头图 1 + 宣传图 4 | 290 | 无 | ✅ **2026-10-16 完成**：五图齐备（`store_header` + `promo_redirect` / `promo_economy` / `promo_ambush` / `promo_barrage`，1920×1080，Maker 制造积分）→ 归置 `shots/store/`；实机图 5 张自 `shots/` 选定；登记 CREDITS §3.6（详见 §11.11） |
| ★★☆ | **BGM 补 1 首** | 1 | 84 | 极低 | ✅ **2026-10-16 完成**：`bgm_settlement.mp3` 生成并接入（D2-6 提前，三态 BGM 齐） |
| ★☆☆ | **塔 / 墙 / 核心 3D 模型** | 3–5 | 120–200 | **中高** | 当前是程序化 `BoxMesh`（方块）。换模型观感提升最大，但要改 `view.gd` 渲染路径 → **只在 D5 有余量时做** |
| ★☆☆ | **宣传视频** | 1 | 226 | 无 | 讲解视频官方必交。不自录的话可用 AI 生成片段 |

**预估总消耗约 1,100 —— 95,175 用不完是正常的。**

**纪律（重要）**：

1. **不要为了花而花。** 先做刚需（图标 + 音效）。余额作废是小事，生成一堆用不上的素材才是浪费。
2. 生成素材**必须登记进 `素材使用声明`**（官方硬要求，见 §0.3 C）。
3. ⚠️ 「**AI 美术占比 >50% 不能参评最佳美术**」—— 本作不冲该奖，无影响；日后若想冲需重估。
4. （2026-10-16 更新）29 个 mp3 里 **17 个被代码引用**——原 7 个（`orc_chief_roar` /
   `mining_gold_hit` / `build_stone_place` / `zerg_death` / `orc_death` / `dungeon_ambience` /
   `bgm_reroute`）+ 本轮新接 10 个（见 §11.10）。补音效时**别重复生成已有的**；
   刚需已齐，剩余可选项见上表 ★☆☆。

**时点**：图标 + 音效 + 详情页素材在 **D1–D2 做完**（这两天本来就在出包）；
3D 模型看 D5 余量。

### 7.5 D2（10-16）· 双端可玩包 + 首次真人试玩 + 日志 ③

| 任务 | 范围 | 验收 |
|---|---|---|
| D2-1 双端包 | PC exe + Android APK 各出一份 | 两端各自能启动完成一局。🔶 **2026-10-16 包已双端出齐**：Windows `export/game.exe`（已自签 `CN=Reroute`，本机信任链 Valid；“无法验证发布者”材料补齐）+ `game.pck`；`--main-pack` 自证 22/0 PASS；**Android 正式 `export/reroute-release.apk`（282.9MB，keystore alias `reroute`，apksigner = CN=Reroute）**。直跑被拦根因 = 本机 **SAC=1** 拦未签名 exe（**自签注册信任后双击复测已通过：能启动**）。**Windows 目视验收通过；Android 装机验收 2026-10-16 经 MuMu 12 完成（GL 验收包口径，见 §11.13）。**签名材料在仓外 `D:\G\game\keystores\`（勿入库）。详见 §11.12/§11.13；证据 `logs/gates-20261016-d2/` + `logs/gates-20261016-mumu/` |
| D2-2 包体裁剪 | ✅ 已完成（见 §7.12）：`export_presets.cfg` 设 `exclude_filter="tests/*,shots/*,tools/*"` | 包体下降，功能不受影响 |
| D2-3 真人试玩 | **至少 2 人各玩 2 局**，记录：卡在哪、什么时候看不懂、哪一步最无聊、第一局结局 | 书面记录（这决定 D3 的全部内容） |
| D2-4 引导复核 | 确认左下提示徽章与标题屏「玩法说明」是否足够；试玩者是否 5 秒内看懂「放墙改道」 | 试玩记录里的原话 |
| D2-5 **详情页素材** | 按 §7.4b 生成头图 + 宣传图；实机图从 `shots/` 选 5 张 | ✅ **2026-10-16 完成**：AI 五图齐备（头图 + 宣传 ×4 → `shots/store/`）+ 实机图 5 张选定（`game` / `heat` / `ghost` / `smoke_mid` / `game_20x9`）；登记 CREDITS §3.6。详见 §11.11 |
| D2-6 **BGM 补齐** | 按 §7.4b 补 1 首结算 BGM，接入 `view.gd` | ✅ **2026-10-16 提前完成**：`bgm_settlement.mp3`（loop）经 `view.bgm_settlement` → `main._check_outcome` 接入；标题/对局/结算三态 BGM 齐（probe_audio 3 条断言锁定） |
| D2-7 **日志 ③** | 建议：真人试玩的第一批反馈 | 已发（带标签 + 配图） |

**出口**：可玩包能发给别人；有 2 人以上的试玩记录。

### 7.6 D3（10-17）· 数值定稿 + 缺陷全修 + 一次性重录基线 + 日志 ④

**这是唯一允许改动基线的一天。** 顺序不能反：

1. **数值定稿**：按 D2 试玩记录调 `sim/sim.gd` 与 `sim/scenario.gd`。
   判据：`probe_smoke` 的 `outcome` 与 `tick` 落在设计区间（LOST 于 3500–5000 tick
   或 WON 于 6400 tick 附近），`peak_units ≤ 60`；试玩者能复述核心规则。
   **定稿后即冻结，之后不允许再改 `sim/` 数值。**
2. **缺陷全修**（§10.2）：按 E → B → C 顺序（最安全到最危险）。
   A、D 若当天来不及，移到 D6。**（E 随 D5-4、A/B/C 已于 2026-10-15 提前修复并统一重录，见 §10.2 与 §11.5；D 留档。）**
3. **一次性重录基线**：
   - `sim/golden_baseline.gd` 的黄金指纹（现 16 条）→ 用 `probe_golden` 采集新值
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
| D5-1 `view.gd` 拆分 | 972 行 → `view.gd` 门面 + `view_core`（坐标/相机/渲染基建）+ `view_terrain`（蓝图/柱带/环带/热层/拾取）+ `view_entities`（单位/建筑/英雄/死亡/幽灵）+ `view_audio`（SFX/BGM）。**纯搬移，零行为变化** | ✅ 2026-10-15 完成：拆分前后 `probe_sync` 输出逐字节一致（1749 断言、`match=100`、SHA256 一致）；全 19 闸 post 比照 pre 全绿 |
| D5-2 探针规整 | 统一输出格式、抽公共夹具（`_chk`/`_cmp` 重复实现在 10+ 个文件里）、补文件头注释。**允许改断言，但每条改动必须在提交信息里写明「原断言为何是错的」**（规范见 §9.5） | ✅ 2026-10-15 完成：新增 `tests/probes/probe_kit.gd`（ProbeKit 夹具：`check`/`fail`/`cmp_int`/`cmp_approx`/`cmp_v3`/`cmp_rect`/`finish`），17 探针统一 `extends ProbeKit`、输出统一为 `[TAG] checks=N bad=M` + `[TAG] PASS|FAIL`；重构前后 checks 数逐项一致（`probe_sync` 输出 SHA256 逐字节相同），断言变更逐条见提交信息；全 19 闸绿（证据 `logs/gates-20261015-d52/post/`） |
| D5-3 拖拽预览逐格绘制 | `view.show_ghost` 目前把首尾格画成**单个矩形**，斜线会覆盖非目标格 | ✅ 2026-10-15 完成：`show_ghost` 改逐格方块（各自贴合所在柱顶，节点循环复用）；`probe_sync` 幽灵断言重写（盒数=格数 + 逐格世界位/缩放/染色，直连+斜线两例；旧断言锁定单盒模型属错误口径已删）；负对照实跑：旧实现 + 新断言 → `bad=2 FAIL`（`logs/gates-20261015-d53/negctl_old_impl_sync.out`）；`probe_shots` ghost 场景改斜线真产线，`shots/ghost.png` 目视确认为对角阶梯绿格；全 19 闸绿（证据 `logs/gates-20261015-d53/post/`） |
| D5-4 窗口缩放一致性 | HUD 的 `S` 只在 `build()` 算一次，窗口变化时 `_layout()` 只重排不重算比例 | ✅ 2026-10-15 完成：`_layout()` 开头重算 `S`（布局与 `hit_regions()` 均取当前视口，恒同步，缩放后点击排除不再错位）；`probe_hud` 新增「窗口缩放一致性」7 条（56→63：缩放后 S=1.1765、顶栏高随 S、两命中区随 S；还原后回 1.0/64）；负对照实跑：旧 hud + 新断言 → `bad=4 FAIL`（`logs/gates-20261015-d54/negctl_old_impl_hud.out`）；全 19 闸绿（证据 `logs/gates-20261015-d54/post/`） |

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
2. **`view.gd` 拆分（D5-1）** —— 同上（**已完成 2026-10-15，本项失效**）
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
- **包体**：原 PC `export/game.pck` 72 MB。原 `export_presets.cfg` 的
  `export_filter="all_resources"` 且 `exclude_filter=""`，导致 **`shots/` 的 15 张截图、
  `tests/`（含 17 个探针）全被打进包**。已设 `exclude_filter="tests/*,shots/*,tools/*"`
  排除全部非运行资源。Android 侧尤其重要。
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
| 探针 | `probe_<领域>.gd`，`tests/probes/` | `tests/probes/probe_input.gd` |
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
| 单测 | `run_tests.gd` | `passed=106 failed=0` + `[UNIT-ALL-GREEN]` | 否 |
| 黄金回放 | `tests/probes/probe_golden.gd` | `[GOLDEN] checks=2 bad=0` + `PASS`（16 指纹） | 否 |
| 模拟模块 | `tests/probes/probe_{sim,grid,flow,scenario,world}.gd` | 各自 `[TAG] checks=N bad=0` + `PASS` | 否 |
| 场景构建 | `tests/probes/probe_scene.gd` | `[SCENE] checks=16 bad=0` + `PASS`（field=4096 / plain=39820 / 单地面网格对拍） | 否 |
| 蓝图 | `tests/probes/probe_blueprint.gd` | `[BLUEPRINT] checks=11 bad=0` + `PASS` | 否 |
| 视觉同步 | `tests/probes/probe_sync.gd` | `[SYNC] PASS match=100 bad=0` | **是** |
| 输入闭环 | `tests/probes/probe_input.gd` | `[INPUT] PASS bad=0` | **是** |
| HUD | `tests/probes/probe_hud.gd` | `[HUD] PASS bad=0` | **是** |
| 三屏流转 | `tests/probes/probe_ui_flow.gd` | `[UI_FLOW] PASS bad=0` | **是** |
| 存档与设置 | `tests/probes/probe_save.gd` | `[SAVE] checks=74 bad=0` + `PASS`（含安卓返回路由） | **是** |
| 全局冒烟 | `tests/probes/probe_smoke.gd` | `[SMOKE] PASS` | **是** |
| 资产/模型 | `tests/probes/probe_{asset,model,orient}.gd` | 各自 `[TAG] PASS`（model/orient 出图；checks=6/1） | **是** |
| 音频 | `tests/probes/probe_audio.gd` | `[AUDIO] PASS bad=0` | **是** |
| 截图像素 | `tests/probes/probe_shots.gd` + `python tools/check_shots.py` | 探针 `[SHOTS] checks=6 bad=0` + 像素 `[SHOTS] checks=29 fail=0` | **是** |
| 开屏 | `tests/probes/probe_intro.gd` | `[INTRO] checks=36 bad=0` + `PASS` | **是** |
| 导出自证 | 同目录 `game.exe --selfcheck`（本机 SAC 拦未签名 exe，口径更正见 §11.19 注） | `[SELFCHECK] PASS` + exit 0 | 否 |
| **触屏闭环** | `tests/probes/probe_touch.gd` | `[TOUCH] checks=39 bad=0` + `PASS`（触摸可点 + 按钮触达尺寸矩阵）；拖线/技能等全操作路径 D1 扩展 | **是** |
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
| `sim/mapgen.gd` / `sim/scenario.gd`（布局生成） | 单测（`test_mapgen`/`test_scenario` 自由域 sweep + 快照）+ `probe_{scenario,scene,blueprint,golden}` + **全部窗口探针**（地图数据变化波及截图/输入/音频选格） |
| `game/main.gd` | `probe_input` + `probe_ui_flow` + `probe_smoke` + `probe_touch` + `probe_save` |
| `game/view.gd` / `game/view_*.gd` | `probe_sync` + `probe_scene` + `probe_shots`/`check_shots` + `probe_audio`（改 `view_audio` 时） |
| `game/hud.gd` / `screens.gd` | `probe_hud` + `probe_ui_flow` + `probe_touch`（触屏可点）+ `probe_save` |
| `game/save_io.gd` / `game/user_settings.gd` | `probe_save` + `probe_audio`（改 bus 逻辑时） |
| `sim/save.gd` | `run_tests`（test_save）+ `probe_save` + `probe_golden`（不触碰模拟路径的护栏） |
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
| 1 | 视图地面柱带不含 sim 高度，与 `ground_y` 口径不一致（单位「浮」在柱顶之上） | `view_terrain.gd _rebuild_field` | 柱高改为 `field_h + grid.get_h * H_STEP` |
| 2 | 改高检测用「高度总和」，**等量反向改高（+1/−1）漏检**，地貌不刷新 | `view_entities.gd sync` | 新增 `Grid.height_rev`，按版本号触发 |
| 3 | 改高走 `build_terrain()` 全量重建，**清空单位/建筑视觉缓存** | `view_entities.gd sync` | 只调 `_rebuild_field()` |
| 4 | 重开一局只重置 `heat_on` 标志，热层网格与 HUD 按钮不熄灭 | `main.gd new_game` | 补 `view.set_heat(false)` + `hud.set_heat_vis(false)` |
| 5 | 建造预览（幽灵）不检查英雄占格，模拟层却拒建 → 预览显示绿色但点击无效 | `main.gd mode_valid` | 补英雄占格守卫 |
| 6 | `set_mode` 有两条路径，HUD 高亮可能不同步 | `main.gd` | 统一走 `set_mode()` |
| 7 | `run_tests` 退出时报 14 个对象泄漏 + 8 个资源占用 | `tests/kit.gd` | 用例执行完 `tests.clear()` 解循环引用 |

### 10.2 本轮必修（D4 一天内全修，修完一次性重录基线）

用户 2026-10-14 裁定：**全修，允许重录基线。**

| # | 问题 | 位置 | 修法 |
|---|---|---|---|
| A | 黄金命令表**未按 tick 排序**：[1150..1195] 与 [30..461] 的条目排在 5600 之后，执行器只顺序消费 → 这些命令实际延后执行 | `verify.gd SCRIPT_COMMANDS` | ✅ 2026-10-15 完成：①新增 verify 单测 3 例（稳定排序 / 乱序≡有序 + 参照实现对拍 / 金表非降序回归锁）；②`Verify.sorted_commands()` 稳定排序防御 + `SCRIPT_COMMANDS` 重排（81 条、校验和 112773 不变）；③重录：命令按声明 tick 生效后世界于 tick 4926 核心被毁判负（LOST），指纹 16→12（tick 800 一条未变）。负对照 negctl_old_verify.out（2 例 FAIL）。证据 `logs/gates-20261015-d6abc/` |
| B | 流场距离上界 `max_d = 14*(w+h)+16 = 1360`，`push` 超界**静默丢弃**。蛇形长廊理论路径可达 `w*h*14 = 32256` | `flowfield.gd:44,130-132` | ✅ 2026-10-15 完成：①新增单测 snake-corridor-beyond-old-bound（8×8 蛇形走廊远端 340 > 旧上界 240，旧实现必红）；②上界改为可证明值 `14×w×h`（最短路径不重复经过任何格）；③实测确认：现有地图未触及 → 当时 16 指纹逐字节不变（fingerprints_bc_unchanged.out）。负对照 negctl_old_flowfield.out |
| C | 摊销补场期间若再次改图，不会重新 `begin`，完成时却记录**最新** `grid.rev` → 可能把混合拓扑当已同步 | `world.gd:239-247` | ✅ 2026-10-15 完成：新增 `rebuild_rev` 记录本轮 begin 的 rev，中途改图则整轮重启 begin，完成时 `field_rev = rebuild_rev`；新增单测 amortized-rebuild-restarts-on-midchange（小预算连续改图 → 与全量重建逐格对照 + 变墙格 -1）；实测指纹不变。负对照 negctl_old_world.out |
| D | 围攻目标与核心不连通时建筑评分保持 `INT64_MAX`，严格小于比较使邻接敌人选不到它（现有测试固定了「贴墙不啃」行为） | `world.gd:410-435` / `test_world.gd:233-254` | ⏸ 留档（2026-10-15）：需先定设计意图（敌人该不该啃全围死的建筑），未动代码；时间不够可砍（见 §7.11） |
| E | HUD 的 `S` 只在 `build()` 算一次，窗口缩放后比例不重算 | `hud.gd:91-92,300-306` | ✅ 2026-10-15 完成（D5-4）：`_layout()` 开头重算 `S`，布局与 `hit_regions()` 恒同步（缩放后点击排除不再错位）；`probe_hud` +7 断言（56→63），负对照 bad=4 FAIL。注：字号/按钮像素尺寸的缩放刷新不在验收范围（观感项，未做）。证据 `logs/gates-20261015-d54/` |

**修复顺序**：E（最安全）→ B（加测试 + 上界）→ C（加测试 + 修竞态）→ A（排序 + 重录）
→ D（需先定意图）。**（2026-10-15 执行：E 随 D5-4，B → C → A 按序完成并统一重录；D 留档。）**

**重录纪律**：A 必然改变 16 指纹；B/C 可能改变。**一次修完再统一重录，不要边修边重录。**
（2026-10-15 执行结果：A 实际改变——指纹 16→12，世界提前于 tick 4926 判负；B/C 实测未改变任何指纹。
已按纪律一次修完再统一重录，决策记录见 §11.5。）
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

### 11.2c v2.2 → v2.3 变更（2026-10-15）

**触发**：登录制造后台实查积分（`maker.taptap.cn/credits`），发现一笔**带硬期限的存量资源**。

| 变更 | 说明 |
|---|---|
| **新增 §7.4b「制造积分使用」** | 活动积分 95,175 于 **2026-10-21 12:00 到期**（与 GameJam 硬截止同日）。含余额、单价、两条生成路径、生成清单、纪律 |
| **新增 §0.3 C-2 组** | 把积分消耗纳入交付清单（图标 / 音效 / 详情页素材 / BGM） |
| **新增 D1-7、D2-5、D2-6 任务** | 积分消耗落到日程：D1 出图标 + 音效，D2 出详情页素材 + 结算 BGM |

**实查数据**（2026-10-15）：

- 通用积分 **23,127**（长期有效，不急）；付费积分 0；活动积分 **95,175**（可用于「改道」，10-21 12:00 到期）
- **活动积分优先消耗** → 生成时先扣活动的，不浪费通用积分
- 单价：音效 10 / 3D 模型 40 / 图片 58 / 音乐 84 / 视频 226 / 对话按 token
- 现有 19 个 mp3 中**仅 7 个被代码引用**，其余 12 个闲置
- 平台已改订阅制（制造 Max / Ultra），**积分申请流程暂未开放** → 存量用完不再有新增

**关键判断**：刚需素材（图标 + 7 条音效 + 详情页素材 + 1 首 BGM）**预估仅约 1,100 积分**。
**95,175 用不完是正常的，不要为了花而花**——余额作废是小事，生成一堆用不上的素材才是浪费。

### 11.2d 事实性修正（2026-10-15，独立复核）

来源：并行会话产出的 `docs/GOVERNANCE-AUDIT-20261015.md`。**其指控已逐条自行复算，
以下三条成立并已修正**：

| # | 原文 | 实际 | 处置 |
|---|---|---|---|
| 1 | §0.5 ② 称「`AI-ASSETS.md` 写 18 条，Godot 实测 19 个 mp3，数字必须重新点数」 | **误判**。原文是「音效 全部 **18** 条」**加**「对局 BGM **一条**」= **19**，自洽 | **删去该条误判**并加注说明——照原话去改会把对的数改错 |
| 2 | §13.1 写「**D4** 之后冻结 `sim/`」 | 与 §7.6 D3「定稿后即冻结」冲突 | 改为 **D3** |
| 3 | §0.5 ③ 与 §7.12 写 `shots/` **13 张** | 实测 **15** 张 | 均改为 15 |

**未处理、待裁定的（属并行会话 §五 清单范围，避免双写冲突）**：
§10.2 缺陷表未回流地形体检 R1/R2；`sim/` 冻结日在 §7.0 与 §7.6 的表述差异；
`PLAN:8` 与 §11 台账的「已提交/尚未提交」陈旧句；两处 §锚点指向不存在的编号。

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

### 11.5 缺陷 A/B/C 修复与基线重录（2026-10-15，D6 缺陷段）

**背景**：§10.2「本轮必修」执行。E 随 D5-4 修完；本次按 B → C → A 顺序修复，一次性重录基线。

| 缺陷 | 修复 | 测试/负对照 | 指纹影响（实测） |
|---|---|---|---|
| B 流场上界 | `max_d` 由 `14×(w+h)+16` 改为可证明值 `14×w×h`（最短路径不重复格） | 新单测 `snake-corridor-beyond-old-bound`（旧实现必红） | **不变**（现有地图未触及旧上界） |
| C 摊销竞态 | 新增 `rebuild_rev`；补场中途改图则整轮重启 `begin` | 新单测 `amortized-rebuild-restarts-on-midchange`（与全量重建逐格对照） | **不变**（实测） |
| A 命令排序 | `Verify.sorted_commands()` 稳定排序防御 + `SCRIPT_COMMANDS` 按 tick 重排（81 条不变） | 新单测 3 例（含「声明 tick 生效」参照实现对拍 + 金表有序性回归锁） | **改变**：世界于 tick 4926 核心被毁判负（LOST），指纹 **16→12**（400..4800；tick 800 一条未变） |

**为何必须重录**：A 修复前 [1150..1195] 与 [30..461] 段命令实际延后到 ~5600 后才执行（数组序 ≠ tick 序），
16 条指纹记录的是「错误时序」下的行为；修复后命令按声明 tick 生效，世界提前判负，旧 16 条基线不再可达。

**受影响断言清单**：`golden_baseline.gd FPS`（16→12 条，头部注释含决策记录）、`probe_golden`（按 FPS.size() 逐条比对）、
`selfcheck.gd` 文案、单测 83→88（新增 5 例）、其余 15 闸输出逐字节一致（`logs/gates-20261015-d6abc/_cmp-d54.txt`）。

**证据**：`logs/gates-20261015-d6abc/`（post 全闸 19 绿 + 3 份负对照 + B/C 并跑指纹不变实测 + 重录原始输出）。

---

### 11.6 相机操控（2026-10-15）

**需求**：`WASD` 平移视野、鼠标右键拖拽平移（跟手）、`Q/E` 旋转视野。

**实现**（纯表现层，零模拟改动）：
- `view_core`：取景后把相机位姿抽成 `(focus 地面注视点, yaw, 基准俯角/距离)` 口径；
  `pan_world`（WASD 相对相机方向，焦点夹在地图邻域 ±30 内防丢）、
  `pan_pixels`（右键拖拽，焦平面像素→世界比例，抓取感：内容跟手）、`rotate_y`（绕焦点）。
- `world_to_screen` 由「yaw 固定」闭式解泛化为相机完整基（右/上/前向量）投影——
  平移旋转后赏金浮字定位仍准（probe 断言 <1px）。
- `main`：输入分发加右键分支（HUD 区域内不起拽）+ WASD/QE 事件驱动按键集
  （无 OS 轮询，探针可注）；`_update_camera` 在主循环推进；
  **标题/暂停/结算下冻结视角**；窗口缩放触发的取景会重置平移/旋转（回默认北向全图）。
- `view` 门面转发三个新方法。

**测试**：`probe_input` 新增 10 条（41→51）：W/D 位移方向、Q/E 旋转方向、
旋转后投影一致性 ×2、右键拖拽内容跟手（屏位移 ≈ 指部位移）、相机操控零模拟副作用
（供给/建筑数）、新视角拾取回环。负对照实跑（旧 game 三文件 + 新断言）：`bad=5 FAIL`，
exit 1（`logs/gates-20261015-cam/negctl_old_impl_cam.out`）。

**证据**：`logs/gates-20261015-cam/`（全 19 闸绿；vs d6abc 仅 3 个 .out 变化——
probe_input 按设计 +10、probe_scene ms 噪声、check_shots ±4 像素阈值内，其余 16 个逐字节一致）。

---

### 11.7 世界 64² 重做 + 基线第二次重录（2026-10-16）

**需求（用户直令）**：「地图太小」（①外圈扩展/相机放宽 ②滚轮缩放 ③默认取景更满
④玩法图真变大）、「地形不连续」（场外台阶环 + 整体方块感）、**「不应该有包围圈」**；
约束：64×64、场内也要平滑、一次做完。用户不看中途截图，由 AI 目视 `shots/` 确认。

**sim 侧**：`Scenario` 48²→64² 重排——核心 (32,6)、英雄点 (32,8)、出怪口
(20,56)/(44,56)/(5,57)、盆地插口 (5,53)、盆地矿 x4..6×y56..59、中场矿 x30..34×y20、
岩脊 y40..42、咽喉 x18..20/43..45、盆地环 x2..9×y53..61；稀疏表土保留 7 格。
指纹 `0x12715062`→**`0x02d81d2a`**（covers=25、subsolids=450）；`SCRIPT_COMMANDS`
81 条按新坐标平移；单测/探针全量随动（`run_tests` 88 例全绿）。

**视图侧**：`view_terrain` 重写为**单张水密顶点色地面网格**——采样线 = 场外渐进格距
`P(i)=HALF+i+0.06i²`（i=1..54，至 ±260.96）+ 场内 `-32..32` 步 0.5（237 线）；
格中心顶点=本格柱顶、整数坐标顶点=四邻 max（挖坑见底、填高平整）；
顶点 237²=56169、索引 334176；**外圈台阶柱带与 SOLID 独立 MultiMesh 全删**
（实心融入网格：岩石色 + 1.6m）；热层/拾取改走同一网格顶点。`blueprint` 场外改
slope 门控缓降坡（无环山）+ 中频起伏 + 远降；相机 `_zoom` 0.6–1.8×（滚轮 0.9/1.1
级进、取景重置）、平移限位 ±56、HUD 预留区 TOP56/RIGHT160/BOTTOM22；`main` 滚轮
分发（暂停/标题/结算与 HUD 区冻结，`_camera_free` 同口径）。

**基线第二次重录（本次裁定）**：剧本与地图是**同一契约的两半**，地图重排 → 旧脚本
可达的 12 条基线整体失效，按冻结纪律一次重录：**16 条（400..6400）**，结局由
LOST@4926 变 **WON@6400（核心余 784）**。原因：出怪口（南岸）→ 核心（北岸）路径
延长 ~50%，同脚本防守转胜，属**真实行为变更**而非实现漂移；当前脚本局偏易，
D3 数值定稿时结合本轮回试玩一并评估。

**测试**：`probe_scene` 新增 5 条（单地面 mesh / 单 surface / 56169 顶点 /
334176 索引 / 连续性行检）+ 计数换 `field=4096`/`plain=39312`（checks 6→11）；
`probe_input` 新增滚轮 6 条（拉近/还原/限位 0.6/限位 1.8/暂停冻结/HUD 冻结）、
`_terrain_top` 改读地面网格顶点（checks 51→57）；`selfcheck` 计数随动。
负对照实跑（旧 game/ 五个视图文件 + 新断言）：`probe_scene` = `debug_stats` 取
`plain` 键运行时报错中止 → 无 PASS（`negctl_scene.out/.err`）；`probe_input` =
`bad=5 FAIL`（网格缺格中心顶点 ×3、填高/挖低无响应、滚轮无响应 ×3；
`negctl_input.out/.err`）。

**证据**：`logs/gates-20261016-world64/`（全 19 闸绿 + 2 份负对照；世界级重做，
不逐字节比对旧 post）；`shots/*` 全部重出并目视确认——外圈=连续旷野缓坡（无台阶
圈）、岩脊/盆地/插口可辨、核心下「暗色椭圆」经排查为集结的 blade 敌（非网格瑕疵）。

### 11.8 UI 补全：存档 / 设置 / 退出 / 安卓返回（2026-10-16）

**需求（用户直令）**：补全「开始/继续/退出/存档/设置」界面与按钮 + 移动端适配。
**用户拍板**：3 槽位 + 存档列表（「继续对局」进读档列表、「保存进度」进存档列表）；
音乐/音效滑杆 + 全屏开关（Android 隐藏该行）；安卓返回键路由 + 新触屏探针；
退出二次确认。零新美术，沿 HUD 大盘色板。

**存档**：新 `sim/save.gd`（encode/decode/inspect）——标量 + grid `cells/hgt`(base64)
+ units(10 列)/buildings(7 列) 行表 + next-id（canonical 不含、必须存）+ hero +
meta（run 供读档重放蓝图）；int64（seed/rng.state）以十进制**字符串**存（JSON number
走 double 丢精度）；四重校验（格式/schema=5/剧本指纹 `0x02d81d2a`/canonical checksum），
decode 重建世界后逐位对拍，不一致拒载。
**关键确定性修复**：encode 时若世界处于摊销补场窗口（`rebuilding` 或 `field_rev !=
grid.rev`），先 `world._rebuild_field_sync()` 补完再存——否则暂停存档落在补场中途、
读档续跑与不存档直跑漂移（补场为派生态，零指纹影响；`probe_golden` 16 指纹复核不变）。
`game/save_io.gd` 管 3 槽位 I/O（user://save_slotN.json）；损坏档先做花括号结构预检
再 JSON 解析（截断/垃圾档判坏且不刷引擎报错）。
**UI**：`screens.gd` 重写为五屏 + 确认弹窗——标题（开始/继续/设置/玩法说明/退出）、
暂停（继续/保存进度/设置/重开/回标题）、存档列表（load|save 双模式；load 可删带二次
确认；槽卡「槽 N · 第 W 波/开局 · mm:ss · 保存时刻」）、设置、结算；「继续对局」无档禁用
（损坏档也算非空——进列表可删）。

**设置**：新 `game/user_settings.gd`——user://settings.cfg；BGM/SFX 具名 bus
（滑杆 0..100 → 线性增益 → dB；0 = -80dB 静音；默认 100 保现状响度）；全屏开关
PC 生效（Android/headless 跳过）；`view_audio` 四 SFX 池 + 环境音路由 SFX bus、
BGM 走 BGM bus；`main._ready` 启动即 `apply_all(load_cfg())`。

**退出 / 安卓返回**：标题「退出游戏」+ 二次确认（确定 → `_quit_game`：停音频 +
0.5s 延时退，防活动播放对象直接 quit 的 Playback 泄漏）；Android 返回 =
`NOTIFICATION_WM_GO_BACK_REQUEST` 通知 + 非键盘 `ui_cancel` 动作双入口 →
`main._android_back_handle()`（80ms 去抖）：确认弹窗=取消；暂停↔继续；进行中=暂停；
存档/设置=回上级；结算=回标题；标题=退出确认。桌面 ESC 语义不变（标题/结算 ESC
仍不响应；键盘 Esc 事件统一换算为同一路由）。

**测试**：单测 88→100（`test_save.gd` 12 例：往返/续跑 900 与 1600 tick 指纹对拍/
rng 序列/next-id/hgt 保真/篡改·版本·截断拒载/inspect 三态）；新探针 `probe_save`
（74 断言：接线/保存/覆盖确认/读档恢复 tick·run·供给·实体/删除/损坏档/设置落盘+bus dB+
全屏/退出确认 spy/安卓返回六路由+去抖）+ `probe_touch`（29 断言：合成 ScreenTouch 驱动
开始→暂停→继续→重开 + 22 按钮触达尺寸矩阵 ≥36px）。既有探针断言零改动（纯新增）。
负对照 ×2 实跑：断 `main.save_game` 接线 → `[SAVE] FAIL`（新保存路径断言成片失败）；
关 `sim/save.gd` 终审校验 → 单测 `passed=98 failed=2`（恰为两条 tamper 用例）。

**证据**：`logs/gates-20261016-ui/`（全 21 闸绿：19 探针 + run_tests + check_shots，
stderr 零 ERROR；`shots/title.png` 改版 + 新增 `shots/slots.png`/`shots/settings.png`
目视确认）；决策补充 = `save.gd` 头注释（补场同步修复）。

### 11.9 Android 导出管线 / 触屏输入 / DPI 与安全区（2026-10-16，补做 D0/D1 遗留）

**背景**：用户指出「之前的任务没有完成」→ 复核 D0–D7 倒排，确认 D0-3/4、D1-1/2/4/5/6/7
未闭环，本轮清 D0/D1（D1-7 见下）。

**Android 管线（D0-3/4、D1-1）**：SDK（cmdline-tools + licenses + platform-tools +
build-tools 34/35 + platforms 34/35）与 JDK 21 就位；debug keystore 生成；`csproj` 改
net9.0（Android 导出模板硬性要求）；`project.godot` 增 `handheld/orientation=4`
（SensorLandscape；int 4 经实测为正确存储格式）+ `import_etc2_astc=true`；
`export_presets.cfg` 新增 Android 预设（arm64-v8a + x86_64、包名 `com.reroute.game`、
显示名「改道」、exclude 同 Windows）。导出成功：`--export-debug` → 测试 APK（278MB），
`apksigner verify` 通过。已知无害输出：build-tools 兜底提示、`shutdown_adb_on_exit`、
无图标警告（D1-7 补）。**真机装机待设备（`adb devices` 暂空）**。

**触屏决策（D1-2 关键偏离说明）**：不按原文「在 `_unhandled_input` 加 ScreenTouch/ScreenDrag
分支」实现，理由 = 双触发（引擎 `emulate_mouse_from_touch` 默认真，触摸已被换算成鼠标事件
喂进现有 pointer_down/up 路径；再写分支真机双重处理）。实证链：① `get_root().push_input()`
**旁路** Input 单例换算——按钮可点是 GUI 原生吃触摸，但世界区拖拽到不了 `_unhandled_input`
（开发期负对照 nc-pushinput：bad=4 FAIL）；② `Input.parse_input_event()` = 真实设备链路
（OS → Input 换算 → GUI/unhandled）→ 触屏拖线通过。`probe_touch` 相位 6：同 run 内
触屏拖线 vs 鼠标拖线，`canonical_bytes()` 逐字节一致 + 4 格墙 + 扣费 40 + drag_start 清空
（29→39 断言）；正式负对照 nc-touch（关 `emulate_mouse_from_touch`）bad=4 FAIL。

**DPI 与安全区（D1-5）**：`stretch/mode=canvas_items` + `aspect=expand` 落地 §6.5 策略——
逻辑视口恒「高 720 / 宽按比例」，DPR 由拉伸换算负责；HUD 与相机 `S = clampf(逻辑高/816,
1.0, 1.6)` 语义由物理像素转为**逻辑像素**（1280×720 下二者等价 → 既有断言零改动，实测
probe_input/sync/hud 缩放段全绿）。安全区新增 `hud.safe: Vector4`（左/上/右/下，逻辑像素）：
Android 由 `DisplayServer.get_display_safe_area()` 物理→逻辑换算，桌面恒 0；`_layout()` 与
`hit_regions()` 同步内缩；探针注入口 `set_safe_insets_override()`。probe_hud 新增 6 断言
（63→69），负对照 nc-safe（`_compute_safe` 恒零）bad=5 FAIL。目视件：`shots/game_20x9.png`
（1600×720＝20:9）、`game_narrow.png`（960×720 窗口＝逻辑 1280×960，S=1.176 窄屏放大），
HUD 不越界/无遮挡；`check_shots.py` 增两张尺寸+关键色校验（25 项）。

**证据**：`logs/gates-20261016-d1/`（21 闸绿：run_tests 100/0 + 7 headless 探针 +
12 窗口探针 + check_shots 25/0；负对照 ×3：nc-safe bad=5 / nc-touch bad=4 /
nc-pushinput bad=4）。

### 11.10 D1-7 制造积分素材（图标 + 音效）与接线（2026-10-16）

**Maker 绑定（解除原阻塞）**：本地 Maker MCP 生成必须落「改道」App 绑定的项目 → 本地项目
`D:\G\game\games\reroute-maker`（`taptap-maker init --app-id aff101b1-0170-4d6f-bc05-ffef7baafcec`
绑定「改道」；同机另有通用 maker-game 项目 —— **勿选**）。PAT 落 `~/.taptap-maker/pat.json`；
MCP 侧需以 `target_dir` 显式指定项目（无目录参数时 `maker_status_lite` 会误判「未绑定」）。
产物在 `reroute-maker/assets/`，挑选后**复制**进本仓 `assets/`；参考图跨目录引用须传绝对路径。

**图标**：共 9 版候选（早前会话 icon1_sandbox…icon5_zigzag + 本轮 reroute_icon_a–d，后者首跑
因相对路径误解析失败、改绝对路径后 4/4 成功），用户选定 **icon2_core**。导出套件 `assets/icon/`：
`icon_master.png`（1024 主图）+ `icon_192.png`（Android 主图标）+ `adaptive_fg_432.png` /
`adaptive_bg_432.png`（自适应前后景）+ `icon.ico`（Windows）；接线 = `project.godot config/icon`
+ `export_presets.cfg`（Windows `icon`/`console_wrapper_icon`、Android `launcher_icons`）。
图标无探针断言面（并入 D2-1 双端包目视验收）。

**音效 10 条（9 SFX + 1 结算 BGM）**，接线点（全在既有播放链上，零新接口）：

- **波次号角**：`orc_chief_roar.mp3` → 专用 `wave_horn.mp3`（语义修正：旧版借蛮王吼叫；
  probe_audio 既有断言目标同步换名，仍 1 响 / 60t 节流）。
- **放塔 / 放墙**：原统一「落石」音拆二——放塔沿用 `build_stone_place.mp3`、放墙 `wall_place.mp3`；
  建筑循环内**帧内去重**（一帧拖多格只响一次；同帧双墙去重有断言）。
- **拆除**：`building_remove.mp3`（检测 = 建筑从活表消失；拆墙/塔塌同源）。
- **填高 / 挖低**：`terrain_fill.mp3` / `terrain_lower.mp3`（`main.apply_mode_at` 前后 H 比较，
  仅实际生效才响）。
- **塔开火**：`tower_shot.mp3`（检测 = 建筑 `cooldown` 回跳；冷却递减序中任何回跳必为新射击）。
- **核心受击**：`core_hit.mp3`（核心 hp 下降检测 + **30t 节流**防多敌同啃叠音；首次建档不响）。
- **胜负 + 结算 BGM**：`match_win.mp3` / `match_lose.mp3`（0.85 增益）+
  `bgm_settlement.mp3`（loop，音量 0.40）。`view_audio` 重构为 `_bgm_play` 通播 +
  `bgm_settlement(enabled)`；`main._check_outcome()` 抽取原 `_process` 内联终局分支（语义等价），
  兼顾胜负音与结算 BGM 切入。接线期曾遇 `view.gd` 两个 `bgm_settlement` 声明并存 parse error
  （import 失败）→ 去重保留 `enabled` 版。

**测试**：`probe_audio` 38→**56** 断言（+18：放墙 / 同帧双墙去重 / 拆除 / 填挖 / 塔火 /
核心受击 / 胜负 + 结算 BGM 切入·循环态；floor 25→50）；`selfcheck` ALL_MP3 19→29。
**负对照实跑**：断塔火检测 + 核心受击 + 结算 BGM 调用 → `bad=3`（恰 3 条对应断言红，其余 53 绿），
恢复后 56/0。

**证据**：`logs/gates-20261016-d17/`（21 闸绿：run_tests 100/0 + 7 headless 探针 + 12 窗口探针 +
check_shots 25/0；`nc-d17.*` 负对照与 `audio-post-nc.*` 恢复件齐）。素材登记：本仓 `CREDITS.md`
§3.2/§3.5 + §7.4b 清单；对外件 `cashline/docs/AI-ASSETS.md` 已同批补行（2026-10-16）。

**遗留**：双端 release 包（D2-1）目视验收（图标并入；D2-5 已收盘，见 §11.11）——打包段进展见 §11.12（Windows 已签名出包 + Android 正式包与提审件封装完毕；**Windows 目视验收已通过（双击能启动）、Android 装机待设备**）。

### 11.11 详情页素材（D2-5：AI 五图 + 实机图选定）(2026-10-16)

**官方硬要求**：详情页头图 1 + 宣传图 4（五图齐备）。全部为 Maker 制造积分生成
（58 分/张，1920×1080），风格与既有 AI 管线一致。第 5 张（`promo_barrage`）参考
「头图 + 改道图」生成，其余 4 张为早批生成。

| 槽位 | 文件（`shots/store/`） | 内容 |
|---|---|---|
| 头图 | `store_header.png` | 核心与防线全景封面 |
| 宣传 1 | `promo_redirect.png` | 放墙改道（机制表达最佳） |
| 宣传 2 | `promo_economy.png` | 击杀赏金（`reward + traveled>>3`） |
| 宣传 3 | `promo_ambush.png` | 挖矿开新口（暗门两难；首批中最弱，备用） |
| 宣传 4 | `promo_barrage.png` | 弩塔齐射轰击虫群 |

**实机图 5 张**（自 `shots/`，副本同置 `shots/store/`，用户上传时最终确认）：
`game` / `heat` / `ghost` / `smoke_mid` / `game_20x9`——纯对局画面（不用菜单截图，
对齐 §0.3 E 口径），覆盖对局全景 / 威胁热层 / 改道预览 / 波次中期 / 20:9 移动端。

**归置与登记**：副本入 `shots/store/`（`shots/*` 排除出包，不进 pck；副本即提审上传源）；
登记 CREDITS §3.6；对外件 `cashline/docs/AI-ASSETS.md` 与 D1-7 素材**同批**补行（2026-10-16 收盘）。

**遗留**：用户侧上传详情页（五图 + 实机图从本仓副本取）。

### 11.12 D2-1 双端 release 包（打包段）(2026-10-16)

**Windows**：`--export-release "Windows Desktop"` 出包 `export/game.exe`（109.5MB）+
`game.pck`（80.6MB）+ `data_RerouteGodot_windows_x86_64/`（.NET publish 产物；`export/` 不入库）。
本机**直跑 game.exe 被系统拦截**——根因定位 = 本机 **Smart App Control 处于强制模式（SAC=1）**，
拦未签名新 exe。三条对照坐实：同目录拷入的微软签名 `where.exe` 可跑；Godot 官方 console exe
签名 Valid 可跑；game.exe `NotSigned` 被拒（连 PowerShell `Start-Process` 亦被策略拦）。
**这不是产物缺陷**，但两件事要记：①本机双击验收转用户侧（关 SAC 可解，一次性不可逆，用户决定）；
②「SAC 开启的玩家机器上首次运行」是发行问题（自签不满足 SAC 信誉要求；留 D4 评估去向：
说明文档 / 引导关 SAC / 换分发形态）。替代自证：`--main-pack export/game.pck --selfcheck` →
**22/0 PASS**；exe 图标抽取目视 = icon2_core。

**Windows 签名（用户侧双击报「无法验证发布者」后补齐）**：自签代码签名证书 `CN=Reroute`
（5 年期，指纹 `8048667B8B54107F7725D5C6B81F0D72B2676D58`；材料
`D:/G/game/keystores/reroute-codesign.pfx`/`.cer`，**仓外**）→ 导入 CurrentUser\TrustedPublisher
+ Root 后 `Get-AuthenticodeSignature` = **Valid**；`game.exe` 已签名（+1.3KB），本机发布者显示
Reroute。边界：自签**只在本机信任链下有效**——他人机器的 SmartScreen 不认自签（仍需 CA 证书，
或按「更多信息→仍要运行」指引操作，留 D4 写进说明）；SAC 是否放行自签待用户复测判定
（若仍拦 = SAC 本身，需关闭它或换验收形态）。重新导出 exe 后复签：`tools/sign_windows_exe.ps1`。

**Android 出包（预演 → 正式）**：`--export-release "Android"` +
`GODOT_ANDROID_KEYSTORE_RELEASE_PATH/USER/PASSWORD` 环境变量注入——预设 `keystore/*` 六字段
实测全空而导出仍完成签名，**机制实锤**（密码不落仓库/预设）→ `reroute-release-rehearsal.apk`
282.9MB 出包，`apksigner verify --print-certs` = `CN=Android Debug`（预演用 debug keystore）。
**正式**：生成 release keystore（`D:/G/game/keystores/reroute-release.keystore`，alias `reroute`，
PKCS12/RSA2048/10000 天，SHA-256 `06FB8144DF8C524F198B3A414A0474B74B1C4D25D6F8C15F0AA4B7393A4F0E3F`；
密码台账 `signing.env` 同目录，**仓外**）→ 同机制出 `export/reroute-release.apk`（282.9MB），
`apksigner verify --print-certs` = `CN=Reroute, OU=GameJam, O=Reroute, C=CN`（与 keystore 指纹一致）；
预演包已删（被正式包取代）。
单次导出 ~10 分钟（dotnet publish + 打包 + 签名 + 校验），跑闸勿按短超时。旁注：
“Could not find version of build tools that matches Target SDK, using 34.0.0” 为 build-tools
回退提示（34.0.0 实签），无害。

**侧效应修复**：证据 `logs/gates-20261016-d2/win-exe-icon.png` 被 Godot 导入扫描误当资源
（生成伴生 `.import`）——增设 `logs/.gdignore`（Godot 遇 `.gdignore` 跳过整目录扫描），
删除误生成 `.import`。

**提审上传件（2026-10-16 封装）**：Android = `export/reroute-release.apk`（282,885,969B，
SHA-256 `ee3a56d11d6257aa07e1c96d742a94f5770ae632d7f6c8576f0759d0364af1d9`）；
Windows = `export/reroute-windows.zip`（146.4MB，根目录 `game.exe`［已签名］+ `game.pck` +
`data_RerouteGodot_windows_x86_64/` + `运行说明.txt`［自签提示与「仍要运行」指引，面向他人机器］；
上传表单「可执行文件」填 `game.exe`；SHA-256
`4dc2142e67bd5403441b9a7a034a0a8f7bccd455c393024401acb866618c8eb8`）。封装纪律：打包前清
`data/` 的 `*.tmp` 与旧运行时残留（历次导出曾混入 60+ 个 dotnet publish 残留 .tmp + 旧
.NET8 文件，疑实时防护干扰——首版 zip 因此多出 ~33MB，已重封）；zip 不含 `.idsig`。
上传操作口径（TapPlay / 通用隐私协议 / 投稿弹窗占位 / 防沉迷「未接入」/ 双端同时勾选）
已收录于 §0.3 B 清单，照单执行。

**上传前终核（2026-10-16）**：四件（APK/zip/exe/pck）SHA-256 与本段登记一致、apksigner =
CN=Reroute、exe 签名 Valid、pck 自证 22/0 PASS，证据 `logs/gates-20261016-d2/final-precheck.out`；
发布快照 = 标签 `d2-1-release-20261016` + git bundle `../reroute-godot-snapshot-20261016.bundle`
（99.5MB，`git bundle verify` = okay）。同批：Maker 工程（reroute-maker）素材批入库推送 +
远端构建成功（`f0936e2`，1m20s，日志 watcher 已开）。

**遗留**：Android 装机验收 —— ✅ 2026-10-16 经 MuMu 12 完成（GL 验收包口径，见 §11.13）；Windows 已签名双击复测已通过 = 能启动。

### 11.13 MuMu 模拟器装机验收（Android 装机验收落地）(2026-10-16)

**环境**：MuMu 模拟器（Android 15，x86_64，假 Adreno 640 / 宿主 N 卡；`D:/Program Files/Netease/MuMu`，
adb `127.0.0.1:16384`；x86_64 ADB 连接与安装均正常）。

**① 提审包（Vulkan）在 MuMu 黑屏 = 模拟器侧限制，非游戏缺陷**：`export/reroute-release.apk`
安装成功（282,885,969B streamed）、进程启动、引擎初始化、主循环与游戏逻辑照常跑，但呈现层报
`ERROR: Couldn't present to Vulkan queue (VkResult error 5)`（`rendering_device_driver_vulkan.cpp:3359`，
前缀 `AHardwareBuffer(w=4,h=4) failed (-3)`），画面全黑。排查链：宿主 renderer_mode vk/dx ×
strategy perf/dis/auto × force_discrete 全组合无改善；dexdump 证实 APK 无 intent 传引擎参数机制
（`cmdLineArg` 仅为 XR 模式枚举，死路）；Godot 上游 issue（#105598 等「模拟器黑屏、真机正常」）
属同已知类问题。**结论：MuMu 虚拟 Vulkan present 不兼容，与游戏包无因果**（同代码 Windows
Vulkan 渲染早已目视验收通过）。

**② 替代验收：GL 兼容验收包（同代码同资源，仅渲染后端不同）**：临时置
`renderer/rendering_method.mobile="gl_compatibility"` → `--export-release "Android"` 出
`export/acceptance-glcheck/reroute-glcheck.apk`（同 keystore CN=Reroute，sha256 `25e79614…`，与
提审包 `ee3a56d1…` 相区分）→ **project.godot 已还原、`git status` 干净自证（提审物零污染）**。
MuMu 上日志 `OpenGL ES 3.2 - Compatibility - Adreno 640`，验收链全绿：主菜单渲染 → 开始对局
（HUD/核心 1200/供给 300/波次/工具栏）→ 放墙扣费（300→290）+ 墙入场上屏 → 自然失守结算
「防线失守 0:46」（完整对局闭环）→ 再来一局 → 选塔×60 放塔扣费 + 塔上屏 → 全程无
FATAL/crash/ANR。

**证据**：`logs/gates-20261016-mumu/mumu-08…12-*.png`（08 主菜单 / 09 对局 / 10 放墙 / 11 结算 /
12 放塔；01-07 为黑屏排查过程留档）。**口径注**：Android 目视验收用 GL 后端完成；提审包（Vulkan）
建议用户真机复验一眼（安装 + 开一局），与 D2-3 真人试玩合并执行。MuMu 现设置保留
renderer_mode=dx + strategy=auto + force_discrete=true。

### 11.14 世界程序化生成（变奏级 + 高度微变）与基线第三次重录（2026-10-16 晚）

**需求（用户裁定）**：每局玩法地图与视觉地形都要不同，但难度与观感不许漂移。「变奏级」=
结构模板固定（北岸核心山头 / 双咽喉岩脊 / 西南盆地插口陷阱 / 南场微丘），参数在可行带内
逐局变奏；「高度微变」= 高度层随布局联动（核心山头顶 5 级、岩脊 / 盆地环 / 微丘按布局落位），
不做结构性改版。

**A 阶段 · 模拟侧生成**
- 新 `sim/mapgen.gd`：纯整数、唯一随机源 = sim `Rng`（SplitMix64），`generate(seed, salt)`
  采样布局参数字典（12 维参数域：core_x 30..34 / ridge_y 40..42 / 咽喉 16..22·41..47 间距≥15 /
  盆地 x0 2..4 · y0 52..54 · 7..8×8..9 / 插口上缘列 / mid_y 19..21 / 表土相位 2..6 / 微丘 2×2）；
  **盐重采样**：结构不变量校验失败换盐重采（≤64 次），产物绝不修改。200 种子压测全过
  （salt 全 0）。
- `Scenario` 重构：`Scenario.new(seed)` = 采样 → 校验（原 `check_grid` / `check_plug_open`
  口径原样复用）→ 建格；**裸图路径长标定 `PATH_REF=548`（±15% 带 [466,630]）**——
  难度不许因布局漂移（`probe_scenario` 实测 d0=d1=548）。
- 冻结面迁移：`sim/verify.gd` 加 `script_for(sc)`（81 条命令脚本按 sc 生成，模板 + 锚定
  坐标）；`game/main.gd` 每局 `Scenario.new(BASE_SEED + run_index)` 并打印 `sc_seed`；
  `sim/save.gd` v2 增存 `sc_seed`；`game/selfcheck.gd` / `probe_golden` / `probe_world`
  全部锚定化（不再假设手搓坐标）。
- **基线第三次重录**（§5.4 流程：先说明 → 重采 → 同提交更新）：剧本指纹
  `0x02d81d2a → 0x7dea2b02`；黄金 16 指纹重采（400..6400，首 `b72e0c13`、末 `811afe0e`），
  WON@6400（核心余 744）、kills=236、supply=583。
- 单测 100→104（`test_mapgen` 生成器用例 + `test_verify` 锚定化）；全 19 探针 + check_shots
  绿：`logs/gates-20261016-mapgen-post/`。

**B 阶段 · 视觉地形算法升级（`game/`）**：见 §11.15。两阶段合计单测 104、全 19 闸 +
check_shots 全绿：`logs/gates-20261016-visual/`。

### 11.15 视觉地形算法升级（渲染观感对齐商店头图）（2026-10-16 晚）

**目标**：观感向 `shots/store/store_header.png`（峡谷宣传图）靠拢，且每局视觉不同
（预设跟随 `run_index`，与玩法种子同变）。

**B1 `game/blueprint.gd`（场算法）**
- vnoise 改五次插值；新增：域扭曲（warp 0.30..0.50）、脊状调制（`(1-|2n-1|)`，按
  `rr > 0.02` 门控成本）、台地量化（floor + smooth01 塑缓坡，场外按 `(1-g*0.7)` 淡出）、
  **阈值化拉普拉斯侵蚀**（场内 129²@0.5m 预烘焙：Neumann 边界、双线性采样；场外解析
  直取；erode_iter 5..8 按预设）。
- 远场 micro 门控（`m_fade > 0.003` 才参与），消场界接缝。
- **锚点 API**：`Blueprint.compose(bp, seed, anchor)`——`main._visual_anchor()` 从 `Scenario`
  注入 `ridge_y+1 / basin_rect 中心 / core`（注意是 `basin_rect`），视觉地形与玩法布局对齐；
  缺省 `{}` = 预设坐标（探针 / `--selfcheck` 口径不变）。
- 三预设（canyon/shale/ember）参数上浮 + 调色板整体提亮变暖。
- 性能：compose ~210ms + 场内 129² ~8ms + 全域扫 340..390ms，总 `<1s` 闸过。

**B2 `game/view_terrain.gd` / `view_core.gd`（渲染层）**
- `_field_color(h, solid, slope, cx, cy)` 重写：三档连续混色 + 坡度岩化
  （`rock_mix = clampf((slope-0.45)/1.2, 0, 0.72)`）+ 层理 sin + 确定性抖动。
- 边框圈 `RIM_BUMP := 4.2`（地图边框 SOLID 格抬升 = 峡谷崖壁围合，纯视觉）；
  背景色 = 雾色 ×(1.32,1.22,1.08)。
- 灯光：太阳 energy 1.9、暖色 (1.0,0.87,0.68)；环境光 (0.62,0.53,0.43)×0.62。

**闸与证据**：`probe_scene` 连续性抽检加崖壁例外（>2.0 台阶仅允许 `|x|≥31` 带）；顶点数
不变（56169 / 334176）；`check_shots` 25 项无需重标定即绿；全 19 闸 + 单测绿：
`logs/gates-20261016-visual/`（§2 全表已按此重核）。`shots/store/` 实机 5 图已用新截图
刷新（AI 五图未动）。

**遗留**：Windows 侧产物已按本文口径重出（`game.pck` 自证 22/0 + 复签 Valid，2026-10-16 晚）；
Android `reroute-release.apk` 仍为 D2-1 版、不含本次变更——**D4 提交前需重出双端包**
（Windows 出包后必须复签：`tools/sign_windows_exe.ps1`，PS 5.1 需 UTF-8 BOM，已修）。
提交前终核证据 = `logs/gates-20261016-final/`（headless 套件 + 重导出 + 自证）。

### 11.16 「场内地面缺失」根因修复 + 峡谷化第二步（2026-10-17 凌晨）

**根因修复（用户反馈「区域在一个坑里」）**：`view_terrain._build_indices()` 三角绕序倒置
（原 `(a,c,b)/(a,d,c)` 使全部地面面片被背面剔除）——自 world64 重做（`1e836bf`）即存在，
用户所见「平坦地板」实为雾背景穿透的洞（雾开 = fog 色，雾关 = 背景 ×1.32 可证）。
改为 `(a,b,c)/(a,c,d)`（保留共享对角 a-c）；墙带陡面因屏幕投影翻转故此前可见。
诊断链：magenta 背景测试（洞=magenta）→ NaN/数据扫描（0 异常）→ `git stash`（洞在已
提交代码同样存在，非本轮引入）→ hide/cull 测试定论。顶点数/索引数不变（56169/334176）。

**峡谷化第二步（用户拍板：rim_h=18 / 干冲沟保留 / fit 俯角落 44°）**
- `blueprint.compose` 场外新增：干冲沟（fbm 窄带挖蚀 2.2m、d>2 淡入）、崖顶脊状化
  （`crest := 0.75+0.40*rn²`）、台阶层理量化（4.5m 一层 + smooth01 圆缘）；mouth 豁口
  改由 `main._visual_anchor()` 注入 `gate_x`（spawns 格 x→世界 x−31.5），豁口对齐出发口。
- 三预设重调（canyon rim 18.0/mesa 16/und 2.2/0.050；shale 12.5；ember 21），
  微观纹理收敛；`view_terrain`：RIM_BUMP 4.2→5.0、岩壁层理带对齐 4.5m 台阶、
  场内花纹更收敛；`view_core`：环境光 0.40→0.50、太阳 elevation 52°→58°、
  `fit_camera` 俯角界 40/56→36/44（二分偏好最高可行俯角 → 默认落 44°）。
- DP 陷阱：`floor()` 推断 Variant，`var tq: float` 必须显式类型（Parse Error 一次）。

**闸与证据**：全 19 探针 + 单测 104/0 + selfcheck 22/0 全绿；`probe_scene` PASS（11）；
`check_shots` 25 项无需重标定（game_20x9 warm=958769 teal=2761，修复前 804330）；
`probe_save` 曾误用 headless 运行挂起报错——save/orient 等窗口探针必须窗口模式（§2.1）。
剧本指纹 0x7dea2b02 不变（纯视觉改动）。

---

### 11.17 峡谷化第三步：开阔荒漠口径 + 双端包重出（2026-10-17 晨）

（用户裁定「四周不应该是墙」，拍板按头图改）§11.16 前段「环崖 + 台地层理 + 北屏风」
整格局废弃——正确形态 = **开阔荒漠**：场界改成头图式矮石墙
（`RIM_BUMP` 5.0→0.8，总高 ≈2.2m，保留周向起伏与南豁口 `_rim_scale`/`_gates`）；
蓝图场外重写：环崖 rim_h 18m 级→1.1~1.7m 低沿埂（去台阶量化/去crest直墙/去北屏风
rim_north），干冲沟 2.2→1.0m 浅干河，台地原（fbm 阈值）→**8 座离散孤岩长丘**
（种子定圆环散布 r16~42m/半径 9~19m/高 0.55~1.15×mesa 6.5~10.5m；skirt=max(0.8r,
h/0.42) 斜率限幅→任一采样行相邻高差 ≤~1.5m，`probe_scene` 连续性不破），远山剪影
52m 级→7~8m 低剪影（fog_start 58+，只做朦胧地平线）。沙丘/色板/雾/暖阳全保留。
三预设 canyon/shale/ember 同步（canyon: rim 1.4/mesa 9·12·14/sky 7·64/und 2.6·0.036）。
`probe_scene` PASS、check_shots 25/0 复绿（warm=1016312）、全 19 闸 + 104 单测 +
selfcheck 复绿；**双端包重出**：`game.exe` 109,550,080B + `game.pck` 80,587,824B
（复签 Valid + pck 自证 22/0）+ `reroute-release.apk` 282,902,492B（apksigner
CN=Reroute SHA-256 06fb8144… 一致）。`shots/store/` 实机五图已换新景并逐一目视。

---

### 11.18 美术 pass：CC0 地表纹理 + 地面三平面完整版 shader + 金矿岩块（2026-10-17 晨）

**外部素材引入（第一次非字体第三方实体）**：ambientCG 全站 CC0（列入 CREDITS §二裁决表
+ 新 §3.7）。2 组 4 张 1024²：Ground093C（沙，Color/NormalGL）/ Rock061（岩，Color/NormalGL），
VRAM 压缩 + mipmap；两组 Roughness 弃用（shader 端常量分辨率权衡）；法线取 NormalGL。
`THIRD-PARTY-NOTICES.txt` 新增「2. 地表纹理」节（URL 实测可达，修改说明含裁剪明细）。

**地面完整版 shader**（新 `game/terrain_ground.gdshader`，替代原 StandardMaterial3D 三带色）：
世界空间三平面（blend=sharp）双材质混合——沙 × Ground093C、岩 × Rock061；混合权值来自
**顶点色 a 位**（CPU 侧程序化编码，`_field_color` alpha=rock_mix(0..0.72)、SOLID 恒 1，
`_outside_color` 同口径），rgb 维持程序化三带色（check_shots 校准面不依赖新纹理）。
纹理增益归一（sand_gain 1.26/1.39/1.74；rock_gain 3.60/3.90/4.20，三轮标定）、
tex_m 3.4/3.6、rough 0.62/0.66、占位法线 0.75/0.95。`view_terrain` 接线：预载 + `_ground_mat`
改 ShaderMaterial + 四纹理参数；太阳 yaw 38°→10°（南崖面 NdotL 0.42→0.53）、canyon 雾提亮
[0.650,0.525,0.405]。`check_shots` ghost 阈值 0.0003→0.0001（纹理后 AA 边缘差实测 0.00030，
原阈值零余量；真回归=game/ghost 全同 d2≈0 语义不变）。

**金矿岩块（矿格观感换新）**：核查发现 10-04 gold_ore 概念件只完成了四视图（art-review/），
成品模型从未落地（.maker 记录仅 1 条空 prompt）；27 个母版 UUID 全面排查（3 zip 全量枚举
+ all_D 联络表目视）确认无现役对应物。用四视图 multiview 直出重建
（`1b4aea1f…`，7816 verts / 398.7KB，metallic 0.15 / rough 0.75），`tools/convert_all.py`
SRC 修正 `reroute-maker/assets`（原 reroute/ 已不存在；全量重转 11/11 自证）+ gold_ore
static 任务；`models.gd` 新增 `ORE_SCENE`/`spawn_ore`（footprint 0.94 归一）、
`view_entities` 矿格 spawn_gold→spawn_ore、`selfcheck` glb 5→6、`probe_asset`
矿格断言更新（root 1.0 / inst ≈0.94）。特写目视与概念图一致（棕岩簇 + 金脉贯穿）。

**闸与证据（artpass）**：全 21 闸绿（单测 104/0；probe_asset 59/0；check_shots 25/0，
game_20x9 warm=1010153、ghost diff=0.00031）。证据 `logs/gates-20261017-artfinal/`。
指纹无变更。CREDITS §3.1 11 glb 口径、§五、R-3 同步；AI-ASSETS.md 同批补行。

**建筑三件 AI 直出（Step 5，同晨接续）**：Maker text2model 三件（wall_barrier 0.94³
footprint + 1.33h 各轴独立、tower_ballista 等比 3.1h、core_jade 等比 2.5h，balanced 档；
塔 prompt「射击/十字弩」触发平台内容过滤 422→「瞭望台/窗格」中性术语过审）。
`convert_all.py` +3 static（wall 0.0/0.9、tower 0.1/0.85、core 0.2/0.6）；
`models.gd` BUILDING_SCENES/BUILDING_SIZE + `spawn_building`（墙各轴独立对齐 footprint，
塔/核等比以防变形；返回已校准实例由调用方挂 building_root 包装节点）；
`view_entities` 建筑分支三组 `_part` 盒体拼接 → spawn_building（spec §12 盒体 fallback
正式退役）；selfcheck glb 6→9、probe_asset 资产清单 +3（59→63 checks）。
临时目视探针拍三件特写：玉晶/石墙/金帽石塔观感达标后即删。核心 emission 未做（自然光
下青玉色已达标，bloom 缺席时发光意义有限，砍单）。

**闸与证据（b3）**：headless tests 104/0 + sim/grid/flow/scenario/world 全 PASS；
窗口 sync/smoke/input/hud/ui_flow/shots/audio/model/orient/save/touch 全 PASS；
probe_asset 63/0；check_shots 25/0（game_20x9 warm=1010393）。probe_golden 在主工作树
FAIL——归因**并行会话正在实时修改 sim/（未提交半成品）**的工作树污染（canon/flowfield/
grid/world + test_* 在飞）；干净 worktree（f0033a6 checkout）复核 probe_golden PASS，
与建筑 glb 化无关。全 21 闸终值以 sim 收敛后统一重跑。证据 `logs/gates-20261017-b3/`。

---

### 11.19 六边化全换 + G2 每局地形变幅（H1–H3 + 模板池 V1 / 动机池 V2）与基线第四次重录（2026-10-17）

**需求（用户裁定链）**：①四周不要墙 → 开阔荒漠矮墙（已完成）；②「就要全换（玩法+视觉）」、
架构优先于日程；③每局地形不一样是真实目的；④G2 完整变幅；⑤六边优先（选项 C，接受 10-21
剩余 4~5 天高风险）；**H0 修订**：实采**尖顶 pointy-top odd-r（奇行右移半格）+ 64×64 矩形
阵列**（方向序 0E 1NE 2NW 3W 4SW 5SE）。

**H1 模拟核心（`sim/`）**：`grid` 换六边邻接表（`DX/DY` 表 + `nx/ny/to_axial/hex_dist`）；
`flowfield` 六向等权 STRAIGHT=10（`off_e/off_o`+`par[]`、平手序号最小、切比雪夫兜底）；
`world` 移动/`cast_shock` 轴向主轴；`canon.STATE_SCHEMA := 6`（v5 旧档拒载）。单测 104/0。

**H2 验证**：剧本指纹 **0x7dea2b02 不变**；两主口裸图路径长 548 ∈ [466,630] 标定带中段；
难度带无需重标定。

**H3 表现层（`game/`）**：`view_core` 六棱板网格（CX/CZ 8.66m 间距、纵向拉伸 15%、
`HEX_CORNERS` C0..C5、场区网格名 **"HexField"**、`world_to_cell` 精确六边包含）；棱墙只朝
低邻画（内部）＋`WALL_EMBED` 0.5（界外双面）；ghost/热层随六棱；`main.gd` gates 公式含
`+0.5*(y&1)` 半格；地标装饰半格对齐；`selfcheck` plain 钉 39820 复核 22/0。

**V1 模板池（G2 玩法侧）**：五套布局 T0 横脊（默认）/ T1 错行双脊 / T2 弧脊 / T3 斜壁 /
T4 獠牙翼。**冻结纪律**：默认种子走 `_generate_default`（参数流字节级冻结、恒 T0），
其余种子走 `_generate_varied`（遗留抽取在前、模板抽取在后）；`MapGen` 暴露静态几何面
（`band_rows/gate_rows/carved/extra_walls`）。参数域加宽：core_x 28..38 / ridge_y 39..43 /
咽喉 15..26·38..51 间距≥15 / 盆地 1..5·50..52·6..9·7..9 / mid_y 18..23 / sparse_phase 2..7 /
mesa 行 ry+5..48。`scenario` 新增 `template_id/_p/_barrier` 蒙版（三口径统一：几何/高度/校验）、
`chokes` 携带口行 c.y；`verify.script_for` 咽喉行全部相对各口 c.y（T0 恒等 ⇒ 黄金脚本逐条
不变，已在 worktree 9bb12bc 逐位实证零扰动）。check_grid 新增「屏障格非实心/咽喉缺口未开/
咽喉口高度破例/矿格压脊」四串。

**V2 动机池（G2 视觉侧）**：`blueprint.ORDER` 3→6（+ochre 赭黄 / slate 青岩 / dusk 暮紫），
**追加序位**（1..3 轮换口径逐字节不变）；新预设各配 landmark 三件套/world/micro/palette 全参；
新探针 `probe_blueprint`（11 断言：结构/配色域/采样有限/两两可辨/轮换/确定性；互辨阈值只对
新预设参与配对生效——旧三角互为同系变奏是有意设计）。**砍单序第一批已启用**：视觉族取 6
（9~12 上限未扩满，工期对冲）。

**第四次基线重录（单次）**：16 指纹 400..6400 全量换新（重录前实际 16 条全异；`ProbeKit`
失败行显示上限 12 造成「仅 12 红」假象）；结局不变 **WON@6400**（核心余 808，击杀 236，
供给余 621）；剧本指纹 0x7dea2b02 不变。取样脚本复用 `run_world` 同循环（跳过不变量检查），
用完即删。**探针口径注**：默认种子（run 1..3）视觉与玩法均冻结，历史截图/黄金语义对齐。

**V3 全闸终值与双端重出（2026-10-17）**：单测 104/0；headless：golden 2/0、scene 16/0、
sim 5/0、grid 40/0、flow 53/0、scenario 72/0（48 局扫段模板覆盖 5、指纹互异 ≥44）、
world 20/0、blueprint 11/0；窗口：save 74/0、orient 1/0、asset 63/0、model 6/0、sync 1805/0、
input 57/0、hud 69/0、ui_flow 39/0、audio 56/0、touch 39/0、shots 5/0、smoke 31/0
（run1 LOST@4937 kills=133 towers 6/6 mismatch=0）；`check_shots` 25/0；
导出件 `--selfcheck` 22/0。**双端包已重出**：Windows `export/game.exe` 109,550,080B 已复签
（SIGNED=Valid）+ `game.pck` 103,722,596B（+23MB = 建筑三件 glb，预期）；Android
`export/reroute-release.apk` 305,975,988B（keystore alias `reroute`，apksigner Signer #1
CN=Reroute）。**注**：Windows 自证跑法以 `export/game.exe --selfcheck` 直跑为准
（`--main-pack` 在 4.7.2 模板上报 path overrides 不支持，10-16 记录口径更正）。
**遗留**：Android 真机装机复验与视觉族扩满（9~12）留待时间窗内机动。

### 11.20 UI v2.1「帝王金黑」实装 + probe_input §14 标定修正（2026-10-17）

**范围**：按已批准的 `docs/UI-REDESIGN-20261017.md`（v2.1）实装 `hud.gd`/`screens.gd` 换肤，
不动任何探针锁死面（控件名、页流转 API、`set_mode` 机制 `sb_normal` meta、`FLOAT_LIFE`、
`hit_regions()`、22 钮尺寸矩阵）。新色板 token：`gold/gold_hi/gold_lo/edge_hi/shadow/track/
warn/on_gold`（原 key 全保留），色板热替换即探针安全（`DARK[key]` 动态读取）。

**衬线**：`NotoSerifSC-Bold-Sub.ttf`（子集 31 字形、13.8KB，wght=700；台账三件已登记）
以 `const F_SERIF` 引入；`_serif_title` 因子集无空格/U+3000 字形改用逐字 Label+间距方案
（不重做子集）。selfcheck 补衬线断言 → **23/0**（跑法 `--headless --path <P> --selfcheck`，
勿用 `-s res://game/selfcheck.gd`——其为 RefCounted，由 main.gd 尾部按 `--selfcheck` 调）。

**踩坑实录（title 渐变）**：①`Color(10,9,6,α)` 浮点口径分量>1 被钳白 → 必须 `Color8`；
②GradientTexture2D 方向凭两次错误渲染猜测失败 → 以一次性采图探针定地面真值：
**texture 行 0=矩形顶，`fill_from=(0,0)→(0,1)` 即顶透明→底不透明**（探针用完即删）。
同一陈旧截图连续目验两次零变化也是教训：title.png 由 probe_ui_flow 出，probe_shots 不含。

**probe_input §14 标定修正（D5/D1 先例）**：晨间 canyon3 日志同代码 57/0，实机连跑双红
(Δx≈114)。stash 基线对照同样红 → 非本次改动引入；属环境帧速漂移：W 平移按
`CAM_PAN_SPEED×Σdt`，慢帧使焦点南漂 ~30m，测点视轴深度 53.1m 出现透视放大 1.43×。
断言改**机器无关口径**（≥58 条）：投影对照动态屏内选格；跟手改测焦平面点恒 1:1；
新增「焦点位移=80×upp」几何直检。**负对照**：临时改 `pan_pixels` 侧向系数 ×2 → 两断言
同时咬红（13.9760/6.9885、Δx=160.0 与 80×upp 不符），还原后 58/0 复绿。

**改名决策**：标题菜单「继续对局」→「读档存档」（`btn_continue` 控件名不变，
probe_save 仅锁名+禁用态，零影响）；UI-REDESIGN doc §3 已按实装口径补正。

**全闸终值（实装后窗口模式重出 19 受击截图）**：单测 104/0；headless golden/scene/sim/
grid/flow/scenario/world/blueprint 全 PASS；窗口 sync/smoke/shots(5)/save/audio/asset/
model/orient 全 PASS、input **58/0**、hud 69/0、ui_flow 39/0、touch 39/0；
`check_shots.py` 25/0（金色 UI 计入 warm 谓词，910096>850724 基线）。目验 6 张
（title/hud/gameover/settings/slots/game_narrow）通过；已知小瑕疵豁免：设置页滑杆
grabber 为默认主题灰点（有意不引贴图）、gameover 卡右下 1px 描边圆角缺口。

**双端包重出（2026-10-17 午后）**：Windows `export/game.exe` 109,551,432B 复签
（SIGNED=Valid，复签后自证 23/0）+ `game.pck` 103,739,444B（较 §11.19 包 +16.8KB =
衬线子集 + UI 代码增量）；**`reroute-windows.zip` 175,551,201B 重建**——发现上一版
zip 混入 10-16 11:45 的史前 pck（80,571,148B，早于 world64 重包），系 10-16 晚重出
时漏建 zip 的遗留交付缺陷，本轮修复（game.exe/game.pck/运行说明.txt/data_* 四件码）；
Android `export/reroute-release.apk` 306,061,351B（alias `reroute`，口令台账
`signing.env`→`GODOT_ANDROID_KEYSTORE_RELEASE_*` 拼装注入，apksigner verify =
CN=Reroute, OU=GameJam, O=Reroute, C=CN）。四件 SHA-256（上传前终核口径）：
APK `178edbe4…a399b4` / ZIP `1bcbac06…f9ea05` / EXE `0539d11b…585bc` /
PCK `4bf830a9…d5b2`。README「继续对局」口径同步为「读档存档」。

### 11.21 LOD：源 4 级接回 + 按屏占比切级（2026-10-17）

**背景/决策**：美术 pass 后实机观感已逼近宣传图，移动端性能成为下一瓶颈。用户三问定案：
① **路线 B = 直接上源 4 级 LOD**（不把引擎自动网格抽取当主力）；② 激进度**冲性能**
（切级系数 1.3 偏早切）；③ 验证口径**完全不新增探针**（`verify_glb` 管线自检锁定数据 +
临时目视件三机位 + `check_shots` 复跑兜底）。

**方案硬约束**：Godot 内置 mesh LOD 是**索引级**（各级共享同一顶点缓冲，meshoptimizer
simplify 产出），塞不进美术 LOD（各级独立顶点缓冲）；MSFT_lod 未实装；
visibility_range 不具可测性且无迟滞、不便调试。故采用「转换器导出四个并列
MeshInstance3D（`lod0..lod3`，蒙皮件共享同一 skeleton）+ 运行时按屏占比切 `.visible`」。

**转换器（`tools/umd2_to_gltf.py`）**：`parse_mdl` 全 4 级解析——每级独立顶点缓冲 +
索引块，**索引块 k ↔ LOD k** 映射经「num_ib==num_lods」与三角比 100/85/65/45 双重确证；
每级独立 mesh（POSITION/NORMAL/TEXCOORD_0/TANGENT，蒙皮级另加 JOINTS/WEIGHTS）；
AABB 统一取 **LOD0**（宁大勿小）；蒙皮件四个 lod 节点共享同一 skin；节点名
`lod0..lod3`（Godot 导入后居于 Skeleton3D 之下，绑定器递归查找）。
**14/14 资产**（含建筑三件/金矿）源文件均含 4 级。

**verify_glb 断言升级**（本任务自动化验证面）：四节点/四 mesh 存在 + 逐级顶点/索引
非递增 + 蒙皮件各级挂 skin + 逐级权重和抽查；并以 **EXPECTED 表**（源 .mdl 逐级实测
verts/idx，14×4）锁定数量。14/14 PASS。

**运行时切级（`game/models.gd` + `game/view_entities.gd`）**：度量 `h = 世界半径 /
(相机距离 × tan(fov/2))`（fov 恒 45°）；阈值出自源管线 `.lodgroup` 的 screenSize
**0.20/0.08/0.03**（对象屏高占比），再乘 `LOD_AGGRESSIVENESS=1.3`；迟滞 10%（回升需
超阈值 ×1.1）防边界抖动。单位逐帧切；静态件（覆盖层/建筑）仅在**相机变换或新注册**
（`_lod_dirty`）时刷。**总回退开关：`LOD_AGGRESSIVENESS=0` → 恒 LOD0 = 原状**。
引擎 auto-LOD 保留（各级网格之下再抽，无害兜底）。

**口径保护（关键）**：`mesh_aabb` 经 `_lod_decoy` 跳过 lod1..3 → 校准口径 = LOD0，
与 glb 化前逐值一致（probe_asset 缩放断言零改而绿）；probe_asset 网格断言为 `>=1`，
天然兼容；`probe_model` 裸实例化补一行 `bind_lod(inst, 0.0)`（只显 LOD0，防四级同渲染
叠模）；selfcheck 只查 AnimationPlayer、probe_orient 走 spawn_unit，均零改。
`spawn_gold` 为死代码（无调用点），保持原样仅挂 meta 不刷新。

**目视+数字存证**（临时件用后删）：远/中/近三机位 = 默认全图 L3 / 20m L1–L2 / 3m L0；
覆盖层四档分布 25→[0,0,4,21]；切级梯 0.30→0/0.25→1/0.10→2/0.05→2/0.02→3，
迟滞 0.27→1/0.29→0 全对；近/中/远截图目验无叠模无破面。

**闸**：单测 104/0 + 全 21 闸绿（headless golden/scene/blueprint/sim/grid/flow/scenario/
world + 窗口 sync/input/hud/ui_flow/smoke/shots/audio/asset/model/orient/save/touch 全
PASS；**golden 主树直接 PASS**——并行会话的 sim 半成品已收敛提交，无需 worktree 复核）+
`check_shots` 25/0。证据 `logs/gates-20261017-lod/`。

**体积**：glb 8.0MB → 21.0MB（+13MB；蒙皮件 ×2.0~2.6，静态件 ×3.0）；pck 预计 +13MB
上下（上一包 103,739,444B，以冻结包复测为准）。**双端包需再重出**（§11.20 包在 LOD 之前）。

### 11.22 TapTap 提审通道侦查与新建常规 app 决策（2026-10-17，冻结待启动）

**通道就位**：官方 `taptap-cli`（`@taptap/cli`，Windows 二进制在 npm 全局包 `bin/`）已登录
（开发者 434158「工具道具的工作室」，凭据 keychain，token 有效）；调用需环境变量
`TAPTAP_CLI_BUNDLED_SKILLS_ROOT` 指向包根，scope 用 `--dev-id 434158 --app-id <id>`；
写操作纪律 = dry-run 预览 → 用户确认 → `--yes`（不可逆节点必停）。

**堵点裁定（只读体检，2026-10-17）**：现有 app「改道」**958251 系制造/关卡（spark）型**——
`get-available-package-types` 仅 `["spark"]`、`package_slots.windows.available=false`、
`region_flag_*` 为关卡型选项集（[1,3,4]）——**无法承接常规 APK/Windows 双端包**；方向创建时
定死、CLI 无改向命令。与 §0.3「本作不走制造线（PC/安卓常规发布）」冲突，须换载体。

**决策（用户确认）**：**新建常规 app「改道」**承接双端常规发布——`package_type=windows`
（用户选定，PC 向）+ `category=strategy` + `developer_role=developer`，create-app dry-run
已通过；创建后先读包体槽位/平台选项做**验证闸门**再继续；旧 958251 保持未发布不动（SCE
协议不签、不提交）。

**流水线（冻结，待地图算法更新落地 + 双端包终版重出后启动）**：创建 → 验证闸门 →
`upload-apk` / `upload-pc-package` → `select-package`（main=APK + windows=zip，写后读回）→
素材/字段/合规（防沉迷未接入 + TapPlay、双端平台勾选、分发状态=开放试玩）→ 自测二维码
（用户扫码）→ `precheck-app-review` → `prepare-review-snapshot` → 用户确认 →
`submit-app-review` → 投稿弹窗（占位文案已备）→ 活动页投稿（CLI 未覆盖则浏览器兜底）。

**并行缺口提醒**：投稿材料「讲解视频 + 实机录屏」尚未产出（§0.3 C 官方必交）；开发者日志
需 ≥5 篇（现 `docs/devlogs/01~03` 三篇）；制造积分 95,175 于 **10-21 12:00** 到期。

### 11.23 UI v2.2「质感层 + 样式工厂」（2026-10-17）

**动因**：v2.1 视觉完好了但「没有质感」（用户语）——正是 Gaming 反模式
（Minimalist + Static assets）；借机把 UI 样式治理也一并落掉。分六档递进提交，
每档独立绿后方可进下一档。

**P1 样式工厂搬迁（1248cf1）**：新 `game/ui_style.gd`（RefCounted，preload 引入、
不经 class_name 防全局类缓存坑）为全部 Control 样式唯一构造口；hud/_flat/_make_label、
screens/_flat/_label/_button 改一行委托；screens 裸 Color8 清零（hud 的 22 处 =
`DARK` 调色板定义区，规约白名单）。**判据坑实录：仓库里三张页面 PNG 是陈渍产物**——
回滚对照实测 head 代码与搬迁代码渲染逐字节同（MIGSAME），提交物反而不同（HEADDIFF）；
顺手以重渲染纠偏。四 UI 闸 69/39/39/74 绿。

**P2 发射器 a：运行时 Theme + type variations（283cf22）**：`UiStyle.build_theme(C,S)`
单源生成（default_font NotoSans + 变体 `PrimaryButton/MenuButton/DarkCard/TitleBar/
GoldSlider`），按 S 缓存共享实例，hud 与 shell 同源；screens 六面板/滑杆/全部菜单钮
变体一行接入；pad 逐实例钮从 `UiStyle.get_theme()` duplicate 样式盒陆 override（防共享
实例污染）。**探针面（HUD 模式钮/热层/暂停）维持发射器 b**（override+`sb_normal`
meta——probe_hud:238 只读该 meta 的 bg_color，读的是自家对象，与渲染通道天然解耦；
排查截图差时证实 settings/slots/title 的 PNG 差全为战场跑格子透过 veil 的采样噪声，
非 UI 回归）。四闸全绿。

**P3 质感层 A 档全量（f640cca）**：A1 按钮顶缘 2px 亮金（DARK.edge_hi α46→120）+ 底缘
3px 金压线（**draw 闭包零子节点，随尺寸自适应**；StyleBoxFlat 单 border_color 表达不了
双色边，闭包是唯一干净解）；A2 卡片投影 12S/4S/DARK.shadow α80→150 + 主钮 6px/α110；
A3 金字投影（衬线全题/banner/go_title/浮字/供给数，GLOW_GOLD α140 offset(0,1)）；
A4 噪粒 NoiseTexture2D 5% TILE（FastNoiseLite 种子 20260415 确定性；**game 页禁挂**
保 check_shots 契约）；A5 径向暗角 α0→80@0.78（fill_to=(0.5,0.02) 椭圆随画幅）；
A6 按下 content_margin_top+2 伪按压；C 六面板四角 8px L 饰线（同为 draw 闭包）。
unit+hud/ui_flow/touch/save/smoke/shots+check_shots 全绿；6 目验过。

**P4 守规（7fa1571）**：新 `tools/check_ui_lint.py`——L1 裸 Color 构造仅限 DARK 定义区
（区间自动探测）+ token 透明度重组豁免（`Color(DARK[…].r…)` 类算术）+ 注释剥离；
L2 StyleBox/Theme/Gradient 类构造口唯一化（工厂外全红）；L3 `theme_type_variation`
禁字面量（必须引 UiStyle.* 常量）。selfcheck +8 工厂预设一致性断言（按下位移/投影档/
共享主题同实例/变体四件/氛围纹理）= **31/0**。顺手把 title 帷幕纹理、banner 淡入初值、
hp 刻影线共 5 处收进工厂（lint 践行时清出的最后一批散件）。

**P5 终验（1b35d1c）**：全 21 闸复跑全绿（headless 9 + 窗口 12）+ check_shots 25/0 +
ui-lint PASS；19 张受击截图终版重出。

**P6 双端包终版（SAC 自证口径 = exe+pck 同目录 `--selfcheck`）**：
- game.exe 109,551,432B 复签 **Valid**（CN=Reroute）+ 同目录 selfcheck **31/0**
- game.pck 109,738,128B（较 §11.20 包 +5,998,684B；v2.2 工厂 + 他会话 glb 刷新）
- reroute-windows.zip 183,606,300B（192 条目，testzip 完整性 None-bad）
- reroute-release.apk 312,058,040B（apksigner = CN=Reroute, OU=GameJam, O=Reroute, C=CN）
- SHA-256 终版：exe `0539d11b…585bc` / pck `2470b934…ddbb` /
  apk `4f57cb95…a5f0a9`（全值）`4f57cb950194081fbf25a71a2342a1865b0cce51768f26ce95cd4718a15500a9` /
  zip `94bbaa80…b57a1`（全值）`94bbaa80a7b4af8b87ed9e0404d12a6ba0de57ea8652dfb5e2963cc66a5b57a1`

**打包方法论补记（修正 §11.20 口径）**：game.exe 是**内容无关模板件**（mono 模板 +
`project.bin` 内嵌 + Authenticode 签名块 +1,352B；模板/证书/图标不变 ⇒ **字节确定性**，
任意版本导出同哈希）。版本判据**永远**是 exe+同目录 pck 的 selfcheck 断言链
（当前 31 = v2.2），exe 单独的同哈希≠旧包。两 AI 会话并行同跑导出时 pck/exe mtime 会
被对方刷新，**以哈希 + selfcheck 双证收官**，别追 mtime。

**治理面**：维护入口唯一化 = 只改 `ui_style.gd` 参数表（VEIL 档位/投影档/噪粒度/
暗角深/TICK 臂长/GLOW 色）；双发射器并存期，判据 = selfcheck 工厂一致性 8 条 + lint 3 条；
赛后收敛方向（theme 化已全量落地，遗留 = 探针面 10 钮 override→variation 翻转 + .tscn
场景化）。

### 11.24 开屏动画「晶体特写」（2026-10-17，可交付前最后一夜）

**动因**：冷启动直落标题屏缺仪式感；用户拍板 B 方案 = 3D 核心晶体特写 + 「改道」金字 +
暗黑宇感手风琴节奏（≤4s 硬钳，终值 3.4s）+ 专用 stinger。作为品牌拍点与完整性闭环收口。

**实现**（`game/intro.gd`，CanvasLayer 30）：
- **确定性状态机**：不用 Tween——`_process(dt)` 累加 t 解析求值一切 alpha/位置/转速/光强；
  skip 只改推进速率（t×25 快收）。`t = minf(t, DUR_MAX=4.0)` 硬钳用户口径；
  probe 可 `set_process(false)` 手动喂 dt 精确断言相位（D5-2 探针纪律延续）。
- **3D 特写**：SubViewport `own_world_3d` + core_jade 裸实例等比 scale 至 CRYSTAL_H=1.8
  + `bind_lod` 只显 LOD0（口径同 spawn_building）；三灯 = key 暖金 0.8k / 晶内玉光 2.6k /
  背金 0.95k（energy 按 t 浮现进度 k 解析）；玉色光团 = **运行时烘焙径向 Image**
  （128² 逐像素 α²衰减 + 加法混合——GradientTexture2D 径向 alpha 在 Sprite3D 上实测
  不衰减成硬边矩形，弃用留档）；CPUParticles3D 金尘上扬（GL 兼容口径）。
- **2D 叠字**：「改道」金衬线逐字 76px 绝对定位（容器会顶掉 y 动画）+ 阶梯渐入（0.12s 错拍）
  + 升 8px；金线 `UiStyle.RULE` 自中心展开 ±130·S；副标语 P3 段渐入；
  P4 整层 0.6s 淡出**透出底下的标题屏**（open_title 先行，天然交叉溶解交接）。
- **音频**：`intro_stinger.mp3`（2.58s，Maker 生成；进场即放——音内 ~1.9s 水晶击点
  对齐画面 P2 金字段）；selfcheck mp3 断言 29→30。
- **门控（探针零影响）**：`main._intro_enabled()` = selfcheck / headless / 主循环脚本路径
  `res://tests/` 前缀（探针 `-s` 全命中）三类自动跳过；冷启动仅播一次；
  探针模式 main 无 intro 实例（probe_intro 断言 + 21 旧探针零改全过为证）。
- **跳过**：任意键 / 鼠标点击 / 屏幕触摸 → `_input` 吞事件（`set_input_as_handled` +
  `_root.mouse_filter=STOP` 防标题钮盲点）→ 25× 快收；Android 返回键顶部路由为跳过
  （双入口先于去抖++;不弹退出确认）。
- **启动屏**：`project.godot` + `boot_splash/bg_color` 深黑 + `show_image=false`
  （灭 Godot 默认 Logo，冷启动全程无外牌）。

**闸**：新 `probe_intro`（性能轮后 36 checks） → **全 22 闸**（单测 104/0 + headless 8 + 窗口 13 +
check_shots 25/0）+ check_ui_lint 3/0 全绿；负对照 = 关输入吞实跑 bad=3 FAIL 复原（证据
`logs/gates-20261017-intro/`），闸清单 AGENTS 同步 20→21 探针 / 12→13 窗口。
**目视**：probe P2/P3 + 真实播放三帧（0.9 黑暗浮现 / 2.0 亮起金字渐入 / 3.1 淡出透出标题）复核过。

**性能提速（2026-10-17 晚，用户反馈「开屏整段不流畅/风扇狂转」）**：实测 = 显示器 240Hz
vsync 满速渲染（开屏与标题 idle 均 240fps）+ 开屏双份全屏 3D（主世界含阴影/雾照渲）+ P1
首帧编译尖峰（p99 8.48ms / max 23.6ms）。三改：① **主世界停画**——第 1 帧留 `main.view`
暖机（编译进启动帧，口径如旧），第 2 拍起隐藏、T_P3 恢复（重绘/阴影首帧全盖在开屏下，
P4 揭示已是熟帧），`_exit_tree` 安全网兜底任意路径退出；② 子视口 `SUB_SCALE=0.7` 降分辨率
+ TextureRect 拉伸（软画场景肉眼无差，探针 P2/P3 与旧证据逐帧比对无回归）；③ **首拍预热帧**
（`UPDATE_ONCE` 把晶体材质/泛光管线编译藏进黑幕，P1 前回关）+ dt 钳 `minf(dt, 0.1)` 防长
停滞跳拍。实测（编辑器 debug 同机同场景 before/after）：开屏 p99 8.48→5.17ms、P0.5 绘制
调用 52→30、vmem 247→227MB、idle 不变（未动标题基线）。`probe_intro` 26→36 checks
（+预热/停画/恢复/安全网断言；**探针咬出「恢复后 `_ticks>=2` 重复命中隐藏分支」真 bug**）。
**菜单限帧（用户拍板 2026-10-17 晚：只限菜单/标题，对局全速）**：`main._sync_fps_cap()`
在 `_process` 顶部幂等同步 `Engine.max_fps`，判据复用 `_camera_free()`（标题/暂停/结算 =
60fps，对局 = 0 不限 vsync 全速），无状态簿记、每帧自愈。实测（同机）：标题 idle 与开屏
从 240fps 满速（4.16ms）→ **16.67ms/60fps 稳定钉死**；开屏 avg 16.58 / p99 17.14 /
max 17.20ms——**连 P1 编译尖峰都被 60fps 的 4× 帧预算吸收**。`probe_smoke` 31→34
（标题 60 / 对局 0 / 结算 60 三态断言）；全 22 闸 + check_shots + lint 复验绿。证据同目录
`after_cap_editor.out`。

**坑档（复用价值）**：① Sprite3D 径向渐变纹理 alpha 不按预期衰减（渐变机渲染口径），
运行时烘焙 Image 径向 α² 是稳解；② `Image.create` 4 参宽高 mipmap 格式，勿带第 5 参；
③ SubViewport 渲染开关三段式：首拍 `UPDATE_ONCE` 预热帧（黑幕内编译）→ `DISABLED` 直到
P1 → `UPDATE_ALWAYS`（初版为「P0 全关」，性能轮改口：**编译尖峰才是卡顿源，预热比省帧重要**）。

---

### 11.25 地形改造自然化 T1：圆唇 + 斜壁 + 渣坡裙脚 + 墙面调色（2026-10-18）

**动因**：放墙/挖坑/填高（「改造」）是核心机制词，但改造后的格边此前是**直上直下的壁块**——
方盒子感、与六边化后的自然地面割裂。用户裁定⑦「地形改造自然化」（全域统一口径、按**可爬性
真值**分级、痕迹自然无痕）；目验⑧「墙面太暗/太平，再调色」后完成调色轮。

**实现**（`game/view_terrain.gd` 纯表现层 + `terrain_ground.gdshader`，指纹 0x7dea2b02 不变）：
- **剖面口径**：每格落差边由「高格一侧」拥有（沿用旧棱墙归属）；`edge_profile(x,y,k,t,t_lo,kind)`
  输出 (r,h) 点列：P0=(0,t) 圆唇顶（**恒不外延，顶缝水密**）→ 外挑 `LIP_OUT=0.07` +
  垂落 `LIP_V=0.14`（微差边按落差收窄 `minf(LIP_V, delta*0.6)`）→ 坡身 → **沉底坡脚
  `t_lo-0.010`**（沉入低邻顶消灭底部漏光）。石阶 4 点 / 边坡（Δ1）5 点 / 崖壁（Δ≥2 或
  实心/界外）6 点；全部经 `Blueprint.ihash` 确定性微扰（去镜面平整）。
- **分级可读性**（按**模拟高度差** = 可爬性真值）：Δ0 微差 = 暗色石阶；Δ1 = **暖色渣坡**
  （一眼可走）；Δ≥2/实心/界外 = **斜壁 + 层理色阶 + 渣坡裙脚**（不可爬）。顶面板 100% 不动
  （贴地/热层/拾取全走平顶）。
- **渣坡裙脚**：崖壁剖面第 5 点 = 贴地薄楔外缘（r=`BATTER*(2.0+1.2*rel)`，高度自适应：
  恒低于坡身 2cm 且离地 ≥4mm——防实心/微差边小落差时剖面非单调/穿地）；裙脚色 = 暖色碎渣
  带（掺沙纹），第 6 点为回勾近地暗缝。面斜率签 `rel∈0.55..1.45` 逐边确定性起伏（去等宽感）。
- **角缝闭合（真 bug 修复留档）**：非顶层剖面点沿边方向外延 `0.75×r`——相邻边在共享角重叠
  成折缝，消灭特写下的「梳齿」楔形漏光亮缝；延伸量 < 面深，不产生新穿插。
- **墙面调色**：shader 新增 `rock_soft_up`——岩权区世界法线向上偏 `a*rock_soft_up` 借顶光；
  层理双频带 + 逐边明暗签 + `tag<0.24` 明面亮带 + 暖色地板防死黑；`nrm_rock` 0.95→0.75
  柔化孔洞斑驳。终值 `rock_soft_up=1.05`（近景墙面带均值 38.6→78.5 / 255；曲线：0.45→+5%、
  0.85→53、1.2→98、2.0→111）。

**关键实测（反直觉，留档）**：**顶点法线对墙面光照零效果**——fragment NORMAL 由三平面法线
贴图按 `w=pow(abs(n),6)` 权重重算，垂直面无论顶点法线怎么弯，权重都落到水平面 normal map
（n2y 弯折 0.85 实测像素均值 38.6→38.5 = 噪音）。提亮只有两路：顶点色反照率、shader 法线补偿。

**闸**：`probe_sync` 新增「自然化棱边」段（`_terrain_edge_check` + 剖面形状/顶点账目/确定性
断言）——填 1 级 → 6 边全可爬、填 2 级 → 全崖壁、降级 → 回坡、账目独立重算（**函数内自调
`edge_profile` 随剖面点数演进**，本次崖壁 5→6 点时账目公式自动跟进）、重建两次逐位一致、
P0 精确在顶线、末点贴/沉低邻顶、高度单调不增。**1829/0 PASS**；负对照（旧实现 + 新断言）=
`bad=1 FAIL` 单条干净（守卫探测 `edge_kind_at/edge_profile` 缺失）。`probe_shots` 增设第 6 图
`game_closeup.png`（填两级崖壁+裙脚 / 挖一级坑特写）；`check_shots` 25→29 项（特写尺寸/
唯一色/暖色下限）。全 22 闸绿（证据 `logs/gates-20261018-t1nat/`）；store 实机五图副本刷新。

**目视迭代**：特写排查修掉底脚漏光与角缝亮条；调色轮三版收敛（近景带均值 38.6 → 53 → 78.5，
全景暖色像素 850724→914813）；`game.png` 全景 + `game_closeup.png` 特写目验通过。演示价值：
`game_closeup` 即「改造前后」对照素材（填高成台 / 挖坑成池 / Δ1 坡 vs Δ2 崖可读性），
可作开发者日志④⑤配图。

---

### 11.26 双端包重出（2026-10-18，含开屏/限帧/自然化三项增量）

**动因**：v2.2「终版」包（10-17 17:50）之后代码继续演进——开屏动画（8177c59）、开屏提速 +
菜单限帧（5bdadf9/b652f17）、自然化 T1（013dd8d）均不在包内；真机验证与提审流水线需最新包。

**结果（四件）**：
- `game.exe` 109,551,432B，复签 **Valid**（CN=Reroute；签名后与 v2.2 包 **SHA-256 逐字节同哈希**
  `0539d11b…2285bc`——「exe = 内容无关模板件」口径第三次实证）；同目录 `--selfcheck` **31/0 PASS**
- `game.pck` 109,800,796B（较 v2.2 +62,668B；纯代码增量）
- `reroute-release.apk` 312,119,839B（较 v2.2 +61,799B；apksigner v2/v3 = true，
  DN `CN=Reroute, OU=GameJam, O=Reroute, C=CN`）
- `reroute-windows.zip` 183,669,125B（192 条目，testzip None-bad；含已签名 exe + pck +
  `data_RerouteGodot_windows_x86_64/` + `运行说明.txt`；不含 .idsig）
- SHA-256：pck `153082ee…d9c5` / apk `44956252…f053` / zip `0a6a324f…c1992`；
  证据 `logs/gates-20261018-t1nat/export-{win,apk,selfcheck}.out`

**上传件**：APK + zip（Zip 上传表单「可执行文件」填 `game.exe`）；§0.3 B 清单照单执行。

---

### 11.27 世界生成 2.0：玩法层彻底自由化（2026-10-19）

**动因**：用户要求「Minecraft 式」程序化生成——每局地形骨架不再套模板，而是每种子自由生长；
拍板「彻底自由化（大改）」，允许玩法布局随生成变化。拆两拍交付：**拍 1（本次）= 玩法世界
生成自由化**；**拍 2（后续）= 视觉联动**（岩脊/山体/动机池跟随自由布局）。难度不漂移的
硬约束不变：裸图路径长必须落在 `PATH_REF 548 ±15%`（[466,630]）带内。

**生成路由（`sim/mapgen.gd`）**：默认种子 20261003 → `_generate_default`（字节冻结，锚点/
指纹零漂移）；其余种子 salt 0..47 → `_generate_freeform`（新）；salt 48..63 →
`_generate_varied_legacy(seed, salt-48)` 兜底（原 G2 模板池，保留但不参与常规生成；
`FREEFORM_SALT_MAX=48`）。64 种子实测：兜底 0 次、盐峰 29、指纹 64 局互异。

**自由生成不变量**（`Scenario._check_freeform` 全量校验，失败换盐重采样）：
- 核心位：离边 ≥ `CORE_MARGIN 6`，净空半径 `CORE_CLEAR 5`；山头 = h3（hex 距 ≤2）+ h2(d3) + h1(d4)
- 主口 2~3 个：距核心环带 `MAIN_D 47..54`（直接锚定 466..630 路径带），彼此 ≥ `MAIN_GAP_MIN 14`，
  带 3×3 净空且 h0
- 盆地 6..9 × 7..9：四周单圈实心环 + **唯一** `COVER` 插口（棱中、距角 ≥2 格）、内部 12 格矿块、
  盆地口贴块心矿
- 中场矿 5 格；矿格共 17；岩野/微丘/散土由整数 fBm 三带（岩石占 60..220‰、微丘 20..160‰ 护栏、
  散土 `SPARSE_MIN/MAX 5..9`）落格：岩野格 `SOLID`、散土格 `COVER`、微丘格 h1
- 复算裸图流场双主口路径长落 [466,630]；盆地实心环 + 插口开门可达（`check_plug_open`）

**参数标定记录（本轮两处修正）**：
- 微丘噪声带 `[38000,45500] → [42000,47000]`（`MOUND_LO_T/HI_T`）：32 桶直方图质量积分定带
  （保留噪声质量 100%→66%），微丘中位 499→314 格（≈90‰，落 80~110‰ 目标带）；
  护栏 `MOUND_LO/HI_PERM 20/160` 余量充足。
- 插口避角 off-by-one：`next_int(bw-3/bh-3) → next_int(bw-4/bh-4)`（「距角 ≥2 格」设计口径落地）。

**读取面（波次路由）**：`Scenario.wave_cell(entry_index)`——双主口保持历史「出怪口 id−1」口径
（与旧图逐位同历史）；三主口按波次表序轮转 0..2（绝不落到盆地口）。`Scenario.basin_cell()` =
`spawns` 末位，插口挖开后盆地向其补漏兵（世界侧 trickle）。`World.run_waves` 走
`emit_wave_at(pos, ...)`；`emit_wave(spawn_idx, ...)` 保留为兼容壳（旧测试同路径）。
`fingerprint()` 新增 `_fingerprint_freeform` 分支（默认分支零改动，剧本指纹 `0x7dea2b02` 不变）；
样本种子 20261004 自由指纹 `0xf5f49e0c`（单测钉死）。

**存档与局号**：不升 `STATE_SCHEMA`（仍 6）——`save.decode` 的 `sc_fp` 校验自动拒绝「旧变幅
种子」的存档，默认种子存档照常可读。`run_index` 跨会话：`user://settings.cfg` 新增 `runs`
计数，`start_match()` 落盘；标题预烘焙局不计数；探针/selfcheck 经 `_detect_probe_run()` 门控，
不污染计数。视觉锚点：`main._visual_anchor()` 在无单一脊线（`ridge_y=-1`）时不再传 `ridge_y`；
`blueprint` 锚点读取全 `has()` 守卫（回落预设）。

**测试与探针（单测 104→106）**：
- `test_mapgen`：`64-seed-sweep` 重写为自由路径结构不变量（盐窗/核心留边/主口周缘/盆地尺寸/
  插口棱中/矿数 17/岩丘计数带/布局签名 ≥60 互异/三主口样本 ≥6；原 `determinism-fresh-vs-cache`
  假绿——自由图 `chokes` 为空使断言静默短路——重写为 spawns/插口/岩丘计数对拍）；新增
  `freeform-negative-controls` 7 条负对照（主口净空被填 / 岩群格被清 / 微丘降平 / 核心山头削平 /
  盆地环开洞 / 插口填实 / 死盆地不可达）。
- `test_scenario`：新增 `freeform-snapshot` 扁平快照（种子 20261004：盐 3 / 核心 (43,14) /
  英雄 (43,16) / 主口 (14,50)(3,41)(30,15) / 盆地 (27,11,9×8) / 插口 (35,15) / 中场矿 (41..45,21) /
  盆地矿 12 / 岩 217 / 丘 285 / 散土 9 / 路径 470·530 / 指纹 `0xf5f49e0c`）。
- `probe_scenario`：48 种子自由域全扫（77 checks：兜底 0 / 合法率 100% / 指纹互异 ≥46 /
  三主口 ≥3）+ `wave_cell`/`basin_cell` 解析段（双主口历史映射逐条、三主口轮转覆盖全主口）。
- 窗口探针三处「旧图/旧机」耦合断言修复（根因均非玩法回归）：`probe_asset` 覆盖层总数改
  数据驱动（= 当局 COVER 格数，旧硬编码 25 为默认图值）；`probe_audio._find_ore_cover` 改全域
  扫描（旧两矩形是默认图矿位）；`probe_input` 反向改高对改 h 感知选格（旧断言靠默认图北台地）
  + Q/E 旋转改墙钟 400ms 按住（本机 ~2000fps 下 10 帧仅数毫秒，帧计时阈值失效）。

**闸结果**：单测 106/0；无头 8 探针全绿（`probe_golden` PASS，16 指纹零漂移）；窗口 13 探针
全绿（sync 1845/0、input 58/0、hud 69/0、ui_flow 39/0、smoke 34/0、shots 6/0、audio 56/0、
asset 63/0、model 6/0、orient 1/0、save 74/0、touch 39/0、intro 36/0）；`check_shots` 29/0；
`check_ui_lint` 绿；`dotnet build` 0 警告 0 错误。冒烟局（run=1 seed 20261004）新值 =
`LOST tick=2902 kills=52 supply=422 peak_units=29`。全部截图重出 + store 实机五图副本刷新。
证据 `logs/gates-20261019-worldgen/`（含 64 种子 sweep 前后对照 `worldgen-sweep-64-{pre,post}.out`；
64 局全扫 ≈31s、最慢单种子 2.8s）。

**已知非致命**：`ui_style.gd:62` 在 4.7.2 下报引擎 ERROR「MenuButton 变体与内建类撞名」
（v2.2 遗留，主题仍构建成功、探针不受影响；待单独清理）。

**拍 2 待办（视觉联动）**：岩脊/山体/地标随自由布局生成（`_visual_anchor` 扩展）、三主口视觉门、
动机池与岩野/盆地形态联动；TapTap 常规 app 提审流水线（§11.22）以此为前置。

---

### 11.28 设置 v2：帧率上限 + 画面质量档（2026-10-18）

> **注（2026-10-19）**：本节的帧率候选（30/60/90）与画质档（低/中/高）已由 §11.29「设置 v3」扩展取代；
> 本节保留为演进记录。

**需求**：设置页可自选帧率（30/60/90）与画面质量。

**实现**：
- `user_settings.gd`：`settings.cfg` 增 `video/fps`（0 = 不限，30/60/90；默认 0 保现状）与
  `video/quality`（0 低 / 1 中 / 2 高；默认 2 保现状）；非法值回默认 / 夹取。新增纯函数
  `fps_cap()` / `quality_level()`（应用组合归 main，模块内仍不引用视图）。
- 限帧组合（`main._sync_fps_cap`）：对局态 = 玩家上限（0 → vsync 全速）；菜单/标题/结算 =
  `min(上限, 60)`（上限 0 → 60）——既有「只限菜单」口径保留，玩家设 30 时菜单同步降到 30。
  探针/自检运行恒用 0/60 口径（忽略玩家设置，保 gate 确定性）。
- 画质（`view_core.apply_quality` + `view.apply_quality` 转发）：`scaling_3d_scale`
  0.70 / 0.85 / 1.0；低档关直射阴影（`sun.shadow_enabled = level >= 1`）；低/中开 FXAA
  （`screen_space_aa`）。默认高档 = 原行为；探针运行不应用（保截图 gate 口径）。
- UI（`screens.gd`）：设置页新增两行互斥选项钮（`_option_row` = 88 宽标签 + 56×30 chips；
  选中走 `UiStyle.BTN_PRIMARY_VAR`、其余 `BTN_MENU_VAR`，零逐钮 override）；点选即落盘 +
  经 `fps_changed` / `quality_changed` 回调通知 main（main 同步 `_settings` 缓存并应用）。
- 回归（用户裁定本轮不新增专测）：`probe_save` 74/0、`probe_smoke` 34/0（限帧断言不变）、
  `check_ui_lint` PASS、5 改动文件 `--check-only` 全过。`shots/settings.png` 重出。

---

### 11.29 设置 v3：完整视频设置 + 平台默认（2026-10-19）

**需求**（用户裁定，替换 §11.28 的两行简版）：
- 显示：显示模式（全屏/无边框/窗口化，安卓隐藏）、分辨率（原生 + 列表；安卓隐藏，改由
  渲染缩放承担「渲染精度」）、垂直同步、帧率上限（30/60/120/无限制；安卓仅 30/60）。
- 画质：预设（低/中/高/极高）、阴影质量、特效质量、抗锯齿（关/FXAA/TAA；安卓仅关/FXAA）、
  后期处理、景深（默认关）。
- 性能：渲染缩放滑块（兼安卓「渲染精度」）、UI 缩放滑块、画面亮度滑块。
- 动态模糊按用户「可考虑移除」裁定**不做**（Godot 无内建实现）；动态分辨率本轮不单列
  （用户允许「开/关 或 滑块」二选一，取滑块；安卓默认 85% 渲染保流畅）。

**数据层**（`user_settings.gd`）：
- `video/` 键：display_mode（0 窗口化 / 1 无边框 / 2 全屏）、res_idx（0 原生 = 桌面可用区，
  1..4 = 2560×1440 / 1920×1080 / 1600×900 / 1280×720；默认 4 保现状）、vsync、
  fps（0/30/60/120）、quality（0..3）、shadow_q / fx_q / post_q（0..2）、aa（0/1/2）、
  dof、render_pct（50..100）、ui_pct（80..130）、bright_pct（70..130）；`progress/runs` 不变。
- 旧档兼容：`video/fullscreen=true` → display_mode 2；v2 只有 `quality` 时，v3 子项按该预设补齐
  （低/高/极高实测一致，避免「预设档与子项错配」），其余缺失键回平台默认。
- **平台默认**：PC = 高画质（阴影/特效/后期高，渲染 100%，不限帧）；安卓 = 中画质
  （阴影/特效/后期中，渲染 85%，60 帧）——移动端优先流畅/续航（对齐用户平台建议）。
  安卓 Mobile 渲染器无 TAA → `aa_opts()` 仅关/FXAA，`aa_level()` 把 2 回退 1（读档/写盘/预设
  三处统一合法化）。
- `QUALITY_PRESETS`：低（阴影低/特效低/AA 关/后期低/缩放 70）、中（中/中/FXAA/中/85）、
  高（高/高/FXAA/高/100）、极高（高/高/TAA/高/100）——预设只写画质子项，不碰显示/帧率/UI。
- `apply_video`（OS 层）：PC 应用显示模式（borderless flag + window mode）与窗口尺寸
  （窗口化/无边框；全屏交桌面），改尺寸后居中到可用区；垂直同步两平台应用；安卓（恒全屏）
  跳过显示模式/分辨率。`fps_cap()` 平台合法化（安卓 0/120 → 60）。

**表现层**：
- `view_core.apply_video(cfg)`：`scaling_3d_scale = render_pct/100`；AA（FXAA / `use_taa`）；
  阴影质量 = 2/4 分裂 + 最大距离 45/80/100；后期处理 = **雾距相对当前地图视觉基准**的倍率
  （低 1.6× / 中 1.25× / 高 1.0×）——基准由 `view_terrain` 应用调色板时经 `set_fog_base`
  写入（worldgen 拍 2 每图雾距 50..62 / 195..260 不被覆盖；默认档实测像素零差）；
  亮度 = `Environment.adjustment_*`（100% 关闭）；景深 = `CameraAttributesPractical`
  远场轻虚化（far 80 / transition 60 / amount 0.06，默认关）。
- `view_entities`：特效质量 = 死亡消散时长（高 28 tick 原口径 / 中 14 / 低 1）。
- 探针/自检运行（`main._is_probe_run`）只应用音频；显示/画质/UI 缩放一律不应用，保 gate 口径。

**UI**（`screens.gd`）：
- 设置页四组（音频/显示/画质/性能）+ `ScrollContainer`（纵向滚动；金黑滚动条走
  `UiStyle.scrollbar` 工厂，L2 合规）；chips 58×38（≥ probe_touch 触达矩阵下限），行左对齐；
  命名 `btn_<key>_<值>` / `sld_<key>` / `lbl_<key>_val`。
- 改值统一出口 `_commit_video`：落盘 → `video_changed` → main 同步缓存 + `apply_video`（OS）
  + `view.apply_video`（画质）；UI 缩放走 `ui_changed` → HUD 立即 `_layout`，界面页标记脏、
  离开设置页/回对局时按新 S 重建（拖动中不自毁）。
- 平台差异：安卓隐藏显示模式/分辨率行；帧率仅 30/60；抗锯齿仅关/FXAA。

**平台适配核对（对齐用户 2026-10-19 建议）**：
- 渲染器：`project.godot` 无显式覆盖 → Godot 4 默认 desktop Forward+ / Android Mobile。
- 纹理压缩：Windows 预设 S3TC/BPTC；Android 预设显式 `texture_format/s3tc_bptc=false` +
  `etc2_astc=true`（导入侧双变体 `.s3tc.ctex` / `.etc2.ctex`，导出各取一份；APK 实测 4 个
  `.etc2` 地形贴图 + 32 个 lossless，0 个 `.s3tc`）。
- ABI（2026-10-20 复核）：Godot C#/.NET Android 导出不支持 armeabi-v7a（仅 arm64-v8a +
  x86_64），最终包保持双 ABI（约 312MB），不做裁剪；minSdk 24 / targetSdk 36。
- 输入：触屏经引擎 `emulate_mouse_from_touch` 走同一套鼠标事件（§11.9，probe_touch 覆盖）；
  安全区（刘海/手势条）与 UI 缩放已接入。
- PC 分辨率：窗口列表含 1920×1080 / 2560×1440 / 原生；UI 随视口高度 S 自适应（1.0..1.6）；
  截图覆盖 20:9（1600×720）/ 4:3（960×720 窄屏 + 1600×1200 平板）/ 16:10（1280×800）。
- 未做（明确留档）：动态分辨率（需真机调参，避免画面脉动）、PC 悬停提示/快捷键、
  纹理单格式/降采样（保兼容面与画质）、真机中低端机实测（用户侧）。

**回归**：`probe_save` 77/0（显示模式 chips 替代全屏开关 + 三项默认滑块断言）、
`probe_touch` 71/0（按钮矩阵 54）、`probe_smoke` 34/0、`probe_hud` 73/0、
`probe_ui_flow` 39/0、`probe_sync` 1845/0、`probe_scene` 25/0、`probe_shots` 6/0、
`check_shots` 29/0、单测 107/0、`check_ui_lint` PASS、改动文件 `--check-only` 全过；
`probe_input` 首跑 1 条既有机器相关抖动、复跑 58/0 PASS。临时接线/目视脚本（预设模板、
TAA/DOF/亮度、UI 缩放重建、默认档像素零差）验证后删除。`shots/settings.png` 重出。
证据 `logs/gates-20261019-settings3/`。

### 11.30 UI v2.3「独立化」：色板归位 + HUD 变体化 + 拾取探针重标定（2026-10-20）

**动机**：v2.2 后 UI 子系统仍有两处「半独立」——色板真源在 `hud.gd`（壳层 screens 反向依赖
hud 取色）；HUD 10 钮仍走 override + `sb_normal` meta 的发射器 b（改样式要双写）。本轮收编，
并顺带清掉两颗雷：变体名撞内置类（每次启动喷 ERROR）、`probe_input` 机器相关假红。

**改动**：
- 色板：`DARK`（21 key）迁入 `game/ui_style.gd` 唯一真源；`hud.DARK` 保留
  `const DARK := UiStyle.DARK` 兼容别名（探针/历史引用按 key 取色零改）；`screens.gd` 改
  `C = UiStyle.DARK`（壳层不再依赖 hud 取色）。`hud.build_stats` 仍在 hud（数据格式化，非样式）。
- HUD 变体：`ui_style` 新增 `hud_button_states(C, active)` → `HudButton`/`HudButtonActive`
  两组变体（字色三态口径沿 v2.1 运行时实况：同色 text/on_gold，悬停不走亮金）；
  `hud._style_button` 只设尺寸/字号 + `theme_type_variation` + A1 光边；
  `set_mode`/`set_heat_vis` 改一行变体切换；**`sb_normal` meta 机制与逐钮四态 override 退役**
  （探针改读 `get_theme_stylebox("normal")` effective 解析）。
- 变体名避让内置类：`BTN_MENU_VAR` 值 `"MenuButton"` → `"UiMenuButton"`——4.7.2 禁止
  `set_type_variation` 用内置类名（每次 build_theme 喷
  `A type associated with a built-in class cannot be marked as a variation…`；样式因同名 type
  条目仍生效，属隐性雷）。
- `probe_input` §14.5 重标定（旧口径「任意位姿下 (24,24) 回拾」不稳）：
  - 根因：W/D 按帧、Q/E 按墙钟、拖拽按像素 → §14 后相机位姿随帧率漂移；且 `pick_cell` 是
    2 迭代高度面收敛（非真射线），相邻格高差大时会**合法**收敛到邻格（实测 (24,24) 顶高
    1.34、回拾 (23,23)；§11.29 已有「首跑抖动、复跑过」记录）。
  - 新口径：钉扎 focus=格心 / yaw=0 / zoom=1；扫「自身与 6 邻高度差 ≤0.10」的平坦格群
    （= 2 迭代精确收敛域，扫区 22..41 全量 **199/199** 实证），取 6 个不同行格断言点击回环。
  - 附带排雷：钉扎需 ~14 帧，若继续推进 tick（TICK_DT=1/20）对局会在 §15 前走到 gameover
    （`_camera_free()` 拦滚轮 → §15 假红，已实测复现）；§14 尾 `main.set_process(false)`
    冻结主循环（相机/滚轮均不经 _process，§15 断言不受影响）。
- `selfcheck` 31→33：+2 条 HUD 变体断言；顺带校正 `covers` 25→27（拍 2 视觉联动后实测值，
  HEAD 断言未同步，属既有红，非冻结项）。
- 文档：UI-REDESIGN §8 + 锁定表行更新；AGENTS 台账。

**回归**（全 22 闸 + 附加，证据 `logs/gates-20261020-v23/`）：unit 107/0、golden 2/0、
scene 25/0、blueprint 21/0、sim 5/0、grid 40/0、flow 53/0、scenario 77/0（fp 0x7dea2b02 未漂）、
world 20/0；sync 1845/0、input **65/0**（58→65：旧 1 条回拾断言 → 平坦格群检查 + 6 格回环 +
计数检查；连跑两次稳定）、hud 73/0、ui_flow 39/0、touch 71/0、save 77/0、smoke 34/0、shots 8/0、
audio 56/0、asset 63/0、model 6/0、orient 1/0、intro 36/0；selfcheck **33/0**（`--selfcheck`）、
check_shots **39/0**、check_ui_lint PASS。受击截图全量重出（顺带刷新 gameover/slots 等早于
v2.2 的存量陈旧件；目验 gameover/hud/slots 通过）。

**遗留**：页流不加 facade（`main → screens` 具名方法集已是唯一调用面，加壳徒增）；`.tscn`
场景化留赛后。

### 11.31 TapTap 常规 app 提审执行 + 活动投稿材料（2026-10-19 ~ 10-20）

**app 载体**：新建常规 app **986470**（开发者 434158），版本 **V-20261019**
（`revision/audit_id = 1106016`）。旧 app `958251` 保持未发布不动（spark-only，见 §11.22）。

**包体（已上传并绑定）**：Android `reroute-release.apk`（312,119,839B，包体 id `1066768`，主包）
+ Windows `reroute-windows.zip`（183,669,125B，包体 id `20242`，`branch=1`，入口 `game.exe`）。

**合规（按群公告硬要求）**：
- Android：`apk_anti_addiction_status=not-integrated` + `apk_sandbox_authorized=true`（TapPlay 接入）；
  「游戏包体 → 免安装」显示**已授权**。
- APK 隐私资质：资质认证 →「隐私政策与隐私检测」→ 配置方式选
  **「免安装，使用平台托管」**（= TapPlay + 通用隐私协议，无需自填链接）→ 提交审核，
  状态由「待上传」变「审核中」。
- Windows：`pc_game_anti_addiction_status=1`（未接入防沉迷，使用 Tap 通用防沉迷系统）。

**平台与分发**：`MOBILE` + `PC_OFFICIAL`；`region_flag_android=region_flag_pc=4`（开放试玩）。

**商店资料**：图标（替换默认）、`banner_4`（含「改道」标题）、5 张截图、Windows logo/横版封面/
竖版封面/游戏库壁纸、简介/推荐语/开发者的话、双端更新日志、Windows 最低配置。

**审核**：`precheck-app-review` 0 阻塞 0 警告（`preaudit_passed=true`，`release_schedule=immediate`）
→ 提审 `audit_id 1106016`，`status=reviewing`（10-20 01:40 复核仍未变）。
入口：`https://developer.taptap.cn/v3/434158/app/986470/store/update`。

**投稿材料（活动页 `https://www.taptap.cn/poster/NIKiDS1YShdA`）**：
- 实机视频：`export/reroute-gameplay-demo.mp4`（39.77s / 1280×720 / 60fps，核心存活 HP 268；
  videoId `5990199`）。
- 讲解视频：`export/reroute-explainer-70s.mp4`（70.57s / 1280×720 / 30fps；edge-tts
  `zh-CN-YunxiNeural` 旁白 + 烧录字幕 + 实机/截图；构建脚本
  `%TEMP%\opencode\build_explainer.py` + `rebuild_subs.py`，产物在 `%TEMP%\opencode\vidwork\`）。
- 活动页当前显示「当前投稿状态：未投稿」，需商店审核通过后点「前往投稿」完成。

**开发者日志（≥5 篇，已达成）**：① 10-15 → ② 10-16 → ③ 10-17（`860546275211218896`）
→ ④ 10-19（`861382976393448456`）→ ⑤ 10-20（`861415324296154627`，版块「综合讨论」）。
规则原文（活动海报）：「开发期内累计在 TapTap 发布 5 篇及以上开发者日志……非灌水内容」。
事故记录：10-20 凌晨误将 04 重发一帖（`861401811414680462`，灌水区），已用帖子
「更多 → 删除」清理（现 404），04 原帖未受影响。

**风险与遗留**：① 审核时长不可控，活动投稿必须等过审（官方口径「审核通过才算有效投稿」）；
② 提审包为 10-18 版，世界生成 2.0（§11.27）未含，留作上线后更新；
③ 试玩量（≥50，去水）在 **10-25 ~ 12-3** 全民试玩/评审期内统计，非提审前置。

**10-20 凌晨复核（重要修正）**：
- 隐私资质首次提交被**驳回**——「隐私政策链接请勿为 TapTap 站内页面，请更换为独立网页链接」；
  「免安装，使用平台托管」生成的是 `https://www.taptap.cn/app/986470/common-privacy`（站内页）。
  已建独立托管页：仓库 `LLL-404/reroute-privacy`（GitHub Pages，公开）→
  **`https://lll-404.github.io/reroute-privacy/privacy.html`**；资质页改选**「自行配置」**填入该链接，
  已重新提交 → **审核中**。
- 上架资质（与版本审核相互独立）共 5 项，当前 **1/5**，状态「不满足上架条件」：
  - `AI接入声明` 待上传：开关「是否接入了生成式AI」→ ON 后需上传「AI 合成声明证明截图」
    （仅当游戏内提供 AI 生成合成服务时适用；本作仅在开发期使用 AI 资产，需判断口径）。
  - `游戏适龄分级` 待上传：8+/12+/16+ 单选。
  - `隐私政策与隐私检测` 审核中（见上）。
  - `防沉迷合规` 待上传：需「2021.9.1 防沉迷新规接入证明」录屏（MP4 ≤2min ≤100MB）
    + 「中宣部网络游戏防沉迷实名认证系统」截图（JPG/PNG ≤5MB）；本作走 TapTap 平台托管，
    录屏需真机 + 未成年账号演示。
- 版本页「必填完成度 **20/21**，差 1 项」= **游戏包体** 组：Windows 配置的
  「最低配置 / 推荐配置 → 操作系统」两处为空（显示「请选择 Windows 系统版本」）；
  包体绑定本身正常（`list-packages`：main=1066768、windows=20242，revision 1106016）。
- 版本状态仍 **审核中**（audit 1106016），发布设置「过审后立即发布」。

**10-20 凌晨复核（二）：找到真正投稿入口（此前判断有误）**
- 官方规则原文写的是：作品须在 10-21 12:00 前上传，并在 **「开发者中心 - 平台活动」** 中完成投稿。
  即投稿入口 **不在** `www.taptap.cn/poster/...`（那只是活动落地页），而在
  `https://developer.taptap.cn/v3/434158/activity-center`（左侧「运营 → 平台活动」）。
- 「我的活动」表格中该活动行：**投稿截止 2026-10-21 12:00**，当前 `未选择游戏 / 未投稿`
  → 点「投稿」进入 `…/activity-center/13/sign-up`：左侧勾选游戏（厂商下有两个同名「改道」，
  需选 **986470**），右侧「填写资料」弹表单。
- 投稿问卷仅 **5 个文字字段**（无视频/图片上传；视频五图走商店页）：
  1. `你的 QQ 号` *（队长 QQ）
  2. `再次确认是否为学生团队` *（是/否）
  3. `如为学生团队请上传在线文档链接，不是请填无` *
  4. `素材声明在线文档链接（包含 AI 美术和第三方素材）` *
  5. `开发日志 TapTap 站内链接` *（**5 篇用逗号隔开**，是瓜分「全程参与奖」与参评
     「最佳社区运营」的必备条件）
  底部：`保存草稿并返回` / `提交投稿`；页内提示「修改并重新提交后需要再次审核」。
- 报名记录（`get-records?...&scene=1`，id 13851，报名于 09-23）已存在，含：
  手机 `15864488375` / **QQ `2350178663`** / 邮箱 `15864488375@163.com` /
  学校「枣庄学院」/ `是否使用 TapTap 制造 = 是` / `是否为学生团队 = 否`
  （10-20 复核二次精确核对码位：U+5426=否；系原文「= 是」为笔误）。
  → 投稿第 1 栏可直接用 `2350178663`。
- 已补独立「素材使用声明」在线文档（GitHub Pages）：
  **`https://lll-404.github.io/reroute-privacy/assets-declaration.html`**（已 200 可访问），
  内容 = `cashline/docs/AI-ASSETS-public.md`（已核对与 Godot 工程实测一致：
  14 glb / 30 mp3 / 4 张 CC0 纹理 / 字体 2）。→ 用于第 4 栏。
- 5 篇开发日志站内链接（第 5 栏用）：
  ① `https://www.taptap.cn/moment/859900396141808195`
  ② `https://www.taptap.cn/moment/860212304162064981`
  ③ `https://www.taptap.cn/moment/860546275211218896`
  ④ `https://www.taptap.cn/moment/861382976393448456`
  ⑤ `https://www.taptap.cn/moment/861415324296154627`
- 仍未决：第 2/3 栏（学生团队口径）需用户拍板；商店「游戏介绍」按活动规则**必须**声明
  「本游戏内含有使用 AI 生成的游戏资产」，改动商店页是否触发重新审核待定。

**10-20 凌晨（三）：活动投稿已提交（首投被急驳，属预期）** ← 本节为 10-20 03:30 补记
- 已按上述入口完成 **投稿提交**：记录 id **19287**（app 986470），5 项齐（QQ 2350178663 /
  学生团队=否（按报名原值）/ 学生文档=无 / 素材声明链接 / 5 篇日志，逗号分隔）；
  提交后**即时驳回**，理由「游戏尚未审核发布或已下架，请完成审核并开放试玩」。
  唯一阻断 = 商店版本 V-20261019 仍在审核中。重投入口：活动中心该行「编辑投稿」
  （或 `…/activity-center/13/sign-up`，表单已存 5/5，点「提交」即重投）。
- 素材声明（第 4 栏）实际提交 = gist
  `https://gist.github.com/LLL-404/4e58096ec730f2a8dd95289aa99a5106`；已补
  「**〇、AI 素材占比（速览）**」章节（规则要求「使用比例 + 具体内容」）；
  同步更新 GitHub Pages `assets-declaration.html`（reroute-privacy commit `403f446`），
  并新发 **TapTap 站内动态备份** `https://www.taptap.cn/moment/861445870371995916`
  （大陆可达性更稳；如换链接 → 编辑投稿替换字段后重提）。docx/纯文本同源更新（cashline/docs）。
- **自动监控 + 自动重投已配置并运行**：`reroute-godot/logs/submit-20261020/tools/auto_resubmit.py`
  —— 每 5 分钟查 `list-app-versions`；一旦 `reviewing` → 上线，自动无头打开投稿页点「提交」，
  日志 `logs/submit-20261020/auto/auto_resubmit.log`，截图 `activity/05-auto-resubmit.png`；
  含「记录已无驳回则跳过」防重护栏；过 10-21 11:30 自动退出。全部证据见
  `logs/submit-20261020/README.md`。
- 后续（过审后按序）：
  ① 重投确认通过（记录变为审核中/通过）；
  ② 商店资料写回：**状态机 1/3/4/5 全锁**（官方 skill 文档已核实），已上线后须先
  `create-draft` → `save-changes`（简介补「本游戏内含有使用 AI 生成的游戏资产（…）」
  ——规则硬性，否则放弃所有评奖；+ trailer 5991203 / gameplay_demo_video 5991204）
  → `submit-app-review`（immediate）；payload `%TEMP%\opencode\save_videos.json`。
  若活动记录因 app 回审核中被刷新为未通过 → 立即 `withdraw-app-review` 回退。
- 全程参与奖（海报原文核实）四项条件：① 按时有效投稿（通过平台审核）② 完整展示核心玩法
  ③ ≥5 篇日志（**已达成**）④ **10-25~12-03 试玩评审期有效试玩 ≥50 人**（评审期指标，
  截止前无需完成，需提前准备社区推广）。海报正文未对投稿视频设硬性要求（视频为商店素材加分项）。

---

### 11.32 双端发布包重出（v2.3，2026-10-20 08:04~08:16）

**口径**：沿 §11.26（Windows zip 192 条目 = `game.exe` + `game.pck` + `运行说明.txt` +
`data_RerouteGodot_windows_x86_64/`（189 文件），不含 `.idsig`；Android 双 ABI + ETC2）。
本轮为 UI v2.3 + 世界生成拍 2 视觉联动后首次全量重出。

| 产物 | 字节 | SHA-256 |
|---|---|---|
| `export/game.exe` | 109,551,432 | `0539d11b…85bc`（签名后与 v2.2/10-18 包逐字节同哈希，第四次实证 exe=内容无关模板件） |
| `export/game.pck` | 109,831,652 | `88158f75…db96` |
| `export/reroute-windows.zip` | 183,719,469 | `f7854e80…5c59` |
| `export/reroute-release.apk` | 312,152,675 | `07860536…fcc6` |

**验证**：

- exe 复签 `SIGNED=Valid`（CN=Reroute 自签；本机 SAC 拦截未签名 exe，见 §11.12）。
- 包内自证：`export/game.exe --selfcheck`（exe+pck 同目录）→ **33/0 PASS**（含 v2.3 新增
  2 条 HUD 变体断言）；10-18 旧包日志中的 `MenuButton` 变体 ERROR 已消失。
- zip：192 条目、`testzip None`；APK：`apksigner verify` v2/v3=true、CN=Reroute、
  整包 `testzip None`（722 条目，`assets/assets.sparsepck`）。
- 证据：`logs/gates-20261020-v23/export-{win,apk}.out`、`export-selfcheck.{out,err}`。
- **注记（APK 导出退出码）**：导出本身完成（日志 `[ DONE ] export` + `Signed` + 校验），
  但 Godot 进程在 MCP 插件关闭后未自行退出 → 人工终止，包装层记 `exit=-1`；产物完整性由
  apksigner 验签 + 全条目 CRC 复核（不作为失败判据）。
- `export/` 不入 git（含他会话视频素材），包体仅本机交付。

---

### 11.33 UI v2.4「指挥坞 + 三屏修缮」（2026-10-20）

**缘起**：v2.3 只完成样式独立化，实机仍呈「调试按钮列 + 菜单裁切」；本轮按
「HUD → 标题/设置/存档」顺序做一轮可用性与层次改造，不改模拟/指纹。

**HUD（game/hud.gd）**：

- 右下 8 钮改**指挥坞**：分组标题（建造 / 地形 / 指令）+ 暗底细边面板 + 顶部 2px 光边
  （A1 `edge_dress`）；行内 = 名称左对齐 + 成本右对齐（`row_name`/`row_cost` 子 Label，
  Button 文本清空，避免逐钮样式盒 override）；成本供给不足转 `danger` 红，点亮行成本转
  `on_gold`；技能行右侧显示剩余秒（`20s`），就绪留空。
- 几何：`BTN_H` 42→38、`COL_W` 128→176、坞 200×426（12 内边距 / 17 标题行 / 1 行距 /
  7 组距），点击排除 `CORNER_W/H` 216×442；缩放时行尺寸与子标签随 `_layout()` 重算。
- 顶栏：核心血条 200×12、正文 11/12；供给拆「供给」10 小标 + 17 大数值（`supply_text`
  现在只存数值，探针同步）；热层/暂停 60×30。
- 教学提示条：10px 瘦身；`HINT_LIFE=400` tick（20s）后 0.5s 淡出并隐藏（只触发一次），
  进入存档/设置模态页调用 `dismiss_hint()`；`hit_regions()` 只在可见时追加提示区（隐藏后
  该区域交还战场）。
- 波次横幅：16/10 字号、内边距 7、下移至 y+96，不再压住场地中心。

**三屏（game/screens.gd）**：

- 设置：滚动区外套 Control（视口 68%）+ `UiStyle.fade_tex` 底缘渐隐（可滚动暗示）；
  滚动区与「返回」之间加 1px 金线，返回不再像压在内容上。
- 存档：删除钮位固定 62px（删除钮与同宽占位块互斥显隐），空槽/读档/存档三种状态槽条
  左缘恒定对齐；save 模式仍隐藏删除钮（探针口径不变）。
- 标题：菜单列 240→264、标题 54→56，页脚/标语位置随列宽外移 24。
- `UiStyle.fade_tex(bottom, height)` 新增（L1/L2 lint 合规：色 token 与 Gradient 构造仍只在
  `ui_style.gd`）。

**回归（logs/gates-20261020-v24/）**：全 22 闸绿 —— unit 107/0、golden 2/0、scene 25/0、
blueprint 21/0、sim 5/0、grid 40/0、flow 53/0、scenario 77/0（fp `0x7dea2b02`）、world 20/0、
sync 1845/0、input 65/0、**hud 82/0**（+9：坞面板 / 成本可负担性 / 提示淡出 / 浮字钳顶 / 区域新口径）、
ui_flow 39/0、save 77/0、touch 71/0、smoke 34/0、shots 8/0、audio 56/0、asset 63/0、
model 6/0、orient 1/0、intro 36/0；selfcheck 33/0；check_shots 39/0；lint PASS。
探针截图全量重出（hud / game 六尺寸 / heat / ghost / title / settings / slots / gameover 等）。

**未打包**：四件包仍为 §11.32 的 v2.3 内容；若需交付 v2.4，按 §11.26 口径重出四件。
（→ **已打包，见 §11.34**。）

---

### 11.34 隐私政策首启门 + 过审上线 + 活动投稿通过（2026-10-20 14:17 ~ 10-21 00:43）

#### 缘起：隐私合规检测的真实根因

10-20 11:26 版本 V-20261019 审核驳回，理由「**安装包隐私合规检测未通过**」，
消息中心**无报告**（通知原文仅写「如未收到报告可通过工单咨询」）。

排查过程（**两条错误猜测，留档避免重犯**）：

| 猜测 | 证伪方式 | 结论 |
|---|---|---|
| APK 声明了 `android.permission.DUMP` | `aapt2 dump xmltree` 显示**无任何 `uses-permission` 节点**（零权限）。此前用 Python 按 UTF-16 解码二进制 AXML 再正则匹配，命中的只是 **string pool 残留字符串**，不是真声明 | ✗ 假线索 |
| `<profileable shell=true>` 是风险项 | 解包 Godot 官方 `4.7.2.stable.mono/android_release.apk`，**模板同样带 profileable** | ✗ 模板自带，非本项目引入 |

**决定性证据**：直调 `GET /api/app/v1/pc-game/list-packages` 发现 **Windows 包体 20242 的
`reject_reason` 与 APK 的 `status_reason` 一字不差**。Windows 包只有 exe+pck+txt，
同样被判不过 ⇒ **不是包体技术问题，是游戏内容/行为层问题**。

⇒ 正解：**游戏首启没有隐私政策弹窗与同意流程**（国内隐私合规检测头号必查项，Godot 默认不提供）。

#### 实现：`game/privacy_gate.gd`

- CanvasLayer `layer=40`（高于开屏 30 / 壳 20 / HUD 10）；全屏暗底 + 居中卡片
  （宽度 `clamp(视口宽×0.86, 320, 560)`），金色标题「隐私政策」
- 正文四段：**收集信息**（不收集、不上传，设置/存档仅本机）/ **第三方服务**（无统计/广告/登录/支付 SDK）/
  **权限说明**（不需要通讯录、位置、相机、麦克风、存储读写）/ **你的权利**（设置页可随时查，卸载即删）
- 三按钮：`btn_privacy_link`（`OS.shell_open` 跳独立网页）/ `btn_privacy_agree`（金色主钮）/
  `btn_privacy_decline`（不同意，退出）
- 信号 `agreed` / `declined`；**拒绝 Android 返回键关闭**（必须显式二选一）
- 完整政策：`https://lll-404.github.io/reroute-privacy/privacy.html`（GitHub Pages，独立页非站内页）

**`main.gd` 接线（关键合规口径）**：

```
_ready():
  view = $View
  _is_probe_run = _detect_probe_run()
  _settings = UserSettings.load_cfg()
  if not _is_probe_run and not _settings.privacy_agreed:
      UserSettings.apply_video(_settings)   # 先摆正窗口，否则小窗把卡片压到最小宽
      _show_privacy_gate(); return          # ← 不建 HUD/壳、不开局、不播开屏、不写盘
  _boot()                                   # 原 _ready 主体
```

- 同意 → `privacy_agreed=true` 落盘 → `_boot()`；不同意 → `get_tree().quit(0)`
- 探针 / selfcheck / headless 一律跳过，**保 22 闸与 selfcheck 口径不变**

**`user_settings.gd`**：`privacy_agreed` 三处（`default_cfg` / `load_cfg` / `save_cfg`）。
⚠️ `save_cfg` 会重写整个 ConfigFile，**必须像 `runs` 一样从旧档读 `prev_agreed` 兜底**，
否则设置页一保存就把同意状态冲成 false。

**`screens.gd`**：设置页末尾加「关于」分组 + 「隐私政策 / 查看完整说明」按钮（`btn_privacy_policy`），
常量 `PRIVACY_URL` 置顶。

#### 验收

| 项 | 结果 |
|---|---|
| 新探针 `tests/probes/probe_privacy.gd` | **`[PRIVACY] checks=9 bad=0 PASS`**（三按钮 + 标题正文 + 同意/拒绝两条信号链路） |
| 既有 selfcheck | **`checks=33 bad=0 PASS`**（未破坏） |
| 画面 | 窗口模式实拍确认渲染正常（`%TEMP%\opencode\privacy_shot.png`） |
| 端到端 | **10-21 00:14 版本 `online`/已上线** ⇒ 隐私检测通过 |

#### 顺手修的编译阻塞缺陷

`game/view_terrain.gd:498` 引用 **`ROCK_GATE_KEEP` 但从未定义**（并行会话未提交的半成品），
导致 `view.gd` 整体编译失败、`entities/terrain` 全 nil、selfcheck 崩在 header。
补 `const ROCK_GATE_KEEP := 1.4`（出怪口保留半径，米；`_gate_pts` 存世界坐标，1 格 = 1 米）。

#### 双端包重出（含隐私门，口径同 §11.26）

| 产物 | 字节 | 校验 |
|---|---|---|
| `export/reroute-release.apk` | 312,181,643 | `apksigner` → `CN=Reroute`，SHA-256 `06fb8144…4F0E3F`（与线上一致） |
| `export/game.exe` | 109,550,080 | `tools/sign_windows_exe.ps1` 复签 → `SIGNED=Valid` |
| `export/game.pck` | 109,859,040 | — |
| `export/reroute-windows.zip` | 181,524,583 | 192 条目（exe + pck + 运行说明.txt + data 189） |

⚠️ **签名机制（踩过一次，必记）**：`export_presets.cfg` 的 `keystore/*` **六字段全空**，
签名靠**环境变量注入** `GODOT_ANDROID_KEYSTORE_RELEASE_PATH` / `_USER` / `_PASSWORD`
（keystore `D:/G/game/keystores/reroute-release.keystore`，alias `reroute`；
密码台账 `signing.env` 同目录，仓外）。**不设环境变量直接 `--export-release` 会用 debug keystore
签成 `CN=Android Debug`**，与线上包签名不一致 → 必被拒。单次导出 ~10 分钟，勿按短超时判失败。

#### 包体绑定：Windows「默认包」不可绑（本次最大坑）

包体库卡片有两种标签，**只有前者能绑**：

| 标签 | 能否绑定 |
|---|---|
| **游戏本体包** | 能 |
| **默认包** | **不能**——卡片连选中态都没有，「确认选择」是灰的 |

试过且**全部失败**：CLI `select-package`（branch 0/1 都报「不在可选列表」）、
UI 卡片坐标点 / JS 派发 / 文字点击、`clear-package` 清空槽位后重绑。

**管用路径（已验证）**：从「包体库」对话框内的**「上传新包体」**上传
（不是页面上的「上传包体」），且**必须手填「版本设置」三个框**——库内入口不自动带版本号，
不填则保存恒灰（提示「请先完善包体配置」）。⚠️ antd 是受控组件，**JS 改 `input.value`
+ 派发 input/change 无效**，必须用 Playwright `fill()`。填完保存，包体**自动绑到 windows 槽位**。

APK 侧则直接用 `select-package`（`{"slot":"main","package":{"id":"<新apk>","type":"apk"}}`）即可。

**最终绑定**：`main` = **1067414**（新 APK）/ `windows` = **21249**（新 zip 1.3.0）。

#### 过审与投稿

- `submit-app-review`（`release_schedule=immediate`）→ `review_submission accepted`
  → 状态 `reviewing` → **10-21 00:14 `online`/已上线**
- 活动投稿（记录 19287）重投：**自动脚本失败** —— `auto_resubmit.py` 用的
  `PROFILE = wb-ff-taptap5` **登录态已过期**，被重定向到手机号登录页（页面仅 73 字符），
  读不到「已填 5/5」而中止。**换 `wb-ff-taptap4`（developer 域登录态有效）手动重投**
  → sign-up 页显示「已填 5/5」→ 勾选第一个「改道」（绿色图标 = 已上线 = 986470）→ 提交
  → 活动列表「关注的活动」显示 **「已通过」**。
- ⚠️ **profile 分工记死**：`wb-ff-taptap4` 用于全部后台操作（提审/投稿/包体）；
  `wb-ff-taptap5` 已失效，勿再用。

#### 结论

**全程参与奖四项硬条件全部满足**：按时有效投稿（已通过）✓ / 完整展示核心玩法 ✓ /
≥5 篇开发者日志（①10-15 ②10-16 ③10-17 ④10-19 ⑤10-20）✓ / 试玩量 ≥50 属
10-25~12-03 评审期指标，非截止前要求。

---

### 11.35 UI v2.5「图标指挥盘 + 三屏翻新」+ 撤销 pill 落地（2026-10-20 晚 ~ 10-21）

#### 缘起与范围口径

用户对 v2.4 界面直接反馈「**界面差，推倒重来**」。重做方向 = **图标指挥盘 HUD + 三屏/模态
全面翻新**（铜金黑曜石色板延续、去盒化、游戏感）。**范围口径（用户 10-21 明示）**：项目并行
做两个模式（肉鸽 + 主要模式），**本轮 UI 全部只作用于主要模式**——肉鸽模式（他会话的
`btn_rogue` 入口起）不在本轮 UI 翻新面内。

另：他会话于 10-21 早做**保护性提交** `936c175`「wip: UI v2.5 图标指挥盘 + B2 岩块散布」，
把本轮 wip 与其并行工作一并入库（提交标注「窗口闸未跑」）；本轮补齐证据链。

#### HUD v2.5：图标指挥盘（game/hud.gd）

- 右下 **3 行 2/3/3 图标格**：建造（墙/塔）→ 地形（挖矿/填高/挖低）→ 指令（震荡波/拆/英雄）。
  格 `CELL_W=72 × CELL_H=68`、图标 24、`CELL_GAP=8 / ROW_GAP=10 / DOCK_PAD=10`，
  几何常量 `DOCK_W=252 / DOCK_H=244`，点击排除角块 `CORNER_W=268 / CORNER_H=260`
  （坞面 + 16 邻边节）。Button `text=""`，每格三子节点：
  `row_icon`（UiIcon 代码绘制图标：wall=砖纹重画、skill=中心圆+8 向爆发射线、其余语义形）
  + `row_name`（名称 11pt=`FS_NAME`）+ `row_cost`（成本 9.5pt=`FS_COST`）。
- **字号/几何随 S 全量重算**（v2.5 主命题：平板「大格子小字」根修）：`_layout()` 内
  逐控件重设 `font_size/int(FS*S)` 与位置——顶栏、指挥盘、提示条、横幅全部覆盖；
  窗口缩放后不再只挪位置。
- 顶栏：加**盾/铜钱**小图标（`supply_icon`/`core_icon`），供给数值 18pt 拆小标+大数。
- 提示条：金色「**TIP**」小字标 + 1px 金分隔线（`HINT_LIFE=400` 淡出口径不变）。
- 命中排除区：`hit_regions()` 仍是三块（顶栏条 / CORNER 角块 / 可见提示条），
  v2.5 几何换算只改尺寸不改来源。

#### 三屏/模态翻新（game/screens.gd）

| 页 | 改法 |
|---|---|
| 标题 | **去盒化菜单行** `_menu_row`：序号 01-05 + 1px 下划线 + 主行金字左金条；新变体 `UiMenuRow` / `UiMenuRowPrimary`；左内容距 46S（序号列位） |
| 设置 | 分组标题「tick 金杠 + 线」（`_group_header` 改 HBox）；chip 60×40；标签 96 宽；滑杆 240；卡 540；返回 240×44；body 间距 12；滚动高 0.66/640 |
| 存档 | 卡 520；行 380×52；删除 64×52；返回 240×44；标题条 44 |
| 结算 | 卡 440；题 36；正文 13.5；钮 46/44 |
| 暂停 | 卡 340；题 24；钮 260×46/44 |

样式纪律延续 v2.3/v2.4：颜色一律 token 突（`UiStyle.DARK`）；图标脚本**禁构造颜色**
（`UiIcon.setup(icon, color_key)` 由 HUD 传 tokens；`check_ui_lint` L1/L2 咬）；
`game` 页不挂氛围层（check_shots 契约）。

#### 撤销 pill：他会话撤销机制的 HUD 落地

他会话并行新增**建造撤销**机制（未提交半成品，见其工作树）：`sim/world.gd` 增
`undo_build` 命令、`main.gd` 增 `_remember_build` / `_update_undo_ui`（ callbacks `on_undo`），
并要求 HUD 提供 **`hud.set_undo_vis(on, secs)`** 与 **`hud.undo_panel`**（探针断言
`.visible`）。v2.5 重写指挥盘时删除了 v2.4 遗留挂点 ⇒ `main.gd` 的调用全部炸
（`Nonexistent function 'set_undo_vis'`），且 `probe_input` 因
`Invalid access to property 'undo_panel'` **中止无 checks 行（exit=0 假绿）**。

落地（hud.gd，v2.5 共识合约）：

- `undo_panel: Button`（140×30S，**浮在指挥坞上沿居中**，dock top −36S；HudButton
  变体 + A1 光边；文案「撤销 · Ns」，留窗 ≤5s 由 main 每 tick 刷剩余秒）
- `set_undo_vis(on: bool, secs: int = 0)`：null 安全（build 前调用早退）；`secs`
  带默认值兼容 `set_undo_vis(false)` 单参调用
- **不入 `hit_regions()`**（浮钮在场时 Button 自吞输入，不产生穿点）；`_undo_on`
  为显隐归口：`set_visible_hud` 复显时按 `_undo_on` 还原（整层隐藏不得误亮）；
  `reset()` 新局置 false
- pressed → `callbacks["on_undo"]`（与 Ctrl+Z / 右键撤销同源命令链）

#### 蚌实修理：他会话半成品的编译阻塞

`game/view_terrain.gd` 两行 `var dx := w.x - gp.x` / `var dz := w.z - gp.y`——
`:=` 推断**无类型数组元素** duke 报错（§7 硬约束「禁 `:=` 推断无类型 Array 访问」）。
改为显式 `: float` 两处，`view` 链恢复编译。已随 936c175 入库。

#### 探针口径更新（伴随 UI 实际变化，注明归属）

- `probe_touch` 按钮矩阵 `54 → 55 → 56`：+1 = **§11.34 隐私说明钮 `btn_privacy_policy`**
  （他会话提交 696d977 时未跑窗口闸）；再 +1 = **他会话标题页肉鸽入口 `btn_rogue`**
  （并行新增；本轮矩阵口径随之更新，组成 `6+5+2+7+34+2`）
- `probe_hud` 86 → 92：+6 撤销 pill 断言（窗内可见 / 倒计时文案 / 收起隐藏 /
  复显+文案刷新 / 复位隐藏）
- `probe_input` §2 撤销段断言（visible 出现/消失）与他合约对齐（其本身未改）

#### 验收与证据

| 闸 | 结果 |
|---|---|
| headless 9 闸 | unit **107/0**、golden **2/0**、scene **25/0**、blueprint **21/0**、sim **5/0**、grid **40/0**、flow **53/0**、scenario **77/0**（剧本指纹 `0x7dea2b02` 不变）、world **20/0** 全 PASS |
| 窗口 13 闸 | sync **2771/0**（他会话同步扩探针）、input **89/0**（含他会话撤销/Ctrl+Z 段）、hud **91/0**（86+5 撤销断言）、ui_flow **39/0**、save **77/0**、smoke **34/0**、shots **9/0**、audio **56/0**、asset **63/0**、model **6/0**、orient **1/0**、intro **36/0**、touch **73/0**（矩阵 56） |
| `tools/check_shots.py` | **44 项 fail=0 PASS**（含新 `btn_rogue` 后重出截图） |
| UI lint / selfcheck | **3/0** / **33/0** |
| 证据目录 | `logs/gates-20261020-v25/`（22 闸 stdout + exit） |

判定要点：`probe_input` 此前因 `undo_panel` 缺失中止（exit=0 假绿、无 checks 行），
落地撤销 pill 后 `[INPUT] checks=89 bad=0` 恢复完整；`hud/input/touch/scene/shots/check_shots`
均以本节落地后之最终树重跑为准。

#### 状态与移交

- 主要模式 UI（v2.5）已收口；**标题页 `btn_rogue` 的样式/布局由他会话继续**（在
  `_menu_row` 结构上插入，矩阵口径已容纳）
- 双端包**未重出**：待用户确认本轮界面后按 §11.26 口径重出四件（届时标题/按钮布局
  以会话收敛后的最终态为准）
- 预览邮件随附 6-7 张截图（title/settings/slots/gameover/hud/game/game_tablet）

### 11.35 打击感补丁：静默音效接线 + 受击闪白 + 震屏 + 音高抖动（2026-10-21）

#### 起因：音效库 30 个文件只用了 12 个

`assets/audio/sfx/` 下 30 个 mp3，`play_sound` 实际只覆盖 12 个。`gold_collect` /
`orc_hurt` / `zerg_hurt` / `orc_warrior_attack` / `zerg_blade_attack` / `*_step` /
`*_worker_*` 全部静默。零新资产的纯接线收益，优先做。

#### 改动清单（全部落在表现层，`sim/` 零改动）

| 项 | 文件 | 做法 |
|---|---|---|
| A1 受击音 | `game/view_entities.gd` | 受击分支（`hp` 下降）播 `zerg_hurt` / `orc_hurt`，音量 0.5 |
| A2 攻击音 | 同上 | Attack 状态机分支播 `zerg_blade_attack` / `orc_warrior_attack`，音量 0.45 |
| A3 收金音 | 同上 | 比较 `world.supply` 增量 → `gold_collect`，音量 0.4；本帧有挖矿覆盖层消失时让位（已有 `mining_gold_hit`） |
| B1 音高抖动 | `game/view_audio.gd` | `pitch_scale = 1 ± 4%`，独立 `RandomNumberGenerator`，不污染 sim 确定性 |
| B2 受击闪白 | `game/view_entities.gd` | `MeshInstance3D.material_overlay` 挂共享 ADD 材质，随脉冲两档衰减（0.22 → 0.10 → 关） |
| B3 震屏 | `game/view_core.gd` / `view.gd` / `main.gd` | 相机位姿只叠**平移**偏移（两频正弦 + 二次衰减）；探针态由 `main` 关 `shake_on` |

**限流是硬要求**（大群围攻逐兵逐帧触发必音爆）：

| 音 | 单兵间隔 | 全局间隔 |
|---|---|---|
| 受击 | 20 tick（1.0s） | 4 tick（5 次/秒） |
| 攻击 | — | 4 tick（5 次/秒） |
| 收金 | — | 8 tick（2.5 次/秒） |

#### 闪白：两个只能靠实测发现的坑

| 坑 | 现象 | 正解 |
|---|---|---|
| ADD 混合下 `albedo_color.a` 不参与强度 | 写 `Color(1,1,1,0.55)` 与写 `Color(1,1,1,1.0)` 结果一样，都是过曝纯白 | 强度写进颜色值：`Color(0.22,0.22,0.22,1.0)` |
| `cull_mode = CULL_DISABLED` | 背面再叠一遍，暗色单位直接变白剪影 | `CULL_BACK` |

两档强度实测依据：`shots/flash_off.png` / `flash_on.png`（同姿态对照）。0.30 起暗色 zerg 就读成灰白、丢失色相，**0.22 是保留色相的上限**。
低画质档（`fx_quality == 0`）强制关闪白，但**仍要走一次写 null 的路径**，否则切档后残留亮层。

#### 震屏：三条设计约束

| 约束 | 原因 |
|---|---|
| **只平移，不旋转** | 旋转会改 `world_to_screen` 的闭式解缓存，HUD 浮动文字与建造预览会跟着漂；平移不动朝向，HUD 对位不变 |
| **同帧多次触发取 max，不叠加** | 多塔同时打核心时幅值叠乘会直接晃吐；`shake_amp = max(amp)` 才支持连续触发 |
| **探针态必须关（`shake_on = false`）** | 截图探针靠固定取景做像素校验，抖动会让基准图漂移；`main._ready` 里按 `_detect_probe_run()` 关 |

归零那一帧也必须 `_apply_cam()` —— 否则相机会停在最后一帧的偏移上，回不到基准位（`probe_gamefeel` 第三段专测这条）。

口径：核心受击 0.30m / 0.22s、10 tick 独立节流（约 2 次/秒，比音效的 30 tick 更密）；技能释放 0.45m / 0.28s，无节流（释放本身有冷却）。

#### 验收

| 闸 | 结果 |
|---|---|
| `run_tests`（107 单测） | `[UNIT-ALL-GREEN]` |
| `probe_golden` | `checks=2 bad=0 PASS`（16 指纹未变） |
| `probe_audio`（窗口模式） | `checks=56 bad=0 PASS` |
| `probe_asset`（窗口模式） | `checks=63 bad=0 PASS` |
| `probe_sync` | `checks=2771 bad=0 PASS` |
| `probe_smoke`（窗口模式） | `checks=34 bad=0 PASS` |
| `probe_hud` | `checks=91 bad=0 PASS` |
| `probe_input` | `checks=93 bad=0 PASS` |
| **`probe_gamefeel`（新增闸）** | `checks=18 bad=0 PASS`（闪白触发 tick 940 + 消退 + 震屏生命周期 + 核心受击触发点） |

⚠️ `probe_audio` / `probe_asset` / `probe_smoke` / `probe_gamefeel` **必须窗口模式**：
`audio_on` 在 headless 下为 false，6 条「播放中」断言会假失败；`probe_asset` 在 headless 会 SIGTERM。

#### 未做（留档备选）

| 项 | 未做原因 |
|---|---|
| 通用飘字（伤害/资源） | 需先把 `hud.float_bounty` 的池扩成通用接口，属 hud.gd 改动（该文件有外部并发写入史，改动前必须重读） |
| 顿帧 | 塔防节奏会被打断，只适合核心受击单点，待玩法侧裁定 |
| 敌人头顶血条 | 会让玩家精确算血，削弱塔防的不确定焦虑，**不建议做** |
| 建造落位尘土 | 需要新增粒子节点，还要考虑低画质档降级，成本高于前四项 |

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
    <godot> --headless --path <P> -s res://tests/run_tests.gd      # 期望 passed=106 failed=0
    <godot> --path <P> -s res://tests/probes/probe_xxx.gd                       # 期望 [XXX] PASS
- 证据要求：stdout 原文 + exit code + （涉及画面时）截图且必须目视
- 失败预案：<该任务在 §7.11 砍单顺序里的位置>
- 完成后：更新源文件头部注释 + 本文对应章节 + 立即提交
```

---

## 13. 快速上手（新 AI 的第一小时）

```bash
# 0. 环境
GODOT="C:/G/game/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe"
P="C:/Users/Administrator/Documents/默认项目/reroute-godot"

# 1. 建立基线（全绿才动手）
"$GODOT" --headless --path "$P" -s res://tests/run_tests.gd
"$GODOT" --headless --path "$P" -s res://tests/probes/probe_golden.gd
"$GODOT" --headless --path "$P" -s res://tests/probes/probe_scene.gd
"$GODOT" --path "$P" -s res://tests/probes/probe_sync.gd        # 窗口模式！
"$GODOT" --path "$P" -s res://tests/probes/probe_input.gd       # 窗口模式！

# 2. 读代码顺序
sim/sim.gd → sim/scenario.gd → sim/grid.gd → sim/flowfield.gd → sim/world.gd
→ game/main.gd → game/view.gd → game/view_*.gd → game/hud.gd → game/screens.gd

# 3. 改完再跑一遍第 1 步，外加受影响的闸（见 §9.3）
```

**先读 `sim/` 再读 `game/`。** 模拟层是权威，表现层是投影。任何「表现层看起来不对」
的问题，先确认模拟状态本身是否正确。

### 13.1 冲刺期特别提醒

- **硬截止 2026-10-21 12:00 —— 交付已完成**：10-21 00:14 版本上线（`status=online`），
  活动投稿「已通过」。本节保留为冲刺期历史口径，赛后复盘参考。
- **开发者日志 5 篇已达成**（①10-15 ②10-16 ③10-17 ④10-19 ⑤10-20），规则为「开发期内累计 ≥5 篇」。
- **每次改动后立刻提交**。7 天里没有回滚余量。
- **D3 之后 `sim/` 冻结**，任何数值改动都要连带重录基线，不允许。
- **D4（10-18）只做提交，不写代码。**
- 任何一天任务未完成，**不要加班补，按 §7.11 砍单**。
- 分不清优先级时，问一个问题：**这件事影响「能不能交上」吗？** 不影响就往后放。
