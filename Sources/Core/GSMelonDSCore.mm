//
//  GSMelonDSCore.mm
//  Gameshell
//
//  melonDS（Nintendo DS / DSi）核心的宿主胶水层。
//
//  为什么是 .mm（ObjC++）：
//  melonDS 是一整套 C++ 核心（src/ 下 NDS/GPU/SPU/ARM... 全是 C++），头文件也是 C++，
//  只有 ObjC++ 能同时容纳 C++ 与 ObjC —— 与 GSSnesCore.mm / GSNestopiaCore.mm 同一套写法。
//
//  为什么走 libretro 接口：
//  melonDS 上游本体的「桌面形态」自带窗口、独立渲染线程与 UI，我们一个都不要；
//  它给 RetroArch 用的 src/libretro/ 前端恰好就是我们要的那层（有明确契约 libretro.h）。
//  核心侧实现就是 Vendor/melonds/src/libretro/libretro.cpp，本文件是前端侧实现。
//
//  JIT 与「无 JIT」两条路径（用户明确要求都支持）：
//  - 编译期：Scripts/build_cores.sh 传 JIT_ARCH=aarch64，于是 melonDS 编入 ARM64 dynarec
//    （ARMJIT*.cpp + dolphin/Arm64Emitter.cpp，见 Makefile.common 的 JIT_ARCH 分支）。
//    对应宏 JIT_ENABLED / ARCHITECTURE_ARM64。
//  - 运行时：由宿主按 GSJIT 的真实探测结果回答核心的 melonds_jit_enable 选项：
//    设备拿得到可执行内存就答 enabled（走 JIT，快），否则答 disabled（走解释器，慢但能跑）。
//    JIT 不设用户开关：能用就用 —— 这是用户明确的要求。
//  - 只答 disabled 还不够：NDS::Init() 在 JIT_ENABLED 下是**无条件**构造 JIT 编译器、
//    执行 mmap(MAP_JIT) 的，没有权限时它拿到 MAP_FAILED 还照写，正是「一开 NDS 就闪退」
//    的根因。所以 Vendor 侧另打了兜底补丁（ARMJIT_Compiler.cpp：mmap 失败就沿用静态缓冲）。
//  - 因此 requiresJIT 返回 NO：解释器兜底，NDS 在任何设备上都打得开，只是速度不同。
//
//  画面格式：核心在 retro_load_game 里要求 RETRO_PIXEL_FORMAT_XRGB8888，
//  但 melonDS 的显示缓冲在内存里本身就是 RGBA 字节序
//  （见 GPU2D_Soft.cpp 的 dst[i] = r | (g << 8) | (b << 16)，以及 line 末尾补 0xFF000000），
//  所以这里**不需要**像 Mesen-S 那样交换 byte0/byte2，只把 alpha 补成不透明即可。
//  行距一律用 video_refresh 回调传进来的 pitch，不假设它等于 width*4。
//
//  画面尺寸：随用户选的双屏布局而变 —— 上下 / 左右是 256x384 / 512x192，
//  只上屏 / 只下屏是 256x192。真实尺寸仍以每帧回调的 width/height 为准，缓冲按需 realloc。
//  布局由宿主答 melonds_screen_layout（取值见 GSNDSSupport）。
//
//  音频：核心的采样率固定 32768 Hz、帧率 32*1024*1024/560190 ≈ 59.826 fps，
//  audio_callback 一律按「交错立体声」出货。libretro 的 audio_sample_batch 契约里
//  frames 的单位是**立体声帧**，换算成宿主协议（count = int16 总数）要乘 2。
//
//  存档：与 Mesen-S 相反 —— melonDS **自己落盘**。
//  retro_load_game 里会算出 save_path = <save 目录>/<ROM 同名>.sav 交给 NDS::LoadROM，
//  且 retro_run 每帧末尾会调 NDSCart_SRAMManager::Flush() 把脏页写回。
//  所以宿主不需要管 .sav：只要把 GET_SAVE_DIRECTORY 答成 ROM 所在目录，
//  核心算出来的路径就与 GSROMLibrary batterySaveURLForROM: 完全一致（同目录、同名 .sav）。
//
//  BIOS / 固件：我们不随 App 分发任何 BIOS。用户在设置页用「文件」App 把
//  bios7.bin / bios9.bin / firmware.bin 导入到沙盒 Documents/Bios/，宿主把
//  GET_SYSTEM_DIRECTORY 答成这个目录，核心便会按文件名去取（见 libretro.cpp 的
//  _handle_load_game）。三件套不全时核心自动降级到 FreeBIOS + 合成固件，仍能直启进游戏。
//  melonds_boot_directly 一律答 enabled（见 gs_retro_lookup_variable）：
//  插了固件也直启进游戏，不走核心自带的系统菜单 —— 那条路在 iOS 上没用。
//
//  触摸：把 melonds_touch_mode 答成 Touch，核心便走 libretro 的 RETRO_DEVICE_POINTER
//  （见 input.cpp 的 TouchMode::Touch 分支）。宿主经 setTouchPoint:active: 传「DS 下屏内的
//  归一化坐标（0–1）」，本文件换算成 pointer 的 int16 坐标，换算依据见该方法注释。
//  特别注意 pointer 的 ident（X=0 / Y=1 / PRESSED=2）与 JOYPAD 的 B(0) / Y(1) / SELECT(2)
//  数值撞车，所以 inputStateForPort: 必须先判 device 再判 ident。
//
//  符号前缀：本文件必须在 libretro.h 之前 include gs_symbol_prefix.h ——
//  原因见该文件顶部注释（同一 App 里还静态链接了另一个 libretro 核心 Mesen-S）。
//
//  单例：melonDS 的 libretro.cpp 里全是文件级全局（environ_cb / audio_cb / screen_layout_data…），
//  所以同一时刻只能有一个会话。GSEmulatorSession 每次新建一个核心实例、用完必须 shutdown。
//
//  诚实标注：本文件在本机只做过静态检查（无 iOS SDK / 无 cmake，无法真机验证）。
//  真正的交叉编译与链接由 GitHub CI（macos 构建机）验证；未实机跑通前，
//  README / REFERENCE 不得声称「已实测可玩」。
//

