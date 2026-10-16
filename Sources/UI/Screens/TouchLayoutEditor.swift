//
//  TouchLayoutEditor.swift
//  Gameshell
//
//  触屏手柄的「布局编辑器」：拖拽移动每一簇按键、双指或滑杆调整大小。
//
//  入口只在设置页里（触摸卡片上的「编辑布局」），游玩界面（EmulatorView）不提供编辑入口，
//  避免玩到一半误触把布局拖乱。编辑的是**当前所选系统**的布局（各系统分开保存）。
//  改完立即写回 GSKeyMapping 内存，松手时落盘到 Documents/keymap.json。
//  坐标是归一化的（相对手柄可用区域），所以横竖屏各自按自己的区域生效。
//

#if os(iOS)

import SwiftUI

struct TouchLayoutEditor: View {

    let mapping: GSKeyMapping
    /// 正在编辑哪个系统（nes / snes / gb / gbc / gba / nds）
    let systemIdentifier: String
    let onClose: () -> Void

    /// 编辑器内自己持一份布局，拖拽时即时重绘；松手 / 松滑杆时落盘。
    @State private var layouts: [Int: GSTouchClusterLayout] = [:]
    @State private var selected: GSTouchCluster = .dPad
    /// 一次拖拽 / 缩放的起点（手势过程中不变，避免累积误差）
    @State private var gestureOrigin: GSTouchClusterLayout?

    /// 该系统的按键簇集合
    private var clusters: [GSTouchCluster] {
        GSKeyMapping.touchClusters(forSystem: systemIdentifier)
            .compactMap { GSTouchCluster(rawValue: $0.intValue) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            GeometryReader { proxy in
                let canvas = proxy.size
                ZStack(alignment: .topLeading) {
                    canvasBackground
                    ForEach(clusters.indices, id: \.self) { index in
                        let cluster = clusters[index]
                        if isVisible(cluster) {
                            clusterNode(cluster, canvas: canvas)
                        }
                    }
                }
                .frame(width: canvas.width, height: canvas.height)
            }

            toolbar
        }
        .background(Theme.Color.background)
        .onAppear(perform: loadLayouts)
        .transition(.opacity)
    }

    // MARK: - 顶栏

