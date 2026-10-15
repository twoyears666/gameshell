//
//  GSNestopiaCore.mm
//  Gameshell
//
//  Nestopia（NES / Famicom）静态库的宿主胶水层。
//
//  为什么必须是 .mm（ObjC++）而不是 .m：
//  1) Nestopia 的核心与 API 层是 C++（namespace Nes::Core / Nes::Api），
//     C++ 头文件在纯 ObjC 里根本没法 include —— 只有 ObjC++ 能同时容纳两边；
//  2) 用户点名要保留 ObjC，也正是因为后面 Wii / 3DS / Wii U 的 JIT 链路
//     （mmap(MAP_JIT) + 运行时生成代码）都只能走 C / ObjC 这条路，
//     核心适配层统一用这套写法，风格一致。
//
//  颜色：Nestopia 的输出位深与掩码由 RenderState 决定。这里显式设成
//  32bpp、mask 为 R=0x0000FF / G=0x00FF00 / B=0xFF0000 —— 小端内存里的字节序
//  正好是 R,G,B,X，也就是宿主统一的 RGBA8888，不需要任何转换。
//  （RetroArch 用的是 XRGB 掩码，于是还得再转一次；我们直接选 RGBA 掩码省掉这步。）
//
//  音频：Nestopia 每帧写**单声道** 16 位采样（长度见 Output::length[0]），
//  而宿主协议要的是交错立体声，所以这里把每个采样复制成 L=R 两份再交出去。
//
//  存档：卡带的电池备份内存（WRAM 等）由 Api::Memory 暴露；载入 ROM 后把 .sav
//  读回内存块，之后每 60 帧和上一份快照比一次，变了才写回文件 —— 不做逐帧写盘。
//
//  参考：上游 libretro 前端（Vendor/nestopia/libretro/libretro.cpp）给出了
//  核心生命周期、RenderState、控制器选择的权威用法（Load → SetRenderState →
//  SetSampleRate → AutoSelectControllers → Power(true)，之后每帧 Execute）。
//

#import "GSBuiltCoresCompat.h"

#if GS_HAVE_NESTOPIA

#import "GSEmulator.h"

#include "NstApiEmulator.hpp"
#include "NstApiMachine.hpp"
#include "NstApiMemory.hpp"
#include "NstApiSound.hpp"
#include "NstApiVideo.hpp"
#include "NstApiInput.hpp"

#include <fstream>
#include <new>

/// NES 画面的固定尺寸（Nestopia 的 NES 输出就是 256x240；不做 NTSC 滤波）
static const unsigned kGSNestopiaVideoWidth = Nes::Core::Video::Output::WIDTH;   // 256
static const unsigned kGSNestopiaVideoHeight = Nes::Core::Video::Output::HEIGHT; // 240

/// 一帧最多多少采样（PAL 是 44100/50 = 882，留点余量）
static const unsigned kGSNestopiaMaxAudioFrames = 1024;

/// 采样率（Nestopia 支持 44100~96000，统一用 44100）
static const unsigned kGSNestopiaSampleRate = 44100;

/// 每隔多少帧检查一次电池存档是否需要写回
static const unsigned kGSNestopiaSaveCheckInterval = 60;

#pragma mark - 运行时上下文

/// 一套完整 的 Nestopia 运行时。
/// 刻意堆分配而不是直接做成 ObjC 的 ivar：C++ 对象在 ObjC++ 里当 ivar 有很多
/// ARC / 析构时序的坑，用普通指针 + 显式 delete 反而清楚。
struct GSNestopiaContext {
    Nes::Api::Emulator *emulator = NULL;
    Nes::Api::Video::Output *video = NULL;
    Nes::Api::Sound::Output *audio = NULL;
    Nes::Api::Input::Controllers *input = NULL;

    /// 视频缓冲：RGBA8888，一行 256 像素
    uint32_t *videoBuffer = NULL;
    /// 音频缓冲：Nestopia 写的单声道采样
    int16_t *audioBuffer = NULL;

