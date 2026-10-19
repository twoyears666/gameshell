//
//  TouchLayoutEditor.swift
//  Gameshell
//
//  触屏手柄的「布局编辑器」：逐个拖拽移动每个按键、双指或滑杆调整大小。
//
//  入口只在设置页里（触摸卡片上的「编辑布局」），游玩界面（EmulatorView）不提供编辑入口，
//  避免玩到一半误触把布局拖乱。编辑的是**当前所选系统**的布局（各系统分开保存）。
//  每个按键（A / B / X / Y / L / R / START / SELECT / MENU）都是**独立元素**，互不绑定；
//  十字键是整体元素。改完立即写回 GSKeyMapping 内存，松手时落盘到 keymap.json。
//  坐标是归一化的（相对手柄可用区域），所以横竖屏各自按自己的区域生效。
//
//  注意：NDS 的触摸屏（下屏）**不在这里摆放** —— 它在播放器里由核心渲染出的下屏矩形
//  精确覆盖，位置与大小跟着双屏布局走（上下 / 左右 / 只下屏），无需也没有必要手工拖拽。
//  它是否显示仍然由「触屏手柄」卡片里的「显示 触摸屏」开关决定。
//

#if os(iOS)

import SwiftUI

struct TouchLayoutEditor: View {

    let mapping: GSKeyMapping
    /// 正在编辑哪个系统（nes / snes / gb / gbc / gba / nds）
    let systemIdentifier: String
    let onClose: () -> Void

    /// 编辑器内自己持一份布局，拖拽时即时重绘；松手 / 松滑杆时落盘。
    @State private var layouts: [Int: GSTouchElementLayout] = [:]
    @State private var selected: GSTouchElement = .dPad
    /// 一次拖拽 / 缩放的起点（手势过程中不变，避免累积误差）
    @State private var gestureOrigin: GSTouchElementLayout?

