//
//  GSKeyMapping.h
//  Gameshell
//
//  三端键位配置（触屏 / 键盘 / 手柄），**三端都按系统区分**。
//
//    · 触屏：虚拟手柄的整体缩放与透明度（全局），以及各按键是否显示、
//      每个按键各自的位置与大小（按系统分别保存；按键之间互不绑定）；
//    · 键盘：UIKeyboardHIDUsage（HID 键码）→ GSButton（按系统分别保存）；
//    · 手柄：GCController 的按钮字典键（"Button A" / "Direction Pad Up" …）→ GSButton（按系统分别保存）。
//
//  为什么要按系统分：各机器的按键分布本来就不一样 —— GBA 只要 A/B + L/R；
//  SNES 与 NDS 是 A/B/X/Y 四键；NDS 还多一个 Menu 与下屏触摸区；
//  8 位机（NES / GB / GBC）根本没有 L/R/ X/Y 这些键，键盘 / 手柄自然也不该共用一套。
//  默认数值参照 Delta 的各套皮肤（Standard GBA / Standard DS）。
//
//  配置持久化在沙盒 `Documents/keymap.json`；读不到就回落到内置默认值，
//  读到旧的「全局一套」格式时自动迁移到按系统分桶的新格式。
//  这里只管「配置 + 查询」，按键的实际转发在 GSInputManager 与播放器层。
//

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import "GSEmulator.h"

NS_ASSUME_NONNULL_BEGIN

/// 触屏上可独立摆放的元素 —— **每个按键各自独立**调位置与大小，互不绑定。
/// 十字键与 NDS 下屏触摸区是「整体元素」，不拆；
/// 其余按键（A / B / X / Y / L / R / START / SELECT / MENU）各自一条，
/// 不再有「A / B」「A / B / X / Y」「START / SELECT」这种成组的簇。
typedef NS_ENUM(NSInteger, GSTouchElement) {
    GSTouchElementDPad = 0,     // 十字键（整体，不拆四个方向）
    GSTouchElementA,            // A 键
    GSTouchElementB,            // B 键
    GSTouchElementX,            // X 键（仅 SNES / NDS）
    GSTouchElementY,            // Y 键（仅 SNES / NDS）
    GSTouchElementL,            // L 肩键
    GSTouchElementR,            // R 肩键
    GSTouchElementStart,        // START
    GSTouchElementSelect,       // SELECT
    GSTouchElementMenu,         // Menu（NDS：切换游戏内暂停菜单）
    GSTouchElementTouchScreen,  // 触摸屏（NDS 下屏，整体）
};

/// 单个元素的布局：归一化中心坐标（0–1，相对手柄可用区域）+ 相对默认尺寸的缩放。
/// 用归一化坐标是为了让播放器与设置页的布局编辑器共用同一套数值，换屏幕尺寸也不会错位，
/// 也方便以后做「材质包」时整套替换按键布局。
@interface GSTouchElementLayout : NSObject <NSCopying>

/// 中心点横坐标（0 = 最左，1 = 最右）
@property (nonatomic, assign) CGFloat x;
/// 中心点纵坐标（0 = 最上，1 = 最下）
@property (nonatomic, assign) CGFloat y;
/// 相对默认尺寸的缩放（0.6 – 1.6，默认 1.0）
@property (nonatomic, assign) CGFloat scale;

+ (instancetype)layoutWithX:(CGFloat)x y:(CGFloat)y scale:(CGFloat)scale NS_SWIFT_NAME(make(x:y:scale:));

@end

@interface GSKeyMapping : NSObject

+ (instancetype)sharedMapping NS_SWIFT_NAME(shared());

#pragma mark - 触屏整体（全局，不分系统）

/// 虚拟手柄整体缩放（0.6 – 1.4，默认 1.0）
@property (nonatomic, assign) CGFloat touchScale;
/// 虚拟手柄整体透明度（0.3 – 1.0，默认 0.92）
@property (nonatomic, assign) CGFloat touchOpacity;

#pragma mark - 触屏元素（按系统区分）

/// 某系统该有哪些触屏元素（设置页遍历、播放器渲染都用它）。
/// systemIdentifier 取 GSSystemInfo.identifier（"nes" / "snes" / "gb" / "gbc" / "gba" / "nds"）。
+ (NSArray<NSNumber *> *)touchElementsForSystem:(NSString *)systemIdentifier NS_SWIFT_NAME(touchElements(forSystem:));
/// 触屏元素在某系统里的展示名（"十字键" / "A 键" / "START" / "Menu" / "触摸屏" …）
+ (NSString *)displayNameForElement:(GSTouchElement)element NS_SWIFT_NAME(displayName(forElement:));

