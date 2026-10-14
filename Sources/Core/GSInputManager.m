#import "GSInputManager.h"
#import <GameController/GameController.h>

NSNotificationName const GSInputManagerDidUpdateNotification = @"GSInputManagerDidUpdate";

#if TARGET_OS_IPHONE || TARGET_OS_MACCATALYST
#import <UIKit/UIKit.h>
#endif

@implementation GSInputSnapshot

- (instancetype)init {
    self = [super init];
    if (self) {
        _controllerNames = @[];
    }
    return self;
}

- (NSString *)summaryText {
    if (self.hardwareInputAvailable) {
        NSMutableArray<NSString *> *parts = [NSMutableArray array];
        if (self.controllerCount > 0) {
            [parts addObject: [NSString stringWithFormat: @"手柄 ×%ld", (long)self.controllerCount]];
        }
        if (self.keyboardConnected) {
            [parts addObject: @"键盘"];
        }
        if (self.pointerConnected) {
            [parts addObject: @"鼠标"];
        }
        return parts.count > 0 ? [parts componentsJoinedByString: @" · "] : @"已就绪";
    }
    return @"未检测到外设";
}

@end

#pragma mark -

@interface GSInputManager ()
@property (nonatomic, copy, readwrite) GSInputSnapshot *snapshot;
@property (nonatomic, assign) BOOL monitoring;

- (void)refreshSnapshot;
- (void)notifyDelegate;
- (void)handleControllerListChanged;
@end

@implementation GSInputManager

+ (instancetype)sharedManager {
    static GSInputManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[GSInputManager alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _snapshot = [[GSInputSnapshot alloc] init];
    }
    return self;
}

- (void)startMonitoring {
    if (self.monitoring) {
        return;
    }
    self.monitoring = YES;

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver: self
               selector: @selector(handleControllerListChanged)
                   name: GCControllerDidConnectNotification
                 object: nil];
    [center addObserver: self
               selector: @selector(handleControllerListChanged)
                   name: GCControllerDidDisconnectNotification
                 object: nil];

#if TARGET_OS_IPHONE || TARGET_OS_MACCATALYST
    [center addObserver: self
               selector: @selector(handleControllerListChanged)
                   name: GCKeyboardDidConnectNotification
                 object: nil];
    [center addObserver: self
               selector: @selector(handleControllerListChanged)
                   name: GCKeyboardDidDisconnectNotification
                 object: nil];
#endif

    [self handleControllerListChanged];
}

- (void)stopMonitoring {
    if (!self.monitoring) {
        return;
    }
    self.monitoring = NO;
    [[NSNotificationCenter defaultCenter] removeObserver: self];
}

- (void)handleControllerListChanged {
    [self refreshSnapshot];
    [self notifyDelegate];
}

- (void)reportKeyboardActivity {
    if (!self.snapshot.keyboardConnected) {
        self.snapshot.keyboardConnected = YES;
        [self notifyDelegate];
    }
}

- (void)reportPointerActivity {
    if (!self.snapshot.pointerConnected) {
        self.snapshot.pointerConnected = YES;
        [self notifyDelegate];
    }
}

- (void)refreshSnapshot {
    NSArray<GCController *> *controllers = [GCController controllers];
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (GCController *controller in controllers) {
        NSString *name = controller.vendorName ?: controller.productCategory;
        [names addObject: name ?: @"未知手柄"];
    }

    self.snapshot.controllerCount = controllers.count;
    self.snapshot.controllerNames = [names copy];

#if TARGET_OS_IPHONE || TARGET_OS_MACCATALYST
    if (@available(iOS 14.0, *)) {
        // GCKeyboard / GCMouse 在 iOS 14+ 提供键鼠在线探测
        if ([GCKeyboard coalescedKeyboard] != nil) {
            self.snapshot.keyboardConnected = YES;
        }
        if ([GCMouse current] != nil) {
            self.snapshot.pointerConnected = YES;
        }
    }
#else
    // macOS 自带键盘与鼠标 / 触控板，视为始终可用
    self.snapshot.keyboardConnected = YES;
    self.snapshot.pointerConnected = YES;
#endif

    self.snapshot.hardwareInputAvailable =
        self.snapshot.controllerCount > 0 ||
        self.snapshot.keyboardConnected ||
        self.snapshot.pointerConnected;
}

- (void)notifyDelegate {
    void (^work)(void) = ^{
        [[NSNotificationCenter defaultCenter] postNotificationName: GSInputManagerDidUpdateNotification
                                                            object: self];
        [self.delegate inputManagerDidUpdate: self];
    };
    if ([NSThread isMainThread]) {
        work();
    } else {
        dispatch_async(dispatch_get_main_queue(), work);
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver: self];
}

@end
