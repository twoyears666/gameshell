import SwiftUI
import Foundation

#if canImport(WebKit)
import WebKit
#endif

/// 播放器：URL 驱动的核心落点。
/// 用 WKWebView 加载游戏页面；非 http(s) 的链接交给系统。
struct PlayerView: View {
    let game: GSGame
    @EnvironmentObject private var state: AppState

    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        VStack(spacing: 0) {
            playerBar
            ZStack {
                Theme.Color.background.ignoresSafeArea()

                if let url = resolvedURL {
                    WebView(url: url,
                            isLoading: $isLoading,
                            loadError: $loadError,
                            onPointerActivity: { GSInputManager.shared.reportPointerActivity() },
                            onKeyboardActivity: { GSInputManager.shared.reportKeyboardActivity() })
                } else {
                    unavailable
                }

                if isLoading, loadError == nil {
                    ProgressView()
                        .tint(Theme.Color.accent)
                }

                if let loadError {
                    errorView(loadError)
                }
            }
        }
        .background(Theme.Color.background)
    }

    // MARK: - 顶栏

    private var playerBar: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Button {
                state.stopPlaying()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                    Text("退出")
                        .font(Theme.Font.caption)
                }
                .foregroundStyle(Theme.Color.textPrimary)
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous)
                        .fill(Theme.Color.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous)
                                .stroke(Theme.Color.border, lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)

            Text(game.name)
                .font(Theme.Font.cardTitle)
                .foregroundStyle(Theme.Color.textPrimary)
                .lineLimit(1)

            Spacer()

            Button {
                state.confirm(
                    title: "重新加载？",
                    message: "将重新从 URL 加载游戏页面。",
                    confirmTitle: "重新加载"
                ) {
                    loadError = nil
                    isLoading = true
                    state.stopPlaying()
                    DispatchQueue.main.async { state.launch(game) }
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Color.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle().fill(Theme.Color.surface)
                            .overlay(Circle().stroke(Theme.Color.border, lineWidth: 1))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs)
        .background(Theme.Color.headerGradient)
    }

    private var unavailable: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "link.badge.plus")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(Theme.Color.textTertiary)
            Text("该条目没有可加载的 http(s) URL")
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Color.textSecondary)
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(Theme.Color.accent)
            Text("加载失败")
                .font(Theme.Font.section)
                .foregroundStyle(Theme.Color.textPrimary)
            Text(message)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.lg)
            PillButton(title: "返回", style: .secondary) { state.stopPlaying() }
                .frame(maxWidth: 160)
        }
    }

    private var resolvedURL: URL? {
        GSGameLauncher.normalizedGameURLFromString(game.gameURLString, baseURL: nil)
    }
}

// MARK: - WKWebView 封装

#if canImport(WebKit)

#if os(iOS)
private struct WebView: UIViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool
    @Binding var loadError: String?
    var onPointerActivity: () -> Void
    var onKeyboardActivity: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let parent: WebView
        init(_ parent: WebView) { self.parent = parent }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async { parent.isLoading = true; parent.loadError = nil }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async { parent.isLoading = false }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
                self.parent.loadError = error.localizedDescription
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
                self.parent.loadError = error.localizedDescription
            }
        }
    }
}
#else
private struct WebView: NSViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool
    @Binding var loadError: String?
    var onPointerActivity: () -> Void
    var onKeyboardActivity: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let parent: WebView
        init(_ parent: WebView) { self.parent = parent }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async { parent.isLoading = true; parent.loadError = nil }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async { parent.isLoading = false }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
                self.parent.loadError = error.localizedDescription
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
                self.parent.loadError = error.localizedDescription
            }
        }
    }
}
#endif

#endif
