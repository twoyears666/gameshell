//
//  GSROMLibrary.m
//  Gameshell
//

#import "GSROMLibrary.h"

NSString *const GSROMLibraryErrorDomain = @"GSROMLibraryErrorDomain";

typedef NS_ENUM(NSInteger, GSROMLibraryErrorCode) {
    GSROMLibraryErrorCodeNoAccess = 1,
    GSROMLibraryErrorCodeUnrecognizedSystem,
    GSROMLibraryErrorCodeCopyFailed,
};

#pragma mark - GSROM

@implementation GSROM

- (instancetype)initWithAbsolutePath:(NSString *)absolutePath relativePath:(NSString *)relativePath {
    self = [super init];
    if (self) {
        _absolutePath = [absolutePath copy];
        _relativePath = [relativePath copy];
        _identifier = [relativePath copy];
        _fileName = [absolutePath.lastPathComponent copy];
        _name = [[_fileName stringByDeletingPathExtension] copy];

        GSSystemInfo *info = [GSSystemRegistry infoForFileName: _fileName];
        _system = info ? info.system : GSSystemUnknown;

        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath: absolutePath
                                                                                   error: NULL];
        _sizeBytes = [attributes[NSFileSize] unsignedLongLongValue];
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat: @"<GSROM %@ (%@)>", self.name, self.relativePath];
}

@end

#pragma mark - GSROMLibrary

@implementation GSROMLibrary

+ (NSURL *)romsRootURL {
    NSURL *documents = [[NSFileManager defaultManager] URLForDirectory: NSDocumentDirectory
                                                              inDomain: NSUserDomainMask
                                                     appropriateForURL: nil
                                                                create: YES
                                                                 error: NULL];
    NSURL *root = [documents URLByAppendingPathComponent: @"ROMs" isDirectory: YES];
    [[NSFileManager defaultManager] createDirectoryAtURL: root
                             withIntermediateDirectories: YES
                                              attributes: nil
                                                   error: NULL];
    return root;
}

+ (NSURL *)directoryURLForSystem:(GSSystem)system {
    GSSystemInfo *info = [GSSystemRegistry infoForSystem: system];
    NSURL *directory = [[self romsRootURL] URLByAppendingPathComponent: info.identifier isDirectory: YES];
    [[NSFileManager defaultManager] createDirectoryAtURL: directory
                             withIntermediateDirectories: YES
                                              attributes: nil
                                                   error: NULL];
    return directory;
}

+ (NSArray<GSROM *> *)allROMs {
    return [self romsInDirectory: [self romsRootURL]];
}

+ (NSArray<GSROM *> *)romsInDirectory:(NSURL *)directory {
    NSFileManager *manager = [NSFileManager defaultManager];
    NSMutableArray<GSROM *> *result = [NSMutableArray array];

    NSDirectoryEnumerator<NSURL *> *enumerator = [manager enumeratorAtURL: directory
                                              includingPropertiesForKeys: @[NSURLFileSizeKey, NSURLIsDirectoryKey]
                                                                 options: NSDirectoryEnumerationSkipsHiddenFiles
                                                            errorHandler: nil];

    NSString *rootPath = directory.path;
    for (NSURL *fileURL in enumerator) {
        NSNumber *isDirectory = nil;
        [fileURL getResourceValue: &isDirectory forKey: NSURLIsDirectoryKey error: NULL];
        if (isDirectory.boolValue) {
            continue;
        }

        NSString *fileName = fileURL.lastPathComponent;
        // 存档 / 临时文件不算 ROM
        if ([fileName hasPrefix: @"."]) {
            continue;
        }
        GSSystemInfo *info = [GSSystemRegistry infoForFileName: fileName];
        if (info == nil) {
            continue;
        }

        NSString *fullPath = fileURL.path;
        NSString *relative = [fullPath substringFromIndex: MIN(rootPath.length + 1, fullPath.length)];
        [result addObject: [[GSROM alloc] initWithAbsolutePath: fullPath relativePath: relative]];
    }

    [result sortUsingComparator: ^NSComparisonResult(GSROM *lhs, GSROM *rhs) {
        if (lhs.system != rhs.system) {
            return lhs.system < rhs.system ? NSOrderedAscending : NSOrderedDescending;
        }
        return [lhs.name localizedStandardCompare: rhs.name];
    }];
    return [result copy];
}

+ (nullable GSROM *)importFileAtURL:(NSURL *)url error:(NSError **)error {
    GSSystemInfo *info = [GSSystemRegistry infoForFileURL: url];
    if (info == nil) {
        if (error) {
            *error = [NSError errorWithDomain: GSROMLibraryErrorDomain
                                         code: GSROMLibraryErrorCodeUnrecognizedSystem
                                     userInfo: @{NSLocalizedDescriptionKey:
                                        [NSString stringWithFormat: @"认不出这个文件属于哪个系统：%@", url.lastPathComponent ?: @""]}];
        }
        return nil;
    }

    // 文件选择器给的是安全作用域 URL，复制前必须显式申请访问权限
    BOOL scoped = [url startAccessingSecurityScopedResource];
    NSFileManager *manager = [NSFileManager defaultManager];
    NSURL *directory = [self directoryURLForSystem: info.system];
    NSURL *destination = [directory URLByAppendingPathComponent: url.lastPathComponent];

    // 重名时加序号，绝不覆盖用户已有的 ROM
    if ([manager fileExistsAtPath: destination.path]) {
        NSString *base = [url.lastPathComponent stringByDeletingPathExtension];
        NSString *ext = url.pathExtension;
        NSUInteger index = 2;
        do {
            NSString *candidate = [NSString stringWithFormat: @"%@-%lu.%@", base, (unsigned long)index, ext];
            destination = [directory URLByAppendingPathComponent: candidate];
            index += 1;
        } while ([manager fileExistsAtPath: destination.path] && index < 1000);
    }

    NSError *copyError = nil;
    BOOL copied = [manager copyItemAtURL: url toURL: destination error: &copyError];
    if (scoped) {
        [url stopAccessingSecurityScopedResource];
    }

    if (!copied) {
        if (error) {
            *error = copyError ?: [NSError errorWithDomain: GSROMLibraryErrorDomain
                                                     code: GSROMLibraryErrorCodeCopyFailed
                                                 userInfo: @{NSLocalizedDescriptionKey: @"复制 ROM 到沙盒失败"}];
        }
        return nil;
    }

    NSString *relative = [[destination.path substringFromIndex: [self romsRootURL].path.length + 1] copy];
    return [[GSROM alloc] initWithAbsolutePath: destination.path relativePath: relative];
}

+ (BOOL)deleteROM:(GSROM *)rom error:(NSError **)error {
    NSFileManager *manager = [NSFileManager defaultManager];
    NSError *removeError = nil;
    BOOL removed = [manager removeItemAtPath: rom.absolutePath error: &removeError];
    if (!removed && error) {
        *error = removeError;
    }
    return removed;
}

+ (NSURL *)batterySaveURLForROM:(GSROM *)rom {
    NSURL *romURL = [NSURL fileURLWithPath: rom.absolutePath];
    NSString *saveName = [[romURL.lastPathComponent stringByDeletingPathExtension]
        stringByAppendingPathExtension: @"sav"];
    return [[romURL URLByDeletingLastPathComponent] URLByAppendingPathComponent: saveName];
}

@end
