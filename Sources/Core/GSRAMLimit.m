//
//  GSRAMLimit.m
//  Gameshell
//

#import "GSRAMLimit.h"
#import "GSLog.h"

#import <dlfcn.h>
#import <os/proc.h>
#import <unistd.h>

/// 私有接口 memorystatus_control 的函数签名：
/// 第 3 个参数 flags 承载上限值（字节），buffer / size 传 NULL / 0 即可。
typedef int (*GSMemoryStatusControlFunction)(uint32_t command, int32_t pid,
                                            uint32_t flags, void *buffer, size_t size);

/// 命令号取自 XNU 的 private/memorystatus.h：
/// MEMORYSTATUS_CMD_SET_JETSAM_TASK_LIMIT —— 活动 / 非活动内存上限一起设成同一个值。
static const uint32_t GSMemoryStatusCommandSetTaskLimit = 6;

/// memorystatus_control 的 flags 只有 32 位，所以上限封顶 3.75GB
static const unsigned long long GSRAMLimitMaximumBytes = 3840ull * 1024 * 1024;
/// 再小的设备也给核心留出至少 512MB，避免把上限设得比现状还低
static const unsigned long long GSRAMLimitMinimumBytes = 512ull * 1024 * 1024;

static GSRAMLimitStatus GSRecordedStatus = GSRAMLimitStatusUnknown;
static unsigned long long GSRecordedLimitBytes = 0;

@implementation GSRAMLimit

+ (unsigned long long)physicalMemoryBytes {
    return (unsigned long long)[NSProcessInfo processInfo].physicalMemory;
}

+ (unsigned long long)availableMemoryBytes {
    // 「还能再分配多少才触到 jetsam 上限」；进程没有内存上限时系统返回 0。
    // 这个接口只有 iOS 有，macOS 版（纯 URL 模式）没有 jetsam 概念，返回 0。
#if TARGET_OS_IPHONE
    return (unsigned long long)os_proc_available_memory();
#else
    return 0;
#endif
}

+ (unsigned long long)appliedLimitBytes {
    return GSRecordedLimitBytes;
}

+ (GSRAMLimitStatus)status {
    return GSRecordedStatus;
}

+ (GSRAMLimitStatus)applyIfNeeded {
    if (GSRecordedStatus == GSRAMLimitStatusRaised) {
        return GSRecordedStatus;
    }

    // 普通 IPA 没有 com.apple.private.memorystatus：符号在、调用会被系统拒绝，
    // 这里如实落到 Unavailable，由设置页说明「当前安装方式没有内存权限」。
    void *symbol = dlsym(RTLD_DEFAULT, "memorystatus_control");
    if (symbol == NULL) {
        GSRecordedStatus = GSRAMLimitStatusUnavailable;
        return GSRecordedStatus;
    }

    unsigned long long physical = self.physicalMemoryBytes;
    if (physical == 0) {
        GSRecordedStatus = GSRAMLimitStatusUnavailable;
        return GSRecordedStatus;
    }

    unsigned long long target = physical * 3 / 4;
    if (target > GSRAMLimitMaximumBytes) {
        target = GSRAMLimitMaximumBytes;
    }
    if (target < GSRAMLimitMinimumBytes) {
        target = GSRAMLimitMinimumBytes;
    }

    GSMemoryStatusControlFunction control = (GSMemoryStatusControlFunction)symbol;
    int result = control(GSMemoryStatusCommandSetTaskLimit, (int32_t)getpid(),
                         (uint32_t)target, NULL, 0);

    if (result == 0) {
        GSRecordedStatus = GSRAMLimitStatusRaised;
        GSRecordedLimitBytes = target;
        GSLogI(@"emu", @"内存上限已提升到 %llu MB（物理内存 %llu MB）",
               target / (1024 * 1024), physical / (1024 * 1024));
    } else {
        GSRecordedStatus = GSRAMLimitStatusUnavailable;
        GSRecordedLimitBytes = 0;
        GSLogI(@"emu", @"内存上限提升不可用（memorystatus_control 返回 %d）", result);
    }
    return GSRecordedStatus;
}

@end

/// 启动即应用：tipa 带私有内存权限时立刻生效；普通 IPA 只探测，失败不影响启动
__attribute__((constructor))
static void GSRAMLimitBootstrap(void) {
    [GSRAMLimit applyIfNeeded];
}
