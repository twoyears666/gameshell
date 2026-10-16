//
//  GSIconStore.h
//  Gameshell
//
//  App 内导入的本地图标存储：图片写进沙盒 `Documents/Icons/<identifier>.<ext>`，
//  条目里只记相对 Documents 的路径（"Icons/<identifier>.<ext>"），换沙盒 / 换机器
//  都不会因为绝对路径失效。
//
//  同一份路径解析也供「模拟器封面」缓存（"Covers/..."）复用，所以这里只做
//  「相对路径 ↔ 绝对文件 URL」的转换，不关心调用方是谁。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface GSIconStore : NSObject

+ (instancetype)sharedStore NS_SWIFT_NAME(shared);

/// 图标根目录 Documents/Icons（会自动创建）
+ (nullable NSURL *)iconsRootURL;

/// 把图片数据写进 Documents/Icons/<identifier>.<ext>，返回相对路径 "Icons/<identifier>.<ext>"。
/// 同一 identifier 已有旧图标时会先删掉（避免残留不同扩展名的旧文件）。
+ (nullable NSString *)storeIconData:(NSData *)data
                       fileExtension:(nullable NSString *)fileExtension
                       forIdentifier:(NSString *)identifier;

/// 删除某条目的图标（尝试常见扩展名），返回是否至少删掉了一个
+ (BOOL)removeIconForIdentifier:(NSString *)identifier;

/// 把 "Icons/xxx.png" / "Covers/gba/xxx.png" 这类相对 Documents 的路径解析成绝对文件 URL
+ (nullable NSURL *)absoluteURLForRelativePath:(NSString *)relativePath;

@end

NS_ASSUME_NONNULL_END
