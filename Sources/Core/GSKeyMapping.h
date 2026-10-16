//
//  GSKeyMapping.h
//  Gameshell
//
//  三端键位配置（触屏 / 键盘 / 手柄），全局一套，不分系统。
//
//    · 触屏：虚拟手柄的缩放、透明度，以及各按键簇是否显示；
//    · 键盘：UIKeyboardHIDUsage（HID 键码）→ GSButton；
//    · 手柄：GCController 的按钮字典键（"Button A" / "Direction Pad Up" …）→ GSButton。
//
//  配置持久化在沙盒 `Documents/keymap.json`；读不到就回落到内置默认值。
//  这里只管「配置 + 查询」，按键的实际转发在 GSInputManager 与播放器层。
//

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import "GSEmulator.h"

NS_ASSUME_NONNULL_BEGIN

/// 触屏按键簇：设置页里可以单独调整每一簇的位置与大小。
typedef NS_ENUM(NSInteger, GSTouchCluster) {
    GSTouchClusterDPad = 0,     // 十字键
    GSTouchClusterFace,         // A / B
    GSTouchClusterL,            // L 肩键
    GSTouchClusterR,            // R 肩键
    GSTouchClusterStartSelect,  // START / SELECT
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

+ (instancetype)sharedMapping NS_SWIFT_NAME(shared);

#pragma mark - 触屏布局

/// 虚拟手柄整体缩放（0.6 – 1.4，默认 1.0）
@property (nonatomic, assign) CGFloat touchScale;
/// 虚拟手柄整体透明度（0.3 – 1.0，默认 0.92）
@property (nonatomic, assign) CGFloat touchOpacity;
@property (nonatomic, assign) BOOL touchShowDPad;
@property (nonatomic, assign) BOOL touchShowFace;
@property (nonatomic, assign) BOOL touchShowShoulders;
@property (nonatomic, assign) BOOL touchShowStartSelect;

#pragma mark - 触屏按键簇布局（位置 + 大小，仅设置页里可改）

/// 全部按键簇（设置页遍历用）
+ (NSArray<NSNumber *> *)touchClusters;
/// 按键簇的展示名（"十字键" / "A / B" …）
+ (NSString *)displayNameForCluster:(GSTouchCluster)cluster NS_SWIFT_NAME(displayName(forCluster:));

/// 某簇当前布局；用户没自定义过时就是内置默认值（永远非空）
- (GSTouchClusterLayout *)layoutForCluster:(GSTouchCluster)cluster NS_SWIFT_NAME(layout(for:));
/// 写入某簇布局：只改内存，不落盘；需要落盘请显式调用 -persist（拖拽过程中每帧都写盘太重）
- (void)setLayout:(GSTouchClusterLayout *)layout forCluster:(GSTouchCluster)cluster NS_SWIFT_NAME(setLayout(_:for:));
/// 有没有被用户改过（设置页显示「已自定义」用）
- (BOOL)hasCustomTouchLayout;
/// 把全部按键簇布局恢复成内置默认（并落盘）
- (void)resetTouchLayouts;

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
