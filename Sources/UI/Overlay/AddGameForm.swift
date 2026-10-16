import SwiftUI

/// App 内添加 URL 的自绘表单（不使用任何系统弹窗）。
/// 名称 + URL + 可选图标；校验与结果提示都由 AppState 走自绘 toast。
struct AddGameForm: View {
    @Binding var name: String
    @Binding var urlString: String
    var onCancel: () -> Void
    /// 保存：图标数据 + 扩展名（没选图标时为 nil）
    var onSave: (Data?, String?) -> Void

    @State private var iconData: Data?
    @State private var iconExtension: String?
    @State private var preview: GSPlatformImage?
    @State private var isPickingIcon = false
    @State private var iconError: String?

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { onCancel() }

            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text("添加游戏")
                    .font(Theme.Font.section)
                    .foregroundStyle(Theme.Color.textPrimary)

                field(title: "名称", placeholder: "例如：我的网页游戏", text: $name)
                field(title: "URL", placeholder: "https://example.com 或 steam://run/123", text: $urlString)

                iconRow

                Text("http(s) 用内置浏览器打开；其它 scheme（如 steam://）交给系统唤起对应 App。")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: Theme.Spacing.sm) {
                    PillButton(title: "取消", style: .secondary) { onCancel() }
                    PillButton(title: "保存", style: .primary) { onSave(iconData, iconExtension) }
                }
                .padding(.top, Theme.Spacing.xxs)
            }
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: 420)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Theme.Color.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                            .stroke(Theme.Color.border, lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
            .padding(Theme.Spacing.lg)
        }
        .transition(.opacity)
        .iconPicker(isPresented: $isPickingIcon) { url in loadIcon(from: url) }
    }

    // MARK: - 图标

    private var iconRow: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Text("图标（可选）")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.textSecondary)

            HStack(spacing: Theme.Spacing.sm) {
                iconPreview

                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    HStack(spacing: Theme.Spacing.xs) {
                        PillButton(title: iconData == nil ? "选择图片" : "更换图片", style: .secondary) {
                            isPickingIcon = true
                        }
                        .frame(width: 108)

                        if iconData != nil {
                            PillButton(title: "移除", style: .secondary) { clearIcon() }
                                .frame(width: 76)
                        }
                    }

                    if let iconError {
                        Text(iconError)
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Color.accent)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("不选就按 URL 自动取图；本地图片会复制进 App 沙盒。")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Color.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var iconPreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .fill(Theme.Color.surfaceAlt)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .stroke(Theme.Color.border, lineWidth: 1)
                )

            if let preview {
                Image.gs(preview)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.Color.textTertiary)
            }
        }
        .frame(width: 60, height: 60)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
    }

    private func loadIcon(from url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        do {
            let data = try Data(contentsOf: url)
            guard let image = GSPlatformImage(data: data) else {
                iconError = "这个文件不是可用的图片"
                return
            }
            iconData = data
            iconExtension = url.pathExtension.isEmpty ? nil : url.pathExtension.lowercased()
            preview = image
            iconError = nil
        } catch {
            iconError = "读取图片失败：\(error.localizedDescription)"
        }
    }

    private func clearIcon() {
        iconData = nil
        iconExtension = nil
        preview = nil
        iconError = nil
    }

    // MARK: - 文本输入

    private func field(title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Text(title)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.textSecondary)

            TextField("", text: text,
                      prompt: Text(placeholder).foregroundColor(Theme.Color.textTertiary))
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Color.textPrimary)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, Theme.Spacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .fill(Theme.Color.surfaceAlt)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                                .stroke(Theme.Color.border, lineWidth: 1)
                        )
                )
        }
    }
}
