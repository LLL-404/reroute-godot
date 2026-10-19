# 《改道》Godot 工程 — AI 开发入口

> **权威文档永远是 [`docs/DEVELOPMENT-PLAN.md`](docs/DEVELOPMENT-PLAN.md)**。本文件只是给 AI 的
> **速查表与红线**，不复制权威文档内容；冲突时以方案为准。

64×64 塔防，核心机制「放墙改道」：敌人绕得越远、死时赏金越高（`reward + traveled>>3`）。
Engineering 保真度极高：模拟核心是**确定性**的，有 16 指纹黄金基线锁死行为（2026-10-17 六边化 + G2 后第四次重录）。世界为 **pointy-top odd-r 六边形 64×64**（奇行右移半格）。

---

## 一、目录（2026-10-15 整理后）

| 路径 | 管什么 |
|---|---|
| `sim/` | 模拟核心十二模块，纯逻辑、**无浮点、无渲染**：`lua64`(语义 shim) / `canon` / `rng` / `grid` / `flowfield` / `mapgen`(布局生成) / `scenario`(布局构造+校验) / `sim`(数值表) / `world` / `verify` / `golden_baseline` / `save`(存档编解码) |
| `game/` | 表现层，只读模拟：`main`(主循环/输入) / `view`(3D 门面) + 组件 `view_core`/`view_terrain`/`view_entities`/`view_audio`（D5-1 拆分 2026-10-15） / `models` / `blueprint` / `hud` / `screens`(五屏+确认弹窗) / `save_io`(槽位 I/O) / `user_settings`(音量/全屏) / `selfcheck` |
| `tests/` | 单测 106 例 + **21 个验收探针**（`tests/probes/`，公共夹具 `probe_kit.gd`，D5-2 2026-10-15；`probe_intro` 2026-10-17） |
| `tools/` | Python 工具：`check_shots.py` / `convert_all.py` / `umd2_to_gltf.py` / `verify_glb.py` |
| `assets/` | `audio/sfx`(30 mp3) / `fonts`(Noto Sans SC) / `models`(glb) / `icon`(图标五件套) |
| `docs/` | 开发方案（权威）、审计报告、`devlogs/` |
| `shots/` | 验收截图产物 + `store/` 详情页提审素材（AI 五图 + 实机图副本；已 `exclude_filter` 排除出包） |
| `logs/` | 闸的 stdout/exit 证据 |

## 二、分层纪律（**单向，不许反向**）

```
sim/   ←──  game/            （表现层读模拟，模拟层不知道表现层存在）
sim/   ←──  tests/           （单测驱动模拟）
game/  ←──  tests/probes/    （探针驱动表现层与整机）
```

- `sim/` **禁止** `require`/`preload` 任何 `game/` 下的文件。
- 唯一的写路径是 `main.gd` 调 `world.apply_command(...)`；`view.gd` 及其四组件绝对不许回写模拟状态。
- `view_entities.gd` 的插值缓存（`unit_nodes` 的 `px/py`、`death_fx`、`_height_rev`）是派生态，**不进指纹**。
- 白盒直写（`w.supply = ...`）只允许出现在 `tests/`，生产代码禁止。

## 三、跑闸（先读这个再动手）

```bash
GODOT="C:/G/game/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe"
P="C:/Users/Administrator/Documents/默认项目/reroute-godot"

# headless 安全：单测 + 模拟模块探针 + 场景构建
"$GODOT" --headless --path "$P" -s res://tests/run_tests.gd                    # 106 单测
for p in golden scene blueprint sim grid flow scenario world; do
  "$GODOT" --headless --path "$P" -s res://tests/probes/probe_$p.gd
done

# 必须窗口模式（涉及屏幕坐标/渲染纹理，headless 下必然失败或空转不退出）
for p in sync input hud ui_flow smoke shots audio asset model orient save touch intro; do
  "$GODOT" --path "$P" -s res://tests/probes/probe_$p.gd
done

python tools/check_shots.py    # 截图像素校验
```

**改完代码必须跑对应闸**，不要只跑能跑的那个。改 `sim/` 必须跑 `probe_golden`。

## 四、两条必须记住的铁律