    /// 这一帧要在音频缓冲里留多少采样（按 NTSC/PAL 不同）
    unsigned audioSamplesPerFrame = 0;
    bool isPAL = false;

    GSNestopiaContext() {}
};

#pragma mark - 核心

@interface GSNestopiaCore : NSObject <GSEmulatorCore>
/// 把当前按键掩码翻成 Nestopia 的 Pad 位
- (unsigned)nestopiaPadButtons;
@end

@implementation GSNestopiaCore {
    GSNestopiaContext *_context;
    BOOL _loaded;
    GSButton _buttonMask;
    double _sampleRate;

    /// 交错立体声输出缓冲（Nestopia 给的是单声道，这里扩成 L=R）
    int16_t *_stereoBuffer;

    /// 存档路径 + 上一次写盘的内容，用来判断「有没有变化」
    NSString *_savePath;
    NSData *_lastSavedImage;
    unsigned _framesSinceSaveCheck;
}

@synthesize delegate = _delegate;

+ (nullable id<GSEmulatorCore>)create {
    return [[GSNestopiaCore alloc] init];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _sampleRate = (double)kGSNestopiaSampleRate;
        _stereoBuffer = (int16_t *)calloc(kGSNestopiaMaxAudioFrames * 2, sizeof(int16_t));
    }
    return self;
}

- (void)dealloc {
    [self shutdown];
}

#pragma mark 协议属性

- (NSString *)coreName { return @"Nestopia"; }
- (NSString *)coreVersion { return @"Nestopia（Vendor/nestopia）"; }
- (double)sampleRate { return _sampleRate; }
- (BOOL)requiresJIT { return NO; }

- (double)framesPerSecond {
    if (!_context) {
        return 60.0988;
    }
    // 帧率 = 点时钟 / 每帧的点数。Api::Machine 把这两个常量直接暴露出来了，
    // 与上游 libretro 前端算的是同一个式子（CLK_DOT / CLK_VSYNC）。
    const double dots = _context->isPAL ? (double)Nes::Api::Machine::CLK_PAL_DOT
                                        : (double)Nes::Api::Machine::CLK_NTSC_DOT;
    const double vsync = _context->isPAL ? (double)Nes::Api::Machine::CLK_PAL_VSYNC
                                         : (double)Nes::Api::Machine::CLK_NTSC_VSYNC;
    if (dots <= 0 || vsync <= 0) {
        return _context->isPAL ? 50.0070 : 60.0988;
    }
    return dots / vsync;
}

- (size_t)videoWidth { return (size_t)kGSNestopiaVideoWidth; }
- (size_t)videoHeight { return (size_t)kGSNestopiaVideoHeight; }

#pragma mark 载入 / 卸载

