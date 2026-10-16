#import "GSKeyMapping.h"

#pragma mark - 按钮标识

/// 每个按钮位对应一个稳定的键名（用于持久化与查询）
static NSString *GSButtonKey(GSButton button) {
    switch (button) {
        case GSButtonA:      return @"A";
        case GSButtonB:      return @"B";
        case GSButtonX:      return @"X";
        case GSButtonY:      return @"Y";
        case GSButtonUp:     return @"Up";
        case GSButtonDown:   return @"Down";
        case GSButtonLeft:   return @"Left";
        case GSButtonRight:  return @"Right";
        case GSButtonL:      return @"L";
        case GSButtonR:      return @"R";
        case GSButtonStart:  return @"Start";
        case GSButtonSelect: return @"Select";
        default:             return @"";
    }
}

static GSButton GSButtonFromKey(NSString *key) {
    if (key.length == 0) {
        return 0;
    }
    for (NSNumber *number in [GSKeyMapping configurableButtons]) {
        GSButton button = (GSButton)number.unsignedIntValue;
        if ([GSButtonKey(button) isEqualToString: key]) {
            return button;
        }
    }
    return 0;
}

/// HID 键码 → 显示名（常见键给可读名字，其余回落成 "HID <码>"）
static NSString *GSKeyboardLabel(NSInteger usage) {
    switch (usage) {
        case 79:  return @"→";
        case 80:  return @"←";
        case 81:  return @"↓";
        case 82:  return @"↑";
        case 40:  return @"Enter";
        case 41:  return @"Esc";
        case 43:  return @"Tab";
        case 44:  return @"空格";
        case 225: return @"Shift";
        case 224: return @"Ctrl";
        case 226: return @"Alt";
        default:  break;
    }
    if (usage >= 4 && usage <= 29) {
        unichar character = (unichar)('A' + (usage - 4));
        return [NSString stringWithCharacters: &character length: 1];
    }
    if (usage >= 30 && usage <= 39) {
        NSInteger digit = (usage == 39) ? 0 : (usage - 29);
        return [NSString stringWithFormat: @"%ld", (long)digit];
    }
    return [NSString stringWithFormat: @"HID %ld", (long)usage];
}

/// 手柄标识 → 显示名
static NSString *GSGamepadLabel(NSString *identifier) {
    static NSDictionary<NSString *, NSString *> *map;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        map = @{
            @"Button A": @"A",
            @"Button B": @"B",
            @"Button X": @"X",
            @"Button Y": @"Y",
            @"Left Shoulder": @"L1",
            @"Right Shoulder": @"R1",
            @"Left Trigger": @"L2",
            @"Right Trigger": @"R2",
            @"Menu": @"Menu",
            @"Options": @"Options",
            @"Home": @"Home",
            @"Left Thumbstick Button": @"L3",
            @"Right Thumbstick Button": @"R3",
            @"Direction Pad Up": @"十字键上",
            @"Direction Pad Down": @"十字键下",
            @"Direction Pad Left": @"十字键左",
            @"Direction Pad Right": @"十字键右",
        };
    });
    return map[identifier] ?: identifier;
}

#pragma mark - 按键簇

/// 每个按键簇的稳定键名（持久化用）
static NSString *GSTouchClusterKey(GSTouchCluster cluster) {
    switch (cluster) {
        case GSTouchClusterDPad:        return @"dpad";
        case GSTouchClusterFace:        return @"face";
        case GSTouchClusterL:           return @"L";
        case GSTouchClusterR:           return @"R";
        case GSTouchClusterStartSelect: return @"startSelect";
        case GSTouchClusterMenu:        return @"menu";
        case GSTouchClusterTouchScreen: return @"touchScreen";
    }
    return @"";
}

/// 全部按键簇（按 rawValue 顺序，持久化 / 迁移遍历用）
static const GSTouchCluster GSTouchClusterAll[] = {
    GSTouchClusterDPad, GSTouchClusterFace, GSTouchClusterL, GSTouchClusterR,
    GSTouchClusterStartSelect, GSTouchClusterMenu, GSTouchClusterTouchScreen,
};

