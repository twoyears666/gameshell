#import "GSGameLauncher.h"

static NSString *const GSLaunchScheme = @"gameshell";

@implementation GSGameLauncher

+ (GSLaunchAction)actionForURL:(NSURL *)url {
    if (![[url.scheme lowercaseString] isEqualToString: GSLaunchScheme]) {
        // 非 gameshell:// 的外部 http(s) 链接，一律按「直接打开该 URL」处理
        NSString *scheme = [url.scheme lowercaseString];
        if ([scheme isEqualToString: @"http"] || [scheme isEqualToString: @"https"]) {
            return GSLaunchActionOpen;
        }
        return GSLaunchActionUnknown;
    }

    NSString *action = [self actionTokenForURL: url];
    if ([action isEqualToString: @"open"]) return GSLaunchActionOpen;
    if ([action isEqualToString: @"play"]) return GSLaunchActionPlay;
    if ([action isEqualToString: @"search"]) return GSLaunchActionSearch;
    if ([action isEqualToString: @"home"] || action.length == 0) return GSLaunchActionHome;
    return GSLaunchActionUnknown;
}

+ (NSString *)actionTokenForURL:(NSURL *)url {
    // gameshell://open?url=... → host = "open"
    if (url.host.length > 0) {
        return [url.host lowercaseString];
    }
    // gameshell:open?url=... → path = "/open"
    return [[url.path stringByReplacingOccurrencesOfString: @"/" withString: @""] lowercaseString];
}

+ (nullable NSDictionary<NSString *, NSString *> *)parametersForURL:(NSURL *)url {
    NSURLComponents *components = [NSURLComponents componentsWithURL: url resolvingAgainstBaseURL: NO];
    if (components == nil) {
        return nil;
    }
    NSMutableDictionary<NSString *, NSString *> *params = [NSMutableDictionary dictionary];
    for (NSURLQueryItem *item in components.queryItems ?: @[]) {
        if (item.name.length == 0) {
            continue;
        }
        params[item.name] = item.value ?: @"";
    }
    return [params copy];
}

+ (NSString *)nameForAction:(GSLaunchAction)action {
    switch (action) {
        case GSLaunchActionHome:   return @"home";
        case GSLaunchActionOpen:   return @"open";
        case GSLaunchActionPlay:   return @"play";
        case GSLaunchActionSearch: return @"search";
        default:                   return @"unknown";
    }
}

+ (nullable NSURL *)normalizedGameURLFromString:(NSString *)string
                                        baseURL:(nullable NSURL *)baseURL {
    NSString *trimmed = [string stringByTrimmingCharactersInSet:
                         [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        return nil;
    }
    // 已经是绝对 URL
    NSURL *direct = [NSURL URLWithString: trimmed];
    if (direct != nil && direct.scheme.length > 0) {
        NSString *scheme = [direct.scheme lowercaseString];
        if ([scheme isEqualToString: @"http"] || [scheme isEqualToString: @"https"]) {
            return direct;
        }
        // 其它自定义 scheme（如 Itch、Steam 唤醒）原样返回，由系统决定能否处理
        return direct;
    }
    // 相对路径 → 相对 baseURL 解析
    if (baseURL != nil) {
        return [NSURL URLWithString: trimmed relativeToURL: baseURL].absoluteURL;
    }
    return nil;
}

+ (NSURL *)deepLinkWithAction:(GSLaunchAction)action
                   parameters:(NSDictionary<NSString *, NSString *> *)parameters {
    NSURLComponents *components = [[NSURLComponents alloc] init];
    components.scheme = GSLaunchScheme;
    components.host = [self nameForAction: action];

    NSMutableArray<NSURLQueryItem *> *items = [NSMutableArray array];
    NSArray<NSString *> *sortedKeys = [parameters.allKeys sortedArrayUsingSelector: @selector(compare:)];
    for (NSString *key in sortedKeys) {
        [items addObject: [NSURLQueryItem queryItemWithName: key value: parameters[key]]];
    }
    components.queryItems = items.count > 0 ? items : nil;

    return components.URL;
}

@end