- (BOOL)loadROMAtPath:(NSString *)path savePath:(NSString *)savePath error:(NSError **)error {
    if (_loaded) {
        if (error) {
            *error = [self errorWithText: @"这个核心上一次的 ROM 还没卸载"];
        }
        return NO;
    }
    if (path.length == 0) {
        if (error) {
            *error = [self errorWithText: @"ROM 路径为空"];
        }
        return NO;
    }

    std::ifstream rom(path.fileSystemRepresentation, std::ios::in | std::ios::binary);
    if (!rom.is_open()) {
        if (error) {
            *error = [self errorWithText: @"打不开这个 ROM 文件"];
        }
        return NO;
    }

    GSNestopiaContext *context = new (std::nothrow) GSNestopiaContext();
    if (!context) {
        if (error) {
            *error = [self errorWithText: @"内存不足，无法创建核心"];
        }
        return NO;
    }
    context->videoBuffer = (uint32_t *)calloc((size_t)kGSNestopiaVideoWidth * kGSNestopiaVideoHeight,
                                             sizeof(uint32_t));
    context->audioBuffer = (int16_t *)calloc(kGSNestopiaMaxAudioFrames, sizeof(int16_t));
    context->emulator = new (std::nothrow) Nes::Api::Emulator();
    if (!context->videoBuffer || !context->audioBuffer || !context->emulator) {
        if (error) {
            *error = [self errorWithText: @"显存 / 内存不足，无法创建 Nestopia 运行时"];
        }
        [self destroyContext: context];
        return NO;
    }

    Nes::Api::Machine machine(*context->emulator);

    // 载入卡带映像。上游用 Machine::Load(istream, FavoredSystem)；
    // FavoredSystem 只在核心自己判断不出机型时才起作用（这里不做强制）。
    Nes::Result result = machine.Load(rom, Nes::Api::Machine::FAVORED_NES_NTSC);
    if (NES_FAILED(result)) {
        if (error) {
            *error = [self errorWithText:
                [NSString stringWithFormat: @"Nestopia 认不出这个 ROM（错误码 %d）："
                    @"文件可能损坏，或扩展名与实际内容不符；Famicom 磁碟机（.fds）还需要 BIOS，本版本不含 BIOS",
                    (int)result]];
        }
        [self destroyContext: context];
        return NO;
    }

    // 画面：32bpp + RGBA 掩码（见文件头的说明）
    {
        Nes::Api::Video video(*context->emulator);
        Nes::Api::Video::RenderState state;
        state.filter = Nes::Api::Video::RenderState::FILTER_NONE;
        state.width = (Nes::ushort)kGSNestopiaVideoWidth;
        state.height = (Nes::ushort)kGSNestopiaVideoHeight;
        state.bits.count = 32;
        state.bits.mask.r = 0x000000FFu;
        state.bits.mask.g = 0x0000FF00u;
        state.bits.mask.b = 0x00FF0000u;
        video.SetRenderState(state);
    }
    context->video = new (std::nothrow) Nes::Api::Video::Output(
        (void *)context->videoBuffer, (long)(kGSNestopiaVideoWidth * sizeof(uint32_t)));
    if (!context->video) {
        if (error) {
            *error = [self errorWithText: @"内存不足，无法创建视频输出"];
        }
        [self destroyContext: context];
        return NO;
    }

    // 声音：采样率与音量（各通道按默认音量）
    {
        Nes::Api::Sound sound(*context->emulator);
        sound.SetSampleRate((Nes::ulong)kGSNestopiaSampleRate);
        sound.SetVolume(Nes::Api::Sound::ALL_CHANNELS, Nes::Api::Sound::DEFAULT_VOLUME);
    }

    // NTSC / PAL 由映像自己决定（不做强制），帧长决定每帧要留多少音频采样
    machine.SetMode(machine.GetDesiredMode());
    context->isPAL = (machine.GetMode() == Nes::Api::Machine::PAL);
    context->audioSamplesPerFrame = kGSNestopiaSampleRate / (context->isPAL ? 50u : 60u);
    context->audio = new (std::nothrow) Nes::Api::Sound::Output(
        context->audioBuffer, context->audioSamplesPerFrame);
    context->input = new (std::nothrow) Nes::Api::Input::Controllers();
    if (!context->audio || !context->input) {
        if (error) {
            *error = [self errorWithText: @"内存不足，无法创建音频 / 输入通道"];
        }
        [self destroyContext: context];
        return NO;
    }

    // 手柄：让核心按当前卡带自动选好控制器（我们的虚拟手柄就是标准 Pad 1）
    Nes::Api::Input(*context->emulator).AutoSelectControllers();

    _context = context;
    _buttonMask = 0;
    _savePath = [savePath copy];
    [self restoreBatteryImage];
    _lastSavedImage = [self batteryImage];
    _framesSinceSaveCheck = 0;

    // 上电（上游是 Load → 各种设置 → AutoSelectControllers → Power(true)）
    machine.Power(true);
    _loaded = YES;
    return YES;
}