static GSTouchCluster GSTouchClusterFromKey(NSString *key) {
    for (size_t index = 0; index < sizeof(GSTouchClusterAll) / sizeof(GSTouchClusterAll[0]); index++) {
        if ([GSTouchClusterKey(GSTouchClusterAll[index]) isEqualToString: key]) {
            return GSTouchClusterAll[index];
        }
    }
    return GSTouchClusterDPad;
}

/// 解析一份「cluster 键名 → {x,y,scale}」字典
static NSMutableDictionary<NSNumber *, GSTouchClusterLayout *> *GSParseLayoutBucket(NSDictionary *source) {
    NSMutableDictionary<NSNumber *, GSTouchClusterLayout *> *bucket = [NSMutableDictionary dictionary];
    for (id key in source) {
        id entry = source[key];
        if (![key isKindOfClass: [NSString class]] || ![entry isKindOfClass: [NSDictionary class]]) {
            continue;
        }
        NSDictionary *values = entry;
        GSTouchClusterLayout *layout = [GSTouchClusterLayout layoutWithX: 0.5 y: 0.5 scale: 1.0];
        if ([values[@"x"] isKindOfClass: [NSNumber class]]) { layout.x = [values[@"x"] doubleValue]; }
        if ([values[@"y"] isKindOfClass: [NSNumber class]]) { layout.y = [values[@"y"] doubleValue]; }
        if ([values[@"scale"] isKindOfClass: [NSNumber class]]) { layout.scale = [values[@"scale"] doubleValue]; }
        bucket[@(GSTouchClusterFromKey(key))] = layout;
    }
    return bucket;
}

#pragma mark - 各系统的按键簇 profile

/// 系统标识规整（小写）；nil / 空归成空串
static NSString *GSSystemKey(NSString *systemIdentifier) {
    return [(systemIdentifier ?: @"") lowercaseString];
}

/// 各系统的按键簇集合
static NSArray<NSNumber *> *GSClustersForSystem(NSString *systemIdentifier) {
    NSString *system = GSSystemKey(systemIdentifier);
    if ([system isEqualToString: @"nds"]) {
        return @[@(GSTouchClusterDPad), @(GSTouchClusterFace),
                 @(GSTouchClusterL), @(GSTouchClusterR), @(GSTouchClusterStartSelect),
                 @(GSTouchClusterMenu), @(GSTouchClusterTouchScreen)];
    }
    if ([system isEqualToString: @"nes"] || [system isEqualToString: @"gb"] || [system isEqualToString: @"gbc"]) {
        // 8 位机没有 L / R 肩键
        return @[@(GSTouchClusterDPad), @(GSTouchClusterFace), @(GSTouchClusterStartSelect)];
    }
    // snes / gba / 未知：十字键 + A/B(/X/Y) + L/R + START/SELECT
    return @[@(GSTouchClusterDPad), @(GSTouchClusterFace),
             @(GSTouchClusterL), @(GSTouchClusterR), @(GSTouchClusterStartSelect)];
}

/// SNES / NDS 的 A / B 簇要画成 A / B / X / Y 四键
static BOOL GSSystemUsesFourFaceKeys(NSString *systemIdentifier) {
    NSString *system = GSSystemKey(systemIdentifier);
    return [system isEqualToString: @"snes"] || [system isEqualToString: @"nds"];
}