1. **无头 CLI 用 `_console.exe` 变体**，普通 `.exe` 不输出 stdout。
2. **`--headless` 下根视口只有 64×64**。凡涉及屏幕坐标或渲染纹理的探针
   （`sync` / `input` / `hud` / `ui_flow` / `smoke` / `shots` / `audio` /
   `asset` / `model` / `orient` / `save` / `touch` / `intro`）**必须窗口模式运行**。

## 五、调试陷阱（都会伪装成「挂起」）

- **越界读会中止 `_initialize` → `quit()` 不执行 → 无头引擎空转**。判「挂起」前
  **stderr 必须重定向到文件**再看，别靠肉眼看窗口有没有反应。
- GDScript 数组越界是**硬报错**，不像 Lua 母版靠 nil-on-越界兜底。

## 六、基线冻结纪律（**最高优先级**）

以下三者是「判据即产品」，**禁止为了让某个探针变绿而修改它们**：

| 冻结物 | 位置 |
|---|---|
| 16 个黄金指纹 | `sim/golden_baseline.gd` |
| 剧本指纹 `0x7dea2b02` | `Scenario.fingerprint()` |
| `STATE_SCHEMA = 6`（六边化后；v5 旧档拒载） | `canon.gd` / `world.canonical_bytes()` |

漂移了先怀疑**实现**，不是怀疑基线。真要改：先说明为何必须改 → 重跑 `probe_golden` 采新值
→ **同一次提交里**更新基线 + 写决策记录。

## 七、移植/编码硬约束

- **类内禁自引用**：`class_name X` 的脚本内禁止 `X.new(...)` / `load("res://自身路径")`，
  Godot 4.7.2 分析器会编译期无限递归。自测/自检放类外。
- **`pad_idx` 用规范公式** `(y+1)*stride+(x+1)`（Lua 母版多 +1 靠 nil 兜底，此处不能）。
- **禁 `:=` 推断无类型 Array 访问**：一律显式类型或先判 `size()`。
- **数组原地 compact 会报类型错误**：建新数组，别 `arr[i]=arr[j]` + `resize`。
- **保留字/撞名**：`pass`→`pmap`、`set`→`set_cell`；Lua `--`→`#`；大 hex 字面量（≥2^63）
  被钳位报错 → 用带符号十进制。
- **语义 shim**（`sim/lua64.gd`）：`%`→`Lua64.mod`（向下取整）、`//`→`idiv`、
  `>>`→`Lua64.lshr`（逻辑移）。`*`/`+`/`<<`/位运算回绕与 Lua 一致，可直译。
- **确定性**：随机源只有 `World.rng`，禁 `randi()`/`randf()`；`sim/` 内禁浮点。

## 八、命名规范

| 对象 | 规范 |
|---|---|
| 文件 | `snake_case.gd` |
| 类名 | `PascalCase`（`class_name`） |
| 常量 | `UPPER_SNAKE` |
| 变量/函数 | `snake_case` |
| 私有成员 | 前缀 `_` |
| 探针 | `probe_<领域>.gd` → **`tests/probes/`** |
| 单测 | `test_<模块>.gd` → `tests/` |

## 九、已知待办

- `view.gd` 拆分（D5-1）**已完成（2026-10-15）**：972 行 → 206 行门面（`_ready` 组装 + 公共面转发）
  + 四组件 `view_core`(246) / `view_terrain`(243) / `view_entities`(418) / `view_audio`(116)。
  机制 = 组合 + 转发属性，外部 `view.xxx` 访问零变化、探针无需改路径；验收 = 拆分前后
  `probe_sync` 输出逐字节一致（已通过：SHA256 相同；全 19 闸 post 比照 pre 全绿）。
- 探针规整（D5-2）**已完成（2026-10-15）**：新增公共夹具 `tests/probes/probe_kit.gd`
  （`class_name ProbeKit extends SceneTree`：`check`/`fail`/`cmp_int`/`cmp_approx`/`cmp_v3`/`cmp_rect`/`finish`），
  17 探针全部 `extends ProbeKit`，输出统一为 `[TAG] checks=N bad=M` + `[TAG] PASS|FAIL`；
  重构前后 checks 数逐项一致（`probe_sync` 输出 SHA256 逐字节相同）；
  全 19 闸绿（证据 `logs/gates-20261015-d52/post/`）。夹具改动后需 `--import` 刷类缓存。
