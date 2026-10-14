import SwiftUI

/// 根视图：只有主界面 + 播放器全屏覆盖 + 自绘浮层。
struct RootView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ZStack {
            Theme.Color.background.ignoresSafeArea()

            HomeView()

            // 打开 http(s) 链接时全屏覆盖内置 WebView
            if let playing = state.playingGame {
                PlayerView(game: playing)
                    .transition(.opacity)
                    .zIndex(20)
            }

            // 自绘浮层：本 App 唯一允许的「弹窗」形态
            if let overlay = state.overlay {
                CustomOverlayLayer(request: overlay) {
                    state.dismissOverlay()
                }
            }
        }
        .animation(Theme.Motion.standard, value: state.playingGame?.identifier)
    }
}
