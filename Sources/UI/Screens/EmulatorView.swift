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

    var body: some View {
        ZStack {
            SwiftUI.Color.black.ignoresSafeArea()
            content
            topBar

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

    // MARK: - 顶栏

    private var topBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Spacing.sm) {
                Button {
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

#endif
