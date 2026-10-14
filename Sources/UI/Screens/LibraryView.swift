import SwiftUI

/// 游戏库：分类 chips + 搜索 + 自适应网格
struct LibraryView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                SearchField(text: $state.searchText)
                CategoryChips(categories: state.categories, selection: $state.selectedCategory)

                let list = state.filteredGames
                if list.isEmpty {
                    emptyState
                } else {
                    SectionHeader(title: state.selectedCategory == "全部" ? "全部游戏" : state.selectedCategory,
                                  subtitle: "共 \(list.count) 款")
                    LazyVGrid(columns: columns, spacing: Theme.Spacing.md) {
                        ForEach(list, id: \.identifier) { game in
                            GameCard(game: game) { state.openDetail(game) }
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.md)
        }
        .background(Theme.Color.background)
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(Theme.Color.textTertiary)
            Text(state.games.isEmpty ? "清单为空，请检查 games.json" : "没有符合条件的游戏")
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xl)
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.md),
              count: Theme.gridColumns(for: gridWidth))
    }

    /// 网格按容器宽度计算列数，此处用一个保守估计值
    private var gridWidth: CGFloat {
        #if os(macOS)
        return 1000
        #else
        return 420
        #endif
    }
}
