#import <Cocoa/Cocoa.h>
#import <CoreGraphics/CoreGraphics.h>
#import <QuartzCore/QuartzCore.h>
#import "AccountRateLimitReader.h"
#import "TokenLogParser.h"
#import <math.h>

static NSColor *TBOrbitColor(void) {
    return [NSColor colorWithSRGBRed:0.20 green:0.78 blue:0.61 alpha:1.0];
}

static NSColor *TBWarningColor(void) {
    return [NSColor colorWithSRGBRed:0.96 green:0.62 blue:0.19 alpha:1.0];
}

static NSColor *TBCriticalColor(void) {
    return [NSColor colorWithSRGBRed:1.00 green:0.36 blue:0.36 alpha:1.0];
}

static NSColor *TBStatusColor(double remaining) {
    if (remaining <= 10) return TBCriticalColor();
    if (remaining <= 30) return TBWarningColor();
    return TBOrbitColor();
}

static NSString *TBFormatTokens(long long value) {
    if (value >= 1000000) return [NSString stringWithFormat:@"%.1fM", (double)value / 1000000.0];
    if (value >= 1000) return [NSString stringWithFormat:@"%.1fk", (double)value / 1000.0];
    return [NSString stringWithFormat:@"%lld", value];
}

@interface TBPetBadgeView : NSView
@property(nonatomic) double remainingPercent;
@property(nonatomic) BOOL hasValue;
@property(nonatomic, copy) dispatch_block_t dragEndedHandler;
- (void)updateRemainingPercent:(double)remaining hasValue:(BOOL)hasValue;
@end

@implementation TBPetBadgeView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _remainingPercent = 0;
        _hasValue = NO;
        self.wantsLayer = YES;
    }
    return self;
}

- (BOOL)mouseDownCanMoveWindow { return YES; }

- (void)mouseDown:(NSEvent *)event {
    [self.window performWindowDragWithEvent:event];
    if (self.dragEndedHandler) self.dragEndedHandler();
}

- (void)updateRemainingPercent:(double)remaining hasValue:(BOOL)hasValue {
    BOOL changed = self.hasValue != hasValue || fabs(self.remainingPercent - remaining) >= 0.5;
    self.remainingPercent = remaining;
    self.hasValue = hasValue;
    [self setNeedsDisplay:YES];

    if (changed && self.layer) {
        CABasicAnimation *pulse = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
        pulse.fromValue = @0.96;
        pulse.toValue = @1.0;
        pulse.duration = 0.18;
        pulse.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
        [self.layer addAnimation:pulse forKey:@"token-pulse"];
    }
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    NSRect bubble = NSMakeRect(5, 10, 106, 46);
    NSBezierPath *shape = [NSBezierPath bezierPathWithRoundedRect:bubble xRadius:17 yRadius:17];

    NSShadow *shadow = [NSShadow new];
    shadow.shadowColor = [NSColor colorWithWhite:0 alpha:0.24];
    shadow.shadowBlurRadius = 10;
    shadow.shadowOffset = NSMakeSize(0, -2);
    [NSGraphicsContext saveGraphicsState];
    [shadow set];
    [[NSColor colorWithWhite:0.10 alpha:0.94] setFill];
    [shape fill];
    [NSGraphicsContext restoreGraphicsState];

    NSBezierPath *tail = [NSBezierPath bezierPath];
    [tail moveToPoint:NSMakePoint(49, 11)];
    [tail lineToPoint:NSMakePoint(58, 3)];
    [tail lineToPoint:NSMakePoint(64, 11)];
    [tail closePath];
    [[NSColor colorWithWhite:0.10 alpha:0.94] setFill];
    [tail fill];

    double remaining = self.remainingPercent;
    NSColor *status = self.hasValue ? TBStatusColor(remaining) : NSColor.tertiaryLabelColor;
    [status setStroke];
    NSBezierPath *track = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(15, 20, 25, 25)];
    track.lineWidth = 3;
    [[NSColor colorWithWhite:1 alpha:0.18] setStroke];
    [track stroke];
    if (self.hasValue) {
        [status setStroke];
        NSBezierPath *ring = [NSBezierPath bezierPath];
        ring.lineWidth = 3;
        ring.lineCapStyle = NSLineCapStyleRound;
        double fraction = fmin(1, fmax(0.012, remaining / 100.0));
        [ring appendBezierPathWithArcWithCenter:NSMakePoint(27.5, 32.5)
                                         radius:12.5
                                     startAngle:90
                                       endAngle:90 - 360 * fraction
                                      clockwise:YES];
        [ring stroke];
    }

    NSString *value = self.hasValue ? [NSString stringWithFormat:@"%.0f%%", remaining] : @"--";
    NSMutableParagraphStyle *left = [NSMutableParagraphStyle new];
    left.alignment = NSTextAlignmentLeft;
    [value drawInRect:NSMakeRect(48, 26, 56, 25)
       withAttributes:@{
           NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:20 weight:NSFontWeightBold],
           NSForegroundColorAttributeName: NSColor.whiteColor,
           NSParagraphStyleAttributeName: left
       }];
    [@"TOKEN 剩余" drawInRect:NSMakeRect(49, 15, 54, 12)
               withAttributes:@{
                   NSFontAttributeName: [NSFont systemFontOfSize:8 weight:NSFontWeightSemibold],
                   NSForegroundColorAttributeName: [NSColor colorWithWhite:1 alpha:0.55],
                   NSKernAttributeName: @0.4,
                   NSParagraphStyleAttributeName: left
               }];
}

