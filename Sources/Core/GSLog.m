//
//  GSLog.m
//  Gameshell
//
//  实现见头文件注释。写盘走一条串行队列，避免模拟线程 / 主线程互相抢文件句柄。
//

#import "GSLog.h"

NSString *const GSLogTagEmulator = @"emu";
NSString *const GSLogTagInput = @"input";
NSString *const GSLogTagROM = @"rom";

/// 日志文件上限：超过就删掉重来，免得无限增长（日志只用来诊断，不做长期归档）
static const unsigned long long GSLogMaxBytes = 1ull * 1024 * 1024;

@interface GSLog ()
/// 真正落盘的一行（tag + 消息）；两个公开入口都汇到这里
+ (void)writeTag:(NSString *)tag message:(NSString *)message;
@end

@implementation GSLog

/// 落盘用的串行队列（同一个文件句柄只被一条队列碰）
+ (dispatch_queue_t)writeQueue {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.twoyears666.gameshell.log", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

/// 时间戳格式化器（只在 writeQueue 上访问）
+ (NSDateFormatter *)timestampFormatter {
    static NSDateFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"MM-dd HH:mm:ss.SSS";
    });
    return formatter;
}

+ (nullable NSURL *)logDirectoryURL {
    NSURL *documents = [[NSFileManager defaultManager]
        URLForDirectory: NSDocumentDirectory
               inDomain: NSUserDomainMask
      appropriateForURL: nil
                 create: YES
                  error: NULL];
    if (documents == nil) {
        return nil;
    }
    return [documents URLByAppendingPathComponent: @"Logs" isDirectory: YES];
}

+ (nullable NSURL *)logFileURL {
    NSURL *directory = [self logDirectoryURL];
    return directory != nil ? [directory URLByAppendingPathComponent: @"gameshell.log"] : nil;
}

+ (unsigned long long)logFileSize {
    NSURL *url = [self logFileURL];
    if (url == nil) {
        return 0;
    }
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath: url.path error: NULL];
    return attributes != nil ? [attributes[NSFileSize] unsignedLongLongValue] : 0;
}

+ (void)clear {
    NSURL *url = [self logFileURL];
    if (url == nil) {
        return;
    }
    dispatch_async([self writeQueue], ^{
        [[NSFileManager defaultManager] removeItemAtURL: url error: NULL];
    });
}

+ (void)tag:(NSString *)tag format:(NSString *)format, ... {
    va_list arguments;
    va_start(arguments, format);
    NSString *message = [[NSString alloc] initWithFormat: format arguments: arguments];
    va_end(arguments);
    [self writeTag: tag message: message];
}

+ (void)tag:(NSString *)tag message:(NSString *)message {
    [self writeTag: tag message: message];
}

/// 打一行：先 NSLog（Xcode / Console 里实时看），再异步追加到日志文件
+ (void)writeTag:(NSString *)tag message:(NSString *)message {
    NSLog(@"[%@] %@", tag, message);

    NSURL *url = [self logFileURL];
    if (url == nil) {
        return;
    }
    dispatch_async([self writeQueue], ^{
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSURL *directory = [url URLByDeletingLastPathComponent];
        if (![fileManager fileExistsAtPath: directory.path]) {
            [fileManager createDirectoryAtURL: directory
                  withIntermediateDirectories: YES
                                   attributes: nil
                                        error: NULL];
        }

        // 超过上限就删掉重来：日志只用于诊断，不需要长期保留
        NSDictionary *attributes = [fileManager attributesOfItemAtPath: url.path error: NULL];
        if (attributes != nil && [attributes[NSFileSize] unsignedLongLongValue] > GSLogMaxBytes) {
            [fileManager removeItemAtURL: url error: NULL];
        }
        if (![fileManager fileExistsAtPath: url.path]) {
            [fileManager createFileAtPath: url.path contents: nil attributes: nil];
        }

        NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath: url.path];
        if (handle == nil) {
            return;
        }
        NSString *line = [NSString stringWithFormat: @"%@ [%@] %@\n",
                          [[self timestampFormatter] stringFromDate: [NSDate date]], tag, message];
        @try {
            [handle seekToEndOfFile];
            [handle writeData: [line dataUsingEncoding: NSUTF8StringEncoding]];
        } @catch (NSException *exception) {
            // 日志本身不能把调用方带崩：写失败就只留 NSLog
        }
        [handle closeFile];
    });
}

@end
