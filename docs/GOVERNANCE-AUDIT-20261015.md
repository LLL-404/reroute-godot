# 治理体检：规范 / 框架 / 流程到底有没有 · 2026-10-15

**范围**：`reroute-godot`（活跃）、`reroute`（Maker 版母体）、`cashline`（决策文档）、顶层 `games/README.md` 四层治理资产。
**方法**：3 个只读专家代理并行分头审（可执行性 / 文档权威链 / 流程遵守度），主线逐条自己复算命令。基线 `77915ff`，`reroute-godot` 共 25 个提交。
**状态图例**：【实测】主线跑了命令；【读码】核对原文；【推演】未复现。

---

## 一、直接回答：有，而且文本很全——但执行层一件都不在活跃仓里

| 治理资产 | `reroute-godot`（**正在开发**） | `reroute`（已冻结） | `cashline`（文档） | 顶层 |
|---|---|---|---|---|
| 开发规范文本 | ✅ §8 六节（命名/格式/注释/类型/日志/提交） | ✅ AGENTS.md 17 条规则 | — | ✅ 跨仓规矩 4 条 |
| 开发流程文本 | ✅ §7.0–§7.12（D0–D7 倒排 + 每任务流程） | — | ⚠️ 已降级的两份计划 | — |
| 验收标准文本 | ✅ §9.1–§9.5（闸清单/影响矩阵/目视/改断言规范） | — | — | — |
| 判据变更记账 | ❌ 无（顶层要求动判据先记 `cashline/docs/DECISIONS.md`，10-13 之后 **0 条**） | — | ⚠️ 账断在 10-12 | — |
| `.editorconfig` | ❌ **无**（且历史 0 次） | ✅ | ✅ | — |
| `.gitattributes` | ❌ **无**（且历史 0 次） | ✅ | ✅ | — |
| `AGENTS.md` / `CLAUDE.md` | ❌ **无** | ✅（1–190 行是平台注入策略块，191–1117 才是作者内容） | ❌ | — |
| CI / git hooks | ❌ 无 `.github/`，`.git/hooks` 只剩 `.sample` | — | — | — |
| 格式闸 | ❌ 无 | ✅ stylua + `check_format.py` | ✅ `tools/check_format.py`（含 `--selftest` 与五类负对照） | — |
| 文档新鲜度闸 | ❌ 不受管辖 | 部分 | ✅ `check_doc_freshness.py`（**扫描根只有 cashline 与 reroute**） | — |
| 像素/截图闸 | ✅ `tools/check_shots.py`（有阈值、缺图 FAIL） | — | — | — |
| 游戏验收闸 | ✅ 83 单测 + 16 黄金指纹 + 17 探针（**这套是全仓最强的资产**） | ✅ 13 道 Lua 闸 | — | — |

**一句话**：规范不是没写，是**写在了一个没有任何机器闸的仓里**。三处实测能证明这不是措辞问题：

- `git log --all -- .editorconfig .gitattributes AGENTS.md` → **0 条**。不是删了，是 10-13 建仓那天就没带过来，比 `reroute` 补这层（10-12）晚一天。
- 顶层 `games/README.md:69` 写着"动手前先读该仓的 `AGENTS.md`""格式规则在各自 `.editorconfig`（LF 锁死是硬要求）"——这句话对三仓中的两仓**今天是假的**。而 `reroute/.editorconfig:6-11` 与 `DECISIONS.md:203-210` 里逐字记着同款事故（"那句话当时是假的"）。同一个洞，第三次踩。
- `grep -rl INVALID --include='*.gd' --include='*.py' .` → **0 命中**。§9.2 第 3 条"量化闸读零要输出 `INVALID` 而不是 `PASS`"这条哨兵，全仓没有任何实现。

---

## 二、红项（按能否挡住 10-18 投稿排）

**R1 阻塞【实测】两个仓的最后一刀没有备份。** `git -C reroute status -sb` → `main...origin/main [ahead 8]`——冻结母体最后 8 个提交（含 10-13 那 86 例 sim 单测）只在本机一份。`cashline` 干脆 0 远端，还带一个未提交的 `docs/specs/_registry.md`。顶层 `games/README.md`（今天刚写进"三仓事实"和降级判定）不在任何 git 仓里。**唯一记录"哪些文档已被取代"的地方，恰好是唯一没备份的文件。**

