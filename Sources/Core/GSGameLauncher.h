#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// gameshell:// 深链所表达的动作
typedef NS_ENUM(NSInteger, GSLaunchAction) {
    GSLaunchActionUnknown = 0,
    GSLaunchActionHome,     // gameshell://home
    GSLaunchActionOpen,     // gameshell://open?url=https://...   —— 直接用 URL 打开
    GSLaunchActionPlay,     // gameshell://play?id=xxx             —— 按 id 在清单里找
    GSLaunchActionSearch,   // gameshell://search?q=xxx
};

/// URL 驱动的启动器：负责把外部 URL / gameshell:// 深链解析成「启动意图」。
@interface GSGameLauncher : NSObject

+ (GSLaunchAction)actionForURL:(NSURL *)url;
+ (nullable NSDictionary<NSString *, NSString *> *)parametersForURL:(NSURL *)url;
+ (NSString *)nameForAction:(GSLaunchAction)action;

/// 把 http(s) 或相对地址规整成 WebView 可加载的绝对 URL
+ (nullable NSURL *)normalizedGameURLFromString:(NSString *)string
                                        baseURL:(nullable NSURL *)baseURL;

/// 生成深链
+ (NSURL *)deepLinkWithAction:(GSLaunchAction)action
                   parameters:(NSDictionary<NSString *, NSString *> *)parameters;

@end

NS_ASSUME_NONNULL_END
