//
//  GSSystem.h
//  Gameshell
//
//  模拟器「系统」的注册表：扩展名 → 系统 → 计划使用的核心。
//  系统的划分与命名参照 RetroArch 的 system 概念，但核心接入方式是直接调用
//  各核心的 C API（不加载 libretro 动态库）——iOS 上动态库需要 dynamic-codesigning
//  权限，iOS 15 + A12 及以上已被系统封禁，所以核心一律静态链接进主二进制。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 支持（或计划支持）的模拟器系统
typedef NS_ENUM(NSInteger, GSSystem) {
    GSSystemUnknown = 0,
    GSSystemNES,    // Nintendo Entertainment System / Famicom
    GSSystemSNES,   // Super Nintendo Entertainment System
    GSSystemGB,     // Game Boy
    GSSystemGBC,    // Game Boy Color
    GSSystemGBA,    // Game Boy Advance
    GSSystemNDS,    // Nintendo DS
    GSSystem3DS,    // Nintendo 3DS
    GSSystemWii,    // Nintendo Wii
    GSSystemWiiU,   // Nintendo Wii U
};

/// 单个系统的元信息
@interface GSSystemInfo : NSObject

@property (nonatomic, assign, readonly) GSSystem system;
/// 系统标识，同时用作 ROM 子目录名：nes / snes / gb / gbc / gba / nds / 3ds / wii / wiiu
@property (nonatomic, copy, readonly) NSString *identifier;
/// 展示用全名，例如 "Game Boy Advance"
@property (nonatomic, copy, readonly) NSString *displayName;
/// 展示用短名，例如 "GBA"
@property (nonatomic, copy, readonly) NSString *shortName;
/// 该系统的 ROM 扩展名（不含点，小写），例如 @[@"gba"]
@property (nonatomic, copy, readonly) NSArray<NSString *> *fileExtensions;
/// 计划使用的核心名，例如 "mGBA"；无计划则为 nil
@property (nonatomic, copy, readonly, nullable) NSString *plannedCoreName;
/// 计划使用的核心许可证，例如 "MPL-2.0"（诚实标注，见 REFERENCE.md）
@property (nonatomic, copy, readonly, nullable) NSString *plannedCoreLicense;
/// 是否必须开启 JIT 才能运行（Wii / 3DS / Wii U 为 YES）
@property (nonatomic, assign, readonly) BOOL requiresJIT;
/// 该系统的核心当前是否已经真正接入主二进制（未接入的如实为 NO）
@property (nonatomic, assign, readonly) BOOL coreIntegrated;
/// 未接入时给用户看的说明；已接入为 nil
@property (nonatomic, copy, readonly, nullable) NSString *statusNote;

@end

/// 系统注册表
@interface GSSystemRegistry : NSObject

+ (GSSystemInfo *)infoForSystem:(GSSystem)system;
+ (nullable GSSystemInfo *)infoForIdentifier:(NSString *)identifier;
/// 按扩展名（可带点、大小写不限）查系统
+ (nullable GSSystemInfo *)infoForFileExtension:(NSString *)fileExtension;
/// 按文件名的扩展名查系统
+ (nullable GSSystemInfo *)infoForFileName:(NSString *)fileName;
/// 按 URL 的扩展名查系统
+ (nullable GSSystemInfo *)infoForFileURL:(NSURL *)url;

/// 全部系统（含仅占位的）
+ (NSArray<GSSystemInfo *> *)allSystems;
/// 已经真正接入核心、可以玩的系统
+ (NSArray<GSSystemInfo *> *)integratedSystems;
/// 被认作 ROM 的扩展名全集（用于文件选择器过滤）
+ (NSArray<NSString *> *)allROMFileExtensions;

@end

NS_ASSUME_NONNULL_END