/// 各按键簇在某系统里的内置默认布局（归一化中心 + 缩放）。
///   · 8/16 位机与 GBA 沿用 Delta「Standard GBA」皮肤的 iPhone 横屏数值（画布 667×375）：
///     十字键左下、A/B 右下、L/R 顶部两角、START/SELECT 底部居中；
///   · NDS 用 Delta「Standard DS」横屏数值（同为 667×375）：A/B/X/Y 四键在右、
///     L/R 在两侧偏中、Menu 与下屏触摸区各就各位 —— 与 GBA 明显不同，这正是要按系统区分的点。
static GSTouchClusterLayout *GSDefaultLayoutForCluster(GSTouchCluster cluster, NSString *systemIdentifier) {
    if ([GSSystemKey(systemIdentifier) isEqualToString: @"nds"]) {
        switch (cluster) {
            case GSTouchClusterDPad:        return [GSTouchClusterLayout layoutWithX: 0.115 y: 0.791 scale: 1.0];
            case GSTouchClusterFace:        return [GSTouchClusterLayout layoutWithX: 0.878 y: 0.791 scale: 1.0];
            case GSTouchClusterL:           return [GSTouchClusterLayout layoutWithX: 0.361 y: 0.628 scale: 1.0];
            case GSTouchClusterR:           return [GSTouchClusterLayout layoutWithX: 0.640 y: 0.628 scale: 1.0];
            case GSTouchClusterStartSelect: return [GSTouchClusterLayout layoutWithX: 0.535 y: 0.767 scale: 1.0];
            case GSTouchClusterMenu:        return [GSTouchClusterLayout layoutWithX: 0.292 y: 0.768 scale: 1.0];
            case GSTouchClusterTouchScreen: return [GSTouchClusterLayout layoutWithX: 0.735 y: 0.323 scale: 1.0];
        }
        return [GSTouchClusterLayout layoutWithX: 0.5 y: 0.5 scale: 1.0];
    }

    // nes / gb / gbc / snes / gba / 未知：Delta「Standard GBA」
    switch (cluster) {
        case GSTouchClusterDPad:        return [GSTouchClusterLayout layoutWithX: 0.143 y: 0.745 scale: 1.0];
        case GSTouchClusterFace:        return [GSTouchClusterLayout layoutWithX: 0.865 y: 0.784 scale: 1.0];
        case GSTouchClusterL:           return [GSTouchClusterLayout layoutWithX: 0.097 y: 0.093 scale: 1.0];
        case GSTouchClusterR:           return [GSTouchClusterLayout layoutWithX: 0.903 y: 0.093 scale: 1.0];
        case GSTouchClusterStartSelect: return [GSTouchClusterLayout layoutWithX: 0.501 y: 0.928 scale: 1.0];
        case GSTouchClusterMenu:        return [GSTouchClusterLayout layoutWithX: 0.292 y: 0.768 scale: 1.0];
        case GSTouchClusterTouchScreen: return [GSTouchClusterLayout layoutWithX: 0.735 y: 0.323 scale: 1.0];
    }
    return [GSTouchClusterLayout layoutWithX: 0.5 y: 0.5 scale: 1.0];
}

#pragma mark - 布局对象

@implementation GSTouchClusterLayout

+ (instancetype)layoutWithX:(CGFloat)x y:(CGFloat)y scale:(CGFloat)scale {
    GSTouchClusterLayout *layout = [[GSTouchClusterLayout alloc] init];
    layout.x = x;
    layout.y = y;
    layout.scale = scale;
    return layout;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _x = 0.5;
        _y = 0.5;
        _scale = 1.0;
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    return [GSTouchClusterLayout layoutWithX: self.x y: self.y scale: self.scale];
}

@end

#pragma mark -

@interface GSKeyMapping ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *keyboardBindings;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *gamepadBindings;
/// 按系统的自定义布局：system → (GSTouchCluster 的 NSNumber → layout)；没存进来的就是内置默认
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableDictionary<NSNumber *, GSTouchClusterLayout *> *> *touchLayouts;
/// 按系统的可见性覆盖：system → (GSTouchCluster 的 NSNumber → NSNumber(BOOL))；没有覆盖时按默认显示
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableDictionary<NSNumber *, NSNumber *> *> *touchVisibility;

+ (NSDictionary<NSString *, NSNumber *> *)defaultKeyboardBindings;
+ (NSDictionary<NSString *, NSString *> *)defaultGamepadBindings;
- (void)loadFromDisk;
@end

