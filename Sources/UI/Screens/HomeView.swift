import SwiftUI

#if os(iOS)
import UIKit
#endif

/// 主界面：顶栏 + 「最近游玩」顶排（最多 10 个）+ 「游戏库」方块行 + 添加入口。
/// App 不内置任何游戏 / ROM，方块行渲染的全是用户自己添加或导入的内容。
/// 右上角：添加（URL 条目）+ 设置（键位）。设置页是自绘覆盖层，见 SettingsView。
struct HomeView: View {
    @EnvironmentObject private var state: AppState

    @State private var isAdding = false
    @State private var isImportingROM = false
    @State private var draftName = ""
    @State private var draftURL = ""

    /// 当前被选中的方块：0 = 「最近游玩」顶排，1 = 「游戏库」；index 是那一排里的第几张。
    /// 手柄 / 键盘（方案 2）靠方向键移动它，指针（方案 3）靠悬停直接改它。
    /// 白框只会出现在这一张上，其余卡片一律不描边。
    @State private var focusedRow = 0
    @State private var focusedIndex = 0

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
                                       isActiveRow: focusedRow == 0,
                                       focusedIndex: focusedIndex,
                                       onFocus: { focus(row: 0, index: $0) },
                                       onTap: { state.launch($0) },
                                       onLongPress: { state.showGameMenu(for: $0) })
                    }

                    SectionHeader(title: "游戏库",
                                  subtitle: librarySubtitle,
                                  trailing: AnyView(importROMPill))

                    if state.libraryItems.isEmpty {
                        emptyState
                    } else {
                        LibraryTileRow(items: state.libraryItems,
                                       romCovers: state.romCovers,
                                       isActiveRow: focusedRow == 1,
                                       focusedIndex: focusedIndex,
                                       onFocus: { focus(row: 1, index: $0) },
                                       onTap: { state.launch($0) },
                                       onLongPress: { state.showGameMenu(for: $0) })
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
        // 手柄 / 键盘在首页也能移动选中方块（方案 2）：做成 0 尺寸，不参与布局
        .overlay(alignment: .topLeading) { keyboardCapture }
        .onAppear {
            state.refreshLibrary()
            normalizeFocus()
            updateGamepadForwarding()
        }
        .onChange(of: canNavigate) { _ in updateGamepadForwarding() }
        .onChange(of: state.libraryItems.count) { _ in normalizeFocus() }
        .onChange(of: state.recentItems.count) { _ in normalizeFocus() }
    }

    // MARK: - 首页焦点（方案 2 / 方案 3）

    /// 首页是否接收手柄 / 键盘输入：设置页打开、有浮层、或已经在游玩时一律让路
    private var canNavigate: Bool {
        !state.settingsOpen && state.overlay == nil
            && state.playingGame == nil && state.playingROM == nil
    }

    @ViewBuilder
    private var keyboardCapture: some View {
        #if os(iOS)
        KeyboardCaptureView(isActive: canNavigate) { usage, pressed in
            guard pressed else { return }
            handleKeyboardNav(usage)
        }
        .frame(width: 0, height: 0)
        #else
        EmptyView()
        #endif
    }

    private var rowCounts: [Int] {
        [state.recentItems.count, state.libraryItems.count]
    }

    /// 指针悬停（方案 3）：直接把焦点切到悬停的那一排那一张
    private func focus(row: Int, index: Int) {
        focusedRow = row
        focusedIndex = index
    }

    /// 把焦点夹回合法范围（列表增删后调一次）
    private func normalizeFocus() {
        let counts = rowCounts
        if counts[focusedRow] == 0 {
            if counts[0] > 0 { focusedRow = 0 }
            else if counts[1] > 0 { focusedRow = 1 }
        }
        let count = counts[focusedRow]
        focusedIndex = count == 0 ? 0 : min(focusedIndex, count - 1)
    }

    /// 手柄 / 键盘的焦点移动：左右在本排内移动，上下换排
    private func moveFocus(dx: Int, dy: Int) {
        let counts = rowCounts
        if dy != 0 {
            let target = focusedRow + (dy > 0 ? 1 : -1)
            if target >= 0, target < counts.count, counts[target] > 0 {
                focusedRow = target
                focusedIndex = min(focusedIndex, counts[target] - 1)
            }
            return
        }
        guard dx != 0 else { return }
        let count = counts[focusedRow]
        guard count > 0 else { return }
        focusedIndex = max(0, min(count - 1, focusedIndex + dx))
    }

    /// 打开当前选中的方块（手柄 A / 键盘回车）
    private func launchFocused() {
        let items = focusedRow == 0 ? state.recentItems : state.libraryItems
        guard focusedIndex >= 0, focusedIndex < items.count else { return }
        state.launch(items[focusedIndex])
    }

    private func updateGamepadForwarding() {
        // 开始游玩后，手柄转发归播放器层（EmulatorInputCoordinator）接管，
        // 这里绝不能去 end，否则会把播放器刚接上的 handler 清掉。
        if state.playingROM != nil || state.playingGame != nil { return }

        let manager = GSInputManager.shared()
        if state.settingsOpen || state.overlay != nil {
            manager.endButtonForwarding()
            return
        }
        manager.beginButtonForwarding { identifier, pressed in
            guard pressed else { return }
            handleGamepadNav(identifier)
        }
    }

    private func handleGamepadNav(_ identifier: String) {
        switch identifier {
        case "Direction Pad Left":  moveFocus(dx: -1, dy: 0)
        case "Direction Pad Right": moveFocus(dx: 1, dy: 0)
        case "Direction Pad Up":    moveFocus(dx: 0, dy: -1)
        case "Direction Pad Down":  moveFocus(dx: 0, dy: 1)
        case "Button A":            launchFocused()
        default: break
        }
    }

    #if os(iOS)
    private func handleKeyboardNav(_ usage: UIKeyboardHIDUsage) {
        switch usage {
        case .keyboardLeftArrow:  moveFocus(dx: -1, dy: 0)
        case .keyboardRightArrow: moveFocus(dx: 1, dy: 0)
        case .keyboardUpArrow:    moveFocus(dx: 0, dy: -1)
        case .keyboardDownArrow:  moveFocus(dx: 0, dy: 1)
        case .keyboardReturnOrEnter, .keypadEnter: launchFocused()
        default: break
        }
    }
    #endif

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
/// 只有「当前选中排」里的那一张会亮白框并放大，其余卡片缩小变暗、不描边。
/// 选中位置由外层 HomeView 统一持有：手柄 / 键盘移动焦点（方案 2），指针悬停直接切（方案 3）。
struct LibraryTileRow: View {
    let items: [LibraryItem]
    /// ROM 封面表：rom.identifier → 相对 Documents 的路径
    var romCovers: [String: String] = [:]
    /// 这一排是不是当前被选中的那一排
    var isActiveRow: Bool = false
    /// 当前选中下标（跨排共享，超出本排范围会被夹住）
    var focusedIndex: Int = 0
    /// 指针悬停到某一张时回调，用来把焦点切过去
    var onFocus: (Int) -> Void = { _ in }
    var onTap: (LibraryItem) -> Void
    var onLongPress: (LibraryItem) -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass
    /// 入场动画开关：出现后拉一次，触发错峰入场
    @State private var appeared = false

