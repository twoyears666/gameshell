import SwiftUI
import Foundation

#if canImport(UIKit)
import UIKit
#endif

/// 全局设计令牌（Design Tokens）。
/// 所有颜色 / 圆角 / 间距 / 字号都集中在这里，UI 层一律引用 Theme.*，
/// 便于后续做「主题包」替换，不在视图里硬编码样式。
enum Theme {

    // MARK: - 颜色

    enum Color {
        /// 页面最底层背景（近黑）
        static let background = SwiftUI.Color(hex: 0x0B0B10)
        /// 次级背景（分组 / 弹层遮罩底）
        static let backgroundElevated = SwiftUI.Color(hex: 0x121216)
        /// 卡片 / 列表行背景
        static let surface = SwiftUI.Color(hex: 0x1B1B20)
        /// 卡片内更深的分区
        static let surfaceAlt = SwiftUI.Color(hex: 0x232329)
        /// 描边
        static let border = SwiftUI.Color(hex: 0x2A2A30)
        /// 主文本
        static let textPrimary = SwiftUI.Color.white
        /// 次文本
        static let textSecondary = SwiftUI.Color(hex: 0x9AA0A6)
        /// 更弱的提示文本
        static let textTertiary = SwiftUI.Color(hex: 0x6B7075)

        /// 主强调色（橙）——「启动 / 畅玩」按钮
        static let accent = SwiftUI.Color(hex: 0xFF7A18)
        static let accentPressed = SwiftUI.Color(hex: 0xE06A0F)
        /// 次强调（紫），用于宣传标题渐变
        static let accentSecondary = SwiftUI.Color(hex: 0x9B5CFF)
        static let accentTertiary = SwiftUI.Color(hex: 0xFF4FA3)

        /// 评分徽章底
        static let ratingBackground = SwiftUI.Color(hex: 0x000000).opacity(0.55)

        /// 顶部栏渐变
        static let headerGradient = LinearGradient(
            colors: [SwiftUI.Color(hex: 0x17171D), SwiftUI.Color(hex: 0x0B0B10)],
            startPoint: .top,
            endPoint: .bottom
        )

        /// 宣传标题渐变（紫 → 粉）
        static let marketingGradient = LinearGradient(
            colors: [accentSecondary, accentTertiary],
            startPoint: .leading,
            endPoint: .trailing
        )

        /// 封面图底部渐隐遮罩
        static let coverScrim = LinearGradient(
            colors: [.clear, SwiftUI.Color.black.opacity(0.75)],
            startPoint: .center,
            endPoint: .bottom
        )
    }

    // MARK: - 圆角

    enum Radius {
        static let chip: CGFloat = 8
        static let control: CGFloat = 10
        static let card: CGFloat = 14
        static let hero: CGFloat = 18
        static let pill: CGFloat = 999
    }

    // MARK: - 间距

    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        /// 内容区左右边距 ≈ 3% 窗口宽度
        static let screenHorizontalRatio: CGFloat = 0.03
    }

    // MARK: - 字号

    enum Font {
        static let display = SwiftUI.Font.system(size: 28, weight: .bold)
        static let title = SwiftUI.Font.system(size: 22, weight: .bold)
        static let section = SwiftUI.Font.system(size: 18, weight: .semibold)
        static let cardTitle = SwiftUI.Font.system(size: 16, weight: .semibold)
        static let body = SwiftUI.Font.system(size: 15, weight: .regular)
        static let caption = SwiftUI.Font.system(size: 13, weight: .regular)
        static let chip = SwiftUI.Font.system(size: 12, weight: .medium)
        static let rating = SwiftUI.Font.system(size: 13, weight: .bold)
        static let button = SwiftUI.Font.system(size: 17, weight: .semibold)
    }

    // MARK: - 动画

    enum Motion {
        static let quick = Animation.easeOut(duration: 0.18)
        static let standard = Animation.easeInOut(duration: 0.26)
        static let spring = Animation.spring(response: 0.35, dampingFraction: 0.82)
    }

    // MARK: - 布局断点

    /// 判断当前是否横屏（手持 / 主机布局）
    static func isLandscape(_ size: CGSize) -> Bool {
        size.width >= size.height
    }

    /// 内容区左右边距
    static func horizontalPadding(for width: CGFloat) -> CGFloat {
        max(Spacing.md, width * Spacing.screenHorizontalRatio)
    }

    /// 按屏幕宽度决定网格列数（手机 1–2 列 / iPad·mac 多列 Bento）
    static func gridColumns(for width: CGFloat) -> Int {
        switch width {
        case ..<520: return 1
        case ..<900: return 2
        case ..<1300: return 3
        default: return 4
        }
    }
}

// MARK: - 便捷扩展

extension SwiftUI.Color {
    /// 从 0xRRGGBB 构建颜色
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }

    /// 从 "#RRGGBB" 字符串构建颜色，非法输入返回 nil
    init?(hexString: String) {
        var value = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let hex = UInt32(value, radix: 16) else { return nil }
        self.init(hex: hex)
    }
}