- 拖拽预览逐格（D5-3）**已完成（2026-10-15）**：`view_entities.show_ghost` 由「首尾单拉伸盒」
  改为**逐格方块**（各自贴合所在柱顶；`ghost_mi` 仍指首格）；斜线拖拽不再覆盖线外格。
  `probe_sync` 幽灵断言重写（盒数=格数 + 逐格世界位/缩放/染色；直连+斜线），
  负对照实跑（旧实现 + 新断言 = `bad=2 FAIL`）；`shots/ghost.png` 改斜线目视件（对角阶梯绿格）。
- 窗口缩放一致性（D5-4）**已完成（2026-10-15）**：`hud._layout()` 开头重算 `S`
  （布局与 `hit_regions()` 均取当前视口、恒同步，缩放后点击排除不再错位）；
  `probe_hud` 新增缩放断言 7 条（checks 56→63），负对照实跑（旧 hud + 新断言 = `bad=4 FAIL`）。
- 缺陷 A/B/C 修复 + 基线重录（2026-10-15，D6 缺陷段）**已完成**：A=`verify.gd` 命令表按 tick
  稳定排序（`sorted_commands` 防御 + `SCRIPT_COMMANDS` 重排，81 条不变）；B=`flowfield` 上界改
  可证明值 `14×w×h`；C=`world` 摊销补场中途改图整轮重启（`rebuild_rev`）。新增单测 5 例（83→88）。
  **重录结果：世界于 tick 4926 核心被毁判负，指纹 16→12；B/C 单独实测指纹不变。**
  负对照 3 份 + 全 19 闸绿（证据 `logs/gates-20261015-d6abc/`，含 `_cmp-d54.txt`）；
  决策记录 = `golden_baseline.gd` 头注释 + 方案 §11.5。缺陷 D（围攻评分）留档待设计意图。
- 相机操控（2026-10-15）**已完成**：`WASD` 平移 / 右键拖拽跟手平移 / `Q/E` 旋转；
  纯表现层（`view_core` 的 `focus/yaw` 口径 + `main._update_camera`），标题/暂停/结算冻结，
  窗口缩放取景会重置平移旋转；`world_to_screen` 泛化为相机基投影（旋转后浮字仍准）。
  `probe_input` 断言 41→51；负对照实跑 `bad=5 FAIL`；全 19 闸绿（证据 `logs/gates-20261015-cam/`）。
- 世界 64² 重做（2026-10-16）**已完成**：玩法图 48²→64²（`Scenario` 重排：核心 (32,6)、
  三出怪口、盆地环 + 插口、岩脊 y40..42、咽喉双通道、中场矿 y20）；视觉去「包围圈」——
  `view_terrain` 重写为**单张水密顶点色网格**（场内 0.5m 细格邻格 max-blend 柱顶，
  场外渐进格距旷野 P(i)=32+i+0.06i²，外圈台阶柱带全删）；`blueprint` 场外改 slope 门控缓降坡；
  相机 scale 放宽 + 滚轮缩放（0.6–1.8×，HUD 区/暂停冻结）；Solid 融入地面（岩石色 + 1.6m）。
  **基线第二次重录：世界由 LOST@4926 变 WON@6400（核心余 784），指纹 12→16（400..6400）。**
  全 19 闸绿 + 负对照 2 份（证据 `logs/gates-20261016-world64/`）；`probe_scene`/`probe_input`
  新增结构/缩放断言；决策记录 = 方案 §11.7。
- UI 补全：存档 / 设置 / 退出 / 安卓返回（2026-10-16）**已完成**：新 `sim/save.gd`
  （encode/decode/inspect 四重校验；encode 遇摊销补场窗口先 `_rebuild_field_sync()`——
  确定性关键修复）+ `game/save_io.gd`（3 槽位 user://save_slotN.json）+ `game/user_settings.gd`
  （user://settings.cfg；BGM/SFX bus；全屏）；`screens.gd` 重写为五屏 + 确认弹窗；
  `main.gd` 接线读档/存档/退出/安卓返回（GO_BACK 通知 + `ui_cancel` 动作双入口，80ms 去抖）；
  `view_audio` 按 bus 路由。单测 88→100（`test_save.gd` 12 例）；新探针 `probe_save`(74)/
  `probe_touch`(29)；负对照 ×2（断存档接线→`[SAVE] FAIL`；关终审校验→单测 98/2 恰两条
  tamper 用例）；全 21 闸绿（证据 `logs/gates-20261016-ui/`）；决策记录 = 方案 §11.8。
