//
//  GSMGBACore.m
//  Gameshell
//
//  mGBA 静态库的宿主胶水层（GBA / GB / GBC）。
//
//  为什么用 ObjC 写：
//  1) 核心是纯 C 库（libmgba.a），ObjC 直接调它的 C API 最省事；
//  2) 协议里的 delegate 回调是 ObjC 对象，用 ObjC 把 C 回调桥回对象最自然。
//  （真正需要 ObjC 的 JIT 链路在 GSEmulator.m / 未来的 Wii、3DS、Wii U 核心里。）
//
//  颜色：库按默认配置编译，没有定义 COLOR_16_BIT / COLOR_5_6_5，所以 mColor 是
//  32 位整数 0xAABBGGRR —— 在小端内存里字节序正好是 R,G,B,A，也就是 RGBA8888，
//  宿主可以直接按 RGBA8888 读，不需要任何颜色转换。
//
//  参考：mGBA 官方 libretro 胶水（Vendor/mgba/src/platform/libretro/libretro.c）
//  给出了核心生命周期与音频回调的权威用法。
//

#import "GSBuiltCoresCompat.h"

#if GS_HAVE_MGBA

#import "GSEmulator.h"
#import "GSSystem.h"

// 下面两个宏必须和 Scripts/build_cores.sh 编 mGBA 静态库时的配置一致：
// CMake 会把 ENABLE_VFS、ENABLE_DIRECTORIES 放进 FEATURE_DEFINES 传给核心源码
// （CMakeLists.txt 第 356 行 set(ENABLE_VFS ON)，第 882-892 行拼出 ENABLE_VFS;ENABLE_DIRECTORIES），
// 而 struct mCore / struct mDirectorySet 的成员布局正是由它们决定的
// （core.h 第 45 行、directories.h 第 13 行）。
// 漏定义的话，宿主看到的 struct mCore 成员偏移就和库里的对不上 —— ABI 不一致，会直接读错内存。
//
// 另外两个容易搞混的宏，这里刻意都不定义：
//  - MINIMAL_CORE：CMake 里的 MINIMAL_CORE 只决定「编哪些源文件」，
//    它并不作为编译宏传给核心源码（flags.h 只有 src/platform/python 在 include），
//    所以库里根本没有这个宏，宿主也不能有；
//  - ENABLE_DEBUGGERS：脚本里显式 -DENABLE_DEBUGGERS=OFF，库里同样没有。
#define ENABLE_VFS 1
#define ENABLE_DIRECTORIES 1

#import <mgba/core/core.h>
#import <mgba/core/config.h>
#import <mgba/core/interface.h>
#import <mgba/core/serialize.h>   // mCoreSaveStateNamed / SAVESTATE_*
#import <mgba-util/audio-buffer.h>
#import <mgba-util/image.h>
#import <mgba-util/vfs.h>          // VFileMemChunk / VFileFromConstMemory

/// 视频缓冲固定按最大尺寸分配：GBA 是 240x160，GB/GBC 是 160x144
static const unsigned kGSMGBAVideoStride = 240;
static const unsigned kGSMGBAVideoHeightMax = 160;

/// mGBA 内部音频缓冲的阈值（采样帧数）。给到 >= 一帧的量即可，
/// 太小会频繁回调，太大则增加延迟。
static const size_t kGSMGBAInternalAudioSamples = 1024;
/// 一次从 mGBA 缓冲里最多取多少采样帧
static const size_t kGSMGBAAudioDrainFrames = 2048;

/// 即时存档要包含哪些区块。取「电池存档 + 实时时钟」，与 mGBA 自己的
/// rewind 功能（src/core/rewind.c 的 mCoreRewindAppend）用的是同一组 flag；
/// 刻意不含截图 / 元数据（那些是给「存档缩略图」用的，我们不需要）。
static const int kGSMGBASaveStateFlags = SAVESTATE_SAVEDATA | SAVESTATE_RTC;

#pragma mark - 基础类型

/// mAVStream 没有 userdata 字段，所以把 stream 放在自定义结构体第一个成员，
/// 靠「首成员地址 == 结构体地址」把回调里的 stream* 还原成宿主对象。
typedef struct GSMGBAStream {
	struct mAVStream stream;
	void *owner; // (__bridge GSMGBACore *)，不持有所有权
} GSMGBAStream;

/// 完整接口声明必须放在 C 回调之前：回调里要给这个类发消息，只写 @class 前向声明是不够的。
@interface GSMGBACore : NSObject <GSEmulatorCore>
- (void)handleAudioBuffer:(struct mAudioBuffer *)buffer;
- (void)handleAudioRateChanged:(unsigned)rate;
@end

#pragma mark - C 回调

static void _GSMGBAPostAudioBuffer(struct mAVStream *stream, struct mAudioBuffer *buffer) {
	GSMGBACore *owner = (__bridge GSMGBACore *)((GSMGBAStream *)stream)->owner;
	if (!owner) {
		return;
	}
	[owner handleAudioBuffer: buffer];
}