#import "GSBuiltCoresCompat.h"

#if GS_HAVE_MELONDS

#import "GSEmulator.h"
#import "GSNDSSupport.h"

// 先改名再取声明（关键顺序，别调换）：
// 主二进制里同时链接了 Mesen-S，两个核心的 retro_* 入口点同名会撞车，
// 经这个头文件把 melonDS 的入口点统一换成 gsmds_ 前缀。
#include "gs_symbol_prefix.h"

// melonDS 自带的 libretro 契约头。路径刻意带上 libretro-common/ 一层，
// 免得被 Mesen-S 的 Vendor/mesens/Libretro/libretro.h 抢先命中（两个核心的头不同源）。
// 对应的搜索路径写在 project.yml 的 HEADER_SEARCH_PATHS。
#include "libretro-common/include/libretro.h"

#include <math.h>
#include <stdlib.h>
#include <string.h>

/// 宿主帧缓冲上限（RGBA8888）。256x384 的 Top/Bottom 只占 384KB，
/// 但 Left/Right 与 Hybrid 布局会更大，留到 1024x512（2MB）足够。
static const size_t kGSMelondsMaxFrameBytes = 1024 * 512 * 4;
/// 单帧尺寸硬上限（超过说明核心给了异常参数，直接丢弃，不冒险 realloc）
static const unsigned kGSMelondsMaxVideoWidth = 1024;
static const unsigned kGSMelondsMaxVideoHeight = 512;
/// 核心钉死的采样率（libretro.cpp: 32.0f * 1024.0f）；拿不到 av_info 时兜底
static const double kGSMelondsDefaultSampleRate = 32768.0;
/// NTSC 帧率（libretro.cpp: 32*1024*1024/560190）；拿不到 av_info 时兜底
static const double kGSMelondsDefaultFPS = 32.0 * 1024.0 * 1024.0 / 560190.0;

