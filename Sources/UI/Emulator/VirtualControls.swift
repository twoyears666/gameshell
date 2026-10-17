//
//  VirtualControls.swift
//  Gameshell
//
//  自绘虚拟手柄（操控布局参照 Delta / manic emu，不借鉴 RetroArch 的触屏菜单）。
//  全部用 SwiftUI 画出来，不引入任何第三方库，也不使用系统弹窗。
//
//  组成（按系统不同）：
//    · 左侧十字键：八向（含斜向）+ 拇指滑动
//    · 右侧 A / B（SNES / NDS 上是 A / B / X / Y 四键菱形）
//    · 底部 START / SELECT
//    · 顶部 L / R 肩键（8 位机没有）
//    · NDS 额外：Menu（切换暂停菜单）
//
//  NDS 的触摸屏（下屏）**不在手柄里**：它由播放器按核心渲染出的下屏矩形精确覆盖
//  （见 EmulatorView），所以触摸位置天然跟着真实下屏走，双屏布局怎么排都不会错位。
//
//  显示哪些按键、每个按键各自的位置与大小都**按系统区分**，来自 GSKeyMapping 的
//  touchElementsForSystem: / layoutForElement:forSystem:；
//  每个按键（A / B / X / Y / L / R / START / SELECT / MENU）都是**独立元素**，互不绑定；
//  设置页里的「布局编辑器」可以逐个拖拽调整，游玩界面里不可编辑。
//  按键状态合并成一个 GSButton 位掩码交给上层，最终进 GSEmulatorSession.setButtonMask(_:)；
//  Menu 走 onMenu 回调。
//

import SwiftUI

#if os(iOS)

// MARK: - 尺寸

/// 按键簇的底尺寸：按手柄可用区域自适应。
/// 播放器与设置页的布局编辑器共用这一份，避免两处各算一套导致对不上。
struct GamepadMetrics {
    let area: CGSize

    /// 十字键的边长（不含单元素缩放）
    var dpadSize: CGFloat { min(area.height * 0.86, max(96, min(area.width * 0.32, 168))) }
    var faceDiameter: CGFloat { dpadSize * 0.36 }
    var shoulderWidth: CGFloat { max(64, min(area.width * 0.19, 150)) }
    var shoulderHeight: CGFloat { max(30, min(area.height * 0.16, 44)) }
    var pillWidth: CGFloat { max(58, min(area.width * 0.16, 116)) }
    var pillHeight: CGFloat { max(28, min(area.height * 0.13, 38)) }
    /// Menu 是单个胶囊按键
    var menuWidth: CGFloat { pillWidth }
    var menuHeight: CGFloat { pillHeight }

    /// 某元素在给定布局下的尺寸 —— **每个按键各自一套**，播放器与编辑器共用（编辑器用它决定拖拽热区）
    func box(for element: GSTouchElement, layout: GSTouchElementLayout) -> CGSize {
        let scale = layout.scale
        switch element {
        case .dPad:
            return CGSize(width: dpadSize * scale, height: dpadSize * scale)
        case .A, .B, .X, .Y:
            return CGSize(width: faceDiameter * scale, height: faceDiameter * scale)
        case .L, .R:
            return CGSize(width: shoulderWidth * scale, height: shoulderHeight * scale)
        case .start, .select:
            return CGSize(width: pillWidth * scale, height: pillHeight * scale)
        case .menu:
            return CGSize(width: menuWidth * scale, height: menuHeight * scale)
        default:
            return CGSize(width: faceDiameter * scale, height: faceDiameter * scale)
        }
    }
}

// MARK: - 虚拟手柄

/// 虚拟手柄整体：按归一化布局自适应摆放每个按键。显示的按键与默认布局都按系统区分。
/// **每个按键都是独立元素**，各自有自己的位置与大小，互不绑定。
struct VirtualGamepad: View {

