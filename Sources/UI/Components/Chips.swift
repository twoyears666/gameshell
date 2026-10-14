import SwiftUI
import Foundation

/// 评分徽章：圆角半透明底 + 星标 + 分数。
struct RatingChip: View {
    let rating: Double
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "star.fill")
                .font(.system(size: compact ? 10 : 11, weight: .bold))
                .foregroundStyle(Theme.Color.accent)
            Text(String(format: "%.1f", rating))
                .font(compact ? Theme.Font.chip : Theme.Font.rating)
                .foregroundStyle(Theme.Color.textPrimary)
        }
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, compact ? 3 : 4)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                .fill(Theme.Color.ratingBackground)
        )
    }
}

/// 通用小标签（平台 / 分类）
struct TagChip: View {
    let text: String
    var highlighted: Bool = false

    var body: some View {
        Text(text)
            .font(Theme.Font.chip)
            .foregroundStyle(highlighted ? SwiftUI.Color.black.opacity(0.85) : Theme.Color.textSecondary)
            .padding(.horizontal, Theme.Spacing.xs)
            .padding(.vertical, Theme.Spacing.xxs)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                    .fill(highlighted ? Theme.Color.accent : Theme.Color.surfaceAlt)
            )
    }
}

/// 分区标题：「标题 + 可选右侧更多」
struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Font.section)
                    .foregroundStyle(Theme.Color.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Color.textSecondary)
                }
            }
            Spacer()
            if let actionTitle {
                Button(action: { action?() }) {
                    HStack(spacing: 2) {
                        Text(actionTitle)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
