#import "GSCoverFetcher.h"

@interface GSCoverFetcher ()
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, assign) BOOL cancelled;

+ (nullable NSURL *)documentsURL;
+ (nullable NSURL *)coverDirectoryForSystemIdentifier:(NSString *)identifier create:(BOOL)create;
+ (nullable NSString *)storeCoverData:(NSData *)data forROM:(GSROM *)rom;
+ (NSString *)coverFileNameForROM:(GSROM *)rom;
- (nullable NSString *)downloadCoverForROM:(GSROM *)rom;
@end

@implementation GSCoverFetcher

+ (instancetype)sharedFetcher {
    static GSCoverFetcher *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[GSCoverFetcher alloc] init];
    });
    return shared;
}

#pragma mark - 路径

+ (nullable NSURL *)documentsURL {
    return [[NSFileManager defaultManager]
        URLForDirectory: NSDocumentDirectory
               inDomain: NSUserDomainMask
      appropriateForURL: nil
                 create: YES
                  error: NULL];
}

+ (nullable NSURL *)coverDirectoryForSystemIdentifier:(NSString *)identifier create:(BOOL)create {
    NSURL *documents = [self documentsURL];
    if (documents == nil || identifier.length == 0) {
        return nil;
    }
    NSURL *root = [documents URLByAppendingPathComponent: @"Covers" isDirectory: YES];
    NSURL *directory = [root URLByAppendingPathComponent: identifier isDirectory: YES];
    if (create) {
        [[NSFileManager defaultManager] createDirectoryAtURL: directory
                                 withIntermediateDirectories: YES
                                                  attributes: nil
                                                       error: NULL];
    }
    return directory;
}

+ (nullable NSString *)thumbnailDirectoryForSystem:(GSSystem)system {
    NSString *identifier = [GSSystemRegistry infoForSystem: system].identifier;
    static NSDictionary<NSString *, NSString *> *map;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        map = @{
            @"nes":  @"Nintendo - Nintendo Entertainment System",
            @"snes": @"Nintendo - Super Nintendo Entertainment System",
            @"gb":   @"Nintendo - Game Boy",
            @"gbc":  @"Nintendo - Game Boy Color",
            @"gba":  @"Nintendo - Game Boy Advance",
            @"nds":  @"Nintendo - Nintendo DS",
            @"3ds":  @"Nintendo - Nintendo 3DS",
            @"wii":  @"Nintendo - Wii",
            @"wiiu": @"Nintendo - Wii U",
        };
    });
    return map[identifier];
}

+ (NSString *)coverFileNameForROM:(GSROM *)rom {
    NSString *base = rom.fileName.length > 0 ? rom.fileName : rom.name;
    return [base stringByAppendingPathExtension: @"png"];
}

+ (nullable NSString *)cachedCoverRelativePathForROM:(GSROM *)rom {
    NSString *identifier = [GSSystemRegistry infoForSystem: rom.system].identifier;
    NSURL *directory = [self coverDirectoryForSystemIdentifier: identifier create: NO];
    if (directory == nil) {
        return nil;
    }
    NSString *fileName = [self coverFileNameForROM: rom];
    NSURL *fileURL = [directory URLByAppendingPathComponent: fileName];
    if (![[NSFileManager defaultManager] fileExistsAtPath: fileURL.path]) {
        return nil;
    }
    return [NSString stringWithFormat: @"Covers/%@/%@", identifier, fileName];
}

+ (nullable NSString *)storeCoverData:(NSData *)data forROM:(GSROM *)rom {
    NSString *identifier = [GSSystemRegistry infoForSystem: rom.system].identifier;
    NSURL *directory = [self coverDirectoryForSystemIdentifier: identifier create: YES];
    if (directory == nil) {
        return nil;
    }
    NSString *fileName = [self coverFileNameForROM: rom];
    NSURL *fileURL = [directory URLByAppendingPathComponent: fileName];
    if (![data writeToURL: fileURL atomically: YES]) {
        return nil;
    }
    return [NSString stringWithFormat: @"Covers/%@/%@", identifier, fileName];
}

