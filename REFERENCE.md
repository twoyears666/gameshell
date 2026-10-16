# REFERENCE — 参考来源与完成度说明

本文件遵守**诚实原则**：
- 明确写出参考了什么软件、参考了哪一部分；
- **凡是没有完整实现的功能，一律直接写明「未完成」**，不做夸大、不留模糊空间。

---

## 1. 参考的软件

| 软件 | 参考部分 | 说明 |
| --- | --- | --- |
| **盖世游戏 / GameHub**（App Store，应用介绍页） | 界面视觉语言与信息结构 | **仅参考外观与布局思路**，用于确定本项目的 UI 壳形态 |
| **PlayStation 5 系统首页** | 首页第一排的横向方块行布局与聚焦表现 | 仅参考「一排大号方块卡片、聚焦项放大并高亮、其余变暗」的呈现方式 |
| Apple **GameController** 框架文档 | 手柄输入接入方式 | 使用官方 API，非第三方代码 |
| **RetroArch** | 「系统（system）」的划分与扩展名归类思路 | **只参考概念与命名**；**明确不借鉴它的触屏 UI**（用户要求），也**不**采用它「外挂 libretro 动态库」的加载方式 |
| **Delta / manic emu** | 虚拟按键（十字键 / A·B / START·SELECT / 肩键）的布置与手感 | 仅参考操控布局；按键**全部由本项目用 SwiftUI 自绘**，没有复制其代码/资源 |
| **MeloCafe** | Wii U 在 iOS 上的接入方式 | **尚未接入**，仅作为后续接入时的参考 |
| **mGBA**（`Vendor/mgba`，MPL-2.0） | 直接调用其 C API，提供 GBA / GB / GBC 模拟 | **已真实接入**：源码放进 `Vendor/mgba`，CI 交叉编译成 arm64 静态库链接进主二进制——这不是「参考外观」，是真正在用它的源码 |
| **Nestopia**（`Vendor/nestopia`，GPL-2.0-or-later） | 直接调用其 C++ API（`Nes::Core::Api`），提供 NES / Famicom 模拟 | **已真实接入**：同上，源码入库 + CI 交叉编译成静态库；不用它给 RetroArch 用的 libretro 前端 |
| **Mesen-S**（`Vendor/mesens`，GPL-3.0） | 走它的 **libretro 前端形态**（`Libretro/libretro.cpp` 已是核心侧实现），提供 SNES / Super Famicom 模拟 | **已真实接入**：源码入库（182 个源文件，源清单照抄上游 `Libretro/Makefile.common`）+ `-DLIBRETRO` 交叉编译成静态库。宿主侧只用它的 libretro 契约，**没有复制 RetroArch 的任何代码** |
| **Snes9x** | 原计划用它做 SNES | **不接入**：其许可证为「非商用专用」（不是开源许可、与 GPL-3.0 不兼容），因此不引入其源码 |

> 除了盖世游戏 / GameHub / PS5 的「结构与视觉风格」，以及 mGBA / Nestopia / Mesen-S 这种**直接链接进来的源码**，
> 其它条目都只用于「思路与概念」层面的参考，**没有复制其代码、图片、字体或资源文件**。

> 参考范围严格限定为「**结构与视觉风格**」。
> 本项目**没有**复制盖世游戏 / GameHub / PlayStation 的任何代码、图片、字体或资源文件。

### 具体参考了哪些部分

**现在仍在用的：**

1. **整体配色**：近黑背景（`#0B0B10`）、`#1B1B20` 卡片、`#2A2A30` 细描边、白色主文本、`#9AA0A6` 次文本。
2. **强调色用法**：橙色 `#FF7A18` 用于主按钮（现在的用途是顶栏「添加」按钮）。
3. **首页第一排（PS5 风格）**：正方形大卡片横向滚动；聚焦项（默认第一个，指针悬停时切换）放大到 1.0 并加白色高亮描边与投影，其余缩小到 0.93、透明度降到 0.72；卡片底部渐隐遮罩上叠加游戏名与平台，支持手柄的条目额外显示一个手柄图标。
4. **响应式（部分）**：方块尺寸随水平 size class 变化（紧凑 150 / 常规 190）。

