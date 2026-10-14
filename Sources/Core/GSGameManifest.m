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
@property (nonatomic, copy) NSArray<GSGame *> *games;
@property (nonatomic, copy) NSArray<NSString *> *categories;
@end

@implementation GSGameManifest

- (instancetype)initWithDictionary:(NSDictionary *)dictionary {
    self = [super init];
    if (self) {
        _title = [GSGame stringForKey:@"title" in: dictionary fallback: @"游戏库"];
        _subtitle = [GSGame stringForKey:@"subtitle" in: dictionary fallback: @""];

        NSArray *rawGames = dictionary[@"games"];
        _games = [rawGames isKindOfClass:[NSArray class]]
            ? [GSGame gamesFromArray: rawGames]
            : @[];

        NSArray *rawCategories = dictionary[@"categories"];
        if ([rawCategories isKindOfClass:[NSArray class]]) {
            _categories = rawCategories;
        } else {
            // 未声明分类时，用「全部」+ 去重后的平台名兜底
            NSMutableOrderedSet<NSString *> *set = [NSMutableOrderedSet orderedSetWithObject: @"全部"];
            for (GSGame *game in _games) {
                if (game.platform.length > 0) {
                    [set addObject: game.platform];
                }
            }
            _categories = [set array];
        }
    }
    return self;
}

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