static void _GSMGBAAudioRateChanged(struct mAVStream *stream, unsigned rate) {
	GSMGBACore *owner = (__bridge GSMGBACore *)((GSMGBAStream *)stream)->owner;
	if (!owner) {
		return;
	}
	[owner handleAudioRateChanged: rate];
}

#pragma mark - 核心

@implementation GSMGBACore {
	struct mCore *_core;
	mColor *_videoBuffer;
	GSMGBAStream _streamWrapper;
	int16_t *_audioDrain;

	unsigned _videoWidth;
	unsigned _videoHeight;
	double _sampleRate;
	BOOL _loaded;
}
@synthesize delegate = _delegate;

+ (nullable id<GSEmulatorCore>)create {
	return [[GSMGBACore alloc] init];
}

- (instancetype)init {
	self = [super init];
	if (self) {
		_audioDrain = calloc(kGSMGBAAudioDrainFrames * 2, sizeof(int16_t));
		_streamWrapper.stream.postAudioBuffer = _GSMGBAPostAudioBuffer;
		_streamWrapper.stream.audioRateChanged = _GSMGBAAudioRateChanged;
		_streamWrapper.owner = (__bridge void *)self;
	}
	return self;
}

- (void)dealloc {
	[self shutdown];
}

#pragma mark 协议属性

- (NSString *)coreName { return @"mGBA"; }
- (NSString *)coreVersion { return @"mGBA（Vendor/mgba）"; }
- (double)sampleRate { return _sampleRate; }
- (BOOL)requiresJIT { return NO; }

- (double)framesPerSecond {
	if (!_core) {
		return 60.0;
	}
	int32_t frequency = _core->frequency(_core);
	int32_t cycles = _core->frameCycles(_core);
	if (frequency <= 0 || cycles <= 0) {
		return 60.0;
	}
	// 帧率 = 主频 / 每帧周期数（GBA ≈ 59.73，GB ≈ 59.73）
	return (double)frequency / (double)cycles;
}

- (size_t)videoWidth { return _videoWidth ?: kGSMGBAVideoStride; }
- (size_t)videoHeight { return _videoHeight ?: kGSMGBAVideoHeightMax; }

#pragma mark 载入 / 卸载

/// 按文件扩展名决定用哪个核心：gba -> GBA，gb/gbc -> GB
- (enum mPlatform)platformForPath:(NSString *)path {
	GSSystemInfo *info = [GSSystemRegistry infoForFileName: path.lastPathComponent ?: @""];
	switch (info.system) {
		case GSSystemGBA:
			return mPLATFORM_GBA;
		case GSSystemGB:
		case GSSystemGBC:
			return mPLATFORM_GB;
		default:
			break;
	}
	// 扩展名认不出时按 GBA 试一次（ROM 内容不对的话核心自己会拒）
	return mPLATFORM_GBA;
}

- (BOOL)loadROMAtPath:(NSString *)path savePath:(NSString *)savePath error:(NSError **)error {
	if (_loaded) {
		if (error) {
			*error = [NSError errorWithDomain: @"GSEmulatorErrorDomain" code: 1
			                         userInfo: @{NSLocalizedDescriptionKey: @"这个核心上一次的 ROM 还没卸载"}];
		}
		return NO;
	}
	if (path.length == 0) {
		if (error) {
			*error = [NSError errorWithDomain: @"GSEmulatorErrorDomain" code: 1
			                         userInfo: @{NSLocalizedDescriptionKey: @"ROM 路径为空"}];
		}
		return NO;
	}

	_core = mCoreCreate([self platformForPath: path]);
	if (!_core) {
		if (error) {
			*error = [NSError errorWithDomain: @"GSEmulatorErrorDomain" code: 1
			                         userInfo: @{NSLocalizedDescriptionKey: @"mGBA 没有可用的核心"}];
		}
		return NO;
	}

	mCoreInitConfig(_core, NULL);
	if (!_core->init(_core)) {
		if (error) {
			*error = [NSError errorWithDomain: @"GSEmulatorErrorDomain" code: 1
			                         userInfo: @{NSLocalizedDescriptionKey: @"mGBA 核心初始化失败"}];
		}
		[self teardown];
		return NO;
	}

	// 视频缓冲：按最大尺寸分配，GB 的 160x144 也落在里面
	_videoBuffer = malloc((size_t)kGSMGBAVideoStride * kGSMGBAVideoHeightMax * sizeof(mColor));
	if (!_videoBuffer) {
		if (error) {
			*error = [NSError errorWithDomain: @"GSEmulatorErrorDomain" code: 1
			                         userInfo: @{NSLocalizedDescriptionKey: @"显存不足，无法创建视频缓冲"}];
		}
		[self teardown];
		return NO;
	}
	memset(_videoBuffer, 0xFF, (size_t)kGSMGBAVideoStride * kGSMGBAVideoHeightMax * sizeof(mColor));
	_core->setVideoBuffer(_core, _videoBuffer, kGSMGBAVideoStride);

	_core->setAudioBufferSize(_core, kGSMGBAInternalAudioSamples);
	_core->setAVStream(_core, &_streamWrapper.stream);

	// 载入 ROM 本体（mCoreLoadFile 内部会 VFileOpen + loadROM，失败时自己关文件）
	if (!mCoreLoadFile(_core, path.fileSystemRepresentation)) {
		if (error) {
			*error = [NSError errorWithDomain: @"GSEmulatorErrorDomain" code: 1
			                         userInfo: @{NSLocalizedDescriptionKey:
			                             @"mGBA 认不出这个 ROM（文件可能损坏，或扩展名与实际内容不符）"}];
		}
		[self teardown];
		return NO;
	}

	// 电池存档：文件不存在时会被创建。失败不致命（有些卡带本来就没有存档区）。
	if (savePath.length > 0) {
		mCoreLoadSaveFile(_core, savePath.fileSystemRepresentation, false);
	}

	_core->reset(_core);

	_loaded = YES;
	_sampleRate = (double)_core->audioSampleRate(_core);
	if (_sampleRate <= 0) {
		_sampleRate = 44100.0;
	}
	return YES;
}

