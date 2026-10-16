//
//  GSPlayHistory.h
//  Gameshell
//
//  「最近游玩」记录：主界面顶排就是靠它排出来的。
//
//  只记录两样东西：条目的 identifier 与种类（URL 条目 / ROM），加上最后一次游玩的
//  时间戳。条目本身（名称 / 封面 / URL）仍由清单与 ROM 库自己提供，这里不复制，
//  避免两份数据打架——找不到的条目在 UI 侧直接跳过。
//
//  持久化在沙盒 `Documents/play_history.json`，只保留最近 N 条。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 记录的种类：URL 条目（games.json）还是模拟器 ROM（Documents/ROMs）
typedef NS_ENUM(NSInteger, GSPlayHistoryKind) {
    GSPlayHistoryKindURL = 0,
    GSPlayHistoryKindROM = 1,
};

/// 一条「最近游玩」记录
@interface GSPlayHistoryEntry : NSObject

/// 对应 GSGame.identifier 或 GSROM.identifier
@property (nonatomic, copy, readonly) NSString *identifier;
@property (nonatomic, assign, readonly) GSPlayHistoryKind kind;
/// 最后一次游玩的时间（unix 时间戳，秒）
@property (nonatomic, assign, readonly) NSTimeInterval lastPlayedAt;

@end

@interface GSPlayHistory : NSObject

+ (instancetype)sharedHistory NS_SWIFT_NAME(shared());

/// 记一次游玩：已存在则刷新时间并提到最前，不存在则新建；顺带裁剪到上限
- (void)recordIdentifier:(NSString *)identifier kind:(GSPlayHistoryKind)kind;

/// 按时间倒序取最近 limit 条
- (NSArray<GSPlayHistoryEntry *> *)recentEntriesWithLimit:(NSUInteger)limit;

/// 删除某条记录（条目被删时调用）
- (void)removeIdentifier:(NSString *)identifier;

- (void)clear;

+ (NSUInteger)historyLimit;

@end

NS_ASSUME_NONNULL_END
