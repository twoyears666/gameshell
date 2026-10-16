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

#pragma mark - 按键簇布局

/// 每个按键簇的稳定键名（持久化用）
static NSString *GSTouchClusterKey(GSTouchCluster cluster) {
    switch (cluster) {
        case GSTouchClusterDPad:        return @"dpad";
        case GSTouchClusterFace:        return @"face";
        case GSTouchClusterL:           return @"L";
        case GSTouchClusterR:           return @"R";
        case GSTouchClusterStartSelect: return @"startSelect";
    }
    return @"";
}

static GSTouchCluster GSTouchClusterFromKey(NSString *key) {
    for (NSNumber *number in [GSKeyMapping touchClusters]) {
        GSTouchCluster cluster = (GSTouchCluster)number.integerValue;
        if ([GSTouchClusterKey(cluster) isEqualToString: key]) {
            return cluster;
        }
    }
    return GSTouchClusterDPad;
}

/// 各按键簇的内置默认布局（归一化中心 + 缩放），对应播放器里的默认观感
static GSTouchClusterLayout *GSDefaultLayoutForCluster(GSTouchCluster cluster) {
    switch (cluster) {
        case GSTouchClusterDPad:        return [GSTouchClusterLayout layoutWithX: 0.12 y: 0.78 scale: 1.0];
        case GSTouchClusterFace:        return [GSTouchClusterLayout layoutWithX: 0.88 y: 0.78 scale: 1.0];
        case GSTouchClusterL:           return [GSTouchClusterLayout layoutWithX: 0.11 y: 0.11 scale: 1.0];
        case GSTouchClusterR:           return [GSTouchClusterLayout layoutWithX: 0.89 y: 0.11 scale: 1.0];
        case GSTouchClusterStartSelect: return [GSTouchClusterLayout layoutWithX: 0.50 y: 0.94 scale: 1.0];
    }
    return [GSTouchClusterLayout layoutWithX: 0.5 y: 0.5 scale: 1.0];
}

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
/// 用户自定义过的按键簇布局（key = GSTouchCluster 的 NSNumber）；没存进来的就是内置默认
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, GSTouchClusterLayout *> *touchLayouts;

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
        [self applyDefaultTouchProfile];
        _keyboardBindings = [[GSKeyMapping defaultKeyboardBindings] mutableCopy];
        _gamepadBindings = [[GSKeyMapping defaultGamepadBindings] mutableCopy];
        _touchLayouts = [NSMutableDictionary dictionary];
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

#pragma mark - 触屏

- (void)applyDefaultTouchProfile {
    _touchScale = 1.0;
    _touchOpacity = 0.92;
    _touchShowDPad = YES;
    _touchShowFace = YES;
    _touchShowShoulders = YES;
    _touchShowStartSelect = YES;
}

- (void)setTouchScale:(CGFloat)touchScale {
    _touchScale = MAX((CGFloat)0.6, MIN((CGFloat)1.4, touchScale));
}

- (void)setTouchOpacity:(CGFloat)touchOpacity {
    _touchOpacity = MAX((CGFloat)0.3, MIN((CGFloat)1.0, touchOpacity));
}

#pragma mark - 触屏按键簇布局

+ (NSArray<NSNumber *> *)touchClusters {
    return @[
        @(GSTouchClusterDPad), @(GSTouchClusterFace),
        @(GSTouchClusterL), @(GSTouchClusterR),
        @(GSTouchClusterStartSelect),
    ];
}

+ (NSString *)displayNameForCluster:(GSTouchCluster)cluster {
    switch (cluster) {
        case GSTouchClusterDPad:        return @"十字键";
        case GSTouchClusterFace:        return @"A / B";
        case GSTouchClusterL:           return @"L 肩键";
        case GSTouchClusterR:           return @"R 肩键";
        case GSTouchClusterStartSelect: return @"START / SELECT";
    }
    return @"按键簇";
}

- (GSTouchClusterLayout *)layoutForCluster:(GSTouchCluster)cluster {
    GSTouchClusterLayout *layout = self.touchLayouts[@(cluster)];
    return layout != nil ? layout : GSDefaultLayoutForCluster(cluster);
}