**参考过、但本项目已移除、不再提供的：**

> 下面是早期版本参考过、后来按「只要主界面，不要杂七杂八功能」的要求**主动删掉**的部分，如实列出以免误解。

5. **首页顶部的圆角搜索框** —— **已移除，不提供**（没有搜索功能）。
6. **首页「最新资讯」区块** —— **已移除，不提供**（没有资讯功能）。
7. **评分徽章**（半透明底 + 星标 + 分数）—— **已移除，不展示**（`rating` 字段仍能被解析入库，但界面不显示）。
8. **榜单页**（横幅 + 热门榜 / 最新榜 + 分类 chips + 名次行）—— **已移除，不提供**。
9. **详情页**（封面 + 标题 + 标签 chips + 介绍 + 底部操作栏）—— **已移除，不提供**。
10. **底部标签栏**（首页 / 游戏库 / 榜单 / 我的）—— **已移除，不提供**；现在**只有一个主界面**（外加一个自绘的设置页覆盖层，不是独立标签页）。
11. **独立的游戏库页 / 分类筛选 / 关键词搜索** —— **不提供**；「游戏库」现在作为主界面的一个分区存在（与「最近游玩」顶排同页），没有分类筛选与搜索。

---

## 2. 已实现（可用）

| 功能 | 状态 | 位置 |
| --- | --- | --- |
| 深色主题设计令牌集中管理（颜色/圆角/间距/字号/尺寸） | ✅ 已实现 | `Sources/UI/Theme.swift` |
| **只有一个主界面**（无标签栏 / 无榜单 / 无我的 / 无详情 / 无搜索），内含「最近游玩」顶排 + 「游戏库」分区 | ✅ 已实现 | `Sources/UI/Screens/HomeView.swift` |
| **App 内添加 URL**（顶栏「添加」→ 填名称 + URL → 保存，写入沙盒） | ✅ 已实现 | `HomeView.addButton` + `AddGameForm.swift` + `AppState.addGame` |
| **长按方块卡片删除条目**（自绘确认浮层） | ✅ 已实现 | `SquareTileCard.onLongPress` + `AppState.confirmRemoval` |
| 用户清单持久化到沙盒 `Documents/games.json`（重启后仍在） | ✅ 已实现 | `GSGameManifest.persistToUserStore` |
| 游戏清单 JSON 驱动（UI 零硬编码游戏，**默认清单为空、不内置任何游戏**） | ✅ 已实现 | `Resources/games.json` + `GSGameManifest` |
| URL 驱动启动（WebView 加载 `http(s)`） | ✅ 已实现 | `PlayerView.swift` |
| 非 `http(s)` 的 URL 交给系统唤起对应 App（如 `steam://`） | ✅ 已实现 | `AppState.openExternally` |
| 首页方块行（聚焦放大 / 高亮描边），现服务于「最近游玩」与「游戏库」两个分区 | ✅ 已实现 | `HomeView.LibraryTileRow` + `SquareTileCard` |
| 清单为空时的空态引导 | ✅ 已实现 | `HomeView.emptyState` |
| **顶排「最近游玩」**（最多 10 个，按最后一次游玩时间倒序，条目被删则自动跳过） | ✅ 已实现 | `GSPlayHistory` + `AppState.refreshRecent` |
| **「游戏库」方块行**（URL 条目 + 模拟器 ROM 混排，一行横向滚动） | ✅ 已实现 | `HomeView.LibraryTileRow` + `LibraryItem.swift` |
| **URL 条目导入本地图标**（「添加」里选图片，写入沙盒 `Documents/Icons/`） | ✅ 已实现 | `AddGameForm.swift` + `GSIconStore` |
| **模拟器 ROM 自动抓取官方封面**（libretro-thumbnails `Named_Boxarts`，命中即缓存到 `Documents/Covers/`） | ⚠️ 待实机验证（联网抓取，本机无 iOS SDK，端到端未验证） | `GSCoverFetcher` + `AppState.refreshROMCovers` |
| **设置页：三端键位**（触屏缩放 / 透明度 / 按键簇显隐、键盘、手柄；改完即生效并持久化） | ✅ 已实现 | `SettingsView.swift` + `GSKeyMapping` |
| **设置页：触屏布局编辑器**（拖拽移动每一簇、双指或滑杆调整大小；入口**只在设置页**，游玩界面不可编辑） | ✅ 已实现 | `TouchLayoutEditor.swift` + `VirtualControls.swift` + `GSKeyMapping` |
| 模拟器内三端按键转发（触屏虚拟手柄 + 硬件键盘 + 手柄 → 单一 `GSButton` 位掩码 → 核心） | ✅ 已实现 | `EmulatorInputCoordinator.swift` + `KeyboardCapture.swift` + `GSInputManager` |
| 深链 `gameshell://home / open / play`（`search` 已移除，收到时提示） | ✅ 已实现 | `GSGameLauncher.m` + `GameshellApp.swift` + `AppState.handle(url:)` |
| 自绘浮层（toast / confirm / 表单），**不使用系统弹窗** | ✅ 已实现 | `Sources/UI/Overlay/` |
| 手柄在线探测与热插拔（GameController） | ✅ 已实现 | `GSInputManager.m` |
| 键鼠在线探测（GCKeyboard / GCMouse，iOS 14+） | ✅ 已实现 | `GSInputManager.m` |
| GitHub Actions CI（iOS 真机 + macOS 编译） | ✅ 已实现 | `.github/workflows/build.yml` |
| IPA 打包（`Payload/Gameshell.app` → `.ipa`） | ✅ 已实现（**ad-hoc 自签名**，非开发者证书签名） | `.github/workflows/build.yml` |
| TrollStore 用的 `.tipa` | ✅ 已实现（在最小 entitlements 之上带 **TrollStore 原生 JIT entitlements**，见下） | `.github/workflows/build.yml` + `Signing/Gameshell-iOS-JIT.entitlements` |
| **模拟器：ROM 导入**（App 内文件选择器 → 复制进沙盒 `Documents/ROMs/<系统>/`，重名加序号不覆盖） | ✅ 已实现（iOS） | `Sources/Core/GSROMLibrary.m` + `Sources/UI/Overlay/ImportROMSheet.swift` |
| **模拟器：GBA / GB / GBC 实机模拟**（mGBA 静态链接进主二进制） | ✅ 已实现（iOS） | `Sources/Core/GSMGBACore.m` + `Sources/Core/GSEmulator.m` |
| **模拟器：NES 实机模拟**（Nestopia 静态链接进主二进制；256×240 RGBA 画面 + 单声道扩立体声 + 电池存档） | ✅ 已实现（iOS），CI 已确认 `libnestopia.a` 编出并链接通过 | `Sources/Core/GSNestopiaCore.mm` + `Sources/Core/GSEmulator.m` |
| **模拟器：SNES 实机模拟**（Mesen-S 静态链接进主二进制；XRGB8888 → RGBA8888 逐像素转换 + 可变分辨率重分配缓冲 + 32040Hz 交错立体声 + 宿主侧 SRAM 落盘） | ⚠️ **代码已写完、CI 编译链接通过，但尚未实机实测**（详见下方「诚实补一句」） | `Sources/Core/GSSnesCore.mm` + `Sources/Core/GSEmulator.m` |
| **模拟器：画面输出**（核心出 RGBA8888 → CGImage，`CADisplayLink` 按屏幕刷新率取最新帧） | ✅ 已实现（iOS） | `GSEmulator.m` + `EmulatorView.EmulatorFrameSource` |
| **模拟器：声音输出**（交错 int16 直接进 `AVAudioSourceNode`，无格式转换） | ✅ 已实现（iOS） | `Sources/App/GSAudioPlayer.swift` |
| **模拟器：自绘虚拟手柄**（十字键八向 + A / B + START / SELECT + L / R；每簇位置与大小由 `GSTouchClusterLayout` 归一化坐标决定，可在设置页调整） | ✅ 已实现（iOS） | `Sources/UI/Emulator/VirtualControls.swift` + `Sources/Core/GSKeyMapping.m` |
| **模拟器：ROM 并入游戏库**（统一方块行，卡片带系统徽标 / 封面）+ 设置页「核心接入状态表」 | ✅ 已实现（iOS） | `Sources/UI/Components/LibraryItem.swift` + `Sources/UI/Components/GameCard.swift` + `Sources/UI/Emulator/CoreStatusList.swift` |
| **模拟器：JIT 能力探测**（真的去 `mmap(MAP_JIT)` 试探）+ TrollStore 探测 | ✅ 已实现 | `GSJIT`（`Sources/Core/GSEmulator.m`） |
| **TrollStore 原生 JIT 自举**（带 `no-sandbox` 时，`__attribute__((constructor))` 抢在 `UIApplicationMain` 前 spawn 自身、子进程 `ptrace(PT_TRACE_ME)`，父子拿到 `CS_DEBUGGED` → `mmap(MAP_JIT)` 成立；照 Amethyst-iOS / UTM） | ⚠️ 代码已写完、CI 编译链接通过，**尚未实机验证**（本机无 iOS 工具链） | `Sources/Core/GSEmulator.m`（`GSJITBootstrapIfNeeded`） |
| **TrollStore tipa 内置 JIT entitlements**（**不再**用被封禁的 `dynamic-codesigning` / `com.apple.private.cs.debugger`；改用 `com.apple.private.security.no-sandbox` + `platform-application` + `storage.AppDataContainers`/`MobileDocuments` + 内存 / IOKit / mach-lookup 一套，照 Amethyst-iOS） | ✅ 已实现（⚠️ 代价：tipa 装好后**脱离沙盒**，`Documents` 可能不再解析到自己的容器，异常时需按 `HOME` 兜底；只签进 tipa，普通 IPA / macOS 不带） | `Signing/Gameshell-iOS-JIT.entitlements` + `.github/workflows/build.yml` |
| **模拟器：核心编译期降级**（某个核心没编出来 → 该项目如实标成「不可用」，不拖垮整个构建） | ✅ 已实现 | `Scripts/build_cores.sh` + `Sources/Core/GSBuiltCoresCompat.h` |

