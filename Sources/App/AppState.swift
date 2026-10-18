import SwiftUI
import Foundation
import Combine

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// 全局应用状态：清单、游戏库（URL 条目 + 模拟器 ROM）、最近游玩、启动、自绘浮层。
/// 本 App 禁用系统弹窗（UIAlertController / NSAlert），所有提示与确认都走 CustomOverlay。
final class AppState: ObservableObject {

    /// 清单本身（标题 / 副标题 / 条目）
    @Published private(set) var manifest: GSGameManifest?

    /// 游戏库里用户自己添加的 URL 条目，App 不内置任何游戏
    @Published private(set) var games: [GSGame] = []

    /// 正在打开的游戏（http(s) 走内置 WebView）
    @Published var playingGame: GSGame?

    /// ROM 库：从沙盒 Documents/ROMs 扫出来的用户自己的 ROM
    @Published private(set) var roms: [GSROM] = []

    /// 正在玩的 ROM（非 nil 时整屏交给 EmulatorView）
    @Published private(set) var playingROM: GSROM?

    /// 当前这次游玩的模拟器会话
    @Published private(set) var emulatorSession: GSEmulatorSession?

    /// 会话启动失败的原因（例如缺少 JIT）；nil = 已经正常启动
    @Published private(set) var emulatorStartFailure: String?

    /// 顶排「最近游玩」：按时间倒序，UI 只取前 10 个
    @Published private(set) var recentItems: [LibraryItem] = []

    /// ROM 封面缓存：rom.identifier → 相对 Documents 的路径。
    /// 抓取完成后更新这里，卡片会随之换成真封面（之前显示系统徽标）。
    @Published private(set) var romCovers: [String: String] = [:]

    @Published var overlay: OverlayRequest?

    /// 设置页是否打开（自绘覆盖层，与播放器同级）
    @Published var settingsOpen = false

    /// 外设状态摘要（手柄 / 键鼠）
    @Published private(set) var inputSummary: String = "未检测到外设"

    /// 三端键位配置（触屏 / 键盘 / 手柄）：设置页改的就是这一份，模拟器读的也是它
    let keyMapping = GSKeyMapping.shared()

    private var inputObserver: NSObjectProtocol?

    // GSPlayHistoryKind 的原始值（见 GSPlayHistory.h）：URL 条目 = 0，ROM = 1。
    // 这里用原始值比较，避免依赖 Swift 对枚举成员名的自动改写。
    private static let historyKindURL = 0
    private static let historyKindROM = 1

    #if os(iOS)
    /// 模拟器声音（核心 → AVAudioEngine）
    private var audioPlayer: GSAudioPlayer?
    #endif

    init() {
        loadManifest()
        refreshROMs()
        refreshRecent()
        observeInput()
    }

    var title: String { manifest?.title ?? "Gameshell" }
    var subtitle: String { manifest?.subtitle ?? "" }

    /// 游戏库内容：用户添加的 URL 条目 + 导入的 ROM，混排在一起
    var libraryItems: [LibraryItem] {
        games.map { .game($0) } + roms.map { .rom($0) }
    }

    /// 重新扫 ROM 库 + 刷新最近游玩（进主界面时调一次）
    func refreshLibrary() {
        refreshROMs()
        refreshRecent()
    }

    // MARK: - 清单

    /// 优先读沙盒里用户自己添加的清单（Documents/games.json），
    /// 没有才回到内置的那份空清单。
    private func loadManifest() {
        manifest = GSGameManifest.loadUserStore()
            ?? GSGameManifest.load(named: "games.json", in: Bundle.main)
        games = manifest?.games ?? []
    }

