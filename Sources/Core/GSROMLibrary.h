//
//  GSROMLibrary.h
//  Gameshell
//
//  ROM 库：把用户自己的 ROM 文件放进沙盒里的 Documents/ROMs/<system>/，
//  App 只做「扫描 + 归类 + 导入 + 删除」，不内置、不带任何 ROM。
//

#import <Foundation/Foundation.h>
#import "GSSystem.h"

NS_ASSUME_NONNULL_BEGIN

/// 一条 ROM 记录（由文件系统扫描得到，不写进 games.json，避免两份数据打架）
@interface GSROM : NSObject

/// 唯一标识 = 相对 Documents/ROMs/ 的路径
@property (nonatomic, copy, readonly) NSString *identifier;
/// 去掉扩展名后的显示名
@property (nonatomic, copy, readonly) NSString *name;
/// 文件名（含扩展名）
@property (nonatomic, copy, readonly) NSString *fileName;
/// 相对 Documents/ROMs/ 的路径，例如 "gba/Pokemon.gba"
@property (nonatomic, copy, readonly) NSString *relativePath;
/// 绝对路径
@property (nonatomic, copy, readonly) NSString *absolutePath;
/// 识别出的系统；识别不出为 GSSystemUnknown
@property (nonatomic, assign, readonly) GSSystem system;
@property (nonatomic, assign, readonly) unsigned long long sizeBytes;

- (instancetype)initWithAbsolutePath:(NSString *)absolutePath relativePath:(NSString *)relativePath;

@end

@interface GSROMLibrary : NSObject

/// ROM 根目录：Documents/ROMs（会自动创建）
+ (NSURL *)romsRootURL;
/// 某个系统的目录：Documents/ROMs/<system identifier>
+ (NSURL *)directoryURLForSystem:(GSSystem)system;

/// 扫描 ROM 根目录（含各系统子目录），返回按系统 + 文件名排序的结果
+ (NSArray<GSROM *> *)allROMs;
/// 扫描指定目录
+ (NSArray<GSROM *> *)romsInDirectory:(NSURL *)directory;

/// 把外部文件（文件选择器给的 URL）复制进 Documents/ROMs/<system>/。
/// 会自动 startAccessingSecurityScopedResource。
+ (nullable GSROM *)importFileAtURL:(NSURL *)url error:(NSError **)error;

/// 删除一条 ROM（只删它自己）
+ (BOOL)deleteROM:(GSROM *)rom error:(NSError **)error;

/// 电池存档 .sav 的存放位置（与 ROM 同目录、同名）
+ (NSURL *)batterySaveURLForROM:(GSROM *)rom;

/// 错误域
FOUNDATION_EXPORT NSString *const GSROMLibraryErrorDomain;

@end

NS_ASSUME_NONNULL_END
