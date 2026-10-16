//
//  CoreStatusList.swift
//  Gameshell
//
//  模拟器「核心接入状态」的共用 UI：
//    · CoreStatusChip —— 单个系统的接入小标签
//    · CoreStatusList —— 九个系统一览（诚实标注，未接入的写明计划核心与是否依赖 JIT）
//    · GSCardBackground —— 卡片背景（surface + 描边）
//
//  设置页与「导入 ROM」浮层都用这一份，避免两处各写一遍状态表。
//  macOS 版是纯 URL 模式，没有模拟器，故整体只在 iOS 下编译。
//

import SwiftUI

#if os(iOS)

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

/// 九个系统的接入状态一览
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

/// 卡片背景（surface + 描边），与主界面其它卡片保持一致的观感。
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
