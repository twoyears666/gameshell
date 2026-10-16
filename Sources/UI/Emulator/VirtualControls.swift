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
//    · NDS 额外：Menu（切换暂停菜单）+ 触摸屏（下屏）
//
//  显示哪些簇、各簇默认位置与大小都**按系统区分**，来自 GSKeyMapping 的
//  touchClustersForSystem: / layoutForCluster:forSystem:；
//  设置页里的「布局编辑器」可以拖拽调整，游玩界面里不可编辑。
//  按键状态合并成一个 GSButton 位掩码交给上层，最终进 GSEmulatorSession.setButtonMask(_:)；
//  触摸屏另走 onTouch 归一化坐标，Menu 走 onMenu 回调。
//

import SwiftUI

#if os(iOS)

// MARK: - 尺寸

/// 按键簇的底尺寸：按手柄可用区域自适应。
/// 播放器与设置页的布局编辑器共用这一份，避免两处各算一套导致对不上。
struct GamepadMetrics {
    let area: CGSize

    /// 十字键的边长（不含簇缩放）
    var dpadSize: CGFloat { min(area.height * 0.86, max(96, min(area.width * 0.32, 168))) }
    var faceDiameter: CGFloat { dpadSize * 0.36 }
    var faceClusterSize: CGFloat { faceDiameter * 2.6 }
    var shoulderWidth: CGFloat { max(64, min(area.width * 0.19, 150)) }
    var shoulderHeight: CGFloat { max(30, min(area.height * 0.16, 44)) }
    var pillWidth: CGFloat { max(58, min(area.width * 0.16, 116)) }
    var pillHeight: CGFloat { max(28, min(area.height * 0.13, 38)) }
    var pillSpacing: CGFloat { max(8, pillWidth * 0.14) }
    /// Menu 是单个胶囊按键
    var menuWidth: CGFloat { pillWidth }
    var menuHeight: CGFloat { pillHeight }
    /// NDS 下屏触摸区（4:3，与 DS 下屏 256×192 同比例）
    var touchScreenWidth: CGFloat { max(120, min(area.width * 0.34, 240)) }
    var touchScreenHeight: CGFloat { touchScreenWidth * 0.75 }

    /// 某簇在给定布局下的包围盒尺寸（布局编辑器用它决定拖拽热区）
    func box(for cluster: GSTouchCluster, clusterLayout: GSTouchClusterLayout) -> CGSize {
        let scale = clusterLayout.scale
        switch cluster {
        case .dPad:
            return CGSize(width: dpadSize * scale, height: dpadSize * scale)
        case .face:
            return CGSize(width: faceClusterSize * scale, height: faceClusterSize * scale)
        case .L, .R:
            return CGSize(width: shoulderWidth * scale, height: shoulderHeight * scale)
        case .startSelect:
            return CGSize(width: (pillWidth * 2 + pillSpacing) * scale, height: pillHeight * scale)
        case .menu:
            return CGSize(width: menuWidth * scale, height: menuHeight * scale)
        case .touchScreen:
            return CGSize(width: touchScreenWidth * scale, height: touchScreenHeight * scale)
        default:
            return CGSize(width: 48, height: 48)
        }
    }
}

// MARK: - 虚拟手柄

/// 虚拟手柄整体：按归一化布局自适应摆放各按键簇。显示的簇与默认布局都按系统区分。
struct VirtualGamepad: View {

    /// 手柄可用的区域尺寸（横屏=整屏，竖屏=画面下方的操作区）
    let size: CGSize
    /// 三端键位配置：决定整体缩放 / 透明度 / 各按键簇是否显示，以及每簇的位置与大小
    let mapping: GSKeyMapping
    /// 当前系统标识（nes / snes / gb / gbc / gba / nds），决定按键簇集合与四键形态
    var systemIdentifier: String = ""
    /// 位掩码变化回调（按下/抬起都会回传一次完整掩码）
    var onMaskChange: (GSButton) -> Void
    /// 触摸屏簇拖动：归一化坐标（0–1，相对触摸区）+ 是否按下
    var onTouch: (CGPoint, Bool) -> Void = { _, _ in }
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

    /// 当前系统有哪些按键簇
    private var clusters: [GSTouchCluster] {
        GSKeyMapping.touchClusters(forSystem: systemIdentifier)
            .compactMap { GSTouchCluster(rawValue: $0.intValue) }
    }

