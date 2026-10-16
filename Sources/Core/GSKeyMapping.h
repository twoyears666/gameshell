//
//  GSKeyMapping.h
//  Gameshell
//
//  三端键位配置（触屏 / 键盘 / 手柄）。触屏的键位布局与可见性**按系统区分**，
//  键盘 / 手柄仍是全局一套。
//
//    · 触屏：虚拟手柄的整体缩放与透明度（全局），以及各按键簇是否显示、
//      每一簇的位置与大小（按系统分别保存）；
//    · 键盘：UIKeyboardHIDUsage（HID 键码）→ GSButton；
//    · 手柄：GCController 的按钮字典键（"Button A" / "Direction Pad Up" …）→ GSButton。
//
//  为什么要按系统分：各机器的按键分布本来就不一样 —— GBA 只要 A/B + L/R；
//  SNES 与 NDS 是 A/B/X/Y 四键；NDS 还多一个 Menu 与下屏触摸区。
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

/// 触屏按键簇：设置页里可以单独调整每一簇的位置与大小。
/// 前 5 个的 rawValue 保持不变（旧数据按 rawValue 迁移，不能错位）；
/// Menu / TouchScreen 是后加的，追加在末尾。
typedef NS_ENUM(NSInteger, GSTouchCluster) {
    GSTouchClusterDPad = 0,     // 十字键
    GSTouchClusterFace,         // A / B（SNES / NDS 上是 A / B / X / Y 四键）
    GSTouchClusterL,            // L 肩键
    GSTouchClusterR,            // R 肩键
    GSTouchClusterStartSelect,  // START / SELECT
    GSTouchClusterMenu,         // Menu（NDS：切换游戏内暂停菜单）
    GSTouchClusterTouchScreen,  // 触摸屏（NDS 下屏）
};

/// 单个按键簇的布局：归一化中心坐标（0–1，相对手柄可用区域）+ 相对默认尺寸的缩放。
/// 用归一化坐标是为了让播放器与设置页的布局编辑器共用同一套数值，换屏幕尺寸也不会错位，
/// 也方便以后做「材质包」时整套替换按键布局。
@interface GSTouchClusterLayout : NSObject <NSCopying>

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

#pragma mark - 触屏按键簇（按系统区分）

/// 某系统该有哪些按键簇（设置页遍历、播放器渲染都用它）。
/// systemIdentifier 取 GSSystemInfo.identifier（"nes" / "snes" / "gb" / "gbc" / "gba" / "nds"）。
+ (NSArray<NSNumber *> *)touchClustersForSystem:(NSString *)systemIdentifier NS_SWIFT_NAME(touchClusters(forSystem:));
/// 该系统的 A / B 簇是否要画成 A / B / X / Y 四键（SNES / NDS 为 YES）
+ (BOOL)systemUsesFourFaceKeys:(NSString *)systemIdentifier NS_SWIFT_NAME(systemUsesFourFaceKeys(_:));
/// 按键簇在某系统里的展示名（"十字键" / "A / B" / "A / B / X / Y" / "Menu" / "触摸屏" …）
+ (NSString *)displayNameForCluster:(GSTouchCluster)cluster forSystem:(NSString *)systemIdentifier NS_SWIFT_NAME(displayName(forCluster:system:));

/// 某系统里某簇当前布局；用户没自定义过时就是该系统的内置默认值（永远非空）
- (GSTouchClusterLayout *)layoutForCluster:(GSTouchCluster)cluster forSystem:(NSString *)systemIdentifier NS_SWIFT_NAME(layout(for:system:));
/// 写入某系统里某簇的布局：只改内存，不落盘；需要落盘请显式调用 -persist（拖拽过程中每帧都写盘太重）
- (void)setLayout:(GSTouchClusterLayout *)layout forCluster:(GSTouchCluster)cluster forSystem:(NSString *)systemIdentifier NS_SWIFT_NAME(setLayout(_:for:system:));
/// 该系统有没有被用户改过布局（设置页显示「已自定义」用）
- (BOOL)hasCustomTouchLayoutForSystem:(NSString *)systemIdentifier NS_SWIFT_NAME(hasCustomTouchLayout(forSystem:));
/// 把某系统的按键簇布局与可见性恢复成内置默认（并落盘）
- (void)resetTouchLayoutsForSystem:(NSString *)systemIdentifier NS_SWIFT_NAME(resetTouchLayouts(forSystem:));

/// 某系统里某簇当前是否显示（没被显式改过时，属于该系统按键簇集合的默认显示）
- (BOOL)isClusterVisible:(GSTouchCluster)cluster forSystem:(NSString *)systemIdentifier NS_SWIFT_NAME(isClusterVisible(_:forSystem:));
- (void)setVisible:(BOOL)visible forCluster:(GSTouchCluster)cluster forSystem:(NSString *)systemIdentifier NS_SWIFT_NAME(setVisible(_:forCluster:system:));

#pragma mark - 键盘（usage = UIKeyboardHIDUsage 的 rawValue）

/// 该 HID 键码绑到的按钮；没绑定返回 0
- (GSButton)buttonForKeyboardUsage:(NSInteger)usage;
- (void)setKeyboardUsage:(NSInteger)usage forButton:(GSButton)button;
- (void)clearKeyboardBindingForButton:(GSButton)button;
/// 该按钮当前绑的键，显示用（"Z" / "↑" …）；没绑返回 nil
- (nullable NSString *)keyboardBindingLabelForButton:(GSButton)button;

#pragma mark - 手柄（identifier = GCController 的按钮字典键）

/// 该手柄标识绑到的按钮；没绑定返回 0
- (GSButton)buttonForGamepadIdentifier:(NSString *)identifier;
- (void)setGamepadIdentifier:(NSString *)identifier forButton:(GSButton)button;
- (void)clearGamepadBindingForButton:(GSButton)button;
/// 该按钮当前绑的手柄键，显示用（"A" / "L1" …）；没绑返回 nil
- (nullable NSString *)gamepadBindingLabelForButton:(GSButton)button;

#pragma mark - 持久化

- (void)persist;
- (void)resetToDefaults;

/// 参与配置的按钮全集（设置页列表用）
+ (NSArray<NSNumber *> *)configurableButtons;
/// 按钮的展示名（"A 键" / "方向键上" …）
+ (NSString *)displayNameForButton:(GSButton)button;

@end

NS_ASSUME_NONNULL_END
