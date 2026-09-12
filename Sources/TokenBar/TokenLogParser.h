#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface TBDashboardSnapshot : NSObject
@property(nonatomic) double usedPercent;
@property(nonatomic) BOOL hasRateLimit;
@property(nonatomic, copy) NSString *limitID;
@property(nonatomic, copy, nullable) NSString *limitName;
@property(nonatomic, nullable) NSDate *resetDate;
@property(nonatomic) NSInteger windowMinutes;
@property(nonatomic) long long taskTotalTokens;
@property(nonatomic) long long taskCachedTokens;
@property(nonatomic) long long lastTotalTokens;
@property(nonatomic) long long lastInputTokens;
@property(nonatomic) long long lastCachedTokens;
@property(nonatomic) long long lastOutputTokens;
@property(nonatomic) long long contextWindow;
@property(nonatomic, copy) NSString *sourceFile;
@property(nonatomic, strong) NSDate *sourceModifiedAt;
@property(nonatomic, strong) NSDate *tokenEventAt;
- (double)remainingPercent;
- (double)contextUsedPercent;
@end

FOUNDATION_EXPORT TBDashboardSnapshot * _Nullable TBParseLatestTokenEvent(
    NSData *data,
    NSString *sourceFile,
    NSDate *modifiedAt,
    NSError **error
);

FOUNDATION_EXPORT TBDashboardSnapshot * _Nullable TBSelectNewestRateLimitSnapshot(
    NSArray<TBDashboardSnapshot *> *snapshots
);

@interface TBTokenLogReader : NSObject
- (TBDashboardSnapshot * _Nullable)readLatestSnapshotWithError:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
