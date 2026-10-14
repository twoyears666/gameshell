# Gameshell

一个 **iOS / iPadOS / macOS** 的 URL 启动器 **UI 壳**（shell）。
界面风格参考 **盖世游戏 / GameHub**、第一排方块行参考 **PS5 首页**，但**不使用其任何代码或资源**，仅参照「布局结构与视觉语言」。
本仓库目前是壳：功能会持续往里加，**没实现的功能都在 [REFERENCE.md](REFERENCE.md) 里如实标注为「未完成」**。

- **只有一个界面**：主界面（顶栏 + 第一排方块行），没有游戏库 / 榜单 / 我的等其它页面
- **技术栈**：Swift（SwiftUI，UI 层）+ Objective-C（核心层）混合
- **游戏来源**：完全 **URL 驱动** —— 打开一个 URL 就等于打开一个游戏或 App；
  `http(s)` 用内置 WebView 打开，`steam://` 这类 scheme 交给系统**唤起对应 App**
- **App 内添加 URL**：主界面右上角「添加」，填名称 + URL 即可，写入沙盒后重启仍在（基础功能）
- **不内置任何游戏**：清单默认为空，所有条目都由你自己添加
- **第一排**：PS5 风格的横向方块行（聚焦项放大 + 白色高亮描边，其余缩小变暗）
- **输入**：支持 **手柄**（GameController 框架，热插拔）与 **键鼠**
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

每次推送到 `main`，[.github/workflows/build.yml](.github/workflows/build.yml) 会在 `macos-15` 上跑完整流程并上传：

| 产物 | 内容 | 签名状态 |
| --- | --- | --- |
| `Gameshell-macOS` | macOS `.app` | **ad-hoc 自签名** |
| `Gameshell-IPA` | iOS 真机 `.ipa`（`Payload/Gameshell.app`） | **ad-hoc 自签名 + 最小 entitlements**，非开发者证书签名 |
| `Gameshell-TrollStore-tipa` | 与 IPA 内容相同的 `.tipa`，便于 TrollStore 识别 | 同上 |

> ⚠️ **诚实说明**：CI 产出的 IPA / tipa 是 **未签名 + `codesign -s -` ad-hoc 自签名** 的包
> （entitlements 见 [Signing/Gameshell-iOS.entitlements](Signing/Gameshell-iOS.entitlements)），
> 只能通过 **TrollStore（巨魔）** 或侧载工具安装 / 重签，
> **不能**直接装到未越狱设备、也**不能**上架 App Store。
> 正规签名的 IPA 需要 Apple 开发者证书与描述文件，属于**未完成**部分（见 [REFERENCE.md](REFERENCE.md)）。

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

## 目录结构

```
Sources/
├── App/                    # Swift：入口与全局状态
│   ├── GameshellApp.swift  # @main，注册 gameshell:// scheme
│   └── AppState.swift      # 清单增删/持久化、URL 启动、浮层、外设状态
├── Core/                   # Objective-C：核心逻辑
│   ├── GSGameManifest.h/.m # 清单解析 + 增删 + 沙盒持久化
│   ├── GSGameLauncher.h/.m # 深链解析 / URL 规整
│   ├── GSInputManager.h/.m # 手柄（GCController）+ 键鼠在线探测
│   └── Gameshell-Bridging-Header.h
└── UI/                     # Swift：SwiftUI 界面
    ├── Theme.swift         # 设计令牌（颜色/圆角/间距/字号/尺寸）
    ├── Components/         # 顶栏、方块卡片（PS5 风格）、封面
    ├── Screens/            # 主界面 / 播放器（WebView）
    └── Overlay/            # 自绘浮层 + App 内添加 URL 表单（禁系统弹窗）
Resources/
├── games.json              # 内置兜底清单（默认为空）
└── Assets.xcassets

用户数据：沙盒 Documents/games.json（App 内添加的条目）
```

## 设计约束

- **禁止系统弹窗**：不使用 `UIAlertController` / `NSAlert` / `NSPanel`，所有提示、确认、输入表单都走自绘浮层。
- **深色主题**：近黑背景 + `#1B1B20` 卡片 + 橙色 `#FF7A18` 强调色，卡片带 `#2A2A30` 细描边。
- **令牌集中**：任何视图都不硬编码颜色尺寸，一律引用 `Theme.*`。

## 状态

主界面（PS5 风格方块行 + App 内添加 URL + 沙盒持久化 + URL 启动 + 手柄键鼠探测 + CI）已经可用，业务功能仍在补。
逐项完成度请看 [REFERENCE.md](REFERENCE.md) 的「未完成清单」。
