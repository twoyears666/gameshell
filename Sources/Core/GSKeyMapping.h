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
