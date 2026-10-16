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
//  各按键簇显示与否、整体缩放与透明度都来自 GSKeyMapping（设置页里可调）。
//  所有按键状态合并成一个 GSButton 位掩码交给上层，最终进 GSEmulatorSession.setButtonMask(_:)。
//

import SwiftUI

#if os(iOS)

/// 虚拟手柄整体：按给定的可用区域自适应摆放各按键。
struct VirtualGamepad: View {

    /// 手柄可用的区域尺寸（横屏=整屏，竖屏=画面下方的操作区）
    let size: CGSize
    /// 三端键位配置：决定缩放 / 透明度 / 各按键簇是否显示
    let mapping: GSKeyMapping
    /// 位掩码变化回调（按下/抬起都会回传一次完整掩码）
    var onMaskChange: (GSButton) -> Void

    /// A / B / L / R / START / SELECT 的按下状态
    @State private var held: GSButton = []
    /// 十字键的按下状态
    @State private var dpadMask: GSButton = []

    private var combinedMask: GSButton { held.union(dpadMask) }

    /// 整体缩放：键位配置限制在 0.6 – 1.4
    private var scale: CGFloat { max(0.6, min(1.4, mapping.touchScale)) }
    /// 整体透明度：0.3 – 1.0
    private var opacity: Double { Double(max(0.3, min(1.0, mapping.touchOpacity))) }

    var body: some View {
        ZStack {
            SwiftUI.Color.clear

            // 左：十字键
            if mapping.touchShowDPad {
                DPadControl(size: dpadSize) { mask in
                    dpadMask = mask
                    onMaskChange(combinedMask)
                }
                .position(x: margin + dpadSize / 2, y: size.height - margin - dpadSize / 2)
            }

            // 右：A / B
            if mapping.touchShowFace {
                faceCluster
                    .position(x: size.width - margin - faceClusterSize / 2,
                              y: size.height - margin - faceClusterSize / 2)
            }

            // 顶部：L / R
            if mapping.touchShowShoulders {
                key(label: "L", bit: .L, width: shoulderWidth, height: shoulderHeight, fontSize: 14)
                    .position(x: margin + shoulderWidth / 2, y: margin + shoulderHeight / 2)
                key(label: "R", bit: .R, width: shoulderWidth, height: shoulderHeight, fontSize: 14)
                    .position(x: size.width - margin - shoulderWidth / 2, y: margin + shoulderHeight / 2)
            }

            // 底部中间：START / SELECT
            if mapping.touchShowStartSelect {
                HStack(spacing: pillSpacing) {
                    key(label: "SELECT", bit: .select, width: pillWidth, height: pillHeight, fontSize: 11)
                    key(label: "START", bit: .start, width: pillWidth, height: pillHeight, fontSize: 11)
                }
                .position(x: size.width / 2, y: size.height - margin - pillHeight / 2)
            }
        }
        .frame(width: size.width, height: size.height)
        // 缩放 / 透明度直接作用在整块手柄上：命中区域会跟着一起变换，触按位置不会错位。
        .scaleEffect(scale)
        .opacity(opacity)
    }

    // MARK: - 尺寸

    private var margin: CGFloat { max(10, min(size.width, size.height) * 0.03) }

    private var dpadSize: CGFloat { min(size.height * 0.86, max(96, min(size.width * 0.32, 168))) }

    private var faceDiameter: CGFloat { dpadSize * 0.36 }

    private var faceClusterSize: CGFloat { faceDiameter * 2.6 }

    private var shoulderWidth: CGFloat { max(64, min(size.width * 0.19, 150)) }

    private var shoulderHeight: CGFloat { max(30, min(size.height * 0.16, 44)) }

    private var pillWidth: CGFloat { max(58, min(size.width * 0.16, 116)) }

    private var pillHeight: CGFloat { max(28, min(size.height * 0.13, 38)) }

    private var pillSpacing: CGFloat { max(8, pillWidth * 0.14) }

    // MARK: - 组装

    private var faceCluster: some View {
        ZStack {
            key(label: "B", bit: .B, width: faceDiameter, height: faceDiameter,
                fontSize: faceDiameter * 0.36)
                .offset(x: -faceDiameter * 0.40, y: faceDiameter * 0.40)

            key(label: "A", bit: .A, width: faceDiameter, height: faceDiameter,
                fontSize: faceDiameter * 0.36)
                .offset(x: faceDiameter * 0.46, y: -faceDiameter * 0.30)
        }
        .frame(width: faceClusterSize, height: faceClusterSize)
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

// MARK: - 十字键

/// 十字键：按下点相对中心的偏移决定方向，支持八向与拇指滑动。
private struct DPadControl: View {
    let size: CGFloat
    var onChange: (GSButton) -> Void

    @State private var mask: GSButton = []

    private var thickness: CGFloat { size * 0.34 }
    /// 单条臂从外边缘一直到中心
    private var armLength: CGFloat { size / 2 + thickness / 2 }

    var body: some View {
        ZStack {
            arm(.up)
            arm(.down)
            arm(.left)
            arm(.right)
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in update(at: value.location) }
                .onEnded { _ in apply([]) }
        )
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
private struct GamepadKey: View {
    let label: String
    let width: CGFloat
    let height: CGFloat
    let fontSize: CGFloat
    let isHighlighted: Bool
    var onPress: (Bool) -> Void

    @State private var isDown = false

    private var active: Bool { isDown || isHighlighted }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: min(width, height) / 2, style: .continuous)
    }

    var body: some View {
        Text(label)
            .font(.system(size: fontSize, weight: .semibold))
            .foregroundStyle(active ? SwiftUI.Color.black.opacity(0.88) : Theme.Color.textPrimary)
            .frame(width: width, height: height)
            .background(shape.fill(active ? Theme.Color.accent : Theme.Color.surface.opacity(0.92)))
            .overlay(shape.stroke(active ? Theme.Color.accent : Theme.Color.border, lineWidth: 1.5))
            .shadow(color: .black.opacity(0.32), radius: 6, y: 3)
            .contentShape(shape)
            .animation(Theme.Motion.quick, value: active)
            .gesture(
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
    }
}

#endif
