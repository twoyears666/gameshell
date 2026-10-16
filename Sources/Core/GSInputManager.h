#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 外设状态变化时发出（手柄热插拔 / 键鼠上下线）
FOUNDATION_EXPORT NSNotificationName const GSInputManagerDidUpdateNotification;

/// 输入状态快照（手柄 / 键鼠）
@interface GSInputSnapshot : NSObject
@property (nonatomic, assign) NSInteger controllerCount;
@property (nonatomic, copy) NSArray<NSString *> *controllerNames;
@property (nonatomic, assign) BOOL keyboardConnected;
@property (nonatomic, assign) BOOL pointerConnected;   // 鼠标 / 触控板
@property (nonatomic, assign) BOOL hardwareInputAvailable;
- (NSString *)summaryText;
@end

@class GSInputManager;

@protocol GSInputManagerDelegate <NSObject>
- (void)inputManagerDidUpdate:(GSInputManager *)manager;
@end

/// 手柄按键转发回调：
/// identifier 直接用 GameController 的按钮字典键（"Button A" / "Left Shoulder" /
/// "Direction Pad Up" …），pressed 为按下 / 抬起。交由调用方去查键位映射。
typedef void (^GSInputButtonHandler)(NSString *identifier, BOOL pressed);

/// 手柄 + 键鼠输入的统一入口。
/// 手柄：基于 GameController 框架（GCController），支持热插拔。
/// 键鼠：在 iOS/iPadOS 上由系统把蓝牙键盘鼠标接入 UIKit（UIPress / pointer），
///       这里只做「在线探测 + 状态上报」；键盘按键转发由播放器层（UIKit）处理。
@interface GSInputManager : NSObject

@property (nonatomic, weak, nullable) id<GSInputManagerDelegate> delegate;
@property (nonatomic, copy, readonly) GSInputSnapshot *snapshot;

+ (instancetype)sharedManager NS_SWIFT_NAME(shared());

- (void)startMonitoring;
- (void)stopMonitoring;

/// 播放器层收到键盘事件后回报一次，用于统计「最近是否有键鼠输入」
- (void)reportKeyboardActivity;
- (void)reportPointerActivity;

#pragma mark - 手柄按键转发

/// 开始转发：把当前在线（含之后热插拔）手柄的每个按钮按下 / 抬起事件交给 handler。
/// 同一时刻只有一个 handler；重复调用会替换掉旧的。
- (void)beginButtonForwardingWithHandler:(GSInputButtonHandler)handler
    NS_SWIFT_NAME(beginButtonForwarding(handler:));

/// 停止转发并清除 handler（离开模拟器 / 播放器时调用）
- (void)endButtonForwarding;

@end

NS_ASSUME_NONNULL_END
