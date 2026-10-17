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

#pragma mark - 触屏元素

/// 每个触屏元素的稳定键名（持久化用）
static NSString *GSTouchElementKey(GSTouchElement element) {
    switch (element) {
        case GSTouchElementDPad:        return @"dpad";
        case GSTouchElementA:           return @"A";
        case GSTouchElementB:           return @"B";
        case GSTouchElementX:           return @"X";
        case GSTouchElementY:           return @"Y";
        case GSTouchElementL:           return @"L";
        case GSTouchElementR:           return @"R";
        case GSTouchElementStart:       return @"start";
        case GSTouchElementSelect:      return @"select";
        case GSTouchElementMenu:        return @"menu";
        case GSTouchElementTouchScreen: return @"touchScreen";
    }
    return @"";
}

/// 全部触屏元素（按 rawValue 顺序，遍历 / 迁移用）
static const GSTouchElement GSTouchElementAll[] = {
    GSTouchElementDPad, GSTouchElementA, GSTouchElementB, GSTouchElementX, GSTouchElementY,
    GSTouchElementL, GSTouchElementR, GSTouchElementStart, GSTouchElementSelect,
    GSTouchElementMenu, GSTouchElementTouchScreen,
};

/// 键名 → 元素；不认识返回 NO（可能是旧「按键簇」的键名，交给迁移路径处理）
static BOOL GSTouchElementFromKey(NSString *key, GSTouchElement *outElement) {
    for (size_t index = 0; index < sizeof(GSTouchElementAll) / sizeof(GSTouchElementAll[0]); index++) {
        if ([GSTouchElementKey(GSTouchElementAll[index]) isEqualToString: key]) {
            if (outElement != NULL) { *outElement = GSTouchElementAll[index]; }
            return YES;
        }
    }
    return NO;
}

/// 把 {x,y,scale} 字典解析成布局并夹紧。keymap.json 是用户可写的边界数据，
/// 读回时按头文件声明的范围夹紧（x / y 0–1、scale 0.6–1.6），
/// 免得写坏的数值把按键甩到手柄区域之外。
static GSTouchElementLayout *GSTouchElementLayoutFromValues(NSDictionary *values) {
    GSTouchElementLayout *layout = [GSTouchElementLayout layoutWithX: 0.5 y: 0.5 scale: 1.0];
    if ([values[@"x"] isKindOfClass: [NSNumber class]]) {
        layout.x = MAX((CGFloat)0.0, MIN((CGFloat)1.0, (CGFloat)[values[@"x"] doubleValue]));
    }
    if ([values[@"y"] isKindOfClass: [NSNumber class]]) {
        layout.y = MAX((CGFloat)0.0, MIN((CGFloat)1.0, (CGFloat)[values[@"y"] doubleValue]));
    }
    if ([values[@"scale"] isKindOfClass: [NSNumber class]]) {
        layout.scale = MAX((CGFloat)0.6, MIN((CGFloat)1.6, (CGFloat)[values[@"scale"] doubleValue]));
    }
    return layout;
}

/// 参与配置的系统的标识全集（迁移旧「全局一套」数据时平摊到这些系统）
static NSArray<NSString *> *GSAllSystemIdentifiers(void) {
    return @[@"nes", @"snes", @"gb", @"gbc", @"gba", @"nds"];
}

/// 判断一份键位字典是「按系统分桶」的新格式还是「全局一套」的旧格式。
/// 新格式：值都是字典（system → 桶）；旧格式：值都是标量（按钮键名 → usage / 标识）。
static BOOL GSBucketIsPerSystem(NSDictionary *source) {
    for (id value in source.allValues) {
        if ([value isKindOfClass: [NSDictionary class]]) {
            return YES;
        }
    }
    return NO;
}

/// 解析一份「按钮键名 → HID usage」桶（键盘）
static NSDictionary<NSString *, NSNumber *> *GSParseKeyboardBucket(NSDictionary *source) {
    NSMutableDictionary<NSString *, NSNumber *> *bucket = [NSMutableDictionary dictionary];
    for (id key in source) {
        id value = source[key];
        if ([key isKindOfClass: [NSString class]] && [value isKindOfClass: [NSNumber class]]) {
            bucket[key] = value;
        }
    }
    return bucket;
}

/// 解析一份「按钮键名 → 手柄标识」桶（手柄）
static NSDictionary<NSString *, NSString *> *GSParseGamepadBucket(NSDictionary *source) {
    NSMutableDictionary<NSString *, NSString *> *bucket = [NSMutableDictionary dictionary];
    for (id key in source) {
        id value = source[key];
        if ([key isKindOfClass: [NSString class]] && [value isKindOfClass: [NSString class]]) {
            bucket[key] = value;
        }
    }
    return bucket;
}

#pragma mark - 各系统的触屏元素 profile