@implementation GSKeyMapping

+ (instancetype)sharedMapping {
    static GSKeyMapping *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[GSKeyMapping alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _keyboardBindings = [NSMutableDictionary dictionary];
        _gamepadBindings = [NSMutableDictionary dictionary];
        _touchLayouts = [NSMutableDictionary dictionary];
        _touchVisibility = [NSMutableDictionary dictionary];
        [self applyDefaultTouchProfile];
        _keyboardBindings = [[GSKeyMapping defaultKeyboardBindings] mutableCopy];
        _gamepadBindings = [[GSKeyMapping defaultGamepadBindings] mutableCopy];
        [self loadFromDisk];
    }
    return self;
}

#pragma mark - 按钮集合

+ (NSArray<NSNumber *> *)configurableButtons {
    return @[
        @(GSButtonA), @(GSButtonB), @(GSButtonX), @(GSButtonY),
        @(GSButtonUp), @(GSButtonDown), @(GSButtonLeft), @(GSButtonRight),
        @(GSButtonL), @(GSButtonR), @(GSButtonStart), @(GSButtonSelect),
    ];
}

+ (NSString *)displayNameForButton:(GSButton)button {
    switch (button) {
        case GSButtonA:      return @"A 键";
        case GSButtonB:      return @"B 键";
        case GSButtonX:      return @"X 键";
        case GSButtonY:      return @"Y 键";
        case GSButtonUp:     return @"方向键上";
        case GSButtonDown:   return @"方向键下";
        case GSButtonLeft:   return @"方向键左";
        case GSButtonRight:  return @"方向键右";
        case GSButtonL:      return @"L 肩键";
        case GSButtonR:      return @"R 肩键";
        case GSButtonStart:  return @"Start";
        case GSButtonSelect: return @"Select";
        default:             return @"未知按键";
    }
}

#pragma mark - 触屏整体

- (void)applyDefaultTouchProfile {
    _touchScale = 1.0;
    _touchOpacity = 0.92;
}

- (void)setTouchScale:(CGFloat)touchScale {
    _touchScale = MAX((CGFloat)0.6, MIN((CGFloat)1.4, touchScale));
}

- (void)setTouchOpacity:(CGFloat)touchOpacity {
    _touchOpacity = MAX((CGFloat)0.3, MIN((CGFloat)1.0, touchOpacity));
}

#pragma mark - 触屏按键簇（按系统区分）

+ (NSArray<NSNumber *> *)touchClustersForSystem:(NSString *)systemIdentifier {
    return GSClustersForSystem(systemIdentifier);
}

+ (BOOL)systemUsesFourFaceKeys:(NSString *)systemIdentifier {
    return GSSystemUsesFourFaceKeys(systemIdentifier);
}

+ (NSString *)displayNameForCluster:(GSTouchCluster)cluster forSystem:(NSString *)systemIdentifier {
    switch (cluster) {
        case GSTouchClusterDPad:        return @"十字键";
        case GSTouchClusterFace:        return GSSystemUsesFourFaceKeys(systemIdentifier) ? @"A / B / X / Y" : @"A / B";
        case GSTouchClusterL:           return @"L 肩键";
        case GSTouchClusterR:           return @"R 肩键";
        case GSTouchClusterStartSelect: return @"START / SELECT";
        case GSTouchClusterMenu:        return @"Menu";
        case GSTouchClusterTouchScreen: return @"触摸屏";
    }
    return @"按键簇";
}

- (GSTouchClusterLayout *)layoutForCluster:(GSTouchCluster)cluster forSystem:(NSString *)systemIdentifier {
    NSMutableDictionary<NSNumber *, GSTouchClusterLayout *> *bucket = self.touchLayouts[GSSystemKey(systemIdentifier)];
    GSTouchClusterLayout *layout = bucket[@(cluster)];
    return layout != nil ? layout : GSDefaultLayoutForCluster(cluster, systemIdentifier);
}

