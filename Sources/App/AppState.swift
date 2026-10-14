import SwiftUI
import Foundation
import Combine

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// 全局应用状态：清单、启动、自绘浮层。
/// 本 App 只有主界面；禁用系统弹窗（UIAlertController / NSAlert），
/// 所有提示与确认都走 CustomOverlay。
final class AppState: ObservableObject {

    /// 清单本身（标题 / 副标题 / 条目）
    @Published private(set) var manifest: GSGameManifest?

    /// 主界面方块行的数据源：全是用户自己添加的条目，App 不内置任何游戏
    @Published private(set) var games: [GSGame] = []

    /// 正在打开的游戏（http(s) 走内置 WebView）
    @Published var playingGame: GSGame?

    @Published var overlay: OverlayRequest?

    /// 外设状态摘要（手柄 / 键鼠）
    @Published private(set) var inputSummary: String = "未检测到外设"

    private var inputObserver: NSObjectProtocol?

    init() {
        loadManifest()
        observeInput()
    }

    var title: String { manifest?.title ?? "Gameshell" }
    var subtitle: String { manifest?.subtitle ?? "" }

    // MARK: - 清单

    /// 优先读沙盒里用户自己添加的清单（Documents/games.json），
    /// 没有才回到内置的那份空清单。
    private func loadManifest() {
        manifest = GSGameManifest.loadUserStore()
            ?? GSGameManifest.load(named: "games.json", in: Bundle.main)
        games = manifest?.games ?? []
    }

    /// App 内添加 URL —— 基础功能。
    /// 校验不通过时用自绘 toast 提示并返回 false。
    func addGame(name: String, urlString: String) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            showToast("请先填名称")
            return false
        }
        guard let url = normalizedInputURL(trimmedURL) else {
            showToast("URL 格式不对，例如 https://example.com 或 steam://run/123")
            return false
        }
        guard let manifest else {
            showToast("清单不可用，无法添加")
            return false
        }
        guard !games.contains(where: { $0.gameURLString == url.absoluteString }) else {
            showToast("这个 URL 已经在清单里了")
            return false
        }

        let game = GSGame(dictionary: [
            "id": UUID().uuidString,
            "name": trimmedName,
            "url": url.absoluteString,
            "platform": platformLabel(for: url),
        ])
        manifest.add(game)
        games = manifest.games

        if !manifest.persistToUserStore() {
            showToast("已添加，但写入沙盒失败（重启后会丢）")
        }
        return true
    }

    /// 删除前先走自绘确认浮层
    func confirmRemoval(of game: GSGame) {
        confirm(title: "删除「\(game.name)」？",
                message: "只从清单里移除这一条，不会动其它数据。",
                confirmTitle: "删除") { [weak self] in
            self?.remove(game)
        }
    }

    private func remove(_ game: GSGame) {
        guard let manifest else { return }
        manifest.removeGame(withIdentifier: game.identifier)
        games = manifest.games

        if !manifest.persistToUserStore() {
            showToast("删除后写入沙盒失败")
            return
        }
        showToast("已删除「\(game.name)」")
    }

    /// 用户输入的补全：带 scheme 就原样规整，不带就补 https://
    private func normalizedInputURL(_ raw: String) -> URL? {
        guard !raw.isEmpty else { return nil }
        if let url = URL(string: raw), let scheme = url.scheme, !scheme.isEmpty {
            return GSGameLauncher.normalizedGameURL(from: raw, baseURL: nil) ?? url
        }
        return GSGameLauncher.normalizedGameURL(from: "https://" + raw, baseURL: nil)
    }

    /// 方块卡片上的小标签：网页 / 具体 scheme 名
    private func platformLabel(for url: URL) -> String {
        switch url.scheme?.lowercased() {
        case "http", "https": return "网页"
        case .some(let scheme): return scheme
        case .none: return "URL"
        }
    }

    // MARK: - 启动

    /// URL 驱动启动：http(s) 交给内置 WebView，其它 scheme 交给系统唤起对应 App。
    func launch(_ game: GSGame) {
        guard let url = GSGameLauncher.normalizedGameURL(from: game.gameURLString, baseURL: nil) else {
            showToast("这条记录没有可用的 URL")
            return
        }
        if url.scheme == "http" || url.scheme == "https" {
            playingGame = game
        } else {
            openExternally(url)
        }
    }

    /// 把非 http(s) 的链接（如 steam://、minecraft://）交给系统打开，由系统唤起对应 App。
    /// iOS 上能否打开取决于目标 App 是否已安装，这里如实把失败结果提示出来。
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

    // MARK: - 深链

    func handle(url: URL) {
        let action = GSGameLauncher.action(for: url)
        let params = GSGameLauncher.parameters(for: url) ?? [:]

        switch action {
        case .open:
            if let raw = params["url"],
               let resolved = GSGameLauncher.normalizedGameURL(from: raw, baseURL: nil) {
                startAdHoc(url: resolved, title: params["name"] ?? resolved.host ?? "链接")
            } else {
                showToast("深链缺少 url 参数")
            }
        case .play:
            if let identifier = params["id"],
               let game = games.first(where: { $0.identifier == identifier }) {
                launch(game)
            } else {
                showToast("清单里没有 id 为 \(params["id"] ?? "?") 的条目")
            }
        case .search:
            showToast("search 深链已移除，请用 open?url=")
        case .home:
            stopPlaying()
        default:
            showToast("无法识别的链接")
        }
    }

    /// 打开一个不在清单里的临时 URL（深链直接给 URL 的场景）
    private func startAdHoc(url: URL, title: String) {
        if url.scheme != "http" && url.scheme != "https" {
            openExternally(url)
            return
        }
        let adHoc = GSGame(dictionary: [
            "id": "adhoc-" + UUID().uuidString,
            "name": title,
            "url": url.absoluteString,
            "platform": "网页",
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
