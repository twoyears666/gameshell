import SwiftUI

/// 根视图：负责整体布局（竖屏单列 / 横屏双列）、详情与播放器的全屏切换、自绘浮层。
struct RootView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ZStack {
            Theme.Color.background.ignoresSafeArea()

            mainShell

            // 详情页（全屏覆盖）
            if let game = state.presentedGame {
                DetailView(game: game)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .zIndex(10)
            }

            // 播放器（全屏覆盖）
            if let playing = state.playingGame {
                PlayerView(game: playing)
                    .transition(.opacity)
                    .zIndex(20)
            }

            // 自绘浮层：唯一允许的「弹窗」形态
            if let overlay = state.overlay {
                CustomOverlayLayer(request: overlay) {
                    state.dismissOverlay()
                }
            }
        }
        .animation(Theme.Motion.standard, value: state.presentedGame?.identifier)
        .animation(Theme.Motion.standard, value: state.playingGame?.identifier)
    }

    // MARK: - 主壳

    private var mainShell: some View {
        VStack(spacing: 0) {
            TopBar(
                title: state.selectedTab.rawValue,
                subtitle: state.manifest?.subtitle,
                inputSummary: state.inputSummary
            )

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            BottomTabBar(selection: $state.selectedTab)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state.selectedTab {
        case .home: HomeView()
        case .library: LibraryView()
        case .charts: ChartsView()
        case .profile: ProfileView()
        }
    }
}