> **诚实补一句**：上表「已实现」指的是**代码已写完并进入 CI 构建**。
> GBA / NES 的画面 / 声音 / 虚拟手柄**尚未在真机上逐项实测过**（我这边没有可用的测试设备），
> 所以「能跑起来」目前只能保证到「构建通过、逻辑按核心文档对齐」这一层，**不宣称已经真机验证**。
>
> SNES（Mesen-S）也一样：本机既没有 iOS SDK 也没有 cmake，**无法在本地真机/模拟器上跑过**，
> 只能做语法预检（`clang -fsyntax-only`）与源清单比对，真正的编译验证交给 CI。
> 因此它现在标的是 **⚠️ 待实机验证**，而不是 ✅。

---

## 3. 未完成清单（诚实标注）

下列功能**尚未完整实现**：

| 功能 | 状态 |
| --- | --- |
| 账号登录 / 用户体系 | **未完成** |
| 云游戏串流 | **未完成** |
| 游戏下载与本地安装 | **未完成** |
| 本地模拟器内核（如 JVM / 兼容层） | **未完成** |
| 手柄 / 键盘按键**转发进网页内游戏**（当前只做在线探测；转发只实现了「进模拟器核心」，网页游戏仍不转发） | **未完成** |
| 蓝牙键鼠按键转发进网页游戏 | **未完成** |
| 主界面方块行的手柄 / 键盘焦点导航（当前只有指针悬停聚焦，手柄不能左右移动焦点，也不能用手柄选中启动） | **未完成** |
| **App 内编辑已有条目**（现在只能添加和删除，不能改名称 / URL） | **未完成** |
| **清单的导入 / 导出**（只能通过 App 内添加或直接改沙盒 `Documents/games.json`） | **未完成** |
| **多排方块行 / 分组**（现在只有一排横向方块） | **未完成** |
| PS5 首页那样的动态背景氛围（当前只有纯色背景） | **未完成** |
| 收藏 / 心愿单 | **未完成** |
| 成就系统 | **未完成** |
| 云存档 | **未完成** |
| 主题包（自定义布局 / 配色 / 文本的可替换包） | **未完成**（当前仅把令牌集中，尚未做包加载） |
| 应用图标（`AppIcon` 资源为空） | **未完成** |
| 单元测试 | **未完成** |
| 正规签名的 IPA（Apple 开发者证书 + 描述文件，可直接装到未越狱设备） | **未完成**（CI 目前只产出 ad-hoc 自签名的 IPA / tipa，仅 TrollStore / 侧载工具可用） |
| App Store / TestFlight 分发 | **未完成** |
| 榜单 / 在线榜单接口 | **不提供**（榜单页已移除） |
| 资讯 | **不提供**（资讯区块已移除） |
| 分类筛选 / 关键词搜索 | **不提供**（相关页面已移除） |

