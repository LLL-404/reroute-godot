# 《改道》地形系统体检 · 2026-10-15

**范围**：地形/高程/单向崖/程序化蓝图在 Godot 版的全链路——`sim/grid.gd`、`sim/flowfield.gd`、`sim/world.gd`、`sim/scenario.gd`、`sim/verify.gd`、`game/blueprint.gd`、`game/view.gd`、`game/main.gd`，以及覆盖它们的 83 例单测与 10 个探针。

**方法**：4 个只读专家代理并行分头审（模拟层数据结构 / 命令路径与守卫 / 表现层渲染 / 验证覆盖），主线逐条点验——能读码定论的读原文，能实跑证伪的自己跑。**基线代码** `3c48d91`，引擎 Godot 4.7.2 stable mono。日志：`D:/G/game/games/logs/gates-20261015/`。

**核验状态图例**：【实测】我跑了命令并有输出；【读码】我逐行核对过原文与算例；【推演】只有书面推演，未复现。凡代理报来而我没核过的，一律不写进本表。

---

## 红项（按能不能挡住 10-18 投稿排序）

### R1 阻塞【实测】黄金回放里"改地形"的样本全挤到了最后一刻

`sim/verify.gd:8-9` 的注释写着"命令在该 tick 开始前生效"，但 `:31-37` 把 19 条命令追加在 `[5600,...]` 之后，而 `:66` 的消费是**严格按数组顺序、不排序**（`while ci < commands.size() and commands[ci][0] <= tick_count + 1`）。

实跑结果（临时探针，跑完已删）：81 条命令里 **19 条实际生效 tick 与标称不符**；9 条填高/挖低**全部**推迟到 5600；`dig(5,37)` 从 1000 推到 1100。于是 `EVERY=400` 采的 16 个指纹中，**400..5200 这 13 个不含任何高度层改造**——`sim/golden_baseline.gd:4` 写的"含高度层样本"对 13/16 不成立。

后果不只是注释难看：改道玩法的主干（挖开 → 绕远 → 流场重算）在确定性基线里几乎没被走过，而且这些命令挤在同一 tick 生效，恰好是压力最大的形态。

**修法**：命令表按 tick 排序 → 走 §5.4 的"记录 + 重录"流程（16 指纹会变，这是预期的，不是回归）。

### R2 阻塞【实测】把"下崖"语义改坏，五道闸一个都不红

注入变异：`sim/flowfield.gd:177` 的 `hp[nb] - hp[p] <= 1`（上崖限 1 级、下崖不限）改成 `absi(hp[nb] - hp[p]) <= 1`（上下都限 1 级）。跑 `run_tests`（83 例）、`probe_golden`（16 指纹）、`probe_flow`、`probe_scenario`、`probe_world` ——**全绿**。

这不是等价变异。自建夹具（8×8，goal (0,0)，(1,0) h=3，(2,0) h=5）：原码 `dir_at(2,0)=4`（向西下崖）；变异后 `dist_at(2,0)` 仍是 20，但 `dir_at` 返回 -1——**单位手里有距离却不肯动**。验完已 `git checkout -- sim/flowfield.gd` 还原，工作树干净。

根因：`relax`（`:122`）与 `dir_at`（`:177`）是两条镜像谓词，`tests/test_flowfield.gd:143-172` 只钉了 relax 侧，两谓词失同步无人报警。

### R3 一般【读码】热层按"改了图"刷新，读到的却是还没追平的流场

`game/view.gd:491` 的触发键是 `world.grid.rev`，`:412-418` 读的是 `world.field.dist_at`，`:421` 把 `heat_rev` 记成最新 `grid.rev`；而流场重建发生在**下一次** `world.tick()`（`sim/world.gd:240-247`）。

帧序是 `main.gd:175-190` 先按 dt 补 tick、`:191` 才 `view.sync(world)`。`TICK_DT = 1/20`（`main.gd:9`），60fps 下约 3 帧才 1 tick → **命令落在没有 tick 的那约 2/3 帧里**，热层就按"改道前"的拓扑出图，并且因为 rev 已记成最新，之后不再刷新，直到玩家下一次改图。玩家看到的永远是上一次改道的残缺热图——而"绕得远"的染色正是这个玩法唯一的即时反馈。

