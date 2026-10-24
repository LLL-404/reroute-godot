# 《改道》Godot 工程 · 技术说明

64×64 六边形网格塔防，核心机制「放墙改道」——敌人绕得越远，死时赏金越高。

本文件是**技术向**说明（安装 / 运行 / 配置 / 限制）。项目速览见 [`README.md`](README.md)，
开发权威见 [`docs/DEVELOPMENT-PLAN.md`](docs/DEVELOPMENT-PLAN.md)，AI 开发红线见 [`AGENTS.md`](AGENTS.md)。

> **占位符约定**：文中所有 `<待补 …>` 是**故意留空**的——具体命令、路径、地址尚未定稿。
> 未加占位符的内容均可由仓库内文件直接核对，未引用任何不存在的文件或脚本。

---

## 一、项目用途

### 是什么

一款**单机塔防**。地图是 64×64 的 pointy-top odd-r 六边形网格，玩家用墙体、箭塔与地形改造
（填高 / 挖低）把敌人的行进路线拉长。绕行距离直接换算成赏金（`reward + traveled >> 3`），
所以「改路」既是防守手段也是经济手段。

**两种模式，标题屏入口**：

| 模式 | 规模 | 说明 |
|---|---|---|
| 经典对局 | 单局 6400 tick | 撑到终局且场上清空即胜；布局与视觉地形按种子变奏 |
| 肉鸽 | 5 层 × 20 波 | 阶段制（每波清场停住选牌），每波后三选一（塔卡 / 遗物 / 天赋 / 地形牌）；出怪口逐层逼近核心 |

### 技术定位

| 项 | 值 |
|---|---|
| 引擎 | Godot **4.7.2 stable (mono)**，Windows 构建 |
| 玩法代码 | GDScript（`.csproj` / `.sln` 只用于固定程序集名 `RerouteGodot`，无 C# 逻辑） |
| 目标平台 | Windows Desktop + Android（同一游戏、双端同包） |
| 上游来源 | 从 UrhoX + Lua 母版移植而来；Lua 语义由 `sim/lua64.gd` 的 shim 补齐 |
| 交付背景 | 2026 TapTap 聚光灯 21 天 GameJam 参赛作品，已在 TapTap 上线（商店页：`<待补：商店页地址>`） |

### 架构分层（单向，不许反向）

```
sim/   ←──  game/           表现层只读模拟，模拟层不知道表现层存在
sim/   ←──  tests/          单测驱动模拟
game/  ←──  tests/probes/   探针驱动表现层与整机
```

- `sim/`：**确定性**模拟核心，13 个模块，纯逻辑、**无浮点、无渲染**。唯一随机源是 `World.rng`。
- `game/`：表现层，按职责分四层：`app/`（入口 `main` + 包内自证 `selfcheck`）、`core/`（蓝图/存档/用户设置）、`view/`（3D 视图、模型与地形着色器）、`ui/`（HUD、界面壳、三选一、开屏、隐私门；页面场景在 `ui/pages/`）。
- `run/`：肉鸽模式编排层（`RunState` / `RewardPool` / `Threat`），不改 `sim/` 语义。
- `tests/`：9 个单测模块 + 37 个验收探针。

**唯一的模拟写路径**是 `main.gd` 调 `world.apply_command(dict)`。非法命令静默零副作用，不抛异常。

---

## 二、安装步骤

### 1. 引擎

版本**必须严格一致**：`4.7.2 stable mono`。理由不是洁癖——16 个黄金指纹是逐位比对，
换引擎小版本就可能漂移；导出模板也锁在 `4.7.2.stable.mono`。

- 下载地址：`<待补：Godot 4.7.2 stable mono 下载地址>`
- 本机安装路径：`<待补：Godot 安装目录>`
- ⚠️ **无头 CLI 必须用 `_console.exe` 变体**。普通 `.exe` 不输出 stdout，跑闸会看起来「全绿但没输出」。

### 2. 取代码

```bash
git clone <待补：仓库地址> <待补：本地目录>
```

默认分支 `master`。`export/`、`.godot/`、`*.exe`、`*.pck`、`bin/`、`obj/` 均在 `.gitignore` 里
——**拿到仓库不等于拿到可执行包**，包体要自己导出（见第三节）。

### 3. 首次打开

用 Godot 打开仓库根目录的 `project.godot`。首次导入会生成 `.godot/`（已忽略，不必提交）。