- (void)setLayout:(GSTouchClusterLayout *)layout forCluster:(GSTouchCluster)cluster forSystem:(NSString *)systemIdentifier {
    if (layout == nil) {
        return;
    }
    NSString *system = GSSystemKey(systemIdentifier);
    NSMutableDictionary<NSNumber *, GSTouchClusterLayout *> *bucket = self.touchLayouts[system];
    if (bucket == nil) {
        bucket = [NSMutableDictionary dictionary];
        self.touchLayouts[system] = bucket;
    }
    // 值域收在这里，播放器与设置页都不必再各自夹一遍
    bucket[@(cluster)] = [GSTouchClusterLayout layoutWithX: MAX((CGFloat)0.0, MIN((CGFloat)1.0, layout.x))
                                                          y: MAX((CGFloat)0.0, MIN((CGFloat)1.0, layout.y))
                                                      scale: MAX((CGFloat)0.6, MIN((CGFloat)1.6, layout.scale))];
}

- (BOOL)hasCustomTouchLayoutForSystem:(NSString *)systemIdentifier {
    NSMutableDictionary<NSNumber *, GSTouchClusterLayout *> *bucket = self.touchLayouts[GSSystemKey(systemIdentifier)];
    return bucket.count > 0;
}

- (void)resetTouchLayoutsForSystem:(NSString *)systemIdentifier {
    NSString *system = GSSystemKey(systemIdentifier);
    [self.touchLayouts removeObjectForKey: system];
    [self.touchVisibility removeObjectForKey: system];
    [self persist];
}

- (BOOL)isClusterVisible:(GSTouchCluster)cluster forSystem:(NSString *)systemIdentifier {
    NSNumber *override = self.touchVisibility[GSSystemKey(systemIdentifier)][@(cluster)];
    if (override != nil) {
        return override.boolValue;
    }
    // 没被显式改过时，属于该系统按键簇集合的就默认显示
    for (NSNumber *number in GSClustersForSystem(systemIdentifier)) {
        if ((GSTouchCluster)number.integerValue == cluster) {
            return YES;
        }
    }
    return NO;
}

- (void)setVisible:(BOOL)visible forCluster:(GSTouchCluster)cluster forSystem:(NSString *)systemIdentifier {
    NSString *system = GSSystemKey(systemIdentifier);
    NSMutableDictionary<NSNumber *, NSNumber *> *bucket = self.touchVisibility[system];
    if (bucket == nil) {
        bucket = [NSMutableDictionary dictionary];
        self.touchVisibility[system] = bucket;
    }
    bucket[@(cluster)] = @(visible);
}

#pragma mark - 默认键位

+ (NSDictionary<NSString *, NSNumber *> *)defaultKeyboardBindings {
    // 方向键 → 上下左右；Z → A、X → B；Enter → Start、Shift → Select；Q → L、W → R
    return @{
        @"Up":     @82,
        @"Down":   @81,
        @"Left":   @80,
        @"Right":  @79,
        @"A":      @29,
        @"B":      @27,
        @"Start":  @40,
        @"Select": @225,
        @"L":      @20,
        @"R":      @26,
    };
}

+ (NSDictionary<NSString *, NSString *> *)defaultGamepadBindings {
    return @{
        @"A":      @"Button A",
        @"B":      @"Button B",
        @"X":      @"Button X",
        @"Y":      @"Button Y",
        @"L":      @"Left Shoulder",
        @"R":      @"Right Shoulder",
        @"Start":  @"Menu",
        @"Select": @"Options",
        @"Up":     @"Direction Pad Up",
        @"Down":   @"Direction Pad Down",
        @"Left":   @"Direction Pad Left",
        @"Right":  @"Direction Pad Right",
    };
}

#pragma mark - 键盘

- (GSButton)buttonForKeyboardUsage:(NSInteger)usage {
    for (NSString *key in self.keyboardBindings) {
        if ([self.keyboardBindings[key] integerValue] == usage) {
            return GSButtonFromKey(key);
        }
    }
    return 0;
}

