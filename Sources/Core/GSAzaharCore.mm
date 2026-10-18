//
//  GSAzaharCore.mm
//  Gameshell
//
//  Azahar（Nintendo 3DS）核心的宿主胶水层。
//
//  为什么是 .mm（ObjC++）：
//  Azahar 是一整套 C++ 核心（core / video_core / audio_core…），头文件都是 C++，
//  只有 ObjC++ 能同时容纳 C++ 与 ObjC —— 与 GSMelonDSCore.mm 同一套写法。
//
//  为什么走 libretro 接口：
//  Azahar 上游的「桌面形态」自带 SDL/Qt 前端、独立渲染线程与 UI，我们一个都不要；
//  它给 RetroArch 用的 src/citra_libretro/ 前端恰好就是我们要的那层（有明确契约 libretro.h）。
//
//  渲染路径：软件渲染（software renderer）
//  构建时把 graphics_api 选项答成 "Software"，核心便走 SwRenderer::RendererSoftware，
//  在 emu_window/libretro_window.cpp 的 SwapBuffers 里把两块屏合成进一块 XRGB8888 缓冲，
//  再经 video_refresh 回调交出来 —— 与宿主「收一帧 RGBA8888」的架构一致。
//  为什么不上 Vulkan/MoltenVK：libretro 模式下核心对 Vulkan 走的是 frontend 提供
//  Vulkan device 的协商接口（retro_hw_render_context_negotiation_interface_vulkan），
//  宿主侧要自建 VkInstance/Device 并共享渲染目标，这是一整条新通路，本轮不做。
//
//  画面格式：核心写的是 XRGB8888 小端，内存字节序是 B,G,R,0（见 libretro_window.cpp 的
//  blit_screen：data[0]=src[2]、data[2]=src[0]）；宿主协议要 R,G,B,0xFF，
//  所以这里必须交换 byte0 / byte2 并把 alpha 补成 0xFF（同 GSSnesCore.mm 的做法）。
//  行距一律用回调传进来的 pitch，不假设它等于 width*4。
//
//  画面尺寸：默认布局是上屏（400x240）叠在下屏（320x240）之上，合成后 400x480。
//  构建时把 resolution_factor 钉成 "1"，保证缓冲不会超过宿主上限。真实尺寸以每帧回调为准。
//
//  音频：核心采样率 32728 Hz（audio_core 的 native_sample_rate）、帧率 60 fps。
//  libretro 的 audio_sample_batch 契约里 frames 的单位是**立体声帧**，
//  换算成宿主协议（count = int16 总数）要乘 2。
//
//  系统文件 / 存档目录（关键，与 melonDS 不同）：
//  Azahar 在 libretro 模式下把「用户目录」设成 <GET_SAVE_DIRECTORY>/Azahar/
//  （见 core_settings.cpp 的 ParseStorageOptions），它就在这个目录下找
//  sysdata / nand / sdmc 这些 3DS 系统文件、也把游戏存档写在这里。
//  所以宿主把 GET_SYSTEM_DIRECTORY 与 GET_SAVE_DIRECTORY 都答成 Documents/Bios，
//  于是用户目录落在 Documents/Bios/Azahar/ —— 与 NDS 的 BIOS 目录同源、一目了然。
//  没有 3DS 系统文件（sysdata）时核心会报「unable to locate a 3DS system archive」并拒绝载入，
//  这是核心的真实行为，宿主如实把它转成启动失败提示，不假装能玩。
//
//  JIT：Azahar 是双模式 —— dynarmic（CPU JIT）与 FastInterp 解释器都编进了库里
//  （arm/dynarmic/arm_dynarmic.cpp 与 arm/fastinterp 都在 citra_core 的目标里）。
//  上游本来在 iOS 上把 use_cpu_jit 硬写成 false，构建脚本会给 core_settings.cpp 打补丁
//  把这一处放开（见 Scripts/build_cores.sh 的 build_azahar_core）。于是：
//    · 设备拿得到可执行内存（GSJIT 探测 = enabled）→ 本文件答 citra_use_cpu_jit=enabled，走 JIT；
//    · 拿不到 → 答 disabled，核心按 use_fastinterp 退回 FastInterp 解释器。
//  「有 JIT 就一定用 JIT」，无 JIT 也不拒绝启动 —— 所以 requiresJIT 返回 NO，
//  界面改用 cpuBackendDescription 如实标注当前实际跑在哪一档。
//
//  符号前缀：本文件必须在 libretro.h 之前 include gs_azahar_symbol_prefix.h ——
//  原因见该文件顶部注释（同一 App 里还静态链接了 Mesen-S 与 melonDS 两个 libretro 核心）。
//
//  单例：Azahar 的 libretro 前端里 emu_instance / 各回调都是文件级全局，
//  所以同一时刻只能有一个会话。GSEmulatorSession 每次新建一个核心实例、用完必须 shutdown。
//
//  尚未接入：触摸屏（下屏）与摇杆（Circle Pad）。宿主协议目前只有按键位（GSButton），
//  没有摇杆通道；触摸层在播放器里也是 NDS 专用。这两个能力待宿主协议扩展后再补，
//  本文件不假装实现。
//
//  诚实标注：本文件在本机只做过静态检查（无 iOS SDK / 无 cmake，无法真机验证）。
//  真正的交叉编译与链接由 GitHub CI（macos 构建机）验证；未实机跑通前，
//  README / REFERENCE 不得声称「已实测可玩」。
//