### 4. Python（可选，跑截图校验 / UI lint / 资产转换才需要）

仓库**没有** `requirements.txt` / `pyproject.toml`——这几个脚本是裸脚本，依赖自行安装。

- 解释器：`<待补：Python 解释器路径>`
- 依赖：`Pillow`（`check_shots.py` / `make_store_assets.py` 用到；其余脚本仅标准库）
- 注意 `check_shots.py`、`check_ui_lint.py` 的**工作目录必须是项目根**（脚本内按相对路径取文件）。

### 5. Android 出包（只在需要出 APK 时）

| 依赖 | 说明 |
|---|---|
| Android SDK | 路径在 Godot 编辑器设置里配：`<待补：SDK 路径>` |
| JDK 21 | `<待补：JDK 路径>` |
| release keystore | **在仓库之外**，路径 `<待补：keystore 路径>`；alias `reroute`，密码台账 `<待补：签名环境变量文件路径>` |
| 环境变量 | `GODOT_ANDROID_KEYSTORE_RELEASE_PATH` / `_USER` / `_PASSWORD` 三个必须注入——`export_presets.cfg` 里 keystore 六字段是空的 |

Windows 出包不需要 keystore，但导出后要复签（脚本已存在：`tools/sign_windows_exe.ps1`，
依赖本机证书库里的自签证书 `CN=Reroute`）。

---

## 三、运行方式

### 3.1 直接跑游戏

```bash
GODOT="<待补：Godot 4.7.2 mono 的 _console.exe 路径>"
P="<待补：本项目根目录绝对路径>"

"$GODOT" --path "$P"
```

主场景是 `res://game/app/main.tscn`（写在 `project.godot` 的 `run/main_scene`）。

### 3.2 单测

```bash
"$GODOT" --headless --path "$P" -s res://tests/run_tests.gd
```

入口 `tests/run_tests.gd`，下挂 9 个 `test_<模块>.gd`（`canon` / `grid` / `rng` / `flowfield` /
`mapgen` / `scenario` / `world` / `verify` / `save`）。最近一次记录：**107 例全绿**（2026-10-22）。

### 3.3 验收探针

`tests/probes/` 下共 **37 个** `probe_*.gd`（另有一份公共夹具 `probe_kit.gd`）。
其中约 22 道是正式验收闸，其余是素材录制 / 目视辅助（`probe_promo_*`、`probe_demo_record`、
`probe_camcheck`、`probe_gamefeel` 等）。

**必须按运行模式分成两批，混跑会假红：**

```bash
# A. headless 安全（纯逻辑 / 场景构建）
for p in golden scene blueprint sim grid flow scenario world privacy rogue rogue_ui; do
  "$GODOT" --headless --path "$P" -s "res://tests/probes/probe_$p.gd"
done

# B. 必须窗口模式（涉及屏幕坐标 / 渲染纹理，headless 下必然失败或空转不退出）
for p in sync input hud ui_flow smoke shots audio asset model orient save touch intro; do
  "$GODOT" --path "$P" -s "res://tests/probes/probe_$p.gd"
done
```

判据统一是输出 `[TAG] checks=N bad=0` 且 `[TAG] PASS`。

### 3.4 静态校验（Python，cwd = 项目根）

| 命令 | 校验什么 | 通过判据 |
|---|---|---|
| `python tools/check_shots.py` | 截图的尺寸 + 关键色族统计（非逐像素） | exit 0 + `[SHOTS] PASS` |
| `python tools/check_ui_lint.py` | UI 守规 L1–L4（样式必须走 `ui_style.gd` 工厂） | exit 0 + `[UI-LINT] PASS` |
| `python tools/verify_glb.py` | glb 结构自洽 + bind pose 数学自证 + LOD 各级顶点数 | 退出码 + 逐资产报告 |

### 3.5 导出

预设名固定两个：`Windows Desktop` → `export/game.exe`，`Android` → `export/reroute.apk`。

```bash
"$GODOT" --headless --path "$P" --export-release "Windows Desktop" "$P/export/game.exe"
"$GODOT" --headless --path "$P" --export-release "Android" "$P/export/reroute.apk"
```

两条硬规矩：

1. **导出完成后 Godot 进程不自动退出。** 判完成看 `export/` 产物的 mtime 连续两次相同，
   别等进程结束。单次导出约 10 分钟，别设短超时。
