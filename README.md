# Gameshell

一个 **iOS / iPadOS / macOS** 的 URL 启动器 **UI 壳**（shell）。
界面风格参考 **盖世游戏 / GameHub**、第一排方块行参考 **PS5 首页**，但**不使用其任何代码或资源**，仅参照「布局结构与视觉语言」。
本仓库以「壳 + 启动通路」为主；模拟器部分**已接入 mGBA、Nestopia、Mesen-S 与 melonDS**（GBA / GB / GBC / NES / SNES / NDS），其余系统**尚未接入**。
功能会持续往里加，**没实现的功能都在 [REFERENCE.md](REFERENCE.md) 里如实标注为「未完成」**。

- **主界面**：顶栏 + 顶排「最近游玩」（最多 10 个）+ 「游戏库」方块行（URL 条目与模拟器 ROM 混排）；另有**设置页**（触屏 / 键盘 / 手柄三端键位，触屏还能拖拽调位置与大小）
- **技术栈**：Swift（SwiftUI，UI 层）+ Objective-C（核心层）混合
- **游戏来源**：完全 **URL 驱动** —— 打开一个 URL 就等于打开一个游戏或 App；
  `http(s)` 用内置 WebView 打开，`steam://` 这类 scheme 交给系统**唤起对应 App**
- **App 内添加 URL**：主界面右上角「添加」，填名称 + URL 即可，写入沙盒后重启仍在（基础功能）
- **不内置任何游戏**：清单默认为空，所有条目都由你自己添加
- **模拟器 ROM 导入与模拟**：游戏库右上角「导入 ROM」，导入后点开卡片即用内置核心模拟；
  **不内置任何 ROM**，全部由你自己导入（App 内导入，或从「文件」App 拷进 `Documents/ROMs/<系统>/`）
- **已接入的核心**：**mGBA**（GBA / GB / GBC）+ **Nestopia**（NES）+ **Mesen-S**（SNES）+ **melonDS**（NDS / DSi）；3DS / Wii / Wii U **尚未接入**（如实标注，见 [REFERENCE.md](REFERENCE.md)）
- **游戏封面**：URL 条目可在「添加」时**导入本地图标**；模拟器 ROM 会**自动联网抓取官方封面**（libretro-thumbnails 的 `Named_Boxarts`），命中即缓存，未命中回退到系统徽标，不报错
- **键位设置**：右上角齿轮进设置页，可分别调整**触屏**、**键盘**、**手柄**三端键位，改完即生效并持久化；**三端都按系统分别配置，每个系统各有一套** —— 先选系统（GB / GBC / GBA / NES / SNES / NDS），触屏调缩放 / 透明度 / 各按键显隐，并在「编辑布局」里**逐个拖拽移动每个按键、调整其大小**（每个按键都是独立的，互不绑定；也可一键把某个大小应用到全部）；键盘 / 手柄也各自按系统分别绑定（同一系统里一个键只绑一个按钮）
- **虚拟手柄**：操控界面自绘（布局参照 Delta / manic emu），**不借鉴 RetroArch 的触屏 UI**；**按键按系统区分、且每个按键各自独立** —— 8 / 16 位机是十字键 + A / B + START / SELECT（GBA / SNES 另有 L / R，SNES 为四键菱形），NDS 则是 A / B / X / Y 四键菱形 + L / R + MENU + 可触摸的下屏
- **变速与即时存档**：顶栏档位按钮**循环切换 `0.5× / 1× / 2× / 4×`**（**加速时自动静音**）；顶栏「快照」打开 **4 个槽**（带时间戳）可**存 / 读 / 删**，**退出模拟器时自动写一份「自动存档」**（可在快照面板里读回 / 删除）（⚠️ 代码已写完、CI 编译链接通过，**尚未实机实测**）
- **第一排**：PS5 风格的横向方块行（聚焦项放大 + 白色高亮描边，其余缩小变暗）
- **输入**：**手柄**（GameController 框架，热插拔）与 **键鼠**都能被识别；模拟器内触屏 / 键盘 / 手柄三端按键会汇总成一份位掩码转发给核心
- **构建**：GitHub Actions CI（macOS runner：XcodeGen + xcodebuild）
- **主题**：所有颜色 / 圆角 / 间距 / 字号集中在 `Theme.swift`，便于后续做主题包

