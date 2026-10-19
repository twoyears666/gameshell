//
//  GSEmulator.h
//  Gameshell
//
//  模拟器宿主层（Objective-C）。
//
//  为什么是 Objective-C：
//  1) Wii / 3DS / Wii U 的模拟需要 JIT（MAP_JIT + 可写可执行内存 + 运行时生成的代码），
//     这条链路依赖 pthread_jit_write_protect_np / mmap 等底层调用，语言必须是 C/ObjC；
//  2) 核心（mGBA 等）本身就是 C 库，用 ObjC 直接对接它的 C API 最省事。
//
//  核心一律静态链接进主二进制：iOS 15 + A12 起，系统封禁了
//  dynamic-codesigning 与 com.apple.private.cs.debugger，运行时 dlopen 未签名动态库
//  已经不可行（RetroArch 那种「外挂 core dylib」的做法在 TrollStore 上也不成立）。
//

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import "GSSystem.h"
#import "GSROMLibrary.h"

NS_ASSUME_NONNULL_BEGIN

/// 统一的按键位定义。
/// 刻意与 mGBA 的 GBAKey / GBKey 位序一致：
/// A=bit0 B=bit1 SELECT=bit2 START=bit3 RIGHT=bit4 LEFT=bit5 UP=bit6 DOWN=bit7 R=bit8 L=bit9
typedef NS_OPTIONS(uint32_t, GSButton) {
    GSButtonA      = 1u << 0,
    GSButtonB      = 1u << 1,
    GSButtonSelect = 1u << 2,
    GSButtonStart  = 1u << 3,
    GSButtonRight  = 1u << 4,
    GSButtonLeft   = 1u << 5,
    GSButtonUp     = 1u << 6,
    GSButtonDown   = 1u << 7,
    GSButtonR      = 1u << 8,
    GSButtonL      = 1u << 9,

    /// 8 / 16 位机的常用别名（A/B 与 GBA 一致，R/L 在 NES/SNES 上映射到 X/Y 之外的肩键）
    GSButtonX      = 1u << 10,
    GSButtonY      = 1u << 11,

    /// New 3DS 等新增按键（宿主侧定义；下发时各自翻成 retro 的对应 joypad id）：
    /// ZL / ZR 是 New 3DS 才有的后肩键，HOME 是 3DS 的系统键。
    GSButtonZL     = 1u << 12,
    GSButtonZR     = 1u << 13,
    GSButtonHome   = 1u << 14,
};

/// JIT 状态（Wii / 3DS / Wii U 依赖它）
typedef NS_ENUM(NSInteger, GSJITStatus) {
    GSJITStatusUnknown = 0,
    /// 当前进程无法分配可执行内存（未开 JIT）
    GSJITStatusUnavailable,
    /// 已经拿到可执行内存，可以跑需要 JIT 的核心
    GSJITStatusEnabled,
};

#pragma mark - JIT

/// JIT 探测与开启。
@interface GSJIT : NSObject

/// 真实探测：直接在进程内尝试 mmap(MAP_JIT)，成功即视为可用。
+ (GSJITStatus)probeStatus;

/// 设备是否装了 TrollStore（靠探测 TrollStore 的 URL scheme）
+ (BOOL)isTrollStoreAvailable;

/// TrollStore 上用来给指定 bundle id 打开 JIT 的 URL：
/// apple-magnifier://enable-jit?bundle-id=<bundleID>
/// bundle id 拼不出合法 URL 时返回 nil（Swift 侧就是这么判空的）
+ (nullable NSURL *)trollStoreEnableJITURLForBundleID:(NSString *)bundleID;

/// 申请一块可读可写可执行的 JIT 内存；失败返回 NULL（未开 JIT 时就是这样）。
+ (nullable void *)allocateExecutableMemoryWithSize:(size_t)size;

/// 释放由上面的方法申请的内存
+ (void)releaseExecutableMemory:(void *)pointer size:(size_t)size;

@end

#pragma mark - 核心协议

@protocol GSEmulatorCore;

/// 核心向宿主回报的每帧产物。像素固定为 RGBA8888，便于统一成 CGImage。
@protocol GSEmulatorCoreDelegate <NSObject>
- (void)coreDidRenderFrameRGBA8888:(const uint8_t *)pixels
                             width:(size_t)width
                            height:(size_t)height
                            stride:(size_t)stride;
- (void)coreDidProduceAudioSamples:(const int16_t *)samples
                             count:(size_t)count;   // 交错立体声，count = int16 采样总数（L/R 交替，偶数才有完整帧）
@end

/// 一个可玩的核心。核心自己负责把 ROM 载入、把颜色转成 RGBA8888、把音频交出来。
@protocol GSEmulatorCore <NSObject>

@property (nonatomic, weak, nullable) id<GSEmulatorCoreDelegate> delegate;
@property (nonatomic, copy, readonly) NSString *coreName;
@property (nonatomic, copy, readonly) NSString *coreVersion;
/// 音频采样率（载入 ROM 后才有效）
@property (nonatomic, assign, readonly) double sampleRate;
/// 每秒跑多少帧（用于宿主侧的帧节奏控制）
@property (nonatomic, assign, readonly) double framesPerSecond;
/// 视频输出尺寸（载入 ROM 后才有效）
@property (nonatomic, assign, readonly) size_t videoWidth;
@property (nonatomic, assign, readonly) size_t videoHeight;
/// 该平台是否必须开 JIT 才能启动（目前只有 Wii / Wii U 为 YES；
/// 3DS 与 NDS 都是双模式：有 JIT 就用 JIT，没有就降级解释器，不拒绝启动）
@property (nonatomic, assign, readonly) BOOL requiresJIT;