#import "GSBuiltCoresCompat.h"

#if GS_HAVE_AZAHAR

#import "GSEmulator.h"
#import "GSNDSSupport.h"

// 先改名再取声明（关键顺序，别调换）：
// 主二进制里同时链接了 Mesen-S、melonDS 与 Azahar，三个核心的 retro_* 入口点同名会撞车，
// 经这个头文件把 Azahar 的入口点统一换成 gsazh_ 前缀。
#include "gs_azahar_symbol_prefix.h"

// melonDS 自带的 libretro 契约头（Azahar 用的也是同一份标准 libretro.h，
// 枚举值与结构体布局一致）。路径刻意带上 libretro-common/ 一层，
// 免得被 Mesen-S 的 Vendor/mesens/Libretro/libretro.h 抢先命中。
#include "libretro-common/include/libretro.h"

// melonDS 自带的这份 libretro.h 比 Azahar 上游（externals/libretro-common 子模块）旧一截，
// 没有 RETRO_ENVIRONMENT_GET_JIT_CAPABLE。按上游当前值（74）补上，
// 保证与 Azahar 头文件里的同名枚举值一致。
// （就算取错也无害：认不出的 cmd 本文件一律回 false，核心只会当作「无 JIT」，
//  而 iOS 上它本来就走解释器。）
#ifndef RETRO_ENVIRONMENT_GET_JIT_CAPABLE
#define RETRO_ENVIRONMENT_GET_JIT_CAPABLE 74
#endif

#include <stdlib.h>
#include <string.h>

/// 宿主帧缓冲上限（RGBA8888）。默认布局 400x480 只占 768KB，留到 1024x512（2MB）足够。
static const size_t kGSAzaharMaxFrameBytes = 1024 * 512 * 4;
/// 单帧尺寸硬上限（超过说明核心给了异常参数，直接丢弃，不冒险 realloc）
static const unsigned kGSAzaharMaxVideoWidth = 1024;
static const unsigned kGSAzaharMaxVideoHeight = 512;
/// 核心钉死的采样率（audio_core 的 native_sample_rate）
static const double kGSAzaharDefaultSampleRate = 32728.0;
/// 核心钉死的帧率（retro_get_system_av_info: 60.0）
static const double kGSAzaharDefaultFPS = 60.0;

#pragma mark - 类前置声明

@interface GSAzaharCore : NSObject <GSEmulatorCore>

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
static __unsafe_unretained GSAzaharCore *sHost = nil;

#pragma mark - libretro 前端回调（C 语言链接）

// 全部包在 extern "C" 里：libretro.h 的函数指针 typedef 是 C 链接的，
// 放在 C++ 里不加这个的话类型对不上（而且函数名会被修饰）。

