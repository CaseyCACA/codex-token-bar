#import "TokenLogParser.h"

static NSString *const TBTokenLogErrorDomain = @"com.casey.tokenbar.logs";

typedef NS_ENUM(NSInteger, TBTokenLogErrorCode) {
    TBTokenLogErrorNoSessionDirectory = 1,
    TBTokenLogErrorNoSessionLog,
    TBTokenLogErrorNoTokenEvent,
};

static NSError *TBLogError(TBTokenLogErrorCode code, NSString *message) {
    return [NSError errorWithDomain:TBTokenLogErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

static NSDictionary *TBDictionary(id value) {
    return [value isKindOfClass:NSDictionary.class] ? value : nil;
}

static NSNumber *TBNumber(id value) {
    return [value isKindOfClass:NSNumber.class] ? value : nil;
}

@implementation TBDashboardSnapshot

- (instancetype)init {
    self = [super init];
    if (self) {
        _sourceFile = @"";
        _limitID = @"";
        _sourceModifiedAt = NSDate.date;
        _tokenEventAt = NSDate.distantPast;
    }
    return self;
}

- (double)remainingPercent {
    if (!self.hasRateLimit) return NAN;
    if (self.resetDate && [self.resetDate timeIntervalSinceNow] <= 0) return 100.0;
    return fmin(100.0, fmax(0.0, 100.0 - self.usedPercent));
}

- (double)contextUsedPercent {
    if (self.contextWindow <= 0) return NAN;
    return fmin(100.0, (double)self.lastInputTokens / (double)self.contextWindow * 100.0);
}

@end

TBDashboardSnapshot *TBParseLatestTokenEvent(
    NSData *data,
    NSString *sourceFile,
    NSDate *modifiedAt,
    NSError **error
) {
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!text) {
        if (error) *error = TBLogError(TBTokenLogErrorNoTokenEvent, @"token 日志不是有效文本");
        return nil;
    }

    NSArray<NSString *> *lines = [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
    for (NSString *line in lines.reverseObjectEnumerator) {
        if (line.length == 0) continue;
        NSData *lineData = [line dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *event = TBDictionary([NSJSONSerialization JSONObjectWithData:lineData options:0 error:nil]);
        NSDictionary *payload = TBDictionary(event[@"payload"]);
        if (![event[@"type"] isEqual:@"event_msg"] || ![payload[@"type"] isEqual:@"token_count"]) continue;

        NSDictionary *info = TBDictionary(payload[@"info"]);
        NSDictionary *total = TBDictionary(info[@"total_token_usage"]);
        NSDictionary *last = TBDictionary(info[@"last_token_usage"]);
        if (!total || !last) continue;

        TBDashboardSnapshot *snapshot = [TBDashboardSnapshot new];
        snapshot.taskTotalTokens = [TBNumber(total[@"total_tokens"]) longLongValue];
        snapshot.taskCachedTokens = [TBNumber(total[@"cached_input_tokens"]) longLongValue];
        snapshot.lastTotalTokens = [TBNumber(last[@"total_tokens"]) longLongValue];
        snapshot.lastInputTokens = [TBNumber(last[@"input_tokens"]) longLongValue];
        snapshot.lastCachedTokens = [TBNumber(last[@"cached_input_tokens"]) longLongValue];
        snapshot.lastOutputTokens = [TBNumber(last[@"output_tokens"]) longLongValue];
        snapshot.contextWindow = [TBNumber(info[@"model_context_window"]) longLongValue];
        snapshot.sourceFile = sourceFile;
        snapshot.sourceModifiedAt = modifiedAt;
        NSString *timestamp = [event[@"timestamp"] isKindOfClass:NSString.class] ? event[@"timestamp"] : nil;
        if (timestamp) {
            NSISO8601DateFormatter *formatter = [NSISO8601DateFormatter new];
            formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
            snapshot.tokenEventAt = [formatter dateFromString:timestamp] ?: modifiedAt;
        } else {
            snapshot.tokenEventAt = modifiedAt;
        }

        NSDictionary *rateLimits = TBDictionary(payload[@"rate_limits"]);
        NSDictionary *primary = TBDictionary(rateLimits[@"primary"]);
        snapshot.limitID = [rateLimits[@"limit_id"] isKindOfClass:NSString.class] ? rateLimits[@"limit_id"] : @"";
        snapshot.limitName = [rateLimits[@"limit_name"] isKindOfClass:NSString.class] ? rateLimits[@"limit_name"] : nil;
        NSNumber *used = TBNumber(primary[@"used_percent"]);
        snapshot.hasRateLimit = used != nil;
        snapshot.usedPercent = used.doubleValue;
        snapshot.windowMinutes = [TBNumber(primary[@"window_minutes"]) integerValue];
        NSNumber *reset = TBNumber(primary[@"resets_at"]);
        if (reset) snapshot.resetDate = [NSDate dateWithTimeIntervalSince1970:reset.doubleValue];
        return snapshot;
    }

    if (error) *error = TBLogError(TBTokenLogErrorNoTokenEvent, @"最新任务还没有产生 token 数据");
    return nil;
}

TBDashboardSnapshot *TBSelectNewestRateLimitSnapshot(NSArray<TBDashboardSnapshot *> *snapshots) {
    TBDashboardSnapshot *newestCanonical = nil;
    TBDashboardSnapshot *newestWithRate = nil;
    TBDashboardSnapshot *newestFallback = nil;
    for (TBDashboardSnapshot *snapshot in snapshots) {
        if (!newestFallback || [snapshot.tokenEventAt compare:newestFallback.tokenEventAt] == NSOrderedDescending) {
            newestFallback = snapshot;
        }
        if (snapshot.hasRateLimit &&
            (!newestWithRate || [snapshot.tokenEventAt compare:newestWithRate.tokenEventAt] == NSOrderedDescending)) {
            newestWithRate = snapshot;
        }
        if (snapshot.hasRateLimit && [snapshot.limitID isEqualToString:@"codex"] &&
            (!newestCanonical || [snapshot.tokenEventAt compare:newestCanonical.tokenEventAt] == NSOrderedDescending)) {
            newestCanonical = snapshot;
        }
    }
    // Model-specific pools (for example Codex Spark) must not silently replace
    // the account's canonical Codex quota in the menu bar.
    return newestCanonical ?: newestWithRate ?: newestFallback;
}

@interface TBTokenLogReader ()
@property(nonatomic, nullable) TBDashboardSnapshot *cachedCanonicalSnapshot;
@end

@implementation TBTokenLogReader

- (TBDashboardSnapshot *)readLatestSnapshotWithError:(NSError **)error {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSURL *codexRoot = [fm.homeDirectoryForCurrentUser URLByAppendingPathComponent:@".codex" isDirectory:YES];
    NSArray<NSURL *> *roots = @[
        [codexRoot URLByAppendingPathComponent:@"sessions" isDirectory:YES],
        [codexRoot URLByAppendingPathComponent:@"archived_sessions" isDirectory:YES]
    ];
    BOOL hasReadableRoot = NO;
    for (NSURL *root in roots) {
        BOOL isDirectory = NO;
        if ([fm fileExistsAtPath:root.path isDirectory:&isDirectory] && isDirectory) {
            hasReadableRoot = YES;
            break;
        }
    }
    if (!hasReadableRoot) {
        if (error) *error = TBLogError(TBTokenLogErrorNoSessionDirectory, @"找不到 Codex 本地任务目录");
        return nil;
    }

    NSArray<NSURLResourceKey> *keys = @[NSURLIsRegularFileKey, NSURLContentModificationDateKey];
    NSMutableArray<NSDictionary *> *candidates = [NSMutableArray array];
    for (NSURL *root in roots) {
        NSDirectoryEnumerator<NSURL *> *enumerator = [fm enumeratorAtURL:root
                                              includingPropertiesForKeys:keys
                                                                 options:NSDirectoryEnumerationSkipsHiddenFiles
                                                            errorHandler:nil];
        for (NSURL *url in enumerator) {
            if (![url.pathExtension isEqual:@"jsonl"]) continue;
            NSDictionary *values = [url resourceValuesForKeys:keys error:nil];
            if (![values[NSURLIsRegularFileKey] boolValue]) continue;
            NSDate *modified = values[NSURLContentModificationDateKey];
            if (modified) [candidates addObject:@{ @"url": url, @"modified": modified }];
        }
    }

    if (candidates.count == 0) {
        if (error) *error = TBLogError(TBTokenLogErrorNoSessionLog, @"还没有可读取的 Codex 任务");
        return nil;
    }

    [candidates sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
        return [right[@"modified"] compare:left[@"modified"]];
    }];

    // A file can be touched by a non-token event after its last quota update.
    // Inspect several recently active/archived tasks, then compare the event's
    // own timestamp so the account-wide quota cannot regress to stale data.
    NSUInteger normalInspectionCount = MIN((NSUInteger)32, candidates.count);
    NSUInteger deepInspectionLimit = MIN((NSUInteger)256, candidates.count);
    NSMutableArray<TBDashboardSnapshot *> *snapshots = [NSMutableArray array];
    NSError *lastReadError = nil;
    for (NSUInteger index = 0; index < deepInspectionLimit; index++) {
        if (index >= normalInspectionCount && self.cachedCanonicalSnapshot) break;
        NSDictionary *candidate = candidates[index];
        NSURL *url = candidate[@"url"];
        NSDate *modifiedAt = candidate[@"modified"];
        NSFileHandle *handle = [NSFileHandle fileHandleForReadingFromURL:url error:&lastReadError];
        if (!handle) continue;
        unsigned long long size = [handle seekToEndOfFile];
        const unsigned long long tailSize = 8ULL * 1024ULL * 1024ULL;
        unsigned long long offset = size > tailSize ? size - tailSize : 0;
        [handle seekToFileOffset:offset];
        NSData *data = [handle readDataToEndOfFile];
        [handle closeFile];

        if (offset > 0) {
            const unsigned char newline = '\n';
            NSRange range = [data rangeOfData:[NSData dataWithBytes:&newline length:1]
                                      options:0
                                        range:NSMakeRange(0, data.length)];
            if (range.location != NSNotFound) {
                data = [data subdataWithRange:NSMakeRange(NSMaxRange(range), data.length - NSMaxRange(range))];
            }
        }

        NSError *parseError = nil;
        TBDashboardSnapshot *snapshot = TBParseLatestTokenEvent(data, url.lastPathComponent, modifiedAt, &parseError);
        if (snapshot) {
            [snapshots addObject:snapshot];
            if ([snapshot.limitID isEqualToString:@"codex"] &&
                (!self.cachedCanonicalSnapshot ||
                 [snapshot.tokenEventAt compare:self.cachedCanonicalSnapshot.tokenEventAt] == NSOrderedDescending)) {
                self.cachedCanonicalSnapshot = snapshot;
            }
        }
        else if (parseError) lastReadError = parseError;
    }

    if (self.cachedCanonicalSnapshot && ![snapshots containsObject:self.cachedCanonicalSnapshot]) {
        [snapshots addObject:self.cachedCanonicalSnapshot];
    }

    TBDashboardSnapshot *selected = TBSelectNewestRateLimitSnapshot(snapshots);
    if (!selected && error) {
        *error = lastReadError ?: TBLogError(TBTokenLogErrorNoTokenEvent, @"最近的任务还没有产生 token 数据");
    }
    return selected;
}

@end