- Android 管线 + 触屏 + DPI/安全区（D0-3/4、D1-1/2/4/5/6，2026-10-16）**已完成（真机装机待设备）**：
  SDK/JDK21/debug keystore 就位；`csproj` 改 net9.0；`project.godot` 增 `orientation=4` +
  `stretch canvas_items+expand` + ETC2/ASTC；`export_presets.cfg` 新增 Android 预设（`com.reroute.game`）；
  debug APK 导出成功且 `apksigner verify` 通过。触屏 = 引擎 `emulate_mouse_from_touch` 换算
  （**不写 ScreenTouch 分支**：`push_input` 旁路换算 / `parse_input_event` 走全链路，实测对拍逐字节一致）；
  `probe_touch` 29→39。安全区 = `hud.safe` + `set_safe_insets_override()`（probe_hud 63→69）；
  `probe_shots` 增 20:9/窄屏目视件；`check_shots.py` 25 项。负对照 ×3（nc-safe bad=5 /
  nc-touch   bad=4 / nc-pushinput bad=4）。证据 `logs/gates-20261016-d1/`；决策记录 = 方案 §11.9。
- 制造积分素材（D1-7，2026-10-16）**已完成**：Maker 绑定 `D:\G\game\games\reroute-maker`
  （App「改道」）；图标 icon2_core → `assets/icon/` 五件套（`config/icon` + Windows/Android
  导出预设）；10 音效入库并接线（`view_entities`：波次号角换 `wave_horn`、建筑四路
  [放塔/放墙帧内去重、拆除、塔开火=cooldown 回跳]、核心受击 30t 节流；`main._check_outcome`
  结算链 + `bgm_settlement`）。`probe_audio` 38→56、`selfcheck` 29 mp3；负对照 bad=3；
  全 21 闸绿（证据 `logs/gates-20261016-d17/`）；决策记录 = 方案 §11.10。
- 详情页素材（D2-5，2026-10-16）**已完成**：AI 五图（头图 `store_header` + 宣传图
  `promo_redirect` / `promo_economy` / `promo_ambush` / `promo_barrage`，1920×1080）
  归置 `shots/store/`（+ 实机图 5 张副本：`game`/`heat`/`ghost`/`smoke_mid`/`game_20x9`）；
  登记 CREDITS §3.6；待用户上传。决策记录 = 方案 §11.11。
