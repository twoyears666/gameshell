#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 单个游戏条目。
/// 说明：UI 层不硬编码任何游戏，所有条目均由 games.json（manifest）驱动，
/// 便于后续做主题包 / 在线更新。
@interface GSGame : NSObject

@property (nonatomic, copy) NSString *identifier;      // 唯一 id
@property (nonatomic, copy) NSString *name;            // 显示名称
@property (nonatomic, copy) NSString *iconURLString;   // 图标（远程 URL / asset 名 / SF Symbol 名）
@property (nonatomic, copy) NSString *gameURLString;   // 游戏入口 URL —— URL 驱动的核心
@property (nonatomic, copy) NSString *platform;        // 平台标签：iOS / Web / 云 / PC
@property (nonatomic, assign) BOOL controllerSupport;  // 是否支持手柄
@property (nonatomic, assign) double rating;           // 评分 0–10
@property (nonatomic, copy) NSString *summary;         // 一句话简介
@property (nonatomic, copy) NSArray<NSString *> *tags; // 标签
@property (nonatomic, copy, nullable) NSString *accentHex; // 可选卡片强调色，如 "#FF7A18"

- (instancetype)initWithDictionary:(NSDictionary *)dictionary;
+ (NSArray<GSGame *> *)gamesFromArray:(NSArray *)array;

@end

/// 游戏清单：整个游戏库的数据来源。
@interface GSGameManifest : NSObject

@property (nonatomic, copy, readonly) NSString *title;
@property (nonatomic, copy, readonly) NSString *subtitle;
@property (nonatomic, copy, readonly) NSArray<GSGame *> *games;
@property (nonatomic, copy, readonly) NSArray<NSString *> *categories; // 分类 chips

- (instancetype)initWithDictionary:(NSDictionary *)dictionary;

/// 从 App Bundle 里加载，例如 @"games.json"
+ (nullable instancetype)manifestNamed:(NSString *)name
                              inBundle:(nullable NSBundle *)bundle
    NS_SWIFT_NAME(load(named:in:));

+ (nullable instancetype)manifestWithJSONData:(NSData *)data
                                        error:(NSError **)error;

+ (nullable instancetype)manifestWithJSONString:(NSString *)json
                                          error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
