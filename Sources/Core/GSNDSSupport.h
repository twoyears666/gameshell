//
//  GSNDSSupport.h
//  Gameshell
//
//  NDS 专属支持：BIOS / 固件的导入与运行选项。
//
//  为什么 BIOS / 固件要单独导入：
//  1) bios7.bin / bios9.bin / firmware.bin 是任天堂的版权文件，不能随 App 分发，
//     只能由用户从自己的机器上导出，再用「文件」App 选进来；
//  2) 没有这三件套时，melonDS 会退回内部的 FreeBIOS + 合成固件，仍能直接进游戏；
//  3) 有 firmware.bin 时核心会读它取语言等默认值，但一律直启进游戏、不走固件菜单。
//
//  目录约定：Documents/Bios/{bios7.bin,bios9.bin,firmware.bin}。
//  melonDS 的 libretro 核心会去 GET_SYSTEM_DIRECTORY（我们答这个目录）下按文件名找它们，
//  所以文件名必须严格叫这三个。
//
//  运行选项（双屏布局 / JIT 加速）持久化在 Documents/nds.json。
//

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

/// NDS 双屏布局（运行时答给核心的 melonds_screen_layout）
typedef NS_ENUM(NSInteger, GSNDSScreenLayout) {
    /// 上下堆叠（默认，也是最经典的排布）
    GSNDSScreenLayoutTopBottom = 0,
    /// 左右并排
    GSNDSScreenLayoutLeftRight,
    /// 只显示上屏（此时没有触摸区）
    GSNDSScreenLayoutTopOnly,
    /// 只显示下屏（整块都是触摸区）
    GSNDSScreenLayoutBottomOnly,
};

/// 三个必要文件的固定名（顺序固定，UI 与核心都按这套来）
FOUNDATION_EXPORT NSString *const GSBiosFileName7;        // bios7.bin
FOUNDATION_EXPORT NSString *const GSBiosFileName9;        // bios9.bin
FOUNDATION_EXPORT NSString *const GSBiosFileNameFirmware; // firmware.bin

@interface GSNDSSupport : NSObject

+ (instancetype)shared NS_SWIFT_NAME(shared());

#pragma mark - BIOS / 固件（Documents/Bios/）

/// Documents/Bios（不存在会自动创建）
+ (NSURL *)biosDirectoryURL;
/// 某个固定名的文件是否存在
- (BOOL)hasBIOSFileNamed:(NSString *)name NS_SWIFT_NAME(hasBIOSFile(named:));
/// 把用户选中的文件复制进 Documents/Bios/ 并改名成 name（name 只允许上面三个常量）
- (BOOL)importBIOSFileAtURL:(NSURL *)url asName:(NSString *)name error:(NSError **)error
    NS_SWIFT_NAME(importBIOSFile(at:as:));
/// 删掉某个固定名的文件
- (void)removeBIOSFileNamed:(NSString *)name NS_SWIFT_NAME(removeBIOSFile(named:));

#pragma mark - 运行选项（Documents/nds.json）

/// 双屏布局（默认上下）
@property (nonatomic, assign) GSNDSScreenLayout screenLayout NS_SWIFT_NAME(screenLayout);

/// 说明：JIT 不设开关 —— 进程拿得到可执行内存就用（快），拿不到就退回解释器（慢但能跑），
/// 由胶水层按 GSJIT.probeStatus 自动决定，用户不需要操心。
/// 启动方式也不设开关 —— 一律直启进游戏，不走固件菜单。

- (void)persist;

#pragma mark - 给 melonDS 核心用的取值 / 几何

/// 答给核心 melonds_screen_layout 的字符串
- (NSString *)melonDSScreenLayoutValue;

/// 某布局下核心渲染缓冲的像素尺寸（无边框间隙，gap 恒为 0）
+ (CGSize)bufferSizeForLayout:(GSNDSScreenLayout)layout;
/// 某布局下「下屏」在缓冲里的归一化矩形（0–1；只上屏布局返回 CGRectNull）
+ (CGRect)bottomScreenNormalizedRectForLayout:(GSNDSScreenLayout)layout;
/// 把「下屏内的归一化坐标 (0–1)」换算成核心 libretro pointer 的 int16 坐标
+ (CGPoint)pointerForNormalizedTouch:(CGPoint)point layout:(GSNDSScreenLayout)layout;

@end

NS_ASSUME_NONNULL_END