/// 系统标识规整（小写）；nil / 空归成空串
static NSString *GSSystemKey(NSString *systemIdentifier) {
    return [(systemIdentifier ?: @"") lowercaseString];
}

/// 8 位机：NES / GB / GBC（没有 L / R 肩键，也没有 X / Y）
static BOOL GSIsEightBitSystem(NSString *systemIdentifier) {
    NSString *system = GSSystemKey(systemIdentifier);
    return [system isEqualToString: @"nes"] || [system isEqualToString: @"gb"] || [system isEqualToString: @"gbc"];
}

/// 某系统有哪些触屏元素
static NSArray<NSNumber *> *GSElementsForSystem(NSString *systemIdentifier) {
    NSString *system = GSSystemKey(systemIdentifier);
    if ([system isEqualToString: @"nds"]) {
        return @[@(GSTouchElementDPad), @(GSTouchElementA), @(GSTouchElementB), @(GSTouchElementX), @(GSTouchElementY),
                 @(GSTouchElementL), @(GSTouchElementR), @(GSTouchElementStart), @(GSTouchElementSelect),
                 @(GSTouchElementMenu), @(GSTouchElementTouchScreen)];
    }
    if ([system isEqualToString: @"snes"]) {
        return @[@(GSTouchElementDPad), @(GSTouchElementA), @(GSTouchElementB), @(GSTouchElementX), @(GSTouchElementY),
                 @(GSTouchElementL), @(GSTouchElementR), @(GSTouchElementStart), @(GSTouchElementSelect)];
    }
    if (GSIsEightBitSystem(system)) {
        return @[@(GSTouchElementDPad), @(GSTouchElementA), @(GSTouchElementB),
                 @(GSTouchElementStart), @(GSTouchElementSelect)];
    }
    // gba / 未知：十字键 + A/B + L/R + START/SELECT
    return @[@(GSTouchElementDPad), @(GSTouchElementA), @(GSTouchElementB),
             @(GSTouchElementL), @(GSTouchElementR), @(GSTouchElementStart), @(GSTouchElementSelect)];
}

/// 某元素在某系统里的内置默认布局（归一化中心 + 缩放 1.0）。
/// 数值由旧「按键簇」默认（参照 Delta「Standard GBA / Standard DS」皮肤、667×375 画布）
/// 拆分成单个按键：簇中心 + 单键相对簇中心的偏移（A/B 斜排、A/B/X/Y 菱形、START/SELECT 并排）。
static GSTouchElementLayout *GSDefaultLayoutForElement(GSTouchElement element, NSString *systemIdentifier) {
    if ([GSSystemKey(systemIdentifier) isEqualToString: @"nds"]) {
        switch (element) {
            case GSTouchElementDPad:        return [GSTouchElementLayout layoutWithX: 0.115 y: 0.791 scale: 1.0];
            case GSTouchElementA:           return [GSTouchElementLayout layoutWithX: 0.920 y: 0.791 scale: 1.0];
            case GSTouchElementB:           return [GSTouchElementLayout layoutWithX: 0.878 y: 0.865 scale: 1.0];
            case GSTouchElementX:           return [GSTouchElementLayout layoutWithX: 0.878 y: 0.717 scale: 1.0];
            case GSTouchElementY:           return [GSTouchElementLayout layoutWithX: 0.836 y: 0.791 scale: 1.0];
            case GSTouchElementL:           return [GSTouchElementLayout layoutWithX: 0.361 y: 0.628 scale: 1.0];
            case GSTouchElementR:           return [GSTouchElementLayout layoutWithX: 0.640 y: 0.628 scale: 1.0];
            case GSTouchElementStart:       return [GSTouchElementLayout layoutWithX: 0.626 y: 0.767 scale: 1.0];
            case GSTouchElementSelect:      return [GSTouchElementLayout layoutWithX: 0.444 y: 0.767 scale: 1.0];
            case GSTouchElementMenu:        return [GSTouchElementLayout layoutWithX: 0.292 y: 0.768 scale: 1.0];
            case GSTouchElementTouchScreen: return [GSTouchElementLayout layoutWithX: 0.735 y: 0.323 scale: 1.0];
        }
        return [GSTouchElementLayout layoutWithX: 0.5 y: 0.5 scale: 1.0];
    }

    // nes / gb / gbc / snes / gba / 未知：Delta「Standard GBA」
    switch (element) {
        case GSTouchElementDPad:        return [GSTouchElementLayout layoutWithX: 0.143 y: 0.745 scale: 1.0];
        case GSTouchElementA:           return [GSTouchElementLayout layoutWithX: 0.907 y: 0.736 scale: 1.0];
        case GSTouchElementB:           return [GSTouchElementLayout layoutWithX: 0.829 y: 0.849 scale: 1.0];
        case GSTouchElementX:           return [GSTouchElementLayout layoutWithX: 0.865 y: 0.710 scale: 1.0];
        case GSTouchElementY:           return [GSTouchElementLayout layoutWithX: 0.823 y: 0.784 scale: 1.0];
        case GSTouchElementL:           return [GSTouchElementLayout layoutWithX: 0.097 y: 0.093 scale: 1.0];
        case GSTouchElementR:           return [GSTouchElementLayout layoutWithX: 0.903 y: 0.093 scale: 1.0];
        case GSTouchElementStart:       return [GSTouchElementLayout layoutWithX: 0.592 y: 0.928 scale: 1.0];
        case GSTouchElementSelect:      return [GSTouchElementLayout layoutWithX: 0.410 y: 0.928 scale: 1.0];
        case GSTouchElementMenu:        return [GSTouchElementLayout layoutWithX: 0.292 y: 0.768 scale: 1.0];
        case GSTouchElementTouchScreen: return [GSTouchElementLayout layoutWithX: 0.735 y: 0.323 scale: 1.0];
    }
    return [GSTouchElementLayout layoutWithX: 0.5 y: 0.5 scale: 1.0];
}