@end

@interface TBDashboardView : NSView
@property(nonatomic, nullable) TBDashboardSnapshot *snapshot;
@property(nonatomic, copy, nullable) NSString *errorMessage;
@property(nonatomic, nullable) NSDate *refreshedAt;
@property(nonatomic, copy) dispatch_block_t refreshHandler;
@property(nonatomic, copy) dispatch_block_t toggleBadgeHandler;
@property(nonatomic) BOOL badgeVisible;
- (void)renderSnapshot:(TBDashboardSnapshot * _Nullable)snapshot
                 error:(NSString * _Nullable)error
             refreshed:(NSDate *)refreshed;
@end

@implementation TBDashboardView {
    NSButton *_badgeButton;
    NSButton *_refreshButton;
    NSButton *_quitButton;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;

        _badgeButton = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"pawprint.fill" accessibilityDescription:@"显示或隐藏宠物余额"]
                                           target:self
                                           action:@selector(badgePressed:)];
        _badgeButton.bordered = NO;
        _badgeButton.toolTip = @"显示或隐藏宠物旁的余额浮标";
        _badgeButton.frame = NSMakeRect(218, 9, 28, 26);
        [self addSubview:_badgeButton];

        _refreshButton = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"arrow.clockwise" accessibilityDescription:@"立即刷新"]
                                             target:self
                                             action:@selector(refreshPressed:)];
        _refreshButton.bordered = NO;
        _refreshButton.toolTip = @"立即刷新";
        _refreshButton.frame = NSMakeRect(252, 9, 28, 26);
        [self addSubview:_refreshButton];

        _quitButton = [NSButton buttonWithTitle:@"退出" target:self action:@selector(quitPressed:)];
        _quitButton.bordered = NO;
        _quitButton.font = [NSFont systemFontOfSize:11];
        _quitButton.contentTintColor = NSColor.secondaryLabelColor;
        _quitButton.frame = NSMakeRect(280, 9, 42, 26);
        [self addSubview:_quitButton];
    }
    return self;
}

- (void)setBadgeVisible:(BOOL)badgeVisible {
    _badgeVisible = badgeVisible;
    _badgeButton.contentTintColor = badgeVisible ? TBOrbitColor() : NSColor.tertiaryLabelColor;
    _badgeButton.toolTip = badgeVisible ? @"隐藏宠物旁的余额浮标" : @"显示宠物旁的余额浮标";
}

- (BOOL)isFlipped { return NO; }

- (void)renderSnapshot:(TBDashboardSnapshot *)snapshot error:(NSString *)error refreshed:(NSDate *)refreshed {
    self.snapshot = snapshot;
    self.errorMessage = error;
    self.refreshedAt = refreshed;
    [self setNeedsDisplay:YES];
}

- (void)refreshPressed:(id)sender {
    if (self.refreshHandler) self.refreshHandler();
}

- (void)badgePressed:(id)sender {
    if (self.toggleBadgeHandler) self.toggleBadgeHandler();
}

- (void)quitPressed:(id)sender {
    [NSApp terminate:nil];
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    [NSColor.windowBackgroundColor setFill];
    NSRectFill(self.bounds);

    if (!self.snapshot) {
        [self drawEmptyState];
        [self drawFooter];
        return;
    }

    TBDashboardSnapshot *s = self.snapshot;
    double remaining = s.remainingPercent;
    NSColor *status = isnan(remaining) ? NSColor.secondaryLabelColor : TBStatusColor(remaining);

    [self drawGaugeAt:NSMakePoint(58, 310) radius:34 progress:(isnan(remaining) ? 0 : remaining / 100.0) color:status];
    NSString *gaugeValue = isnan(remaining) ? @"—" : [NSString stringWithFormat:@"%.0f", remaining];
    [self drawText:gaugeValue
            inRect:NSMakeRect(29, 292, 58, 34)
              font:[NSFont monospacedDigitSystemFontOfSize:27 weight:NSFontWeightBold]
             color:NSColor.labelColor
         alignment:NSTextAlignmentCenter];

    [self drawText:@"本周期还剩"
            inRect:NSMakeRect(108, 332, 190, 18)
              font:[NSFont systemFontOfSize:13 weight:NSFontWeightMedium]
             color:NSColor.secondaryLabelColor
         alignment:NSTextAlignmentLeft];
    NSString *headline = isnan(remaining) ? @"额度未知" : [NSString stringWithFormat:@"%.0f%%", remaining];
    [self drawText:headline
            inRect:NSMakeRect(107, 294, 195, 40)
              font:[NSFont systemFontOfSize:34 weight:NSFontWeightBold]
             color:NSColor.labelColor
         alignment:NSTextAlignmentLeft];
    [self drawText:[self resetText:s.resetDate]
            inRect:NSMakeRect(108, 273, 195, 17)
              font:[NSFont systemFontOfSize:12 weight:NSFontWeightMedium]
             color:NSColor.secondaryLabelColor
         alignment:NSTextAlignmentLeft];

    [self drawProgressInRect:NSMakeRect(18, 251, 292, 7)
                    progress:(isnan(remaining) ? 0 : remaining / 100.0)
                       color:status];
    [self drawMetrics:s];
    [self drawFooter];
}

