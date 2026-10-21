//
//  GSRAMLimit.h
//  Gameshell
//
//  进程内存上限：
//   · TrollStore 版（tipa）带 com.apple.private.memorystatus，启动时自动调用
//     memorystatus_control，把 jetsam 上限提到物理内存的 3/4 —— 3DS / NDS 核心
//     在高负载下不会被系统提前杀掉；
//   · 普通 IPA 版带公开的 com.apple.developer.kernel.increased-memory-limit，
//     由系统在启动时按机型放宽额度；设置页通过本类如实显示探测结果。
//
//  所有数值都来自真实探测，取不到就返回 0 / Unavailable，不假装已生效。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 内存上限状态
typedef NS_ENUM(NSInteger, GSRAMLimitStatus) {
    /// 还没探测过
    GSRAMLimitStatusUnknown = 0,
    /// 运行时提升不可用（当前安装方式没有授予内存权限）
    GSRAMLimitStatusUnavailable,
    /// 已把进程上限提升到 appliedLimitBytes
    GSRAMLimitStatusRaised,
};

@interface GSRAMLimit : NSObject

/// 真实探测并尝试提升；幂等，启动时自动调用一次，设置页也可以手动再触发
+ (GSRAMLimitStatus)applyIfNeeded;

/// 最近一次探测 / 提升的结果
+ (GSRAMLimitStatus)status;

/// 已提升到的上限（字节）；没有提升时返回 0
+ (unsigned long long)appliedLimitBytes;

/// 进程还能再分配多少内存（字节）；进程没有上限或取不到时为 0
+ (unsigned long long)availableMemoryBytes;

/// 设备物理内存（字节）
+ (unsigned long long)physicalMemoryBytes;

@end

NS_ASSUME_NONNULL_END
