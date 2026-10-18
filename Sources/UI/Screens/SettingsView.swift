//
//  SettingsView.swift
//  Gameshell
//
//  设置页：三端键位（触屏 / 键盘 / 手柄）+ 核心接入进度一览。
//  自绘覆盖层（与播放器同级），不使用任何系统弹窗。
//  三端键位改完立即写回 GSKeyMapping 并持久化到 Documents/keymap.json。
//

import SwiftUI
import Foundation

struct SettingsView: View {
    @EnvironmentObject private var state: AppState

    @State private var resetToken = 0

    #if os(iOS)
    @StateObject private var capture = GSBindingCapture()
    /// 是否打开「触屏布局编辑器」覆盖层（入口只在设置页，游玩界面不提供）
    @State private var showsLayoutEditor = false
    /// 布局编辑器正在编辑哪个系统（各系统各存一套布局）
    @State private var layoutEditorSystem = "gba"
    #endif

    var body: some View {
        VStack(spacing: 0) {
            SettingsHeaderBar(subtitle: headerSubtitle) { state.closeSettings() }

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    #if os(iOS)
                    TouchSettingsCard(mapping: state.keyMapping) { system in
                        layoutEditorSystem = system
                        showsLayoutEditor = true
                    }
                    KeyboardSettingsCard(mapping: state.keyMapping, capture: capture)
                    GamepadSettingsCard(mapping: state.keyMapping, capture: capture)
                    NDSSettingsCard()
                    CoreIntegrationCard()
                    resetCard
                    #else
                    macNotice
                    #endif
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.md)
                .id(resetToken)
            }
        }
        .background(Theme.Color.background)
        .overlay { captureLayer }
        .overlay { layoutEditorLayer }
        .transition(.opacity)
    }

    /// 触屏布局编辑器覆盖层（仅 iOS，只有设置页能打开）
    @ViewBuilder
    private var layoutEditorLayer: some View {
        #if os(iOS)
        if showsLayoutEditor {
            TouchLayoutEditor(mapping: state.keyMapping,
                              systemIdentifier: layoutEditorSystem) { showsLayoutEditor = false }
        }
        #endif
    }

    private var headerSubtitle: String {
        #if os(iOS)
        return "触屏 / 键盘 / 手柄三端键位"
        #else
        return "macOS 版为纯 URL 模式"
        #endif
    }

    // MARK: - 绑定捕获层

    @ViewBuilder
    private var captureLayer: some View {
        #if os(iOS)
        ZStack(alignment: .bottom) {
            if capture.isBinding {
                bindingBanner
            }
            // 常驻的 0 尺寸键盘捕获视图：只在需要绑键时才成为 first responder
            KeyboardCaptureView(isActive: capture.awaitingKeyboard) { usage, pressed in
                capture.handleKeyboard(usage, pressed: pressed)
            }
            .frame(width: 0, height: 0)
        }
        #endif
    }

    #if os(iOS)
    /// 全部恢复默认（触屏布局 + 键盘 / 手柄键位）
    private var resetCard: some View {
        SettingsCard(title: "恢复默认",
                     subtitle: "把触屏布局与键盘 / 手柄键位全部还原成内置默认值") {
            HStack {
                Spacer(minLength: 0)
                PillButton(title: "全部恢复默认", style: .secondary) {
                    state.keyMapping.resetToDefaults()
                    resetToken += 1
                }
                .frame(width: 150)
            }
        }
    }

    private var bindingBanner: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: capture.mode == .keyboard ? "keyboard" : "gamecontroller")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.Color.accent)

            Text(bindingPrompt)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.textPrimary)
                .lineLimit(1)

            Spacer(minLength: 0)

            PillButton(title: "取消", style: .secondary) { capture.cancel() }
                .frame(width: 72)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs)
        .background(Theme.Color.surface.opacity(0.96))
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.Color.border).frame(height: 1)
        }
    }

    private var bindingPrompt: String {
        let name = capture.pending.map { GSKeyMapping.displayName(for: $0) } ?? "该键"
        return capture.mode == .keyboard
            ? "为「\(name)」绑定键盘键：按下任意键（Esc 取消）"
            : "为「\(name)」绑定手柄键：按手柄上的任意键（点「取消」放弃）"
    }
    #else
    private var macNotice: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "laptopcomputer")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.Color.accent)
                Text("macOS 版没有模拟器")
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Color.textPrimary)
            }
            Text("模拟器核心（mGBA / Nestopia / Mesen-S）只在 iOS 目标里交叉编译，macOS 版保持纯 URL 模式，因此没有键位需要配置。")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.Color.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .stroke(Theme.Color.border, lineWidth: 1)
                )
        )
    }
    #endif
}