/// Nestopia 把 ROM、存档、渲染器都在 Machine 的析构里一起回收，
/// 所以这里刻意什么都不做，卸载统一走 shutdown（与 mGBA 胶水同一套约定）。
- (void)unloadROM {
}

- (void)shutdown {
    [self flushBatteryImageIfNeeded: YES];
    _savePath = nil;
    _lastSavedImage = nil;
    if (_context) {
        [self destroyContext: _context];
        _context = NULL;
    }
    _loaded = NO;
    _buttonMask = 0;
    _delegate = nil;
    free(_stereoBuffer);
    _stereoBuffer = NULL;
}

/// 释放一整套运行时。顺序跟创建相反，任何一步都不能少（否则 Nestopia 内部的
/// 回调表 / 静态 callback 会留下悬空指针）。
- (void)destroyContext:(GSNestopiaContext *)context {
    if (!context) {
        return;
    }
    if (context->input) {
        // 上游在卸载时也会把这些静态回调清掉，这里虽然没设置过，一并做掉更稳妥
        Nes::Api::Input::Controllers::Pad::callback.Unset();
        delete context->input;
        context->input = NULL;
    }
    if (context->audio) {
        delete context->audio;
        context->audio = NULL;
    }
    if (context->video) {
        delete context->video;
        context->video = NULL;
    }
    if (context->emulator) {
        delete context->emulator;
        context->emulator = NULL;
    }
    free(context->audioBuffer);
    context->audioBuffer = NULL;
    free(context->videoBuffer);
    context->videoBuffer = NULL;
    delete context;
}

#pragma mark 每帧

- (void)runFrame {
    if (!_context || !_context->emulator || !_loaded) {
        return;
    }

    _context->input->pad[0].buttons = [self nestopiaPadButtons];
    // 每一帧都要重新「下单」：length[0] 返回的是实际写入量，留着不动会把请求越压越小
    _context->audio->length[0] = _context->audioSamplesPerFrame;
    _context->video->pixels = (void *)_context->videoBuffer;
    _context->video->pitch = (long)(kGSNestopiaVideoWidth * sizeof(uint32_t));

    _context->emulator->Execute(_context->video, _context->audio, _context->input);

    unsigned frames = _context->audio->length[0];
    if (frames > kGSNestopiaMaxAudioFrames) {
        frames = kGSNestopiaMaxAudioFrames;
    }
    if (frames > 0 && _stereoBuffer) {
        for (unsigned i = 0; i < frames; i++) {
            int16_t sample = _context->audioBuffer[i];
            _stereoBuffer[i * 2] = sample;
            _stereoBuffer[i * 2 + 1] = sample;
        }
        [self.delegate coreDidProduceAudioSamples: _stereoBuffer count: (size_t)frames * 2];
    }

    [self.delegate coreDidRenderFrameRGBA8888: (const uint8_t *)_context->videoBuffer
                                        width: (size_t)kGSNestopiaVideoWidth
                                       height: (size_t)kGSNestopiaVideoHeight
                                       stride: (size_t)(kGSNestopiaVideoWidth * sizeof(uint32_t))];

    if (++_framesSinceSaveCheck >= kGSNestopiaSaveCheckInterval) {
        _framesSinceSaveCheck = 0;
        [self flushBatteryImageIfNeeded: NO];
    }
}

- (void)setButtonMask:(GSButton)mask {
    _buttonMask = mask;
}

#pragma mark 按键映射

