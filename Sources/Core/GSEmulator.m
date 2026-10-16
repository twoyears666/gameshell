//
//  GSEmulator.m
//  Gameshell
//
//  模拟器宿主层实现：JIT 探测 / 帧循环 / 画面取帧 / 音频环形缓冲 / 会话管理。
//

#import "GSEmulator.h"
#import "GSSystem.h"
#import "GSROMLibrary.h"
#import "GSBuiltCoresCompat.h"

#import <sys/mman.h>
#import <os/lock.h>
#import <time.h>
#import <unistd.h>

#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#endif

#if GS_HAVE_MGBA
extern id<GSEmulatorCore> GSMGBACoreCreate(void);
#endif

#if GS_HAVE_NESTOPIA
/// 实现在 GSNestopiaCore.mm（ObjC++：Nestopia 是 C++ 库）
extern id<GSEmulatorCore> GSNestopiaCoreCreate(void);
#endif

#if GS_HAVE_MESENS
/// 实现在 GSSnesCore.mm（ObjC++：Mesen-S 是 C++ 库，走 libretro 接口）
extern id<GSEmulatorCore> GSSnesCoreCreate(void);
#endif

#if GS_HAVE_MELONDS
/// 实现在 GSMelonDSCore.mm（ObjC++：melonDS 是 C++ 库，走 libretro 接口）
extern id<GSEmulatorCore> GSMelonDSCoreCreate(void);
#endif

NSString *const GSEmulatorErrorDomain = @"GSEmulatorErrorDomain";

typedef NS_ENUM(NSInteger, GSEmulatorErrorCode) {
    GSEmulatorErrorCodeNoCore = 1,
    GSEmulatorErrorCodeJITRequired,
    GSEmulatorErrorCodeLoadFailed,
};

#pragma mark - TrollStore JIT 自举（仅 iOS）

#if TARGET_OS_IPHONE

// 在较高系统的 TrollStore 上，dynamic-codesigning / com.apple.private.cs.debugger 已被封禁，
// 想自己开 JIT 只剩一条路：App 带 com.apple.private.security.no-sandbox，
// 运行时「spawn 一个自己的子进程，子进程 ptrace(PT_TRACE_ME)」——
// 这样父子进程都拿到 CS_DEBUGGED，mmap(MAP_JIT) 于是成立。
// 做法照 AngelAuraMC/Amethyst-iOS（Natives/main.m）与 UTM（Services/UTMJailbreak.m）。
//
// 要点：
//   · 必须在 UIApplicationMain 之前跑完 → 用 __attribute__((constructor))（SwiftUI 的 @main App
//     已把 main() 生成掉了，没有别的插入点）；
//   · 子进程靠哨兵参数识别，只做 ptrace 后立刻 _exit(0)，绝不进入 UIApplicationMain，避免起两份界面；
//   · 只有带 no-sandbox entitlement 时才做（普通 IPA / macOS 没有，直接跳过）；
//   · 已经能 mmap(MAP_JIT) 就不做，避免白 spawn 一次。
//
// ⚠️ no-sandbox 之后 NSDocumentDirectory 可能不再解析到自己的容器；本 App 的 ROMs/ 存档/
//    keymap.json 都在 Documents 下。若真机上发现路径异常，需要按 HOME 重新定位（Amethyst 的兜底方式）。

#import <crt_externs.h>
#import <Security/Security.h>
#import <spawn.h>
#import <signal.h>
#import <sys/wait.h>
#import <errno.h>
#import <string.h>

extern char **environ;

// 私有 API：从自身读 entitlement（声明照 Amethyst 的 utils.m）
CFTypeRef SecTaskCopyValueForEntitlement(void *task, NSString *entitlement, CFErrorRef _Nullable *error);
void *SecTaskCreateFromSelf(CFAllocatorRef allocator);

// ptrace 在 iOS 公开 SDK 里未声明，照 Amethyst 自行声明
#define GS_PT_TRACE_ME 0
#define GS_PT_DETACH 11
int ptrace(int, pid_t, caddr_t, int);

