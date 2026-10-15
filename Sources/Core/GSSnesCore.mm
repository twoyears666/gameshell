//
//  GSSnesCore.mm
//  Gameshell
//
//  Mesen-S（SNES / Super Famicom）核心的宿主胶水层。
//
//  为什么必须是 .mm（ObjC++）而不是 .m：
//  Mesen-S 是一整套 C++ 核心（Core/ + Utilities/ + SevenZip/），头文件是 C++，
//  只有 ObjC++ 能同时容纳 C++ 与 ObjC —— 与 GSNestopiaCore.mm 同一套写法。
//  （用户点名要保留 ObjC，也正是因为 Wii / 3DS / Wii U 的 JIT 链路只能走 C/ObjC。）
//
//  为什么走 libretro 接口而不是直接调 Mesen-S 的 C++ API：
//  Mesen-S 的「非 libretro」形态是桌面程序（自带窗口、独立解码/渲染线程、
//  UI 目录、Lua 脚本宿主…），我们一个都不要；它也从未把「宿主用」的取帧 / 取音频
//  C++ API 稳定开放出来。它给 RetroArch 用的 Libretro/ 前端恰好就是我们要的那层，
//  而且有明确契约（libretro.h），所以这里就按 libretro 前端来写：
//  Mesen-S 自带 Libretro/libretro.cpp 就是「核心侧」实现，我们这份是「前端侧」实现。
//
//  关键：核心必须带 -DLIBRETRO 编译（见 Vendor/mesens/CMakeLists.txt）。
//  该宏在核心内部切掉了独立解码/渲染线程（Core/VideoDecoder.cpp / VideoRenderer.cpp
//  的 StartThread() 变成空实现），于是 retro_run() → RunSingleFrame() → PPU
//  这条链路是在**调用 retro_run 的那个线程里同步跑完**的。宿主按帧节奏调
//  retro_run 的架构因此成立；不定义 LIBRETRO 的话核心会自己起线程，行为冲突。
//
//  画面格式：核心在 retro_load_game 里要求 RETRO_PIXEL_FORMAT_XRGB8888，
//  像素值是 0xFF000000 | (r<<16) | (g<<8) | b（见 Core/DefaultVideoFilter.cpp）。
//  小端内存里的字节序是 B,G,R,X，而宿主协议要的是 RGBA8888（R,G,B,A），
//  所以这里逐像素把 byte0 与 byte2 换一下、A 填 0xFF。
//
//  画面尺寸可变：Mesen-S 的 base 是 256x239，但 hi-res 模式会给 512 宽（乃至更高），
//  每帧的真实尺寸以 video_refresh 回调传入的 width/height/pitch 为准，
//  缓冲按需 realloc（上限见 kGSMesensMaxFrameBytes，2MB 足够 512x478）。
//
//  音频：retro_init 里核心把采样率钉死成 Spc::SpcSampleRate = 32040 Hz，
//  且 SoundMixer 一律按「交错立体声」出货。libretro 的 audio_sample_batch 契约里
//  frames 的单位是**立体声帧**，换算成宿主协议（count = int16 总数）要乘 2。
//
//  存档：核心在 #ifdef LIBRETRO 下对 .srm **直接 return**（BatteryManager.cpp
//  「let the frontend handle save ram」），retro_deinit 里的 SaveBatteries 也被注释掉了
//  —— 也就是说核心自己不落盘。所以宿主必须走 RetroArch 那套：
//  retro_get_memory_data(RETRO_MEMORY_SAVE_RAM) 拿到指针，载入后把 .sav 灌进去，
//  退出前 / 每 60 帧比对一次快照，变了才写回 .sav 文件（不逐帧写盘）。
//
//  单例：Libretro/libretro.cpp 里全是 file-static 全局（_console / _renderer /
//  _soundManager / _keyManager / retroEnv…），所以同一时刻只能有一个会话。
//  这也是 GSEmulatorSession 每次新建一个核心实例、用完必须 shutdown 的原因。
//
//  诚实标注：本文件在本机只做过语法预检（无 iOS SDK / 无 cmake，无法真机验证）。
//  真正的交叉编译与运行由 GitHub CI（macos 构建机）验证；未实机跑通前，
//  README / REFERENCE 不得声称「已实测可玩」。
//