### 模拟器核心接入进度

| 系统 | 核心（许可证） | 状态 |
| --- | --- | --- |
| GB / GBC / GBA | mGBA（MPL-2.0） | ✅ 已接入，静态链接进主二进制 |
| NES / Famicom | Nestopia（GPL-2.0-or-later） | ✅ 已接入，静态链接进主二进制（CI 已确认编出并链接通过） |
| SNES / Super Famicom | Mesen-S（GPL-3.0） | ✅ 已接入，静态链接进主二进制；⚠️ **尚未实机实测**（CI 验证编译链接，本机无 iOS 工具链）。原计划的 Snes9x 因「非商用许可」与整仓 GPL-3.0 不兼容，已排除 |
| NDS | melonDS（GPL-3.0） | **未接入**（只有空壳库 + `GS_HAVE_* 0`） |
| 3DS | Azahar 系（GPL-2.0） | **未接入**，且**需要 JIT** |
| Wii | Dolphin（GPL-2.0+） | **未接入**，且**需要 JIT** |
| Wii U | Cemu / MeloCafe 系 | **未接入**，且**需要 JIT** |

> 未接入的系统**仍然可以导入 ROM**（文件待在 `Documents/ROMs/<系统>/`），
> 点开时由 `GSSystem` 的 `coreIntegrated` 如实判定并提示「核心尚未接入」，不会假装能玩。

