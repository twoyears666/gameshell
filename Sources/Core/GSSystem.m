//
//  GSSystem.m
//  Gameshell
//

#import "GSSystem.h"
#import "GSEmulator.h"

#pragma mark - GSSystemInfo

@interface GSSystemInfo ()
@property (nonatomic, assign) GSSystem system;
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, copy) NSString *shortName;
@property (nonatomic, copy) NSArray<NSString *> *fileExtensions;
@property (nonatomic, copy, nullable) NSString *plannedCoreName;
@property (nonatomic, copy, nullable) NSString *plannedCoreLicense;
@property (nonatomic, assign) BOOL requiresJIT;
@end

@implementation GSSystemInfo

- (BOOL)coreIntegrated {
    return [GSEmulatorSession hasCoreForSystem: self.system];
}

- (NSString *)statusNote {
    if (self.coreIntegrated) {
        return nil;
    }
    NSMutableString *note = [NSMutableString string];
    if (self.plannedCoreName.length > 0) {
        [note appendFormat: @"核心尚未接入主二进制（计划：%@）", self.plannedCoreName];
    } else {
        [note appendString: @"尚无可用核心"];
    }
    if (self.requiresJIT) {
        [note appendString: @"；该平台运行依赖 JIT，需要先按 REFERENCE.md 开启 JIT"];
    }
    return note;
}

- (NSString *)description {
    return [NSString stringWithFormat: @"<%@ %@ (%@)>", NSStringFromClass(self.class),
                                      self.displayName, self.identifier];
}

@end

#pragma mark - 注册表

@implementation GSSystemRegistry

+ (NSArray<GSSystemInfo *> *)allSystems {
    static NSArray<GSSystemInfo *> *systems;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        systems = @[
            [self infoWithSystem: GSSystemNES
                      identifier: @"nes"
                     displayName: @"Nintendo Entertainment System"
                       shortName: @"NES"
                  fileExtensions: @[@"nes", @"fds", @"unf", @"unif"]
                  plannedCoreName: @"Nestopia"
               plannedCoreLicense: @"GPL-2.0-or-later"
                      requiresJIT: NO],

            [self infoWithSystem: GSSystemSNES
                      identifier: @"snes"
                     displayName: @"Super Nintendo Entertainment System"
                       shortName: @"SNES"
                  fileExtensions: @[@"sfc", @"smc", @"swc", @"fig", @"bs"]
                  plannedCoreName: @"待定"
               plannedCoreLicense: @"必须是 GPL-3.0 兼容的核心（原计划的 Snes9x 是非商用许可，与整仓 GPL-3.0 不兼容，已排除）"
                      requiresJIT: NO],

            [self infoWithSystem: GSSystemGB
                      identifier: @"gb"
                     displayName: @"Game Boy"
                       shortName: @"GB"
                  fileExtensions: @[@"gb"]
                  plannedCoreName: @"mGBA"
               plannedCoreLicense: @"MPL-2.0"
                      requiresJIT: NO],

            [self infoWithSystem: GSSystemGBC
                      identifier: @"gbc"
                     displayName: @"Game Boy Color"
                       shortName: @"GBC"
                  fileExtensions: @[@"gbc"]
                  plannedCoreName: @"mGBA"
               plannedCoreLicense: @"MPL-2.0"
                      requiresJIT: NO],

            [self infoWithSystem: GSSystemGBA
                      identifier: @"gba"
                     displayName: @"Game Boy Advance"
                       shortName: @"GBA"
                  fileExtensions: @[@"gba", @"agb"]
                  plannedCoreName: @"mGBA"
               plannedCoreLicense: @"MPL-2.0"
                      requiresJIT: NO],

            [self infoWithSystem: GSSystemNDS
                      identifier: @"nds"
                     displayName: @"Nintendo DS"
                       shortName: @"NDS"
                  fileExtensions: @[@"nds"]
                  plannedCoreName: @"melonDS"
               plannedCoreLicense: @"GPL-3.0"
                      requiresJIT: NO],

            [self infoWithSystem: GSSystem3DS
                      identifier: @"3ds"
                     displayName: @"Nintendo 3DS"
                       shortName: @"3DS"
                  fileExtensions: @[@"3ds", @"cia", @"cci", @"cxi", @"app"]
                  plannedCoreName: @"Azahar（Citra 后继）"
               plannedCoreLicense: @"GPL-2.0"
                      requiresJIT: YES],

            [self infoWithSystem: GSSystemWii
                      identifier: @"wii"
                     displayName: @"Nintendo Wii"
                       shortName: @"Wii"
                  fileExtensions: @[@"wbfs", @"iso", @"rvz", @"wia", @"dol", @"elf"]
                  plannedCoreName: @"Dolphin"
               plannedCoreLicense: @"GPL-2.0+"
                      requiresJIT: YES],

            [self infoWithSystem: GSSystemWiiU
                      identifier: @"wiiu"
                     displayName: @"Nintendo Wii U"
                       shortName: @"Wii U"
                  fileExtensions: @[@"wud", @"wux", @"rpx", @"wua", @"rpl"]
                  plannedCoreName: @"Cemu / MeloCafe（iOS 移植）"
               plannedCoreLicense: @"MPL-2.0"
                      requiresJIT: YES],
        ];
    });
    return systems;
}

