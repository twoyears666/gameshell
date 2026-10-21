import SwiftUI

/// 应用入口。
/// SwiftUI 负责 UI 壳，Objective-C 负责核心（清单解析 / URL 启动 / 手柄键鼠）。
@main
struct GameshellApp: App {
    @StateObject private var state = AppState()

    init() {
        // Metal HUD 必须在任何 Metal 设备创建之前写进环境变量，所以放在 App 入口最早期
        GSMetalHUD.applyAtLaunch()
    }

    var body: some Scene {
        #if os(macOS)
        WindowGroup {
            rootView
        }
        .defaultSize(width: 1200, height: 800)
        #else
        WindowGroup {
            rootView
        }
        #endif
    }

    private var rootView: some View {
        RootView()
            .environmentObject(state)
            .preferredColorScheme(.dark)   // 设计规范：仅深色主题
            .onOpenURL { url in
                // URL 驱动：gameshell://open?url=... / play?id=... / search?q=...
                state.handle(url: url)
            }
    }
}