- (void)drawEmptyState {
    NSImage *image = [NSImage imageWithSystemSymbolName:@"circle.dotted" accessibilityDescription:nil];
    image.size = NSMakeSize(34, 34);
    [image drawInRect:NSMakeRect(147, 252, 34, 34)];
    [self drawText:@"等待 token 数据"
            inRect:NSMakeRect(32, 214, 264, 24)
              font:[NSFont systemFontOfSize:15 weight:NSFontWeightSemibold]
             color:NSColor.labelColor
         alignment:NSTextAlignmentCenter];
    [self drawText:(self.errorMessage ?: @"运行一次 Codex 任务后，这里会自动更新。")
            inRect:NSMakeRect(34, 168, 260, 40)
              font:[NSFont systemFontOfSize:12]
             color:NSColor.secondaryLabelColor
         alignment:NSTextAlignmentCenter];
}

- (void)drawMetrics:(TBDashboardSnapshot *)s {
    NSRect card = NSMakeRect(18, 91, 292, 144);
    [[NSColor.labelColor colorWithAlphaComponent:0.045] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:card xRadius:13 yRadius:13] fill];

    NSArray<NSString *> *symbols = @[@"circle.hexagongrid.fill", @"arrow.right.circle.fill", @"bolt.horizontal.circle.fill", @"text.line.first.and.arrowtriangle.forward"];
    NSArray<NSString *> *titles = @[@"本任务处理量", @"最近一次调用", @"缓存复用", @"上下文占用"];
    NSString *context = isnan(s.contextUsedPercent) ? @"—" : [NSString stringWithFormat:@"%.0f%%", s.contextUsedPercent];
    NSArray<NSString *> *values = @[TBFormatTokens(s.taskTotalTokens), [@"+" stringByAppendingString:TBFormatTokens(s.lastTotalTokens)], TBFormatTokens(s.lastCachedTokens), context];
    NSArray<NSColor *> *colors = @[TBOrbitColor(), NSColor.labelColor, [NSColor colorWithSRGBRed:0.42 green:0.53 blue:0.66 alpha:1], TBWarningColor()];

    for (NSInteger index = 0; index < 4; index++) {
        CGFloat y = 202 - index * 36;
        NSImage *symbol = [NSImage imageWithSystemSymbolName:symbols[index] accessibilityDescription:nil];
        NSImageSymbolConfiguration *configuration = [NSImageSymbolConfiguration configurationWithPointSize:15 weight:NSFontWeightMedium];
        symbol = [symbol imageWithSymbolConfiguration:configuration];
        [colors[index] set];
        [symbol drawInRect:NSMakeRect(29, y - 2, 18, 18) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:YES hints:nil];
        [self drawText:titles[index]
                inRect:NSMakeRect(55, y - 1, 150, 18)
                  font:[NSFont systemFontOfSize:13]
                 color:NSColor.labelColor
             alignment:NSTextAlignmentLeft];
        [self drawText:values[index]
                inRect:NSMakeRect(202, y - 1, 94, 18)
                  font:[NSFont monospacedDigitSystemFontOfSize:13 weight:NSFontWeightSemibold]
                 color:NSColor.labelColor
             alignment:NSTextAlignmentRight];
        if (index < 3) {
            [NSColor.separatorColor setStroke];
            NSBezierPath *line = [NSBezierPath bezierPath];
            [line moveToPoint:NSMakePoint(55, y - 12)];
            [line lineToPoint:NSMakePoint(298, y - 12)];
            line.lineWidth = 0.5;
            [line stroke];
        }
    }

    [self drawText:@"ⓘ  处理量包含缓存上下文，不等于额度扣减"
            inRect:NSMakeRect(20, 59, 288, 17)
              font:[NSFont systemFontOfSize:11]
             color:NSColor.tertiaryLabelColor
         alignment:NSTextAlignmentLeft];
}

- (void)drawFooter {
    [NSColor.separatorColor setStroke];
    NSBezierPath *divider = [NSBezierPath bezierPath];
    [divider moveToPoint:NSMakePoint(16, 42)];
    [divider lineToPoint:NSMakePoint(312, 42)];
    divider.lineWidth = 0.5;
    [divider stroke];

    NSColor *dotColor = self.errorMessage ? TBCriticalColor() : TBOrbitColor();
    [dotColor setFill];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(18, 19, 6, 6)] fill];
    [self drawText:[self updateText]
            inRect:NSMakeRect(30, 13, 190, 18)
              font:[NSFont systemFontOfSize:11]
             color:NSColor.secondaryLabelColor
         alignment:NSTextAlignmentLeft];
}

- (void)drawGaugeAt:(NSPoint)center radius:(CGFloat)radius progress:(double)progress color:(NSColor *)color {
    [[NSColor.labelColor colorWithAlphaComponent:0.09] setStroke];
    NSBezierPath *track = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(center.x-radius, center.y-radius, radius*2, radius*2)];
    track.lineWidth = 7;
    [track stroke];

    [color setStroke];
    NSBezierPath *ring = [NSBezierPath bezierPath];
    ring.lineWidth = 7;
    ring.lineCapStyle = NSLineCapStyleRound;
    double fraction = fmin(1, fmax(0.012, progress));
    [ring appendBezierPathWithArcWithCenter:center radius:radius startAngle:90 endAngle:90 - 360 * fraction clockwise:YES];
    [ring stroke];
}

