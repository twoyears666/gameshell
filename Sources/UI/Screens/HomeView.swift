import SwiftUI

/// 首页：搜索 → 今日推荐（大图 hero）→ 最新资讯 → 热门游戏网格
struct HomeView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                SearchField(text: $state.searchText)

                if let hero = state.manifest?.games.first {
                    SectionHeader(title: "今日推荐", subtitle: state.manifest?.subtitle)
                    HeroCard(game: hero) { state.openDetail(hero) }
                }

                newsSection

                SectionHeader(
                    title: "热门游戏",
                    subtitle: "共 \(state.games.count) 款",
                    actionTitle: "全部",
                    action: { state.selectedTab = .library }
                )
                gameGrid
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.md)
        }
        .background(Theme.Color.background)
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

    // MARK: - 网格

    private var gameGrid: some View {
        LazyVGrid(columns: columns, spacing: Theme.Spacing.md) {
            ForEach(Array(state.games.prefix(8)), id: \.identifier) { game in
                GameCard(game: game) { state.openDetail(game) }
            }
        }
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.md),
              count: sizeClass == .compact ? 1 : 2)
    }
}

/// 首页 hero：大封面 + 底部渐变 + 标题 + 评分 + 启动按钮
struct HeroCard: View {
    let game: GSGame
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                GameCover(game: game, symbolScale: 0.3)
                    .frame(height: 220)

                LinearGradient(
                    colors: [.clear, SwiftUI.Color.black.opacity(0.85)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(game.name)
                        .font(Theme.Font.display)
                        .foregroundStyle(Theme.Color.textPrimary)
                        .lineLimit(1)

                    Text(game.summary)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Color.textSecondary)
                        .lineLimit(2)

                    HStack(spacing: Theme.Spacing.xs) {
                        RatingChip(rating: game.rating)
                        ForEach(game.tags.prefix(2), id: \.self) { tag in
                            TagChip(text: tag)
                        }
                    }
                }
                .padding(Theme.Spacing.md)
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous)
                    .stroke(Theme.Color.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
