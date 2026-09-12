#import <Foundation/Foundation.h>
#import "AccountRateLimitReader.h"
#import "TokenLogParser.h"
#import <math.h>

static void Assert(BOOL condition, NSString *message) {
    if (!condition) {
        NSLog(@"FAIL: %@", message);
        exit(1);
    }
}

int main(void) {
    @autoreleasepool {
        NSString *jsonl = @"{\"type\":\"event_msg\",\"payload\":{\"type\":\"agent_message\"}}\n"
        "{\"timestamp\":\"2026-07-20T04:54:03.964Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"total_token_usage\":{\"input_tokens\":100000,\"cached_input_tokens\":70000,\"output_tokens\":2500,\"total_tokens\":102500},\"last_token_usage\":{\"input_tokens\":20000,\"cached_input_tokens\":15000,\"output_tokens\":500,\"total_tokens\":20500},\"model_context_window\":200000},\"rate_limits\":{\"primary\":{\"used_percent\":30.0,\"window_minutes\":10080,\"resets_at\":1890000000}}}}";
        NSError *error = nil;
        TBDashboardSnapshot *snapshot = TBParseLatestTokenEvent([jsonl dataUsingEncoding:NSUTF8StringEncoding], @"fixture.jsonl", NSDate.date, &error);
        Assert(snapshot != nil, error.localizedDescription ?: @"snapshot should parse");
        Assert(fabs(snapshot.remainingPercent - 70.0) < 0.001, @"remaining percent");
        Assert(snapshot.taskTotalTokens == 102500, @"task token total");
        Assert(snapshot.lastTotalTokens == 20500, @"last token total");
        Assert(snapshot.lastCachedTokens == 15000, @"cached token total");
        Assert(fabs(snapshot.contextUsedPercent - 10.0) < 0.001, @"context percent");
        Assert([snapshot.tokenEventAt compare:snapshot.sourceModifiedAt] != NSOrderedSame, @"event timestamp should come from the log line");

        TBDashboardSnapshot *staleTouchedFile = [TBDashboardSnapshot new];
        staleTouchedFile.hasRateLimit = YES;
        staleTouchedFile.limitID = @"codex";
        staleTouchedFile.usedPercent = 80;
        staleTouchedFile.tokenEventAt = [NSDate dateWithTimeIntervalSince1970:100];
        staleTouchedFile.sourceModifiedAt = [NSDate dateWithTimeIntervalSince1970:300];
        TBDashboardSnapshot *newestQuota = [TBDashboardSnapshot new];
        newestQuota.hasRateLimit = YES;
        newestQuota.limitID = @"codex";
        newestQuota.usedPercent = 98;
        newestQuota.tokenEventAt = [NSDate dateWithTimeIntervalSince1970:200];
        newestQuota.sourceModifiedAt = [NSDate dateWithTimeIntervalSince1970:200];
        TBDashboardSnapshot *selected = TBSelectNewestRateLimitSnapshot(@[staleTouchedFile, newestQuota]);
        Assert(selected == newestQuota, @"newest token event must win even when stale file was touched later");
        Assert(fabs(selected.remainingPercent - 2.0) < 0.001, @"98 percent used means 2 percent remaining");

        TBDashboardSnapshot *sparkPool = [TBDashboardSnapshot new];
        sparkPool.hasRateLimit = YES;
        sparkPool.limitID = @"codex_bengalfox";
        sparkPool.limitName = @"GPT-5.3-Codex-Spark";
        sparkPool.usedPercent = 0;
        sparkPool.tokenEventAt = [NSDate dateWithTimeIntervalSince1970:400];
        selected = TBSelectNewestRateLimitSnapshot(@[newestQuota, sparkPool]);
        Assert(selected == newestQuota, @"newer model-specific pool must not replace canonical Codex quota");

        NSString *accountJSON = @"{\"id\":2,\"result\":{\"rateLimits\":{\"limitId\":\"codex_bengalfox\",\"primary\":{\"usedPercent\":0,\"windowDurationMins\":10080,\"resetsAt\":1890000100}},\"rateLimitsByLimitId\":{\"codex\":{\"limitId\":\"codex\",\"primary\":{\"usedPercent\":5,\"windowDurationMins\":10080,\"resetsAt\":1890000000}},\"codex_bengalfox\":{\"limitId\":\"codex_bengalfox\",\"primary\":{\"usedPercent\":0,\"windowDurationMins\":10080,\"resetsAt\":1890000100}}}}}";
        error = nil;
        TBDashboardSnapshot *accountSnapshot = TBParseAccountRateLimitsResponse(
            [accountJSON dataUsingEncoding:NSUTF8StringEncoding],
            NSDate.date,
            &error
        );
        Assert(accountSnapshot != nil, error.localizedDescription ?: @"account rate-limit response should parse");
        Assert([accountSnapshot.limitID isEqualToString:@"codex"], @"account response should select canonical Codex pool");
        Assert(fabs(accountSnapshot.remainingPercent - 95.0) < 0.001, @"account response should expose 95 percent remaining");

        NSData *missing = [@"{\"type\":\"event_msg\",\"payload\":{\"type\":\"agent_message\"}}" dataUsingEncoding:NSUTF8StringEncoding];
        error = nil;
        Assert(TBParseLatestTokenEvent(missing, @"fixture.jsonl", NSDate.date, &error) == nil, @"missing token event should fail");
        Assert(error != nil, @"missing token event should explain failure");
        NSLog(@"PASS: parser tests");
    }
    return 0;
}