extern "C" {

/// 回答核心 GET_VARIABLE 的问题。只回答几个「必须由前端拍板」的选项，
/// 其余一律返回 false，让核心用自己的默认值。
static bool gs_retro_lookup_variable(struct retro_variable *variable) {
    const char *key = variable->key;
    if (key == NULL) {
        return false;
    }

    if (strcmp(key, "citra_graphics_api") == 0 || strcmp(key, "azahar_graphics_api") == 0) {
        // 走软件渲染：与宿主「收一帧 RGBA8888」的架构一致，且不需要 Vulkan 协商通路
        variable->value = "Software";
        return true;
    }
    if (strcmp(key, "citra_resolution_factor") == 0 || strcmp(key, "azahar_resolution_factor") == 0) {
        // 钉成 1：保证 400x480 的合成缓冲不超过宿主上限（核心会对这个值做 std::stoi）
        variable->value = "1";
        return true;
    }
    if (strcmp(key, "citra_use_disk_shader_cache") == 0 || strcmp(key, "azahar_use_disk_shader_cache") == 0) {
        // 软件渲染没有着色器缓存，显式关掉，免得核心去调 Rasterizer()->LoadDefaultDiskResources()
        variable->value = "disabled";
        return true;
    }
    if (strcmp(key, "citra_layout_option") == 0 || strcmp(key, "azahar_layout_option") == 0) {
        // 默认布局：上屏叠下屏，合成后 400x480
        variable->value = "default";
        return true;
    }
    if (strcmp(key, "citra_use_cpu_jit") == 0 || strcmp(key, "azahar_use_cpu_jit") == 0) {
        // 「有 JIT 就一定用 JIT」：只有设备真拿得到可执行内存才答 enabled（走 dynarmic）。
        // 答 disabled 时核心会按 use_fastinterp 退回 FastInterp 解释器，不会拒绝启动。
        variable->value = ([GSJIT probeStatus] == GSJITStatusEnabled) ? "enabled" : "disabled";
        return true;
    }

    // 特别注意：核心会对某些选项做 std::stoi（resolution_factor / cpu_clock_percentage /
    // factor_3d / analog_deadzone），一旦我们返回 true 却给不出字符串就会炸。
    // 拿不准的一律落到 return false，让核心用自己的默认值。
    return false;
}

/// 环境回调。核心会问：system / save 目录、像素格式、变量、JIT 能力、AV 信息…
/// 原则是「能答就答，答不了就 false」—— 拿不到的项核心会回落到自己的默认值。
static bool gs_retro_environment(unsigned cmd, void *data) {
    GSAzaharCore *host = sHost;
    switch (cmd) {
        case RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY: {
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
            // 核心据此把「用户目录」设成 <save>/Azahar/（见 core_settings.cpp），
            // 系统文件与游戏存档都落在这里
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
            // 回 false 让核心只在 retro_load_game 里跑一次选项解析，
            // 不要每帧都重设一遍配置
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

        case RETRO_ENVIRONMENT_GET_JIT_CAPABLE: {
            // 如实回答本进程能不能拿到可执行内存。
            // citra_use_cpu_jit 按同一探测结果作答，所以这里答 true 就意味着真的会走 JIT。
            if (data == NULL) {
                return false;
            }
            *(bool *)data = ([GSJIT probeStatus] == GSJITStatusEnabled);
            return true;
        }

        case RETRO_ENVIRONMENT_SHUTDOWN:
            // 核心请求关闭：我们不做「整 App 退出」这种动作，只表示收到了。
            // 会话的真正回收仍由宿主的 shutdown 走。
            return true;

        default:
            // 其余一律 false：
            //   GET_LOG_INTERFACE   → 核心改用自带的 fallback_log（不乱刷日志）
            //   GET_CURRENT_SOFTWARE_FRAMEBUFFER → 核心自己 calloc 一块 pitch=width*4 的缓冲
            //   GET_VFS_INTERFACE   → 核心用自带的 POSIX 文件层
            //   GET_PREFERRED_HW_RENDER / GET_SENSOR_INTERFACE / GET_MICROPHONE_INTERFACE
            //   SET_VARIABLES / SET_CORE_OPTIONS* / SET_CONTROLLER_INFO / SET_MESSAGE…
            //   全部安全（核心对拿不到的项都有兜底）。
            return false;
    }
}

/// 出帧回调。data == NULL 表示「与上一帧相同」，此时直接返回 ——
/// GSEmulatorSession 会一直保留上一张 CGImage，画面不会闪。
static void gs_retro_video_refresh(const void *data, unsigned width, unsigned height, size_t pitch) {
    GSAzaharCore *host = sHost;
    if (host == nil) {
        return;
    }
    [host handleVideoFrame:data width:width height:height pitch:pitch];
}

/// 核心完全不用这个单采样接口（environment.cpp 的 retro_set_audio_sample 是空实现），
/// 但契约要求给一个合法指针，这里放个空实现。
static void gs_retro_audio_sample(int16_t left, int16_t right) {
    (void)left;
    (void)right;
}

/// 出音频回调。frames 的单位是**立体声帧**，返回值是「消费掉多少帧」。
static size_t gs_retro_audio_sample_batch(const int16_t *data, size_t frames) {
    GSAzaharCore *host = sHost;
    if (host == nil) {
        return 0;
    }
    return [host handleAudioFrames:data frames:frames];
}

static void gs_retro_input_poll(void) {
    // 我们的按键状态由 setButtonMask: 直接推进，没有「轮询一下硬件」这一步
}

/// 读键回调。Azahar 的 UpdateSettings 把按钮硬编码成 engine:libretro +
/// button:<retro joypad id>，所以 ident 就是 retro 的 joypad id，逐项翻一遍即可。
/// 只接 0 号口的 JOYPAD；摇杆 / 触摸 / 传感器一律回 0（本轮未接入）。
static int16_t gs_retro_input_state(unsigned port, unsigned device, unsigned index, unsigned ident) {
    GSAzaharCore *host = sHost;
    if (host == nil) {
        return 0;
    }
    return [host inputStateForPort:port device:device index:index ident:ident];
}

}  // extern "C"

#pragma mark - 实现

@implementation GSAzaharCore {
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
    /// ROM 路径（作为 retro_game_info.path —— 核心 need_fullpath=true，只读路径、不读内容）
    char *_romPathCString;
}

@synthesize delegate = _delegate;

+ (nullable id<GSEmulatorCore>)create {
    return [[GSAzaharCore alloc] init];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _sampleRate = kGSAzaharDefaultSampleRate;
        _fps = kGSAzaharDefaultFPS;
        _videoWidth = 400;
        _videoHeight = 480;
    }
    return self;
}

