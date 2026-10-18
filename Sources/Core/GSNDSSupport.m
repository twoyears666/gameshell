//
//  GSNDSSupport.m
//  Gameshell
//
//  GSNDSSupport 的实现：BIOS / 固件文件管理 + NDS 运行选项 + 触摸几何换算。
//  细节与取舍见头文件注释；这里只说两件容易踩的事：
//  1) 导入 BIOS 文件必须 startAccessingSecurityScopedResource（「文件」App 给的是
//     沙盒外的 URL），复制完立刻 stop；
//  2) 触摸换算与核心 input.cpp 的 TouchMode::Touch 分支严格对齐 ——
//     核心把 pointer 的 int16 值先按 buffer 尺寸放大，再判断落没落在下屏矩形里，
//     所以我们给出去的值必须落在「下屏矩形」内，不能按整块缓冲给。
//

#import "GSNDSSupport.h"
#import "GSLog.h"

NSString *const GSBiosFileName7        = @"bios7.bin";
NSString *const GSBiosFileName9        = @"bios9.bin";
NSString *const GSBiosFileNameFirmware = @"firmware.bin";

/// 单屏尺寸（melonDS 的 VIDEO_WIDTH / VIDEO_HEIGHT）
static const CGFloat kGSScreenWidth = 256.0;
static const CGFloat kGSScreenHeight = 192.0;

/// BIOS 相关错误
static NSString *const GSNDSSupportErrorDomain = @"GSNDSSupportErrorDomain";

@interface GSNDSSupport ()
@property (nonatomic, assign) BOOL loaded;
@end

@implementation GSNDSSupport

// 这个选项属性自己实现了 getter / setter，所以这里显式接上 ivar
@synthesize screenLayout = _screenLayout;

+ (instancetype)shared {
    static GSNDSSupport *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[GSNDSSupport alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        // 内置默认：上下双屏
        _screenLayout = GSNDSScreenLayoutTopBottom;
    }
    return self;
}

#pragma mark - BIOS / 固件

+ (NSURL *)biosDirectoryURL {
    NSFileManager *manager = [NSFileManager defaultManager];
    NSURL *documents = [manager URLForDirectory: NSDocumentDirectory
                                       inDomain: NSUserDomainMask
                              appropriateForURL: nil
                                         create: YES
                                          error: NULL];
    NSURL *directory = [documents URLByAppendingPathComponent: @"Bios" isDirectory: YES];
    [manager createDirectoryAtURL: directory withIntermediateDirectories: YES attributes: nil error: NULL];
    return directory;
}

/// 只有这三个固定名才允许写进 BIOS 目录，别的一律拒绝
+ (BOOL)isValidBIOSName:(NSString *)name {
    return [name isEqualToString: GSBiosFileName7]
        || [name isEqualToString: GSBiosFileName9]
        || [name isEqualToString: GSBiosFileNameFirmware];
}

- (NSURL *)urlForBIOSName:(NSString *)name {
    return [[GSNDSSupport biosDirectoryURL] URLByAppendingPathComponent: name];
}

- (BOOL)hasBIOSFileNamed:(NSString *)name {
    if (![GSNDSSupport isValidBIOSName: name]) {
        return NO;
    }
    return [[NSFileManager defaultManager] fileExistsAtPath: [self urlForBIOSName: name].path];
}

- (BOOL)importBIOSFileAtURL:(NSURL *)url asName:(NSString *)name error:(NSError **)error {
    if (![GSNDSSupport isValidBIOSName: name]) {
        if (error) {
            *error = [NSError errorWithDomain: GSNDSSupportErrorDomain code: 1 userInfo: @{
                NSLocalizedDescriptionKey: [NSString stringWithFormat: @"不认识的 BIOS 文件名：%@", name ?: @""]}];
        }
        return NO;
    }

    NSFileManager *manager = [NSFileManager defaultManager];
    BOOL scoped = [url startAccessingSecurityScopedResource];

    // 覆盖写：用户重新导入同一件时应该就地替换，不要报「已存在」
    NSURL *destination = [self urlForBIOSName: name];
    [manager removeItemAtURL: destination error: NULL];

    NSError *copyError = nil;
    BOOL ok = [manager copyItemAtURL: url toURL: destination error: &copyError];
    if (scoped) {
        [url stopAccessingSecurityScopedResource];
    }

    if (!ok) {
        GSLogI(@"nds", @"导入 BIOS 失败：name=%@ 源=%@ error=%@",
               name, url.path, copyError.localizedDescription ?: @"（无说明）");
        if (error) {
            *error = copyError;
        }
        return NO;
    }
    GSLogI(@"nds", @"已导入 BIOS：name=%@ 源=%@", name, url.path);
    return YES;
}

- (void)removeBIOSFileNamed:(NSString *)name {
    if (![GSNDSSupport isValidBIOSName: name]) {
        return;
    }
    [[NSFileManager defaultManager] removeItemAtURL: [self urlForBIOSName: name] error: NULL];
}

#pragma mark - 运行选项

- (NSURL *)optionsURL {
    NSFileManager *manager = [NSFileManager defaultManager];
    NSURL *documents = [manager URLForDirectory: NSDocumentDirectory
                                       inDomain: NSUserDomainMask
                              appropriateForURL: nil
                                         create: YES
                                          error: NULL];
    return [documents URLByAppendingPathComponent: @"nds.json"];
}