// MARK: - 顶栏

/// 设置页顶栏：返回 + 标题 + 副标题（iOS / macOS 共用）
private struct SettingsHeaderBar: View {
    let subtitle: String
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                    Text("返回")
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
                Text("设置")
                    .font(Theme.Font.cardTitle)
                    .foregroundStyle(Theme.Color.textPrimary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Color.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs)
        .background(Theme.Color.headerGradient)
    }
}

#if os(iOS)

// MARK: - 绑键捕获

/// 设置页的「等待按下某个键」状态机。
/// 键盘：KeyboardCaptureView 把物理按键给过来；手柄：GSInputManager 转发按钮标识。
/// Esc（HID 41）在键盘模式下等于取消。
final class GSBindingCapture: ObservableObject {

    enum Mode { case keyboard, gamepad }

    /// 是否正在等一个键盘按键（KeyboardCaptureView 据此决定是否成为 first responder）
    @Published var awaitingKeyboard = false
    /// 等待绑定的按钮；nil = 没在绑
    @Published private(set) var pending: GSButton?
    /// 每次绑定 / 清除后自增，设置页据此刷新显示的键名
    @Published private(set) var revision = 0

    private(set) var mode: Mode = .keyboard
    private var forwardingGamepad = false
    /// 正在给哪个系统绑（键盘 / 手柄都按系统分别保存，绑的时候要知道写进哪个桶）
    private var boundSystem = "gba"

    private let mapping = GSKeyMapping.shared()
    private var escapeUsage: Int { Int(UIKeyboardHIDUsage.keyboardEscape.rawValue) }

    var isBinding: Bool { pending != nil }

    func startKeyboardBind(_ button: GSButton, system: String) {
        stopGamepadForwarding()
        mode = .keyboard
        pending = button
        boundSystem = system
        awaitingKeyboard = true
        revision += 1
    }

    func startGamepadBind(_ button: GSButton, system: String) {
        mode = .gamepad
        pending = button
        boundSystem = system
        awaitingKeyboard = false

        guard !forwardingGamepad else { return }
        forwardingGamepad = true
        GSInputManager.shared().beginButtonForwarding { [weak self] identifier, pressed in
            guard pressed else { return }
            DispatchQueue.main.async { self?.bindGamepad(identifier) }
        }
        revision += 1
    }

    func handleKeyboard(_ usage: UIKeyboardHIDUsage, pressed: Bool) {
        guard awaitingKeyboard, pressed, let pending else { return }
        if Int(usage.rawValue) == escapeUsage {
            cancel()
            return
        }
        mapping.setKeyboardUsage(Int(usage.rawValue), for: pending, system: boundSystem)
        mapping.persist()
        self.awaitingKeyboard = false
        self.pending = nil
        revision += 1
    }

    func bindGamepad(_ identifier: String) {
        guard mode == .gamepad, let pending else { return }
        mapping.setGamepadIdentifier(identifier, for: pending, system: boundSystem)
        mapping.persist()
        self.pending = nil
        stopGamepadForwarding()
        revision += 1
    }

    func clearKeyboard(_ button: GSButton, system: String) {
        mapping.clearKeyboardBinding(for: button, system: system)
        mapping.persist()
        revision += 1
    }

