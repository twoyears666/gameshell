import SwiftUI

/// 榜单：横幅 + 榜单项（热门 / 最新）
struct ChartsView: View {
    @EnvironmentObject private var state: AppState
    @State private var ranking: RankingKind = .hot

    enum RankingKind: String, CaseIterable, Identifiable {
        case hot = "热门榜"
        case latest = "最新榜"
        var id: String { rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                banner
                segmented
                CategoryChips(categories: state.categories, selection: $state.selectedCategory)

                let list = rankedList
                if list.isEmpty {
                    Text("暂无数据")
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.Color.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.xl)
                } else {
                    VStack(spacing: Theme.Spacing.xs) {
                        ForEach(Array(list.enumerated()), id: \.element.identifier) { index, game in
                            GameRow(rank: index + 1, game: game) { state.openDetail(game) }
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.md)
        }
        .background(Theme.Color.background)
    }

    // MARK: - 横幅

    private var banner: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.Color.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Gameshell 热门榜")
                    .font(Theme.Font.section)
                    .foregroundStyle(Theme.Color.textPrimary)
                Text("榜单数据来自本地清单评分（在线拉取未完成）")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            Spacer()
        }
        .padding(Theme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.Color.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .stroke(Theme.Color.border, lineWidth: 1)
                )
        )
    }

    private var segmented: some View {
        HStack(spacing: 0) {
            ForEach(RankingKind.allCases) { kind in
                Button {
                    withAnimation(Theme.Motion.quick) { ranking = kind }
                } label: {
                    Text(kind.rawValue)
                        .font(Theme.Font.body)
                        .foregroundStyle(ranking == kind ? SwiftUI.Color.black.opacity(0.85) : Theme.Color.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.xs)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                                .fill(ranking == kind ? Theme.Color.accent : SwiftUI.Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.control + 3, style: .continuous)
                .fill(Theme.Color.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.control + 3, style: .continuous)
                        .stroke(Theme.Color.border, lineWidth: 1)
                )
        )
    }

    private var rankedList: [GSGame] {
        var base = state.games.filter {
            state.selectedCategory == "全部" || $0.platform == state.selectedCategory
        }
        switch ranking {
        case .hot:
            base.sort { $0.rating > $1.rating }
        case .latest:
            base.reverse()
        }
        return base
    }
}
