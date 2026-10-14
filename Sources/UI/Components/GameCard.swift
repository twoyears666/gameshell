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
        .onHoverIfSupported { hovering in isHovering = hovering }
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
        .onHoverIfSupported { hovering in isHovering = hovering }
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
        .onHoverIfSupported { hovering in isHovering = hovering }
    }
}

/// `onHover` 在 iOS 上要 16.4+（只有 iPadOS 接指针时才有意义），低版本直接跳过。
extension View {
    @ViewBuilder
    func onHoverIfSupported(_ action: @escaping (Bool) -> Void) -> some View {
        if #available(iOS 16.4, macOS 10.15, *) {
            self.onHover(perform: action)
        } else {
            self
        }
    }
}

/// 首页第一排的方块卡片（PS5 风格）：正方形封面 + 底部名称，
/// 获得聚焦（指针悬停 / 默认第一项）的卡片放大、高亮描边，其余变暗缩小。
struct SquareTileCard: View {
    let game: GSGame
    let side: CGFloat
    let isFocused: Bool
    var onHover: (Bool) -> Void
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                GameCover(game: game, symbolScale: 0.3, cornerRadius: Theme.Radius.hero)

                LinearGradient(
                    colors: [.clear, SwiftUI.Color.black.opacity(0.82)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(game.name)
                            .font(Theme.Font.body)
                            .foregroundStyle(Theme.Color.textPrimary)
                            .lineLimit(1)
                        if game.controllerSupport {
                            Image(systemName: "gamecontroller.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.Color.accent)
                        }
                    }
                    Text(game.platform)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Color.textSecondary)
                        .lineLimit(1)
                }
                .padding(Theme.Spacing.sm)
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous)
                    .stroke(isFocused ? SwiftUI.Color.white.opacity(0.9) : Theme.Color.border,
                            lineWidth: isFocused ? 2 : 1)
            )
            .scaleEffect(isFocused ? 1 : 0.93)
            .opacity(isFocused ? 1 : 0.72)
            .shadow(color: .black.opacity(isFocused ? 0.45 : 0.2),
                    radius: isFocused ? 12 : 4,
                    y: isFocused ? 8 : 2)
            .animation(Theme.Motion.standard, value: isFocused)
        }
        .buttonStyle(.plain)
        .onHoverIfSupported { onHover($0) }
    }
}