    func clearGamepad(_ button: GSButton, system: String) {
        mapping.clearGamepadBinding(for: button, system: system)
        mapping.persist()
        revision += 1
    }

    func cancel() {
        pending = nil
        awaitingKeyboard = false
        stopGamepadForwarding()
        revision += 1
    }

    func refresh() { revision += 1 }

    private func stopGamepadForwarding() {
        if forwardingGamepad {
            GSInputManager.shared().endButtonForwarding()
            forwardingGamepad = false
        }
    }
}

// MARK: - 卡片外壳

private struct SettingsCard<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Font.cardTitle)
                    .foregroundStyle(Theme.Color.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Color.textSecondary)
                }
            }
            content()
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GSCardBackground())
    }
}

// MARK: - 触屏

/// 设置页默认编辑哪个系统：优先 GBA（最经典的布局），否则取第一个已接入的系统
private func defaultSettingsSystemIdentifier() -> String {
    let systems = GSSystemRegistry.integratedSystems()
    if let gba = systems.first(where: { $0.identifier == "gba" }) {
        return gba.identifier
    }
    return systems.first?.identifier ?? "gba"
}

/// 系统选择器：横排小胶囊，点一下切换正在编辑的系统（触屏 / 键盘 / 手柄三张卡共用）
private struct SystemPickerBar: View {
    let systems: [GSSystemInfo]
    @Binding var selection: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("正在编辑的系统")
                .font(Theme.Font.chip)
                .foregroundStyle(Theme.Color.textSecondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.xs) {
                    ForEach(systems, id: \.identifier) { info in
                        Button {
                            selection = info.identifier
                        } label: {
                            Text(info.shortName)
                                .font(Theme.Font.chip)
                                .foregroundStyle(selection == info.identifier
                                                 ? Theme.Color.background
                                                 : Theme.Color.textPrimary)
                                .padding(.horizontal, Theme.Spacing.sm)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous)
                                        .fill(selection == info.identifier
                                              ? Theme.Color.accent
                                              : Theme.Color.surface)
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
    }
}

private struct TouchSettingsCard: View {
    let mapping: GSKeyMapping
    /// 打开布局编辑器（拖拽移动 / 调整大小）；参数是要编辑的系统标识
    let onEditLayout: (String) -> Void

    @State private var scale: CGFloat
    @State private var opacity: CGFloat
    /// 当前在编辑哪个系统：各系统的按键簇集合、默认布局与显示开关都分开
    @State private var systemIdentifier: String

    init(mapping: GSKeyMapping, onEditLayout: @escaping (String) -> Void) {
        self.mapping = mapping
        self.onEditLayout = onEditLayout
        _scale = State(initialValue: mapping.touchScale)
        _opacity = State(initialValue: mapping.touchOpacity)
        _systemIdentifier = State(initialValue: defaultSettingsSystemIdentifier())
    }

    private var systems: [GSSystemInfo] {
        GSSystemRegistry.integratedSystems()
    }

    /// 当前系统有哪些按键元素
    private var elements: [GSTouchElement] {
        GSKeyMapping.touchElements(forSystem: systemIdentifier)
            .compactMap { GSTouchElement(rawValue: $0.intValue) }
    }

    var body: some View {
        SettingsCard(title: "触屏手柄",
                     subtitle: "缩放、透明度是全局的；每个按键是否显示、位置与大小按系统分别保存（按键之间互不绑定）") {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                SystemPickerBar(systems: systems, selection: $systemIdentifier)

                slider(title: "缩放",
                       value: $scale,
                       range: 0.6...1.4,
                       readout: String(format: "%.2f×", scale)) { value in
                    mapping.touchScale = value
                }

                slider(title: "透明度",
                       value: $opacity,
                       range: 0.3...1.0,
                       readout: String(format: "%.0f%%", opacity * 100)) { value in
                    mapping.touchOpacity = value
                }

                ForEach(elements, id: \.rawValue) { element in
                    toggle(title: "显示 \(GSKeyMapping.displayName(forElement: element))",
                           isOn: visibleBinding(element))
                }

                // 每个按键的位置与大小（拖拽移动、双指或滑杆缩放）只在设置页的布局编辑器里调
                PillButton(title: "编辑布局（拖动位置 / 调整大小）", style: .secondary) {
                    onEditLayout(systemIdentifier)
                }
                .padding(.top, Theme.Spacing.xxs)
            }
        }
    }

