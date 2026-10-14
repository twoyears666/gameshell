#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 单个游戏条目。
/// 说明：UI 层不硬编码任何游戏，所有条目都由用户自己添加（App 内添加 / games.json）。
@interface GSGame : NSObject

@property (nonatomic, copy) NSString *identifier;      // 唯一 id
@property (nonatomic, copy) NSString *name;            // 显示名称
@property (nonatomic, copy) NSString *iconURLString;   // 图标（远程 URL / asset 名 / SF Symbol 名）
@property (nonatomic, copy) NSString *gameURLString;   // 游戏入口 URL —— URL 驱动的核心
@property (nonatomic, copy) NSString *platform;        // 由 URL 推导的标签：网页 / steam 等
@property (nonatomic, assign) BOOL controllerSupport;  // 是否支持手柄
@property (nonatomic, assign) double rating;           // 评分 0–10（仅解析入库，当前 UI 不展示）
@property (nonatomic, copy) NSString *summary;         // 简介（仅解析入库，当前 UI 不展示）
@property (nonatomic, copy) NSArray<NSString *> *tags; // 标签（仅解析入库，当前 UI 不展示）
@property (nonatomic, copy, nullable) NSString *accentHex; // 可选卡片强调色，如 "#FF7A18"

- (instancetype)initWithDictionary:(NSDictionary *)dictionary;

/// 回写成 JSON 用的字典（供持久化）
- (NSDictionary *)dictionaryRepresentation;

+ (NSArray<GSGame *> *)gamesFromArray:(NSArray *)array;

@end

/// 游戏清单：主界面方块行的数据来源。
/// 清单默认只有内置的那份空清单；用户在 App 内添加的条目会写入沙盒
/// `Documents/games.json`，下次启动优先读这一份。
@interface GSGameManifest : NSObject

@property (nonatomic, copy, readonly) NSString *title;
@property (nonatomic, copy, readonly) NSString *subtitle;
@property (nonatomic, copy, readonly) NSArray<GSGame *> *games;

- (instancetype)initWithDictionary:(NSDictionary *)dictionary;

/// 从 App Bundle 里加载，例如 @"games.json"
+ (nullable instancetype)manifestNamed:(NSString *)name
                              inBundle:(nullable NSBundle *)bundle
    NS_SWIFT_NAME(load(named:in:));

/// 从沙盒用户清单（Documents/games.json）加载；文件不存在时返回 nil
+ (nullable instancetype)loadFromUserStore NS_SWIFT_NAME(loadUserStore());

+ (nullable instancetype)manifestWithJSONData:(NSData *)data
                                        error:(NSError **)error;

+ (nullable instancetype)manifestWithJSONString:(NSString *)json
                                          error:(NSError **)error;

// MARK: - 增删与持久化（App 内添加 URL 的基础能力）

/// Swift 侧为 `add(_:)`
- (void)add:(GSGame *)game;

/// Swift 侧为 `removeGame(withIdentifier:)`
- (void)removeGameWithIdentifier:(NSString *)identifier;

/// 把当前清单写入沙盒 Documents/games.json，返回是否成功
- (BOOL)persistToUserStore;

/// 用户清单在沙盒里的位置：Documents/games.json
+ (NSURL *)userStoreURL;

@end

NS_ASSUME_NONNULL_END