- (void)drawProgressInRect:(NSRect)rect progress:(double)progress color:(NSColor *)color {
    [[NSColor.labelColor colorWithAlphaComponent:0.08] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:rect xRadius:3.5 yRadius:3.5] fill];
    CGFloat width = fmax(6, NSWidth(rect) * fmin(1, fmax(0, progress)));
    [color setFill];
    [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(NSMinX(rect), NSMinY(rect), width, NSHeight(rect)) xRadius:3.5 yRadius:3.5] fill];
}

- (void)drawText:(NSString *)text inRect:(NSRect)rect font:(NSFont *)font color:(NSColor *)color alignment:(NSTextAlignment)alignment {
    NSMutableParagraphStyle *style = [NSMutableParagraphStyle new];
    style.alignment = alignment;
    style.lineBreakMode = NSLineBreakByTruncatingTail;
    [text drawInRect:rect withAttributes:@{NSFontAttributeName: font, NSForegroundColorAttributeName: color, NSParagraphStyleAttributeName: style}];
}

- (NSString *)resetText:(NSDate *)date {
    if (!date) return @"重置时间未知";
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
    formatter.dateFormat = @"M 月 d 日 HH:mm 重置";
    return [formatter stringFromDate:date];
}

- (NSString *)updateText {
    if (self.errorMessage) return self.errorMessage;
    NSDate *dataDate = self.snapshot.tokenEventAt ?: self.refreshedAt;
    if (!dataDate) return @"尚未更新";
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.dateFormat = @"HH:mm:ss";
    return [NSString stringWithFormat:@"额度更新 · %@", [formatter stringFromDate:dataDate]];
}

@end

@interface TBAppDelegate : NSObject <NSApplicationDelegate>
@end

@implementation TBAppDelegate {
    NSStatusItem *_statusItem;
    NSPopover *_popover;
    TBDashboardView *_dashboard;
    NSPanel *_petBadgePanel;
    TBPetBadgeView *_petBadgeView;
    TBTokenLogReader *_reader;
    TBAccountRateLimitReader *_accountReader;
    TBDashboardSnapshot *_logSnapshot;
    TBDashboardSnapshot *_accountSnapshot;
    NSString *_lastLogError;
    BOOL _accountRefreshInFlight;
    NSTimer *_timer;
    NSTimer *_accountTimer;
    NSTimer *_petFollowTimer;
    id _globalMouseMonitor;
    NSPoint _petDragStartPoint;
    NSPoint _badgeDragStartOrigin;
    NSPoint _pendingPetDragPoint;
    BOOL _petDragUpdateQueued;
    BOOL _petDragCandidate;
    BOOL _trackingPetDrag;
    NSRect _lastPetFrame;
    NSPoint _badgeOffset;
    BOOL _hasBadgeOffset;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    _reader = [TBTokenLogReader new];
    _accountReader = [TBAccountRateLimitReader new];
    _dashboard = [[TBDashboardView alloc] initWithFrame:NSMakeRect(0, 0, 328, 368)];
    __weak typeof(self) weakSelf = self;
    _dashboard.refreshHandler = ^{ [weakSelf refresh]; };
    _dashboard.toggleBadgeHandler = ^{ [weakSelf togglePetBadge]; };

    NSViewController *controller = [NSViewController new];
    controller.view = _dashboard;
    controller.preferredContentSize = NSMakeSize(328, 368);
    _popover = [NSPopover new];
    _popover.contentViewController = controller;
    _popover.behavior = NSPopoverBehaviorTransient;

    _statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    _statusItem.button.target = self;
    _statusItem.button.action = @selector(togglePopover:);
    _statusItem.button.toolTip = @"Token Bar";

    [self configurePetBadge];

    [self refresh];
    [self refreshAccountRateLimits];
    _timer = [NSTimer scheduledTimerWithTimeInterval:3 target:self selector:@selector(timerFired:) userInfo:nil repeats:YES];
    _accountTimer = [NSTimer scheduledTimerWithTimeInterval:15 target:self selector:@selector(accountTimerFired:) userInfo:nil repeats:YES];
    _petFollowTimer = [NSTimer scheduledTimerWithTimeInterval:0.1 target:self selector:@selector(petFollowTimerFired:) userInfo:nil repeats:YES];
    [self followPetIfNeeded];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    [_timer invalidate];
    [_accountTimer invalidate];
    [_petFollowTimer invalidate];
    if (_globalMouseMonitor) {
        [NSEvent removeMonitor:_globalMouseMonitor];
        _globalMouseMonitor = nil;
    }
}

- (void)timerFired:(NSTimer *)timer { [self refresh]; }
- (void)accountTimerFired:(NSTimer *)timer { [self refreshAccountRateLimits]; }
- (void)petFollowTimerFired:(NSTimer *)timer { [self followPetIfNeeded]; }

- (void)installPetDragMonitor {
    __weak typeof(self) weakSelf = self;
    NSEventMask mask = NSEventMaskLeftMouseDown | NSEventMaskLeftMouseDragged | NSEventMaskLeftMouseUp;
    _globalMouseMonitor = [NSEvent addGlobalMonitorForEventsMatchingMask:mask handler:^(NSEvent *event) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;

        // Drag events can arrive much faster than AppKit can repaint a window.
        // Keep only the newest point and schedule one main-thread update.
        if (event.type == NSEventTypeLeftMouseDragged) {
            NSPoint point = NSEvent.mouseLocation;
            @synchronized (strongSelf) {
                strongSelf->_pendingPetDragPoint = point;
                if (strongSelf->_petDragUpdateQueued) return;
                strongSelf->_petDragUpdateQueued = YES;
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                NSPoint latest;
                @synchronized (strongSelf) {
                    latest = strongSelf->_pendingPetDragPoint;
                    strongSelf->_petDragUpdateQueued = NO;
                }
                [strongSelf handlePetDragPoint:latest];
            });
            return;
        }

        void (^handle)(void) = ^{ [strongSelf handleGlobalMouseEvent:event]; };
        if ([NSThread isMainThread]) handle();
        else dispatch_async(dispatch_get_main_queue(), handle);
    }];
}

