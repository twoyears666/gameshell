import SwiftUI

/// 通用游戏卡片。
/// 全部视觉令牌取自 Theme，尺寸由外部约束决定，可复用于首页 hero / 网格 / 横屏手持布局。
struct GameCard: View {
    let game: GSGame
    var showsDescription: Bool = true
    var onTap: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    GameCover(game: game)

                    // 底部渐隐 + 标题
                    VStack(alignment: .leading, spacing: 2) {
                        Text(game.name)
                            .font(Theme.Font.cardTitle)
                            .foregroundStyle(Theme.Color.textPrimary)
                            .lineLimit(1)
                        if game.controllerSupport {
                            Text("支持手柄")
                                .font(Theme.Font.chip)
                                .foregroundStyle(Theme.Color.accent)
                        }
                    }
                    .padding(Theme.Spacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.Color.coverScrim)

                    // 评分徽章
                    VStack {
                        HStack {
                            Spacer()
                            RatingChip(rating: game.rating)
                        }
                        Spacer()
                    }
                    .padding(Theme.Spacing.xs)
                }
                .frame(height: 148)

                if showsDescription {
                    Text(game.summary)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Color.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Theme.Spacing.sm)
                        .padding(.vertical, Theme.Spacing.sm)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Theme.Color.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                            .stroke(Theme.Color.border, lineWidth: 1)
                    )
            )
            .scaleEffect(isHovering ? 1.015 : 1)
            .animation(Theme.Motion.quick, value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering in isHovering = hovering }
    }
}

/// 榜单行：名次 + 图标 + 名称 + 副标题 + 评分
struct GameRow: View {
    let rank: Int
    let game: GSGame
    var onTap: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Theme.Spacing.sm) {
                Text("\(rank)")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(rank <= 3 ? Theme.Color.accent : Theme.Color.textTertiary)
                    .frame(width: 28, alignment: .center)

                GameCover(game: game, symbolScale: 0.5)
                    .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 3) {
                    Text(game.name)
                        .font(Theme.Font.cardTitle)
                        .foregroundStyle(Theme.Color.textPrimary)
                        .lineLimit(1)
                    Text(game.summary)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Color.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: Theme.Spacing.xs)

                RatingChip(rating: game.rating, compact: true)
            }
            .padding(Theme.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .fill(isHovering ? Theme.Color.surfaceAlt : Theme.Color.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                            .stroke(Theme.Color.border, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in isHovering = hovering }
    }
}

/// 表单式条目卡片（设置页用）：左图标 + 标题 + 右侧 chevron
struct SettingRow: View {
    let systemImage: String
    let title: String
    var detail: String? = nil
    var onTap: (() -> Void)? = nil

    @State private var isHovering = false

    var body: some View {
        Button {
            onTap?()
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.Color.accent)
                    .frame(width: 24)

                Text(title)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Color.textPrimary)

                Spacer()

                if let detail {
                    Text(detail)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Color.textSecondary)
                        .lineLimit(1)
                }

                if onTap != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.Color.textTertiary)
                }
            }
            .padding(Theme.Spacing.sm)
            .frame(minHeight: 48)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .fill(isHovering && onTap != nil ? Theme.Color.surfaceAlt : Theme.Color.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                            .stroke(Theme.Color.border, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(onTap == nil)
        .onHover { hovering in isHovering = hovering }
    }
}
