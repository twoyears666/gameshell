import SwiftUI
import Foundation

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
/// 获得聚焦（手柄 / 键盘移动，或指针悬停）的卡片放大并亮白框，其余变暗缩小、**不描边**。
/// 点按 = 打开；长按 = 回弹一下再呼出分组菜单。
struct SquareTileCard: View {
    let item: LibraryItem
    /// ROM 封面的相对路径（由 AppState 在抓取完成后提供；URL 条目不用）
    var coverRelativePath: String? = nil
    let side: CGFloat
    let isFocused: Bool
    var onHover: (Bool) -> Void
    var onTap: () -> Void
    var onLongPress: () -> Void

    /// 长按命中的瞬时回弹
    @State private var pulse = false

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
        // 白框只出现在选中的那一张上，其余卡片一律不描边
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous)
                .stroke(SwiftUI.Color.white.opacity(0.92), lineWidth: 2.5)
                .opacity(isFocused ? 1 : 0)
        )
        .opacity(item.isPlayable ? (isFocused ? 1 : 0.58) : 0.48)
        .scaleEffect((isFocused ? 1.06 : 0.9) * (pulse ? 0.94 : 1))
        .shadow(color: .black.opacity(isFocused ? 0.55 : 0.16),
                radius: isFocused ? 18 : 4,
                y: isFocused ? 12 : 2)
        .animation(Theme.Motion.pop, value: isFocused)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .onLongPressGesture(minimumDuration: 0.5) {
            withAnimation(Theme.Motion.quick) { pulse = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                withAnimation(Theme.Motion.quick) { pulse = false }
            }
            onLongPress()
        }
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
