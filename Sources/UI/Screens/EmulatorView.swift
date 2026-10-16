//
//  EmulatorView.swift
//  Gameshell
//
//  全屏模拟器界面：画面 + 自绘虚拟手柄 + 暂停/退出/JIT 提示。
//
//  画面来自 GSEmulatorSession.copyLatestFrameImage()（核心每帧在模拟线程里生成一张
//  CGImage）。这里用 CADisplayLink 按屏幕刷新率去取「最新一帧」，所以模拟速度与
//  显示速度互不干扰：核心跑多快都不影响显示，掉帧只表现为画面重复。
//
//  输入：触屏（虚拟手柄）+ 硬件键盘（KeyboardCaptureView）+ 手柄（GSInputManager 转发）
//  三路都交给 EmulatorInputCoordinator 汇总成一个 GSButton 位掩码，再进核心。
//

import SwiftUI
import CoreGraphics

#if os(iOS)

import UIKit

struct EmulatorView: View {
    @EnvironmentObject private var state: AppState

    @StateObject private var frames = EmulatorFrameSource()
    @StateObject private var input = EmulatorInputCoordinator()
    @State private var isPaused = false
    /// 速度档位下标（对应 Self.speedOptions）
    @State private var speedIndex = 1
    /// 快照面板是否打开
    @State private var snapshotOpen = false
    /// 4 个存档槽的修改时间（nil = 空槽），打开面板与每次读写后刷新
    @State private var snapshotDates: [Date?] = [nil, nil, nil, nil]

    var body: some View {
        ZStack {
            SwiftUI.Color.black.ignoresSafeArea()
            content
            topBar

            // 快照面板（4 个存档槽），压在画面与顶栏之上
            if snapshotOpen, let session = state.emulatorSession {
                snapshotOverlay(session: session)
                    .transition(.opacity)
                    .zIndex(5)
            }

            // 硬件键盘捕获（0 尺寸，不参与布局也不遮挡画面）
            KeyboardCaptureView(isActive: true) { usage, pressed in
                input.handleKeyboard(usage, pressed: pressed)
            }
            .frame(width: 0, height: 0)
        }
        .onAppear {
            frames.attach(state.emulatorSession)
            input.attach(session: state.emulatorSession, mapping: state.keyMapping)
        }
        .onDisappear {
            frames.detach()
            input.detach()
        }
    }

    // MARK: - 主体

    @ViewBuilder
    private var content: some View {
        if let session = state.emulatorSession {
            if let failure = state.emulatorStartFailure {
                problemPanel(title: "还没能启动这个核心",
                             message: failure,
                             session: session,
                             showsRetry: true)
            } else if !session.isAvailable {
                problemPanel(title: "这个系统暂时打不开",
                             message: session.unavailableReason ?? "核心尚未接入",
                             session: session,
                             showsRetry: false)
            } else {
                gameSurface(session: session)
            }
        }
    }

    private func gameSurface(session: GSEmulatorSession) -> some View {
        GeometryReader { proxy in
            let full = proxy.size
            let landscape = Theme.isLandscape(full)
            // 竖屏时画面占上方、手柄占下方；横屏时画面铺满、手柄浮在画面之上。
            let screenArea = landscape
                ? full
                : CGSize(width: full.width, height: full.height * 0.56)
            let padArea = landscape
                ? full
                : CGSize(width: full.width, height: full.height * 0.44)

            Group {
                if landscape {
                    ZStack {
                        screenLayer(viewport: screenArea)
                        padLayer(area: padArea, session: session)
                    }
                } else {
                    VStack(spacing: 0) {
                        screenLayer(viewport: screenArea)
                        padLayer(area: padArea, session: session)
                    }
                }
            }
            .frame(width: full.width, height: full.height)
        }
    }