2. **Windows 每次重出都要复签**：`powershell -ExecutionPolicy Bypass -File tools/sign_windows_exe.ps1 -ExePath export/game.exe`。
   `game.pck` 不需要签名。

### 3.6 包内自证

导出物自带 33 条断言（引擎/构建模式 → 30 个 mp3 与中文字体是否进包 → 黄金回放 16 指纹 →
确定性复跑 → 主场景构建 → 音频接口 → UI 样式工厂一致性）：

```bash
"$P/export/game.exe" --selfcheck
```

通过输出 `[SELFCHECK] PASS` + exit 0。这是**判断包体好坏的主判据**，优先于任何外部日志。

---

## 四、使用示例

### 示例 1 · 确认改动没破坏模拟行为（改 `sim/` 后必跑）

```bash
"$GODOT" --headless --path "$P" -s res://tests/run_tests.gd
"$GODOT" --headless --path "$P" -s res://tests/probes/probe_golden.gd
```

`probe_golden` 拿种子 `20261003` 回放 6400 tick，逐位比对 16 个指纹（每 400 tick 一个）。
**指纹漂了先怀疑实现，不是怀疑基线。**

### 示例 2 · 确认改动没弄坏画面（改 `game/` 后）

```bash
"$GODOT" --path "$P" -s res://tests/probes/probe_sync.gd
"$GODOT" --path "$P" -s res://tests/probes/probe_shots.gd
python tools/check_shots.py
```

第二条**不能加 `--headless`**。第三条是 Python 脚本、没有运行模式概念，但必须在窗口探针跑完之后
执行——它读的是探针刚产出的截图。

### 示例 3 · 出双端包并自证

```bash
"$GODOT" --headless --path "$P" --export-release "Windows Desktop" "$P/export/game.exe"
"$GODOT" --headless --path "$P" --export-release "Android" "$P/export/reroute.apk"
powershell -ExecutionPolicy Bypass -File tools/sign_windows_exe.ps1 -ExePath export/game.exe
"$P/export/game.exe" --selfcheck        # 期望 [SELFCHECK] PASS / checks=33 bad=0
```

Android 那条需要先注入三个 `GODOT_ANDROID_KEYSTORE_RELEASE_*` 环境变量，否则导出的包是未签名件。

### 示例 4 · 游戏内操作

| 输入 | 行为 |
|---|---|
| `WASD` | 相机平移 |
| 鼠标右键拖拽 | 跟手平移 |
| `Q` / `E` | 旋转 |
| 滚轮 | 缩放（0.6–1.8×） |
| `TAB` | 威胁热层 |
| `Esc` | 暂停 / 返回上级 |

触屏：单指平移、双指缩放旋转、点按建造。存档 3 槽位写 `user://save_slotN.json`，
设置写 `user://settings.cfg`。

### 示例 5 · 资产转换（仅在需要重转模型时）

母版资产已不在本仓。`tools/convert_all.py` 的 `SRC` 指向 `reroute-maker/assets`，
需先从备份 bundle 还原母版才能跑：

```bash
git clone <待补：母版备份 bundle 路径> <待补：还原目标目录>
python tools/convert_all.py
```

---

## 五、关键配置说明

### `project.godot`

| 键 | 值 | 为什么这么设 |
|---|---|---|
| `run/main_scene` | `res://game/app/main.tscn` | 唯一入口；隐私门与开屏都在它下面装配 |
| `display/window/size` | 1280×720 | 基准视口 |
| `display/window/stretch/mode` | `canvas_items` + `aspect=expand` | 宽高比不锁死，适配 16:9 / 16:10 / 20:9 / 4:3 |
| `window/handheld/orientation` | `4` | Android 横屏 |
| `dotnet/project/assembly_name` | `RerouteGodot` | **必须 ASCII**——MSBuild 按 GBK 读 `.sln`，中文名会乱码导致编译失败 |
| `editor_plugins/enabled` | `res://addons/godot-mcp/plugin.cfg` | 编辑器自动化插件，导出时已排除 |

### `export_presets.cfg`

