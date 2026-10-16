//
//  EmulatorInputCoordinator.swift
//  Gameshell
//
//  模拟器里的按键汇总：触屏 + 硬件键盘 + 手柄 → 一个 GSButton 位掩码 → 核心。
//
//  三端各按各的键位表（GSKeyMapping）翻译成 GSButton：
//    · 触屏：虚拟手柄直接给掩码；
//    · 键盘：UIKeyboardHIDUsage 原始值 → 按钮；
//    · 手柄：GameController 的按钮字典键 → 按钮（由 GSInputManager 转发过来）。
//  三路按下状态各自记录、最后合并；抬起只清自己那一路，互不干扰。
//

import SwiftUI

#if os(iOS)
import UIKit

final class EmulatorInputCoordinator: ObservableObject {

    private weak var session: GSEmulatorSession?
    private var mapping: GSKeyMapping?

    private var touchMask: GSButton = []
    private var keyboardMask: GSButton = []
    private var gamepadMask: GSButton = []
    private var forwarding = false

    /// 进入模拟器时挂上会话与键位表，并开始转发手柄按键
    func attach(session: GSEmulatorSession?, mapping: GSKeyMapping) {
        self.session = session
        self.mapping = mapping

        guard !forwarding else { return }
        forwarding = true
        GSInputManager.shared().beginButtonForwarding { [weak self] identifier, pressed in
            DispatchQueue.main.async { self?.handleGamepad(identifier, pressed: pressed) }
        }
    }

    /// 离开模拟器
    func detach() {
        if forwarding {
            GSInputManager.shared().endButtonForwarding()
            forwarding = false
        }
        session = nil
        mapping = nil
        touchMask = []
        keyboardMask = []
        gamepadMask = []
    }

    /// 触屏虚拟手柄给的新掩码
    func setTouchMask(_ mask: GSButton) {
        touchMask = mask
        push()
    }

    /// 硬件键盘的按下 / 抬起
    func handleKeyboard(_ usage: UIKeyboardHIDUsage, pressed: Bool) {
        guard let mapping else { return }
        let button = mapping.buttonForKeyboardUsage(usage.rawValue)
        guard button.rawValue != 0 else { return }

        if pressed {
            keyboardMask.formUnion(button)
        } else {
            keyboardMask.subtract(button)
        }
        push()
    }

    /// 手柄按键（identifier 是 GCController 的按钮字典键）
    private func handleGamepad(_ identifier: String, pressed: Bool) {
        guard let mapping else { return }
        let button = mapping.buttonForGamepadIdentifier(identifier)
        guard button.rawValue != 0 else { return }

        if pressed {
            gamepadMask.formUnion(button)
        } else {
            gamepadMask.subtract(button)
        }
        push()
    }

    /// 合并三路按下状态交给核心（setButtonMask 线程安全，只写待生效掩码）
    private func push() {
        session?.setButtonMask(touchMask.union(keyboardMask).union(gamepadMask))
    }
}

#endif