/// 某系统里某元素当前布局；用户没自定义过时就是该系统的内置默认值（永远非空）
- (GSTouchElementLayout *)layoutForElement:(GSTouchElement)element forSystem:(NSString *)systemIdentifier NS_SWIFT_NAME(layout(for:system:));
/// 写入某系统里某元素的布局：只改内存，不落盘；需要落盘请显式调用 -persist（拖拽过程中每帧都写盘太重）
- (void)setLayout:(GSTouchElementLayout *)layout forElement:(GSTouchElement)element forSystem:(NSString *)systemIdentifier NS_SWIFT_NAME(setLayout(_:for:system:));
/// 把某个大小（缩放）一次性应用到该系统的所有按键（触摸屏是屏、不是按键，不动它），并落盘
- (void)applyScale:(CGFloat)scale toAllElementsForSystem:(NSString *)systemIdentifier NS_SWIFT_NAME(applyScale(_:toAllElementsForSystem:));
/// 该系统有没有被用户改过布局（设置页显示「已自定义」用）
- (BOOL)hasCustomTouchLayoutForSystem:(NSString *)systemIdentifier NS_SWIFT_NAME(hasCustomTouchLayout(forSystem:));
/// 把某系统的元素布局与可见性恢复成内置默认（并落盘）
- (void)resetTouchLayoutsForSystem:(NSString *)systemIdentifier NS_SWIFT_NAME(resetTouchLayouts(forSystem:));

/// 某系统里某元素当前是否显示（没被显式改过时，属于该系统元素集合的默认显示）
- (BOOL)isElementVisible:(GSTouchElement)element forSystem:(NSString *)systemIdentifier NS_SWIFT_NAME(isElementVisible(_:forSystem:));
- (void)setVisible:(BOOL)visible forElement:(GSTouchElement)element forSystem:(NSString *)systemIdentifier NS_SWIFT_NAME(setVisible(_:forElement:system:));

#pragma mark - 键盘（usage = UIKeyboardHIDUsage 的 rawValue；按系统分桶）

/// 该 HID 键码在某系统里绑到的按钮；没绑定返回 0
- (GSButton)buttonForKeyboardUsage:(NSInteger)usage forSystem:(NSString *)systemIdentifier NS_SWIFT_NAME(button(keyboardUsage:system:));
/// 给某系统里某按钮绑键（同一系统内一个键只绑一个按钮）
- (void)setKeyboardUsage:(NSInteger)usage forButton:(GSButton)button forSystem:(NSString *)systemIdentifier NS_SWIFT_NAME(setKeyboardUsage(_:for:system:));
/// 清掉某系统里某按钮的键盘绑定（此后该按钮在此系统里就是「未绑定」）
- (void)clearKeyboardBindingForButton:(GSButton)button forSystem:(NSString *)systemIdentifier NS_SWIFT_NAME(clearKeyboardBinding(for:system:));
/// 某系统里该按钮当前绑的键，显示用（"Z" / "↑" …）；没绑返回 nil
- (nullable NSString *)keyboardBindingLabelForButton:(GSButton)button forSystem:(NSString *)systemIdentifier NS_SWIFT_NAME(keyboardBindingLabel(for:system:));
/// 该系统的键盘绑定有没有被用户改过（设置页显示「已自定义」用）
- (BOOL)hasCustomKeyboardForSystem:(NSString *)systemIdentifier NS_SWIFT_NAME(hasCustomKeyboard(forSystem:));
/// 把某系统的键盘绑定恢复成内置默认
- (void)resetKeyboardForSystem:(NSString *)systemIdentifier NS_SWIFT_NAME(resetKeyboard(forSystem:));

#pragma mark - 手柄（identifier = GCController 的按钮字典键；按系统分桶）

/// 该手柄标识在某系统里绑到的按钮；没绑定返回 0
- (GSButton)buttonForGamepadIdentifier:(NSString *)identifier forSystem:(NSString *)systemIdentifier NS_SWIFT_NAME(button(gamepadIdentifier:system:));
/// 给某系统里某按钮绑手柄键（同一系统内一个手柄键只绑一个按钮）
- (void)setGamepadIdentifier:(NSString *)identifier forButton:(GSButton)button forSystem:(NSString *)systemIdentifier NS_SWIFT_NAME(setGamepadIdentifier(_:for:system:));
/// 清掉某系统里某按钮的手柄绑定
- (void)clearGamepadBindingForButton:(GSButton)button forSystem:(NSString *)systemIdentifier NS_SWIFT_NAME(clearGamepadBinding(for:system:));
/// 某系统里该按钮当前绑的手柄键，显示用（"A" / "L1" …）；没绑返回 nil
- (nullable NSString *)gamepadBindingLabelForButton:(GSButton)button forSystem:(NSString *)systemIdentifier NS_SWIFT_NAME(gamepadBindingLabel(for:system:));
/// 该系统的手柄绑定有没有被用户改过（设置页显示「已自定义」用）
- (BOOL)hasCustomGamepadForSystem:(NSString *)systemIdentifier NS_SWIFT_NAME(hasCustomGamepad(forSystem:));
/// 把某系统的手柄绑定恢复成内置默认
- (void)resetGamepadForSystem:(NSString *)systemIdentifier NS_SWIFT_NAME(resetGamepad(forSystem:));

#pragma mark - 持久化

- (void)persist;
- (void)resetToDefaults;

/// 参与配置的按钮全集（设置页列表用）
+ (NSArray<NSNumber *> *)configurableButtons;
/// 按钮的展示名（"A 键" / "方向键上" …）
+ (NSString *)displayNameForButton:(GSButton)button;

@end

NS_ASSUME_NONNULL_END