    /// 某按键的显示开关绑定：直接读写 GSKeyMapping（按系统），改完立即落盘
    private func visibleBinding(_ element: GSTouchElement) -> Binding<Bool> {
        Binding(
            get: { mapping.isElementVisible(element, forSystem: systemIdentifier) },
            set: { newValue in
                mapping.setVisible(newValue, forElement: element, system: systemIdentifier)
                mapping.persist()
            }
        )
    }

    private func slider(title: String,
                        value: Binding<CGFloat>,
                        range: ClosedRange<CGFloat>,
                        readout: String,
                        apply: @escaping (CGFloat) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(Theme.Font.chip)
                    .foregroundStyle(Theme.Color.textSecondary)
                Spacer(minLength: 0)
                Text(readout)
                    .font(Theme.Font.chip)
                    .foregroundStyle(Theme.Color.textPrimary)
            }
            Slider(value: value, in: range)
                .tint(Theme.Color.accent)
                .onChange(of: value.wrappedValue) { newValue in
                    apply(newValue)
                    mapping.persist()
                }
        }
    }

    private func toggle(title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Color.textPrimary)
        }
        .tint(Theme.Color.accent)
    }
}

// MARK: - 键盘 / 手柄 共用行

private struct BindingRow: View {
    let raw: UInt32
    let label: String?
    let isCapturing: Bool
    let onBind: () -> Void
    let onClear: () -> Void
    let onCancel: () -> Void

    private var title: String {
        GSKeyMapping.displayName(for: GSButton(rawValue: raw))
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text(title)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Color.textPrimary)
                .frame(width: 92, alignment: .leading)

            if isCapturing {
                Text("等待按键…")
                    .font(Theme.Font.chip)
                    .foregroundStyle(Theme.Color.accent)
                Spacer(minLength: 0)
                PillButton(title: "取消", style: .secondary, action: onCancel)
                    .frame(width: 72)
            } else {
                Text(label ?? "未绑定")
                    .font(Theme.Font.chip)
                    .foregroundStyle(label == nil ? Theme.Color.textTertiary : Theme.Color.textSecondary)
                Spacer(minLength: 0)
                PillButton(title: label == nil ? "绑定" : "重绑", style: .secondary, action: onBind)
                    .frame(width: 72)
                if label != nil {
                    PillButton(title: "清除", style: .secondary, action: onClear)
                        .frame(width: 72)
                }
            }
        }
        .padding(.vertical, 1)
    }
}

private struct KeyboardSettingsCard: View {
    let mapping: GSKeyMapping
    @ObservedObject var capture: GSBindingCapture
    /// 键盘绑定按系统分开存：先选系统，再给该系统绑键
    @State private var systemIdentifier: String

    init(mapping: GSKeyMapping, capture: GSBindingCapture) {
        self.mapping = mapping
        self.capture = capture
        _systemIdentifier = State(initialValue: defaultSettingsSystemIdentifier())
    }

    private var systems: [GSSystemInfo] {
        GSSystemRegistry.integratedSystems()
    }

    private var buttons: [UInt32] {
        GSKeyMapping.configurableButtons().map { $0.uint32Value }
    }