/// GSButton 的位序是按 mGBA 定的，和 Nestopia 的 Pad 位不一样，必须显式翻一遍：
///   GSButton: A=bit0 B=bit1 SELECT=bit2 START=bit3 RIGHT=bit4 LEFT=bit5 UP=bit6 DOWN=bit7
///   Pad:      A=0x01 B=0x02 SELECT=0x04 START=0x08 UP=0x10    DOWN=0x20  LEFT=0x40  RIGHT=0x80
- (unsigned)nestopiaPadButtons {
    unsigned buttons = 0;
    if (_buttonMask & GSButtonA)      { buttons |= Nes::Api::Input::Controllers::Pad::A; }
    if (_buttonMask & GSButtonB)      { buttons |= Nes::Api::Input::Controllers::Pad::B; }
    if (_buttonMask & GSButtonSelect) { buttons |= Nes::Api::Input::Controllers::Pad::SELECT; }
    if (_buttonMask & GSButtonStart)  { buttons |= Nes::Api::Input::Controllers::Pad::START; }
    if (_buttonMask & GSButtonUp)     { buttons |= Nes::Api::Input::Controllers::Pad::UP; }
    if (_buttonMask & GSButtonDown)   { buttons |= Nes::Api::Input::Controllers::Pad::DOWN; }
    if (_buttonMask & GSButtonLeft)   { buttons |= Nes::Api::Input::Controllers::Pad::LEFT; }
    if (_buttonMask & GSButtonRight)  { buttons |= Nes::Api::Input::Controllers::Pad::RIGHT; }
    return buttons;
}

#pragma mark 电池存档

/// 把所有「电池备份 + 可写 + 有实体指针」的内存块按索引顺序拼成一份映像。
/// 没有电池的卡带返回 nil（那就没什么可存的）。
- (nullable NSData *)batteryImage {
    if (!_context || !_context->emulator) {
        return nil;
    }
    Nes::Api::Memory memory(*_context->emulator);
    Nes::ulong count = memory.NumRegions();

    NSUInteger total = 0;
    for (Nes::ulong i = 0; i < count; i++) {
        Nes::Api::Memory::Region region = memory.GetRegion(i);
        if (region.data && region.size && region.battery && region.writable) {
            total += (NSUInteger)region.size;
        }
    }
    if (total == 0) {
        return nil;
    }

    NSMutableData *image = [NSMutableData dataWithLength: total];
    uint8_t *out = (uint8_t *)image.mutableBytes;
    for (Nes::ulong i = 0; i < count; i++) {
        Nes::Api::Memory::Region region = memory.GetRegion(i);
        if (region.data && region.size && region.battery && region.writable) {
            memcpy(out, region.data, (size_t)region.size);
            out += region.size;
        }
    }
    return image;
}

/// 把 .sav 的内容按同一顺序灌回内存块（长度对不上就整体放弃，不去猜）
- (void)restoreBatteryImage {
    if (_savePath.length == 0 || !_context || !_context->emulator) {
        return;
    }
    NSData *saved = [NSData dataWithContentsOfFile: _savePath];
    if (saved.length == 0) {
        return;
    }

    Nes::Api::Memory memory(*_context->emulator);
    Nes::ulong count = memory.NumRegions();

    NSUInteger total = 0;
    for (Nes::ulong i = 0; i < count; i++) {
        Nes::Api::Memory::Region region = memory.GetRegion(i);
        if (region.data && region.size && region.battery && region.writable) {
            total += (NSUInteger)region.size;
        }
    }
    if (total != saved.length) {
        return;
    }

    const uint8_t *in = (const uint8_t *)saved.bytes;
    for (Nes::ulong i = 0; i < count; i++) {
        Nes::Api::Memory::Region region = memory.GetRegion(i);
        if (region.data && region.size && region.battery && region.writable) {
            memcpy(region.data, in, (size_t)region.size);
            in += region.size;
        }
    }
}

/// 电池存档变了才写回文件；force=YES 用于退出 / 卸载前的那一次。
- (void)flushBatteryImageIfNeeded:(BOOL)force {
    if (_savePath.length == 0) {
        return;
    }
    NSData *image = [self batteryImage];
    if (!image) {
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

id<GSEmulatorCore> GSNestopiaCoreCreate(void) {
    return [GSNestopiaCore create];
}

#endif /* GS_HAVE_NESTOPIA */