- (BOOL)frontmostAppLooksLikeCodex {
    NSRunningApplication *app = NSWorkspace.sharedWorkspace.frontmostApplication;
    NSString *bundleID = app.bundleIdentifier.lowercaseString ?: @"";
    NSString *name = app.localizedName.lowercaseString ?: @"";
    return [bundleID containsString:@"openai"] ||
           [bundleID containsString:@"codex"] ||
           [name containsString:@"chatgpt"] ||
           [name containsString:@"codex"];
}

- (BOOL)eventBelongsToCodex:(NSEvent *)event {
    CGWindowID windowID = (CGWindowID)event.windowNumber;
    if (windowID == kCGNullWindowID && event.CGEvent) {
        windowID = (CGWindowID)CGEventGetIntegerValueField(event.CGEvent,
                                                            kCGMouseEventWindowUnderMousePointer);
    }
    if (windowID == kCGNullWindowID) return [self frontmostAppLooksLikeCodex];

    CFArrayRef infoRef = CGWindowListCopyWindowInfo(kCGWindowListOptionIncludingWindow,
                                                    windowID);
    NSArray *windowInfo = CFBridgingRelease(infoRef);
    NSDictionary *info = windowInfo.firstObject;
    NSString *owner = info[(id)kCGWindowOwnerName];
    NSInteger layer = [info[(id)kCGWindowLayer] integerValue];
    // The normal Codex content window is layer 0. The pet/effect surface is
    // above it, so require a higher layer to avoid treating regular drags as
    // pet drags.
    return ([owner isEqualToString:@"ChatGPT"] || [owner isEqualToString:@"Codex"]) && layer >= 2;
}

- (BOOL)pointLooksLikePetPixels:(NSPoint)point {
    NSScreen *screen = nil;
    for (NSScreen *candidate in NSScreen.screens) {
        if (NSPointInRect(point, candidate.frame)) {
            screen = candidate;
            break;
        }
    }
    if (!screen) return NO;

    NSNumber *screenNumber = screen.deviceDescription[(id)@"NSScreenNumber"];
    CGDirectDisplayID displayID = (CGDirectDisplayID)screenNumber.unsignedIntValue;
    CGImageRef image = CGDisplayCreateImage(displayID);
    if (!image) return NO;

    size_t width = CGImageGetWidth(image);
    size_t height = CGImageGetHeight(image);
    size_t bytesPerRow = width * 4;
    uint8_t *pixels = calloc(height, bytesPerRow);
    if (!pixels) {
        CGImageRelease(image);
        return NO;
    }

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixels, width, height, 8, bytesPerRow,
                                                  colorSpace,
                                                  (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(colorSpace);
    if (!context) {
        free(pixels);
        CGImageRelease(image);
        return NO;
    }
    CGContextSetInterpolationQuality(context, kCGInterpolationNone);
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);
    CGContextRelease(context);
    CGImageRelease(image);

    NSRect frame = screen.frame;
    CGFloat scaleX = (CGFloat)width / NSWidth(frame);
    CGFloat scaleY = (CGFloat)height / NSHeight(frame);
    CGFloat relativeX = point.x - NSMinX(frame);
    CGFloat relativeY = point.y - NSMinY(frame);
    NSInteger centerX = (NSInteger)lrint(relativeX * scaleX);
    NSInteger centerY = (NSInteger)lrint((NSHeight(frame) - relativeY) * scaleY);

    NSInteger darkCount = 0;
    NSInteger blueCount = 0;
    NSInteger total = 0;
    NSInteger radiusX = (NSInteger)lrint(82.0 * scaleX);
    NSInteger radiusY = (NSInteger)lrint(112.0 * scaleY);
    NSInteger minX = MAX(0, centerX - radiusX);
    NSInteger maxX = MIN((NSInteger)width - 1, centerX + radiusX);
    NSInteger minY = MAX(0, centerY - radiusY);
    NSInteger maxY = MIN((NSInteger)height - 1, centerY + radiusY);
    for (NSInteger y = minY; y <= maxY; y += 2) {
        for (NSInteger x = minX; x <= maxX; x += 2) {
            const uint8_t *pixel = pixels + y * bytesPerRow + x * 4;
            uint8_t r = pixel[0], g = pixel[1], b = pixel[2];
            if (r < 72 && g < 72 && b < 72) darkCount++;
            if (b > r + 16 && b > g + 4 && b > 95) blueCount++;
            total++;
        }
    }
    free(pixels);

    // LYN has both a dark silhouette and a distinctly blue shirt. Requiring
    // both keeps text/ordinary UI drags from being mistaken for the pet.
    return darkCount >= MAX(45, total / 45) && blueCount >= MAX(12, total / 180);
}