> 本项目的设计参考与「未完成功能诚实清单」见 [REFERENCE.md](REFERENCE.md)。

---

## 快速开始

本仓库**不包含** `.xcodeproj`（由 `project.yml` 生成），需要先安装 [XcodeGen](https://github.com/yonaskolb/XcodeGen)：

```bash
brew install xcodegen
xcodegen generate
open Gameshell.xcodeproj
```

命令行构建（与 CI 一致）：

```bash
# iOS / iPadOS（模拟器）
xcodebuild -project Gameshell.xcodeproj -scheme Gameshell \
  -configuration Release -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build

# iOS 真机（用于打包 IPA）
xcodebuild -project Gameshell.xcodeproj -scheme Gameshell \
  -configuration Release -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build

# macOS
xcodebuild -project Gameshell.xcodeproj -scheme Gameshell \
  -configuration Release -destination 'generic/platform=macOS' \
  CODE_SIGNING_ALLOWED=NO build
```

## CI 产物

每次推送到 `main` / `feat/**` / `fix/**`（或 PR 到 `main`），[.github/workflows/build.yml](.github/workflows/build.yml) 会在 `macos-15` 上跑完整流程并上传：

| 产物 | 内容 | 签名状态 |
| --- | --- | --- |
| `Gameshell-macOS` | macOS `.app` | **ad-hoc 自签名** |
| `Gameshell-IPA` | iOS 真机 `.ipa`（`Payload/Gameshell.app`） | **ad-hoc 自签名 + 最小 entitlements**，非开发者证书签名 |
| `Gameshell-TrollStore-tipa` | iOS 真机 `.tipa`：带 **TrollStore 原生 JIT entitlements**（`com.apple.private.security.no-sandbox` 等；**不再**用被封禁的 `dynamic-codesigning` / `com.apple.private.cs.debugger`），运行时会自我开 JIT | **ad-hoc 自签名 + TrollStore JIT entitlements**，非开发者证书签名 |

> ⚠️ **诚实说明**：CI 产出的 IPA / tipa 是 **未签名 + `codesign -s -` ad-hoc 自签名** 的包
> （普通 IPA 用 [Signing/Gameshell-iOS.entitlements](Signing/Gameshell-iOS.entitlements)，tipa 用 [Signing/Gameshell-iOS-JIT.entitlements](Signing/Gameshell-iOS-JIT.entitlements)），
> 只能通过 **TrollStore（巨魔）** 或侧载工具安装 / 重签，
> **不能**直接装到未越狱设备、也**不能**上架 App Store。
> 正规签名的 IPA 需要 Apple 开发者证书与描述文件，属于**未完成**部分（见 [REFERENCE.md](REFERENCE.md)）。
>
> ⚠️ **JIT 与沙盒的代价**：tipa **不再**使用被封禁的 `dynamic-codesigning` / `com.apple.private.cs.debugger`
> （它们在 **iOS 15 + A12 及以上**会让 App 启动即崩），改用 **TrollStore 原生方案**（照 Amethyst-iOS / UTM）：
> 签上 `com.apple.private.security.no-sandbox`（+ `platform-application` + `storage.*`）等 entitlement，
> 运行时由 App 自己 spawn 子进程 `ptrace(PT_TRACE_ME)` 拿到 `CS_DEBUGGED`，于是 `mmap(MAP_JIT)` 成立。
> **代价**：tipa 版本**脱离沙盒**，`Documents` 可能不再解析到 App 自己的容器（若真机发现路径异常需按 `HOME` 兜底）。
> 普通 IPA 不带这些项、保持沙盒；iOS 26+/TXM 机型仍需外挂 StikDebug。

安装注意：

- **系统要求 iOS / iPadOS 16.0 及以上**（`MinimumOSVersion` 由工程 `deploymentTarget` 决定）；低于此版本会装不上或启动即退。
- macOS 上的 `.app` 是 ad-hoc 签名，从浏览器下载后带有 quarantine 标记，需要先执行：

```bash
xattr -dr com.apple.quarantine /path/to/Gameshell.app
```

## URL 驱动

打开一个 URL = 打开一个游戏 / App。**App 内添加（基础功能）**：主界面右上角「添加」→ 填名称和 URL → 保存。

- 条目写入沙盒 `Documents/games.json`，下次启动优先读这份；内置的 `Resources/games.json` 只是**空的兜底清单**。
- **长按方块卡片**可以删除条目（自绘确认浮层，不用系统弹窗）。
- 单条记录的字段（见 `GSGame`）：

```json
{
  "id": "唯一 id",
  "name": "显示名称",
  "url": "https://example.com/game",
  "platform": "网页",
  "icon": "gamecontroller.fill",
  "controllerSupport": false
}
```

- `url`：URL 驱动的核心。
  - `http(s)` → 由内置 WebView 打开（网页 / 网页游戏）。
  - 其它 scheme → 交给系统打开，用于**唤起本机 App**，例如 `steam://`、`minecraft://`、`youtube://`。
  - 在 App 内添加时如果没写 scheme，会自动补 `https://`。
- `icon`：以 `http` 开头按远程图片加载，否则按 SF Symbol 名渲染。
- `rating` / `description` / `tags`：能被解析入库，但**当前 UI 没有展示**（详见 REFERENCE 的未完成清单）。

### 深链（URL scheme：`gameshell://`）

| 深链 | 作用 |
| --- | --- |
| `gameshell://open?url=https://example.com/game&name=示例` | 用 URL 直接开一个不在清单里的条目 |
| `gameshell://open?url=steam://run/123` | URL 是 `steam://` 这类时，交给系统唤起对应 App |
| `gameshell://play?id=<清单里的 id>` | 按 id 在清单里找到并打开 |
| `gameshell://home` | 关闭播放器，回到主界面 |

命令行验证：

```bash
# macOS
open "gameshell://open?url=https://example.com&name=示例"
```

## 模拟器（ROM 导入与模拟）

ROM **全由你自己导入**，App 不内置、也不下载任何 ROM。

### 导入（两种方式）

1. 主界面「模拟器 ROM」分区 → 点「导入 ROM」→ 从系统「文件」里选 ROM。
   选中的文件会被**复制**进沙盒 `Documents/ROMs/<系统>/`；重名自动加序号，**不覆盖**已有文件。
2. 直接用「文件」App 把 ROM 拷进 `Documents/ROMs/<系统>/`（已开启文件共享），回到 App 会自动扫到。

点开卡片即启动：整屏模拟画面 + 自绘虚拟手柄；长按卡片删除（只删 ROM 文件，同目录的 `.sav` 存档会保留）。

### 变速与即时存档

- **变速**：顶栏有一个档位按钮，点击**循环切换** `0.5× → 1× → 2× → 4×`。变速只改宿主的**帧节奏**
  （`frameIntervalNs = 1e9 / (fps × speed)`，核心每轮仍只跑一帧），所以慢放 / 快进都能用；
  **加速（>1×）时自动静音**（核心每秒产出的音频量随速度线性增长，宿主在 >1× 时直接丢弃音频样本）。
- **即时存档（快照）**：顶栏「快照」按钮打开覆盖层，共 **4 个槽**（每个槽显示时间戳），可**存 / 读 / 删**；
  另有 **「自动存档」** —— **退出模拟器时会自动写一份**（`auto.state`），并在快照面板里可以**读回 / 删除**。
- 存档落在沙盒 `Documents/States/<ROM>/`（手动槽 `slot-0.state`…`slot-3.state`，自动存档 `auto.state`）。
- ⚠️ **诚实标注**：变速与即时存档**代码已写完、CI 编译链接通过，但尚未实机实测**。
  另外 **NDS 在 DSi 模式下核心不提供即时存档**（`retro_serialize_size()` 返回 0），
  此时存档会**如实失败并给出提示**，不会假装成功。

### 各系统接入状态（诚实标注）

| 系统 | 认作的扩展名 | 计划核心（许可证） | 当前状态 |
| --- | --- | --- | --- |
| NES | `.nes` `.fds` `.unf` `.unif` | Nestopia（GPL-2.0-or-later） | ✅ **已接入** |
| SNES | `.sfc` `.smc` `.swc` `.fig` `.bs` | Mesen-S（GPL-3.0） | ✅ **已接入** |
| GB | `.gb` | mGBA（MPL-2.0） | ✅ **已接入** |
| GBC | `.gbc` | mGBA（MPL-2.0） | ✅ **已接入** |
| GBA | `.gba` `.agb` | mGBA（MPL-2.0） | ✅ **已接入** |
| NDS | `.nds` | melonDS（GPL-3.0） | ✅ **已接入**（拿得到 JIT 走 dynarec，拿不到自动退回解释器） |
| 3DS | `.3ds` `.cia` `.cci` `.cxi` `.app` | Azahar 系（GPL-2.0，**需 JIT**） | **未接入** |
| Wii | `.wbfs` `.iso` `.rvz` `.wia` `.dol` `.elf` | Dolphin（GPL-2.0+，**需 JIT**） | **未接入** |
| Wii U | `.wud` `.wux` `.rpx` `.wua` `.rpl` | Cemu / MeloCafe 系（MPL-2.0，**需 JIT**） | **未接入** |

> **为什么 SNES 不用 Snes9x**：Snes9x 的许可证是「非商用专用」
> （"freeware for PERSONAL USE only"，且 libretro 移植部分写明 "Under no circumstances
> will commercial rights be given"），它**不是开源许可、也与 GPL-3.0 不兼容**，
> 所以本仓库不引入它的源码。SNES 最终选了同样是 GPL-3.0 的 **Mesen-S**。
>
> 未接入的系统也能**导入** ROM（文件先待在库里），只是点开时 App 会如实告诉你「核心还没接入」，不会假装能玩。

### 为什么核心是静态链接，而不是动态加载

iOS 15 + A12 起系统封禁了 `dynamic-codesigning` 与 `com.apple.private.cs.debugger`，
运行时 `dlopen` 一个**未签名**的核心动态库已经不可行（RetroArch 那种「外挂 core dylib」的做法在 TrollStore 上也不成立）。
因此核心一律用 CMake 交叉编译成 arm64 静态库，**直接链接进主二进制**
（见 [Scripts/build_cores.sh](Scripts/build_cores.sh)；编译不成功时会降级成「该核心不可用」，不会让整个构建挂掉）。

### JIT（3DS / Wii / Wii U 必需）

需要 JIT 的平台，App 会在启动前**真实探测**（直接在进程里 `mmap(MAP_JIT)` 试探）；拿不到可执行内存时如实提示，并给出开启路径：

1. **TrollStore（巨魔）安装**：CI 产出的 `Gameshell-TrollStore-tipa` 带的是 **TrollStore 原生 JIT entitlements**
   （`com.apple.private.security.no-sandbox` + `platform-application` + `storage.*` 等；**不再**使用被封禁的
   `dynamic-codesigning` / `com.apple.private.cs.debugger`）。装上后 App 会在启动瞬间**自己开 JIT**：
   用 `__attribute__((constructor))` 抢在 `UIApplicationMain` 之前，spawn 一个自己的子进程、子进程
   `ptrace(PT_TRACE_ME)`，父子都拿到 `CS_DEBUGGED`，于是 `mmap(MAP_JIT)` 成立（做法照 Amethyst-iOS / UTM）。
   若这样仍拿不到（例如 iOS 26+/TXM 机型），退回到点提示条上的「开启 JIT」——App 用
   `apple-magnifier://enable-jit?bundle-id=<本 App bundle-id>` 拉起 TrollStore 开一次，回到 App 点「重试」。
2. **普通侧载（没有 TrollStore）**：用 **StikDebug** 附加调试器后再启动 App，由调试器授予 JIT。

> ⚠️ 代价：tipa 因为要 `no-sandbox` 才能自开 JIT，装好后 App 会**脱离沙盒**，`Documents` 可能不再解析到自己的容器
> （若真机发现路径异常，需要按 `HOME` 兜底）。普通 IPA / macOS 不带这些项，保持沙盒。

> 现状：**melonDS（NDS / DSi）是第一个真正用到 JIT 的核心** —— 它的库里同时编入 ARM64 dynarec 与解释器两条路径，
> 设备拿得到可执行内存就走 JIT、拿不到就**自动退回解释器**（所以它不把 JIT 当启动硬条件，NDS 在任何设备上都打得开，只是速度不同）。
> 3DS / Wii / Wii U 仍需 JIT 才能真正可用，目前尚未接入。

## 目录结构

```
Sources/
├── App/                        # Swift：入口与全局状态
│   ├── GameshellApp.swift      # @main，注册 gameshell:// scheme
│   ├── AppState.swift          # 清单 / ROM 库、启动、浮层、外设状态
│   └── GSAudioPlayer.swift     # 模拟器音频（核心 → AVAudioEngine，iOS）
├── Core/                       # Objective-C：核心逻辑 + 模拟器宿主
│   ├── GSGameManifest.h/.m     # 清单解析 + 增删 + 沙盒持久化
│   ├── GSGameLauncher.h/.m     # 深链解析 / URL 规整
│   ├── GSInputManager.h/.m     # 手柄（GCController）+ 键鼠在线探测
│   ├── GSSystem.h/.m           # 模拟器「系统」注册表（扩展名 → 系统 → 计划核心）
│   ├── GSROMLibrary.h/.m       # ROM 扫描 / 导入 / 删除 / .sav 路径
│   ├── GSEmulator.h/.m         # 会话 + 帧循环 + 音频环形缓冲 + JIT 探测（GSJIT）
│   ├── GSMGBACore.m            # mGBA 宿主适配（GBA / GB / GBC）
│   ├── GSNestopiaCore.mm       # Nestopia 宿主适配（NES，ObjC++：Nestopia 是 C++）
│   ├── GSSnesCore.mm           # Mesen-S 宿主适配（SNES，ObjC++：走 libretro 接口）
│   ├── GSMelonDSCore.mm       # melonDS 宿主适配（NDS / DSi，ObjC++：走 libretro 接口）
│   ├── GSBuiltCoresCompat.h    # 编译期开关：核心没编出来就降级为「不可用」
│   └── Gameshell-Bridging-Header.h
└── UI/                         # Swift：SwiftUI 界面
    ├── Theme.swift             # 设计令牌（颜色/圆角/间距/字号/尺寸）
    ├── Components/             # 顶栏、方块卡片（PS5 风格）、封面（远程/本地/徽标三态）
    ├── Screens/                # 主界面 / 设置页（含触屏布局编辑器 TouchLayoutEditor）/ 播放器（WebView）/ 模拟器（EmulatorView）
    ├── Emulator/               # 核心状态表 + 自绘虚拟手柄 + 键盘捕获 + 输入汇总
    └── Overlay/                # 自绘浮层 + 添加 URL 表单 + 导入 ROM 浮层 + 文件选择器桥接
Resources/
├── games.json                  # 内置兜底清单（默认为空）
└── Assets.xcassets

Vendor/mgba/                    # mGBA 源码（MPL-2.0），CI 里交叉编译成 arm64 静态库
Vendor/nestopia/                # Nestopia 源码（GPL-2.0-or-later），同上
Vendor/mesens/                  # Mesen-S 源码（GPL-3.0），同上
Vendor/melonds/                 # melonDS 源码（GPL-3.0），同上（含 ARM64 JIT 分支）
Scripts/build_cores.sh          # 编译核心 → build/cores/<平台>/（含 GSBuiltCores.h 开关）
build/cores/<平台>/             # 核心编译产物（lib*.a + 头文件，不提交）

用户数据：沙盒 Documents/games.json（App 内添加的条目）
         沙盒 Documents/ROMs/<系统>/（自己导入的 ROM 与 .sav 存档）
         沙盒 Documents/Icons/<id>.<ext>（导入的条目图标）
         沙盒 Documents/Covers/<系统>/<ROM>.png（抓取到的 ROM 封面）
         沙盒 Documents/States/<ROM>/（即时存档：slot-0.state…slot-3.state + auto.state）
         沙盒 Documents/play_history.json（最近游玩）
         沙盒 Documents/keymap.json（三端键位 + 触屏布局：**三端都按系统分桶**，每个系统一套键位与每簇的位置 / 大小）
```

## 设计约束

- **禁止系统弹窗**：不使用 `UIAlertController` / `NSAlert` / `NSPanel`，所有提示、确认、输入表单都走自绘浮层。
- **深色主题**：近黑背景 + `#1B1B20` 卡片 + 橙色 `#FF7A18` 强调色，卡片带 `#2A2A30` 细描边。
- **令牌集中**：任何视图都不硬编码颜色尺寸，一律引用 `Theme.*`。

## 状态

主界面（PS5 风格方块行 + App 内添加 URL + 沙盒持久化 + URL 启动 + 手柄键鼠探测 + CI）已经可用，
模拟器部分 **mGBA（GBA / GB / GBC）与 Nestopia（NES）已经能导入 ROM 并模拟**
（画面 + 自绘虚拟手柄 + 声音；NES 画面 256×240，音频是单声道扩成立体声）；
**Mesen-S（SNES）** 的宿主适配也已完成、CI 里交叉编译并链接通过，
但**本机没有 iOS 工具链、尚未实机实测**（所以先按「已接入、待实机验证」对待，不写成「实测可玩」）；
**melonDS（NDS / DSi）** 的宿主适配同样写完、CI 里交叉编译（含 ARM64 JIT）并链接通过，
但**同样尚未实机实测**；它是第一个真正用到 JIT 的核心（拿得到走 dynarec、拿不到自动退回解释器）。
**变速（`0.5× / 1× / 2× / 4×`，加速静音）与即时存档（4 槽 + 退出自动存档）** 的代码也已写完、CI 编译链接通过，**尚未实机实测**
（另：NDS 在 DSi 模式下核心不提供即时存档）。
3DS / Wii / Wii U 的**核心尚未接入**（都要 GL 硬件渲染宿主层、且都要 JIT），业务功能仍在补。
逐项完成度请看 [REFERENCE.md](REFERENCE.md) 的「未完成清单」。

## 许可证

本仓库以 **GPL-3.0** 发布，全文见 [LICENSE](LICENSE)。
`Vendor/` 下的第三方源码各自保留原许可：`Vendor/mgba`（mGBA）为 **MPL-2.0**，
`Vendor/nestopia`（Nestopia）为 **GPL-2.0-or-later**（其每个源文件都写明可选用更高版本，
所以能按 GPL-3.0 一并分发），`Vendor/mesens`（Mesen-S）为 **GPL-3.0**，`Vendor/melonds`（melonDS）为 **GPL-3.0**。
**Snes9x 不引入**（非商用许可，与 GPL-3.0 不兼容）。
第三方组件与接入进度在 [LICENSE](LICENSE) 末尾与 [REFERENCE.md](REFERENCE.md) 里如实列出。
