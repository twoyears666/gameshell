//
//  LibraryItem.swift
//  Gameshell
//
//  游戏库里的一条内容：用户添加的 URL 条目（GSGame），或导入的模拟器 ROM（GSROM）。
//  两者在界面上混排（同一排方块卡），靠这个枚举统一，UI 只认 LibraryItem。
//

import Foundation

enum LibraryItem: Identifiable {

    case game(GSGame)
    case rom(GSROM)

    /// 界面里的唯一标识：加前缀区分 URL 条目与 ROM（两者 id 空间不同）
    var id: String {
        switch self {
        case .game(let game): return "game:" + game.identifier
        case .rom(let rom): return "rom:" + rom.identifier
        }
    }

    /// 「最近游玩」记录里存的 identifier（GSPlayHistory 只存这个 + 种类）
    var historyIdentifier: String {
        switch self {
        case .game(let game): return game.identifier
        case .rom(let rom): return rom.identifier
        }
    }

    var title: String {
        switch self {
        case .game(let game): return game.name
        case .rom(let rom): return rom.name
        }
    }

    var subtitle: String {
        switch self {
        case .game(let game):
            return game.platform
        case .rom(let rom):
            let info = GSSystemRegistry.info(for: rom.system)
            return isPlayable ? info.shortName : "\(info.shortName) · 核心未接入"
        }
    }

    /// 无封面时的短文字（ROM 用系统短名当徽标）
    var badgeText: String? {
        switch self {
        case .game: return nil
        case .rom(let rom): return GSSystemRegistry.info(for: rom.system).shortName
        }
    }

    /// 清单条目的强调色；ROM 没有
    var accentHex: String? {
        switch self {
        case .game(let game): return game.accentHex
        case .rom: return nil
        }
    }

    var supportsController: Bool {
        switch self {
        case .game(let game): return game.controllerSupport
        case .rom: return true
        }
    }

    /// 能不能启动（核心未接入的 ROM 只能待在库里，点开会有如实提示）
    var isPlayable: Bool {
        switch self {
        case .game: return true
        case .rom(let rom): return GSEmulatorSession.hasCore(for: rom.system)
        }
    }
}