    private var header: some View {
        HStack(spacing: Theme.Spacing.sm) {
            PillButton(title: "返回", style: .secondary, action: onClose)
                .frame(width: 88)

            VStack(alignment: .leading, spacing: 1) {
                Text("触屏布局 · \(systemTitle)")
                    .font(Theme.Font.cardTitle)
                    .foregroundStyle(Theme.Color.textPrimary)
                Text("拖动移动 · 双指或滑杆调大小")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Color.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            PillButton(title: "恢复默认", style: .secondary) {
                mapping.resetTouchLayouts(forSystem: systemIdentifier)
                gestureOrigin = nil
                loadLayouts()
            }
            .frame(width: 100)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs)
        .background(Theme.Color.headerGradient)
    }

    private var systemTitle: String {
        GSSystemRegistry.info(forIdentifier: systemIdentifier)?.shortName ?? systemIdentifier
    }

    // MARK: - 画布

    private var canvasBackground: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            .fill(Theme.Color.surface.opacity(0.45))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .stroke(Theme.Color.border, lineWidth: 1)
            )
            .padding(Theme.Spacing.sm)
    }

    private func clusterNode(_ cluster: GSTouchCluster, canvas: CGSize) -> some View {
        let metrics = GamepadMetrics(area: canvas)
        let clusterLayout = layout(cluster)
        let box = metrics.box(for: cluster, clusterLayout: clusterLayout)
        let isSelected = selected == cluster

        return clusterContent(cluster, metrics: metrics, clusterLayout: clusterLayout)
            .frame(width: box.width, height: box.height)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .stroke(isSelected ? Theme.Color.accent : Theme.Color.border,
                            style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            )
            .contentShape(Rectangle())
            .gesture(dragGesture(cluster, canvas: canvas))
            .simultaneousGesture(magnifyGesture(cluster))
            .position(x: clusterLayout.x * canvas.width, y: clusterLayout.y * canvas.height)
    }

    @ViewBuilder
    private func clusterContent(_ cluster: GSTouchCluster,
                                metrics: GamepadMetrics,
                                clusterLayout: GSTouchClusterLayout) -> some View {
        switch cluster {
        case .dPad:
            DPadControl(size: metrics.dpadSize * clusterLayout.scale, interactive: false) { _ in }
        case .face:
            GamepadFaceCluster(diameter: metrics.faceDiameter * clusterLayout.scale,
                               hasFourFaceKeys: GSKeyMapping.systemUsesFourFaceKeys(systemIdentifier),
                               interactive: false)
        case .L, .R:
            GamepadKey(label: cluster == .L ? "L" : "R",
                       width: metrics.shoulderWidth * clusterLayout.scale,
                       height: metrics.shoulderHeight * clusterLayout.scale,
                       fontSize: 14 * clusterLayout.scale,
                       isHighlighted: false,
                       interactive: false)
        case .startSelect:
            HStack(spacing: metrics.pillSpacing * clusterLayout.scale) {
                GamepadKey(label: "SELECT",
                           width: metrics.pillWidth * clusterLayout.scale,
                           height: metrics.pillHeight * clusterLayout.scale,
                           fontSize: 11 * clusterLayout.scale,
                           isHighlighted: false,
                           interactive: false)
                GamepadKey(label: "START",
                           width: metrics.pillWidth * clusterLayout.scale,
                           height: metrics.pillHeight * clusterLayout.scale,
                           fontSize: 11 * clusterLayout.scale,
                           isHighlighted: false,
                           interactive: false)
            }
        case .menu:
            GamepadKey(label: "MENU",
                       width: metrics.menuWidth * clusterLayout.scale,
                       height: metrics.menuHeight * clusterLayout.scale,
                       fontSize: 11 * clusterLayout.scale,
                       isHighlighted: false,
                       interactive: false)
        case .touchScreen:
            GamepadTouchScreen(size: CGSize(width: metrics.touchScreenWidth * clusterLayout.scale,
                                            height: metrics.touchScreenHeight * clusterLayout.scale),
                               interactive: false)
        default:
            EmptyView()
        }
    }

    // MARK: - 手势

    private func dragGesture(_ cluster: GSTouchCluster, canvas: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                selected = cluster
                let origin = gestureOrigin ?? layout(cluster)
                if gestureOrigin == nil { gestureOrigin = origin }
                guard canvas.width > 0, canvas.height > 0 else { return }
                apply(GSTouchClusterLayout.make(
                    x: clamp01(origin.x + value.translation.width / canvas.width),
                    y: clamp01(origin.y + value.translation.height / canvas.height),
                    scale: origin.scale), to: cluster)
            }
            .onEnded { _ in commit() }
    }

    private func magnifyGesture(_ cluster: GSTouchCluster) -> some Gesture {
        MagnificationGesture()
            .onChanged { factor in
                selected = cluster
                let origin = gestureOrigin ?? layout(cluster)
                if gestureOrigin == nil { gestureOrigin = origin }
                apply(GSTouchClusterLayout.make(
                    x: origin.x,
                    y: origin.y,
                    scale: clampScale(origin.scale * factor)), to: cluster)
            }
            .onEnded { _ in commit() }
    }

    private func apply(_ clusterLayout: GSTouchClusterLayout, to cluster: GSTouchCluster) {
        layouts[cluster.rawValue] = clusterLayout
        // 只改内存，避免拖拽过程中每帧都写 JSON；落盘在 commit()
        mapping.setLayout(clusterLayout, for: cluster, system: systemIdentifier)
    }

    private func commit() {
        gestureOrigin = nil
        mapping.persist()
    }

    // MARK: - 底部工具条

    private var toolbar: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            clusterChips
            sizeSlider
            Text("每个系统各存一套：「\(systemTitle)」的布局只对它自己生效，改别的系统不会串。坐标按手柄可用区域归一化：横屏用整屏，竖屏用画面下方的操作区。")
                .font(.system(size: 11))
                .foregroundStyle(Theme.Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Color.backgroundElevated)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.Color.border).frame(height: 1)
        }
    }

    private var clusterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.xs) {
                ForEach(clusters.indices, id: \.self) { index in
                    let cluster = clusters[index]
                    Button {
                        selected = cluster
                    } label: {
                        Text(chipTitle(cluster))
                            .font(Theme.Font.chip)
                            .foregroundStyle(selected == cluster ? Theme.Color.background : Theme.Color.textPrimary)
                            .padding(.horizontal, Theme.Spacing.sm)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous)
                                    .fill(selected == cluster ? Theme.Color.accent : Theme.Color.surface)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous)
                                            .stroke(Theme.Color.border, lineWidth: 1)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func chipTitle(_ cluster: GSTouchCluster) -> String {
        let name = GSKeyMapping.displayName(forCluster: cluster, system: systemIdentifier)
        return isVisible(cluster) ? name : "\(name)（已隐藏）"
    }

    private var sizeSlider: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("「\(GSKeyMapping.displayName(forCluster: selected, system: systemIdentifier))」大小")
                    .font(Theme.Font.chip)
                    .foregroundStyle(Theme.Color.textSecondary)
                Spacer(minLength: 0)
                Text(String(format: "%.2f×", layout(selected).scale))
                    .font(Theme.Font.chip)
                    .foregroundStyle(Theme.Color.textPrimary)
            }
            Slider(value: scaleBinding, in: 0.6...1.6) { editing in
                if !editing { mapping.persist() }
            }
            .tint(Theme.Color.accent)
        }
    }

    private var scaleBinding: Binding<CGFloat> {
        Binding(
            get: { layout(selected).scale },
            set: { newValue in
                let current = layout(selected)
                apply(GSTouchClusterLayout.make(x: current.x, y: current.y, scale: newValue), to: selected)
            }
        )
    }

    // MARK: - 数据

    private func layout(_ cluster: GSTouchCluster) -> GSTouchClusterLayout {
        layouts[cluster.rawValue] ?? mapping.layout(for: cluster, system: systemIdentifier)
    }

    private func loadLayouts() {
        var seeded: [Int: GSTouchClusterLayout] = [:]
        for cluster in clusters {
            seeded[cluster.rawValue] = mapping.layout(for: cluster, system: systemIdentifier)
        }
        layouts = seeded
        if !clusters.contains(selected), let first = clusters.first {
            selected = first
        }
    }

    /// 该簇在播放器里是否显示（编辑器按显示状态如实呈现，做到所见即所得）
    private func isVisible(_ cluster: GSTouchCluster) -> Bool {
        mapping.isClusterVisible(cluster, forSystem: systemIdentifier)
    }

    private func clamp01(_ value: CGFloat) -> CGFloat {
        max(0, min(1, value))
    }

    private func clampScale(_ value: CGFloat) -> CGFloat {
        max(0.6, min(1.6, value))
    }
}

#endif
