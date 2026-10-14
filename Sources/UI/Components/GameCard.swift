import SwiftUI

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

/// 主界面第一排的方块卡片（PS5 风格）：正方形封面 + 底部名称。
/// 获得聚焦（指针悬停 / 默认第一项）的卡片放大、高亮描边，其余变暗缩小。
/// 点按 = 打开这个 URL；长按 = 自绘确认后删除。
struct SquareTileCard: View {
    let game: GSGame
    let side: CGFloat
    let isFocused: Bool
    var onHover: (Bool) -> Void
    var onTap: () -> Void
    var onLongPress: () -> Void

    var body: some View {
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
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .onLongPressGesture(minimumDuration: 0.5) { onLongPress() }
        .onHoverIfSupported { onHover($0) }
    }
}
