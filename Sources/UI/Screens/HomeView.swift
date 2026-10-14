import SwiftUI

/// 主界面（唯一界面）：顶栏 + 第一排 PS5 风格方块行 + App 内添加 URL 的自绘表单。
/// App 不内置任何游戏，方块行渲染的全是用户在 App 内自己添加的 URL。
struct HomeView: View {
    @EnvironmentObject private var state: AppState

    @State private var isAdding = false
    @State private var draftName = ""
    @State private var draftURL = ""

    var body: some View {
        VStack(spacing: 0) {
            TopBar(
                title: state.title,
                subtitle: state.subtitle,
                inputSummary: state.inputSummary,
                trailing: AnyView(addButton)
            )

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    if state.games.isEmpty {
                        emptyState
                    } else {
                        SectionHeader(title: "游戏", subtitle: "共 \(state.games.count) 款 · 长按卡片可删除")
                        SquareTileRow(
                            games: state.games,
                            onTap: { state.launch($0) },
                            onLongPress: { state.confirmRemoval(of: $0) }
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.md)
            }
        }
        .background(Theme.Color.background)
        .overlay {
            if isAdding {
                AddGameForm(name: $draftName, urlString: $draftURL, onCancel: dismissAdd, onSave: save)
            }
        }
    }

    // MARK: - 顶栏右侧的添加按钮

    private var addButton: some View {
        Button {
            draftName = ""
            draftURL = ""
            withAnimation(Theme.Motion.spring) { isAdding = true }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                Text("添加")
                    .font(Theme.Font.chip)
            }
            .foregroundStyle(SwiftUI.Color.black.opacity(0.9))
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous)
                    .fill(Theme.Color.accent)
            )
        }
        .buttonStyle(.plain)
    }

    private func dismissAdd() {
        withAnimation(Theme.Motion.standard) { isAdding = false }
    }

    private func save() {
        if state.addGame(name: draftName, urlString: draftURL) {
            dismissAdd()
        }
    }

    // MARK: - 空态

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
            Text("App 不内置游戏，点右上角「添加」填名称和 URL 即可。\nhttp(s) 用内置浏览器打开；steam:// 这类链接交给系统唤起对应 App。\n添加的条目会存到沙盒，重启后仍在。")
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
}

/// 分区标题（只保留标题 + 副标题）
private struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Theme.Font.section)
                .foregroundStyle(Theme.Color.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 第一排：PS5 风格横向方块行。
/// 聚焦项（默认第一个，指针悬停时切换）放大并高亮描边，其余缩小变暗。
struct SquareTileRow: View {
    let games: [GSGame]
    var onTap: (GSGame) -> Void
    var onLongPress: (GSGame) -> Void

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
                        onTap: { onTap(game) },
                        onLongPress: { onLongPress(game) }
                    )
                }
            }
            .padding(.vertical, Theme.Spacing.sm)
        }
    }
}
