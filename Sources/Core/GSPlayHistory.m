#import "GSPlayHistory.h"

@interface GSPlayHistoryEntry ()
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, assign) GSPlayHistoryKind kind;
@property (nonatomic, assign) NSTimeInterval lastPlayedAt;
@end

@implementation GSPlayHistoryEntry
@end

#pragma mark -

@interface GSPlayHistory ()
@property (nonatomic, strong) NSMutableArray<GSPlayHistoryEntry *> *entries;

- (void)loadFromDisk;
- (void)persist;
- (void)removeEntryWithIdentifier:(NSString *)identifier;
@end

@implementation GSPlayHistory

+ (instancetype)sharedHistory {
    static GSPlayHistory *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[GSPlayHistory alloc] init];
    });
    return shared;
}

+ (NSUInteger)historyLimit {
    return 50;
}

+ (NSURL *)storeURL {
    NSURL *directory = [[NSFileManager defaultManager]
        URLForDirectory: NSDocumentDirectory
               inDomain: NSUserDomainMask
      appropriateForURL: nil
                 create: YES
                  error: NULL];
    if (directory == nil) {
        return nil;
    }
    return [directory URLByAppendingPathComponent: @"play_history.json"];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _entries = [NSMutableArray array];
        [self loadFromDisk];
    }
    return self;
}

#pragma mark - 读写

- (void)loadFromDisk {
    NSURL *url = [GSPlayHistory storeURL];
    if (url == nil) {
        return;
    }
    NSData *data = [NSData dataWithContentsOfURL: url];
    if (data == nil) {
        return;
    }
    id object = [NSJSONSerialization JSONObjectWithData: data options: 0 error: NULL];
    if (![object isKindOfClass: [NSArray class]]) {
        return;
    }

    NSMutableArray<GSPlayHistoryEntry *> *loaded = [NSMutableArray array];
    for (id item in (NSArray *)object) {
        if (![item isKindOfClass: [NSDictionary class]]) {
            continue;
        }
        NSDictionary *dictionary = item;
        NSString *identifier = dictionary[@"identifier"];
        if (![identifier isKindOfClass: [NSString class]] || identifier.length == 0) {
            continue;
        }
        GSPlayHistoryEntry *entry = [[GSPlayHistoryEntry alloc] init];
        entry.identifier = identifier;

        NSString *kind = dictionary[@"kind"];
        entry.kind = ([kind isKindOfClass: [NSString class]] && [kind isEqualToString: @"rom"])
            ? GSPlayHistoryKindROM
            : GSPlayHistoryKindURL;

        id timestamp = dictionary[@"lastPlayedAt"];
        entry.lastPlayedAt = [timestamp isKindOfClass: [NSNumber class]] ? [timestamp doubleValue] : 0;
        [loaded addObject: entry];
    }

    [loaded sortUsingComparator: ^NSComparisonResult(GSPlayHistoryEntry *a, GSPlayHistoryEntry *b) {
        if (a.lastPlayedAt > b.lastPlayedAt) { return NSOrderedAscending; }
        if (a.lastPlayedAt < b.lastPlayedAt) { return NSOrderedDescending; }
        return NSOrderedSame;
    }];
    self.entries = loaded;
}

- (void)persist {
    NSURL *url = [GSPlayHistory storeURL];
    if (url == nil) {
        return;
    }
    NSMutableArray *raw = [NSMutableArray arrayWithCapacity: self.entries.count];
    for (GSPlayHistoryEntry *entry in self.entries) {
        [raw addObject: @{
            @"identifier": entry.identifier ?: @"",
            @"kind": entry.kind == GSPlayHistoryKindROM ? @"rom" : @"url",
            @"lastPlayedAt": @(entry.lastPlayedAt),
        }];
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject: raw
                                                  options: NSJSONWritingPrettyPrinted
                                                    error: NULL];
    if (data == nil) {
        return;
    }
    [data writeToURL: url atomically: YES];
}

#pragma mark - 增删查

- (void)recordIdentifier:(NSString *)identifier kind:(GSPlayHistoryKind)kind {
    if (identifier.length == 0) {
        return;
    }
    [self removeEntryWithIdentifier: identifier];

    GSPlayHistoryEntry *entry = [[GSPlayHistoryEntry alloc] init];
    entry.identifier = identifier;
    entry.kind = kind;
    entry.lastPlayedAt = [[NSDate date] timeIntervalSince1970];
    [self.entries insertObject: entry atIndex: 0];

    NSUInteger limit = [GSPlayHistory historyLimit];
    while (self.entries.count > limit) {
        [self.entries removeLastObject];
    }
    [self persist];
}

- (NSArray<GSPlayHistoryEntry *> *)recentEntriesWithLimit:(NSUInteger)limit {
    if (limit == 0 || self.entries.count == 0) {
        return @[];
    }
    NSUInteger count = MIN(limit, self.entries.count);
    return [self.entries subarrayWithRange: NSMakeRange(0, count)];
}

- (void)removeIdentifier:(NSString *)identifier {
    [self removeEntryWithIdentifier: identifier];
    [self persist];
}

- (void)removeEntryWithIdentifier:(NSString *)identifier {
    if (identifier.length == 0) {
        return;
    }
    NSIndexSet *matches = [self.entries indexesOfObjectsPassingTest:
        ^BOOL(GSPlayHistoryEntry *entry, NSUInteger idx, BOOL *stop) {
            return [entry.identifier isEqualToString: identifier];
        }];
    if (matches.count > 0) {
        [self.entries removeObjectsAtIndexes: matches];
    }
}

- (void)clear {
    [self.entries removeAllObjects];
    [self persist];
}

@end
