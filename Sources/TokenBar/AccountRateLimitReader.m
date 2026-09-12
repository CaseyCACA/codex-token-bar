#import "AccountRateLimitReader.h"

static NSString *const TBAccountRateLimitErrorDomain = @"com.casey.tokenbar.account-rate-limits";

static NSError *TBAccountError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:TBAccountRateLimitErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

static NSDictionary *TBAccountDictionary(id value) {
    return [value isKindOfClass:NSDictionary.class] ? value : nil;
}

static NSNumber *TBAccountNumber(id value) {
    return [value isKindOfClass:NSNumber.class] ? value : nil;
}

TBDashboardSnapshot *TBParseAccountRateLimitsResponse(NSData *data, NSDate *fetchedAt, NSError **error) {
    NSDictionary *message = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (![message isKindOfClass:NSDictionary.class]) return nil;
    NSDictionary *result = TBAccountDictionary(message[@"result"]);
    NSDictionary *byLimitID = TBAccountDictionary(result[@"rateLimitsByLimitId"]);
    NSDictionary *rateLimits = TBAccountDictionary(byLimitID[@"codex"]);
    if (!rateLimits) rateLimits = TBAccountDictionary(result[@"rateLimits"]);
    NSDictionary *primary = TBAccountDictionary(rateLimits[@"primary"]);
    NSNumber *used = TBAccountNumber(primary[@"usedPercent"]);
    if (!rateLimits || !used) {
        if (error) *error = TBAccountError(2, @"账户接口没有返回 Codex 主额度");
        return nil;
    }

    TBDashboardSnapshot *snapshot = [TBDashboardSnapshot new];
    snapshot.hasRateLimit = YES;
    snapshot.limitID = [rateLimits[@"limitId"] isKindOfClass:NSString.class] ? rateLimits[@"limitId"] : @"codex";
    snapshot.limitName = [rateLimits[@"limitName"] isKindOfClass:NSString.class] ? rateLimits[@"limitName"] : nil;
    snapshot.usedPercent = used.doubleValue;
    snapshot.windowMinutes = [TBAccountNumber(primary[@"windowDurationMins"]) integerValue];
    NSNumber *reset = TBAccountNumber(primary[@"resetsAt"]);
    if (reset) snapshot.resetDate = [NSDate dateWithTimeIntervalSince1970:reset.doubleValue];
    snapshot.sourceFile = @"account/rateLimits/read";
    snapshot.sourceModifiedAt = fetchedAt;
    snapshot.tokenEventAt = fetchedAt;
    return snapshot;
}

@implementation TBAccountRateLimitReader

- (TBDashboardSnapshot *)readCurrentRateLimitsWithError:(NSError **)error {
    NSURL *executable = [self codexExecutableURL];
    if (!executable) {
        if (error) *error = TBAccountError(1, @"找不到 Codex App Server");
        return nil;
    }

    NSTask *task = [NSTask new];
    task.executableURL = executable;
    task.arguments = @[@"app-server", @"--stdio"];
    NSPipe *inputPipe = [NSPipe pipe];
    NSPipe *outputPipe = [NSPipe pipe];
    task.standardInput = inputPipe;
    task.standardOutput = outputPipe;
    task.standardError = [NSFileHandle fileHandleWithNullDevice];

    NSError *launchError = nil;
    if (![task launchAndReturnError:&launchError]) {
        if (error) *error = launchError;
        return nil;
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 8 * NSEC_PER_SEC),
                   dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        if (task.running) [task terminate];
    });

    NSFileHandle *writer = inputPipe.fileHandleForWriting;
    NSFileHandle *reader = outputPipe.fileHandleForReading;
    NSDictionary *initialize = @{
        @"id": @1,
        @"method": @"initialize",
        @"params": @{
            @"clientInfo": @{
                @"name": @"token-bar",
                @"title": @"Token Bar",
                @"version": @"0.2.0"
            },
            @"capabilities": @{
                @"experimentalApi": @YES
            }
        }
    };
    [self writeMessage:initialize toHandle:writer];
    NSDictionary *initializeResponse = [self readResponseWithID:@1 fromHandle:reader];
    if (!initializeResponse) {
        if (task.running) [task terminate];
        if (error) *error = TBAccountError(3, @"Codex App Server 初始化超时");
        return nil;
    }

    [self writeMessage:@{ @"method": @"initialized" } toHandle:writer];
    [self writeMessage:@{ @"id": @2, @"method": @"account/rateLimits/read", @"params": NSNull.null } toHandle:writer];
    NSDictionary *rateResponse = [self readResponseWithID:@2 fromHandle:reader];
    [writer closeFile];
    if (task.running) [task terminate];
    if (!rateResponse) {
        if (error) *error = TBAccountError(4, @"账户额度读取超时");
        return nil;
    }

    NSData *responseData = [NSJSONSerialization dataWithJSONObject:rateResponse options:0 error:error];
    if (!responseData) return nil;
    return TBParseAccountRateLimitsResponse(responseData, NSDate.date, error);
}

- (NSURL *)codexExecutableURL {
    NSArray<NSString *> *paths = @[
        @"/Applications/ChatGPT.app/Contents/Resources/codex",
        @"/Applications/Codex.app/Contents/Resources/codex",
        @"/opt/homebrew/bin/codex",
        @"/usr/local/bin/codex"
    ];
    for (NSString *path in paths) {
        if ([NSFileManager.defaultManager isExecutableFileAtPath:path]) {
            return [NSURL fileURLWithPath:path];
        }
    }
    return nil;
}

- (void)writeMessage:(NSDictionary *)message toHandle:(NSFileHandle *)handle {
    NSData *json = [NSJSONSerialization dataWithJSONObject:message options:0 error:nil];
    NSMutableData *line = [json mutableCopy];
    const unsigned char newline = '\n';
    [line appendBytes:&newline length:1];
    [handle writeData:line];
}

- (NSDictionary *)readResponseWithID:(NSNumber *)requestID fromHandle:(NSFileHandle *)handle {
    NSMutableData *line = [NSMutableData data];
    while (YES) {
        NSData *byte = [handle readDataOfLength:1];
        if (byte.length == 0) return nil;
        const unsigned char *value = byte.bytes;
        if (value[0] == '\n') {
            if (line.length == 0) continue;
            NSDictionary *message = [NSJSONSerialization JSONObjectWithData:line options:0 error:nil];
            if ([message isKindOfClass:NSDictionary.class] && [message[@"id"] isEqual:requestID]) {
                return message;
            }
            [line setLength:0];
        } else if (value[0] != '\r') {
            [line appendData:byte];
        }
    }
}

@end