**R2 阻塞【实测】今天的 D1 卡在一个方案没预判的环境差上。** 方案要求 JDK 17，实装 `Eclipse Adoptium jdk-21.0.12.101`；`ANDROID_HOME` 与 `ANDROID_SDK_ROOT` **均未设**；`~/.android/debug.keystore` 不存在（D0-4 两天未做，§6.5 表里四行仍是 `❓ D0 清点`）。已就绪的部分：导出模板 `4.7.2.stable.mono` 已装（含 `android_debug.apk`/`android_release.apk`）、`adb` 在 PATH。`export_presets.cfg` 只有 1 个 preset（Windows Desktop）。

**R3 阻塞【实测】§9.1 点名的触屏闸指向不存在的文件。** `probe_touch.gd` 不存在，却被 `PLAN:292`（G7 目标）、`:778`（D1-2）、`:780`（D1-4）三处列为必跑。**注意这不是文档写错**——三处都明写"新增"，它是今天要开工的活；真正的信号是：今天已是 D1，而 10-15 上午两个提交（`3c48d91` 换字体、`77915ff` 体检报告）都不是 D1 交付项。触屏闭环是"最佳双端奖 ¥80,000"唯一还没落地的判据。

**R4 一般【实测】§8.6 提交规范全仓合规率 52%，且没有任何东西能挡住。** 25 条标题里 **12 条**不合规（`git log --pretty=%s | grep -vcE '^(feat|fix|refactor|docs|test|build|chore|style): .+'`）。公平核账：§8.6 是 `c331ca3`（10-14 15:43）才入库的，12 条里 11 条在其之前，属追溯不成立；**生效后唯一一次违规是 `3c48d91`（10-15 08:59「授权修复 R-1：…」），由本会话主线所提**——已推送，不追溯改写，记在这里。无 commit-msg hook、无 CI，所以这条只能靠自觉。

**R5 一般【实测】§8.2 三条格式要求零判红，且现成的闸搬过来会反向炸。** 行宽 >100 的 `.gd` 行实测 **65** 处；换行符实测 19 个文件 `i/lf w/crlf`（`sim/grid.gd`、`sim/world.gd`、`sim/flowfield.gd` 是 CRLF，同目录其余是 LF），全靠本机 `core.autocrlf=true` 撑着——`git config --show-origin` 显示它来自 `D:/Users/23501/.qoder-cn/bin/git/etc/gitconfig`，**不在 `--global`、不在仓内**，换系统 Git / 换客户端 / 上 CI 就失效。而 `cashline/tools/check_format.py:177` 见制表符即 FAIL，本仓 `.gd` 的 Tab 缩进行实测 5920、4 空格行 0 —— 直接搬过去第一轮炸 5920 条。**值得搬的只有 `index_cr_check`（`:210`）与自带负对照的 `index_selfcheck`（`:360`）**，那两条恰好是 10-12 那次"空闸跑了一天没发现"事故修出来的。
附带一条本机陷阱：`grep -cP '\r$'` 在这台机器上会**静默返 0**（`od -An -c` 明明见 `\r\n`），所以判行尾只准用 `git ls-files --eol`。

**R6 一般【实测】现行权威文档一天内就自相矛盾。** `PLAN:8`「当日整理改动**已提交**」vs `:1094`「本次改动**尚未提交**」（实测工作树干净，后者是陈旧句）；`sim/` 冻结日 `:744` 写 D4、`:1292` 写 D3；缺陷全修 `:798` 排 D3、`:1035` 标题写 D4；结构整理 `:1104` 写 D6、§7.8 是 D5；`:497`/`:1005` 两处 §锚点指向不存在的编号。`shots/` 写 13 张、实测 15 张。

**R7 一般【实测】`PLAN` 自己有一条假的"实测不符"。** `:255-257` 说"AI-ASSETS 文中写 18 条，Godot 工程实测 19 个 mp3，数字必须重新点数"。实测 `assets/audio` 下 mp3 = **19**，而 `AI-ASSETS.md:24-25` 写的是"音效 18 条"**加**"对局 BGM 一条"= 19——原文自洽。**照 D0-6 那句去"修正"，会把一个对的数改错。** 该改的是 PLAN 这条断言本身。

**R8 一般【实测】体检结论没有回流进权威文档。** 今天的地形体检（R2 变异五闸全绿、R1 命令表错位）在 `DEVELOPMENT-PLAN` §10.2 缺陷表里**一条都没有**，`AUDIT-TERRAIN-20261015.md` 在四个入口文档里的被引用次数 = **0**。按 `PLAN:3`「接手先读本文」的读取序，最新结论被更旧的 §10.2 挡在门外。