#import "GSBuiltCoresCompat.h"

#if GS_HAVE_MESENS

#import "GSEmulator.h"

// libretro.h 自带 extern "C" 包裹（第 31 行），这里直接 include 即可。
// 注意：它只声明「核心侧」入口（retro_set_* / retro_init / retro_run…），
// 不声明前端回调 —— 所以下面这五个 retro_environment / retro_video_refresh /
// retro_audio_sample / retro_audio_sample_batch / retro_input_poll / retro_input_state
// 由本文件自行定义（并且必须用 extern "C" 保证 C 语言链接，
// 函数指针才能与 libretro.h 里的 typedef 类型一致）。
#include "libretro.h"

#include <stdlib.h>
#include <string.h>

/// 宿主帧缓冲上限（RGBA8888）。SNES hi-res 512x478 约 0.98MB，2MB 留足余量。
static const size_t kGSMesensMaxFrameBytes = 1024 * 512 * 4;
/// 单帧尺寸的硬上限（超过说明核心给了异常参数，直接丢弃，不冒险 realloc）
static const unsigned kGSMesensMaxVideoWidth = 1024;
static const unsigned kGSMesensMaxVideoHeight = 512;
/// 每隔多少帧检查一次电池存档是否需要写回
static const unsigned kGSMesensSaveCheckInterval = 60;
/// 核心钉死的采样率（Spc::SpcSampleRate）；拿不到 av_info 时用它兜底
static const double kGSMesensDefaultSampleRate = 32040.0;
/// NTSC SNES 的帧率，拿不到 av_info 时用它兜底
static const double kGSMesensDefaultFPS = 60.098811862348405;

#pragma mark - 类前置声明

@interface GSSnesCore : NSObject <GSEmulatorCore>

/// 下面几个是给 C 回调用的入口（C 函数在 @implementation 之外，拿不到 ivar）
- (const char *_Nullable)systemDirectoryPath;
- (const char *_Nullable)saveDirectoryPath;
- (void)handleVideoFrame:(const void *_Nullable)data
                   width:(unsigned)width
                  height:(unsigned)height
                   pitch:(size_t)pitch;
- (size_t)handleAudioFrames:(const int16_t *_Nullable)data frames:(size_t)frames;
- (int16_t)inputStateForPort:(unsigned)port
                      device:(unsigned)device
                       index:(unsigned)index
                        ident:(unsigned)ident;

@end

/// 核心是进程级单例（见文件头「单例」一节），同一时刻只能有一个会话。
/// 刻意用 __unsafe_unretained 而不是强引用：对象由 GSEmulatorSession 持有，
/// 这里只是 C 回调找回 ObjC 对象的「线」，shutdown 里会显式置 nil。
static __unsafe_unretained GSSnesCore *sHost = nil;

#pragma mark - libretro 前端回调（C 语言链接）

// 全部包在 extern "C" 里：libretro.h 的函数指针 typedef 是 C 链接的，
// 放在 C++ 里不加这个的话类型对不上（而且函数名会被修饰）。