    /// 手柄可用的区域尺寸（横屏=整屏，竖屏=画面下方的操作区）
    let size: CGSize
    /// 三端键位配置：决定整体缩放 / 透明度 / 各按键是否显示，以及每个按键的位置与大小
    let mapping: GSKeyMapping
    /// 当前系统标识（nes / snes / gb / gbc / gba / nds），决定按键集合
    var systemIdentifier: String = ""
    /// 位掩码变化回调（按下/抬起都会回传一次完整掩码）
    var onMaskChange: (GSButton) -> Void
    /// Menu 键按下（切换游戏内暂停菜单；不参与位掩码）
    var onMenu: () -> Void = {}

    /// A / B / X / Y / L / R / START / SELECT 的按下状态
    @State private var held: GSButton = []
    /// 十字键的按下状态
    @State private var dpadMask: GSButton = []

    private var metrics: GamepadMetrics { GamepadMetrics(area: size) }

    private var combinedMask: GSButton { held.union(dpadMask) }

    /// 整体缩放：键位配置限制在 0.6 – 1.4
    private var scale: CGFloat { max(0.6, min(1.4, mapping.touchScale)) }
    /// 整体透明度：0.3 – 1.0
    private var opacity: Double { Double(max(0.3, min(1.0, mapping.touchOpacity))) }

    /// 当前系统有哪些按键元素
    private var elements: [GSTouchElement] {
        GSKeyMapping.touchElements(forSystem: systemIdentifier)
            .compactMap { GSTouchElement(rawValue: $0.intValue) }
    }

    /// 该元素在本系统里既存在、又处于显示状态
    private func shows(_ element: GSTouchElement) -> Bool {
        elements.contains(element) && mapping.isElementVisible(element, forSystem: systemIdentifier)
    }

    /// 某元素的布局（归一化中心 + 缩放）
    private func layout(_ element: GSTouchElement) -> GSTouchElementLayout {
        mapping.layout(for: element, system: systemIdentifier)
    }

    /// 某元素的中心点（像素）
    private func center(_ element: GSTouchElement) -> CGPoint {
        let elementLayout = layout(element)
        return CGPoint(x: elementLayout.x * size.width, y: elementLayout.y * size.height)
    }

    var body: some View {
        ZStack {
            // 空手白板：不参与命中，否则横屏时它会盖住画面、把 NDS 下屏的触摸一起吃掉
            SwiftUI.Color.clear.allowsHitTesting(false)

            if shows(.dPad) { dpadNode }
            if shows(.A) { keyNode(.A) }
            if shows(.B) { keyNode(.B) }
            if shows(.X) { keyNode(.X) }
            if shows(.Y) { keyNode(.Y) }
            if shows(.L) { keyNode(.L) }
            if shows(.R) { keyNode(.R) }
            if shows(.select) { keyNode(.select) }
            if shows(.start) { keyNode(.start) }
            if shows(.menu) { menuNode }
        }
        .frame(width: size.width, height: size.height)
        // 缩放 / 透明度直接作用在整块手柄上：命中区域会跟着一起变换，触按位置不会错位。
        .scaleEffect(scale)
        .opacity(opacity)
    }

    // MARK: - 各按键

    /// 左：十字键（整体元素，不拆四个方向）
    private var dpadNode: some View {
        let elementLayout = layout(.dPad)
        return DPadControl(size: metrics.dpadSize * elementLayout.scale) { mask in
            dpadMask = mask
            onMaskChange(combinedMask)
        }
        .position(center(.dPad))
    }

    /// 面键 / 肩键 / START / SELECT：每个按键各自一个独立按钮
    private func keyNode(_ element: GSTouchElement) -> some View {
        let elementLayout = layout(element)
        let box = metrics.box(for: element, layout: elementLayout)
        let bit = Self.button(for: element)
        return GamepadKey(label: Self.label(for: element),
                          width: box.width,
                          height: box.height,
                          fontSize: Self.fontSize(for: element, metrics: metrics, scale: elementLayout.scale),
                          isHighlighted: held.contains(bit)) { down in
            if down {
                held.formUnion(bit)
            } else {
                held.remove(bit)
            }
            onMaskChange(combinedMask)
        }
        .position(center(element))
    }