- (void)setKeyboardUsage:(NSInteger)usage forButton:(GSButton)button {
    NSString *key = GSButtonKey(button);
    if (key.length == 0) {
        return;
    }
    // 一个键只绑一个按钮：先清掉同一 usage 的旧绑定
    for (NSString *existing in [self.keyboardBindings.allKeys copy]) {
        if ([self.keyboardBindings[existing] integerValue] == usage) {
            [self.keyboardBindings removeObjectForKey: existing];
        }
    }
    self.keyboardBindings[key] = @(usage);
    [self persist];
}

- (void)clearKeyboardBindingForButton:(GSButton)button {
    NSString *key = GSButtonKey(button);
    if (key.length == 0) {
        return;
    }
    [self.keyboardBindings removeObjectForKey: key];
    [self persist];
}

- (nullable NSString *)keyboardBindingLabelForButton:(GSButton)button {
    NSString *key = GSButtonKey(button);
    NSNumber *usage = key.length > 0 ? self.keyboardBindings[key] : nil;
    if (usage == nil) {
        return nil;
    }
    return GSKeyboardLabel(usage.integerValue);
}

#pragma mark - 手柄

- (GSButton)buttonForGamepadIdentifier:(NSString *)identifier {
    if (identifier.length == 0) {
        return 0;
    }
    for (NSString *key in self.gamepadBindings) {
        if ([self.gamepadBindings[key] isEqualToString: identifier]) {
            return GSButtonFromKey(key);
        }
    }
    return 0;
}

- (void)setGamepadIdentifier:(NSString *)identifier forButton:(GSButton)button {
    NSString *key = GSButtonKey(button);
    if (key.length == 0 || identifier.length == 0) {
        return;
    }
    for (NSString *existing in [self.gamepadBindings.allKeys copy]) {
        if ([self.gamepadBindings[existing] isEqualToString: identifier]) {
            [self.gamepadBindings removeObjectForKey: existing];
        }
    }
    self.gamepadBindings[key] = identifier;
    [self persist];
}

- (void)clearGamepadBindingForButton:(GSButton)button {
    NSString *key = GSButtonKey(button);
    if (key.length == 0) {
        return;
    }
    [self.gamepadBindings removeObjectForKey: key];
    [self persist];
}

- (nullable NSString *)gamepadBindingLabelForButton:(GSButton)button {
    NSString *key = GSButtonKey(button);
    NSString *identifier = key.length > 0 ? self.gamepadBindings[key] : nil;
    if (identifier.length == 0) {
        return nil;
    }
    return GSGamepadLabel(identifier);
}

#pragma mark - 持久化

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
    return [directory URLByAppendingPathComponent: @"keymap.json"];
}

- (NSDictionary *)dictionaryRepresentation {
    return @{
        @"version": @2,
        @"touch": @{
            @"scale": @(self.touchScale),
            @"opacity": @(self.touchOpacity),
        },
        @"visibility": [self touchVisibilityRepresentation],
        @"keyboard": [self.keyboardBindings copy],
        @"gamepad": [self.gamepadBindings copy],
        @"layouts": [self touchLayoutsRepresentation],
    };
}

/// 按键簇布局的持久化形式：system → (cluster → {x,y,scale})；
/// 没自定义过的簇不写盘，读回时自然回落该系统的内置默认值。
- (NSDictionary *)touchLayoutsRepresentation {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    for (NSString *system in self.touchLayouts) {
        NSMutableDictionary<NSNumber *, GSTouchClusterLayout *> *bucket = self.touchLayouts[system];
        NSMutableDictionary *entries = [NSMutableDictionary dictionary];
        for (NSNumber *number in bucket) {
            GSTouchClusterLayout *layout = bucket[number];
            entries[GSTouchClusterKey((GSTouchCluster)number.integerValue)] = @{
                @"x": @(layout.x),
                @"y": @(layout.y),
                @"scale": @(layout.scale),
            };
        }
        if (entries.count > 0) {
            result[system] = entries;
        }
    }
    return result;
}