- (void)setLayout:(GSTouchClusterLayout *)layout forCluster:(GSTouchCluster)cluster {
    if (layout == nil) {
        return;
    }
    // 值域收在这里，播放器与设置页都不必再各自夹一遍
    self.touchLayouts[@(cluster)] = [GSTouchClusterLayout layoutWithX: MAX((CGFloat)0.0, MIN((CGFloat)1.0, layout.x))
                                                                     y: MAX((CGFloat)0.0, MIN((CGFloat)1.0, layout.y))
                                                                 scale: MAX((CGFloat)0.6, MIN((CGFloat)1.6, layout.scale))];
}

- (BOOL)hasCustomTouchLayout {
    return self.touchLayouts.count > 0;
}

- (void)resetTouchLayouts {
    [self.touchLayouts removeAllObjects];
    [self persist];
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
        @"version": @1,
        @"touch": @{
            @"scale": @(self.touchScale),
            @"opacity": @(self.touchOpacity),
            @"showDPad": @(self.touchShowDPad),
            @"showFace": @(self.touchShowFace),
            @"showShoulders": @(self.touchShowShoulders),
            @"showStartSelect": @(self.touchShowStartSelect),
        },
        @"keyboard": [self.keyboardBindings copy],
        @"gamepad": [self.gamepadBindings copy],
        @"layouts": [self touchLayoutsRepresentation],
    };
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

    NSDictionary *touch = dictionary[@"touch"];
    if ([touch isKindOfClass: [NSDictionary class]]) {
        id scale = touch[@"scale"];
        id opacity = touch[@"opacity"];
        if ([scale isKindOfClass: [NSNumber class]]) { self.touchScale = [scale doubleValue]; }
        if ([opacity isKindOfClass: [NSNumber class]]) { self.touchOpacity = [opacity doubleValue]; }
        if ([touch[@"showDPad"] isKindOfClass: [NSNumber class]]) { self.touchShowDPad = [touch[@"showDPad"] boolValue]; }
        if ([touch[@"showFace"] isKindOfClass: [NSNumber class]]) { self.touchShowFace = [touch[@"showFace"] boolValue]; }
        if ([touch[@"showShoulders"] isKindOfClass: [NSNumber class]]) { self.touchShowShoulders = [touch[@"showShoulders"] boolValue]; }
        if ([touch[@"showStartSelect"] isKindOfClass: [NSNumber class]]) { self.touchShowStartSelect = [touch[@"showStartSelect"] boolValue]; }
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

    NSDictionary *layouts = dictionary[@"layouts"];
    if ([layouts isKindOfClass: [NSDictionary class]]) {
        NSMutableDictionary<NSNumber *, GSTouchClusterLayout *> *loaded = [NSMutableDictionary dictionary];
        for (id key in layouts) {
            id entry = layouts[key];
            if (![key isKindOfClass: [NSString class]] || ![entry isKindOfClass: [NSDictionary class]]) {
                continue;
            }
            NSDictionary *values = entry;
            GSTouchClusterLayout *layout = [GSTouchClusterLayout layoutWithX: 0.5 y: 0.5 scale: 1.0];
            if ([values[@"x"] isKindOfClass: [NSNumber class]]) { layout.x = [values[@"x"] doubleValue]; }
            if ([values[@"y"] isKindOfClass: [NSNumber class]]) { layout.y = [values[@"y"] doubleValue]; }
            if ([values[@"scale"] isKindOfClass: [NSNumber class]]) { layout.scale = [values[@"scale"] doubleValue]; }
            loaded[@(GSTouchClusterFromKey(key))] = layout;
        }
        self.touchLayouts = loaded;
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

/// 按键簇布局的持久化形式：没自定义过的簇不写盘，读回时自然回落内置默认值
- (NSDictionary *)touchLayoutsRepresentation {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    for (NSNumber *number in [GSKeyMapping touchClusters]) {
        GSTouchClusterLayout *layout = self.touchLayouts[number];
        if (layout == nil) {
            continue;
        }
        result[GSTouchClusterKey((GSTouchCluster)number.integerValue)] = @{
            @"x": @(layout.x),
            @"y": @(layout.y),
            @"scale": @(layout.scale),
        };
    }
    return result;
}

- (void)resetToDefaults {
    [self applyDefaultTouchProfile];
    [self.touchLayouts removeAllObjects];
    self.keyboardBindings = [[GSKeyMapping defaultKeyboardBindings] mutableCopy];
    self.gamepadBindings = [[GSKeyMapping defaultGamepadBindings] mutableCopy];
    [self persist];
}

@end