- (void)loadIfNeeded {
    if (self.loaded) {
        return;
    }
    self.loaded = YES;

    NSData *data = [NSData dataWithContentsOfURL: [self optionsURL]];
    if (data.length == 0) {
        return;   // 没配过：用内置默认
    }
    id json = [NSJSONSerialization JSONObjectWithData: data options: 0 error: NULL];
    if (![json isKindOfClass: [NSDictionary class]]) {
        return;
    }
    NSDictionary *dict = (NSDictionary *)json;
    if (dict[@"screenLayout"] != nil) {
        NSInteger raw = [dict[@"screenLayout"] integerValue];
        if (raw >= GSNDSScreenLayoutTopBottom && raw <= GSNDSScreenLayoutBottomOnly) {
            _screenLayout = (GSNDSScreenLayout)raw;
        }
    }
}

- (GSNDSScreenLayout)screenLayout {
    [self loadIfNeeded];
    return _screenLayout;
}

- (void)setScreenLayout:(GSNDSScreenLayout)screenLayout {
    [self loadIfNeeded];
    _screenLayout = screenLayout;
    [self persist];
}

- (void)persist {
    NSDictionary *dict = @{
        @"screenLayout":    @(_screenLayout),
    };
    NSData *data = [NSJSONSerialization dataWithJSONObject: dict options: NSJSONWritingPrettyPrinted error: NULL];
    if (data == nil) {
        return;
    }
    [data writeToURL: [self optionsURL] atomically: YES];
}

#pragma mark - 给核心用的取值

- (NSString *)melonDSScreenLayoutValue {
    // 与 libretro.cpp 里 melonds_screen_layout 的解析严格对应
    switch ([self screenLayout]) {
        case GSNDSScreenLayoutLeftRight:    return @"Left/Right";
        case GSNDSScreenLayoutTopOnly:      return @"Top Only";
        case GSNDSScreenLayoutBottomOnly:   return @"Bottom Only";
        case GSNDSScreenLayoutTopBottom:
        default:                            return @"Top/Bottom";
    }
}

#pragma mark - 几何换算

/// 某布局下 buffer 的像素尺寸 + 下屏在 buffer 里的像素偏移（gap 恒为 0）
+ (BOOL)geometryForLayout:(GSNDSScreenLayout)layout
                    width:(CGFloat *)outWidth
                   height:(CGFloat *)outHeight
                   offsetX:(CGFloat *)outOffsetX
                   offsetY:(CGFloat *)outOffsetY {
    CGFloat width = 0, height = 0, offsetX = 0, offsetY = 0;
    switch (layout) {
        case GSNDSScreenLayoutTopBottom:
            width = kGSScreenWidth;      height = kGSScreenHeight * 2;
            offsetX = 0;                 offsetY = kGSScreenHeight;
            break;
        case GSNDSScreenLayoutLeftRight:
            width = kGSScreenWidth * 2;  height = kGSScreenHeight;
            offsetX = kGSScreenWidth;    offsetY = 0;
            break;
        case GSNDSScreenLayoutBottomOnly:
            width = kGSScreenWidth;      height = kGSScreenHeight;
            offsetX = 0;                 offsetY = 0;
            break;
        case GSNDSScreenLayoutTopOnly:
        default:
            // 只上屏：没有下屏，也就没有触摸区
            width = kGSScreenWidth;      height = kGSScreenHeight;
            offsetX = 0;                 offsetY = 0;
            return NO;
    }
    if (outWidth)   { *outWidth = width; }
    if (outHeight)  { *outHeight = height; }
    if (outOffsetX) { *outOffsetX = offsetX; }
    if (outOffsetY) { *outOffsetY = offsetY; }
    return YES;
}

+ (CGSize)bufferSizeForLayout:(GSNDSScreenLayout)layout {
    CGFloat width = 0, height = 0;
    [self geometryForLayout: layout width: &width height: &height offsetX: NULL offsetY: NULL];
    return CGSizeMake(width, height);
}

+ (CGRect)bottomScreenNormalizedRectForLayout:(GSNDSScreenLayout)layout {
    CGFloat width = 0, height = 0, offsetX = 0, offsetY = 0;
    if (![self geometryForLayout: layout width: &width height: &height offsetX: &offsetX offsetY: &offsetY]) {
        return CGRectNull;
    }
    return CGRectMake(offsetX / width, offsetY / height,
                      kGSScreenWidth / width, kGSScreenHeight / height);
}

+ (CGPoint)pointerForNormalizedTouch:(CGPoint)point layout:(GSNDSScreenLayout)layout {
    CGFloat width = 0, height = 0, offsetX = 0, offsetY = 0;
    [self geometryForLayout: layout width: &width height: &height offsetX: &offsetX offsetY: &offsetY];

    // 归一化到 [0,1]，夹紧防止越界值把触摸点送出下屏
    double nx = point.x, ny = point.y;
    if (nx < 0.0) { nx = 0.0; } else if (nx > 1.0) { nx = 1.0; }
    if (ny < 0.0) { ny = 0.0; } else if (ny > 1.0) { ny = 1.0; }

    // 下屏内点 (nx, ny) → buffer 像素 → libretro pointer（0x8000 为缓冲中心偏移）
    double bufferX = offsetX + nx * kGSScreenWidth;
    double bufferY = offsetY + ny * kGSScreenHeight;
    double pointerX = (bufferX / width) * 65536.0 - 32768.0;
    double pointerY = (bufferY / height) * 65536.0 - 32768.0;

    if (pointerX < -32768.0) { pointerX = -32768.0; } else if (pointerX > 32767.0) { pointerX = 32767.0; }
    if (pointerY < -32768.0) { pointerY = -32768.0; } else if (pointerY > 32767.0) { pointerY = 32767.0; }
    return CGPointMake(pointerX, pointerY);
}

@end