/// 子进程识别用的哨兵参数
static const char *const GSJITChildSentinel = "gameshell-jit-child";

/// 本进程是否带指定 entitlement
static BOOL GSProcessHasEntitlement(NSString *key) {
    void *task = SecTaskCreateFromSelf(NULL);
    if (task == NULL) {
        return NO;
    }
    CFTypeRef value = SecTaskCopyValueForEntitlement(task, key, NULL);
    CFRelease(task);
    if (value == NULL) {
        return NO;
    }
    CFRelease(value);
    return YES;
}

/// 真正的 JIT 判据：能不能 mmap(MAP_JIT)
static BOOL GSProbeMapJIT(void) {
#if defined(MAP_JIT)
    size_t page = (size_t)getpagesize();
    void *pointer = mmap(NULL, page, PROT_READ | PROT_WRITE | PROT_EXEC,
                         MAP_PRIVATE | MAP_ANONYMOUS | MAP_JIT, -1, 0);
    if (pointer == MAP_FAILED) {
        return NO;
    }
    munmap(pointer, page);
    return YES;
#else
    return NO;
#endif
}

static void GSJITBootstrapIfNeeded(void) {
    // 只在 TrollStore 这种「带 no-sandbox」的环境里自举；普通 IPA / macOS 直接跳过
    if (!GSProcessHasEntitlement(@"com.apple.private.security.no-sandbox")) {
        return;
    }

    int *argcPointer = _NSGetArgc();
    char ***argvPointer = _NSGetArgv();
    char **argv = argvPointer ? *argvPointer : NULL;
    if (argcPointer == NULL || argv == NULL || argv[0] == NULL) {
        return;
    }

    // 子进程：只做 ptrace(PT_TRACE_ME)，让父子都拿到 CS_DEBUGGED，然后立刻退出
    if (*argcPointer >= 2 && argv[1] != NULL &&
        strcmp(argv[1], GSJITChildSentinel) == 0) {
        ptrace(GS_PT_TRACE_ME, 0, 0, 0);
        _exit(0);
    }

    // 已经能 mmap(MAP_JIT) 就什么都不用做
    if (GSProbeMapJIT()) {
        return;
    }

    pid_t child = 0;
    char *childArgv[] = { argv[0], (char *)GSJITChildSentinel, NULL };
    int result = posix_spawnp(&child, argv[0], NULL, NULL, childArgv, environ);
    if (result != 0) {
        NSLog(@"[GSJIT] 自举失败：posix_spawnp 返回 %d（errno %d）", result, errno);
        return;
    }
    waitpid(child, NULL, WUNTRACED);
    ptrace(GS_PT_DETACH, child, NULL, 0);
    kill(child, SIGTERM);
    wait(NULL);

    if (GSProbeMapJIT()) {
        NSLog(@"[GSJIT] TrollStore 自举成功：已可通过 PT_TRACE_ME 拿到 JIT");
    } else {
        NSLog(@"[GSJIT] 自举后仍拿不到 JIT（可能是 iOS 26+/TXM 机型，需要外挂 StikDebug）");
    }
}

__attribute__((constructor))
static void GSJITBootstrapConstructor(void) {
    GSJITBootstrapIfNeeded();
}

#endif

#pragma mark - JIT

@implementation GSJIT

+ (GSJITStatus)probeStatus {
#if defined(MAP_JIT)
    size_t page = (size_t)getpagesize();
    void *pointer = mmap(NULL, page, PROT_READ | PROT_WRITE | PROT_EXEC,
                         MAP_PRIVATE | MAP_ANONYMOUS | MAP_JIT, -1, 0);
    if (pointer != MAP_FAILED) {
        munmap(pointer, page);
        return GSJITStatusEnabled;
    }
#endif
    return GSJITStatusUnavailable;
}

+ (BOOL)isTrollStoreAvailable {
#if TARGET_OS_IPHONE
    NSURL *probe = [NSURL URLWithString: @"apple-magnifier://"];
    if (!probe) {
        return NO;
    }
    // 需要 Info.plist 的 LSApplicationQueriesSchemes 里声明 apple-magnifier
    return [[UIApplication sharedApplication] canOpenURL: probe];
#else
    return NO;
#endif
}