/// 载入 ROM；savePath 是电池存档（.sav）的路径，由核心自行读写
- (BOOL)loadROMAtPath:(NSString *)path savePath:(NSString *)savePath error:(NSError **)error;
- (void)unloadROM;

/// 跑一帧，并通过 delegate 回报画面 / 声音
- (void)runFrame;
/// 推进按键位掩码（GSButton）
- (void)setButtonMask:(GSButton)mask;

- (void)shutdown;

@optional
/// 当前实际生效的 CPU 后端描述（如 "dynarmic JIT" / "FastInterp 解释器"）。
/// 只有「JIT 与解释器双模式」的核心才实现它，宿主用 respondsToSelector: 判定，
/// 界面据此如实标注当前跑在哪一档。
@property (nonatomic, copy, readonly, nullable) NSString *cpuBackendDescription;

/// 触摸屏（NDS 下屏等）。point 是触摸区内的归一化坐标（0–1，原点在触摸区左上角），
/// active 表示手指当前是否按下。只有支持触摸的核心才实现它。
- (void)setTouchPoint:(CGPoint)point active:(BOOL)active NS_SWIFT_NAME(setTouchPoint(_:active:));

/// 即时存档（可选）。只有支持存档的核心才实现这两个方法；宿主用
/// respondsToSelector: 判定支持与否，不支持就如实告诉用户「这个核心不支持」。
/// copySaveState 返回一份自包含的状态数据（自带尺寸信息，可直接落盘）；
/// restoreSaveState: 只接受同一核心、同一版本产生的数据。
@optional
- (nullable NSData *)copySaveState NS_SWIFT_NAME(copySaveState());
- (BOOL)restoreSaveState:(NSData *)data NS_SWIFT_NAME(restoreSaveState(_:));

@end

#pragma mark - 会话

/// 一次「打开一个 ROM」的会话：宿主 + 核心实例 + 帧循环。
@interface GSEmulatorSession : NSObject

- (instancetype)initWithROM:(GSROM *)rom;

@property (nonatomic, copy, readonly) GSROM *rom;
@property (nonatomic, copy, readonly) GSSystemInfo *systemInfo;
@property (nonatomic, strong, readonly, nullable) id<GSEmulatorCore> core;

/// 核心是否可用；不可用时 unavailableReason 说明原因（诚实标注，不假装能玩）
@property (nonatomic, assign, readonly) BOOL isAvailable;
@property (nonatomic, copy, readonly, nullable) NSString *unavailableReason;

@property (nonatomic, assign) BOOL paused;
/// 该系统的核心是否必须开 JIT
@property (nonatomic, assign, readonly) BOOL requiresJIT;
/// 当前进程的 JIT 状态（真实探测）
@property (nonatomic, assign, readonly) GSJITStatus jitStatus;
/// 需要 JIT 但没开时给用户的提示文案；其它情况为 nil
@property (nonatomic, copy, readonly, nullable) NSString *jitWarning;
/// 当前实际跑在哪一档 CPU 后端，由核心如实回报（核心没有这个能力时为 nil）
@property (nonatomic, copy, readonly, nullable) NSString *cpuBackendDescription;

- (BOOL)startWithError:(NSError **)error;
- (void)stop;

/// 把最新一帧取成 CGImage；还没有帧时返回 NULL
- (nullable CGImageRef)copyLatestFrameImage CF_RETURNS_RETAINED;

/// 设置按键状态
- (void)setButtonMask:(GSButton)mask;

/// 触摸屏（NDS 下屏等）：point 是触摸区内的归一化坐标（0–1），active 表示是否按下。
/// 不支持触摸的核心会忽略；只写「待生效」状态，真正下发在模拟线程里（线程安全）。
- (void)setTouchPoint:(CGPoint)point active:(BOOL)active NS_SWIFT_NAME(setTouchPoint(_:active:));

// MARK: - 速度 / 即时存档

/// 模拟速度倍率，默认 1.0，取值会被夹紧到 0.25–4.0。
/// 说明：核心每次仍只跑「一帧」，宿主是靠改帧节奏实现变速的 ——
/// 倍率 > 1 时每秒跑更多帧（游戏变快），同时静音（见 GSEmulator.m 的注释）。
@property (nonatomic, assign) double emulationSpeed;

/// 当前核心是否支持即时存档（核心实现了存档接口且已经载入 ROM）
@property (nonatomic, assign, readonly) BOOL supportsSaveStates;

/// 取一份即时存档。主线程调用；内部把请求贴给模拟线程执行、等它做完再返回（线程安全）。
/// 不支持、未启动或失败时返回 nil。
- (nullable NSData *)copySnapshot;

/// 恢复一份即时存档。同上走模拟线程；成功返回 YES。
- (BOOL)restoreSnapshot:(NSData *)data;

// MARK: - 音频（由 Swift 侧的 AVAudioEngine 拉取）

@property (nonatomic, assign, readonly) double audioSampleRate;
- (size_t)readAudioInto:(int16_t *)buffer count:(size_t)count;

/// 每个系统当前是否已经有可用的核心实现（供 UI 标注）
+ (BOOL)hasCoreForSystem:(GSSystem)system;
+ (nullable NSString *)coreNameForSystem:(GSSystem)system;

@end

NS_ASSUME_NONNULL_END