#pragma mark - 旧「按键簇」→ 新元素（迁移用）

/// 旧「按键簇」在某系统里的默认中心（只为迁移：把用户改过的簇中心挪到拆分后的按键上）
static BOOL GSLegacyClusterDefaultCenter(NSString *clusterKey, NSString *systemIdentifier, CGPoint *outCenter) {
    BOOL isNDS = [GSSystemKey(systemIdentifier) isEqualToString: @"nds"];
    if ([clusterKey isEqualToString: @"dpad"]) {
        *outCenter = isNDS ? CGPointMake(0.115, 0.791) : CGPointMake(0.143, 0.745);
    } else if ([clusterKey isEqualToString: @"face"]) {
        *outCenter = isNDS ? CGPointMake(0.878, 0.791) : CGPointMake(0.865, 0.784);
    } else if ([clusterKey isEqualToString: @"L"]) {
        *outCenter = isNDS ? CGPointMake(0.361, 0.628) : CGPointMake(0.097, 0.093);
    } else if ([clusterKey isEqualToString: @"R"]) {
        *outCenter = isNDS ? CGPointMake(0.640, 0.628) : CGPointMake(0.903, 0.093);
    } else if ([clusterKey isEqualToString: @"startSelect"]) {
        *outCenter = isNDS ? CGPointMake(0.535, 0.767) : CGPointMake(0.501, 0.928);
    } else if ([clusterKey isEqualToString: @"menu"]) {
        *outCenter = CGPointMake(0.292, 0.768);
    } else if ([clusterKey isEqualToString: @"touchScreen"]) {
        *outCenter = CGPointMake(0.735, 0.323);
    } else {
        return NO;
    }
    return YES;
}

/// 旧「按键簇」键名 → 它包含的触屏元素（face / startSelect 是「一组拆成多个」）
static NSArray<NSNumber *> *GSElementsForLegacyClusterKey(NSString *clusterKey) {
    if ([clusterKey isEqualToString: @"dpad"])        return @[@(GSTouchElementDPad)];
    if ([clusterKey isEqualToString: @"face"])        return @[@(GSTouchElementA), @(GSTouchElementB), @(GSTouchElementX), @(GSTouchElementY)];
    if ([clusterKey isEqualToString: @"L"])           return @[@(GSTouchElementL)];
    if ([clusterKey isEqualToString: @"R"])           return @[@(GSTouchElementR)];
    if ([clusterKey isEqualToString: @"startSelect"]) return @[@(GSTouchElementSelect), @(GSTouchElementStart)];
    if ([clusterKey isEqualToString: @"menu"])        return @[@(GSTouchElementMenu)];
    if ([clusterKey isEqualToString: @"touchScreen"]) return @[@(GSTouchElementTouchScreen)];
    return @[];
}

#pragma mark - 布局对象

@implementation GSTouchElementLayout

+ (instancetype)layoutWithX:(CGFloat)x y:(CGFloat)y scale:(CGFloat)scale {
    GSTouchElementLayout *layout = [[GSTouchElementLayout alloc] init];
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
    return [GSTouchElementLayout layoutWithX: self.x y: self.y scale: self.scale];
}

@end

#pragma mark -

@interface GSKeyMapping ()
/// 按系统的键盘绑定：system → (按钮键名 → HID usage)；没存进来的系统回落内置默认
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableDictionary<NSString *, NSNumber *> *> *keyboardBindings;
/// 按系统的手柄绑定：system → (按钮键名 → 手柄标识)；没存进来的系统回落内置默认
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableDictionary<NSString *, NSString *> *> *gamepadBindings;
/// 按系统的自定义布局：system → (GSTouchElement 的 NSNumber → layout)；没存进来的就是内置默认
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableDictionary<NSNumber *, GSTouchElementLayout *> *> *touchLayouts;
/// 按系统的可见性覆盖：system → (GSTouchElement 的 NSNumber → NSNumber(BOOL))；没有覆盖时按默认显示
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableDictionary<NSNumber *, NSNumber *> *> *touchVisibility;