extern "C" {

/// 环境回调。核心会问：system / save 目录、像素格式、变量、AV 信息…
/// 原则是「能答就答，答不了就 false」—— 核心对拿不到的项一律回落到自己的默认值，
/// 而 Mesen-S 的默认值正好是我们想要的：
///   VideoFilter = None（不启用 NTSC 滤波）、Region = Auto、AspectRatio = Auto。
static bool gs_retro_environment(unsigned cmd, void *data) {
    GSSnesCore *host = sHost;
    switch (cmd) {
        case RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY: {
            // 核心要求返回非空字符串，否则 retro_load_game 直接 return false
            if (host == nil || data == NULL) {
                return false;
            }
            const char *directory = [host systemDirectoryPath];
            if (directory == NULL) {
                return false;
            }
            *(const char **)data = directory;
            return true;
        }

        case RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY: {
            if (host == nil || data == NULL) {
                return false;
            }
            const char *directory = [host saveDirectoryPath];
            if (directory == NULL) {
                return false;
            }
            *(const char **)data = directory;
            return true;
        }

        case RETRO_ENVIRONMENT_SET_PIXEL_FORMAT: {
            // 核心只支持 XRGB8888，其它的它自己就会放弃载入
            if (data == NULL) {
                return false;
            }
            return *(const enum retro_pixel_format *)data == RETRO_PIXEL_FORMAT_XRGB8888;
        }

        case RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE: {
            // 回 false 让核心的 update_settings() 只在 retro_load_game 里跑一次，
            // 不要每帧都重设一遍配置（那是纯粹的性能浪费）
            if (data == NULL) {
                return false;
            }
            *(bool *)data = false;
            return true;
        }

        case RETRO_ENVIRONMENT_SET_SYSTEM_AV_INFO:
        case RETRO_ENVIRONMENT_SET_GEOMETRY:
            // 我们以 video_refresh 回调里的真实 width/height/pitch 为准，
            // 这里只表示「收到了」，不做尺寸缓存。
            return true;

        default:
            // 其余一律 false：GET_VARIABLE（用默认值）、GET_LOG_INTERFACE（不要日志）、
            // GET_FASTFORWARDING（不快进）、SET_SUBSYSTEM_INFO、SET_MEMORY_MAPS… 都是安全的。
            return false;
    }
}

/// 出帧回调。data == NULL 表示「与上一帧相同」，此时直接返回 ——
/// GSEmulatorSession 会一直保留上一张 CGImage，画面不会闪。
static void gs_retro_video_refresh(const void *data, unsigned width, unsigned height, size_t pitch) {
    GSSnesCore *host = sHost;
    if (host == nil) {
        return;
    }
    [host handleVideoFrame:data width:width height:height pitch:pitch];
}

/// 核心完全不用这个单采样接口（libretro.cpp 里 retro_set_audio_sample 是空实现），
/// 但契约要求给一个合法指针，这里放个空实现。
static void gs_retro_audio_sample(int16_t left, int16_t right) {
    (void)left;
    (void)right;
}

/// 出音频回调。frames 的单位是**立体声帧**，返回值是「消费掉多少帧」。
static size_t gs_retro_audio_sample_batch(const int16_t *data, size_t frames) {
    GSSnesCore *host = sHost;
    if (host == nil) {
        return 0;
    }
    return [host handleAudioFrames:data frames:frames];
}

static void gs_retro_input_poll(void) {
    // 我们的按键状态由 setButtonMask: 直接推进，没有「轮询一下硬件」这一步
}

/// 读键回调。Mesen-S 在 update_settings() 里把 KeyMapping 设成
/// keyCode = (port << 8) | (retroId + 1)，之后 LibretroKeyManager::IsKeyPressed
/// 又拆回 (port, retroId) —— 所以这里按 retro 的 joypad id 直接答即可。
/// 另外核心还会问 POINTER / MOUSE（用于 SNES Mouse / Super Scope），
/// 我们没接这两个设备，一律回 0。
static int16_t gs_retro_input_state(unsigned port, unsigned device, unsigned index, unsigned ident) {
    GSSnesCore *host = sHost;
    if (host == nil) {
        return 0;
    }
    return [host inputStateForPort:port device:device index:index ident:ident];
}

}  // extern "C"

#pragma mark - 实现