- 双端 release 打包（D2-1，2026-10-16 **包已双端出齐**）：Windows `export/game.exe` 已自签
  （`CN=Reroute`，材料在仓外 `D:\G\game\keystores\`，本机信任链 Valid；复签脚本
  `tools/sign_windows_exe.ps1`）+ `game.pck`；本机 **SAC=1 拦未签名 exe**——自证走
  `--main-pack export/game.pck --selfcheck`（22/0 PASS）；Android 正式包
  `export/reroute-release.apk`（keystore alias `reroute`，`GODOT_ANDROID_KEYSTORE_RELEASE_*`
  环境变量注入，apksigner = CN=Reroute；密码台账 `D:\G\game\keystores\signing.env` 勿入库）；
  单次导出 ~10min（勿短超时）。Windows 双击复测已通过（能启动）；Android 装机待设备。`logs/` 有 `.gdignore`。
  决策记录 = 方案 §11.12。
- 地图程序化生成 + 视觉算法升级（2026-10-16 晚）**已完成**：新 `sim/mapgen.gd` 变奏级布局
  （12 维参数域 + 盐重采样 ≤64 + 裸图路径长标定 548±15%，难度不漂移）；`Scenario.new(seed)`
  生成 + 校验；每局 `BASE_SEED + run_index`（与仿真 RNG 同源）；**基线第三次重录**
  （剧本指纹 0x02d81d2a→0x7dea2b02；16 指纹 400..6400；WON@6400 余 744）。视觉：
  `blueprint` 五次插值 / 域扭曲 / 脊状 / 台地 / 阈值化侵蚀 + 锚点 API（视觉对齐玩法布局；
  `ridge_y` / `basin_rect` 中心 / `core`）、`view_terrain` 坡度岩化 + 崖壁围合（RIM_BUMP 4.2）、
  灯光/调色提亮；单测 100→104；全 19 闸 + check_shots 绿（证据 `logs/gates-20261016-mapgen-post/`
  + `logs/gates-20261016-visual/`）；决策记录 = 方案 §11.14/§11.15。
  **包重出跟进：10-17 UI v2.1 后已双端重出（zip 顺带修复 10-16 混入史前 pck 的交付缺陷），见方案 §11.20。**
- 峡谷化第二/三步（2026-10-16 晚–10-17 晨）**已完成**：A=场内地面失踪根因修复
  （`_build_indices` 三角绕序倒置，world64 起即存在，雾色假地面——索引绕序对调）；B=第二步
  （干冲沟/脊状崖顶/4.5m 层理/豁口锚定 + fit 俯角 44°）；C=第三步改**开阔荒漠口径**（矮墙
  围界 RIM_BUMP 0.8、rim_h 1.1..1.7 沿埂、8 孤岩长丘斜率限幅、远山剪影压低、宽缓沙丘）。
  均纯视觉（指纹 0x7dea2b02 不变）；第三步全 21 闸绿（证据 `logs/gates-20261017-canyon3/`，
  第二步证据 `logs/gates-20261016-visual/`+`-final/`）；决策记录 = 方案 §11.16/§11.17。
- 历史审计报告（`docs/*-20261015.md`）按**快照原则保持原样**，不要顺着结构整理去改它们。
- 美术 pass（2026-10-17 晨）**已完成**：① 4 张 ambientCG CC0 地表纹理（Ground093C/Rock061，
  NormalGL，VRAM+mipmap）+ 全新 `game/terrain_ground.gdshader` 三平面双材质（沙/岩按顶点色
  a 权值混合，rgb 保持程序化三带色）；`view_core` 太阳 yaw 38°→10°、canyon 雾提亮；
  `check_shots` ghost 阈值 0.0003→0.0001（纹理后 AA 边缘差实测 0.00030）。② 矿格观感换
  `gold_ore.glb`（四视图 multiview 直出重建，10-04 概念件成品从未落地；convert_all.py SRC
  已修正 reroute-maker）：`models.spawn_ore` + selfcheck glb 5→6 + probe_asset 矿格断言更新
  （root 1.0 / inst ≈0.94）。全 21 闸绿（证据 `logs/gates-20261017-artfinal/`）；指纹不变。
  决策记录 = 方案 §11.17/§11.18；许可台账 = CREDITS §3.7 + THIRD-PARTY-NOTICES 第 2 节。
- 建筑三件 glb 化（2026-10-17 晨）**已完成**：Maker text2model 三件（wall_barrier/tower_
  ballista/core_jade）直出入库 + `models.spawn_building` + `view_entities` 建筑盒体拼接
  退役（spec §12 fallback 不再需要）；selfcheck glb 6→9、probe_asset 59→63。
  外部 21 闸全绿（除 golden——**归因另一 AI 会话正在实时修改 sim/（未提交半成品）的工作
  树污染**；干净 worktree f0033a6 复核 probe_golden PASS，与本轮无关；全 21 闸终值以
  sim 收敛后为主）。证据 `logs/gates-20261017-b3/`；决策记录 = 方案 §11.18（建筑段）。
- 六边化全换 + G2 每局地形变幅（2026-10-17）**已完成**：模拟核心换 pointy-top odd-r 六边形
  （`grid/flowfield/world/canon` schema 6，剧本指纹 0x7dea2b02 不变、路径长 548 在标定带）；
  表现层六棱板场区网格（"HexField"）/棱墙/幽灵/热层/拾取全换；G2 = 玩法模板池 T0..T4
  （`_generate_default` 字节级冻结默认种子，变幅只对非默认种子生效；咽喉行随列化 `c.y`）
  + 视觉动机池 3→6（ochre/slate/dusk，追加序位口径保 1..3 不变；**砍单序第一批已启用**，
  9~12 上限未扩满）；**第四次基线重录**（16 指纹全换、WON@6400 余 808/击杀 236/供给 621）。
  新探针 `probe_blueprint`(11)；全 21 闸 + `check_shots` 25/0 + 导出件 `--selfcheck` 22/0 绿。
  **双端包已重出**：Windows 已复签 + Android 305.9MB（CN=Reroute）。
  决策记录 = 方案 §11.19；开发者日志③**已发布**（2026-10-17，moment `860546275211218896`；
  正文留档 `docs/devlogs/03-*.md`）。
  **注**：Windows 自证以 `export/game.exe --selfcheck` 直跑为准（`--main-pack` 在 4.7.2
  模板不支持 path overrides，10-16 记录口径更正）。
- UI v2.1「帝王金黑」实装（2026-10-17）**已完成**：`hud.gd`/`screens.gd` 换肤（色板 token
  `gold/gold_hi/gold_lo/...` 增量、原 key 保留 → 探针动态读色零影响）+ 衬线
  `NotoSerifSC-Bold-Sub.ttf`（31 字形子集；`_serif_title` 逐字间距方案）；标题屏改 Civ6
  左列菜单式（渐变压暗帷幕；坑实录 = 浮点 `Color()` 白化必 Color8 + GradientTexture2D
  行 0=顶 `(0,0)→(0,1)`）；「继续对局」→「读档存档」（`btn_continue` 名不变）；
  probe_input §14 断言标定改机器无关口径（透视放大 1.43× 帧速漂移根因；负对照
  `pan_pixels` ×2 咬红后还原）。全闸绿（input 58/0、hud 69/0、ui_flow 39/0、touch 39/0、
  selfcheck 23/0、check_shots 25/0）；19 受击截图重出 + 目验 6 张通过。
- UI v2.2「质感层 + 样式工厂」（2026-10-17）**已完成**：新 `game/ui_style.gd` 唯一样式口
  （运行时 Theme + type variations 发射器 a：PrimaryButton/MenuButton/DarkCard/TitleBar/
  GoldSlider，按 S 缓存 hud/shell 共享；探针面仍走 override+meta 发射器 b）+ 质感 A 档
  六件（A1 光边 2px+底金 3px draw 闭包 / A2 投影 卡 12S·钮 6px / A3 金字影 α140 /
  A4 噪粒 5% 种子 20260415 / A5 暗角 α0.31@0.78 / A6 按下 +2px）+ C 六面板角饰线；
  **game 页禁挂氛围层**保 check_shots 契约。守规 `tools/check_ui_lint.py`（L1 裸色/
  L2 构造口/L3 变体名）+ selfcheck **31/0**（+8 工厂一致性）。全 21 闸绿 + 19 图重出 +
  双端包终版（exe 109,551,432 复签 Valid+pck 109,738,128+zip 183,606,300+apk 312,058,040；
  判据 = exe+pck 同目录 selfcheck，**exe 为字节确定性模板件、同哈希≠旧包**）。
  证据 `logs/gates-20261017-v22*`；决策记录 = 方案 §11.23 + UI-REDESIGN §7。
- LOD：源 4 级接回 + 屏占比切级（2026-10-17）**已完成**：`umd2_to_gltf.py` 每资产导出
  lod0..lod3 四 mesh 节点（蒙皮件共享 skeleton；逐级独立顶点缓冲——Godot 内置 LOD 为索引级，
  塞不进美术 LOD）；`verify_glb` 以源 `.mdl` 实测表断言逐级 verts/idx（非递增 + 蒙皮权重）；
  `models.gd` 按 `h=半径/(d·tan(fov/2))` 切级，阈值 = 源 `.lodgroup` screenSize
  0.20/0.08/0.03 × `LOD_AGGRESSIVENESS` 1.3 + 10% 迟滞防抖；静态件（覆盖/建筑）相机变换时刷；
  **回退开关：`LOD_AGGRESSIVENESS=0` → 恒 LOD0**；`mesh_aabb` 跳过 lod1..3 保校准口径
  （probe_asset 零改）；`probe_model` 裸实例化补 `bind_lod`（防四级叠模）。全 21 闸 +
  `check_shots` 25/0 绿（含主树 golden——并行 sim 半成品已收敛提交）。glb 8.0→21.0MB
  （+13MB；pck 以冻结包复测为准），**双端包需再重出**。证据 `logs/gates-20261017-lod/`；
  决策记录 = 方案 §11.21。
- TapTap 提审通道（2026-10-17）**冻结待启动**：app 958251 系制造/关卡（spark-only）型，
  不能承接常规双端包；已定**新建常规 app「改道」**（`package_type=windows`）承接双端常规
  发布，等地图算法更新 + 双端包终版重出后启动流水线——决策/证据/步骤见方案 §11.22。
  并行缺口：投稿讲解视频/实机录屏未产出；开发者日志需 ≥5 篇（现 3 篇）。
- 开屏动画（2026-10-17）**已完成**：`game/intro.gd`（CanvasLayer 30，确定性状态机
  `_process(dt)` 解析求值、无 Tween、t 硬钳 4.0s、终值 3.4s）；3D = SubViewport 晶体特写
  （core_jade LOD0 + 三灯 + 烘焙径向 Image 光团 + CPU 金尘）；2D = 金衬线「改道」逐字 +
  金线 + 副标语；P4 淡出透出标题屏（open_title 先行交叉溶解）；任意键/点击/触摸跳过
  （输入吞 + 25× 快收，Android 返回键顶部路由）；门控 = selfcheck/headless/`res://tests/`
  主循环三类自动跳过（探针零影响）；stinger mp3 29→30 mp3；boot_splash 灭默认 Logo。
  新 `probe_intro`(26) + 负对照（关输入吞 bad=3 FAIL）→ **全 22 闸** + check_shots 25/0 +
  lint 全绿。证据 `logs/gates-20261017-intro/`；决策记录 = 方案 §11.24。
  **性能提速轮（10-17 晚，用户反馈开屏不流畅/风扇狂转）**：主世界停画（第 1 帧暖机→
  第 2 拍隐藏→T_P3 恢复，退出安全网）+ 子视口 0.7× 拉伸 + 首拍预热帧（编译藏进黑幕）
  + dt 钳 0.1——开屏 p99 8.5→5.2ms、P0.5 绘制 52→30、vmem 247→227MB；probe_intro
  26→36（探针咬出「恢复后重复命中隐藏分支」真 bug 已修）；全 22 闸复验绿，证据
  `logs/gates-20261017-intro-perf/`。**菜单限帧（用户拍板：只限菜单/标题）**：
  `main._sync_fps_cap()` 每帧按 `_camera_free()` 判据同步 Engine.max_fps——标题/暂停/结算
  60fps、对局不限；idle/开屏 240fps→60fps 稳定钉死（开屏 max 17.2ms，编译尖峰被帧预算
  吸收）；probe_smoke 31→34；全闸复验绿。
- 地形改造自然化 T1（2026-10-18）**已完成**：填/挖落差边由直壁块改**剖面化自然壁**
  （`view_terrain`：圆唇 + 斜壁/渣坡 + 沉底坡脚 + 沿边 ihash 微扰；按模拟高度差分级 = Δ0 石阶 /
  Δ1 暖色可爬坡 / Δ≥2·实心·界外 层理崖壁 + 渣坡裙脚；顶面 100% 不动；非顶层点沿边 0.75×r
  外延闭角缝）；`terrain_ground.gdshader` 增 `rock_soft_up=1.05`（岩权区法线向上偏借顶光——
  **实测唯一有效墙面提亮杠杆**，顶点法线弯折对墙面光照零效果）+ `nrm_rock` 0.75 柔化。
  `probe_sync` +「自然化棱边」段（1829/0；负对照旧实现 + 新断言 = bad=1 FAIL 干净）；
  `probe_shots` +`game_closeup`（6 图）；`check_shots` 25→29；全 22 闸绿（证据
  `logs/gates-20261018-t1nat/`）；store 实机五图副本刷新。决策记录 = 方案 §11.25。
- 双端包重出（2026-10-18）**已完成**：开屏动画/开屏提速/菜单限帧/自然化 T1 四项增量后重出——
  `game.exe` 109,551,432B 复签 **Valid**（签名后与 v2.2 包**逐字节同哈希** `0539d11b…2285bc`，
  「exe = 内容无关模板件」第三次实证）+ 同目录 selfcheck **31/0**；`game.pck` 109,800,796B；
  `reroute-release.apk` 312,119,839B（apksigner v2/v3 true，CN=Reroute）；`reroute-windows.zip`
  183,669,125B（192 条目，testzip None-bad）。SHA：pck `153082ee…d9c5` / apk `44956252…f053` /
  zip `0a6a324f…c1992`。证据 `logs/gates-20261018-t1nat/export-*`；决策记录 = 方案 §11.26。
- 世界生成 2.0「玩法层彻底自由化」（2026-10-19）**已完成**：非默认种子 salt 0..47 走
  `_generate_freeform`（自由核心位 / 2~3 主口 / 盆地 / 岩野 / 微丘，裸图路径 548±15% 带内），
  48..63 保留 G2 模板兜底；默认种子 20261003 仍字节冻结（16 指纹 + 剧本指纹 `0x7dea2b02`
  零漂移）。波次读取面新增 `Scenario.wave_cell`（双主口历史口径 / 三主口按表序轮转）与
  `basin_cell`；自由指纹分支 `_fingerprint_freeform`（样本 20261004 = `0xf5f49e0c`）；
  存档不升 schema（`sc_fp` 拒绝旧变幅档）；`run_index` 跨会话持久化（`settings.cfg` 的
  `runs`，探针/selfcheck 门控）。单测 104→106（64 种子 sweep 重写 + 7 条自由图负对照 +
  `freeform-snapshot` 快照）；三只窗口探针的旧图/旧机耦合断言改数据驱动/墙钟口径
  （asset / audio / input）。全 21 闸 + `check_shots` 29/0 + lint + build 绿
  （证据 `logs/gates-20261019-worldgen/`）；决策记录 = 方案 §11.27。
  **拍 2（视觉联动：岩脊/山体/动机池随自由布局）待做**；TapTap 常规 app 流水线以此为前置。
- 设置 v3：完整视频设置 + 平台默认（2026-10-19）**已完成**（§11.28 的 v2 两行简版为演进记录）：
  设置页四组（音频/显示/画质/性能）+ 滚动容器；显示模式（全屏/无边框/窗口化，安卓隐藏）、
  分辨率（原生/1440p/1080p/900p/720p，安卓隐藏）、垂直同步、帧率 30/60/120/无限制（安卓 30/60）；
  画质预设低/中/高/极高 + 阴影/特效/抗锯齿（关/FXAA/TAA，安卓 Mobile 无 TAA）/后期（雾距倍率）/
  景深；性能渲染缩放、UI 缩放、画面亮度滑块。平台默认：PC 高画质/不限帧，安卓中画质/85% 渲染/
  60 帧（Android 默认 Mobile 渲染器 + ETC2/ASTC；触屏/安全区沿用 §11.9）。探针运行只应用音频
  （显示/画质/UI 不应用，保 gate 口径）。回归：save 77、touch 71（矩阵 54）、smoke 34、hud 73、
  ui_flow 39、sync 1845、scene 25、shots 6、check_shots 29、单测 107、lint PASS；
  证据 `logs/gates-20261019-settings3/`；决策记录 = 方案 §11.29。发布口径（2026-10-20）：
  Android 预设显式 ETC2（APK 实测无 S3TC、纹理双变体导出各取一份）；C#/.NET 不支持
  armeabi-v7a，最终包保持 arm64-v8a + x86_64 双 ABI（约 312MB），不做 ABI 裁剪。
- 截图覆盖扩展（2026-10-20）**已完成**：`probe_shots` 6→8 图（+`shots/game_tablet.png`
  1600×1200 4:3 平板 + `shots/game_16x10.png` 1280×800 16:10），`check_shots` 29→39；
  平板构图/HUD 目验通过；证据 `logs/gates-20261020-tablet/`。

---

*改动本文件前先确认没有和 `DEVELOPMENT-PLAN.md` 打架；两处都改。*