    private func screenLayer(viewport: CGSize) -> some View {
        ZStack {
            SwiftUI.Color.black
            if let image = frames.image {
                let fitted = fittedSize(for: image, in: viewport)
                Image(decorative: image, scale: 1)
                    .interpolation(.none)      // 像素风：放大不要糊
                    .resizable()
                    .frame(width: fitted.width, height: fitted.height)
            } else {
                Text("正在等第一帧画面…")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.textSecondary)
            }

            if isPaused {
                Text("已暂停")
                    .font(Theme.Font.section)
                    .foregroundStyle(Theme.Color.textPrimary)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.xs)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                            .fill(SwiftUI.Color.black.opacity(0.6))
                    )
            }
        }
        .frame(width: viewport.width, height: viewport.height)
    }

    private func padLayer(area: CGSize, session: GSEmulatorSession) -> some View {
        VirtualGamepad(size: area,
                       mapping: state.keyMapping,
                       systemIdentifier: session.systemInfo.identifier,
                       onMaskChange: { mask in
                           input.setTouchMask(mask)
                       },
                       onTouch: { point, active in
                           // 触摸屏（NDS 下屏）：把触摸区内的归一化坐标交给核心
                           session.setTouchPoint(point, active: active)
                       },
                       onMenu: {
                           // NDS 的 Menu 键等价顶栏的暂停按钮
                           togglePause()
                       })
        .frame(width: area.width, height: area.height)
    }

    /// 等比缩放（aspect fit）：超出可用区域就缩，小于就保持 1:1 不拉伸
    private func fittedSize(for image: CGImage, in viewport: CGSize) -> CGSize {
        let imageSize = CGSize(width: CGFloat(image.width), height: CGFloat(image.height))
        guard imageSize.width > 0, imageSize.height > 0,
              viewport.width > 0, viewport.height > 0 else { return imageSize }

        let scale = min(viewport.width / imageSize.width, viewport.height / imageSize.height)
        let fitted = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        // 整数倍缩放看起来最干净
        if scale > 1 {
            let integerScale = floor(scale)
            return CGSize(width: imageSize.width * integerScale,
                          height: imageSize.height * integerScale)
        }
        return fitted
    }

    /// 暂停 / 恢复。顶栏按钮与 NDS 的 Menu 键共用这一处，
    /// 免得两处各写一遍导致 isPaused 与 session.paused 走神。
    private func togglePause() {
        isPaused.toggle()
        state.emulatorSession?.paused = isPaused
    }

    // MARK: - 速度

    /// 速度档位（循环切换）。只改会话的 emulationSpeed：核心帧率本身不动，
    /// 宿主靠改帧节奏实现快慢；> 1× 时会话侧自动静音（见 GSEmulator.m 的注释）。
    private static let speedOptions: [Double] = [0.5, 1, 2, 4]

    private var speedLabel: String {
        let value = Self.speedOptions[speedIndex]
        return value == floor(value) ? "\(Int(value))×" : String(format: "%.1f×", value)
    }

    private var speedButton: some View {
        Button {
            cycleSpeed()
        } label: {
            Text(speedLabel)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.Color.textPrimary)
                .frame(minWidth: 32)
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
                .background(panelCapsule)
        }
        .buttonStyle(.plain)
        .disabled(!emulatorInteractive)
        .opacity(emulatorInteractive ? 1 : 0.4)
    }

    private func cycleSpeed() {
        speedIndex = (speedIndex + 1) % Self.speedOptions.count
        state.emulatorSession?.emulationSpeed = Self.speedOptions[speedIndex]
    }

    // MARK: - 快照

    private var snapshotButton: some View {
        Button {
            openSnapshotPanel()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "camera")
                    .font(.system(size: 12, weight: .semibold))
                Text("快照")
                    .font(.system(size: 12))
            }
            .foregroundStyle(Theme.Color.textPrimary)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, 6)
            .background(panelCapsule)
        }
        .buttonStyle(.plain)
        .disabled(!emulatorInteractive)
        .opacity(emulatorInteractive ? 1 : 0.4)
    }

    /// 胶囊底：白色面 + 细描边（与顶栏其它控件同一套外观）
    private var panelCapsule: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous)
            .fill(Theme.Color.surface)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous)
                    .stroke(Theme.Color.border, lineWidth: 1)
            )
    }

    private var emulatorInteractive: Bool {
        state.emulatorStartFailure == nil && (state.emulatorSession?.isAvailable ?? false)
    }

    private func openSnapshotPanel() {
        refreshSnapshotDates()
        snapshotOpen = true
    }

    private var currentSnapshotStore: EmulatorSnapshotStore? {
        guard let rom = state.playingROM else { return nil }
        return EmulatorSnapshotStore(romIdentifier: rom.identifier)
    }

    private func refreshSnapshotDates() {
        guard let store = currentSnapshotStore else {
            snapshotDates = Array(repeating: nil, count: EmulatorSnapshotStore.slotCount)
            return
        }
        snapshotDates = (0..<EmulatorSnapshotStore.slotCount).map { store.modificationDate(slot: $0) }
    }

    /// 退出前的自动存档：静默写进 auto.state，失败不打扰用户。
    private func autoSaveSnapshot() {
        guard let session = state.emulatorSession, let store = currentSnapshotStore else { return }
        guard session.supportsSaveStates, let data = session.copySnapshot() else { return }
        _ = store.write(data, slot: EmulatorSnapshotStore.autoSlot)
    }

    private func saveSnapshot(slot: Int) {
        guard let session = state.emulatorSession, let store = currentSnapshotStore else { return }
        guard session.supportsSaveStates else {
            state.showToast("这个核心还不支持即时存档")
            return
        }
        guard let data = session.copySnapshot() else {
            state.showToast("存档失败")
            return
        }
        if store.write(data, slot: slot) {
            refreshSnapshotDates()
            state.showToast("已存到存档 \(slot + 1)")
        } else {
            state.showToast("存档写入失败")
        }
    }

    private func loadSnapshot(slot: Int) {
        guard let session = state.emulatorSession, let store = currentSnapshotStore else { return }
        guard let data = store.read(slot: slot) else {
            state.showToast("存档 \(slot + 1) 是空的")
            return
        }
        if session.restoreSnapshot(data) {
            snapshotOpen = false
            state.showToast("已读回存档 \(slot + 1)")
        } else {
            state.showToast("读档失败（存档可能与当前核心或 ROM 不匹配）")
        }
    }

    private func deleteSnapshot(slot: Int) {
        guard let store = currentSnapshotStore else { return }
        store.delete(slot: slot)
        refreshSnapshotDates()
    }

    private func snapshotOverlay(session: GSEmulatorSession) -> some View {
        ZStack {
            SwiftUI.Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { snapshotOpen = false }

            VStack(spacing: 0) {
                HStack {
                    Text("即时存档")
                        .font(Theme.Font.section)
                        .foregroundStyle(Theme.Color.textPrimary)
                    Spacer()
                    Button {
                        snapshotOpen = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.Color.textSecondary)
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.md)

                if session.supportsSaveStates {
                    VStack(spacing: Theme.Spacing.xs) {
                        ForEach(0..<EmulatorSnapshotStore.slotCount, id: \.self) { slot in
                            snapshotSlotRow(slot: slot)
                        }
                        if let store = currentSnapshotStore {
                            snapshotAutoRow(store: store)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.md)

                    Text("退出模拟器时会自动写一份「自动存档」（auto.state）。")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.top, Theme.Spacing.xs)
                } else {
                    Text("这个核心还不支持即时存档。")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(Theme.Spacing.lg)
                }
            }
            .padding(.bottom, Theme.Spacing.md)
            .frame(maxWidth: 420)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Theme.Color.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                            .stroke(Theme.Color.border, lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.45), radius: 24, y: 12)
            .padding(Theme.Spacing.lg)
        }
    }

    private func snapshotSlotRow(slot: Int) -> some View {
        let date = snapshotDates.indices.contains(slot) ? snapshotDates[slot] : nil
        return snapshotRow(title: "存档 \(slot + 1)", date: date, slot: slot, allowsSave: true)
    }

    /// 「自动存档」伪槽位（auto.state）：只提供读 / 删，不提供存。
    private func snapshotAutoRow(store: EmulatorSnapshotStore) -> some View {
        let date = store.modificationDate(slot: EmulatorSnapshotStore.autoSlot)
        return snapshotRow(title: "自动存档",
                           date: date,
                           slot: EmulatorSnapshotStore.autoSlot,
                           allowsSave: false)
    }

    private func snapshotRow(title: String, date: Date?, slot: Int, allowsSave: Bool) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.textPrimary)
                Text(date.map { Self.snapshotDateFormatter.string(from: $0) } ?? "空")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            Spacer(minLength: 0)
            if allowsSave {
                snapshotAction("存", enabled: true) { saveSnapshot(slot: slot) }
            }
            snapshotAction("读", enabled: date != nil) { loadSnapshot(slot: slot) }
            snapshotAction("删", enabled: date != nil) { deleteSnapshot(slot: slot) }
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .fill(Theme.Color.surfaceAlt)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .stroke(Theme.Color.border, lineWidth: 1)
                )
        )
    }

    private func snapshotAction(_ title: String,
                                enabled: Bool,
                                action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(enabled ? Theme.Color.textPrimary : Theme.Color.textSecondary)
                .frame(width: 34, height: 28)
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
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }

    private static let snapshotDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm:ss"
        return formatter
    }()

    // MARK: - 顶栏

    private var topBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Spacing.sm) {
                Button {
                    autoSaveSnapshot()
                    state.stopPlayingROM()
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

                VStack(alignment: .leading, spacing: 1) {
                    Text(state.playingROM?.name ?? "模拟器")
                        .font(Theme.Font.cardTitle)
                        .foregroundStyle(Theme.Color.textPrimary)
                        .lineLimit(1)
                    if let session = state.emulatorSession {
                        Text(coreSummary(session))
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Color.textSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                speedButton
                snapshotButton

                Button {
                    togglePause()
                } label: {
                    Image(systemName: isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.Color.textPrimary)
                        .frame(width: 32, height: 32)
                        .background(
                            Circle().fill(Theme.Color.surface)
                                .overlay(Circle().stroke(Theme.Color.border, lineWidth: 1))
                        )
                }
                .buttonStyle(.plain)
                .disabled(state.emulatorStartFailure != nil || !(state.emulatorSession?.isAvailable ?? false))
                .opacity((state.emulatorSession?.isAvailable ?? false) ? 1 : 0.4)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.xs)
            .background(SwiftUI.Color.black.opacity(0.55))

            if let warning = state.emulatorSession?.jitWarning {
                jitBanner(warning)
            }

            Spacer()
        }
    }

    private func coreSummary(_ session: GSEmulatorSession) -> String {
        let system = session.systemInfo.shortName
        guard let core = session.core else { return system }
        return "\(system) · \(core.coreName) \(core.coreVersion) · \(session.requiresJIT ? "需要 JIT" : "无需 JIT")"
    }

    // MARK: - JIT 提示

    private func jitBanner(_ warning: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Image(systemName: "bolt.trianglebadge.exclamationmark.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.Color.accent)

            Text(warning)
                .font(.system(size: 12))
                .foregroundStyle(Theme.Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            if GSJIT.isTrollStoreAvailable() {
                PillButton(title: "开启 JIT", style: .primary) { openTrollStoreJIT() }
                    .frame(width: 110)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs)
        .background(Theme.Color.surface.opacity(0.94))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.Color.border).frame(height: 1)
        }
    }

    /// TrollStore 版：用 apple-magnifier://enable-jit?bundle-id=... 给自己的进程开 JIT
    private func openTrollStoreJIT() {
        guard let bundleID = Bundle.main.bundleIdentifier,
              let url = GSJIT.trollStoreEnableJITURL(forBundleID: bundleID) else { return }
        let appState = state
        UIApplication.shared.open(url, options: [:]) { success in
            if success {
                appState.showToast("已在 TrollStore 里为本 App 打开 JIT，回到这里点「重试」")
            } else {
                appState.showToast("打不开 TrollStore 的 JIT 链接，确认已安装 TrollStore")
            }
        }
    }

    // MARK: - 不可用 / 启动失败

    private func problemPanel(title: String,
                              message: String,
                              session: GSEmulatorSession,
                              showsRetry: Bool) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(Theme.Color.accent)

            Text(title)
                .font(Theme.Font.section)
                .foregroundStyle(Theme.Color.textPrimary)

            Text(message)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Theme.Spacing.lg)

            HStack(spacing: Theme.Spacing.sm) {
                if session.requiresJIT, GSJIT.isTrollStoreAvailable() {
                    PillButton(title: "开启 JIT", style: .primary) { openTrollStoreJIT() }
                }
                if showsRetry {
                    PillButton(title: "重试", style: .primary) { state.retryEmulatorStart() }
                }
                PillButton(title: "返回", style: .secondary) { state.stopPlayingROM() }
            }
            .frame(maxWidth: 380)
            .padding(.horizontal, Theme.Spacing.lg)
        }
    }
}