附带一条同源：`:421` 先记 `heat_rev`，`:424` 才因 `maxd <= 0` 直接 return → 极端情况下开了热层却整幅空白到下次改图。

现有探针看不见它：`probe_sync.gd:161-191` 的期望值取的是**同一时刻**的 `world.field`，同错同绿。

**修法**：触发键改用 `world.field_rev`（或 `field.done()` 才刷），`probe_sync` 改成"改图当帧读一次、补场之后再读一次"并断言两次不同。

### R4 一般【读码+算例】拖线预览说"不行"，提交照样建一半并扣钱

预览：`main.gd:341-344` 只要有一格 `mode_valid` 假，**整条线染红**。提交：`main.gd:324-325` 逐格 `apply_mode_at`，而 `:297-298` 直接 `world.apply_command`，**不查 `mode_valid`**，合法性由模拟层逐格守卫。

格子算例（按 `sim/scenario.gd:113` 的稀疏表土规则 `y>12 ∧ y<26 ∧ x%9==4 ∧ y%11==6` 手算）：`(13,17)` 是 COVER，`(11,17) (12,17) (14,17) (15,17)` 都是 OPEN。墙模式从 `(11,17)` 拖到 `(15,17)` → 幽灵整条红，实际建出 4 面墙、扣 40 供给。玩家看到"这不行"却钱货两失。

### R5 一般【读码】预览按"当前供给"逐格判，不累计整线开销 → 绿幽灵只建出一部分

`main.gd:235-236` 对线上每一格都用同一个当前 `world.supply` 比；`sim/world.gd:206-207` 提交时逐格扣，扣不动就 return。算例：供给 35，拖 4 格全合法 → 幽灵全绿，实际只建 3 面墙、供给终值 5。塔同理（130 拖 3 格 → 2 塔）。

### R6 一般【读码】环带不含 sim 高度层——`528650e` 修完柱顶留下的接缝

柱带 `view.gd:270-272` = `field_h + grid.get_h * H_STEP`；环带 `:306` 用 `ground_h`（`:212-216` 只走 `height_fn`，**不含 sim 高度**）。`:261` 的注释仍写"同一高度函数保证衔接"。

`sim/scenario.gd:78-87` 使 `y ≤ 29` 整带 h ≥ 1（核心山头 h=3）→ 北半场柱顶比邻接环带高 1.2–3.6m，画面沿北/东西边缘出现一道假崖。且 `_rebuild_ring` 只在 `apply_blueprint` 里调，玩家填挖时根本不刷。判别只看 `shots/game.png` 北边缘；`probe_scene` 对 ring 只断恒 4384，零敏感。

### R7 一般【读码】`field == 2304` 是重言断言

`view.gd:280-287` 三条带必然覆盖全部 2304 格 → `_stat_field` 恒等于 2304。`probe_scene.gd:30` 与 `game/selfcheck.gd:126` 断的就是这个数：分色错、柱高错、band 阈值错**全都不会红**，也无法暴露 R6 与下面的"多刷两次"。

**修法**：`_stat_field` 改成 per-band 三元组，再加一个"重建计次"读数。

### R8 一般【读码】Grid 写侧不守界

读侧 `get_h`（`:50-52`）、`at`、`passable` 都先 `inb`；写侧 `set_h`（`:56-58`）、`init_h`（`:67-69`）直接 `y*w+x`。GDScript 越界是硬报错，按本仓 §5.1.3 会伪装成"挂起"（`_initialize` 中止 → `quit()` 不执行 → 无头空转）。现在靠调用方 `passable` 守卫兜住，属潜伏；`tests/test_grid.gd`、`probe_grid.gd` 都没有写侧越界的负对照。

### R9 观察项（不挡投稿，但都记下来）

