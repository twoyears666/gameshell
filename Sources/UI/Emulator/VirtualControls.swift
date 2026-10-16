//
//  VirtualControls.swift
//  Gameshell
//
//  自绘虚拟手柄（操控布局参照 Delta / manic emu，不借鉴 RetroArch 的触屏菜单）。
//  全部用 SwiftUI 画出来，不引入任何第三方库，也不使用系统弹窗。
//
//  组成：
//    · 左侧十字键：八向（含斜向）+ 拇指滑动
//    · 右侧 A / B：斜向排布（左下 B、右上 A）
//    · 底部 START / SELECT
//    · 顶部 L / R 肩键
//
//  各按键簇显示与否、整体缩放与透明度都来自 GSKeyMapping；
//  每一簇的**位置与大小**另由 GSKeyMapping 的 GSTouchClusterLayout 决定（归一化坐标），
//  设置页里的「布局编辑器」可以拖拽调整，游玩界面里不可编辑。
//  所有按键状态合并成一个 GSButton 位掩码交给上层，最终进 GSEmulatorSession.setButtonMask(_:)。
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
        default:
            return CGSize(width: 48, height: 48)
        }
    }
}

// MARK: - 虚拟手柄

/// 虚拟手柄整体：按归一化布局自适应摆放各按键簇。
struct VirtualGamepad: View {

    /// 手柄可用的区域尺寸（横屏=整屏，竖屏=画面下方的操作区）
    let size: CGSize
    /// 三端键位配置：决定整体缩放 / 透明度 / 各按键簇是否显示，以及每簇的位置与大小
    let mapping: GSKeyMapping
    /// 位掩码变化回调（按下/抬起都会回传一次完整掩码）
    var onMaskChange: (GSButton) -> Void

    /// A / B / L / R / START / SELECT 的按下状态
    @State private var held: GSButton = []
    /// 十字键的按下状态
    @State private var dpadMask: GSButton = []

    private var metrics: GamepadMetrics { GamepadMetrics(area: size) }

    private var combinedMask: GSButton { held.union(dpadMask) }

    /// 整体缩放：键位配置限制在 0.6 – 1.4
    private var scale: CGFloat { max(0.6, min(1.4, mapping.touchScale)) }
    /// 整体透明度：0.3 – 1.0
    private var opacity: Double { Double(max(0.3, min(1.0, mapping.touchOpacity))) }

    /// 某簇的布局（归一化中心 + 缩放）
    private func layout(_ cluster: GSTouchCluster) -> GSTouchClusterLayout {
        mapping.layout(for: cluster)
    }

    /// 某簇的中心点（像素）
    private func center(_ cluster: GSTouchCluster) -> CGPoint {
        let clusterLayout = layout(cluster)
        return CGPoint(x: clusterLayout.x * size.width, y: clusterLayout.y * size.height)
    }

    var body: some View {
        ZStack {
            SwiftUI.Color.clear

            if mapping.touchShowDPad { dpadNode }
            if mapping.touchShowFace { faceNode }
            if mapping.touchShowShoulders { shoulderNodes }
            if mapping.touchShowStartSelect { startSelectNode }
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

    /// 右：A / B
    private var faceNode: some View {
        let clusterLayout = layout(.face)
        return GamepadFaceCluster(diameter: metrics.faceDiameter * clusterLayout.scale,
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

    /// 顶部：L / R
    @ViewBuilder
    private var shoulderNodes: some View {
        let left = layout(.L)
        key(label: "L", bit: .L,
            width: metrics.shoulderWidth * left.scale,
            height: metrics.shoulderHeight * left.scale,
            fontSize: 14 * left.scale)
            .position(center(.L))

        let right = layout(.R)
        key(label: "R", bit: .R,
            width: metrics.shoulderWidth * right.scale,
            height: metrics.shoulderHeight * right.scale,
            fontSize: 14 * right.scale)
            .position(center(.R))
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

// MARK: - A / B 簇

/// A / B 簇（左下 B、右上 A 的斜向排布）。播放器与布局编辑器共用同一份外观。
struct GamepadFaceCluster: View {
    let diameter: CGFloat
    /// 当前按下的位掩码（高亮用）
    var held: GSButton = []
    /// 是否响应触摸（布局编辑器里传 false，只当作可拖拽的图形）
    var interactive: Bool = true
    var onPress: (GSButton, Bool) -> Void = { _, _ in }

    private var clusterSize: CGFloat { diameter * 2.6 }

    var body: some View {
        ZStack {
            GamepadKey(label: "B",
                       width: diameter,
                       height: diameter,
                       fontSize: diameter * 0.36,
                       isHighlighted: held.contains(.B),
                       interactive: interactive) { down in
                onPress(.B, down)
            }
            .offset(x: -diameter * 0.40, y: diameter * 0.40)

            GamepadKey(label: "A",
                       width: diameter,
                       height: diameter,
                       fontSize: diameter * 0.36,
                       isHighlighted: held.contains(.A),
                       interactive: interactive) { down in
                onPress(.A, down)
            }
            .offset(x: diameter * 0.46, y: -diameter * 0.30)
        }
        .frame(width: clusterSize, height: clusterSize)
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
/// 宽高相等时圆角等于半径，于是自动变成圆形（A / B）；否则是胶囊（L / R / START / SELECT）。
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

#endif