| 项 | 值 / 说明 |
|---|---|
| `exclude_filter` | `tests/*, shots/*, tools/*, addons/godot-mcp/*, docs/*, logs/*`——探针、截图、工具、插件源码**不进包** |
| `include_filter` | `assets/fonts/OFL.txt, THIRD-PARTY-NOTICES.txt`——许可文件必须随包 |
| Windows `binary_format/architecture` | `x86_64` |
| Windows `binary_format/embed_pck` | `false` → `game.exe` 与 `game.pck` 必须**同目录** |
| Android `package/unique_name` | `com.reroute.game` |
| Android `version/code` / `version/name` | `2` / `1.0.1` |
| Android `architectures/*` | `arm64-v8a=true`、`x86_64=true`、`armeabi-v7a=false`——**C#/.NET 不支持 v7a**，无法裁剪 |
| Android `texture_format` | `s3tc_bptc=false`、`etc2_astc=true` |
| Android `keystore/*` | **六字段全空**，签名只能靠环境变量注入 |

### 冻结项（改这些 = 改产品判据）

| 冻结物 | 位置 | 当前值 |
|---|---|---|
| 黄金指纹 | `sim/golden_baseline.gd` | 16 条（tick 400..6400），种子 `20261003` |
| 剧本指纹 | `sim/scenario.gd` `fingerprint()` | `0x7dea2b02`（默认种子路径） |
| 存档 schema | `sim/canon.gd` `STATE_SCHEMA` | **7**（工作区）/ **6**（HEAD `ec84f1c`） |

> ⚠️ **这里有一处未提交的变更，别忽略**：`git status` 显示 `sim/canon.gd` 是 `M`，
> 工作区已改到 **7**，HEAD 还是 **6**，而线上包（V-20261021 / 1.0.0）是从 schema 6 的代码构建的。
> 带 7 的包一旦覆盖发布，**玩家现有存档会全部被拒载**。
> 三处文档口径也不统一：`AGENTS.md` 写 6（与 HEAD 一致）、`CLAUDE.md` 写 5（更旧）、代码工作区是 7。
> 动 schema 之前先把这三处对齐。

> schema 不匹配的存档会被 `sim/save.gd` 直接拒载，这是故意的。

真要改基线：说明为何必须改 → 重跑 `probe_golden` 采新值 → **同一次提交里**更新基线 + 写决策记录。
**禁止为了让探针变绿而改基线。**

### 代码风格

`.editorconfig`：全局 UTF-8 + **LF 换行** + 去行尾空格 + 文件末尾留空行；`*.gd` 用 **Tab** 缩进、
行宽 ≤100；`*.py` / `*.cs` 用 4 空格；`*.md` 不套行宽、且**不 trim 行尾空格**（Markdown 里那是硬换行语法）。

`.gitattributes` 是 `* text=auto eol=lf`，但 `addons/**`、`logs/**` 固定 CRLF。
判行尾只认 `git ls-files --eol`——本机 `grep -cP '\r$'` 会**静默返 0**，拿它当判据会得出「没有 CR」的假结论。

---

## 六、常见问题

**Q：`--headless` 下探针全红，是不是代码坏了？**
不是。`--headless` 的根视口只有 64×64，凡涉及屏幕坐标或渲染纹理的探针（`sync` / `input` / `hud` /
`ui_flow` / `smoke` / `shots` / `audio` / `asset` / `model` / `orient` / `save` / `touch` / `intro`）
**必须窗口模式**跑。加 `--headless` 必然假红或空转不退出。

**Q：命令跑完没有任何输出。**
用了普通 `.exe` 而不是 `_console.exe`。普通变体不往 stdout 写东西。

**Q：探针看起来「挂起」了，一直不退出。**
大概率不是死循环，是**越界读中止了 `_initialize`，导致 `quit()` 没执行**。
判「挂起」之前必须把 stderr 重定向到文件再看：

```bash
"$GODOT" --headless --path "$P" -s res://tests/probes/probe_xxx.gd 2> /tmp/err.txt
```

**Q：导出命令跑完进程不退。**
预期行为，不是卡死。判完成看 `export/` 产物 mtime 是否连续两次相同。

**Q：Godot 报分析器错误、实例化直接挂起且零输出。**
检查是不是在 `class_name X` 的脚本内部写了 `X.new(...)` 或 `load("res://自身路径")`。
Godot 4.7.2 的分析器会编译期无限递归。**自测/自检代码必须放类外。**

**Q：`:=` 推断报类型错误。**
不要对无类型数组访问用 `:=`（如 `head[i]` / `off[k]` / `dist[p]`）。一律显式标注类型，或先判 `size()`。

