#import "GSIconStore.h"

@implementation GSIconStore

+ (instancetype)sharedStore {
    static GSIconStore *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[GSIconStore alloc] init];
    });
    return shared;
}

+ (nullable NSURL *)documentsURL {
    return [[NSFileManager defaultManager]
        URLForDirectory: NSDocumentDirectory
               inDomain: NSUserDomainMask
      appropriateForURL: nil
                 create: YES
                  error: NULL];
}

+ (nullable NSURL *)iconsRootURL {
    NSURL *documents = [self documentsURL];
    if (documents == nil) {
        return nil;
    }
    NSURL *root = [documents URLByAppendingPathComponent: @"Icons" isDirectory: YES];
    [[NSFileManager defaultManager] createDirectoryAtURL: root
                             withIntermediateDirectories: YES
                                              attributes: nil
                                                   error: NULL];
    return root;
}

+ (NSArray<NSString *> *)knownExtensions {
    return @[@"png", @"jpg", @"jpeg", @"heic", @"webp", @"gif", @"bmp"];
}

+ (nullable NSString *)storeIconData:(NSData *)data
                       fileExtension:(nullable NSString *)fileExtension
                       forIdentifier:(NSString *)identifier {
    if (data.length == 0 || identifier.length == 0) {
        return nil;
    }
    NSURL *root = [self iconsRootURL];
    if (root == nil) {
        return nil;
    }

    [self removeIconForIdentifier: identifier];

    NSString *ext = [fileExtension lowercaseString];
    if (ext.length == 0) {
        ext = @"png";
    }
    NSString *fileName = [identifier stringByAppendingPathExtension: ext];
    NSURL *fileURL = [root URLByAppendingPathComponent: fileName];
    if (![data writeToURL: fileURL atomically: YES]) {
        return nil;
    }
    return [@"Icons" stringByAppendingPathComponent: fileName];
}

+ (BOOL)removeIconForIdentifier:(NSString *)identifier {
    if (identifier.length == 0) {
        return NO;
    }
    NSURL *root = [self iconsRootURL];
    if (root == nil) {
        return NO;
    }
    BOOL removedAny = NO;
    NSFileManager *manager = [NSFileManager defaultManager];
    for (NSString *ext in [self knownExtensions]) {
        NSURL *fileURL = [root URLByAppendingPathComponent:
            [identifier stringByAppendingPathExtension: ext]];
        if ([manager fileExistsAtPath: fileURL.path]) {
            if ([manager removeItemAtURL: fileURL error: NULL]) {
                removedAny = YES;
            }
        }
    }
    return removedAny;
}

+ (nullable NSURL *)absoluteURLForRelativePath:(NSString *)relativePath {
    if (relativePath.length == 0) {
        return nil;
    }
    NSURL *documents = [self documentsURL];
    if (documents == nil) {
        return nil;
    }
    return [documents URLByAppendingPathComponent: relativePath];
}

@end