**R9 一般【实测】降级信息只写在体系外。** `cashline/docs/GAMEJAM-2026-PLAN.md:6` 至今自写"日程与其他文档冲突时**以本文为准**"、`MAKER-PORT-PLAN.md:13-14`"本文仍是技术方案的权威"、`specs/_registry.md:59` 裁决表仍指"哪天做什么→GAMEJAM-PLAN"——**三处都还声称自己是权威**，而它们被取代的唯一依据在顶层 README（不入 git）。`_registry.md` 10-14 只加了一行 CREDITS 登记（还没提交），裁决表 9 行一行没改，扫描根也没有 `reroute-godot` → 新权威在管辖体系之外，机器全绿。

**R10 观察【实测】`cashline/docs/AI-ASSETS.md` 不能直接当投稿附件。** `:45` 仍写"引擎：**UrhoX**"、`:29` 称动画由"离线 Lua 脚手架烘焙（`scripts/ZergMotion.lua`）"，Godot 侧实际走 `tools/umd2_to_gltf.py` → glTF。它被 `PLAN:240,1219` 当投稿底稿引用。同理 `cashline/docs/devlogs/01-参赛宣言.md:40-46` 整节"为什么是 TapTap 制造"+"最佳制造奖 8 万块，谁不想要"，与 10-15 更正后的口径（非制造作品已无资格）正面对撞——**这篇旧稿现在不能发**。本仓 `docs/devlogs/01-开篇-放墙改道.md` 实测无 Maker 残口径，但状态行仍是"待发布"，而全程参与奖要求 ≥5 篇、每篇间隔 ≥1 天。

**R11 观察【读码】`reroute/AGENTS.md` 没有冻结声明，且方向与现行相反。** `:5-8` 仍命令"只用 Maker MCP 与工程内文档为真源，别用开发者中心文档"，而 `PLAN §0.1` 正是从开发者中心查证的。任何接手者（或 AI）误进这个仓读它，会被带到相反的路径上。平台注入块（1–190 行，带 version/hash）不要改文，冻结声明加在块外。

---

## 三、我改判与驳回的代理结论

- **改判**：`probe_touch.gd` 缺失被报成"闸指向不存在的文件"（文档缺陷）。三处引用都明写"新增"，它是 D1 未开工的进度信号，不是文档 bug。严重度从"文档腐化"改记到"排期风险"（见 R3）。
- **驳回**：代理报"§8.6 合规率 52% 说明规范没被遵守"。规范 10-14 15:43 才入库，12 条违规里 11 条在其之前，追溯不成立；生效后真违规只有 1 条（见 R4）。
- **驳回**：代理报"`reroute-godot` 索引里有 CRLF 污染风险"。实测索引侧 `i/crlf` 与 `i/mixed` 各 **0**（258 个跟踪文件：174 `i/lf w/lf`、19 `i/lf w/crlf`、65 二进制）——**今天无历史污染，不需要 renormalize**，风险纯 prospective（换环境才发生）。
- **纠正主线自己的口径**：我上一轮说这个仓"24 个提交"，实测 `git rev-list --count HEAD` = **25**。

---

## 四、这套流程里哪些是纸面的，哪些真挡住过事故

**纸面的（写了、没人被挡过）**：§9.5 改断言规范（自限"D6-2 适用"，实测 0 次遵守，且历史上有一次断言被改松：`9517e2d` 把 `probe_sync` 的 scale 期望从公式改成 `Vector3(1,1,1)`、`death_fx` 期望 0→1，正文只写"改模型口径"）；§9.2 的 `INVALID` 哨兵（0 实现）；§7.1 第 2/4 步"跑闸留证据"（10-13/10-14 两天日志目录里没有任何输出，唯一能复算的证据是今天这批）；§6.5/§7.3 的 `❓ D0 清点` 与 keystore 状态位（挂了两天无人被挡）；§11 台账（自我陈述不受校验，已实测三处不实）。

**真正值钱的（保留，别在 D5 结构整理时动它们）**：16 指纹黄金回放 + `canon.gd:74` 负对照（迁移期逐位对齐全靠它）；§5.4"禁止为修绿探针改基线"（11 次探针改动、**0 次基线改动**，红线确实守住了）；§9.4 目视 + `check_shots.py`（`8dbeac2` 靠它抓到幽灵截屏消失）；§5.3 确定性 + `probe_smoke` 三次逐位一致；§9.3 影响矩阵的 `export_presets.cfg` 行——今天 `3c48d91` 改预设即重跑五闸，`logs/gates-20261015/` 里 stdout/err 成对存证，**这是全仓唯一一次证据链完整的改动**。