@implementation GSSnesCore {
    /// 交出去的帧缓冲（RGBA8888，按需 realloc）
    uint8_t *_frameBuffer;
    size_t _frameCapacity;

    size_t _videoWidth;
    size_t _videoHeight;
    double _sampleRate;
    double _fps;

    /// retro_init 已调用、retro_deinit 尚未调用
    BOOL _initialized;
    /// retro_load_game 成功、retro_unload_game 尚未调用
    BOOL _loaded;

    GSButton _buttonMask;

    /// 核心要的两个目录（它只读不写这对指针，所以由本对象持有、shutdown 里释放）
    char *_systemDirCString;
    char *_saveDirCString;
    /// ROM 路径（作为 retro_game_info.path，让核心能按扩展名识别映像类型）
    char *_romPathCString;

    /// ROM 字节。核心的 VirtualFile 只包住指针不拷贝，`Console` 会把它留在 RomInfo 里
    /// 直到卸载 —— 所以映射出来的 NSData 必须活满整个会话，不能只活到 load 结束。
    NSData *_romData;

    /// 电池存档（.sav）。核心在 LIBRETRO 下不落盘，由宿主负责。
    NSString *_savePath;
    NSData *_lastSavedImage;
    unsigned _framesSinceSaveCheck;
}

@synthesize delegate = _delegate;

+ (nullable id<GSEmulatorCore>)create {
    return [[GSSnesCore alloc] init];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _sampleRate = kGSMesensDefaultSampleRate;
        _fps = kGSMesensDefaultFPS;
        _videoWidth = 256;
        _videoHeight = 239;
    }
    return self;
}

- (void)dealloc {
    [self teardownCore];
}

#pragma mark 协议属性

- (NSString *)coreName { return @"Mesen-S"; }
- (NSString *)coreVersion { return @"Mesen-S（Vendor/mesens）"; }
- (double)sampleRate { return _sampleRate; }
- (double)framesPerSecond { return _fps; }
- (size_t)videoWidth { return _videoWidth; }
- (size_t)videoHeight { return _videoHeight; }
- (BOOL)requiresJIT { return NO; }

#pragma mark 给 C 回调用的小接口

- (const char *_Nullable)systemDirectoryPath { return _systemDirCString; }
- (const char *_Nullable)saveDirectoryPath { return _saveDirCString; }

#pragma mark 载入 / 卸载

- (BOOL)loadROMAtPath:(NSString *)path savePath:(NSString *)savePath error:(NSError **)error {
    if (_initialized || _loaded) {
        if (error) {
            *error = [self errorWithText: @"这个核心上一次的会话还没关掉"];
        }
        return NO;
    }
    if (path.length == 0) {
        if (error) {
            *error = [self errorWithText: @"ROM 路径为空"];
        }
        return NO;
    }

    // 映射读取：核心只包住这个指针不拷贝（见 _romData 的注释），所以整段会话都要留着。
    NSData *romData = [NSData dataWithContentsOfFile: path
                                             options: NSDataReadingMappedIfSafe
                                               error: NULL];
    if (romData.length == 0) {
        if (error) {
            *error = [self errorWithText: @"打不开这个 ROM 文件（文件不存在或内容为空）"];
        }
        return NO;
    }

    // 核心要一个 system 目录（用来找 BIOS / 游戏数据库之类的附带文件）。
    // 我们不入库任何 BIOS，所以给 ROM 所在目录就够了；核心找不到会自行降级，
    // 只有依赖 BIOS 的少数特殊卡带（BS-X 之类）才会因此跑不起来。
    NSString *directory = path.stringByDeletingLastPathComponent;
    if (directory.length == 0) {
        directory = NSTemporaryDirectory();
    }

    _romData = romData;
    _systemDirCString = strdup(directory.fileSystemRepresentation);
    _saveDirCString = strdup(directory.fileSystemRepresentation);
    _romPathCString = strdup(path.fileSystemRepresentation);
    _savePath = [savePath copy];
    if (_systemDirCString == NULL || _saveDirCString == NULL || _romPathCString == NULL) {
        if (error) {
            *error = [self errorWithText: @"内存不足，无法准备核心运行环境"];
        }
        [self teardownCore];
        return NO;
    }

    // 顺序是硬要求：环境回调必须在 retro_init 之前装好
    // （retro_init 里第一件事就是 retroEnv(GET_LOG_INTERFACE)），
    // 而 video / audio / input 回调必须在 retro_init 之后 ——
    // 那几个对象（_renderer / _soundManager / _keyManager）是 retro_init 创建的。
    sHost = self;
    retro_set_environment(gs_retro_environment);
    retro_init();
    _initialized = YES;

    retro_set_video_refresh(gs_retro_video_refresh);
    retro_set_audio_sample(gs_retro_audio_sample);
    retro_set_audio_sample_batch(gs_retro_audio_sample_batch);
    retro_set_input_poll(gs_retro_input_poll);
    retro_set_input_state(gs_retro_input_state);

    struct retro_game_info game = {};
    game.path = _romPathCString;
    game.data = romData.bytes;
    game.size = (size_t)romData.length;
    game.meta = NULL;

    if (!retro_load_game(&game)) {
        if (error) {
            *error = [self errorWithText:
                @"Mesen-S 认不出这个 ROM。常见原因：扩展名与实际内容不符、"
                 "文件损坏，或用了本版本不支持的特殊卡带（BS-X、需要 BIOS 的机型）。"];
        }
        [self teardownCore];
        return NO;
    }
    _loaded = YES;

    struct retro_system_av_info av = {};
    retro_get_system_av_info(&av);
    if (av.timing.sample_rate > 0) {
        _sampleRate = av.timing.sample_rate;
    }
    if (av.timing.fps > 0) {
        _fps = av.timing.fps;
    }
    if (av.geometry.base_width > 0) {
        _videoWidth = (size_t)av.geometry.base_width;
    }
    if (av.geometry.base_height > 0) {
        _videoHeight = (size_t)av.geometry.base_height;
    }

    _buttonMask = 0;
    [self restoreSaveRAM];
    _lastSavedImage = [self saveRAMImage];
    _framesSinceSaveCheck = 0;
    return YES;
}