    private var side: CGFloat {
        sizeClass == .compact ? Theme.Size.squareTile : Theme.Size.squareTileWide
    }

    /// 本排真正高亮的下标（非选中排 → -1，即整排都不亮白框）
    private var activeIndex: Int {
        guard isActiveRow, !items.isEmpty else { return -1 }
        return max(0, min(items.count - 1, focusedIndex))
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    SquareTileCard(
                        item: item,
                        coverRelativePath: coverPath(for: item),
                        side: side,
                        isFocused: index == activeIndex,
                        onHover: { hovering in
                            if hovering { onFocus(index) }
                        },
                        onTap: { onTap(item) },
                        onLongPress: { onLongPress(item) }
                    )
                    // 入场：逐个错峰从下往上弹出（只跑一次）
                    .opacity(appeared ? 1 : 0)
                    .scaleEffect(appeared ? 1 : 0.82, anchor: .bottom)
                    .offset(y: appeared ? 0 : 18)
                    .animation(Theme.Motion.entrance.delay(Double(min(index, 14)) * 0.04), value: appeared)
                }
            }
            .padding(.vertical, Theme.Spacing.sm)
        }
        .onAppear { appeared = true }
    }

    private func coverPath(for item: LibraryItem) -> String? {
        switch item {
        case .game: return nil
        case .rom(let rom): return romCovers[rom.identifier]
        }
    }
}