+ (NSDictionary<NSString *, NSNumber *> *)defaultKeyboardBindings;
+ (NSDictionary<NSString *, NSString *> *)defaultGamepadBindings;
- (NSDictionary *)keyboardRepresentation;
- (NSDictionary *)gamepadRepresentation;
/// 读盘时吃进一条布局：键名是新元素键就直接写入，是旧「按键簇」键名就拆开迁移
- (void)ingestLayoutValues:(NSDictionary *)values forKey:(NSString *)key intoSystem:(NSString *)system;
/// 读盘时吃进一条可见性（同上，兼容旧「按键簇」键名）
- (void)ingestVisibility:(NSNumber *)value forKey:(NSString *)key intoSystem:(NSString *)system;
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
        // 键盘 / 手柄不再预置「全局一套」：各系统没自定义时按默认值回落（见读写方法）
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

#pragma mark - 触屏元素（按系统区分）

+ (NSArray<NSNumber *> *)touchElementsForSystem:(NSString *)systemIdentifier {
    return GSElementsForSystem(systemIdentifier);
}

+ (NSString *)displayNameForElement:(GSTouchElement)element {
    switch (element) {
        case GSTouchElementDPad:        return @"十字键";
        case GSTouchElementA:           return @"A 键";
        case GSTouchElementB:           return @"B 键";
        case GSTouchElementX:           return @"X 键";
        case GSTouchElementY:           return @"Y 键";
        case GSTouchElementL:           return @"L 肩键";
        case GSTouchElementR:           return @"R 肩键";
        case GSTouchElementStart:       return @"START";
        case GSTouchElementSelect:      return @"SELECT";
        case GSTouchElementMenu:        return @"Menu";
        case GSTouchElementTouchScreen: return @"触摸屏";
    }
    return @"按键";
}

- (GSTouchElementLayout *)layoutForElement:(GSTouchElement)element forSystem:(NSString *)systemIdentifier {
    NSMutableDictionary<NSNumber *, GSTouchElementLayout *> *bucket = self.touchLayouts[GSSystemKey(systemIdentifier)];
    GSTouchElementLayout *layout = bucket[@(element)];
    return layout != nil ? layout : GSDefaultLayoutForElement(element, systemIdentifier);
}

- (void)setLayout:(GSTouchElementLayout *)layout forElement:(GSTouchElement)element forSystem:(NSString *)systemIdentifier {
    if (layout == nil) {
        return;
    }
    NSString *system = GSSystemKey(systemIdentifier);
    NSMutableDictionary<NSNumber *, GSTouchElementLayout *> *bucket = self.touchLayouts[system];
    if (bucket == nil) {
        bucket = [NSMutableDictionary dictionary];
        self.touchLayouts[system] = bucket;
    }
    // 值域收在这里，播放器与设置页都不必再各自夹一遍
    bucket[@(element)] = [GSTouchElementLayout layoutWithX: MAX((CGFloat)0.0, MIN((CGFloat)1.0, layout.x))
                                                         y: MAX((CGFloat)0.0, MIN((CGFloat)1.0, layout.y))
                                                     scale: MAX((CGFloat)0.6, MIN((CGFloat)1.6, layout.scale))];
}

- (void)applyScale:(CGFloat)scale toAllElementsForSystem:(NSString *)systemIdentifier {
    CGFloat clamped = MAX((CGFloat)0.6, MIN((CGFloat)1.6, scale));
    NSString *system = GSSystemKey(systemIdentifier);
    NSMutableDictionary<NSNumber *, GSTouchElementLayout *> *bucket = self.touchLayouts[system];
    if (bucket == nil) {
        bucket = [NSMutableDictionary dictionary];
        self.touchLayouts[system] = bucket;
    }
    // 触摸屏是「屏」不是按键，不参与整体大小应用
    for (NSNumber *number in GSElementsForSystem(systemIdentifier)) {
        GSTouchElement element = (GSTouchElement)number.integerValue;
        if (element == GSTouchElementTouchScreen) {
            continue;
        }
        GSTouchElementLayout *current = [self layoutForElement: element forSystem: systemIdentifier];
        bucket[number] = [GSTouchElementLayout layoutWithX: current.x y: current.y scale: clamped];
    }
    [self persist];
}

- (BOOL)hasCustomTouchLayoutForSystem:(NSString *)systemIdentifier {
    NSMutableDictionary<NSNumber *, GSTouchElementLayout *> *bucket = self.touchLayouts[GSSystemKey(systemIdentifier)];
    return bucket.count > 0;
}

- (void)resetTouchLayoutsForSystem:(NSString *)systemIdentifier {
    NSString *system = GSSystemKey(systemIdentifier);
    [self.touchLayouts removeObjectForKey: system];
    [self.touchVisibility removeObjectForKey: system];
    [self persist];
}

