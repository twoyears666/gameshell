//
//  ImportROMSheet.swift
//  Gameshell
//
//  「导入 ROM」自绘浮层。
//
//  说明 + 系统支持表 + 一个「选择 ROM 文件」的动作按钮。
//  选文件走共享的 DocumentPickerBridge（系统文件选择器）——iOS 上唯一
//  能浏览文件的方式；它不是弹窗，本 App 的提示 / 确认仍然全部走自绘浮层。
//

import SwiftUI

#if os(iOS)

import UniformTypeIdentifiers

struct ImportROMSheet: View {

    @EnvironmentObject private var state: AppState
    var onClose: () -> Void

    @State private var isPickerPresented = false

    var body: some View {
        ZStack {
            SwiftUI.Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            card
        }
        .transition(.opacity)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("导入 ROM")
                .font(Theme.Font.section)
                .foregroundStyle(Theme.Color.textPrimary)

            Text("App 不内置任何 ROM。选中的文件会复制到 App 沙盒的 Documents/ROMs/<系统>/（重名自动加序号，不覆盖已有文件）。\nNDS / 3DS / Wii / Wii U 的核心还没接入，导进来的 ROM 会先待在库里，等核心接上再能启动。")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                CoreStatusList()
            }
            .frame(maxHeight: 220)

            HStack(spacing: Theme.Spacing.sm) {
                PillButton(title: "关闭", style: .secondary) { onClose() }
                PillButton(title: "选择 ROM 文件", style: .primary) {
                    isPickerPresented = true
                }
            }
            .padding(.top, Theme.Spacing.xxs)
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: 460)
        .background(GSCardBackground())
        .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
        .padding(Theme.Spacing.lg)
        .background(picker)
    }

    /// 0 尺寸桥接视图：把系统文件选择器呈现出来
    private var picker: some View {
        DocumentPickerBridge(isPresented: $isPickerPresented, contentTypes: [.data]) { url in
            state.importROM(from: url)
            onClose()
        }
        .frame(width: 0, height: 0)
    }
}

#endif