- (void)dealloc {
    [self teardownCore];
}

#pragma mark 协议属性

- (NSString *)coreName { return @"Azahar"; }
- (NSString *)coreVersion { return @"Azahar（libretro，软件渲染）"; }
- (double)sampleRate { return _sampleRate; }
- (double)framesPerSecond { return _fps; }
- (size_t)videoWidth { return _videoWidth; }
- (size_t)videoHeight { return _videoHeight; }
// 双模式：有 JIT 走 dynarmic，没有就退回 FastInterp 解释器 —— 不拒绝启动，只是速度不同
- (BOOL)requiresJIT { return NO; }
// 界面如实标注当前实际跑在哪一档（与 gs_retro_lookup_variable 答 citra_use_cpu_jit 同一依据）
- (nullable NSString *)cpuBackendDescription {
    return ([GSJIT probeStatus] == GSJITStatusEnabled) ? @"dynarmic JIT" : @"FastInterp 解释器";
}

#pragma mark 给 C 回调用的小接口

- (const char *_Nullable)systemDirectoryPath { return _systemDirCString; }
- (const char *_Nullable)saveDirectoryPath { return _saveDirCString; }

#pragma mark 载入 / 卸载

/// 公共准备：填两个目录指针、装好环境回调、retro_init。
/// 顺序是硬要求：环境回调必须在 retro_init 之前装好
/// （retro_init 会经 GetLoggingBackend 问 GET_LOG_INTERFACE），
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