- **hero 模式预览与提交分叉**：`main.gd:259-260` 只判 `passable`，`sim/world.gd:122` 还要求"非原地"。英雄脚下点英雄 → 幽灵绿、命令静默无效。这正是 `528650e` 给 wall/tower 补掉的同类，hero 分支漏了。
- **`game/blueprint.gd:197` 用裸 `%`**（§5.2 要求一律走 `Lua64.mod`）：`(run_index-1) % 3` 在 `run_index=0` 时得 -1，GDScript 负下标取末位预设。生产 `run_index` 恒 ≥1，属潜伏。
- **单向崖没有任何可读性表达**【读码】：场内 1 级差与 2 级差都只差 1.2m、同为 `ground_hi` 色；而 `y=29/30` 交界是一道 1.2m、**完全可走、看起来像崖**的假崖。玩家无法用眼睛判断哪里能过。
- **三档高程配色被 sim 高度层淹没**【推演】：palette 的 band 窗口只有 0.70（`blueprint.gd:111-119`，`band_lo_at:-0.25 / band_hi_at:0.45`），而 `H_STEP=1.2`/级（`view.gd:12`）→ 1 个 sim 层级就是窗口的 1.7 倍，h≥1 的整个北半场无条件落 `ground_hi`，蓝图分色在场内失效。这条**现有读数无法判别**（见 R7），要先加 per-band 计数。
- **开局多做 2 次全量重建**【读码】：`apply_blueprint`（`:257-258`）在 `grid` 还是上一局的时候先建一次柱带 + 环带，随即被 `build_terrain`（`:332`）覆盖。每局白扔 2304 格实例 + 4384 次 7 层 fbm 求值。
- **触屏分支未落地**【读码】：全仓无 `InputEventScreenTouch`，`project.godot` 未钉 `emulate_mouse_from_touch`；方案 §7.4 的 D1-2 与 `probe_touch.gd` 都还没做。双端奖要求触屏，这是 D1 的正事。
- **"死坑"能把胜利判定卡死**【推演，未实跑】：把某个敌人四周 8 格填到比它高 ≥2（北岸 h1→h3，约 240 供给）它就爬不出来，震荡波同规则也推不上（`world.gd:376`）；若它不在塔射程内，场上就永远有单位 → 6400 不清场 → 8800 判负。玩家可以用钱把结局卡住，需要裁定这算不算要防的漏洞。
- **视图复刻了模拟层的赏金公式**【读码】：`view.gd:656` 重写了一遍 `reward + traveled >> CONVOY_SHIFT`（权威在 `world.gd:490-491`），且用的是视图缓存的 `traveled`。改 sim 公式不会有任何断言变红，浮字与供给会分叉。

---

## 被降级与被驳回的代理结论（留着，防止后人照抄）

- **"摊销补场把旧拓扑记为已同步"（`sim/world.gd:240-247`）——从阻塞级降为潜伏**。读码确实成立：补场跨多 tick 时新改图只 bump `grid.rev` 不重启 `begin`，收尾却 `field_rev = grid.rev`。但实测一次全场重建只吃 **1914 pop**，默认预算 2048（`world.gd:55`）→ **单 tick 内必完成，当前参数下竞态窗口根本不开**；连改 12 格（拖线一帧上限）仍是 1907 pop。代理把它定为阻塞级，前提（补场跨多 tick）是假设不是实测。**余量只有 134 pop（7%）**，改地图尺寸、调预算或加障碍密度就会开；顺带说明 `rebuild_budget` 实际是第四个"事实冻结"参数，而 §5.4 只列了三件。
- **填高/挖低的"冷却数值与文档是否一致"——前提不成立**：代码（`sim/sim.gd:13-14` 只有 `FILL_COST=15`/`LOWER_COST=10`）与 §3.3 都只有花费、没有冷却。
- **剧本指纹 `0x12715062` 与十进制 `309416034` 是不是笔误——不是**：代理自查换算后确认四处口径一致（文档 552 / `scenario.gd:134` / `test_scenario:158` / `README:84`），非缺陷。

---

## 文档与代码不一致（顺手记账）

- `docs/DEVELOPMENT-PLAN.md:498` 写 `game/hud.gd 581`，实测 583。
- §9.3 影响矩阵没有 `game/blueprint.gd` 行，但蓝图经 `ground_y`（`view.gd:223-225`）参与 `pick_cell`，再经 `main.gd:307` 变成仿真坐标命令 → 改它会改落格。
- §5.4 冻结三件，实际第四件是 `rebuild_budget`。
- `sim/verify.gd:8-9` 的注释口径与实现不符（见 R1）。