    /// App 内添加 URL —— 基础功能。
    /// iconData 非空时会先把图片写进沙盒（Documents/Icons/<id>.<ext>），条目里只记相对路径。
    /// 校验不通过时用自绘 toast 提示并返回 false。
    func addGame(name: String,
                 urlString: String,
                 iconData: Data? = nil,
                 iconExtension: String? = nil) -> Bool {
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

        let identifier = UUID().uuidString
        var icon = ""
        if let iconData {
            icon = GSIconStore.storeIconData(iconData,
                                            fileExtension: iconExtension,
                                            forIdentifier: identifier) ?? ""
        }

        let game = GSGame(dictionary: [
            "id": identifier,
            "name": trimmedName,
            "url": url.absoluteString,
            "platform": platformLabel(for: url),
            "icon": icon,
        ])
        manifest.add(game)
        games = manifest.games
        refreshRecent()

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

        // 本地图标与最近游玩记录跟着一起清掉
        _ = GSIconStore.removeIcon(forIdentifier: game.identifier)
        GSLocalImageStore.invalidate()
        GSPlayHistory.shared().removeIdentifier(game.identifier)
        refreshRecent()

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

    /// 游戏库里的任意一条：URL 条目走 URL 启动，ROM 走模拟器
    func launch(_ item: LibraryItem) {
        switch item {
        case .game(let game): launch(game)
        case .rom(let rom): launchROM(rom)
        }
    }

    func confirmRemoval(of item: LibraryItem) {
        switch item {
        case .game(let game): confirmRemoval(of: game)
        case .rom(let rom): confirmROMRemoval(of: rom)
        }
    }

    /// URL 驱动启动：http(s) 交给内置 WebView，其它 scheme 交给系统唤起对应 App。
    func launch(_ game: GSGame) {
        guard let url = GSGameLauncher.normalizedGameURL(from: game.gameURLString, baseURL: nil) else {
            showToast("这条记录没有可用的 URL")
            return
        }
        recordPlay(identifier: game.identifier, isROM: false)

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

    // MARK: - 最近游玩

    /// 记一次游玩并立刻刷新顶排（找不到对应条目时 UI 侧直接跳过）
    private func recordPlay(identifier: String, isROM: Bool) {
        let raw = isROM ? Self.historyKindROM : Self.historyKindURL
        guard let kind = GSPlayHistoryKind(rawValue: raw) else { return }
        GSPlayHistory.shared().recordIdentifier(identifier, kind: kind)
        refreshRecent()
    }

    /// 重建顶排：把历史记录映射回当前还在库里的条目，按时间倒序
    func refreshRecent() {
        var pool: [String: LibraryItem] = [:]
        for game in games { pool["game:" + game.identifier] = .game(game) }
        for rom in roms { pool["rom:" + rom.identifier] = .rom(rom) }

        let entries = GSPlayHistory.shared().recentEntries(withLimit: GSPlayHistory.historyLimit())
        recentItems = entries.compactMap { entry in
            let prefix = entry.kind.rawValue == Self.historyKindROM ? "rom:" : "game:"
            return pool[prefix + entry.identifier]
        }
    }

    // MARK: - 模拟器 ROM

    /// 重新扫描沙盒里的 Documents/ROMs（macOS 版是纯 URL 模式，不扫）
    func refreshROMs() {
        #if os(iOS)
        roms = GSROMLibrary.allROMs()
        refreshROMCovers()
        #endif
    }

    /// 重建 ROM 封面表 + 抓取还没封面的那些
    private func refreshROMCovers() {
        var map: [String: String] = [:]
        for rom in roms {
            if let path = GSCoverFetcher.cachedCoverRelativePath(for: rom) {
                map[rom.identifier] = path
            }
        }
        romCovers = map
        fetchMissingCovers()
    }

    /// 缺封面的 ROM 交给 GSCoverFetcher 去 libretro-thumbnails 找；命中一个更新一个
    private func fetchMissingCovers() {
        let missing = roms.filter { romCovers[$0.identifier] == nil }
        guard !missing.isEmpty else { return }

        GSCoverFetcher.shared().fetchCovers(roms: missing,
                                          limit: 40,
                                          progress: { [weak self] identifier, path in
            DispatchQueue.main.async { self?.romCovers[identifier] = path }
        },
                                          completion: nil)
    }

    /// 导入一份 ROM（文件选择器给的 URL）→ 复制进沙盒里对应的系统目录
    func importROM(from url: URL) {
        do {
            let rom = try GSROMLibrary.importFile(at: url)
            refreshROMs()

            let info = GSSystemRegistry.info(for: rom.system)
            if info.coreIntegrated {
                let core = GSEmulatorSession.coreName(for: info.system) ?? "核心"
                showToast("已导入「\(rom.name)」（\(info.shortName) · \(core)）")
            } else {
                showToast("已导入「\(rom.name)」，但 \(info.shortName) 的核心还没接入，暂时打不开")
            }
        } catch {
            showToast(error.localizedDescription)
        }
    }

    /// 删除 ROM 前先走自绘确认浮层
    func confirmROMRemoval(of rom: GSROM) {
        let info = GSSystemRegistry.info(for: rom.system)
        confirm(title: "删除「\(rom.name)」？",
                message: "只删沙盒里这份 ROM 文件（\(info.shortName) 目录），同目录的 .sav 存档会留着。",
                confirmTitle: "删除") { [weak self] in
            self?.remove(rom)
        }
    }

    private func remove(_ rom: GSROM) {
        do {
            try GSROMLibrary.delete(rom)
            GSPlayHistory.shared().removeIdentifier(rom.identifier)
            refreshROMs()
            refreshRecent()
            showToast("已删除「\(rom.name)」")
        } catch {
            showToast("删除失败：\(error.localizedDescription)")
        }
    }

    /// 打开一个 ROM。没有核心的系统如实拒绝，不假装能玩。
    func launchROM(_ rom: GSROM) {
        let info = GSSystemRegistry.info(for: rom.system)
        guard GSEmulatorSession.hasCore(for: rom.system) else {
            GSLog.tag("emu", message: "启动被拒：\(info.identifier) 尚无可用核心，ROM=\(rom.absolutePath)")
            showToast("\(info.shortName)：\(info.statusNote ?? "尚无可用核心")")
            return
        }

        GSLog.tag("emu", message: "准备启动：系统=\(info.identifier) ROM=\(rom.absolutePath)")

        recordPlay(identifier: rom.identifier, isROM: true)

        stopPlaying()
        stopPlayingROM()

        playingROM = rom
        emulatorSession = GSEmulatorSession(rom: rom)
        emulatorStartFailure = nil
        startEmulator()
    }

    /// 手动重试（例如刚在 TrollStore 里开完 JIT）
    func retryEmulatorStart() {
        GSLog.tag("emu", message: "手动重试启动模拟器")
        emulatorStartFailure = nil
        startEmulator()
    }

    private func startEmulator() {
        guard let session = emulatorSession else { return }
        do {
            try session.start()
            GSLog.tag("emu", message: "模拟器已启动：系统=\(session.systemInfo.identifier) 核心=\(session.core?.coreName ?? "未知")")
            #if os(iOS)
            audioPlayer = GSAudioPlayer(session: session)
            audioPlayer?.start()
            #endif
        } catch {
            GSLog.tag("emu", message: "模拟器启动失败：\(session.systemInfo.identifier) - \(error.localizedDescription)")
            emulatorStartFailure = error.localizedDescription
        }
    }

    func stopPlayingROM() {
        if emulatorSession != nil {
            GSLog.tag("emu", message: "关闭模拟器：系统=\(emulatorSession?.systemInfo.identifier ?? "?")")
        }
        #if os(iOS)
        audioPlayer?.stop()
        audioPlayer = nil
        #endif
        emulatorSession?.stop()
        emulatorSession = nil
        playingROM = nil
        emulatorStartFailure = nil
    }

    // MARK: - 设置页

    func openSettings() {
        withAnimation(Theme.Motion.spring) { settingsOpen = true }
    }

    func closeSettings() {
        withAnimation(Theme.Motion.standard) { settingsOpen = false }
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
