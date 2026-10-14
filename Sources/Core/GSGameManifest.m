#import "GSGameManifest.h"

@implementation GSGame

- (instancetype)initWithDictionary:(NSDictionary *)dictionary {
    self = [super init];
    if (self) {
        _identifier = [GSGame stringForKey:@"id" in: dictionary fallback: [[NSUUID UUID] UUIDString]];
        _name = [GSGame stringForKey:@"name" in: dictionary fallback: @"未命名"];
        _iconURLString = [GSGame stringForKey:@"icon" in: dictionary fallback: @""];
        _gameURLString = [GSGame stringForKey:@"url" in: dictionary fallback: @""];
        _platform = [GSGame stringForKey:@"platform" in: dictionary fallback: @"Web"];
        _controllerSupport = [GSGame boolForKey:@"controllerSupport" in: dictionary fallback: NO];
        _rating = [GSGame doubleForKey:@"rating" in: dictionary fallback: 0.0];
        _summary = [GSGame stringForKey:@"description" in: dictionary fallback: @""];
        _accentHex = dictionary[@"accent"];

        NSArray *rawTags = dictionary[@"tags"];
        _tags = [rawTags isKindOfClass:[NSArray class]] ? rawTags : @[];
    }
    return self;
}

- (NSDictionary *)dictionaryRepresentation {
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
    dictionary[@"id"] = self.identifier ?: @"";
    dictionary[@"name"] = self.name ?: @"";
    dictionary[@"url"] = self.gameURLString ?: @"";
    dictionary[@"platform"] = self.platform ?: @"";
    dictionary[@"controllerSupport"] = @(self.controllerSupport);
    if (self.iconURLString.length > 0) {
        dictionary[@"icon"] = self.iconURLString;
    }
    if (self.summary.length > 0) {
        dictionary[@"description"] = self.summary;
    }
    if (self.tags.count > 0) {
        dictionary[@"tags"] = self.tags;
    }
    if (self.rating > 0) {
        dictionary[@"rating"] = @(self.rating);
    }
    if (self.accentHex.length > 0) {
        dictionary[@"accent"] = self.accentHex;
    }
    return dictionary;
}

+ (NSArray<GSGame *> *)gamesFromArray:(NSArray *)array {
    NSMutableArray<GSGame *> *result = [NSMutableArray arrayWithCapacity: array.count];
    for (id item in array) {
        if ([item isKindOfClass:[NSDictionary class]]) {
            [result addObject: [[GSGame alloc] initWithDictionary: item]];
        }
    }
    return [result copy];
}

+ (NSString *)stringForKey:(NSString *)key
                        in:(NSDictionary *)dictionary
                  fallback:(NSString *)fallback {
    id value = dictionary[key];
    if ([value isKindOfClass:[NSString class]] && [value length] > 0) {
        return value;
    }
    if ([value isKindOfClass:[NSNumber class]]) {
        return [value stringValue];
    }
    return fallback;
}

+ (BOOL)boolForKey:(NSString *)key
                in:(NSDictionary *)dictionary
          fallback:(BOOL)fallback {
    id value = dictionary[key];
    if ([value isKindOfClass:[NSNumber class]]) {
        return [value boolValue];
    }
    if ([value isKindOfClass:[NSString class]]) {
        NSString *lower = [value lowercaseString];
        return [lower isEqualToString:@"true"] || [lower isEqualToString:@"yes"];
    }
    return fallback;
}

+ (double)doubleForKey:(NSString *)key
                    in:(NSDictionary *)dictionary
              fallback:(double)fallback {
    id value = dictionary[key];
    if ([value isKindOfClass:[NSNumber class]]) {
        return [value doubleValue];
    }
    if ([value isKindOfClass:[NSString class]]) {
        return [value doubleValue];
    }
    return fallback;
}

@end

#pragma mark -

@interface GSGameManifest ()
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *subtitle;
@property (nonatomic, strong) NSMutableArray<GSGame *> *mutableGames;
@end

@implementation GSGameManifest