---

## 建议新增的最小用例（按 §9.5，每条都必须配负对照）

1. **`dir_at` 下崖语义**：把 R2 那个夹具直接搬进 `tests/test_flowfield.gd`；红侧 = 改成 `absi` 必须变红。
2. **黄金执行序**：逐条断言"实际生效 tick == 标称 tick"；红侧 = 现状本应红（先修 R1 再钉这条）。
3. **填挖 → 改道行为**：StubScenario 走廊上把一格填到 +2，断言 `field.dist_at` 由有限变 -1 且单位绕行/围攻；红侧 = 填高但 `set_h` 不 bump rev。
4. **热层时序**：改图当帧读一次、补场后再读一次，断言两次不同且第二次等于同步重建。
5. **环带/柱带接缝**：断言边界格与邻接内格顶面高差 ≤ 阈值；红侧 = 去掉环带的 sim 高度。
6. **per-band 分色计数 + 重建计次**：把 R7 的重言断言换成有判别力的读数。
7. **Grid 写侧越界**负对照。
8. **蓝图**：`pick(0)/pick(1)/pick(4)` 数值锚点 + 断言仿真种子与视图种子不同源；红侧 = 让 `blueprint.gd` 改用 sim 种子。
9. **不变式补两条**：单位跨格前后高差合法（上 ≤1、下任意）、`hgt[i] == hp[pad_idx]`。
10. **死坑**：把敌四周填高后跑 6400 tick 断言 `outcome`——先裁定是不是要防。

---

## 复现命令

```bash
G="D:/G/game/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe"
P="D:/G/game/games/reroute-godot"
L="D:/G/game/games/logs/gates-20261015"

# 六件套基线（本轮全绿）
"$G" --headless --path "$P" -s res://tests/run_tests.gd   # 83 例
"$G" --headless --path "$P" -s res://probe_golden.gd      # 16 指纹
"$G" --headless --path "$P" -s res://probe_scene.gd
"$G" --path "$P" -s res://probe_hud.gd                    # 窗口模式
"$G" --path "$P" -s res://probe_ui_flow.gd
"$G" --path "$P" -s res://probe_smoke.gd

# R2 变异检验（做完务必还原）
#   sim/flowfield.gd:177  hp[nb]-hp[p] <= 1   →   absi(hp[nb]-hp[p]) <= 1
#   预期：上述无头三闸 + probe_flow/probe_scenario/probe_world 全绿 = 盲区成立
#   git checkout -- sim/flowfield.gd
```

实跑证据已存档在 `D:/G/game/games/logs/gates-20261015/`：

- `audit_clean.out` —— 现行代码下 A/B/C/D 四部分读数（B1「81 条命令 19 条错位」、B2「9 条高度改造全被推迟」、B3「tick≤5200 之前 0 条高度改造」、C1「全场重建 1914 pop ≤ 预算 2048」、D-VERDICT「夹具未产生分歧」）。
- `audit_mutant.out` —— 同样四部分在 R2 变异下的读数（D2 `dir=-1` 而 `dist=20`、D-VERDICT「谓词失同步可复现」）。
- `mut_run_tests.out`、`mut_probe_golden.out`、`mut_probe_flow.out`、`mut_probe_scenario.out`、`mut_probe_world.out` —— 变异未还原时五道闸的输出，逐条 `exit=0` 且末行分别 `[UNIT-ALL-GREEN]` / `[R7-PROBE] PASS` / `[R4-PROBE] PASS` / `[R5-PROBE] PASS` / `[R6-PROBE] PASS`。这两份对照放在一起，才构成"盲区成立、且不是等价变异"的完整证据。
- `tmp_terrain_audit.gd` —— 探针源码存档。探针本体已从仓库删除（`git status` 只剩本文件），变异已 `git checkout -- sim/flowfield.gd` 还原，`grep -rc MUTATION sim/ game/` 命中 0。