    /// 该簇在本系统里既存在、又处于显示状态
    private func shows(_ cluster: GSTouchCluster) -> Bool {
        clusters.contains(cluster) && mapping.isClusterVisible(cluster, forSystem: systemIdentifier)
    }

    /// 某簇的布局（归一化中心 + 缩放）
    private func layout(_ cluster: GSTouchCluster) -> GSTouchClusterLayout {
        mapping.layout(for: cluster, system: systemIdentifier)
    }

    /// 某簇的中心点（像素）
    private func center(_ cluster: GSTouchCluster) -> CGPoint {
        let clusterLayout = layout(cluster)
        return CGPoint(x: clusterLayout.x * size.width, y: clusterLayout.y * size.height)
    }

    var body: some View {
        ZStack {
            SwiftUI.Color.clear

            if shows(.dPad) { dpadNode }
            if shows(.face) { faceNode }
            if shows(.L) { shoulderNode(.L) }
            if shows(.R) { shoulderNode(.R) }
            if shows(.startSelect) { startSelectNode }
            if shows(.menu) { menuNode }
            if shows(.touchScreen) { touchScreenNode }
        }
        .frame(width: size.width, height: size.height)
        // 缩放 / 透明度直接作用在整块手柄上：命中区域会跟着一起变换，触按位置不会错位。
        .scaleEffect(scale)
        .opacity(opacity)
    }

    // MARK: - 各按键簇

    /// 左：十字键
    private var dpadNode: some View {
        let clusterLayout = layout(.dPad)
        return DPadControl(size: metrics.dpadSize * clusterLayout.scale) { mask in
            dpadMask = mask
            onMaskChange(combinedMask)
        }
        .position(center(.dPad))
    }

    /// 右：A / B（四键系统上是 A / B / X / Y 菱形）
    private var faceNode: some View {
        let clusterLayout = layout(.face)
        return GamepadFaceCluster(diameter: metrics.faceDiameter * clusterLayout.scale,
                                  hasFourFaceKeys: GSKeyMapping.systemUsesFourFaceKeys(systemIdentifier),
                                  held: held) { bit, down in
            if down {
                held.formUnion(bit)
            } else {
                held.remove(bit)
            }
            onMaskChange(combinedMask)
        }
        .position(center(.face))
    }

    /// 顶部两角：L 或 R（8 位机没有这个簇）
    private func shoulderNode(_ cluster: GSTouchCluster) -> some View {
        let clusterLayout = layout(cluster)
        let isLeft = (cluster == .L)
        return key(label: isLeft ? "L" : "R",
                   bit: isLeft ? .L : .R,
                   width: metrics.shoulderWidth * clusterLayout.scale,
                   height: metrics.shoulderHeight * clusterLayout.scale,
                   fontSize: 14 * clusterLayout.scale)
            .position(center(cluster))
    }

    /// 底部中间：START / SELECT
    private var startSelectNode: some View {
        let clusterLayout = layout(.startSelect)
        return HStack(spacing: metrics.pillSpacing * clusterLayout.scale) {
            key(label: "SELECT", bit: .select,
                width: metrics.pillWidth * clusterLayout.scale,
                height: metrics.pillHeight * clusterLayout.scale,
                fontSize: 11 * clusterLayout.scale)
            key(label: "START", bit: .start,
                width: metrics.pillWidth * clusterLayout.scale,
                height: metrics.pillHeight * clusterLayout.scale,
                fontSize: 11 * clusterLayout.scale)
        }
        .position(center(.startSelect))
    }

    /// NDS：Menu 键（等价顶栏的暂停，切换游戏内暂停菜单）
    private var menuNode: some View {
        let clusterLayout = layout(.menu)
        return GamepadKey(label: "MENU",
                          width: metrics.menuWidth * clusterLayout.scale,
                          height: metrics.menuHeight * clusterLayout.scale,
                          fontSize: 11 * clusterLayout.scale,
                          isHighlighted: false) { down in
            if down { onMenu() }
        }
        .position(center(.menu))
    }

    /// NDS：触摸屏（下屏触摸区）
    private var touchScreenNode: some View {
        let clusterLayout = layout(.touchScreen)
        return GamepadTouchScreen(size: CGSize(width: metrics.touchScreenWidth * clusterLayout.scale,
                                               height: metrics.touchScreenHeight * clusterLayout.scale),
                                  onTouch: onTouch)
            .position(center(.touchScreen))
    }