+ (NSURL *)trollStoreEnableJITURLForBundleID:(NSString *)bundleID {
    NSString *escaped = [bundleID stringByAddingPercentEncodingWithAllowedCharacters:
        [NSCharacterSet URLQueryAllowedCharacterSet]] ?: bundleID;
    return [NSURL URLWithString: [@"apple-magnifier://enable-jit?bundle-id=" stringByAppendingString: escaped]];
}

+ (nullable void *)allocateExecutableMemoryWithSize:(size_t)size {
#if defined(MAP_JIT)
    void *pointer = mmap(NULL, size, PROT_READ | PROT_WRITE | PROT_EXEC,
                         MAP_PRIVATE | MAP_ANONYMOUS | MAP_JIT, -1, 0);
    if (pointer == MAP_FAILED) {
        return NULL;
    }
    return pointer;
#else
    (void)size;
    return NULL;
#endif
}

+ (void)releaseExecutableMemory:(void *)pointer size:(size_t)size {
    if (pointer == NULL) {
        return;
    }
    munmap(pointer, size);
}

@end

#pragma mark - 会话

/// 音频环形缓冲的容量（int16 元素个数，交错立体声）
static const size_t GSAudioRingCapacity = 65536;
/// 一帧视频最多多少字节（RGBA8888）。
/// 取 1024x512 —— 覆盖目前接入 / 计划接入的核心里最大的那些画面：
/// NES 256x240、GBA 240x160、SNES 高分辨率 512x448、Wii 640x480 都落在里面。
static const size_t GSMaxFrameBytes = 1024 * 512 * 4;

/// CGDataProvider 的释放回调
static void _GSReleaseFrameBuffer(void *info, const void *data, size_t size);

@interface GSEmulatorSession () <GSEmulatorCoreDelegate>
/// 按系统实例化核心；返回 nil 表示这个系统还没有核心接入。
/// 方法名刻意不叫 new… —— 以 new 开头的选择器会被 clang 当成 new 方法族，返回 instancetype。
+ (nullable id<GSEmulatorCore>)createCoreForSystem:(GSSystem)system;
/// 已经接入的系统 → 核心名。编译期就能确定，只算一次，供 UI 高频查询（不实例化核心）
+ (NSDictionary<NSNumber *, NSString *> *)coreNamesBySystem;
@end

@implementation GSEmulatorSession {
    GSROM *_rom;
    GSSystemInfo *_systemInfo;
    id<GSEmulatorCore> _core;

    BOOL _isAvailable;
    NSString *_unavailableReason;
    BOOL _started;

    // 帧循环
    NSThread *_emulationThread;
    volatile BOOL _running;
    dispatch_semaphore_t _loopExitSemaphore;

    // 最新一帧
    CGImageRef _frameImage;
    os_unfair_lock _frameLock;

    // 音频环形缓冲
    int16_t *_audioRing;
    size_t _audioReadIndex;
    size_t _audioWriteIndex;
    os_unfair_lock _audioLock;

    GSButton _pendingButtonMask;

    // 触摸屏（NDS 下屏）：与按键同理 —— 主线程只写「待生效」状态，
    // 模拟线程消费后、且核心实现了触摸接口时才下发。
    CGPoint _pendingTouchPoint;
    BOOL _pendingTouchActive;
    BOOL _hasPendingTouch;
}

- (instancetype)initWithROM:(GSROM *)rom {
    self = [super init];
    if (self) {
        _rom = rom;
        _systemInfo = [GSSystemRegistry infoForSystem: rom.system];
        _frameLock = OS_UNFAIR_LOCK_INIT;
        _audioLock = OS_UNFAIR_LOCK_INIT;
        _audioRing = calloc(GSAudioRingCapacity, sizeof(int16_t));

        _core = [GSEmulatorSession createCoreForSystem: rom.system];
        if (_core == nil) {
            _isAvailable = NO;
            _unavailableReason = [NSString stringWithFormat:
                @"%@ 的核心还没接入这个版本，暂时打不开。%@",
                _systemInfo.shortName,
                _systemInfo.statusNote ?: @"见 REFERENCE.md 的「核心接入进度」"];
        } else {
            _isAvailable = YES;
        }
    }
    return self;
}

