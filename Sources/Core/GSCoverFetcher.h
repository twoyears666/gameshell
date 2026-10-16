//
//  GSCoverFetcher.h
//  Gameshell
//
//  模拟器 ROM 的封面：按 ROM 文件名去 libretro-thumbnails 匹配官方「盒装封面」
//  （Named_Boxarts），命中就缓存到沙盒 `Documents/Covers/<系统>/<文件名>.png`，
//  之后离线也能用；没命中就静默回退到系统徽标，不报错、不提示。
//
//  封面源：https://thumbnails.libretro.com/<系统目录>/Named_Boxarts/<游戏名>.png
//  不依赖任何 API key，也没有官方接口；匹配靠文件名，属于「尽力而为」。
//

#import <Foundation/Foundation.h>
#import "GSSystem.h"
#import "GSROMLibrary.h"

NS_ASSUME_NONNULL_BEGIN

@interface GSCoverFetcher : NSObject

+ (instancetype)sharedFetcher NS_SWIFT_NAME(shared);

/// 该系统在 libretro-thumbnails 上的目录名（例如 "Nintendo - Game Boy Advance"）；
/// 没有对应目录的系统返回 nil
+ (nullable NSString *)thumbnailDirectoryForSystem:(GSSystem)system;

/// 已经缓存好的封面（相对 Documents 的路径，例如 "Covers/gba/Pokemon.gba.png"）；没有返回 nil
+ (nullable NSString *)cachedCoverRelativePathForROM:(GSROM *)rom;

/// 批量抓取封面。limit 限制一次最多抓多少张（避免几十个请求一起发）。
/// 每张成功都会回调 progress(rom.identifier, 相对路径)；全部结束后回调 completion。
- (void)fetchCoversForROMs:(NSArray<GSROM *> *)roms
                     limit:(NSUInteger)limit
                  progress:(nullable void (^)(NSString *romIdentifier, NSString *relativePath))progress
                completion:(nullable void (^)(void))completion
    NS_SWIFT_NAME(fetchCovers(roms:limit:progress:completion:));

/// 取消当前这批抓取（未开始的任务不会再发请求）
- (void)cancel;

@end

NS_ASSUME_NONNULL_END