    private func key(label: String,
                     bit: GSButton,
                     width: CGFloat,
                     height: CGFloat,
                     fontSize: CGFloat) -> some View {
        GamepadKey(label: label,
                   width: width,
                   height: height,
                   fontSize: fontSize,
                   isHighlighted: held.contains(bit)) { down in
            if down {
                held.formUnion(bit)
            } else {
                held.remove(bit)
            }
            onMaskChange(combinedMask)
        }
    }
}

// MARK: - A / B（或 A / B / X / Y）簇

/// 面键簇。两键时是「左下 B、右上 A」的斜向排布（照 Delta GBA）；
/// 四键时是 A/B/X/Y 菱形（SNES / NDS）。播放器与布局编辑器共用同一份外观。
struct GamepadFaceCluster: View {
    let diameter: CGFloat
    /// 是否画成 A / B / X / Y 四键（SNES / NDS 为 true）
    var hasFourFaceKeys: Bool = false
    /// 当前按下的位掩码（高亮用）
    var held: GSButton = []
    /// 是否响应触摸（布局编辑器里传 false，只当作可拖拽的图形）
    var interactive: Bool = true
    var onPress: (GSButton, Bool) -> Void = { _, _ in }

    private var clusterSize: CGFloat { diameter * 2.6 }

    var body: some View {
        ZStack {
            if hasFourFaceKeys {
                // 菱形：X 上 / A 右 / B 下 / Y 左
                faceKey(.X, offset: CGPoint(x: 0, y: -diameter * 0.46))
                faceKey(.A, offset: CGPoint(x: diameter * 0.46, y: 0))
                faceKey(.B, offset: CGPoint(x: 0, y: diameter * 0.46))
                faceKey(.Y, offset: CGPoint(x: -diameter * 0.46, y: 0))
            } else {
                faceKey(.B, offset: CGPoint(x: -diameter * 0.40, y: diameter * 0.40))
                faceKey(.A, offset: CGPoint(x: diameter * 0.46, y: -diameter * 0.30))
            }
        }
        .frame(width: clusterSize, height: clusterSize)
    }

    private func faceKey(_ bit: GSButton, offset: CGPoint) -> some View {
        GamepadKey(label: Self.label(for: bit),
                   width: diameter,
                   height: diameter,
                   fontSize: diameter * 0.36,
                   isHighlighted: held.contains(bit),
                   interactive: interactive) { down in
            onPress(bit, down)
        }
        .offset(x: offset.x, y: offset.y)
    }

    private static func label(for bit: GSButton) -> String {
        if bit == .A { return "A" }
        if bit == .B { return "B" }
        if bit == .X { return "X" }
        if bit == .Y { return "Y" }
        return "?"
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

/// 触摸屏按键簇：按住拖动，把簇内相对坐标（0–1）交给上层（onTouch）。
/// 诚实的边界：这里给的是「触摸区自身」的归一化坐标，**不等于**渲染出来的下屏像素坐标，
/// 也没有与画面上真实的下屏位置对齐 —— 它是一块专门的触摸板，核心按 DS 下屏（256×192）解释它。
/// 布局编辑器里 interactive 传 false，只当作可拖拽的图形。
struct GamepadTouchScreen: View {
    let size: CGSize
    /// 是否响应触摸（布局编辑器里传 false，只当作可拖拽的图形）
    var interactive: Bool = true
    var onTouch: (CGPoint, Bool) -> Void = { _, _ in }

    @State private var lastPoint: CGPoint = CGPoint(x: 0.5, y: 0.5)

    var body: some View {
        if interactive {
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
        } else {
            face
        }
    }

    private var face: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
            .fill(Theme.Color.accent.opacity(0.16))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .stroke(Theme.Color.accent.opacity(0.75), lineWidth: 1.5)
            )
            .overlay(
                VStack(spacing: 2) {
                    Image(systemName: "hand.tap")
                        .font(.system(size: 15, weight: .semibold))
                    Text("触摸屏")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(Theme.Color.accent)
                .allowsHitTesting(false)
            )
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
    }

    private func normalized(_ location: CGPoint) -> CGPoint {
        guard size.width > 0, size.height > 0 else { return CGPoint(x: 0.5, y: 0.5) }
        return CGPoint(x: min(1, max(0, location.x / size.width)),
                       y: min(1, max(0, location.y / size.height)))
    }
}

#endif
