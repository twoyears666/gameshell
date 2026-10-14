import SwiftUI

/// 顶部搜索框（自绘，不依赖系统搜索组件样式）。
struct SearchField: View {
    @Binding var text: String
    var placeholder: String = "搜索游戏"

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.Color.textSecondary)

            // 注意：prompt 要求的是 Text，而 Text.foregroundStyle 需要 iOS 17+，
            // 这里用 Text.foregroundColor（iOS 13+，软弃用不报警告）保持 iOS 16 可用。
            TextField("", text: $text, prompt: Text(placeholder).foregroundColor(Theme.Color.textTertiary))
                .textFieldStyle(.plain)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Color.textPrimary)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                #endif

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.Color.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs + 2)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous)
                .fill(Theme.Color.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous)
                        .stroke(Theme.Color.border, lineWidth: 1)
                )
        )
    }
}

/// 横向滚动的分类 chips
struct CategoryChips: View {
    let categories: [String]
    @Binding var selection: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.xs) {
                ForEach(categories, id: \.self) { category in
                    Button {
                        withAnimation(Theme.Motion.quick) { selection = category }
                    } label: {
                        Text(category)
                            .font(Theme.Font.chip)
                            .foregroundStyle(selection == category
                                             ? SwiftUI.Color.black.opacity(0.85)
                                             : Theme.Color.textSecondary)
                            .padding(.horizontal, Theme.Spacing.sm)
                            .padding(.vertical, Theme.Spacing.xs)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous)
                                    .fill(selection == category ? Theme.Color.accent : Theme.Color.surface)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous)
                                            .stroke(selection == category ? .clear : Theme.Color.border, lineWidth: 1)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }
}
