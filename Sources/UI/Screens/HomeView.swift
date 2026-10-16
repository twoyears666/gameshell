import SwiftUI

/// 主界面：顶栏 + 「最近游玩」顶排（最多 10 个）+ 「游戏库」方块行 + 添加入口。
/// App 不内置任何游戏 / ROM，方块行渲染的全是用户自己添加或导入的内容。
/// 右上角：添加（URL 条目）+ 设置（键位）。设置页是自绘覆盖层，见 SettingsView。
struct HomeView: View {
    @EnvironmentObject private var state: AppState

    @State private var isAdding = false
    @State private var isImportingROM = false
    @State private var draftName = ""
    @State private var draftURL = ""

    var body: some View {
        VStack(spacing: 0) {
            TopBar(
                title: state.title,
                subtitle: state.subtitle,
                inputSummary: state.inputSummary,
                trailing: AnyView(barButtons)
            )

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    if !state.recentItems.isEmpty {
                        SectionHeader(title: "最近游玩",
                                      subtitle: "最近玩过的 \(state.recentItems.count) 个")
                        LibraryTileRow(items: state.recentItems,
                                       romCovers: state.romCovers,
                                       onTap: { state.launch($0) },
                                       onLongPress: { state.confirmRemoval(of: $0) })
                    }

                    SectionHeader(title: "游戏库",
                                  subtitle: librarySubtitle,
                                  trailing: AnyView(importROMPill))

                    if state.libraryItems.isEmpty {
                        emptyState
                    } else {
                        LibraryTileRow(items: state.libraryItems,
                                       romCovers: state.romCovers,
                                       onTap: { state.launch($0) },
                                       onLongPress: { state.confirmRemoval(of: $0) })
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.md)
            }
        }
        .background(Theme.Color.background)
        .overlay {
            ZStack {
                if isAdding {
                    AddGameForm(name: $draftName,
                                urlString: $draftURL,
                                onCancel: dismissAdd) { data, extensionName in
                        save(iconData: data, iconExtension: extensionName)
                    }
                }

                #if os(iOS)
                if isImportingROM {
                    ImportROMSheet(onClose: dismissImport)
                }
                #endif
            }
        }
        .onAppear { state.refreshLibrary() }
    }

    // MARK: - 顶栏右侧

    private var barButtons: some View {
        HStack(spacing: Theme.Spacing.xs) {
            addButton
            settingsButton
        }
    }

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

    private var settingsButton: some View {
        Button {
            state.openSettings()
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Color.textPrimary)
                .frame(width: 32, height: 32)
                .background(
                    Circle().fill(Theme.Color.surface)
                        .overlay(Circle().stroke(Theme.Color.border, lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
    }

    /// 「导入 ROM」胶囊：只在 iOS 显示（macOS 版是纯 URL 模式）
    @ViewBuilder
    private var importROMPill: some View {
        #if os(iOS)
        Button {
            withAnimation(Theme.Motion.spring) { isImportingROM = true }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 12, weight: .bold))
                Text("导入 ROM")
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
        #else
        EmptyView()
        #endif
    }

    // MARK: - 文案

    private var librarySubtitle: String {
        let gameCount = state.games.count
        let romCount = state.roms.count
        if gameCount == 0 && romCount == 0 {
            return "还没有内容，点右上角「添加」或「导入 ROM」"
        }

        var parts: [String] = []
        if gameCount > 0 { parts.append("URL 条目 \(gameCount) 个") }
        if romCount > 0 { parts.append("ROM \(romCount) 个") }
        return parts.joined(separator: " · ") + " · 长按卡片可删除"
    }

    // MARK: - 动作

    private func dismissAdd() {
        withAnimation(Theme.Motion.standard) { isAdding = false }
    }

    private func dismissImport() {
        withAnimation(Theme.Motion.standard) { isImportingROM = false }
    }

    private func save(iconData: Data?, iconExtension: String?) {
        if state.addGame(name: draftName,
                         urlString: draftURL,
                         iconData: iconData,
                         iconExtension: iconExtension) {
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
                Text("游戏库还是空的")
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Color.textPrimary)
            }
            Text("App 不内置游戏。点右上角「添加」填名称和 URL（http(s) 用内置浏览器打开，steam:// 这类交给系统）；\n模拟器 ROM 点「导入 ROM」从「文件」里选，导入后会自动去取官方封面当图标。")
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

/// 分区标题：标题 + 副标题 + 可选右侧控件（例如「导入 ROM」）
private struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var trailing: AnyView? = nil

    var body: some View {
        HStack(alignment: .bottom, spacing: Theme.Spacing.sm) {
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

            trailing
        }
    }
}

/// 一排方块卡（PS5 风格横向行）。
/// 聚焦项（默认第一个，指针悬停时切换）放大并高亮描边，其余缩小变暗。
struct LibraryTileRow: View {
    let items: [LibraryItem]
    /// ROM 封面表：rom.identifier → 相对 Documents 的路径
    var romCovers: [String: String] = [:]
    var onTap: (LibraryItem) -> Void
    var onLongPress: (LibraryItem) -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var focusedID: String?

    private var side: CGFloat {
        sizeClass == .compact ? Theme.Size.squareTile : Theme.Size.squareTileWide
    }

    private var focusedIdentifier: String? {
        focusedID ?? items.first?.id
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(items) { item in
                    SquareTileCard(
                        item: item,
                        coverRelativePath: coverPath(for: item),
                        side: side,
                        isFocused: focusedIdentifier == item.id,
                        onHover: { hovering in
                            if hovering { focusedID = item.id }
                        },
                        onTap: { onTap(item) },
                        onLongPress: { onLongPress(item) }
                    )
                }
            }
            .padding(.vertical, Theme.Spacing.sm)
        }
    }

    private func coverPath(for item: LibraryItem) -> String? {
        switch item {
        case .game: return nil
        case .rom(let rom): return romCovers[rom.identifier]
        }
    }
}