+ (GSSystemInfo *)infoWithSystem:(GSSystem)system
                      identifier:(NSString *)identifier
                     displayName:(NSString *)displayName
                       shortName:(NSString *)shortName
                  fileExtensions:(NSArray<NSString *> *)fileExtensions
                  plannedCoreName:(nullable NSString *)plannedCoreName
               plannedCoreLicense:(nullable NSString *)plannedCoreLicense
                      requiresJIT:(BOOL)requiresJIT {
    GSSystemInfo *info = [[GSSystemInfo alloc] init];
    info.system = system;
    info.identifier = identifier;
    info.displayName = displayName;
    info.shortName = shortName;
    info.fileExtensions = fileExtensions;
    info.plannedCoreName = plannedCoreName;
    info.plannedCoreLicense = plannedCoreLicense;
    info.requiresJIT = requiresJIT;
    return info;
}

+ (GSSystemInfo *)infoForSystem:(GSSystem)system {
    for (GSSystemInfo *info in [self allSystems]) {
        if (info.system == system) {
            return info;
        }
    }
    return [self unknownInfo];
}

+ (GSSystemInfo *)unknownInfo {
    static GSSystemInfo *unknown;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        unknown = [self infoWithSystem: GSSystemUnknown
                            identifier: @"unknown"
                           displayName: @"未识别"
                             shortName: @"?"
                        fileExtensions: @[]
                        plannedCoreName: nil
                     plannedCoreLicense: nil
                            requiresJIT: NO];
    });
    return unknown;
}

+ (nullable GSSystemInfo *)infoForIdentifier:(NSString *)identifier {
    NSString *needle = [identifier lowercaseString];
    for (GSSystemInfo *info in [self allSystems]) {
        if ([info.identifier isEqualToString: needle]) {
            return info;
        }
    }
    return nil;
}

+ (nullable GSSystemInfo *)infoForFileExtension:(NSString *)fileExtension {
    NSString *needle = [[fileExtension stringByReplacingOccurrencesOfString: @"." withString: @""] lowercaseString];
    if (needle.length == 0) {
        return nil;
    }
    for (GSSystemInfo *info in [self allSystems]) {
        if ([info.fileExtensions containsObject: needle]) {
            return info;
        }
    }
    return nil;
}

+ (nullable GSSystemInfo *)infoForFileName:(NSString *)fileName {
    return [self infoForFileExtension: [fileName pathExtension]];
}

+ (nullable GSSystemInfo *)infoForFileURL:(NSURL *)url {
    return [self infoForFileName: url.lastPathComponent ?: @""];
}

+ (NSArray<GSSystemInfo *> *)integratedSystems {
    return [[self allSystems] filteredArrayUsingPredicate:
        [NSPredicate predicateWithBlock: ^BOOL(GSSystemInfo *info, NSDictionary *bindings) {
            return info.coreIntegrated;
        }]];
}

+ (NSArray<NSString *> *)allROMFileExtensions {
    NSMutableArray<NSString *> *extensions = [NSMutableArray array];
    for (GSSystemInfo *info in [self allSystems]) {
        [extensions addObjectsFromArray: info.fileExtensions];
    }
    return [extensions copy];
}

@end