#pragma mark - 类前置声明

@interface GSMelonDSCore : NSObject <GSEmulatorCore>

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
static __unsafe_unretained GSMelonDSCore *sHost = nil;

#pragma mark - libretro 前端回调（C 语言链接）

// 全部包在 extern "C" 里：libretro.h 的函数指针 typedef 是 C 链接的，
// 放在 C++ 里不加这个的话类型对不上（而且函数名会被修饰）。

extern "C" {

/// 回答核心 GET_VARIABLE 的问题。只回答几个「必须由前端拍板」的选项，
/// 其余一律返回 false，让核心用自己的默认值（melonDS 的默认值对我们是安全的：
/// 触摸禁用、十字屏距 0、单线程软渲染、不随机 MAC…）。
static bool gs_retro_lookup_variable(struct retro_variable *variable) {
    const char *key = variable->key;
    if (key == NULL) {
        return false;
    }

    if (strcmp(key, "melonds_console_mode") == 0) {
        // 选 DS 而不是 DSi：DS 模式兼容性最好，且即时存档只有 DS 模式支持
        variable->value = "DS";
        return true;
    }
    if (strcmp(key, "melonds_boot_directly") == 0) {
        // 一律直启：不插固件菜单那一步。
        // 核心自带系统菜单的那条路在 iOS 上既没用又容易黑屏，宿主已去掉「先进
        // DS 主界面」这个选项（原来还配了「DS 主界面」独立入口），这里跟着钉死。
        // 缺 firmware.bin 时本来就是直启（核心用 FreeBIOS + 合成固件）；
        // 有 firmware.bin 时也直启 —— 核心照旧会读固件取语言等默认值，只是不过菜单。
        variable->value = "enabled";
        return true;
    }
    if (strcmp(key, "melonds_screen_layout") == 0) {
        // 用户在设置页选的双屏布局（上下 / 左右 / 只上屏 / 只下屏）
        variable->value = [[GSNDSSupport shared] melonDSScreenLayoutValue].UTF8String;
        return true;
    }
    if (strcmp(key, "melonds_language") == 0) {
        // 没有固件文件时这个值会生效，而核心的默认是 Japanese —— 显式答 English
        variable->value = "English";
        return true;
    }
    if (strcmp(key, "melonds_jit_enable") == 0) {
        // 设备拿得到可执行内存才开 JIT，否则退回解释器。
        // 核心默认是 true，所以「无 JIT 的设备」必须靠这里显式答 disabled 才不会崩。
        variable->value = ([GSJIT probeStatus] == GSJITStatusEnabled) ? "enabled" : "disabled";
        return true;
    }
    if (strcmp(key, "melonds_touch_mode") == 0) {
        // 触屏走 libretro 的 pointer 设备（input.cpp 的 TouchMode::Touch 分支），
        // 由宿主经 setTouchPoint:active: 驱动。核心默认是 Disabled，必须显式答 Touch。
        variable->value = "Touch";
        return true;
    }

    // 特别注意 melonds_screen_gap：核心会拿 var.value 去 std::stoi，
    // 一旦我们返回 true 却给不出字符串就会炸，所以这里必须落到 return false。
    // 其余（threaded_renderer / mic_input / audio_bitrate /
    // audio_interpolation / use_fw_settings / hybrid_* / dsi_sdcard…）同理交给默认值。
    return false;
}

/// 环境回调。核心会问：system / save 目录、像素格式、变量、AV 信息…
/// 原则是「能答就答，答不了就 false」—— 拿不到的项核心会回落到自己的默认值，
/// 而 melonDS 的默认值正好是我们想要的。
static bool gs_retro_environment(unsigned cmd, void *data) {
    GSMelonDSCore *host = sHost;
    switch (cmd) {
        case RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY: {
            // 核心要求返回非空字符串，否则查 BIOS / 固件会走空路径
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
            // 核心据此算出 <ROM 同名>.sav 的落盘位置（核心自己读写，宿主不插手）
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

        case RETRO_ENVIRONMENT_GET_VARIABLE: {
            if (data == NULL) {
                return false;
            }
            struct retro_variable *variable = (struct retro_variable *)data;
            // 先把 value 清成 NULL：核心的模式是 if (GET_VARIABLE && var.value)，
            // 我们返回 false 时留个野指针会出问题。
            variable->value = NULL;
            return gs_retro_lookup_variable(variable);
        }

        case RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE: {
            // 回 false 让核心只在 retro_load_game 里跑一次 check_variables，
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
            // 其余一律 false：
            //   GET_LOG_INTERFACE   → 核心改用自带的 fallback_log（不乱刷日志）
            //   GET_INPUT_BITMASKS  → 核心改为按 ident 逐个读键（正好对上我们的实现）
            //   GET_VFS_INTERFACE   → libretro-common 用自带的 POSIX 文件层
            //   SET_VARIABLES / SET_CORE_OPTIONS* → 我们不需要它注册选项，
            //                                       选项值上面 GET_VARIABLE 已经硬答了
            //   GET_USERNAME / GET_LANGUAGE / GET_FASTFORWARDING / SET_MEMORY_MAPS…
            //   全部安全。
            return false;
    }
}

/// 出帧回调。data == NULL 表示「与上一帧相同」，此时直接返回 ——
/// GSEmulatorSession 会一直保留上一张 CGImage，画面不会闪。
static void gs_retro_video_refresh(const void *data, unsigned width, unsigned height, size_t pitch) {
    GSMelonDSCore *host = sHost;
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
    GSMelonDSCore *host = sHost;
    if (host == nil) {
        return 0;
    }
    return [host handleAudioFrames:data frames:frames];
}

static void gs_retro_input_poll(void) {
    // 我们的按键状态由 setButtonMask: 直接推进，没有「轮询一下硬件」这一步
}

/// 读键回调。核心在 libretro_supports_bitmasks 为 false 时按 ident 逐个查
/// （我们上面的 NO 回 false 正好让它走这条路），ident 就是 retro 的 joypad id。
/// 只接 0 号口的标准 DS 手柄；触摸 / 麦克风 / 换屏 / 合盖一律回 0。
static int16_t gs_retro_input_state(unsigned port, unsigned device, unsigned index, unsigned ident) {
    GSMelonDSCore *host = sHost;
    if (host == nil) {
        return 0;
    }
    return [host inputStateForPort:port device:device index:index ident:ident];
}

}  // extern "C"

#pragma mark - 实现

@implementation GSMelonDSCore {
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

    /// 触摸屏（DS 下屏）状态。坐标是 libretro pointer 的 int16 表示
    /// （0x8000 为缓冲中心偏移；换算见 setTouchPoint:active: 的注释）。
    int16_t _touchPointerX;
    int16_t _touchPointerY;
    /// 手指当前是否按在触摸屏上
    BOOL _touchActive;

    /// 核心要的两个目录（它只读不写这对指针，所以由本对象持有、shutdown 里释放）
    char *_systemDirCString;
    char *_saveDirCString;
    /// ROM 路径（作为 retro_game_info.path，让核心能按文件名算出 .sav 的名字）
    char *_romPathCString;

    /// ROM 字节。核心的 retro_load_game 只是把 info 缓存下来、并不拷贝内容
    /// （NDS::LoadROM 直接吃这块内存），所以映射出来的 NSData 必须活满整个会话。
    NSData *_romData;
}

@synthesize delegate = _delegate;

+ (nullable id<GSEmulatorCore>)create {
    return [[GSMelonDSCore alloc] init];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _sampleRate = kGSMelondsDefaultSampleRate;
        _fps = kGSMelondsDefaultFPS;
        _videoWidth = 256;
        _videoHeight = 384;
    }
    return self;
}

- (void)dealloc {
    [self teardownCore];
}

#pragma mark 协议属性

- (NSString *)coreName { return @"melonDS"; }
- (NSString *)coreVersion { return @"melonDS（Vendor/melonds）"; }
- (double)sampleRate { return _sampleRate; }
- (double)framesPerSecond { return _fps; }
- (size_t)videoWidth { return _videoWidth; }
- (size_t)videoHeight { return _videoHeight; }
// JIT 是「能用就用、用不了退回解释器」，所以不把它当作启动硬条件
- (BOOL)requiresJIT { return NO; }
// 界面如实标注当前实际跑在哪一档：与 melonds_jit_enable 的作答同一依据
- (nullable NSString *)cpuBackendDescription {
    return ([GSJIT probeStatus] == GSJITStatusEnabled) ? @"ARM64 JIT" : @"解释器";
}

#pragma mark 给 C 回调用的小接口

- (const char *_Nullable)systemDirectoryPath { return _systemDirCString; }
- (const char *_Nullable)saveDirectoryPath { return _saveDirCString; }

#pragma mark 载入 / 卸载

/// 公共准备：填两个目录指针、装好环境回调、retro_init。
/// 顺序是硬要求：环境回调必须在 retro_init 之前装好
/// （retro_init 第一件事就是问 GET_SYSTEM_DIRECTORY / GET_SAVE_DIRECTORY），
/// 而 video / audio / input 回调只需在 retro_load_game 之前装好即可。
- (BOOL)prepareCoreWithSystemDirectory:(NSString *)systemDirectory
                         saveDirectory:(NSString *)saveDirectory
                              romPath:(NSString *)romPath
                                error:(NSError **)error {
    _systemDirCString = strdup(systemDirectory.fileSystemRepresentation);
    _saveDirCString = strdup(saveDirectory.fileSystemRepresentation);
    _romPathCString = strdup(romPath.fileSystemRepresentation);
    if (_systemDirCString == NULL || _saveDirCString == NULL || _romPathCString == NULL) {
        if (error) {
            *error = [self errorWithText: @"内存不足，无法准备核心运行环境"];
        }
        [self teardownCore];
        return NO;
    }

    sHost = self;
    retro_set_environment(gs_retro_environment);
    retro_init();
    _initialized = YES;

    retro_set_video_refresh(gs_retro_video_refresh);
    retro_set_audio_sample(gs_retro_audio_sample);
    retro_set_audio_sample_batch(gs_retro_audio_sample_batch);
    retro_set_input_poll(gs_retro_input_poll);
    retro_set_input_state(gs_retro_input_state);
    return YES;
}

/// 把 game 交给核心，并做成功后的公共收尾（刷新 av 信息、复位输入状态）。
- (BOOL)startCoreWithGame:(struct retro_game_info)game
                  failure:(NSString *)failureText
                    error:(NSError **)error {
    if (!retro_load_game(&game)) {
        if (error) {
            *error = [self errorWithText: failureText];
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
    _touchActive = NO;
    _touchPointerX = 0;
    _touchPointerY = 0;
    return YES;
}

- (BOOL)loadROMAtPath:(NSString *)path savePath:(NSString *)savePath error:(NSError **)error {
    // savePath 这里刻意不用：melonDS 自己按 GET_SAVE_DIRECTORY + ROM 文件名算 .sav，
    // 我们只要保证那个目录就是 ROM 所在目录（见下面 _saveDirCString）即可对上。
    (void)savePath;

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

    // 映射读取：核心只缓存这个指针不拷贝（见 _romData 的注释），所以整段会话都要留着。
    NSData *romData = [NSData dataWithContentsOfFile: path
                                             options: NSDataReadingMappedIfSafe
                                               error: NULL];
    if (romData.length == 0) {
        if (error) {
            *error = [self errorWithText: @"打不开这个 ROM 文件（文件不存在或内容为空）"];
        }
        return NO;
    }

    // save 目录给 ROM 所在目录：核心据此算出 <ROM 同名>.sav，与 GSROMLibrary 的命名一致。
    NSString *saveDirectory = path.stringByDeletingLastPathComponent;
    if (saveDirectory.length == 0) {
        saveDirectory = NSTemporaryDirectory();
    }
    // system 目录给 Documents/Bios：核心就是在这个目录里按文件名找
    // bios7.bin / bios9.bin / firmware.bin（见 libretro.cpp 的 _handle_load_game），
    // 找不到就降级到 FreeBIOS + 合成固件。
    NSString *systemDirectory = [GSNDSSupport biosDirectoryURL].path;

    _romData = romData;
    if (![self prepareCoreWithSystemDirectory: systemDirectory
                                saveDirectory: saveDirectory
                                     romPath: path
                                       error: error]) {
        return NO;
    }

    struct retro_game_info game = {};
    game.path = _romPathCString;
    game.data = romData.bytes;
    game.size = (size_t)romData.length;
    game.meta = NULL;

    return [self startCoreWithGame: game
                           failure: @"melonDS 认不出这个 ROM。常见原因：扩展名与实际内容不符、"
                                    @"文件损坏，或不是 .nds/.ids/.dsi 里的任何一种。"
                             error: error];
}

/// 载入 / 卸载配对（与其它核心胶水同一套约定：unloadROM 空实现，
/// 真正的回收统一走 shutdown）。GSEmulatorSession 会先 unloadROM 再 shutdown。
- (void)unloadROM {
}

- (void)shutdown {
    [self teardownCore];
}

/// 回收一整套 libretro 会话。顺序不能乱：
///   1) retro_unload_game → NDS::DeInit（把卡带、GPU、SPU 一起放掉，
///      核心此时会自己把脏的 .sav 刷盘，所以这里不需要宿主补写）
///   2) retro_deinit → 核心清掉本会话的全局开关
///   3) 最后才断开 sHost 并释放本对象自己持有的缓冲 / C 串
- (void)teardownCore {
    if (_loaded) {
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
    _buttonMask = 0;
    _touchActive = NO;
    _touchPointerX = 0;
    _touchPointerY = 0;
    _delegate = nil;
}

#pragma mark 每帧

- (void)runFrame {
    if (!_loaded) {
        return;
    }
    // 同步跑一帧：核心内部会把画面经 gs_retro_video_refresh、声音经
    // gs_retro_audio_sample_batch 回调出来，并在末尾自己 Flush 电池存档。
    retro_run();
}

- (void)setButtonMask:(GSButton)mask {
    _buttonMask = mask;
}

/// 触摸屏（DS 下屏）。point 是**下屏内的归一化坐标（0–1）**，本方法把它换算成
/// libretro pointer 的 int16 坐标（0x8000 为缓冲中心偏移）。
///
/// 换算依据（input.cpp 的 TouchMode::Touch 分支）：
///   核心侧：buffer_x = (pointer_x + 0x8000) * buffer_width  / 0x10000
///           buffer_y = (pointer_y + 0x8000) * buffer_height / 0x10000
///   要让触摸落到「下屏矩形」内的点，就得先知道该布局下 buffer 有多大、下屏偏在哪 ——
///   这随双屏布局而变（上下 → 下屏在下半；左右 → 下屏在右半；只下屏 → 整块就是下屏）。
///   这些几何统一由 GSNDSSupport.pointerForNormalizedTouch:layout: 给出，
///   播放器把触摸层盖在渲染出的下屏矩形上，传给你的 nx / ny 就是相对那块矩形的。
- (void)setTouchPoint:(CGPoint)point active:(BOOL)active {
    _touchActive = active;

    GSNDSScreenLayout layout = [GSNDSSupport shared].screenLayout;
    CGPoint pointer = [GSNDSSupport pointerForNormalizedTouch: point layout: layout];
    _touchPointerX = (int16_t)pointer.x;
    _touchPointerY = (int16_t)pointer.y;
}

#pragma mark 画面

- (void)handleVideoFrame:(const void *)data
                   width:(unsigned)width
                  height:(unsigned)height
                   pitch:(size_t)pitch {
    if (data == NULL || width == 0 || height == 0) {
        return;
    }
    if (width > kGSMelondsMaxVideoWidth || height > kGSMelondsMaxVideoHeight) {
        return;
    }

    const size_t rowBytes = (size_t)width * 4;
    const size_t needed = rowBytes * height;
    if (needed == 0 || needed > kGSMelondsMaxFrameBytes) {
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

    // melonDS 的显示缓冲本身就是 RGBA 字节序（r | g<<8 | b<<16，见 GPU2D_Soft.cpp），
    // 所以**不需要**交换 R 与 B，只需要把 alpha 补成 0xFF 不透明。
    // 行距用核心给的 pitch，不要假设它等于 width*4。
    const uint8_t *source = (const uint8_t *)data;
    uint8_t *destination = _frameBuffer;
    for (unsigned y = 0; y < height; y++) {
        const uint8_t *sourceRow = source + (size_t)y * pitch;
        uint8_t *destinationRow = destination + (size_t)y * rowBytes;
        memcpy(destinationRow, sourceRow, rowBytes);
        for (unsigned x = 0; x < width; x++) {
            destinationRow[(size_t)x * 4 + 3] = 0xFF;
        }
    }

    // 画面尺寸可能随布局变化，如实更新给 UI
    _videoWidth = (size_t)width;
    _videoHeight = (size_t)height;

    [self.delegate coreDidRenderFrameRGBA8888: _frameBuffer
                                        width: (size_t)width
                                       height: (size_t)height
                                       stride: rowBytes];
}

#pragma mark 即时存档（走核心自带的 libretro 序列化）

/// 取一份即时存档。melonDS 的 retro_serialize_size 只在 DS 模式下返回非 0；
/// DSi 模式核心明确不支持即时存档（它会打 warn 并返回 0），此时我们如实返回 nil，
/// 由 UI 提示「这个模式下不能存/读档」。
- (nullable NSData *)copySaveState {
    if (!_loaded) {
        return nil;
    }
    size_t size = retro_serialize_size();
    if (size == 0) {
        return nil;
    }
    NSMutableData *data = [NSMutableData dataWithLength: size];
    if (!retro_serialize(data.mutableBytes, size)) {
        return nil;
    }
    return data;
}

- (BOOL)restoreSaveState:(NSData *)data {
    if (!_loaded || data.length == 0) {
        return NO;
    }
    return retro_unserialize(data.bytes, (size_t)data.length);
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
    // 先判 device 再判 ident：pointer 的 ident（X=0 / Y=1 / PRESSED=2）
    // 与 JOYPAD 的 B(0) / Y(1) / SELECT(2) 数值撞车，顺序不能反。
    if (device == RETRO_DEVICE_POINTER) {
        if (port != 0 || index != 0) {
            return 0;
        }
        switch (ident) {
            case RETRO_DEVICE_ID_POINTER_PRESSED: return _touchActive ? 1 : 0;
            case RETRO_DEVICE_ID_POINTER_X:       return _touchPointerX;
            case RETRO_DEVICE_ID_POINTER_Y:       return _touchPointerY;
            default:                              return 0;
        }
    }

    // 只接 0 号口的标准 DS 手柄；麦克风 / 换屏 / 合盖一律回 0
    if (port != 0 || device != RETRO_DEVICE_JOYPAD || index != 0) {
        return 0;
    }

    // GSButton 与 retro 的 joypad id 位序不是一回事，必须显式翻一遍。
    // （retro: B=0 Y=1 SELECT=2 START=3 UP=4 DOWN=5 LEFT=6 RIGHT=7 A=8 X=9 L=10 R=11
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

#pragma mark 工具

- (NSError *)errorWithText:(NSString *)text {
    return [NSError errorWithDomain: @"GSEmulatorErrorDomain" code: 1
                           userInfo: @{NSLocalizedDescriptionKey: text}];
}

@end

// 注意：本文件是 Objective-C++，而调用方 GSEmulator.m 是 Objective-C（C 链接）。
// 不写 extern "C" 的话这里会生成 C++ 修饰名（__Z17GSMelonDSCoreCreatev），
// 链接期就会报 "_GSMelonDSCoreCreate undefined symbols"。
extern "C" id<GSEmulatorCore> GSMelonDSCoreCreate(void) {
    return [GSMelonDSCore create];
}

#endif /* GS_HAVE_MELONDS */