/// 载入 / 卸载配对（与 mGBA / Nestopia 胶水同一套约定：unloadROM 空实现，
/// 真正的回收统一走 shutdown）。GSEmulatorSession 会先 unloadROM 再 shutdown。
- (void)unloadROM {
}

- (void)shutdown {
    [self teardownCore];
}

/// 回收一整套 libretro 会话。顺序不能乱：
///   1) 先把存档写回（必须在 retro_unload_game 之前，卸载会把卡带一起放掉）
///   2) retro_unload_game → Console::Stop(false)
///   3) retro_deinit → 核心把 _renderer / _soundManager / _console 全部释放
///   4) 最后才断开 sHost 并释放本对象自己持有的缓冲 / C 串
- (void)teardownCore {
    if (_loaded) {
        [self flushSaveRAMIfNeeded: YES];
        retro_unload_game();
        _loaded = NO;
    }
    if (_initialized) {
        retro_deinit();
        _initialized = NO;
    }
    sHost = nil;

    if (_systemDirCString) {
        free(_systemDirCString);
        _systemDirCString = NULL;
    }
    if (_saveDirCString) {
        free(_saveDirCString);
        _saveDirCString = NULL;
    }
    if (_romPathCString) {
        free(_romPathCString);
        _romPathCString = NULL;
    }
    if (_frameBuffer) {
        free(_frameBuffer);
        _frameBuffer = NULL;
    }
    _frameCapacity = 0;

    _romData = nil;
    _savePath = nil;
    _lastSavedImage = nil;
    _buttonMask = 0;
    _delegate = nil;
}

#pragma mark 每帧

- (void)runFrame {
    if (!_loaded) {
        return;
    }

    // 同步跑一帧：核心内部会把画面经 gs_retro_video_refresh、声音经
    // gs_retro_audio_sample_batch 回调出来（这就是要求 -DLIBRETRO 的原因）。
    retro_run();

    if (++_framesSinceSaveCheck >= kGSMesensSaveCheckInterval) {
        _framesSinceSaveCheck = 0;
        [self flushSaveRAMIfNeeded: NO];
    }
}