    var body: some View {
        SettingsCard(title: "键盘",
                     subtitle: "键盘绑定按系统分开；先选系统，再点「绑定」按键盘上的键，Esc 取消") {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                SystemPickerBar(systems: systems, selection: $systemIdentifier)

                VStack(alignment: .leading, spacing: 2) {
                    ForEach(buttons, id: \.self) { raw in
                        BindingRow(raw: raw,
                                   label: mapping.keyboardBindingLabel(for: GSButton(rawValue: raw),
                                                                       system: systemIdentifier),
                                   isCapturing: capture.isBinding
                                       && capture.mode == .keyboard
                                       && capture.pending == GSButton(rawValue: raw),
                                   onBind: { capture.startKeyboardBind(GSButton(rawValue: raw),
                                                                       system: systemIdentifier) },
                                   onClear: { capture.clearKeyboard(GSButton(rawValue: raw),
                                                                    system: systemIdentifier) },
                                   onCancel: { capture.cancel() })
                    }
                }
            }
        }
    }
}

private struct GamepadSettingsCard: View {
    let mapping: GSKeyMapping
    @ObservedObject var capture: GSBindingCapture
    /// 手柄绑定按系统分开存：先选系统，再给该系统绑键
    @State private var systemIdentifier: String

    init(mapping: GSKeyMapping, capture: GSBindingCapture) {
        self.mapping = mapping
        self.capture = capture
        _systemIdentifier = State(initialValue: defaultSettingsSystemIdentifier())
    }

    private var systems: [GSSystemInfo] {
        GSSystemRegistry.integratedSystems()
    }

    private var buttons: [UInt32] {
        GSKeyMapping.configurableButtons().map { $0.uint32Value }
    }

    var body: some View {
        SettingsCard(title: "手柄",
                     subtitle: "手柄绑定按系统分开；先选系统，再点「绑定」按手柄上的键（需要先连上手柄）") {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                SystemPickerBar(systems: systems, selection: $systemIdentifier)

                VStack(alignment: .leading, spacing: 2) {
                    ForEach(buttons, id: \.self) { raw in
                        BindingRow(raw: raw,
                                   label: mapping.gamepadBindingLabel(for: GSButton(rawValue: raw),
                                                                      system: systemIdentifier),
                                   isCapturing: capture.isBinding
                                       && capture.mode == .gamepad
                                       && capture.pending == GSButton(rawValue: raw),
                                   onBind: { capture.startGamepadBind(GSButton(rawValue: raw),
                                                                      system: systemIdentifier) },
                                   onClear: { capture.clearGamepad(GSButton(rawValue: raw),
                                                                   system: systemIdentifier) },
                                   onCancel: { capture.cancel() })
                    }
                }
            }
        }
    }
}

// MARK: - NDS（BIOS / 固件 / 双屏布局）

/// NDS 的 BIOS / 固件导入与运行选项。
/// BIOS 与固件是任天堂版权文件，本 App 不内置任何一份，也不随包分发；
/// 必须由用户用「文件」App 选自己的 bios7.bin / bios9.bin / firmware.bin 导入，
/// 导入的统一落在沙盒 Documents/Bios/ —— 核心就是去这个目录按文件名取（见 GSNDSSupport）。
private struct NDSSettingsCard: View {

    @EnvironmentObject private var state: AppState

    private let support = GSNDSSupport.shared()

    /// 每次导入 / 删除后自增，用来强制刷新「已导入 / 未导入」状态
    @State private var revision = 0
    /// 正在等用户选哪个 BIOS 文件（nil = 没在选）
    @State private var pickingName: String?
    /// 上一次导入失败的提示（没有就为 nil）
    @State private var errorText: String?
    @State private var screenLayout: GSNDSScreenLayout

    /// 三个固定文件：名字必须严格叫这三个，核心才认
    private static let rows: [(name: String, title: String, note: String)] = [
        (GSBiosFileName7, "bios7.bin", "ARM7 BIOS"),
        (GSBiosFileName9, "bios9.bin", "ARM9 BIOS"),
        (GSBiosFileNameFirmware, "firmware.bin", "NDS 固件"),
    ]

    init() {
        let support = GSNDSSupport.shared()
        _screenLayout = State(initialValue: support.screenLayout)
    }