/// 可见性覆盖的持久化形式：system → (cluster → BOOL)
- (NSDictionary *)touchVisibilityRepresentation {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    for (NSString *system in self.touchVisibility) {
        NSMutableDictionary<NSNumber *, NSNumber *> *bucket = self.touchVisibility[system];
        NSMutableDictionary *entries = [NSMutableDictionary dictionary];
        for (NSNumber *number in bucket) {
            entries[GSTouchClusterKey((GSTouchCluster)number.integerValue)] = bucket[number];
        }
        if (entries.count > 0) {
            result[system] = entries;
        }
    }
    return result;
}

- (void)persist {
    NSURL *url = [GSKeyMapping storeURL];
    if (url == nil) {
        return;
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject: [self dictionaryRepresentation]
                                                  options: NSJSONWritingPrettyPrinted
                                                    error: NULL];
    if (data == nil) {
        return;
    }
    [data writeToURL: url atomically: YES];
}

- (void)loadFromDisk {
    NSURL *url = [GSKeyMapping storeURL];
    if (url == nil) {
        return;
    }
    NSData *data = [NSData dataWithContentsOfURL: url];
    if (data == nil) {
        return;
    }
    id object = [NSJSONSerialization JSONObjectWithData: data options: 0 error: NULL];
    if (![object isKindOfClass: [NSDictionary class]]) {
        return;
    }
    NSDictionary *dictionary = object;

    // 触屏整体：scale / opacity；顺带识别旧格式的 4 个全局显示开关（迁移用）
    NSDictionary *touch = dictionary[@"touch"];
    BOOL hasLegacyShowFlags = NO;
    if ([touch isKindOfClass: [NSDictionary class]]) {
        if ([touch[@"scale"] isKindOfClass: [NSNumber class]]) { self.touchScale = [touch[@"scale"] doubleValue]; }
        if ([touch[@"opacity"] isKindOfClass: [NSNumber class]]) { self.touchOpacity = [touch[@"opacity"] doubleValue]; }
        hasLegacyShowFlags = ([touch[@"showDPad"] isKindOfClass: [NSNumber class]] ||
                              [touch[@"showFace"] isKindOfClass: [NSNumber class]] ||
                              [touch[@"showShoulders"] isKindOfClass: [NSNumber class]] ||
                              [touch[@"showStartSelect"] isKindOfClass: [NSNumber class]]);
    }

    NSDictionary *keyboard = dictionary[@"keyboard"];
    if ([keyboard isKindOfClass: [NSDictionary class]]) {
        NSMutableDictionary<NSString *, NSNumber *> *loaded = [NSMutableDictionary dictionary];
        for (id key in keyboard) {
            id value = keyboard[key];
            if ([key isKindOfClass: [NSString class]] && [value isKindOfClass: [NSNumber class]]) {
                loaded[key] = value;
            }
        }
        self.keyboardBindings = loaded;
    }

    // 布局：新格式是 system → cluster → {x,y,scale}；
    // 旧格式是扁平的 cluster → {x,y,scale}（本次「按系统区分」之前写下的），要先迁移。
    NSMutableDictionary<NSNumber *, GSTouchClusterLayout *> *legacyFlat = [NSMutableDictionary dictionary];
    NSDictionary *layouts = dictionary[@"layouts"];
    if ([layouts isKindOfClass: [NSDictionary class]]) {
        BOOL isLegacy = ([layouts[@"dpad"] isKindOfClass: [NSDictionary class]] ||
                         [layouts[@"face"] isKindOfClass: [NSDictionary class]] ||
                         [layouts[@"startSelect"] isKindOfClass: [NSDictionary class]] ||
                         [layouts[@"menu"] isKindOfClass: [NSDictionary class]] ||
                         [layouts[@"touchScreen"] isKindOfClass: [NSDictionary class]]);
        if (isLegacy) {
            [legacyFlat addEntriesFromDictionary: GSParseLayoutBucket(layouts)];
        } else {
            for (id systemKey in layouts) {
                if (![systemKey isKindOfClass: [NSString class]] ||
                    ![layouts[systemKey] isKindOfClass: [NSDictionary class]]) {
                    continue;
                }
                NSMutableDictionary<NSNumber *, GSTouchClusterLayout *> *bucket = GSParseLayoutBucket(layouts[systemKey]);
                if (bucket.count > 0) {
                    self.touchLayouts[[systemKey lowercaseString]] = bucket;
                }
            }
        }
    }

    // 可见性（新格式）：system → cluster → BOOL
    NSDictionary *visibility = dictionary[@"visibility"];
    if ([visibility isKindOfClass: [NSDictionary class]]) {
        for (id systemKey in visibility) {
            if (![systemKey isKindOfClass: [NSString class]] ||
                ![visibility[systemKey] isKindOfClass: [NSDictionary class]]) {
                continue;
            }
            NSDictionary *entries = visibility[systemKey];
            NSMutableDictionary<NSNumber *, NSNumber *> *bucket = [NSMutableDictionary dictionary];
            for (id key in entries) {
                if ([key isKindOfClass: [NSString class]] && [entries[key] isKindOfClass: [NSNumber class]]) {
                    bucket[@(GSTouchClusterFromKey(key))] = entries[key];
                }
            }
            if (bucket.count > 0) {
                self.touchVisibility[[systemKey lowercaseString]] = bucket;
            }
        }
    }

    // 旧格式迁移：把扁平的布局与 4 个全局开关，平摊到每个已接入系统里有对应簇的那些
    if (legacyFlat.count > 0 || hasLegacyShowFlags) {
        for (NSString *system in @[@"nes", @"snes", @"gb", @"gbc", @"gba", @"nds"]) {
            NSArray<NSNumber *> *clusters = GSClustersForSystem(system);
            for (NSNumber *number in legacyFlat) {
                if ([clusters containsObject: number]) {
                    [self setLayout: legacyFlat[number]
                         forCluster: (GSTouchCluster)number.integerValue
                          forSystem: system];
                }
            }
            if (hasLegacyShowFlags) {
                for (NSNumber *number in clusters) {
                    GSTouchCluster cluster = (GSTouchCluster)number.integerValue;
                    BOOL visible = YES;
                    switch (cluster) {
                        case GSTouchClusterDPad:        visible = [touch[@"showDPad"] boolValue]; break;
                        case GSTouchClusterFace:        visible = [touch[@"showFace"] boolValue]; break;
                        case GSTouchClusterL:
                        case GSTouchClusterR:           visible = [touch[@"showShoulders"] boolValue]; break;
                        case GSTouchClusterStartSelect: visible = [touch[@"showStartSelect"] boolValue]; break;
                        default:                        visible = YES; break;  // menu / touchScreen 是新增的
                    }
                    [self setVisible: visible forCluster: cluster forSystem: system];
                }
            }
        }
    }

    NSDictionary *gamepad = dictionary[@"gamepad"];
    if ([gamepad isKindOfClass: [NSDictionary class]]) {
        NSMutableDictionary<NSString *, NSString *> *loaded = [NSMutableDictionary dictionary];
        for (id key in gamepad) {
            id value = gamepad[key];
            if ([key isKindOfClass: [NSString class]] && [value isKindOfClass: [NSString class]]) {
                loaded[key] = value;
            }
        }
        self.gamepadBindings = loaded;
    }
}

- (void)resetToDefaults {
    [self applyDefaultTouchProfile];
    [self.touchLayouts removeAllObjects];
    [self.touchVisibility removeAllObjects];
    self.keyboardBindings = [[GSKeyMapping defaultKeyboardBindings] mutableCopy];
    self.gamepadBindings = [[GSKeyMapping defaultGamepadBindings] mutableCopy];
    [self persist];
}

@end
