import SwiftUI

/// 游戏封面 / 图标。
/// 支持两种来源：远程图片 URL（icon 以 http 开头）或 SF Symbol 名称。
/// 纯本地绘制，不依赖任何占位图服务。
struct GameCover: View {
    let game: GSGame
    var symbolScale: CGFloat = 0.42
    var cornerRadius: CGFloat = Theme.Radius.card

    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(
                    colors: [accent.opacity(0.35), Theme.Color.surfaceAlt],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                content(in: geo.size)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Theme.Color.border, lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private func content(in size: CGSize) -> some View {
        if let url = remoteURL {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    symbol(in: size)
                }
            }
        } else {
            symbol(in: size)
        }
    }

    private func symbol(in size: CGSize) -> some View {
        Image(systemName: game.iconURLString.isEmpty ? "gamecontroller.fill" : game.iconURLString)
            .font(.system(size: min(size.width, size.height) * symbolScale, weight: .semibold))
            .foregroundStyle(SwiftUI.Color.white.opacity(0.92))
    }

    private var remoteURL: URL? {
        let raw = game.iconURLString
        guard raw.lowercased().hasPrefix("http") else { return nil }
        return URL(string: raw)
    }

    private var accent: SwiftUI.Color {
        if let hex = game.accentHex, let color = SwiftUI.Color(hexString: hex) {
            return color
        }
        return Theme.Color.accent
    }
}