#pragma mark - 抓取

- (NSURLSession *)session {
    if (_session == nil) {
        NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        configuration.timeoutIntervalForRequest = 10;
        configuration.timeoutIntervalForResource = 15;
        _session = [NSURLSession sessionWithConfiguration: configuration];
    }
    return _session;
}

- (void)cancel {
    self.cancelled = YES;
}

- (void)fetchCoversForROMs:(NSArray<GSROM *> *)roms
                     limit:(NSUInteger)limit
                  progress:(void (^)(NSString *, NSString *))progress
                completion:(void (^)(void))completion {
    if (limit == 0) {
        limit = 40;
    }

    NSMutableArray<GSROM *> *todo = [NSMutableArray array];
    for (GSROM *rom in roms) {
        if (todo.count >= limit) {
            break;
        }
        if ([GSCoverFetcher cachedCoverRelativePathForROM: rom] != nil) {
            continue;
        }
        if ([GSCoverFetcher thumbnailDirectoryForSystem: rom.system] == nil) {
            continue;
        }
        [todo addObject: rom];
    }

    if (todo.count == 0) {
        if (completion != nil) {
            dispatch_async(dispatch_get_main_queue(), completion);
        }
        return;
    }

    self.cancelled = NO;

    NSOperationQueue *queue = [[NSOperationQueue alloc] init];
    queue.maxConcurrentOperationCount = 4;
    queue.qualityOfService = NSQualityOfServiceUtility;

    NSMutableArray<NSOperation *> *operations = [NSMutableArray array];
    for (GSROM *rom in todo) {
        NSBlockOperation *operation = [NSBlockOperation blockOperationWithBlock: ^{
            if (self.cancelled) {
                return;
            }
            NSString *relativePath = [self downloadCoverForROM: rom];
            if (relativePath != nil && progress != nil) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    progress(rom.identifier, relativePath);
                });
            }
        }];
        [operations addObject: operation];
        [queue addOperation: operation];
    }

    NSBlockOperation *finish = [NSBlockOperation blockOperationWithBlock: ^{
        if (completion != nil) {
            dispatch_async(dispatch_get_main_queue(), completion);
        }
    }];
    for (NSOperation *operation in operations) {
        [finish addDependency: operation];
    }
    [queue addOperation: finish];
}

- (nullable NSString *)downloadCoverForROM:(GSROM *)rom {
    NSString *directory = [GSCoverFetcher thumbnailDirectoryForSystem: rom.system];
    if (directory.length == 0) {
        return nil;
    }
    NSCharacterSet *allowed = [NSCharacterSet URLPathAllowedCharacterSet];
    NSString *encodedDirectory = [directory stringByAddingPercentEncodingWithAllowedCharacters: allowed];
    NSString *encodedName = [rom.name stringByAddingPercentEncodingWithAllowedCharacters: allowed];
    if (encodedDirectory.length == 0 || encodedName.length == 0) {
        return nil;
    }

    NSString *urlString = [NSString stringWithFormat:
        @"https://thumbnails.libretro.com/%@/Named_Boxarts/%@.png",
        encodedDirectory, encodedName];
    NSURL *url = [NSURL URLWithString: urlString];
    if (url == nil) {
        return nil;
    }

    __block NSData *payload = nil;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    NSURLSessionDataTask *task = [[self session] dataTaskWithURL: url
                                              completionHandler: ^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error == nil &&
            [response isKindOfClass: [NSHTTPURLResponse class]] &&
            ((NSHTTPURLResponse *)response).statusCode == 200) {
            payload = data;
        }
        dispatch_semaphore_signal(semaphore);
    }];
    [task resume];
    dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)));

    if (payload.length == 0) {
        return nil;
    }
    return [GSCoverFetcher storeCoverData: payload forROM: rom];
}

@end
