import SwiftUI

/// 无图时的兜底内容：有短文字就显示文字（例如系统短名 "GBA"），否则画 SF Symbol。
struct GSCoverFallback: View {
    let text: String?
    let symbol: String
    let size: CGSize
    var symbolScale: CGFloat = 0.42

    var body: some View {
        if let text, !text.isEmpty {
            Text(text)
                .font(.system(size: min(size.width, size.height) * 0.26, weight: .heavy))
                .foregroundStyle(SwiftUI.Color.white.opacity(0.92))
        } else {
            Image(systemName: symbol)
                .font(.system(size: min(size.width, size.height) * symbolScale, weight: .semibold))
                .foregroundStyle(SwiftUI.Color.white.opacity(0.92))
        }
    }
}

/// 游戏封面 / 图标。三种来源，按 `source` 自动判断：
///   · http(s) 远程图片 URL     → AsyncImage
///   · 含 "/" 的相对路径         → 本地文件（Icons/… / Covers/…）
///   · 其它（SF Symbol 名 / 空） → 兜底符号，或用 `fallbackText` 文字代替
/// 纯本地绘制，不依赖任何占位图服务。
struct GameCover: View {

    /// 图标来源：GSGame.iconURLString 原样，或缓存好的封面相对路径
    let source: String
    /// 可选强调色（清单里的 accentHex），只影响无图时的底色渐变
    var accentHex: String? = nil
    /// 无图时显示的短文字（如系统短名 "GBA"）；为 nil 时画 SF Symbol
    var fallbackText: String? = nil
    /// 无图且无 fallbackText 时画的符号名
    var fallbackSymbol: String = "gamecontroller.fill"
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
                    fallback(in: size)
                }
            }
        } else if let path = localRelativePath {
            LocalCoverImage(relativePath: path) {
                fallback(in: size)
            }
        } else {
            fallback(in: size)
        }
    }

    private func fallback(in size: CGSize) -> GSCoverFallback {
        GSCoverFallback(text: fallbackText,
                        symbol: symbolName,
                        size: size,
                        symbolScale: symbolScale)
    }

    private var symbolName: String {
        source.isEmpty ? fallbackSymbol : source
    }

    private var remoteURL: URL? {
        guard source.lowercased().hasPrefix("http") else { return nil }
        return URL(string: source)
    }

    private var localRelativePath: String? {
        guard source.contains("/") else { return nil }
        return source
    }

    private var accent: SwiftUI.Color {
        if let hex = accentHex, let color = SwiftUI.Color(hexString: hex) {
            return color
        }
        return Theme.Color.accent
    }
}
