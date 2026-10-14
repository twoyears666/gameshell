import SwiftUI
import Foundation

/// 「我的」页：账号、外设、深链调试、关于。
/// 未实现的功能一律显式标注「未完成」，不隐藏。
struct ProfileView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                profileHeader

                group(title: "外设") {
                    SettingRow(systemImage: "gamecontroller", title: "手柄", detail: state.inputSummary)
                    SettingRow(systemImage: "keyboard", title: "键盘 / 鼠标", detail: "系统级接入，按键映射未完成")
                }

                group(title: "URL 驱动") {
                    SettingRow(systemImage: "link", title: "深链格式", detail: "gameshell://")
                    SettingRow(systemImage: "lifepreserver", title: "自检", detail: "打开首页") {
                        state.selectedTab = .home
                        state.showToast("已回到首页")
                    }
                    SettingRow(systemImage: "plus.app",
                               title: "添加游戏",
                               detail: state.games.isEmpty ? "清单为空" : "共 \(state.games.count) 款") {
                        state.showToast("编辑 Resources/games.json 添加，或用 gameshell://open?url=… 深链打开")
                    }
                }

                group(title: "功能状态（诚实清单）") {
                    SettingRow(systemImage: "person.crop.circle.badge.questionmark", title: "账号登录", detail: "未完成")
                    SettingRow(systemImage: "cloud.fill", title: "云游戏串流", detail: "未完成")
                    SettingRow(systemImage: "arrow.down.circle", title: "游戏下载 / 安装", detail: "未完成")
                    SettingRow(systemImage: "cpu", title: "本地模拟器内核", detail: "未完成")
                    SettingRow(systemImage: "gamecontroller.badge.xmark", title: "手柄按键映射到网页", detail: "未完成")
                    SettingRow(systemImage: "rectangle.on.rectangle.slash", title: "首页方块行的手柄焦点导航", detail: "未完成（当前只有指针悬停聚焦）")
                    SettingRow(systemImage: "square.and.pencil", title: "图形化添加游戏", detail: "未完成（当前编辑 games.json / 深链）")
                }

                group(title: "关于") {
                    SettingRow(systemImage: "info.circle", title: "Gameshell", detail: version)
                    SettingRow(systemImage: "doc.plaintext", title: "参考说明", detail: "见 REFERENCE.md")
                    SettingRow(systemImage: "envelope", title: "反馈") {
                        state.showToast("反馈入口未完成")
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.md)
        }
        .background(Theme.Color.background)
    }

    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        return "v\(short)"
    }

    private var profileHeader: some View {
        HStack(spacing: Theme.Spacing.md) {
            ZStack {
                Circle().fill(Theme.Color.surfaceAlt)
                Image(systemName: "person.fill")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            .frame(width: 64, height: 64)
            .overlay(Circle().stroke(Theme.Color.border, lineWidth: 1))

            VStack(alignment: .leading, spacing: 4) {
                Text("未登录")
                    .font(Theme.Font.title)
                    .foregroundStyle(Theme.Color.textPrimary)
                Text("账号体系未完成，当前为本地模式")
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

    @ViewBuilder
    private func group<Content: View>(title: String,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(title)
                .font(Theme.Font.chip)
                .foregroundStyle(Theme.Color.textTertiary)
                .textCase(.uppercase)
            content()
        }
    }
}