- (void)dealloc {
    [self stop];
    free(_audioRing);
}

#pragma mark 核心工厂

+ (nullable id<GSEmulatorCore>)createCoreForSystem:(GSSystem)system {
#if GS_HAVE_MGBA
    switch (system) {
        case GSSystemGBA:
        case GSSystemGB:
        case GSSystemGBC:
            return GSMGBACoreCreate();
        default:
            break;
    }
#endif
#if GS_HAVE_NESTOPIA
    if (system == GSSystemNES) {
        return GSNestopiaCoreCreate();
    }
#endif
#if GS_HAVE_MESENS
    if (system == GSSystemSNES) {
        return GSSnesCoreCreate();
    }
#endif
#if GS_HAVE_MELONDS
    if (system == GSSystemNDS) {
        return GSMelonDSCoreCreate();
    }
#endif
    return nil;
}

+ (NSDictionary<NSNumber *, NSString *> *)coreNamesBySystem {
    static NSDictionary<NSNumber *, NSString *> *names;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableDictionary<NSNumber *, NSString *> *dict = [NSMutableDictionary dictionary];
        // 与上面的 createCoreForSystem: 同一组编译期开关，保持一致
#if GS_HAVE_MGBA
        dict[@(GSSystemGBA)] = @"mGBA";
        dict[@(GSSystemGB)]  = @"mGBA";
        dict[@(GSSystemGBC)] = @"mGBA";
#endif
#if GS_HAVE_NESTOPIA
        dict[@(GSSystemNES)] = @"Nestopia";
#endif
#if GS_HAVE_MESENS
        dict[@(GSSystemSNES)] = @"Mesen-S";
#endif
#if GS_HAVE_MELONDS
        dict[@(GSSystemNDS)] = @"melonDS";
#endif
        names = [dict copy];
    });
    return names;
}

+ (BOOL)hasCoreForSystem:(GSSystem)system {
    return [self coreNamesBySystem][@(system)] != nil;
}

+ (nullable NSString *)coreNameForSystem:(GSSystem)system {
    return [self coreNamesBySystem][@(system)];
}

#pragma mark 只读属性

- (GSROM *)rom { return _rom; }
- (GSSystemInfo *)systemInfo { return _systemInfo; }
- (id<GSEmulatorCore>)core { return _core; }
- (BOOL)isAvailable { return _isAvailable; }
- (NSString *)unavailableReason { return _unavailableReason; }
- (double)audioSampleRate { return _core ? _core.sampleRate : 0; }

- (BOOL)requiresJIT {
    return _systemInfo.requiresJIT;
}

- (GSJITStatus)jitStatus {
    return [GSJIT probeStatus];
}

- (NSString *)jitWarning {
    if (!self.requiresJIT) {
        return nil;
    }
    if (self.jitStatus == GSJITStatusEnabled) {
        return nil;
    }
    return [NSString stringWithFormat:
        @"%@ 需要 JIT 才能运行，当前进程还没拿到可执行内存。\n"
         "TrollStore 安装：用 TrollStore 给 %@ 开一次 JIT（apple-magnifier://enable-jit）。\n"
         "普通侧载：用 StikDebug 附加调试器后再启动。详见 REFERENCE.md。",
        _systemInfo.shortName, NSBundle.mainBundle.bundleIdentifier ?: @"本 App"];
}

#pragma mark 启停

