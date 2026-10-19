import SwiftUI

/// 浮层请求模型。
/// 本 App 完全禁用系统弹窗（UIAlertController / NSAlert / NSPanel），
/// 所有「提示 / 确认 / 菜单 / 输入」都由这里的自绘浮层承担。
struct OverlayRequest: Identifiable {
    enum Kind {
        case toast
        case confirm
        case menu
        case prompt
        /// 只读信息卡：标题 + 多行文本 + 一个「好」按钮（游戏信息 / JIT 档位）
        case info
    }

    let id = UUID()
    let kind: Kind
    let title: String
    var message: String? = nil
    var confirmTitle: String = "确定"
    var cancelTitle: String = "取消"
    var onConfirm: (() -> Void)? = nil

    // MARK: 菜单（长按卡片呼出的分组菜单）
    /// 菜单副标题（一般放系统 / 平台）
    var detail: String? = nil
    var sections: [OverlayMenuSection] = []

    // MARK: 输入框（重命名等）
    var placeholder: String = ""
    var initialText: String = ""
    var onSubmit: ((String) -> Void)? = nil
}

/// 菜单里的一项：图标 + 标题 + 可选右侧说明。
struct OverlayMenuItem: Identifiable {
    let id = UUID()
    var title: String
    var systemImage: String? = nil
    /// 右侧灰色说明（例如「2.4 MB」），也用于把只读信息直接展示在菜单里
    var detail: String? = nil
    var isDestructive: Bool = false
    let action: () -> Void
}

/// 菜单里的一组（有可选组标题）。
struct OverlayMenuSection: Identifiable {
    let id = UUID()
    var title: String? = nil
    var items: [OverlayMenuItem]
}

/// 自绘浮层容器：盖在整棵视图树之上。
struct CustomOverlayLayer: View {
    let request: OverlayRequest
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            switch request.kind {
            case .toast:
                toast
            case .confirm:
                confirmCard
            case .menu:
                menuCard
            case .prompt:
                PromptCard(request: request, onDismiss: onDismiss)
                    .id(request.id)
            case .info:
                infoCard
            }
        }
        .transition(.opacity)
        .zIndex(999)
    }

    // MARK: - Toast

    private var toast: some View {
        VStack {
            Spacer()
            Text(request.title)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Color.textPrimary)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .fill(Theme.Color.surfaceAlt)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                                .stroke(Theme.Color.border, lineWidth: 1)
                        )
                )
                .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
            Spacer().frame(height: Theme.Spacing.xl * 2)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .allowsHitTesting(false)
    }

    // MARK: - Confirm

    private var confirmCard: some View {
        ZStack {
            scrim

            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text(request.title)
                    .font(Theme.Font.section)
                    .foregroundStyle(Theme.Color.textPrimary)

                if let message = request.message, !message.isEmpty {
                    Text(message)
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: Theme.Spacing.sm) {
                    PillButton(title: request.cancelTitle, style: .secondary) {
                        onDismiss()
                    }
                    PillButton(title: request.confirmTitle, style: .primary) {
                        request.onConfirm?()
                        onDismiss()
                    }
                }
                .padding(.top, Theme.Spacing.xxs)
            }
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: 380)
            .background(dialogBackground)
            .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
            .padding(Theme.Spacing.lg)
        }
    }

    // MARK: - Info（只读信息卡）

    private var infoCard: some View {
        ZStack {
            scrim

            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text(request.title)
                    .font(Theme.Font.section)
                    .foregroundStyle(Theme.Color.textPrimary)

                if let message = request.message, !message.isEmpty {
                    Text(message)
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                PillButton(title: request.confirmTitle, style: .primary) { onDismiss() }
                    .padding(.top, Theme.Spacing.xxs)
            }
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: 400)
            .background(dialogBackground)
            .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
            .padding(Theme.Spacing.lg)
        }
    }

    // MARK: - Menu

    private var menuCard: some View {
        ZStack {
            scrim

            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(request.title)
                        .font(Theme.Font.title)
                        .foregroundStyle(Theme.Color.textPrimary)
                        .lineLimit(1)
                    if let detail = request.detail, !detail.isEmpty {
                        Text(detail)
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Color.textSecondary)
                            .lineLimit(1)
                    }
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        ForEach(request.sections) { section in
                            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                if let title = section.title {
                                    Text(title)
                                        .font(Theme.Font.chip)
                                        .foregroundStyle(Theme.Color.textTertiary)
                                        .padding(.leading, Theme.Spacing.xxs)
                                }
                                VStack(spacing: 0) {
                                    ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                                        MenuRow(item: item) {
                                            onDismiss()
                                            item.action()
                                        }
                                        if index < section.items.count - 1 {
                                            Divider()
                                                .overlay(Theme.Color.border)
                                                .padding(.leading, item.systemImage == nil ? Theme.Spacing.sm : 38)
                                        }
                                    }
                                }
                                .background(
                                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                                        .fill(Theme.Color.surfaceAlt)
                                )
                            }
                        }
                    }
                    .padding(.bottom, Theme.Spacing.xxs)
                }
                .frame(maxHeight: 460)

                PillButton(title: "关闭", style: .secondary) { onDismiss() }
            }
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: 420)
            .background(dialogBackground)
            .shadow(color: .black.opacity(0.5), radius: 28, y: 14)
            .padding(Theme.Spacing.lg)
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        }
    }

    // MARK: - 公共

    private var scrim: some View {
        Color.black.opacity(0.55)
            .ignoresSafeArea()
            .onTapGesture { onDismiss() }
    }

    private var dialogBackground: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            .fill(Theme.Color.surface)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .stroke(Theme.Color.border, lineWidth: 1)
            )
    }
}

