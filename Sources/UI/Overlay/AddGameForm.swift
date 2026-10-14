import SwiftUI

/// App 内添加 URL 的自绘表单（不使用任何系统弹窗）。
/// 只有名称 + URL 两个输入项；校验与结果提示都由 AppState 走自绘 toast。
struct AddGameForm: View {
    @Binding var name: String
    @Binding var urlString: String
    var onCancel: () -> Void
    var onSave: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { onCancel() }

            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text("添加游戏")
                    .font(Theme.Font.section)
                    .foregroundStyle(Theme.Color.textPrimary)

                field(title: "名称", placeholder: "例如：我的网页游戏", text: $name)
                field(title: "URL", placeholder: "https://example.com 或 steam://run/123", text: $urlString)

                Text("http(s) 用内置浏览器打开；其它 scheme（如 steam://）交给系统唤起对应 App。")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: Theme.Spacing.sm) {
                    PillButton(title: "取消", style: .secondary) { onCancel() }
                    PillButton(title: "保存", style: .primary) { onSave() }
                }
                .padding(.top, Theme.Spacing.xxs)
            }
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: 420)
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
        .transition(.opacity)
    }

    private func field(title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Text(title)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.textSecondary)

            TextField("", text: text,
                      prompt: Text(placeholder).foregroundColor(Theme.Color.textTertiary))
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Color.textPrimary)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, Theme.Spacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .fill(Theme.Color.surfaceAlt)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                                .stroke(Theme.Color.border, lineWidth: 1)
                        )
                )
        }
    }
}
