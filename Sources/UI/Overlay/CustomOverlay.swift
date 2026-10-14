import SwiftUI

/// 浮层请求模型。
/// 本 App 完全禁用系统弹窗（UIAlertController / NSAlert / NSPanel），
/// 所有「提示 / 确认」都由这里的自绘浮层承担。
struct OverlayRequest: Identifiable {
    enum Kind {
        case toast
        case confirm
    }

    let id = UUID()
    let kind: Kind
    let title: String
    var message: String? = nil
    var confirmTitle: String = "确定"
    var cancelTitle: String = "取消"
    var onConfirm: (() -> Void)? = nil
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
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

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
