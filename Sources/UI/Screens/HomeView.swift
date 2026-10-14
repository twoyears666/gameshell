import SwiftUI

/// 首页：搜索 → 第一排（PS5 风格横向方块行）→ 最新资讯。
/// 本 App 不内置任何游戏，清单为空时给出添加指引。
struct HomeView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                SearchField(text: $state.searchText)

                if state.games.isEmpty {
                    emptyState
                } else {
                    SectionHeader(
                        title: "游戏",
                        subtitle: "共 \(state.games.count) 款 · 左右滑动",
                        actionTitle: "全部",
                        action: { state.selectedTab = .library }
                    )
                    SquareTileRow(games: state.games) { state.openDetail($0) }
                }

                newsSection
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.md)
        }
        .background(Theme.Color.background)
    }

    // MARK: - 空清单引导

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.Color.accent)
                Text("还没有添加任何游戏")
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Color.textPrimary)
            }
            Text("本 App 不内置游戏，全部由你自己添加：\n① 编辑 Resources/games.json 写入条目（url 可以是网页，也可以是 steam:// 这类唤起本机 App 的链接）\n② 或用深链临时打开：gameshell://open?url=https://example.com/game")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.Color.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .stroke(Theme.Color.border, lineWidth: 1)
                )
        )
    }

    // MARK: - 资讯

    private var newsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: "最新资讯", subtitle: "资讯源未接入（未完成）")
            ForEach(Self.placeholderNews, id: \.title) { item in
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: item.symbol)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Theme.Color.accentSecondary)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(Theme.Font.body)
                            .foregroundStyle(Theme.Color.textPrimary)
                        Text(item.detail)
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Color.textSecondary)
                    }
                    Spacer()
                }
                .padding(Theme.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .fill(Theme.Color.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                                .stroke(Theme.Color.border, lineWidth: 1)
                        )
                )
                .opacity(0.65)
            }
        }
    }

    private static let placeholderNews: [(symbol: String, title: String, detail: String)] = [
        ("sparkles", "盖世热门榜每周更新", "榜单拉取接口未完成，当前为静态占位"),
        ("bolt.fill", "手柄支持已接入", "GameController 热插拔已可用，键鼠映射未完成"),
        ("cloud.fill", "云游戏串流", "串流通道未完成"),
    ]
}

/// 第一排：PS5 风格横向方块行。
/// 聚焦项（默认第一个，指针悬停时切换）放大并高亮描边，其余缩小变暗。
struct SquareTileRow: View {
    let games: [GSGame]
    var onTap: (GSGame) -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var focusedID: String?

    private var side: CGFloat {
        sizeClass == .compact ? Theme.Size.squareTile : Theme.Size.squareTileWide
    }

    private var focusedIdentifier: String? {
        focusedID ?? games.first?.identifier
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(games, id: \.identifier) { game in
                    SquareTileCard(
                        game: game,
                        side: side,
                        isFocused: focusedIdentifier == game.identifier,
                        onHover: { hovering in
                            if hovering { focusedID = game.identifier }
                        },
                        onTap: { onTap(game) }
                    )
                }
            }
            .padding(.vertical, Theme.Spacing.sm)
        }
    }
}