**Q：数组原地 compact 报类型错。**
`arr[i] = arr[j]` + `resize()` 这条路在 GDScript 里走不通，建新数组。

**Q：Lua 母版里的 `%` / `//` / `>>` 直译过来结果不对。**
必须走 `sim/lua64.gd` 的 shim：`%` → `Lua64.mod`（向下取整）、`//` → `Lua64.idiv`、
`>>` → `Lua64.lshr`（逻辑移）。Lua 的 `%` 不是 C 的截尾取余。

**Q：Windows 双击提示「无法验证发布者」。**
自签证书（`CN=Reroute`）不在系统信任链里，正常现象。点「更多信息」→「仍要运行」。

**Q：改了 `sim/` 后 `probe_golden` 红了，直接把基线改成新值行不行？**
不行。先怀疑实现。基线是判据，不是缓存。

**Q：截图校验绿了，是不是画面就对？**
不是。`check_shots.py` 做的是尺寸 + 关键色族**统计**判定，不是逐像素比对。
画面结论必须有人肉眼看过截图才算数——本工程多次出现过「日志全绿、像素是假的」。

---

## 七、已知限制

| # | 限制 | 影响 |
|---|---|---|
| 1 | **无 CI** | 所有闸都是本地 CLI 手动跑，没有自动化兜底；包体 300MB 级、需 keystore，也不适合塞进 CI |
| 2 | **Android 只能 arm64-v8a + x86_64** | C#/.NET 不支持 `armeabi-v7a`，32 位 ARM 设备装不上；APK 约 312 MB |
| 3 | **字体未子集化** | `NotoSansSC-Regular.otf` 是全字库（约 8.2 MB），是包体最大的单点优化空间，但需要动资产 |
| 4 | **无真机测试设备** | Android 验证靠 MuMu 模拟器 + adb。模拟器跑得起来**不等于**真机没问题，结论只能写「模拟器可/不可复现」 |
| 5 | **平台已封锁包体更新** | 2026-10-21 起禁止上传/更新包体，官方口径「11 月底入围奖公布后」开放。评审期（10-25 ~ 12-03）内任何修复都无法上线 |
| 6 | **IAA 变现链路未实装** | 代码里没有任何广告 SDK 接入。赛事规则禁止赛期接广告，这条是刻意的，不是遗漏 |
| 7 | **肉鸽模式是竖切** | 5 层 × 20 波已可玩，但奖励池只有 8 张、等权抽取；`RewardPool` 的稀有度字段留作后续扩展，当前不生效 |
| 8 | **世界生成 2.0 视觉联动待做** | 玩法层已自由化（非默认种子走 `_generate_freeform`），但岩脊/山体/视觉动机池尚未跟随自由布局 |
| 9 | **存档 schema 处于半改状态** | 工作区 `STATE_SCHEMA=7` **未提交**，HEAD 是 6，线上包也是 6。带 7 的包一发布，玩家存档全部作废——发布前必须先决定要不要这么改 |
| 10 | **`export/` 不进库** | 仓库里没有可执行包。要跑起来必须自己装引擎、自己导出 |
| 11 | **母版资产不在本仓** | `tools/convert_all.py` 依赖 `reroute-maker/assets`，该工作树已删除，只能从备份 bundle 还原 |
| 12 | **`addons/godot-mcp` 是编辑器专用** | 它只用于编辑器自动化，导出时被排除；不影响运行，但会让人误以为运行时依赖它 |

---

## 附录 A · 待补清单

按出现顺序，需要你填的共 **14 处**（下表 13 行，第 11 行含两个变量）：

| # | 位置 | 待补内容 |
|---|---|---|
| 1 | §一 | 商店页地址 |
| 2 | §二.1 | Godot 4.7.2 mono 下载地址 |
| 3 | §二.1 | Godot 安装路径 |
| 4 | §二.2 | 仓库地址 |
| 5 | §二.2 | 本地目录 |
| 6 | §二.4 | Python 解释器路径 |
| 7 | §二.5 | Android SDK 路径 |
| 8 | §二.5 | JDK 路径 |
| 9 | §二.5 | keystore 路径 |
| 10 | §二.5 | 签名环境变量文件路径 |
| 11 | §三.1 / 各示例 | `$GODOT` 与 `$P` 两个变量 |
| 12 | §四.5 | 母版备份 bundle 路径 |
| 13 | §四.5 | 还原目标目录 |
