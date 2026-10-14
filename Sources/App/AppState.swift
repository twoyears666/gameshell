import SwiftUI
import Foundation
import Combine

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// 底部标签
enum AppTab: String, CaseIterable, Identifiable {
    case home = "首页"
    case library = "游戏库"
    case charts = "榜单"
    case profile = "我的"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .home: return "house.fill"
        case .library: return "square.grid.2x2.fill"
        case .charts: return "chart.bar.fill"
        case .profile: return "person.fill"
        }
    }
}

/// 全局应用状态：清单、导航、自绘浮层。
/// 注意：本 App 禁用系统弹窗（UIAlertController / NSAlert），
/// 所有提示与确认都走这里的 CustomOverlay。
final class AppState: ObservableObject {

    @Published var manifest: GSGameManifest?
    @Published var selectedTab: AppTab = .home
    @Published var selectedCategory: String = "全部"
    @Published var searchText: String = ""
    @Published var presentedGame: GSGame?
    @Published var overlay: OverlayRequest?

    /// 正在播放的游戏（URL 驱动）
    @Published var playingGame: GSGame?

    /// 外设状态摘要（手柄 / 键鼠）
    @Published var inputSummary: String = "未检测到外设"

    private var inputObserver: NSObjectProtocol?

    init() {
        loadManifest()
        observeInput()
    }

    // MARK: - 清单加载

    private func loadManifest() {
        if let manifest = GSGameManifest.load(named: "games.json", in: Bundle.main) {
            self.manifest = manifest
        } else {
            self.manifest = nil
            showToast("未能加载 games.json 清单")
        }
    }

    var games: [GSGame] {
        manifest?.games ?? []
    }

    var categories: [String] {
        manifest?.categories ?? ["全部"]
    }

    /// 分类 + 关键词过滤后的列表
    var filteredGames: [GSGame] {
        var list = games
        if selectedCategory != "全部" {
            list = list.filter { $0.platform == selectedCategory }
        }
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !keyword.isEmpty {
            list = list.filter {
                $0.name.localizedCaseInsensitiveContains(keyword)
                    || $0.summary.localizedCaseInsensitiveContains(keyword)
                    || $0.tags.contains { $0.localizedCaseInsensitiveContains(keyword) }
            }
        }
        return list
    }

    /// 榜单：按评分降序
    var rankedGames: [GSGame] {
        games.sorted { $0.rating > $1.rating }
    }

    // MARK: - 导航

    func openDetail(_ game: GSGame) {
        presentedGame = game
    }

    func closeDetail() {
        presentedGame = nil
    }

    /// URL 驱动启动：http(s) 交给内置 WebView，其它 scheme 交给系统唤起对应 App。
    func launch(_ game: GSGame) {
        guard let url = GSGameLauncher.normalizedGameURL(from: game.gameURLString, baseURL: nil) else {
            showToast("该游戏没有可用的启动 URL")
            return
        }
        if url.scheme == "http" || url.scheme == "https" {
            playingGame = game
        } else {
            openExternally(url)
        }
    }

    /// 把非 http(s) 的链接（如 steam://、minecraft://）交给系统打开，由系统唤起对应 App。
    /// 注意：iOS 上能否打开取决于目标 App 是否已安装，这里如实把失败结果提示出来。
    private func openExternally(_ url: URL) {
        #if os(iOS)
        UIApplication.shared.open(url, options: [:]) { [weak self] success in
            if !success {
                self?.showToast("系统打不开 \(url.scheme ?? "")://，对应 App 可能未安装")
            }
        }
        #elseif os(macOS)
        if !NSWorkspace.shared.open(url) {
            showToast("系统打不开 \(url.scheme ?? "")://，对应 App 可能未安装")
        }
        #endif
    }

    func stopPlaying() {
        playingGame = nil
    }

    // MARK: - 深链处理

    func handle(url: URL) {
        let action = GSGameLauncher.action(for: url)
        let params = GSGameLauncher.parameters(for: url) ?? [:]

        switch action {
        case .open:
            if let raw = params["url"],
               let resolved = GSGameLauncher.normalizedGameURL(from: raw, baseURL: nil) {
                startAdHoc(url: resolved, title: params["name"] ?? resolved.host ?? "游戏")
            } else {
                showToast("深链缺少 url 参数")
            }
        case .play:
            if let identifier = params["id"],
               let game = games.first(where: { $0.identifier == identifier }) {
                launch(game)
            } else {
                showToast("未找到 id 为 \(params["id"] ?? "?") 的游戏")
            }
        case .search:
            searchText = params["q"] ?? ""
            selectedTab = .library
        case .home:
            selectedTab = .home
        default:
            showToast("无法识别的链接")
        }
    }

    /// 打开一个不在清单里的临时 URL（深链直接给 URL 的场景）
    private func startAdHoc(url: URL, title: String) {
        if url.scheme != "http" && url.scheme != "https" {
            // 非网页链接：直接交给系统唤起对应 App
            openExternally(url)
            return
        }
        let adHoc = GSGame(dictionary: [
            "id": "adhoc-" + UUID().uuidString,
            "name": title,
            "url": url.absoluteString,
            "platform": "Web",
        ])
        playingGame = adHoc
    }

    // MARK: - 浮层

    func showToast(_ message: String) {
        withAnimation(Theme.Motion.spring) {
            overlay = OverlayRequest(kind: .toast, title: message)
        }
        let token = overlay?.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
            guard let self, self.overlay?.id == token else { return }
            withAnimation(Theme.Motion.standard) { self.overlay = nil }
        }
    }

    func confirm(title: String,
                 message: String,
                 confirmTitle: String = "确定",
                 cancelTitle: String = "取消",
                 onConfirm: @escaping () -> Void) {
        withAnimation(Theme.Motion.spring) {
            overlay = OverlayRequest(
                kind: .confirm,
                title: title,
                message: message,
                confirmTitle: confirmTitle,
                cancelTitle: cancelTitle,
                onConfirm: onConfirm
            )
        }
    }

    func dismissOverlay() {
        withAnimation(Theme.Motion.standard) { overlay = nil }
    }

    // MARK: - 外设

    private func observeInput() {
        let manager = GSInputManager.shared()
        manager.startMonitoring()
        self.inputSummary = manager.snapshot.summaryText()

        inputObserver = NotificationCenter.default.addObserver(
            forName: .GSInputManagerDidUpdate,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.inputSummary = manager.snapshot.summaryText()
        }
    }
}
