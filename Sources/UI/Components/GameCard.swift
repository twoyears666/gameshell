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

/// 方块卡片（PS5 风格）：正方形封面 + 底部名称。
/// 同一张卡同时服务 URL 条目与 ROM：封面来源由 LibraryItem（清单 icon / 远程 URL）
/// 与 coverRelativePath（已抓到的 ROM 封面）共同决定。
/// 获得聚焦（指针悬停 / 默认第一项）的卡片放大、高亮描边，其余变暗缩小。
/// 点按 = 打开；长按 = 自绘确认后删除。
struct SquareTileCard: View {
    let item: LibraryItem
    /// ROM 封面的相对路径（由 AppState 在抓取完成后提供；URL 条目不用）
    var coverRelativePath: String? = nil
    let side: CGFloat
    let isFocused: Bool
    var onHover: (Bool) -> Void
    var onTap: () -> Void
    var onLongPress: () -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            GameCover(source: coverSource,
                      accentHex: item.accentHex,
                      fallbackText: item.badgeText,
                      symbolScale: 0.3,
                      cornerRadius: Theme.Radius.hero)

            LinearGradient(
                colors: [.clear, SwiftUI.Color.black.opacity(0.82)],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(item.title)
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.Color.textPrimary)
                        .lineLimit(1)
                    if item.supportsController {
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.Color.accent)
                    }
                }
                Text(item.subtitle)
                    .font(Theme.Font.caption)
                    .foregroundStyle(item.isPlayable ? Theme.Color.textSecondary : Theme.Color.accent)
                    .lineLimit(1)
            }
            .padding(Theme.Spacing.sm)

            if let system = item.badgeText {
                Text(system)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.Color.textPrimary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                            .fill(SwiftUI.Color.black.opacity(0.5))
                    )
                    .padding(Theme.Spacing.xs)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous)
                .stroke(isFocused ? SwiftUI.Color.white.opacity(0.9) : Theme.Color.border,
                        lineWidth: isFocused ? 2 : 1)
        )
        .opacity(item.isPlayable ? (isFocused ? 1 : 0.72) : 0.66)
        .scaleEffect(isFocused ? 1 : 0.93)
        .shadow(color: .black.opacity(isFocused ? 0.45 : 0.2),
                radius: isFocused ? 12 : 4,
                y: isFocused ? 8 : 2)
        .animation(Theme.Motion.standard, value: isFocused)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .onLongPressGesture(minimumDuration: 0.5) { onLongPress() }
        .onHoverIfSupported { onHover($0) }
    }

    /// 封面来源：URL 条目用清单里的 icon（远程 URL / 本地相对路径 / 符号名），
    /// ROM 用已经抓到的封面相对路径（还没有就是空 —— 兜底成系统徽标）。
    private var coverSource: String {
        switch item {
        case .game(let game): return game.iconURLString
        case .rom: return coverRelativePath ?? ""
        }
    }
}
