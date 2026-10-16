import SwiftUI

/// 根视图：主界面 + 设置页覆盖层 + 播放器全屏覆盖（网页 / 模拟器）+ 自绘浮层。
struct RootView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ZStack {
            Theme.Color.background.ignoresSafeArea()

            HomeView()

            // 设置页：自绘覆盖层，压在播放器之下，进模拟器 / 网页时会被盖住
            if state.settingsOpen {
                SettingsView()
                    .transition(.opacity)
                    .zIndex(12)
            }

            // 打开 http(s) 链接时全屏覆盖内置 WebView
            if let playing = state.playingGame {
                PlayerView(game: playing)
                    .transition(.opacity)
                    .zIndex(20)
            }

            #if os(iOS)
            // 打开 ROM 时全屏覆盖模拟器（画面 + 自绘虚拟手柄）
            if state.playingROM != nil {
                EmulatorView()
                    .transition(.opacity)
                    .zIndex(21)
            }
            #endif

            // 自绘浮层：本 App 唯一允许的「弹窗」形态
            if let overlay = state.overlay {
                CustomOverlayLayer(request: overlay) {
                    state.dismissOverlay()
                }
            }
        }
        .animation(Theme.Motion.standard, value: state.playingGame?.identifier)
        .animation(Theme.Motion.standard, value: state.playingROM?.identifier)
        .animation(Theme.Motion.standard, value: state.settingsOpen)
    }
}
