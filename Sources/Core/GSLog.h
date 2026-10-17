//
//  GSLog.h
//  Gameshell
//
//  轻量日志：同一条日志同时打到 NSLog（Xcode / Console.app）与沙盒
//  `Documents/Logs/gameshell.log`。日志落在 Documents 下，配合已声明的
//  UIFileSharingEnabled / LSSupportsOpeningDocumentsInPlace，可以直接在
//  「文件」App 里把 gameshell.log 取出来发给别人，不用连 Xcode。
//
//  这是「模拟器诊断」用的工具：模拟器核心是静态链接进主二进制的 C/C++，
//  真机上出问题（例如 NDS 闪退）拿不到 Xcode 控制台，只能靠落盘日志。
//
//  用法（ObjC）：GSLogI(@"emu", @"载入 ROM %@ 失败：%@", path, error);
//  用法（Swift）：GSLog.tag("emu", message: "启动会话 ...")   // 变参方法 Swift 调不了
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 常见 tag（只是约定，方便过滤；传字符串也完全可以）
extern NSString *const GSLogTagEmulator;   // 模拟器宿主 / 会话
extern NSString *const GSLogTagInput;      // 按键转发
extern NSString *const GSLogTagROM;        // ROM 导入 / 扫描

@interface GSLog : NSObject

/// ObjC 变参入口：tag + 格式化消息
+ (void)tag:(NSString *)tag format:(NSString *)format, ... NS_FORMAT_FUNCTION(2, 3);

/// Swift 入口（ObjC 变参方法在 Swift 里不可见，所以单独给一份非变参的）
+ (void)tag:(NSString *)tag message:(NSString *)message NS_SWIFT_NAME(tag(_:message:));

/// 日志文件位置（延迟创建，首次真正写日志时才建目录 / 文件）
+ (nullable NSURL *)logFileURL;

/// 当前日志文件大小（字节）；不存在返回 0
+ (unsigned long long)logFileSize;

/// 清空日志文件
+ (void)clear;

@end

/// 方便调用的宏（参数名别用 tag —— 会和选择器关键字 `tag:` 撞名，被宏替换掉）
#define GSLogI(tagName, ...) [GSLog tag:(tagName) format:__VA_ARGS__]

NS_ASSUME_NONNULL_END
