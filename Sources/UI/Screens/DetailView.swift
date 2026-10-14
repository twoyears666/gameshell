import SwiftUI

/// 游戏详情页：返回 + 封面 + 标题评分 + 标签 + 介绍 + 底部启动栏
struct DetailView: View {
    let game: GSGame
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            detailTopBar

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    GameCover(game: game, symbolScale: 0.28)
                        .frame(height: 230)

                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        HStack(spacing: Theme.Spacing.xs) {
                            Text(game.name)
                                .font(Theme.Font.display)
                                .foregroundStyle(Theme.Color.textPrimary)
                            Spacer()
                            RatingChip(rating: game.rating)
                        }

                        HStack(spacing: Theme.Spacing.xs) {
                            TagChip(text: game.platform, highlighted: true)
                            if game.controllerSupport {
                                TagChip(text: "手柄", highlighted: false)
                            }
                            ForEach(game.tags, id: \.self) { tag in
                                TagChip(text: tag)
                            }
                        }
                    }

                    SectionHeader(title: "游戏介绍")
                    Text(game.summary.isEmpty ? "暂无介绍" : game.summary)
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    SectionHeader(title: "启动地址", subtitle: "URL 驱动")
                    Text(game.gameURLString)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(Theme.Color.textSecondary)
                        .textSelection(.enabled)
                        .padding(Theme.Spacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                                .fill(Theme.Color.surface)
                                .overlay(
                                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                                        .stroke(Theme.Color.border, lineWidth: 1)
                                )
                        )

                    SectionHeader(title: "更多内容", subtitle: "成就 / 云存档 未完成")
                    Text("本区块为占位，成就系统与云存档尚未实现。")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Color.textTertiary)
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.md)
            }

            actionBar
        }
        .background(Theme.Color.background)
    }

    private var detailTopBar: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Button {
                state.closeDetail()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.Color.textPrimary)
                    .frame(width: 34, height: 34)
                    .background(
                        Circle().fill(Theme.Color.surface)
                            .overlay(Circle().stroke(Theme.Color.border, lineWidth: 1))
                    )
            }
            .buttonStyle(.plain)

            Text("详情")
                .font(Theme.Font.section)
                .foregroundStyle(Theme.Color.textPrimary)

            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.top, Theme.Spacing.xs)
        .padding(.bottom, Theme.Spacing.sm)
        .background(Theme.Color.headerGradient)
    }

    private var actionBar: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Button {
                state.showToast("收藏功能未完成")
            } label: {
                Image(systemName: "heart")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.Color.textPrimary)
                    .frame(width: 48, height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                            .fill(Theme.Color.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                                    .stroke(Theme.Color.border, lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)

            Button {
                state.launch(game)
            } label: {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 15, weight: .bold))
                    Text("启动游戏")
                        .font(Theme.Font.button)
                }
                .foregroundStyle(SwiftUI.Color.black.opacity(0.9))
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.sm + 2)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous)
                        .fill(Theme.Color.accent)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            Theme.Color.backgroundElevated
                .overlay(alignment: .top) {
                    Rectangle().fill(Theme.Color.border).frame(height: 1)
                }
        )
    }
}
