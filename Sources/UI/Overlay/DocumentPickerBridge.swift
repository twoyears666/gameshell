//
//  DocumentPickerBridge.swift
//  Gameshell
//
//  系统文件选择器的统一桥接。它不是「弹窗」——本 App 的提示 / 确认仍然全部走自绘浮层，
//  但「浏览文件」在 iOS 上只有 UIDocumentPickerViewController 一条路，所以单独封装一份，
//  给「导入 ROM」与「选择图标」共用。
//
//  iOS：用 0 尺寸宿主 VC 呈现 UIDocumentPickerViewController（避开 SwiftUI 的 .sheet）；
//  macOS：直接用 .fileImporter 打开系统文件面板。
//

import SwiftUI
import UniformTypeIdentifiers

#if os(iOS)
import UIKit

/// 用 0 尺寸宿主 VC 呈现 UIDocumentPickerViewController。
struct DocumentPickerBridge: UIViewControllerRepresentable {

    @Binding var isPresented: Bool
    /// 允许选择的类型；ROM 的扩展名没有系统类型，传 [.data] 交给 App 自己按扩展名识别
    var contentTypes: [UTType] = [.data]
    var onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ viewController: UIViewController, context: Context) {
        context.coordinator.onPick = onPick
        context.coordinator.onFinish = { isPresented = false }

        guard isPresented else { return }
        guard viewController.presentedViewController == nil else { return }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        viewController.present(picker, animated: true)
    }

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        var onPick: (URL) -> Void
        var onFinish: (() -> Void)?

        init(onPick: @escaping (URL) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController,
                            didPickDocumentsAt urls: [URL]) {
            if let url = urls.first { onPick(url) }
            onFinish?()
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onFinish?()
        }
    }
}

#endif

/// 「选一张图片」的便捷修饰符：iOS 走上面的文件选择器，macOS 走系统文件面板。
struct IconPickerModifier: ViewModifier {

    @Binding var isPresented: Bool
    var onPick: (URL) -> Void

    func body(content: Content) -> some View {
        #if os(iOS)
        content.background(
            DocumentPickerBridge(isPresented: $isPresented, contentTypes: [.image], onPick: onPick)
                .frame(width: 0, height: 0)
        )
        #else
        content.fileImporter(isPresented: $isPresented,
                             allowedContentTypes: [.image],
                             allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                onPick(url)
            }
        }
        #endif
    }
}

extension View {
    /// 挂上「选图片」能力（呈现由 isPresented 控制，选中后回调本地文件 URL）
    func iconPicker(isPresented: Binding<Bool>, onPick: @escaping (URL) -> Void) -> some View {
        modifier(IconPickerModifier(isPresented: isPresented, onPick: onPick))
    }
}