    /// NDS：Menu 键（等价顶栏的暂停，切换游戏内暂停菜单）
    private var menuNode: some View {
        let elementLayout = layout(.menu)
        return GamepadKey(label: "MENU",
                          width: metrics.menuWidth * elementLayout.scale,
                          height: metrics.menuHeight * elementLayout.scale,
                          fontSize: 11 * elementLayout.scale,
                          isHighlighted: false) { down in
            if down { onMenu() }
        }
        .position(center(.menu))
    }

    /// 元素 → GSButton 位（A/B/X/Y/L/R/START/SELECT；Menu 不参与位掩码，返回空集）
    private static func button(for element: GSTouchElement) -> GSButton {
        switch element {
        case .A:      return .A
        case .B:      return .B
        case .X:      return .X
        case .Y:      return .Y
        case .L:      return .L
        case .R:      return .R
        case .start:  return .start
        case .select: return .select
        default:      return []
        }
    }

    /// 元素 → 按键上的文字
    private static func label(for element: GSTouchElement) -> String {
        switch element {
        case .A:      return "A"
        case .B:      return "B"
        case .X:      return "X"
        case .Y:      return "Y"
        case .L:      return "L"
        case .R:      return "R"
        case .start:  return "START"
        case .select: return "SELECT"
        default:      return ""
        }
    }

    /// 元素 → 字号（跟各自的基础尺寸一起缩放）
    private static func fontSize(for element: GSTouchElement, metrics: GamepadMetrics, scale: CGFloat) -> CGFloat {
        switch element {
        case .A, .B, .X, .Y:         return metrics.faceDiameter * scale * 0.36
        case .L, .R:                 return 14 * scale
        case .start, .select, .menu: return 11 * scale
        default:                     return 12 * scale
        }
    }
}

// MARK: - 十字键

/// 十字键：按下点相对中心的偏移决定方向，支持八向与拇指滑动。
struct DPadControl: View {
    let size: CGFloat
    /// 是否响应触摸（布局编辑器里传 false，只当作可拖拽的图形）
    var interactive: Bool = true
    var onChange: (GSButton) -> Void

    @State private var mask: GSButton = []

    private var thickness: CGFloat { size * 0.34 }
    /// 单条臂从外边缘一直到中心
    private var armLength: CGFloat { size / 2 + thickness / 2 }

    var body: some View {
        if interactive {
            arms.gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in update(at: value.location) }
                    .onEnded { _ in apply([]) }
            )
        } else {
            arms
        }
    }

    private var arms: some View {
        ZStack {
            arm(.up)
            arm(.down)
            arm(.left)
            arm(.right)
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
    }

    private func arm(_ direction: GSButton) -> some View {
        let highlighted = mask.contains(direction)
        let horizontal = (direction == .left || direction == .right)
        let corner = thickness * 0.22

        return RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(highlighted ? Theme.Color.accent : Theme.Color.surface.opacity(0.92))
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(highlighted ? Theme.Color.accent : Theme.Color.border, lineWidth: 1.5)
            )
            .frame(width: horizontal ? armLength : thickness,
                   height: horizontal ? thickness : armLength)
            .position(x: centerX(direction), y: centerY(direction))
            .shadow(color: .black.opacity(0.3), radius: 5, y: 2)
            .animation(Theme.Motion.quick, value: highlighted)
    }

    private func centerX(_ direction: GSButton) -> CGFloat {
        switch direction {
        case .left: return armLength / 2
        case .right: return size - armLength / 2
        default: return size / 2
        }
    }

    private func centerY(_ direction: GSButton) -> CGFloat {
        switch direction {
        case .up: return armLength / 2
        case .down: return size - armLength / 2
        default: return size / 2
        }
    }

    /// 按触点到中心的偏移决定方向。死区取 12%，超过阈值的方向都算按下（于是斜向自然成立）。
    private func update(at point: CGPoint) {
        let dx = point.x - size / 2
        let dy = point.y - size / 2
        let deadZone = size * 0.12

        var next: GSButton = []
        if dx < -deadZone { next.formUnion(.left) }
        if dx > deadZone { next.formUnion(.right) }
        if dy < -deadZone { next.formUnion(.up) }
        if dy > deadZone { next.formUnion(.down) }
        apply(next)
    }

    private func apply(_ next: GSButton) {
        guard mask != next else { return }
        mask = next
        onChange(next)
    }
}