- (BOOL)startWithError:(NSError **)error {
    if (!_isAvailable || _core == nil) {
        if (error) {
            *error = [NSError errorWithDomain: GSEmulatorErrorDomain
                                         code: GSEmulatorErrorCodeNoCore
                                     userInfo: @{NSLocalizedDescriptionKey:
                                        _unavailableReason ?: @"没有可用的核心"}];
        }
        return NO;
    }
    if (_started) {
        return YES;
    }
    if (self.requiresJIT && self.jitStatus != GSJITStatusEnabled) {
        if (error) {
            *error = [NSError errorWithDomain: GSEmulatorErrorDomain
                                         code: GSEmulatorErrorCodeJITRequired
                                     userInfo: @{NSLocalizedDescriptionKey: self.jitWarning}];
        }
        return NO;
    }

    _core.delegate = self;
    NSURL *saveURL = [GSROMLibrary batterySaveURLForROM: _rom];
    NSError *loadError = nil;
    if (![_core loadROMAtPath: _rom.absolutePath savePath: saveURL.path error: &loadError]) {
        if (error) {
            *error = loadError ?: [NSError errorWithDomain: GSEmulatorErrorDomain
                                                      code: GSEmulatorErrorCodeLoadFailed
                                                  userInfo: @{NSLocalizedDescriptionKey: @"核心无法载入这个 ROM"}];
        }
        return NO;
    }

    _running = YES;
    _loopExitSemaphore = dispatch_semaphore_create(0);
    _emulationThread = [[NSThread alloc] initWithTarget: self
                                               selector: @selector(emulationLoop)
                                                 object: nil];
    _emulationThread.name = @"com.twoyears666.gameshell.emulation";
    _emulationThread.qualityOfService = NSQualityOfServiceUserInitiated;
    [_emulationThread start];
    _started = YES;
    return YES;
}

- (void)stop {
    // 只有帧循环真的在跑时才需要等它退出；
    // 但无论走没走到「启动成功」，只要核心已经建出来就必须回收，
    // 否则「核心 init 过、但 loadROM 失败导致 start 返回 NO」的场景会漏掉核心。
    if (_running) {
        _running = NO;
        if (_loopExitSemaphore) {
            dispatch_semaphore_wait(_loopExitSemaphore, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)));
        }
    }
    _emulationThread = nil;
    _started = NO;
    _hasPendingTouch = NO;

    if (_core) {
        [_core unloadROM];
        [_core shutdown];
        _core = nil;
    }
    os_unfair_lock_lock(&_frameLock);
    if (_frameImage) {
        CGImageRelease(_frameImage);
        _frameImage = NULL;
    }
    os_unfair_lock_unlock(&_frameLock);
}

#pragma mark 帧循环

- (void)emulationLoop {
    double fps = _core.framesPerSecond;
    if (fps < 1.0) {
        fps = 60.0;
    }
    const uint64_t frameIntervalNs = (uint64_t)(1000000000.0 / fps);
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    uint64_t nextFrameNs = (uint64_t)now.tv_sec * 1000000000ull + (uint64_t)now.tv_nsec;

    while (_running) {
        @autoreleasepool {
            if (!self.paused) {
                [_core setButtonMask: _pendingButtonMask];
                // 触摸只在核心真的实现了接口时下发（respondsToSelector: 守卫），
                // 避免对 mGBA / Nestopia 这类不触摸的核心误发消息。
                if (_hasPendingTouch && [_core respondsToSelector: @selector(setTouchPoint:active:)]) {
                    [_core setTouchPoint: _pendingTouchPoint active: _pendingTouchActive];
                    _hasPendingTouch = NO;
                }
                [_core runFrame];
            } else {
                usleep(8000);
            }
        }

        clock_gettime(CLOCK_MONOTONIC, &now);
        uint64_t currentNs = (uint64_t)now.tv_sec * 1000000000ull + (uint64_t)now.tv_nsec;
        nextFrameNs += frameIntervalNs;
        if (nextFrameNs > currentNs) {
            uint64_t deltaMs = (nextFrameNs - currentNs) / 1000000ull;
            if (deltaMs > 0) {
                usleep((useconds_t)(deltaMs * 1000ull));
            }
        } else if (currentNs - nextFrameNs > 5 * frameIntervalNs) {
            // 落后太多就重新对齐，避免追帧雪崩
            nextFrameNs = currentNs;
        }
    }

    if (_loopExitSemaphore) {
        dispatch_semaphore_signal(_loopExitSemaphore);
    }
}

