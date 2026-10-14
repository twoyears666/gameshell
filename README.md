# Gameshell

一个 **iOS / iPadOS / macOS** 的游戏启动器 **UI 壳**（shell）。
界面风格参考 **盖世游戏 / GameHub**，但**不使用其任何代码或资源**，仅参照「布局结构与视觉语言」。
本仓库目前是壳：功能会持续往里加，**没实现的功能都在 [REFERENCE.md](REFERENCE.md) 里如实标注为「未完成」**。

- **技术栈**：Swift（SwiftUI，UI 层）+ Objective-C（核心层）混合
- **游戏来源**：完全 **URL 驱动** —— 打开一个 URL 就等于启动 / 打开一个游戏或 App
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
| `Gameshell-iOS-Simulator` | iOS 模拟器 `.app` | 无需签名 |
| `Gameshell-macOS` | macOS `.app` | 未签名 |
| `Gameshell-IPA` | iOS 真机 `.ipa`（`Payload/Gameshell.app`） | **ad-hoc 自签名**，非开发者证书签名 |
| `Gameshell-TrollStore-tipa` | 与 IPA 内容相同的 `.tipa`，便于 TrollStore 识别 | 同上 |

> ⚠️ **诚实说明**：CI 产出的 IPA / tipa 是 **未签名 + `codesign -s -` ad-hoc 自签名** 的包，
> 只能通过 **TrollStore（巨魔）** 或侧载工具安装 / 重签，
> **不能**直接装到未越狱设备、也**不能**上架 App Store。
> 正规签名的 IPA 需要 Apple 开发者证书与描述文件，属于**未完成**部分（见 [REFERENCE.md](REFERENCE.md)）。

## URL 驱动

游戏列表来自 `Resources/games.json`，**UI 不硬编码任何游戏**。每条目至少有：

```json
{
  "id": "2048",
  "name": "2048",
  "icon": "square.grid.3x3.fill",
  "url": "https://play2048.co/",
  "platform": "休闲",
  "controllerSupport": false,
  "rating": 8.6,
  "description": "……",
  "tags": ["益智", "数字"]
}
```

- `icon`：以 `http` 开头按远程图片加载，否则按 SF Symbol 名称渲染。
- `url`：`http(s)` 由内置 WebView 加载；其它 scheme 交给系统打开。

### 深链（URL scheme：`gameshell://`）

| 深链 | 作用 |
| --- | --- |
| `gameshell://home` | 回到首页 |
| `gameshell://open?url=https://example.com/game&name=示例` | 用 URL 直接开一个不在清单里的游戏 |
| `gameshell://play?id=2048` | 按 id 在清单里找到并启动 |
| `gameshell://search?q=tetris` | 跳转游戏库并带上搜索词 |

命令行验证：

```bash
# macOS
open "gameshell://play?id=2048"
```

## 目录结构

```
Sources/
├── App/                    # Swift：入口与全局状态
│   ├── GameshellApp.swift  # @main，注册 gameshell:// scheme
│   └── AppState.swift      # 清单、导航、浮层、外设状态
├── Core/                   # Objective-C：核心逻辑
│   ├── GSGameManifest.h/.m # games.json 解析 → 游戏模型
│   ├── GSGameLauncher.h/.m # 深链解析 / URL 规整
│   ├── GSInputManager.h/.m # 手柄（GCController）+ 键鼠在线探测
│   └── Gameshell-Bridging-Header.h
└── UI/                     # Swift：SwiftUI 界面
    ├── Theme.swift         # 设计令牌（颜色/圆角/间距/字号/断点）
    ├── Components/         # 卡片、评分徽章、搜索框、标签栏……
    ├── Screens/            # 首页 / 游戏库 / 榜单 / 我的 / 详情 / 播放器
    └── Overlay/            # 自绘浮层（禁系统弹窗）
Resources/
├── games.json              # 游戏清单（唯一数据源）
└── Assets.xcassets
```

## 设计约束

- **禁止系统弹窗**：不使用 `UIAlertController` / `NSAlert` / `NSPanel`，所有提示与确认走自绘浮层（`CustomOverlayLayer`）。
- **深色主题**：近黑背景 + `#1B1B20` 卡片 + 橙色 `#FF7A18` 强调色，卡片带 `#2A2A30` 细描边。
- **响应式**：竖屏单列；iPad / macOS 多列 Bento 网格；横屏双列。
- **令牌集中**：任何视图都不硬编码颜色尺寸，一律引用 `Theme.*`。

## 状态

壳（UI + URL 驱动 + 手柄键鼠探测 + CI）已经可用，业务功能仍在补。
逐项完成度请看 [REFERENCE.md](REFERENCE.md) 的「未完成清单」。