- (BOOL)pointLooksLikePetDragStart:(NSPoint)point {
    if (!_petBadgePanel.visible) return NO;

    // The bubble sits just above the mascot. Keep a generous hit region so
    // different pet sizes/animations still work, but exclude the bubble
    // itself so dragging the badge continues to be handled by its own window.
    NSRect badge = _petBadgePanel.frame;
    NSRect petRegion = NSMakeRect(NSMinX(badge) - 44,
                                  NSMinY(badge) - 160,
                                  NSWidth(badge) + 88,
                                  178);
    return NSPointInRect(point, petRegion) && !NSPointInRect(point, badge);
}

- (void)handleGlobalMouseEvent:(NSEvent *)event {
    NSEventType type = event.type;
    NSPoint point = NSEvent.mouseLocation;
    if (type == NSEventTypeLeftMouseDown) {
        BOOL nearBadgePetRegion = [self pointLooksLikePetDragStart:point];
        BOOL codexPetWindow = [self eventBelongsToCodex:event];
        BOOL petPixels = (nearBadgePetRegion || codexPetWindow) &&
                         [self pointLooksLikePetPixels:point];
        BOOL nearBadgePet = nearBadgePetRegion && petPixels;
        BOOL detachedPetCandidate = codexPetWindow && petPixels;
        _petDragCandidate = nearBadgePet || detachedPetCandidate;
        _trackingPetDrag = nearBadgePet;
        if (_petDragCandidate) {
            _petDragStartPoint = point;
            _badgeDragStartOrigin = _petBadgePanel.frame.origin;
        }
        return;
    }

    if (type == NSEventTypeLeftMouseUp) {
        _trackingPetDrag = NO;
        _petDragCandidate = NO;
    }
}

- (void)handlePetDragPoint:(NSPoint)point {
    if (!_petDragCandidate) return;

    if (!_trackingPetDrag) {
        CGFloat dx = point.x - _petDragStartPoint.x;
        CGFloat dy = point.y - _petDragStartPoint.y;
        if (hypot(dx, dy) < 4.0) return;

        // If the badge was left behind, use the first real drag point to
        // establish a fresh anchor above the pet before applying the delta.
        _trackingPetDrag = YES;
        _badgeDragStartOrigin = NSMakePoint(_petDragStartPoint.x - NSWidth(_petBadgePanel.frame) / 2.0,
                                            _petDragStartPoint.y + 105.0);
    }

    NSPoint origin = NSMakePoint(_badgeDragStartOrigin.x + point.x - _petDragStartPoint.x,
                                 _badgeDragStartOrigin.y + point.y - _petDragStartPoint.y);
    NSPoint current = _petBadgePanel.frame.origin;
    if (fabs(current.x - origin.x) > 0.5 || fabs(current.y - origin.y) > 0.5) {
        [_petBadgePanel setFrameOrigin:origin];
    }
}

- (void)refresh {
    NSError *error = nil;
    _logSnapshot = [_reader readLatestSnapshotWithError:&error];
    _lastLogError = error.localizedDescription;
    [self renderCurrentSnapshot];
}

- (void)refreshAccountRateLimits {
    if (_accountRefreshInFlight) return;
    _accountRefreshInFlight = YES;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        NSError *error = nil;
        TBDashboardSnapshot *snapshot = [strongSelf->_accountReader readCurrentRateLimitsWithError:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) self = weakSelf;
            if (!self) return;
            self->_accountRefreshInFlight = NO;
            if (snapshot) self->_accountSnapshot = snapshot;
            [self renderCurrentSnapshot];
        });
    });
}

- (TBDashboardSnapshot *)currentDisplaySnapshot {
    if (!_accountSnapshot) return _logSnapshot;
    TBDashboardSnapshot *display = [TBDashboardSnapshot new];
    display.hasRateLimit = _accountSnapshot.hasRateLimit;
    display.limitID = _accountSnapshot.limitID;
    display.limitName = _accountSnapshot.limitName;
    display.usedPercent = _accountSnapshot.usedPercent;
    display.resetDate = _accountSnapshot.resetDate;
    display.windowMinutes = _accountSnapshot.windowMinutes;
    display.tokenEventAt = _accountSnapshot.tokenEventAt;
    display.sourceFile = _accountSnapshot.sourceFile;
    display.sourceModifiedAt = _accountSnapshot.sourceModifiedAt;
    if (_logSnapshot) {
        display.taskTotalTokens = _logSnapshot.taskTotalTokens;
        display.taskCachedTokens = _logSnapshot.taskCachedTokens;
        display.lastTotalTokens = _logSnapshot.lastTotalTokens;
        display.lastInputTokens = _logSnapshot.lastInputTokens;
        display.lastCachedTokens = _logSnapshot.lastCachedTokens;
        display.lastOutputTokens = _logSnapshot.lastOutputTokens;
        display.contextWindow = _logSnapshot.contextWindow;
    }
    return display;
}

- (void)renderCurrentSnapshot {
    TBDashboardSnapshot *snapshot = [self currentDisplaySnapshot];
    NSString *error = snapshot ? nil : _lastLogError;
    [_dashboard renderSnapshot:snapshot error:error refreshed:NSDate.date];
    [self updateStatusItem:snapshot];
    BOOL hasValue = snapshot != nil && snapshot.hasRateLimit && !isnan(snapshot.remainingPercent);
    [_petBadgeView updateRemainingPercent:(hasValue ? snapshot.remainingPercent : 0) hasValue:hasValue];
}

