//
//  RomLibrarySection.swift
//  Gameshell
//
//  主界面里的「模拟器 ROM」分区：
//    · 按系统分组的 ROM 方块行（点开 = 启动，长按 = 删除）
//    · 导入入口
//    · 各系统核心接入状态表（未接入的一律如实写明，不假装能玩）
//
//  App 不内置任何 ROM，这里列出的全是用户自己导入的文件（Documents/ROMs/<系统>/）。
//

import SwiftUI

#if os(iOS)

/// 「模拟器 ROM」分区
struct RomLibrarySection: View {

    let roms: [GSROM]
    var onImport: () -> Void
    var onOpen: (GSROM) -> Void
    var onDelete: (GSROM) -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass

    private var tileSide: CGFloat {
        sizeClass == .compact ? Theme.Size.squareTile : Theme.Size.squareTileWide
    }

    // 系统分组按注册表顺序遍历，没有 ROM 的系统直接跳过
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            header

            if roms.isEmpty {
                emptyState
            } else {
                ForEach(GSSystemRegistry.allSystems(), id: \.identifier) { info in
                    let groupROMs = roms.filter { $0.system == info.system }
                    if !groupROMs.isEmpty {
                        groupView(info, groupROMs)
                    }
                }
            }

            coreStatusCard
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 标题

    private var header: some View {
        HStack(alignment: .bottom, spacing: Theme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text("模拟器 ROM")
                    .font(Theme.Font.section)
                    .foregroundStyle(Theme.Color.textPrimary)
                Text(roms.isEmpty
                     ? "App 不内置 ROM，导入你自己的 ROM 文件后在这里启动"
                     : "共 \(roms.count) 个 · 点开启动，长按删除")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.textSecondary)
            }

            Spacer()

            Button(action: onImport) {
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
        }
    }

    // MARK: - 分组

    private func groupView(_ info: GSSystemInfo, _ groupROMs: [GSROM]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.xs) {
                Text(info.shortName)
                    .font(Theme.Font.cardTitle)
                    .foregroundStyle(Theme.Color.textPrimary)
                CoreStatusChip(info: info)
                Spacer()
                Text("\(groupROMs.count) 个")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.textTertiary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(groupROMs, id: \.identifier) { rom in
                        RomTileCard(rom: rom,
                                    side: tileSide,
                                    isPlayable: info.coreIntegrated,
                                    onTap: { onOpen(rom) },
                                    onLongPress: { onDelete(rom) })
                    }
                }
                .padding(.vertical, Theme.Spacing.xs)
            }
        }
    }

    // MARK: - 空态 / 状态表

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "sdcard")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.Color.accent)
                Text("还没有 ROM")
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Color.textPrimary)
            }
            Text("App 不内置任何 ROM。点「导入 ROM」从「文件」里选，导入后复制到 App 沙盒的 Documents/ROMs/<系统>/；\n也可以在「文件」App 里直接把 ROM 拷进来（已开启文件共享）。")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GSCardBackground())
    }

    private var coreStatusCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("核心接入进度")
                .font(Theme.Font.cardTitle)
                .foregroundStyle(Theme.Color.textPrimary)
            CoreStatusList()
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GSCardBackground())
    }
}

// MARK: - ROM 方块卡片

/// 一个 ROM 的方块卡片：系统徽标 + 名称。核心未接入的系统会额外标注出来。
struct RomTileCard: View {
    let rom: GSROM
    let side: CGFloat
    let isPlayable: Bool
    var onTap: () -> Void
    var onLongPress: () -> Void

    private var info: GSSystemInfo { GSSystemRegistry.info(for: rom.system) }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [Theme.Color.surfaceAlt, Theme.Color.surface],
                startPoint: .top,
                endPoint: .bottom
            )

            Image(systemName: "gamecontroller.fill")
                .font(.system(size: side * 0.3, weight: .semibold))
                .foregroundStyle(isPlayable ? Theme.Color.accent.opacity(0.9) : Theme.Color.textTertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(.bottom, side * 0.14)

            LinearGradient(
                colors: [.clear, SwiftUI.Color.black.opacity(0.82)],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(rom.name)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Color.textPrimary)
                    .lineLimit(1)
                Text(isPlayable ? info.shortName : "\(info.shortName) · 核心未接入")
                    .font(Theme.Font.caption)
                    .foregroundStyle(isPlayable ? Theme.Color.textSecondary : Theme.Color.accent)
                    .lineLimit(1)
            }
            .padding(Theme.Spacing.sm)

            Text(info.shortName)
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
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous)
                .stroke(Theme.Color.border, lineWidth: 1)
        )
        .opacity(isPlayable ? 1 : 0.66)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .onLongPressGesture(minimumDuration: 0.5) { onLongPress() }
    }
}

// MARK: - 系统 / 核心状态

/// 单个系统的「核心是否接入」小标签
struct CoreStatusChip: View {
    let info: GSSystemInfo

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(info.coreIntegrated ? Theme.Color.accent : Theme.Color.textSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                    .fill(info.coreIntegrated ? Theme.Color.accent.opacity(0.14) : Theme.Color.surfaceAlt)
            )
    }

    private var text: String {
        if info.coreIntegrated {
            let core = GSEmulatorSession.coreName(for: info.system) ?? info.plannedCoreName ?? "核心"
            return "已接入 · \(core)"
        }
        let planned = info.plannedCoreName ?? "无计划核心"
        return "未接入 · 计划 \(planned)"
    }
}

/// 九个系统的接入状态一览（诚实标注，未接入的写明计划核心与是否依赖 JIT）
struct CoreStatusList: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(GSSystemRegistry.allSystems(), id: \.identifier) { info in
                HStack(spacing: Theme.Spacing.xs) {
                    Text(info.shortName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.Color.textPrimary)
                        .frame(width: 62, alignment: .leading)

                    Text(info.fileExtensions.map { "." + $0 }.joined(separator: " "))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Color.textTertiary)
                        .lineLimit(1)

                    Spacer(minLength: Theme.Spacing.xs)

                    if info.requiresJIT {
                        Text("需 JIT")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.Color.textSecondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                                    .fill(Theme.Color.surfaceAlt)
                            )
                    }

                    CoreStatusChip(info: info)
                }
            }
        }
    }
}

// MARK: - 共用

/// 卡片背景（深色 surface + 描边），与主界面其它卡片保持一致的观感。
struct GSCardBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            .fill(Theme.Color.surface)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .stroke(Theme.Color.border, lineWidth: 1)
            )
    }
}

#endif