- (instancetype)initWithDictionary:(NSDictionary *)dictionary {
    self = [super init];
    if (self) {
        _title = [GSGame stringForKey:@"title" in: dictionary fallback: @"Gameshell"];
        _subtitle = [GSGame stringForKey:@"subtitle" in: dictionary fallback: @""];

        NSArray *rawGames = dictionary[@"games"];
        NSArray<GSGame *> *parsed = [rawGames isKindOfClass:[NSArray class]]
            ? [GSGame gamesFromArray: rawGames]
            : @[];
        _mutableGames = [NSMutableArray arrayWithArray: parsed];
    }
    return self;
}

- (NSArray<GSGame *> *)games {
    return [self.mutableGames copy];
}

#pragma mark - 增删

- (void)add:(GSGame *)game {
    if (game == nil) {
        return;
    }
    [self.mutableGames addObject: game];
}

- (void)removeGameWithIdentifier:(NSString *)identifier {
    if (identifier.length == 0) {
        return;
    }
    NSIndexSet *matches = [self.mutableGames indexesOfObjectsPassingTest:
        ^BOOL(GSGame *game, NSUInteger idx, BOOL *stop) {
            return [game.identifier isEqualToString: identifier];
        }];
    if (matches.count > 0) {
        [self.mutableGames removeObjectsAtIndexes: matches];
    }
}

#pragma mark - 持久化

+ (NSURL *)userStoreURL {
    NSURL *directory = [[NSFileManager defaultManager]
        URLForDirectory: NSDocumentDirectory
               inDomain: NSUserDomainMask
      appropriateForURL: nil
                 create: YES
                  error: NULL];
    return [directory URLByAppendingPathComponent: @"games.json"];
}

+ (nullable instancetype)loadFromUserStore {
    NSURL *url = [self userStoreURL];
    if (url == nil || ![[NSFileManager defaultManager] fileExistsAtPath: url.path]) {
        return nil;
    }
    NSData *data = [NSData dataWithContentsOfURL: url];
    if (data == nil) {
        return nil;
    }
    return [self manifestWithJSONData: data error: NULL];
}

- (BOOL)persistToUserStore {
    NSURL *url = [GSGameManifest userStoreURL];
    if (url == nil) {
        return NO;
    }

    NSMutableArray *rawGames = [NSMutableArray arrayWithCapacity: self.mutableGames.count];
    for (GSGame *game in self.mutableGames) {
        [rawGames addObject: [game dictionaryRepresentation]];
    }

    NSDictionary *payload = @{
        @"title": self.title ?: @"Gameshell",
        @"subtitle": self.subtitle ?: @"",
        @"games": rawGames,
    };

    NSData *data = [NSJSONSerialization dataWithJSONObject: payload
                                                  options: NSJSONWritingPrettyPrinted
                                                    error: NULL];
    if (data == nil) {
        return NO;
    }
    return [data writeToURL: url atomically: YES];
}

#pragma mark - 加载

+ (nullable instancetype)manifestNamed:(NSString *)name inBundle:(nullable NSBundle *)bundle {
    NSBundle *resolvedBundle = bundle ?: [NSBundle mainBundle];
    NSString *fileName = [name stringByDeletingPathExtension];
    NSString *extension = name.pathExtension.length > 0 ? name.pathExtension : @"json";
    NSURL *url = [resolvedBundle URLForResource: fileName withExtension: extension];
    if (url == nil) {
        return nil;
    }
    NSData *data = [NSData dataWithContentsOfURL: url];
    if (data == nil) {
        return nil;
    }
    return [self manifestWithJSONData: data error: NULL];
}

+ (nullable instancetype)manifestWithJSONData:(NSData *)data error:(NSError **)error {
    id object = [NSJSONSerialization JSONObjectWithData: data options: 0 error: error];
    if (![object isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    return [[self alloc] initWithDictionary: object];
}

+ (nullable instancetype)manifestWithJSONString:(NSString *)json error:(NSError **)error {
    NSData *data = [json dataUsingEncoding: NSUTF8StringEncoding];
    if (data == nil) {
        return nil;
    }
    return [self manifestWithJSONData: data error: error];
}

@end