- (void)setButtonMask:(GSButton)mask {
    _buttonMask = mask;
}

#pragma mark 画面

- (void)handleVideoFrame:(const void *)data
                   width:(unsigned)width
                  height:(unsigned)height
                   pitch:(size_t)pitch {
    if (data == NULL || width == 0 || height == 0) {
        return;
    }
    if (width > kGSMesensMaxVideoWidth || height > kGSMesensMaxVideoHeight) {
        return;
    }

    const size_t rowBytes = (size_t)width * 4;
    const size_t needed = rowBytes * height;
    if (needed == 0 || needed > kGSMesensMaxFrameBytes) {
        return;
    }

    if (_frameBuffer == NULL || _frameCapacity < needed) {
        uint8_t *buffer = (uint8_t *)realloc(_frameBuffer, needed);
        if (buffer == NULL) {
            return;
        }
        _frameBuffer = buffer;
        _frameCapacity = needed;
    }

    // XRGB8888（内存字节序 B,G,R,X）→ RGBA8888（R,G,B,A）：换 byte0 与 byte2，A 填 0xFF。
    // 注意行距用核心给的 pitch，不要假设它等于 width*4（虽然 Mesen-S 现在就是这么多）。
    const uint8_t *source = (const uint8_t *)data;
    uint8_t *destination = _frameBuffer;
    for (unsigned y = 0; y < height; y++) {
        const uint8_t *sourceRow = source + (size_t)y * pitch;
        uint8_t *destinationRow = destination + (size_t)y * rowBytes;
        for (unsigned x = 0; x < width; x++) {
            const uint8_t *pixel = sourceRow + (size_t)x * 4;
            uint8_t *out = destinationRow + (size_t)x * 4;
            out[0] = pixel[2];
            out[1] = pixel[1];
            out[2] = pixel[0];
            out[3] = 0xFF;
        }
    }

    // 画面尺寸是可能变的（hi-res 模式会给 512 宽），如实更新给 UI
    _videoWidth = (size_t)width;
    _videoHeight = (size_t)height;

    [self.delegate coreDidRenderFrameRGBA8888: _frameBuffer
                                        width: (size_t)width
                                       height: (size_t)height
                                       stride: rowBytes];
}

#pragma mark 音频

- (size_t)handleAudioFrames:(const int16_t *)data frames:(size_t)frames {
    if (data == NULL || frames == 0) {
        return 0;
    }
    // libretro 的 frames 是「立体声帧」，宿主协议要的是 int16 总数 → 乘 2
    [self.delegate coreDidProduceAudioSamples: data count: frames * 2];
    return frames;
}

#pragma mark 输入

- (int16_t)inputStateForPort:(unsigned)port
                      device:(unsigned)device
                       index:(unsigned)index
                        ident:(unsigned)ident {
    // 只接 1 号口的标准 SNES 手柄；鼠标 / 光枪一律回 0（我们没做那些设备）
    if (port != 0 || device != RETRO_DEVICE_JOYPAD || index != 0) {
        return 0;
    }

    // GSButton 的位序与 retro 的 joypad id 不是一回事，必须显式翻一遍。
    // （retro: B=0 Y=1 SELECT=2 START=3 UP=4 DOWN=5 LEFT=6 RIGHT=7 A=8 X=9 L=10 R=11；
    //   GSButton: A=bit0 B=bit1 SELECT=bit2 START=bit3 RIGHT=bit4 LEFT=bit5
    //             UP=bit6 DOWN=bit7 R=bit8 L=bit9 X=bit10 Y=bit11）
    switch (ident) {
        case RETRO_DEVICE_ID_JOYPAD_A:      return (_buttonMask & GSButtonA) ? 1 : 0;
        case RETRO_DEVICE_ID_JOYPAD_B:      return (_buttonMask & GSButtonB) ? 1 : 0;
        case RETRO_DEVICE_ID_JOYPAD_X:      return (_buttonMask & GSButtonX) ? 1 : 0;
        case RETRO_DEVICE_ID_JOYPAD_Y:      return (_buttonMask & GSButtonY) ? 1 : 0;
        case RETRO_DEVICE_ID_JOYPAD_L:      return (_buttonMask & GSButtonL) ? 1 : 0;
        case RETRO_DEVICE_ID_JOYPAD_R:      return (_buttonMask & GSButtonR) ? 1 : 0;
        case RETRO_DEVICE_ID_JOYPAD_START:  return (_buttonMask & GSButtonStart) ? 1 : 0;
        case RETRO_DEVICE_ID_JOYPAD_SELECT: return (_buttonMask & GSButtonSelect) ? 1 : 0;
        case RETRO_DEVICE_ID_JOYPAD_UP:     return (_buttonMask & GSButtonUp) ? 1 : 0;
        case RETRO_DEVICE_ID_JOYPAD_DOWN:   return (_buttonMask & GSButtonDown) ? 1 : 0;
        case RETRO_DEVICE_ID_JOYPAD_LEFT:   return (_buttonMask & GSButtonLeft) ? 1 : 0;
        case RETRO_DEVICE_ID_JOYPAD_RIGHT:  return (_buttonMask & GSButtonRight) ? 1 : 0;
        default:                            return 0;
    }
}