- (BOOL)isElementVisible:(GSTouchElement)element forSystem:(NSString *)systemIdentifier {
    NSNumber *override = self.touchVisibility[GSSystemKey(systemIdentifier)][@(element)];
    if (override != nil) {
        return override.boolValue;
    }
    // 没被显式改过时，属于该系统元素集合的就默认显示
    for (NSNumber *number in GSElementsForSystem(systemIdentifier)) {
        if ((GSTouchElement)number.integerValue == element) {
            return YES;
        }
    }
    return NO;
}

- (void)setVisible:(BOOL)visible forElement:(GSTouchElement)element forSystem:(NSString *)systemIdentifier {
    NSString *system = GSSystemKey(systemIdentifier);
    NSMutableDictionary<NSNumber *, NSNumber *> *bucket = self.touchVisibility[system];
    if (bucket == nil) {
        bucket = [NSMutableDictionary dictionary];
        self.touchVisibility[system] = bucket;
    }
    bucket[@(element)] = @(visible);
}

#pragma mark - 读盘迁移（旧「按键簇」→ 新元素）

/// 吃进一条布局：键名是新元素键就直接写入；是旧「按键簇」键名就按「相对旧簇中心的偏移不变」拆给每个按键。
- (void)ingestLayoutValues:(NSDictionary *)values forKey:(NSString *)key intoSystem:(NSString *)system {
    NSArray<NSNumber *> *systemElements = GSElementsForSystem(system);
    GSTouchElement element;
    if (GSTouchElementFromKey(key, &element)) {
        if ([systemElements containsObject: @(element)]) {
            [self setLayout: GSTouchElementLayoutFromValues(values) forElement: element forSystem: system];
        }
        return;
    }

    CGPoint oldCenter;
    if (!GSLegacyClusterDefaultCenter(key, system, &oldCenter)) {
        return;
    }
    CGFloat baseX = [values[@"x"] isKindOfClass: [NSNumber class]] ? [values[@"x"] doubleValue] : oldCenter.x;
    CGFloat baseY = [values[@"y"] isKindOfClass: [NSNumber class]] ? [values[@"y"] doubleValue] : oldCenter.y;
    CGFloat baseScale = [values[@"scale"] isKindOfClass: [NSNumber class]] ? [values[@"scale"] doubleValue] : 1.0;

    for (NSNumber *number in GSElementsForLegacyClusterKey(key)) {
        if (![systemElements containsObject: number]) {
            continue;
        }
        GSTouchElement child = (GSTouchElement)number.integerValue;
        GSTouchElementLayout *def = GSDefaultLayoutForElement(child, system);
        [self setLayout: [GSTouchElementLayout layoutWithX: baseX + (def.x - oldCenter.x)
                                                         y: baseY + (def.y - oldCenter.y)
                                                     scale: baseScale]
             forElement: child
              forSystem: system];
    }
}