- (void)configurePetBadge {
    NSRect frame = NSMakeRect(0, 0, 116, 64);
    _petBadgePanel = [[NSPanel alloc] initWithContentRect:frame
                                               styleMask:NSWindowStyleMaskBorderless
                                                 backing:NSBackingStoreBuffered
                                                   defer:NO];
    _petBadgePanel.opaque = NO;
    _petBadgePanel.backgroundColor = NSColor.clearColor;
    _petBadgePanel.hasShadow = NO;
    _petBadgePanel.level = NSStatusWindowLevel;
    _petBadgePanel.hidesOnDeactivate = NO;
    _petBadgePanel.movableByWindowBackground = YES;
    _petBadgePanel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
                                         NSWindowCollectionBehaviorFullScreenAuxiliary |
                                         NSWindowCollectionBehaviorStationary;
    _petBadgeView = [[TBPetBadgeView alloc] initWithFrame:frame];
    __weak typeof(self) weakSelf = self;
    _petBadgeView.dragEndedHandler = ^{ [weakSelf captureBadgeOffset]; };
    _petBadgePanel.contentView = _petBadgeView;

    NSString *frameName = @"TokenBarPetBadgeFrame";
    BOOL restoredFrame = [_petBadgePanel setFrameUsingName:frameName];
    if (!restoredFrame || ![self badgeFrameIsVisibleOnAnyScreen:_petBadgePanel.frame]) {
        NSScreen *screen = NSScreen.mainScreen;
        NSRect visible = screen.visibleFrame;
        NSPoint origin = NSMakePoint(NSMaxX(visible) - NSWidth(frame) - 28,
                                     NSMinY(visible) + 180);
        [_petBadgePanel setFrameOrigin:origin];
    }
    [_petBadgePanel setFrameAutosaveName:frameName];

    NSString *savedOffset = [NSUserDefaults.standardUserDefaults stringForKey:@"TokenBarPetBadgeRelativeOffsetV3"];
    if (savedOffset.length > 0) {
        _badgeOffset = NSPointFromString(savedOffset);
        _hasBadgeOffset = YES;
    }
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    id saved = [defaults objectForKey:@"TokenBarPetBadgeVisible"];
    BOOL visible = saved ? [saved boolValue] : YES;
    _dashboard.badgeVisible = visible;
    if (visible) [_petBadgePanel orderFrontRegardless];
}

- (BOOL)badgeFrameIsVisibleOnAnyScreen:(NSRect)frame {
    for (NSScreen *screen in NSScreen.screens) {
        if (NSIntersectsRect(frame, screen.visibleFrame)) return YES;
    }
    return NO;
}

- (void)captureBadgeOffset {
    if (NSIsEmptyRect(_lastPetFrame)) return;
    NSPoint origin = _petBadgePanel.frame.origin;
    _badgeOffset = NSMakePoint(origin.x - NSMinX(_lastPetFrame), origin.y - NSMinY(_lastPetFrame));
    _hasBadgeOffset = YES;
    [NSUserDefaults.standardUserDefaults setObject:NSStringFromPoint(_badgeOffset)
                                            forKey:@"TokenBarPetBadgeRelativeOffsetV3"];
}

- (void)followPetIfNeeded {
    if (!_petBadgePanel.visible) return;
    BOOL found = NO;
    NSRect petFrame = [self petWindowFrameFound:&found];
    if (!found) {
        // Codex can temporarily hide or rename the mascot surface during an
        // app update. Keep the badge visible instead of leaving it off-screen.
        if (![self badgeFrameIsVisibleOnAnyScreen:_petBadgePanel.frame]) {
            NSScreen *screen = NSScreen.mainScreen;
            NSRect visible = screen.visibleFrame;
            [_petBadgePanel setFrameOrigin:NSMakePoint(NSMaxX(visible) - NSWidth(_petBadgePanel.frame) - 28,
                                                       NSMinY(visible) + 180)];
        }
        return;
    }

    if (!_hasBadgeOffset) {
        // Center the bubble above the mascot's actual visible bounds.
        _badgeOffset = NSMakePoint((NSWidth(petFrame) - NSWidth(_petBadgePanel.frame)) / 2.0,
                                    NSHeight(petFrame) + 8.0);
        _hasBadgeOffset = YES;
    }
    _lastPetFrame = petFrame;

    NSPoint target = NSMakePoint(NSMinX(petFrame) + _badgeOffset.x,
                                 NSMinY(petFrame) + _badgeOffset.y);
    NSPoint current = _petBadgePanel.frame.origin;
    if (fabs(current.x - target.x) > 0.5 || fabs(current.y - target.y) > 0.5) {
        [_petBadgePanel setFrameOrigin:target];
    }
}