/// mGBA 把 ROM、存档、渲染器全都在 deinit 里一起回收，
/// 所以这里刻意什么都不做，卸载统一走 shutdown。
/// （先 unloadROM 再 deinit 会导致存档被释放两次。）
- (void)unloadROM {
}

- (void)teardown {
	if (!_core) {
		return;
	}
	mCoreConfigDeinit(&_core->config);
	_core->deinit(_core);
	_core = NULL;
	_loaded = NO;

	free(_videoBuffer);
	_videoBuffer = NULL;
	_streamWrapper.owner = NULL;
	_delegate = nil;
}

- (void)shutdown {
	[self teardown];
	free(_audioDrain);
	_audioDrain = NULL;
}

#pragma mark 每帧

- (void)runFrame {
	if (!_core || !_loaded) {
		return;
	}
	_core->runFrame(_core);

	unsigned width = 0;
	unsigned height = 0;
	_core->currentVideoSize(_core, &width, &height);
	if (width == 0 || height == 0) {
		return;
	}
	_videoWidth = width;
	_videoHeight = height;

	// mColor 在小端内存里就是 R,G,B,A 四字节，直接当 RGBA8888 交出去
	[self.delegate coreDidRenderFrameRGBA8888: (const uint8_t *)_videoBuffer
	                                    width: (size_t)width
	                                   height: (size_t)height
	                                   stride: (size_t)kGSMGBAVideoStride * sizeof(mColor)];
}

- (void)setButtonMask:(GSButton)mask {
	if (!_core || !_loaded) {
		return;
	}
	// GSButton 的位序刻意与 mGBA 的 GBAKey / GBKey 对齐，可以直接传
	_core->setKeys(_core, (uint32_t)mask);
}

#pragma mark 即时存档

/// 取一份即时存档。用 VFileMemChunk 承接核心写出的状态 —— 它是一块会自动增长的
/// 匿名内存文件，写完再 map 出来拷成 NSData（写法与 mGBA 的 rewind 一致）。
- (nullable NSData *)copySaveState {
	if (!_core || !_loaded) {
		return nil;
	}
	struct VFile *vf = VFileMemChunk(NULL, 0);
	if (!vf) {
		return nil;
	}
	if (!mCoreSaveStateNamed(_core, vf, kGSMGBASaveStateFlags)) {
		vf->close(vf);
		return nil;
	}
	size_t size = (size_t)vf->size(vf);
	if (size == 0) {
		vf->close(vf);
		return nil;
	}
	void *bytes = vf->map(vf, size, MAP_READ);
	if (!bytes) {
		vf->close(vf);
		return nil;
	}
	NSData *data = [NSData dataWithBytes: bytes length: size];
	vf->unmap(vf, bytes, size);
	vf->close(vf);
	return data;
}

/// 读回时用 VFileFromConstMemory 包住 NSData 的字节。flag 必须与写入时一致，
/// 否则核心会按另一套区块布局去读，长度对不上就会失败。
- (BOOL)restoreSaveState:(NSData *)data {
	if (!_core || !_loaded || data.length == 0) {
		return NO;
	}
	struct VFile *vf = VFileFromConstMemory(data.bytes, (size_t)data.length);
	if (!vf) {
		return NO;
	}
	bool ok = mCoreLoadStateNamed(_core, vf, kGSMGBASaveStateFlags);
	vf->close(vf);
	return ok;
}

#pragma mark 音频（由 mGBA 在自己的音频线程里回调进来）

- (void)handleAudioBuffer:(struct mAudioBuffer *)buffer {
	if (!buffer || !_audioDrain) {
		return;
	}
	size_t produced = mAudioBufferRead(buffer, _audioDrain, kGSMGBAAudioDrainFrames);
	if (produced == 0) {
		return;
	}
	unsigned channels = buffer->channels ?: 2;
	[self.delegate coreDidProduceAudioSamples: _audioDrain count: produced * channels];
}

- (void)handleAudioRateChanged:(unsigned)rate {
	if (rate > 0) {
		_sampleRate = (double)rate;
	}
}

@end

id<GSEmulatorCore> GSMGBACoreCreate(void) {
	return [GSMGBACore create];
}

#endif /* GS_HAVE_MGBA */