/// 吃进一条可见性：新元素键直接写入；旧「按键簇」键名就拆给簇里的每个元素。
- (void)ingestVisibility:(NSNumber *)value forKey:(NSString *)key intoSystem:(NSString *)system {
    NSArray<NSNumber *> *systemElements = GSElementsForSystem(system);
    GSTouchElement element;
    if (GSTouchElementFromKey(key, &element)) {
        if ([systemElements containsObject: @(element)]) {
            [self setVisible: value.boolValue forElement: element forSystem: system];
        }
        return;
    }
    for (NSNumber *number in GSElementsForLegacyClusterKey(key)) {
        if ([systemElements containsObject: number]) {
            [self setVisible: value.boolValue forElement: (GSTouchElement)number.integerValue forSystem: system];
        }
    }
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

#pragma mark - 键盘（按系统分桶）

/// 某系统的键盘桶；没存进来时回落内置默认（只读用，不落盘）
- (NSDictionary<NSString *, NSNumber *> *)keyboardBucketForSystem:(NSString *)systemIdentifier {
    NSDictionary *bucket = self.keyboardBindings[GSSystemKey(systemIdentifier)];
    return bucket != nil ? bucket : [GSKeyMapping defaultKeyboardBindings];
}

/// 某系统的键盘桶，可写版：没有就按内置默认造一个并正式存进来，
/// 这样「清除某个键」也会被记住（否则清完又被默认值顶回来）。
- (NSMutableDictionary<NSString *, NSNumber *> *)writableKeyboardBucketForSystem:(NSString *)systemIdentifier {
    NSString *system = GSSystemKey(systemIdentifier);
    NSMutableDictionary<NSString *, NSNumber *> *bucket = self.keyboardBindings[system];
    if (bucket == nil) {
        bucket = [[GSKeyMapping defaultKeyboardBindings] mutableCopy];
        self.keyboardBindings[system] = bucket;
    }
    return bucket;
}

- (GSButton)buttonForKeyboardUsage:(NSInteger)usage forSystem:(NSString *)systemIdentifier {
    NSDictionary<NSString *, NSNumber *> *bucket = [self keyboardBucketForSystem: systemIdentifier];
    for (NSString *key in bucket) {
        if ([bucket[key] integerValue] == usage) {
            return GSButtonFromKey(key);
        }
    }
    return 0;
}

- (void)setKeyboardUsage:(NSInteger)usage forButton:(GSButton)button forSystem:(NSString *)systemIdentifier {
    NSString *key = GSButtonKey(button);
    if (key.length == 0) {
        return;
    }
    NSMutableDictionary<NSString *, NSNumber *> *bucket = [self writableKeyboardBucketForSystem: systemIdentifier];
    // 一个键只绑一个按钮：先清掉同一 usage 的旧绑定
    for (NSString *existing in [bucket.allKeys copy]) {
        if ([bucket[existing] integerValue] == usage) {
            [bucket removeObjectForKey: existing];
        }
    }
    bucket[key] = @(usage);
    [self persist];
}

- (void)clearKeyboardBindingForButton:(GSButton)button forSystem:(NSString *)systemIdentifier {
    NSString *key = GSButtonKey(button);
    if (key.length == 0) {
        return;
    }
    // 先确保该系统的桶存在，再删键 —— 否则删完仍会回落到默认值
    [self writableKeyboardBucketForSystem: systemIdentifier];
    [self.keyboardBindings[GSSystemKey(systemIdentifier)] removeObjectForKey: key];
    [self persist];
}

- (nullable NSString *)keyboardBindingLabelForButton:(GSButton)button forSystem:(NSString *)systemIdentifier {
    NSString *key = GSButtonKey(button);
    if (key.length == 0) {
        return nil;
    }
    NSNumber *usage = [self keyboardBucketForSystem: systemIdentifier][key];
    if (usage == nil) {
        return nil;
    }
    return GSKeyboardLabel(usage.integerValue);
}

- (BOOL)hasCustomKeyboardForSystem:(NSString *)systemIdentifier {
    return self.keyboardBindings[GSSystemKey(systemIdentifier)] != nil;
}

- (void)resetKeyboardForSystem:(NSString *)systemIdentifier {
    [self.keyboardBindings removeObjectForKey: GSSystemKey(systemIdentifier)];
    [self persist];
}

#pragma mark - 手柄（按系统分桶）

/// 某系统的手柄桶；没存进来时回落内置默认（只读用，不落盘）
- (NSDictionary<NSString *, NSString *> *)gamepadBucketForSystem:(NSString *)systemIdentifier {
    NSDictionary *bucket = self.gamepadBindings[GSSystemKey(systemIdentifier)];
    return bucket != nil ? bucket : [GSKeyMapping defaultGamepadBindings];
}

/// 某系统的手柄桶，可写版（同键盘：清键也要能被记住）
- (NSMutableDictionary<NSString *, NSString *> *)writableGamepadBucketForSystem:(NSString *)systemIdentifier {
    NSString *system = GSSystemKey(systemIdentifier);
    NSMutableDictionary<NSString *, NSString *> *bucket = self.gamepadBindings[system];
    if (bucket == nil) {
        bucket = [[GSKeyMapping defaultGamepadBindings] mutableCopy];
        self.gamepadBindings[system] = bucket;
    }
    return bucket;
}

- (GSButton)buttonForGamepadIdentifier:(NSString *)identifier forSystem:(NSString *)systemIdentifier {
    if (identifier.length == 0) {
        return 0;
    }
    NSDictionary<NSString *, NSString *> *bucket = [self gamepadBucketForSystem: systemIdentifier];
    for (NSString *key in bucket) {
        if ([bucket[key] isEqualToString: identifier]) {
            return GSButtonFromKey(key);
        }
    }
    return 0;
}

- (void)setGamepadIdentifier:(NSString *)identifier forButton:(GSButton)button forSystem:(NSString *)systemIdentifier {
    NSString *key = GSButtonKey(button);
    if (key.length == 0 || identifier.length == 0) {
        return;
    }
    NSMutableDictionary<NSString *, NSString *> *bucket = [self writableGamepadBucketForSystem: systemIdentifier];
    for (NSString *existing in [bucket.allKeys copy]) {
        if ([bucket[existing] isEqualToString: identifier]) {
            [bucket removeObjectForKey: existing];
        }
    }
    bucket[key] = identifier;
    [self persist];
}

- (void)clearGamepadBindingForButton:(GSButton)button forSystem:(NSString *)systemIdentifier {
    NSString *key = GSButtonKey(button);
    if (key.length == 0) {
        return;
    }
    [self writableGamepadBucketForSystem: systemIdentifier];
    [self.gamepadBindings[GSSystemKey(systemIdentifier)] removeObjectForKey: key];
    [self persist];
}

- (nullable NSString *)gamepadBindingLabelForButton:(GSButton)button forSystem:(NSString *)systemIdentifier {
    NSString *key = GSButtonKey(button);
    if (key.length == 0) {
        return nil;
    }
    NSString *identifier = [self gamepadBucketForSystem: systemIdentifier][key];
    if (identifier.length == 0) {
        return nil;
    }
    return GSGamepadLabel(identifier);
}

- (BOOL)hasCustomGamepadForSystem:(NSString *)systemIdentifier {
    return self.gamepadBindings[GSSystemKey(systemIdentifier)] != nil;
}

- (void)resetGamepadForSystem:(NSString *)systemIdentifier {
    [self.gamepadBindings removeObjectForKey: GSSystemKey(systemIdentifier)];
    [self persist];
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
        @"version": @4,
        @"touch": @{
            @"scale": @(self.touchScale),
            @"opacity": @(self.touchOpacity),
        },
        @"visibility": [self touchVisibilityRepresentation],
        @"keyboard": [self keyboardRepresentation],
        @"gamepad": [self gamepadRepresentation],
        @"layouts": [self touchLayoutsRepresentation],
    };
}