    var body: some View {
        SettingsCard(title: "NDS（BIOS / 固件）",
                     subtitle: "BIOS 与固件是任天堂版权文件，本 App 不内置：用「文件」App 选自己的 bios7.bin / bios9.bin / firmware.bin 导入") {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {

                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Self.rows, id: \.name) { row in
                        fileRow(row)
                    }
                }
                .id(revision)

                Rectangle()
                    .fill(Theme.Color.border)
                    .frame(height: 1)

                pickerBlock(title: "双屏布局",
                            selection: layoutBinding,
                            options: [(GSNDSScreenLayout.topBottom, "上下"),
                                      (GSNDSScreenLayout.leftRight, "左右"),
                                      (GSNDSScreenLayout.topOnly, "只上屏"),
                                      (GSNDSScreenLayout.bottomOnly, "只下屏")])

                if let errorText {
                    Text(errorText)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        // 「浏览器」在 iOS 上只有 UIDocumentPicker 一条路，所以复用 ROM 导入那套桥接。
        .background(
            DocumentPickerBridge(isPresented: pickerPresented) { url in
                importPicked(url)
            }
            .frame(width: 0, height: 0)
        )
    }

    // MARK: 行 / 块

    /// 一个 BIOS 文件行：状态图标 + 文件名 + 说明 + 导入 / 删除
    private func fileRow(_ row: (name: String, title: String, note: String)) -> some View {
        let imported = support.hasBIOSFile(named: row.name)
        return HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: imported ? "checkmark.circle.fill" : "circle.dashed")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(imported ? Theme.Color.accent : Theme.Color.textTertiary)

            VStack(alignment: .leading, spacing: 1) {
                Text(row.title)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Color.textPrimary)
                Text(imported ? row.note : "未导入")
                    .font(Theme.Font.caption)
                    .foregroundStyle(imported ? Theme.Color.textSecondary : Theme.Color.textTertiary)
            }

            Spacer(minLength: 0)

            PillButton(title: imported ? "重新导入" : "导入", style: .secondary) {
                errorText = nil
                pickingName = row.name
            }
            .frame(width: 84)

            if imported {
                PillButton(title: "删除", style: .secondary) {
                    support.removeBIOSFile(named: row.name)
                    revision += 1
                }
                .frame(width: 64)
            }
        }
        .padding(.vertical, 1)
    }

    /// 一个小标题 + 分段选择器
    private func pickerBlock<T: Hashable>(title: String,
                                          selection: Binding<T>,
                                          options: [(T, String)]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Theme.Font.chip)
                .foregroundStyle(Theme.Color.textSecondary)
            Picker(title, selection: selection) {
                ForEach(options, id: \.0) { option in
                    Text(option.1).tag(option.0)
                }
            }
            .pickerStyle(.segmented)
            .tint(Theme.Color.accent)
        }
    }

    // MARK: 绑定

    private var layoutBinding: Binding<GSNDSScreenLayout> {
        Binding(get: { screenLayout },
                set: { newValue in
                    screenLayout = newValue
                    support.screenLayout = newValue
                })
    }

    /// 文件选择器是否在呈现中（由 pickingName 派生）
    private var pickerPresented: Binding<Bool> {
        Binding(get: { pickingName != nil },
                set: { presented in
                    if !presented { pickingName = nil }
                })
    }

    private func importPicked(_ url: URL) {
        guard let name = pickingName else { return }
        do {
            try support.importBIOSFile(at: url, as: name)
            errorText = nil
            GSLog.tag("nds", message: "已导入 \(name)")
        } catch {
            errorText = "导入 \(name) 失败：\(error.localizedDescription)"
            GSLog.tag("nds", message: "导入 BIOS 失败：\(error.localizedDescription)")
        }
        revision += 1
    }
}

// MARK: - 核心接入进度

private struct CoreIntegrationCard: View {
    var body: some View {
        SettingsCard(title: "核心接入进度", subtitle: "未接入的系统如实标注，不假装能玩") {
            CoreStatusList()
        }
    }
}

#endif
