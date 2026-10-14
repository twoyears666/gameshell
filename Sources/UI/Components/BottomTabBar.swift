import SwiftUI

/// 底部标签栏（自绘，不使用系统 TabView 外观）。
struct BottomTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    withAnimation(Theme.Motion.quick) { selection = tab }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 19, weight: .medium))
                        Text(tab.rawValue)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(selection == tab ? Theme.Color.accent : Theme.Color.textSecondary)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, Theme.Spacing.xs)
        .padding(.bottom, Theme.Spacing.xs)
        .padding(.horizontal, Theme.Spacing.xs)
        .background(
            Theme.Color.backgroundElevated
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Theme.Color.border)
                        .frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        )
    }
}

/// 顶部栏：标题 + 右侧外设状态胶囊。
struct TopBar: View {
    let title: String
    var subtitle: String? = nil
    var inputSummary: String
    var trailing: AnyView? = nil

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Theme.Font.title)
                    .foregroundStyle(Theme.Color.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Color.textSecondary)
                }
            }

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: "gamecontroller")
                    .font(.system(size: 11, weight: .semibold))
                Text(inputSummary)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(Theme.Color.textSecondary)
            .padding(.horizontal, Theme.Spacing.xs)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous)
                    .fill(Theme.Color.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous)
                            .stroke(Theme.Color.border, lineWidth: 1)
                    )
            )

            trailing
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.top, Theme.Spacing.xs)
        .padding(.bottom, Theme.Spacing.sm)
        .background(Theme.Color.headerGradient)
    }
}