/// 键盘绑定的持久化形式：system → (按钮键名 → HID usage)。
/// 没自定义过的系统不写盘，读回时自然回落该系统的内置默认值。
- (NSDictionary *)keyboardRepresentation {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    for (NSString *system in self.keyboardBindings) {
        NSDictionary<NSString *, NSNumber *> *bucket = self.keyboardBindings[system];
        if (bucket.count > 0) {
            result[system] = [bucket copy];
        }
    }
    return result;
}

/// 手柄绑定的持久化形式：system → (按钮键名 → 手柄标识)
- (NSDictionary *)gamepadRepresentation {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    for (NSString *system in self.gamepadBindings) {
        NSDictionary<NSString *, NSString *> *bucket = self.gamepadBindings[system];
        if (bucket.count > 0) {
            result[system] = [bucket copy];
        }
    }
    return result;
}

/// 元素布局的持久化形式：system → (元素键名 → {x,y,scale})；
/// 没自定义过的元素不写盘，读回时自然回落该系统的内置默认值。
- (NSDictionary *)touchLayoutsRepresentation {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    for (NSString *system in self.touchLayouts) {
        NSMutableDictionary<NSNumber *, GSTouchElementLayout *> *bucket = self.touchLayouts[system];
        NSMutableDictionary *entries = [NSMutableDictionary dictionary];
        for (NSNumber *number in bucket) {
            GSTouchElementLayout *layout = bucket[number];
            entries[GSTouchElementKey((GSTouchElement)number.integerValue)] = @{
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

/// 可见性覆盖的持久化形式：system → (元素键名 → BOOL)
- (NSDictionary *)touchVisibilityRepresentation {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    for (NSString *system in self.touchVisibility) {
        NSMutableDictionary<NSNumber *, NSNumber *> *bucket = self.touchVisibility[system];
        NSMutableDictionary *entries = [NSMutableDictionary dictionary];
        for (NSNumber *number in bucket) {
            entries[GSTouchElementKey((GSTouchElement)number.integerValue)] = bucket[number];
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

    // 键盘：新格式是 system → (按钮键名 → usage)；旧格式是扁平的 按钮键名 → usage（要迁移）
    NSDictionary<NSString *, NSNumber *> *legacyKeyboard = nil;
    NSDictionary *keyboard = dictionary[@"keyboard"];
    if ([keyboard isKindOfClass: [NSDictionary class]]) {
        if (GSBucketIsPerSystem(keyboard)) {
            for (id systemKey in keyboard) {
                if (![systemKey isKindOfClass: [NSString class]] ||
                    ![keyboard[systemKey] isKindOfClass: [NSDictionary class]]) {
                    continue;
                }
                NSDictionary<NSString *, NSNumber *> *bucket = GSParseKeyboardBucket(keyboard[systemKey]);
                if (bucket.count > 0) {
                    self.keyboardBindings[[systemKey lowercaseString]] = [bucket mutableCopy];
                }
            }
        } else {
            legacyKeyboard = GSParseKeyboardBucket(keyboard);
        }
    }

    // 布局：新格式是 system → (元素键名 → {x,y,scale})。
    // 桶里若出现旧的「按键簇」键名（face / startSelect…），由 ingest 负责拆分迁移。
    // 更早的格式是扁平的 簇键名 → {x,y,scale}，平摊到各系统。
    NSDictionary *layouts = dictionary[@"layouts"];
    if ([layouts isKindOfClass: [NSDictionary class]]) {
        BOOL isFlatLegacy = NO;
        for (id key in layouts) {
            if ([key isKindOfClass: [NSString class]] && [layouts[key] isKindOfClass: [NSDictionary class]] &&
                ![GSAllSystemIdentifiers() containsObject: [key lowercaseString]]) {
                isFlatLegacy = YES;
                break;
            }
        }
        if (isFlatLegacy) {
            for (NSString *system in GSAllSystemIdentifiers()) {
                for (id key in layouts) {
                    if ([key isKindOfClass: [NSString class]] && [layouts[key] isKindOfClass: [NSDictionary class]]) {
                        [self ingestLayoutValues: layouts[key] forKey: key intoSystem: system];
                    }
                }
            }
        } else {
            for (id systemKey in layouts) {
                if (![systemKey isKindOfClass: [NSString class]] ||
                    ![layouts[systemKey] isKindOfClass: [NSDictionary class]]) {
                    continue;
                }
                NSString *system = [systemKey lowercaseString];
                NSDictionary *entries = layouts[systemKey];
                for (id key in entries) {
                    if ([key isKindOfClass: [NSString class]] && [entries[key] isKindOfClass: [NSDictionary class]]) {
                        [self ingestLayoutValues: entries[key] forKey: key intoSystem: system];
                    }
                }
            }
        }
    }

    // 可见性：system → (元素键名或旧簇键名 → BOOL)
    NSDictionary *visibility = dictionary[@"visibility"];
    if ([visibility isKindOfClass: [NSDictionary class]]) {
        for (id systemKey in visibility) {
            if (![systemKey isKindOfClass: [NSString class]] ||
                ![visibility[systemKey] isKindOfClass: [NSDictionary class]]) {
                continue;
            }
            NSString *system = [systemKey lowercaseString];
            NSDictionary *entries = visibility[systemKey];
            for (id key in entries) {
                if ([key isKindOfClass: [NSString class]] && [entries[key] isKindOfClass: [NSNumber class]]) {
                    [self ingestVisibility: entries[key] forKey: key intoSystem: system];
                }
            }
        }
    }

    // 旧格式迁移：把 4 个全局显示开关平摊到每个系统里对应的元素
    if (hasLegacyShowFlags) {
        BOOL (^legacyFlag)(NSString *) = ^BOOL(NSString *name) {
            NSNumber *value = touch[name];
            return value != nil ? value.boolValue : YES;
        };
        for (NSString *system in GSAllSystemIdentifiers()) {
            for (NSNumber *number in GSElementsForSystem(system)) {
                GSTouchElement element = (GSTouchElement)number.integerValue;
                BOOL visible = YES;
                switch (element) {
                    case GSTouchElementDPad:        visible = legacyFlag(@"showDPad"); break;
                    case GSTouchElementA:
                    case GSTouchElementB:
                    case GSTouchElementX:
                    case GSTouchElementY:           visible = legacyFlag(@"showFace"); break;
                    case GSTouchElementL:
                    case GSTouchElementR:           visible = legacyFlag(@"showShoulders"); break;
                    case GSTouchElementStart:
                    case GSTouchElementSelect:      visible = legacyFlag(@"showStartSelect"); break;
                    default:                        visible = YES; break;  // menu / touchScreen 是新增的
                }
                [self setVisible: visible forElement: element forSystem: system];
            }
        }
    }

    // 手柄：同上，新格式按系统分桶，旧格式（扁平）要迁移
    NSDictionary<NSString *, NSString *> *legacyGamepad = nil;
    NSDictionary *gamepad = dictionary[@"gamepad"];
    if ([gamepad isKindOfClass: [NSDictionary class]]) {
        if (GSBucketIsPerSystem(gamepad)) {
            for (id systemKey in gamepad) {
                if (![systemKey isKindOfClass: [NSString class]] ||
                    ![gamepad[systemKey] isKindOfClass: [NSDictionary class]]) {
                    continue;
                }
                NSDictionary<NSString *, NSString *> *bucket = GSParseGamepadBucket(gamepad[systemKey]);
                if (bucket.count > 0) {
                    self.gamepadBindings[[systemKey lowercaseString]] = [bucket mutableCopy];
                }
            }
        } else {
            legacyGamepad = GSParseGamepadBucket(gamepad);
        }
    }

    // 旧格式迁移：把「全局一套」的键盘 / 手柄绑定平摊给每个系统
    if (legacyKeyboard.count > 0 || legacyGamepad.count > 0) {
        for (NSString *system in GSAllSystemIdentifiers()) {
            if (legacyKeyboard.count > 0) {
                self.keyboardBindings[system] = [legacyKeyboard mutableCopy];
            }
            if (legacyGamepad.count > 0) {
                self.gamepadBindings[system] = [legacyGamepad mutableCopy];
            }
        }
    }
}

- (void)resetToDefaults {
    [self applyDefaultTouchProfile];
    [self.touchLayouts removeAllObjects];
    [self.touchVisibility removeAllObjects];
    // 键盘 / 手柄清空分桶即「所有系统都回落到内置默认」（读写方法里就是这么回落的）
    [self.keyboardBindings removeAllObjects];
    [self.gamepadBindings removeAllObjects];
    [self persist];
}

@end