#pragma mark 电池存档（核心不落盘，这里补上）

/// 把核心的 SRAM 原样拷一份出来；这个卡带没有电池备份时返回 nil。
- (nullable NSData *)saveRAMImage {
    if (!_loaded) {
        return nil;
    }
    uint8_t *pointer = (uint8_t *)retro_get_memory_data(RETRO_MEMORY_SAVE_RAM);
    size_t size = retro_get_memory_size(RETRO_MEMORY_SAVE_RAM);
    if (pointer == NULL || size == 0) {
        return nil;
    }
    return [NSData dataWithBytes: pointer length: size];
}

/// 把 .sav 灌回 SRAM。长度对不上时按 RetroArch 的做法取 min 拷贝
/// （SNES 的 SRAM 大小由卡带头决定，正常情况两边是一致的）。
- (void)restoreSaveRAM {
    if (!_loaded || _savePath.length == 0) {
        return;
    }
    NSData *saved = [NSData dataWithContentsOfFile: _savePath];
    if (saved.length == 0) {
        return;
    }
    uint8_t *pointer = (uint8_t *)retro_get_memory_data(RETRO_MEMORY_SAVE_RAM);
    size_t size = retro_get_memory_size(RETRO_MEMORY_SAVE_RAM);
    if (pointer == NULL || size == 0) {
        return;
    }
    memcpy(pointer, saved.bytes, MIN((size_t)saved.length, size));
}

/// 变了才写盘；force = YES 用于卸载 / 退出前的那一次。
- (void)flushSaveRAMIfNeeded:(BOOL)force {
    if (_savePath.length == 0) {
        return;
    }
    NSData *image = [self saveRAMImage];
    if (image.length == 0) {
        return;
    }
    if (!force && _lastSavedImage && [image isEqualToData: _lastSavedImage]) {
        return;
    }
    [image writeToFile: _savePath atomically: YES];
    _lastSavedImage = image;
}

#pragma mark 工具

- (NSError *)errorWithText:(NSString *)text {
    return [NSError errorWithDomain: @"GSEmulatorErrorDomain" code: 1
                           userInfo: @{NSLocalizedDescriptionKey: text}];
}

@end

// 注意：本文件是 Objective-C++，而调用方 GSEmulator.m 是 Objective-C（C 链接）。
// 不写 extern "C" 的话这里会生成 C++ 修饰名（__Z14GSSnesCoreCreatev），
// 链接期就会报 "_GSSnesCoreCreate undefined symbols"。GSNestopiaCore.mm 踩过一次。
extern "C" id<GSEmulatorCore> GSSnesCoreCreate(void) {
    return [GSSnesCore create];
}

#endif /* GS_HAVE_MESENS */