    /// 该系统的按键元素集合。
    /// 不含触摸屏：NDS 下屏的位置与大小由画面里的下屏矩形决定，不在这里摆放。
    private var elements: [GSTouchElement] {
        GSKeyMapping.touchElements(forSystem: systemIdentifier)
            .compactMap { GSTouchElement(rawValue: $0.intValue) }
            .filter { $0 != .touchScreen }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            GeometryReader { proxy in
                let canvas = proxy.size
                ZStack(alignment: .topLeading) {
                    canvasBackground
                    ForEach(elements.indices, id: \.self) { index in
                        let element = elements[index]
                        if isVisible(element) {
                            elementNode(element, canvas: canvas)
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
                Text("每个按键各自拖动 · 双指或滑杆调大小")
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

    private func elementNode(_ element: GSTouchElement, canvas: CGSize) -> some View {
        let metrics = GamepadMetrics(area: canvas)
        let elementLayout = layout(element)
        let box = metrics.box(for: element, layout: elementLayout)
        let isSelected = selected == element

        return elementContent(element, metrics: metrics)
            .frame(width: box.width, height: box.height)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .stroke(isSelected ? Theme.Color.accent : Theme.Color.border,
                            style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            )
            .contentShape(Rectangle())
            // 关键：先摆位置（.position），再挂手势。
            // 若把 .position 放在 .gesture 之后，命中区会停在旧位置、与画出来的位置错位，于是「拖不动」。
            .position(x: elementLayout.x * canvas.width, y: elementLayout.y * canvas.height)
            .gesture(dragGesture(element, canvas: canvas))
            .simultaneousGesture(magnifyGesture(element))
    }

    @ViewBuilder
    private func elementContent(_ element: GSTouchElement, metrics: GamepadMetrics) -> some View {
        let elementLayout = layout(element)
        switch element {
        case .dPad:
            DPadControl(size: metrics.dpadSize * elementLayout.scale, interactive: false) { _ in }
        case .A, .B, .X, .Y, .L, .R, .ZL, .ZR, .start, .select, .menu, .home:
            keyView(element, metrics: metrics, elementLayout: elementLayout)
        default:
            EmptyView()
        }
    }

    private func keyView(_ element: GSTouchElement,
                         metrics: GamepadMetrics,
                         elementLayout: GSTouchElementLayout) -> some View {
        let box = metrics.box(for: element, layout: elementLayout)
        return GamepadKey(label: Self.label(for: element),
                          width: box.width,
                          height: box.height,
                          fontSize: Self.fontSize(for: element, metrics: metrics, scale: elementLayout.scale),
                          isHighlighted: false,
                          interactive: false)
    }

    // MARK: - 手势

    private func dragGesture(_ element: GSTouchElement, canvas: CGSize) -> some Gesture {
        // 用全局坐标系：视图自身在拖动过程中会移动，用 .local 会把位移算歪、抖成鬼畜。
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                selected = element
                let origin = gestureOrigin ?? layout(element)
                if gestureOrigin == nil { gestureOrigin = origin }
                guard canvas.width > 0, canvas.height > 0 else { return }
                apply(GSTouchElementLayout.make(
                    x: clamp01(origin.x + value.translation.width / canvas.width),
                    y: clamp01(origin.y + value.translation.height / canvas.height),
                    scale: origin.scale), to: element)
            }
            .onEnded { _ in commit() }
    }

    private func magnifyGesture(_ element: GSTouchElement) -> some Gesture {
        MagnificationGesture()
            .onChanged { factor in
                selected = element
                let origin = gestureOrigin ?? layout(element)
                if gestureOrigin == nil { gestureOrigin = origin }
                apply(GSTouchElementLayout.make(
                    x: origin.x,
                    y: origin.y,
                    scale: clampScale(origin.scale * factor)), to: element)
            }
            .onEnded { _ in commit() }
    }

    private func apply(_ elementLayout: GSTouchElementLayout, to element: GSTouchElement) {
        layouts[element.rawValue] = elementLayout
        // 只改内存，避免拖拽过程中每帧都写 JSON；落盘在 commit()
        mapping.setLayout(elementLayout, for: element, system: systemIdentifier)
    }

    private func commit() {
        gestureOrigin = nil
        mapping.persist()
    }

    // MARK: - 底部工具条

    private var toolbar: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            elementChips
            sizeSlider
            Text("每个按键都是独立的：位置与大小各自一套，改这个不会动到别的按键。屏幕坐标按手柄可用区域归一化：横屏用整屏，竖屏用画面下方的操作区。布局只对「\(systemTitle)」生效。"
                 + (systemIdentifier == "nds" ? " NDS 的触摸屏（下屏）不在这里摆放：它跟着画面里的下屏走，由 NDS 设置里的双屏布局决定。" : ""))
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

    private var elementChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.xs) {
                ForEach(elements.indices, id: \.self) { index in
                    let element = elements[index]
                    Button {
                        selected = element
                    } label: {
                        Text(chipTitle(element))
                            .font(Theme.Font.chip)
                            .foregroundStyle(selected == element ? Theme.Color.background : Theme.Color.textPrimary)
                            .padding(.horizontal, Theme.Spacing.sm)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous)
                                    .fill(selected == element ? Theme.Color.accent : Theme.Color.surface)
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

    private func chipTitle(_ element: GSTouchElement) -> String {
        let name = GSKeyMapping.displayName(forElement: element)
        return isVisible(element) ? name : "\(name)（已隐藏）"
    }

    private var sizeSlider: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("「\(GSKeyMapping.displayName(forElement: selected))」大小")
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

            // 便捷功能：把当前这个按键的大小一次性应用到本系统所有按键（触摸屏是屏、不是按键，不动它）。
            PillButton(title: "把这个大小应用到所有按键", style: .secondary) {
                mapping.applyScale(layout(selected).scale, toAllElementsForSystem: systemIdentifier)
                gestureOrigin = nil
                loadLayouts()
            }
            .padding(.top, Theme.Spacing.xxs)
        }
    }

    private var scaleBinding: Binding<CGFloat> {
        Binding(
            get: { layout(selected).scale },
            set: { newValue in
                let current = layout(selected)
                apply(GSTouchElementLayout.make(x: current.x, y: current.y, scale: newValue), to: selected)
            }
        )
    }

    // MARK: - 数据

    private func layout(_ element: GSTouchElement) -> GSTouchElementLayout {
        layouts[element.rawValue] ?? mapping.layout(for: element, system: systemIdentifier)
    }

    private func loadLayouts() {
        var seeded: [Int: GSTouchElementLayout] = [:]
        for element in elements {
            seeded[element.rawValue] = mapping.layout(for: element, system: systemIdentifier)
        }
        layouts = seeded
        if !elements.contains(selected), let first = elements.first {
            selected = first
        }
    }

    /// 该元素在播放器里是否显示（编辑器按显示状态如实呈现，做到所见即所得）
    private func isVisible(_ element: GSTouchElement) -> Bool {
        mapping.isElementVisible(element, forSystem: systemIdentifier)
    }

    private func clamp01(_ value: CGFloat) -> CGFloat {
        max(0, min(1, value))
    }

    private func clampScale(_ value: CGFloat) -> CGFloat {
        max(0.6, min(1.6, value))
    }

    /// 元素 → 按键上的文字（短标签，与播放器一致）
    private static func label(for element: GSTouchElement) -> String {
        switch element {
        case .A:      return "A"
        case .B:      return "B"
        case .X:      return "X"
        case .Y:      return "Y"
        case .L:      return "L"
        case .R:      return "R"
        case .ZL:     return "ZL"
        case .ZR:     return "ZR"
        case .home:   return "HOME"
        case .start:  return "START"
        case .select: return "SELECT"
        case .menu:   return "MENU"
        default:      return ""
        }
    }

    private static func fontSize(for element: GSTouchElement, metrics: GamepadMetrics, scale: CGFloat) -> CGFloat {
        switch element {
        case .A, .B, .X, .Y:         return metrics.faceDiameter * scale * 0.36
        case .L, .R, .ZL, .ZR:       return 14 * scale
        case .start, .select, .menu: return 11 * scale
        case .home:                  return 11 * scale
        default:                     return 12 * scale
        }
    }
}

#endif