**但 §5.4 那条红线有个实测破口**：地形体检 R2 证明，把 `sim/flowfield.gd:177` 的下崖语义改坏，83 单测 + 16 指纹 + 三道 sim 探针**全绿**。也就是"改 `sim/` 一定会被基线挡住"目前是错觉——基线只锁被走到的路径，而 R1 又证明 16 指纹里 13 个不含高度层改造。这两条合起来是治理层面最该修的一件事。

---

## 五、最小可执行化清单（10-18 之前只做前四条）

| # | 做什么 | 挡住哪一次已记录的事故 | 判红命令 | 代价 |
|---|---|---|---|---|
| 1 | 补 `.gitattributes`（照 `reroute/.gitattributes` 改二进制点名清单） | 10-12 那次"注释声称有、仓里其实没有"，10-13 建仓又犯 | `git check-attr text -- sim/grid.gd` 须报 `auto` | 分钟级 |
| 2 | 搬 `index_cr_check` + `index_selfcheck` 成 `tools/check_eol.py`（含 `--selftest`） | `--index` 空闸把假证据写进 DECISIONS；本机 `grep '\r$'` 静默返 0 | `python tools/check_eol.py --selftest` 末行 `[SELFTEST-OK]` | 20–30 分钟 |
| 3 | 补 `AGENTS.md`（作者自己写：闸命令一览 + §8 摘要 + §9.5 五条 + D4 冻结 `sim/`）+ 3 行 `CLAUDE.md` 存根 | 顶层 README:69 那条纪律今天落空；AI 接手不知道先跑哪几道闸、不知道 §9.1 触屏行是空的 | `ls AGENTS.md CLAUDE.md` | 15–25 分钟 |
| 4 | 把地形体检 R1/R2 回写 §10.2 并升 v2.3；顺手修 R6/R7 那几处自相矛盾 | 最新结论被旧缺陷表挡在门外 | 人工过一遍 §10.2 | 30 分钟 |
| 5 | `tools/run_gates.sh` 一次跑完该跑的闸并汇总 `[GATES] PASS/FAIL`，缺件先判红 | §7.1 全靠人记；13 道里 8 道要窗口 | `bash tools/run_gates.sh --list` | 45 分钟 |
| 6 | commit-msg 闸（含 `--selftest` 喂"授权修复 R-1：…"这类必须判红） | R4 | `git log --pretty=%s \| grep -vE '^(feat\|…): .+'` → 0 | 15 分钟 |
| 7 | `.editorconfig`（Tab / ≤100 / LF）+ 一个只判行宽与行尾空白的最小脚本（**不要**复用 tab=FAIL 那条） | §8.2 三处实测无人判；65 行超标 | `python tools/check_format.py` | 40–60 分钟 |
| 8 | 文档锚点闸：`check_doc_freshness.py` 扫描根加 `reroute-godot/docs`，PLAN 头部补 `> 新鲜度：` 锚点 | 10-09 那次"自称代码镜像却四处值不符"；R7 这类抄死的运行时数字 | `python tools/check_doc_freshness.py` → `[FRESH]` | 45–75 分钟 |
| 9 | `reroute` push 那 8 个提交；`cashline` 建远端或至少 `git bundle` | R1（单机一份） | `git -C reroute status -sb` 无 ahead | 分钟级 |
| 10 | GitHub Actions（私有仓 ubuntu，下载 Godot headless 跑单测 + 黄金回放 + eol + commit-msg） | "换台机器结果不同"这一类——**Jam 期性价比最低，10-18 之后再做** | CI 红/绿 | 1–2 小时 + 每次约 200MB 下载【推演】 |

---

## 六、复现命令

```bash
cd /d/G/game/games
git -C reroute status -sb                       # R1 ahead 8
git -C cashline remote -v                       # R1 空
cd reroute-godot
git log --all --oneline -- .editorconfig .gitattributes AGENTS.md | wc -l   # R5 → 0
git ls-files --eol | sed 's/\t.*//' | sort | uniq -c                         # R5
git config --show-origin --get core.autocrlf                                 # R5
git ls-files '*.gd' | xargs grep -cP '.{101,}' | awk -F: '{s+=$2} END{print s}'  # R5 → 65
git log --pretty=%s | grep -vcE '^(feat|fix|refactor|docs|test|build|chore|style): .+'  # R4 → 12
grep -rl INVALID --include='*.gd' --include='*.py' . | wc -l                 # → 0
ls probe_touch.gd                              # R3 → 不存在
find assets/audio -name '*.mp3' | wc -l        # R7 → 19
```