- (NSRect)petFrameFromWindowBounds:(CGRect)quartzBounds windowID:(CGWindowID)windowID {
    CGImageRef image = CGWindowListCreateImage(quartzBounds,
                                               kCGWindowListOptionIncludingWindow,
                                               windowID,
                                               kCGWindowImageBoundsIgnoreFraming |
                                               kCGWindowImageNominalResolution);
    if (!image) return NSZeroRect;

    size_t width = CGImageGetWidth(image);
    size_t height = CGImageGetHeight(image);
    uint8_t *mask = calloc(height, width);
    if (!mask) {
        CGImageRelease(image);
        return NSZeroRect;
    }
    CGContextRef context = CGBitmapContextCreate(mask, width, height, 8, width, NULL,
                                                  (CGBitmapInfo)kCGImageAlphaOnly);
    if (!context) {
        free(mask);
        CGImageRelease(image);
        return NSZeroRect;
    }
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);
    CGContextRelease(context);
    CGImageRelease(image);

    size_t minX = width, minY = height, maxX = 0, maxY = 0;
    BOOL hasPixels = NO;
    for (size_t y = 0; y < height; y += 2) {
        for (size_t x = 0; x < width; x += 2) {
            if (mask[y * width + x] <= 10) continue;
            hasPixels = YES;
            minX = MIN(minX, x); maxX = MAX(maxX, x);
            minY = MIN(minY, y); maxY = MAX(maxY, y);
        }
    }
    free(mask);
    if (!hasPixels || maxX <= minX || maxY <= minY) return NSZeroRect;

    CGFloat scaleX = CGRectGetWidth(quartzBounds) / (CGFloat)width;
    CGFloat scaleY = CGRectGetHeight(quartzBounds) / (CGFloat)height;
    CGFloat qx = CGRectGetMinX(quartzBounds) + minX * scaleX;
    CGFloat qy = CGRectGetMinY(quartzBounds) + minY * scaleY;
    CGFloat qw = (maxX - minX) * scaleX;
    CGFloat qh = (maxY - minY) * scaleY;
    NSScreen *primaryScreen = NSScreen.screens.firstObject;
    if (!primaryScreen) return NSZeroRect;
    return NSMakeRect(qx,
                      NSMaxY(primaryScreen.frame) - qy - qh,
                      qw,
                      qh);
}

- (NSRect)petWindowFrameFound:(BOOL *)found {
    if (found) *found = NO;
    CFArrayRef windowListRef = CGWindowListCopyWindowInfo(
        kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements,
        kCGNullWindowID
    );
    NSArray<NSDictionary *> *windows = CFBridgingRelease(windowListRef);
    for (NSDictionary *window in windows) {
        NSString *owner = window[(id)kCGWindowOwnerName];
        if (![owner isEqualToString:@"ChatGPT"] && ![owner isEqualToString:@"Codex"]) continue;
        if ([window[(id)kCGWindowLayer] integerValue] < 2) continue;

        NSDictionary *boundsDictionary = window[(id)kCGWindowBounds];
        CGRect bounds = CGRectZero;
        if (![boundsDictionary isKindOfClass:NSDictionary.class] ||
            !CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)boundsDictionary, &bounds)) {
            continue;
        }
        CGWindowID windowID = (CGWindowID)[window[(id)kCGWindowNumber] unsignedIntValue];
        NSRect petFrame = [self petFrameFromWindowBounds:bounds windowID:windowID];
        if (NSWidth(petFrame) < 20 || NSHeight(petFrame) < 60 ||
            NSWidth(petFrame) > 300 || NSHeight(petFrame) > 500) continue;
        if (found) *found = YES;
        return petFrame;
    }
    return NSZeroRect;
}

- (void)togglePetBadge {
    BOOL visible = !_petBadgePanel.visible;
    if (visible) {
        [_petBadgePanel orderFrontRegardless];
        [self followPetIfNeeded];
    } else {
        [_petBadgePanel orderOut:nil];
    }
    _dashboard.badgeVisible = visible;
    [NSUserDefaults.standardUserDefaults setBool:visible forKey:@"TokenBarPetBadgeVisible"];
}

- (void)updateStatusItem:(TBDashboardSnapshot *)snapshot {
    double remaining = snapshot ? snapshot.remainingPercent : NAN;
    _statusItem.button.image = [self ringImageWithRemaining:remaining];
    _statusItem.button.imagePosition = NSImageLeft;
    _statusItem.button.title = isnan(remaining) ? @" --" : [NSString stringWithFormat:@" %.0f%%", remaining];
}

- (NSImage *)ringImageWithRemaining:(double)remaining {
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(17, 17)];
    [image lockFocus];
    NSPoint center = NSMakePoint(8.5, 8.5);
    [[NSColor.labelColor colorWithAlphaComponent:0.22] setStroke];
    NSBezierPath *track = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(2.4, 2.4, 12.2, 12.2)];
    track.lineWidth = 2.1;
    [track stroke];
    if (!isnan(remaining)) {
        [NSColor.labelColor setStroke];
        NSBezierPath *ring = [NSBezierPath bezierPath];
        ring.lineWidth = 2.1;
        ring.lineCapStyle = NSLineCapStyleRound;
        double fraction = fmin(1, fmax(0.012, remaining / 100.0));
        [ring appendBezierPathWithArcWithCenter:center radius:6.1 startAngle:90 endAngle:90 - 360 * fraction clockwise:YES];
        [ring stroke];
    }
    [image unlockFocus];
    image.template = YES;
    return image;
}

- (void)togglePopover:(id)sender {
    if (_popover.shown) {
        [_popover performClose:nil];
    } else {
        [self refresh];
        [_popover showRelativeToRect:_statusItem.button.bounds ofView:_statusItem.button preferredEdge:NSRectEdgeMinY];
        [_popover.contentViewController.view.window makeKeyWindow];
    }
}

@end

int main(int argc, const char *argv[]) {
    (void)argc;
    (void)argv;
    @autoreleasepool {
        NSApplication *application = NSApplication.sharedApplication;
        TBAppDelegate *delegate = [TBAppDelegate new];
        application.delegate = delegate;
        [application setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [application run];
    }
    return 0;
}