### 已实现但暂不展示的字段

`GSGame` 里的 `rating` / `summary` / `tags` 能被解析入库，但**当前 UI 没有展示**（评分徽章、标签 chips、详情介绍都已随详情页一起移除）。

### 关于 games.json

有两份清单：

1. **`Resources/games.json`（内置兜底）**：`games` 数组**默认为空**，App **不内置任何游戏**；
   早期演示用的 `bomberman-lite` 等条目已全部移除。
2. **`Documents/games.json`（沙盒用户清单）**：App 内「添加」写入的就是这份，启动时**优先读它**。

条目既可以在 **App 内添加**，也可以直接改沙盒里的那份 `games.json`。

---

## 4. 为什么是「壳」

本项目当前定位为**界面壳 + 启动通路**：
- 只有主界面（+ 一个自绘设置页覆盖层），把「游戏」抽象成一条 URL：接入新游戏**不需要改代码**，在 App 内点「添加」填一条 URL 即可（或直接改沙盒 `games.json`）；
  这条 URL 既可以是网页（`http(s)` → 内置 WebView），也可以是 `steam://` 这类**唤起本机 App** 的链接（交给系统打开）；
- 把视觉全部收敛到 `Theme.swift`，因此后续换皮 / 做主题包**不需要改视图逻辑**；
- 核心逻辑（清单、启动、输入）放在 Objective-C，方便后续接入更底层的原生能力。

真正的「玩游戏」体验（串流、内核、按键映射、存档等）属于上表的**未完成**部分，将逐步补齐。
