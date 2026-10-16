//
//  KeyboardCapture.swift
//  Gameshell
//
//  硬件键盘捕获（iOS）。UIKit 里唯一可靠的「拿到物理按键」方式是让一个
//  UIResponder 成为 first responder，再覆写 pressesBegan / pressesEnded。
//  （最低支持 iOS 16，用不了 iOS 17 才有的 SwiftUI .onKeyPress。）
//
//  模拟器（把按键转发给核心）与设置页（捕获要绑定的键）共用这一份。
//  视图做成 0 尺寸：不参与布局，也不遮挡任何东西。
//

import SwiftUI

#if os(iOS)
import UIKit

struct KeyboardCaptureView: UIViewRepresentable {

    /// true 时成为 first responder 开始收键；false 时主动交还
    var isActive: Bool
    /// 每次按下 / 抬起回调（keyCode 是 UIKeyboardHIDUsage 的原始值）
    var onKey: (UIKeyboardHIDUsage, Bool) -> Void

    func makeUIView(context: Context) -> CaptureUIView {
        let view = CaptureUIView()
        view.isUserInteractionEnabled = true
        view.onKey = onKey
        view.isActive = isActive
        return view
    }

    func updateUIView(_ view: CaptureUIView, context: Context) {
        view.onKey = onKey
        view.isActive = isActive
        view.updateFirstResponder()
    }
}

final class CaptureUIView: UIView {

    var onKey: ((UIKeyboardHIDUsage, Bool) -> Void)?
    var isActive = false

    override var canBecomeFirstResponder: Bool { isActive }

    /// 进入 / 退出捕获时调整 first responder 状态
    func updateFirstResponder() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.isActive {
                if !self.isFirstResponder { self.becomeFirstResponder() }
            } else if self.isFirstResponder {
                self.resignFirstResponder()
            }
        }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if !forward(presses, pressed: true) {
            super.pressesBegan(presses, with: event)
        }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if !forward(presses, pressed: false) {
            super.pressesEnded(presses, with: event)
        }
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        _ = forward(presses, pressed: false)
    }

    /// 只要能拿到 keyCode 就算处理掉；一个都拿不到则交回响应链
    private func forward(_ presses: Set<UIPress>, pressed: Bool) -> Bool {
        guard isActive else { return false }
        var handled = false
        for press in presses {
            guard let key = press.key else { continue }
            onKey?(key.keyCode, pressed)
            handled = true
        }
        return handled
    }
}

#endif