- (BOOL)loadROMAtPath:(NSString *)path savePath:(NSString *)savePath error:(NSError **)error {
    // savePath 这里刻意不用：Azahar 自己把「用户目录」定在 <GET_SAVE_DIRECTORY>/Azahar/，
    // 存档由它在该目录内自行读写，宿主不插手命名。
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
    // 核心 need_fullpath=true：它按路径自己打开文件（不像 melonDS 吃内存指针），
    // 所以这里必须先确认文件真实存在，否则核心只会报一个含糊的 loader 失败。
    if (![[NSFileManager defaultManager] fileExistsAtPath: path]) {
        if (error) {
            *error = [self errorWithText: @"打不开这个 ROM 文件（文件不存在）"];
        }
        return NO;
    }

    // system / save 目录都给 Documents/Bios：
    //   核心据此把用户目录设成 Documents/Bios/Azahar/，
    //   3DS 系统文件（sysdata / nand）与游戏存档都落在那里（见文件头「系统文件 / 存档目录」）。
    NSString *systemDirectory = [GSNDSSupport biosDirectoryURL].path;

    if (![self prepareCoreWithSystemDirectory: systemDirectory
                                saveDirectory: systemDirectory
                                     romPath: path
                                       error: error]) {
        return NO;
    }

    struct retro_game_info game = {};
    game.path = _romPathCString;
    game.data = NULL;   // need_fullpath：核心不读这块内存
    game.size = 0;
    game.meta = NULL;

    if (!retro_load_game(&game)) {
        if (error) {
            *error = [self errorWithText:
                @"Azahar 没能载入这个 ROM。常见原因：扩展名与实际内容不符、文件损坏、"
                 @"ROM 是加密的（需先解密），或缺少 3DS 系统文件 —— "
                 @"Azahar 需要 Documents/Bios/Azahar/ 下有 sysdata（3DS 系统档案）才能启动游戏。"];
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
    return YES;
}

/// 载入 / 卸载配对（与其它核心胶水同一套约定：unloadROM 空实现，
/// 真正的回收统一走 shutdown）。GSEmulatorSession 会先 unloadROM 再 shutdown。
- (void)unloadROM {
}

- (void)shutdown {
    [self teardownCore];
}

/// 回收一整套 libretro 会话。顺序不能乱：
///   1) retro_unload_game → System::Shutdown（把内核、GPU、音频一起放掉）
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

    _buttonMask = 0;
    _delegate = nil;
}

#pragma mark 每帧

- (void)runFrame {
    if (!_loaded) {
        return;
    }
    // 同步跑一帧：核心把画面经 gs_retro_video_refresh、声音经
    // gs_retro_audio_sample_batch 回调出来。
    retro_run();
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
    if (width > kGSAzaharMaxVideoWidth || height > kGSAzaharMaxVideoHeight) {
        return;
    }

    const size_t rowBytes = (size_t)width * 4;
    const size_t needed = rowBytes * height;
    if (needed == 0 || needed > kGSAzaharMaxFrameBytes) {
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

    // 核心是 XRGB8888 小端：内存字节序 B,G,R,0；
    // 宿主要 R,G,B,0xFF —— 交换 byte0 / byte2 并把 alpha 补成不透明。
    // 行距用核心给的 pitch，不要假设它等于 width*4。
    const uint8_t *source = (const uint8_t *)data;
    uint8_t *destination = _frameBuffer;
    for (unsigned y = 0; y < height; y++) {
        const uint8_t *sourceRow = source + (size_t)y * pitch;
        uint8_t *destinationRow = destination + (size_t)y * rowBytes;
        for (unsigned x = 0; x < width; x++) {
            destinationRow[(size_t)x * 4 + 0] = sourceRow[(size_t)x * 4 + 2];
            destinationRow[(size_t)x * 4 + 1] = sourceRow[(size_t)x * 4 + 1];
            destinationRow[(size_t)x * 4 + 2] = sourceRow[(size_t)x * 4 + 0];
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
    // 只接 0 号口的标准 JOYPAD；摇杆 / 触摸 / 传感器一律回 0（本轮未接入）
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
// 不写 extern "C" 的话这里会生成 C++ 修饰名（__Z15GSAzaharCoreCreatev），
// 链接期就会报 "_GSAzaharCoreCreate undefined symbols"。
extern "C" id<GSEmulatorCore> GSAzaharCoreCreate(void) {
    return [GSAzaharCore create];
}

#endif /* GS_HAVE_AZAHAR */
