#import <Foundation/Foundation.h>
#import "TokenLogParser.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT TBDashboardSnapshot * _Nullable TBParseAccountRateLimitsResponse(
    NSData *data,
    NSDate *fetchedAt,
    NSError **error
);

@interface TBAccountRateLimitReader : NSObject
- (TBDashboardSnapshot * _Nullable)readCurrentRateLimitsWithError:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