// MARK: - 单个按键

/// 一个「按住才亮」的虚拟按键。
/// 宽高相等时圆角等于半径，于是自动变成圆形（A / B / X / Y）；否则是胶囊（L / R / START / SELECT / MENU）。
struct GamepadKey: View {
    let label: String
    let width: CGFloat
    let height: CGFloat
    let fontSize: CGFloat
    let isHighlighted: Bool
    /// 是否响应触摸（布局编辑器里传 false，只当作可拖拽的图形）
    var interactive: Bool = true
    var onPress: (Bool) -> Void = { _ in }

    @State private var isDown = false

    private var active: Bool { isDown || isHighlighted }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: min(width, height) / 2, style: .continuous)
    }

    var body: some View {
        if interactive {
            face.gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !isDown else { return }
                        isDown = true
                        onPress(true)
                    }
                    .onEnded { _ in
                        guard isDown else { return }
                        isDown = false
                        onPress(false)
                    }
            )
        } else {
            face
        }
    }

    private var face: some View {
        Text(label)
            .font(.system(size: fontSize, weight: .semibold))
            .foregroundStyle(active ? SwiftUI.Color.black.opacity(0.88) : Theme.Color.textPrimary)
            .frame(width: width, height: height)
            .background(shape.fill(active ? Theme.Color.accent : Theme.Color.surface.opacity(0.92)))
            .overlay(shape.stroke(active ? Theme.Color.accent : Theme.Color.border, lineWidth: 1.5))
            .shadow(color: .black.opacity(0.32), radius: 6, y: 3)
            .contentShape(shape)
            .animation(Theme.Motion.quick, value: active)
    }
}

// MARK: - 触摸屏（NDS 下屏）

/// NDS 下屏触摸区：把区域内归一化坐标（0–1）交给上层（onTouch）。
///
/// 它由 EmulatorView 按核心渲染出的下屏矩形**精确覆盖**，所以这里给出的归一化坐标
/// 就是「下屏内坐标」，与核心 input.cpp 期待的 DS 下屏（256×192）一一对应，
/// 双屏怎么排（上下 / 左右 / 只下屏）都不会错位。
/// 外观刻意做得很淡 —— 只留一圈细描边，盖在真实画面上不碍事。
struct GamepadTouchScreen: View {

    let size: CGSize
    var onTouch: (CGPoint, Bool) -> Void = { _, _ in }

    @State private var lastPoint: CGPoint = CGPoint(x: 0.5, y: 0.5)

    var body: some View {
        face.gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in
                    let point = normalized(value.location)
                    lastPoint = point
                    onTouch(point, true)
                }
                .onEnded { _ in
                    onTouch(lastPoint, false)
                }
        )
    }

    private var face: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .stroke(Theme.Color.accent.opacity(0.4), lineWidth: 1)
            .frame(width: size.width, height: size.height)
            // 描边中间是空的：显式声明命中区，否则下屏中间那块触摸不到
            .contentShape(Rectangle())
    }

    private func normalized(_ location: CGPoint) -> CGPoint {
        guard size.width > 0, size.height > 0 else { return CGPoint(x: 0.5, y: 0.5) }
        return CGPoint(x: min(1, max(0, location.x / size.width)),
                       y: min(1, max(0, location.y / size.height)))
    }
}

#endif