/// 菜单里的一行：点按后回弹一下再执行。
private struct MenuRow: View {
    let item: OverlayMenuItem
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                if let symbol = item.systemImage {
                    Image(systemName: symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(item.isDestructive ? Theme.Color.accent : Theme.Color.textSecondary)
                        .frame(width: 22)
                }
                Text(item.title)
                    .font(Theme.Font.body)
                    .foregroundStyle(item.isDestructive ? Theme.Color.accent : Theme.Color.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: Theme.Spacing.sm)
                if let detail = item.detail, !detail.isEmpty {
                    Text(detail)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Color.textTertiary)
                        .lineLimit(1)
                }
                if !item.isDestructive {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.Color.textTertiary)
                }
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .fill(Theme.Color.surfaceAlt.opacity(isPressed ? 0.4 : 0))
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.97 : 1, anchor: .center)
        .animation(Theme.Motion.quick, value: isPressed)
        .onLongPressGesture(minimumDuration: 0, pressing: { isPressed = $0 }, perform: {})
    }
}

/// 输入框浮层（重命名等）：自绘卡片 + 一个输入框 + 取消 / 确定。
private struct PromptCard: View {
    let request: OverlayRequest
    let onDismiss: () -> Void

    @State private var text: String = ""

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text(request.title)
                    .font(Theme.Font.section)
                    .foregroundStyle(Theme.Color.textPrimary)

                TextField(request.placeholder, text: $text)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Color.textPrimary)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                            .fill(Theme.Color.surfaceAlt)
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                                    .stroke(Theme.Color.border, lineWidth: 1)
                            )
                    )
                    .onSubmit { submit() }

                HStack(spacing: Theme.Spacing.sm) {
                    PillButton(title: request.cancelTitle, style: .secondary) { onDismiss() }
                    PillButton(title: request.confirmTitle, style: .primary) { submit() }
                }
                .padding(.top, Theme.Spacing.xxs)
            }
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: 380)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Theme.Color.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                            .stroke(Theme.Color.border, lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
            .padding(Theme.Spacing.lg)
        }
        .onAppear { text = request.initialText }
    }

    private func submit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        request.onSubmit?(trimmed)
        onDismiss()
    }
}

/// 通用胶囊按钮（用于自绘弹层里的操作）
struct PillButton: View {
    enum Style {
        case primary
        case secondary
    }

    let title: String
    var style: Style = .primary
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Font.button)
                .foregroundStyle(style == .primary ? SwiftUI.Color.black.opacity(0.9) : Theme.Color.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous)
                        .fill(backgroundColor)
                )
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.97 : 1)
        .animation(Theme.Motion.quick, value: isPressed)
        .onLongPressGesture(minimumDuration: 0, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }

    private var backgroundColor: SwiftUI.Color {
        switch style {
        case .primary: return Theme.Color.accent
        case .secondary: return Theme.Color.surfaceAlt
        }
    }
}