#pragma mark 输入

- (void)setButtonMask:(GSButton)mask {
    _pendingButtonMask = mask;
}

/// 触摸屏（NDS 下屏）。point 是触摸区内的归一化坐标（0–1）。
/// 与 setButtonMask: 同一套「主线程写、模拟线程读」模式：只更新待生效值。
- (void)setTouchPoint:(CGPoint)point active:(BOOL)active {
    _pendingTouchPoint = point;
    _pendingTouchActive = active;
    _hasPendingTouch = YES;
}

#pragma mark 画面

- (void)coreDidRenderFrameRGBA8888:(const uint8_t *)pixels
                             width:(size_t)width
                            height:(size_t)height
                            stride:(size_t)stride {
    if (pixels == NULL || width == 0 || height == 0) {
        return;
    }
    size_t rowBytes = width * 4;
    size_t total = rowBytes * height;
    if (total == 0 || total > GSMaxFrameBytes) {
        return;
    }

    uint8_t *copy = malloc(total);
    if (copy == NULL) {
        return;
    }
    for (size_t row = 0; row < height; row++) {
        memcpy(copy + row * rowBytes, pixels + row * stride, rowBytes);
    }

    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, copy, total, _GSReleaseFrameBuffer);
    CGImageRef image = CGImageCreate(width, height, 8, 32, rowBytes, space,
                                     kCGImageAlphaNoneSkipLast | kCGBitmapByteOrder32Big,
                                     provider, NULL, false, kCGRenderingIntentDefault);
    CGDataProviderRelease(provider);
    CGColorSpaceRelease(space);

    if (image == NULL) {
        return;
    }

    os_unfair_lock_lock(&_frameLock);
    if (_frameImage) {
        CGImageRelease(_frameImage);
    }
    _frameImage = image;
    os_unfair_lock_unlock(&_frameLock);
}

static void _GSReleaseFrameBuffer(void *info, const void *data, size_t size) {
    (void)info;
    (void)size;
    free((void *)data);
}

- (nullable CGImageRef)copyLatestFrameImage {
    os_unfair_lock_lock(&_frameLock);
    CGImageRef image = _frameImage;
    if (image) {
        CGImageRetain(image);
    }
    os_unfair_lock_unlock(&_frameLock);
    return image;
}

#pragma mark 音频

- (void)coreDidProduceAudioSamples:(const int16_t *)samples count:(size_t)count {
    if (samples == NULL || count == 0 || _audioRing == NULL) {
        return;
    }

    os_unfair_lock_lock(&_audioLock);
    for (size_t i = 0; i < count; i++) {
        size_t next = (_audioWriteIndex + 1) % GSAudioRingCapacity;
        if (next == _audioReadIndex) {
            // 缓冲满了，丢掉最老的一小段，保证声音不会越来越延迟
            _audioReadIndex = (_audioReadIndex + count) % GSAudioRingCapacity;
        }
        _audioRing[_audioWriteIndex] = samples[i];
        _audioWriteIndex = next;
    }
    os_unfair_lock_unlock(&_audioLock);
}

- (size_t)readAudioInto:(int16_t *)buffer count:(size_t)count {
    if (buffer == NULL || count == 0 || _audioRing == NULL) {
        return 0;
    }

    os_unfair_lock_lock(&_audioLock);
    size_t available = (_audioWriteIndex + GSAudioRingCapacity - _audioReadIndex) % GSAudioRingCapacity;
    size_t toRead = MIN(count, available);
    // 只按整帧（立体声 2 个 int16）取，避免左右声道错位
    toRead -= (toRead % 2);

    for (size_t i = 0; i < toRead; i++) {
        buffer[i] = _audioRing[_audioReadIndex];
        _audioReadIndex = (_audioReadIndex + 1) % GSAudioRingCapacity;
    }
    os_unfair_lock_unlock(&_audioLock);

    if (toRead < count) {
        memset(buffer + toRead, 0, (count - toRead) * sizeof(int16_t));
    }
    return toRead;
}

@end
