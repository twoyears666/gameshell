import SwiftUI

/// 顶部栏：标题 + 副标题 + 右侧外设状态胶囊 + 可选右侧控件。
struct TopBar: View {
    let title: String
    var subtitle: String? = nil
    var inputSummary: String
    var trailing: AnyView? = nil

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Theme.Font.title)
                    .foregroundStyle(Theme.Color.textPrimary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Color.textSecondary)
                }
            }

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: "gamecontroller")
                    .font(.system(size: 11, weight: .semibold))
                Text(inputSummary)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(Theme.Color.textSecondary)
            .padding(.horizontal, Theme.Spacing.xs)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous)
                    .fill(Theme.Color.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous)
                            .stroke(Theme.Color.border, lineWidth: 1)
                    )
            )

            trailing
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.top, Theme.Spacing.xs)
        .padding(.bottom, Theme.Spacing.sm)
        .background(Theme.Color.headerGradient)
    }
}