// MARK: - 取帧

/// 按屏幕刷新率去核心取最新一帧。
/// 核心自己生成新 CGImage；这里只在「拿到的是另一张」时才更新，不做任何像素拷贝。
/// 继承 NSObject 是因为 CADisplayLink 需要一个 ObjC 目标。
final class EmulatorFrameSource: NSObject, ObservableObject {

    @Published private(set) var image: CGImage?

    private weak var session: GSEmulatorSession?
    private var link: CADisplayLink?

    func attach(_ session: GSEmulatorSession?) {
        self.session = session
        guard link == nil else { return }

        let displayLink = CADisplayLink(target: self, selector: #selector(step))
        displayLink.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        displayLink.add(to: .main, forMode: .common)
        link = displayLink
    }

    func detach() {
        link?.invalidate()
        link = nil
        session = nil
        image = nil
    }

    @objc private func step() {
        guard let session else { return }
        guard let next = session.copyLatestFrameImage() else { return }
        if let current = image, current === next {
            return   // 核心还没跑出新帧，画面保持不动
        }
        image = next
    }
}

// MARK: - 即时存档落盘

/// 即时存档的落盘目录：Documents/States/<ROM identifier>/，每个槽一个文件
/// （slot-0.state…slot-3.state），另有一份退出时写的 auto.state。
/// 只做最朴素的读写；目录不存在时惰性创建。
final class EmulatorSnapshotStore {
    /// 「自动存档」用的伪槽号
    static let autoSlot = -1
    /// 手动槽位数量
    static let slotCount = 4

    private let directory: URL

    init(romIdentifier: String) {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        directory = documents
            .appendingPathComponent("States", isDirectory: true)
            .appendingPathComponent(romIdentifier, isDirectory: true)
    }

    private func fileURL(slot: Int) -> URL {
        directory.appendingPathComponent(slot == Self.autoSlot ? "auto.state" : "slot-\(slot).state")
    }

    func modificationDate(slot: Int) -> Date? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL(slot: slot).path) else {
            return nil
        }
        return attributes[.modificationDate] as? Date
    }

    @discardableResult
    func write(_ data: Data, slot: Int) -> Bool {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: fileURL(slot: slot), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    func read(slot: Int) -> Data? {
        try? Data(contentsOf: fileURL(slot: slot))
    }

    func delete(slot: Int) {
        try? FileManager.default.removeItem(at: fileURL(slot: slot))
    }
}

#endif
