#import <UIKit/UIKit.h>

static NSString * const kJevAPIKey = @"JevWeChatAPIKey";
static NSInteger const kJevButtonTag = 20260929;
static NSInteger const kJevOverlayWindowTag = 20260931;

static UIWindow *gJevMainWindow = nil;
static UIWindow *gJevOverlayWindow = nil;
static UITapGestureRecognizer *gJevSelectionTap = nil;
static BOOL gJevSelectingMessage = NO;
static BOOL gJevRequestInFlight = NO;

#pragma mark - Window helpers

static UIWindow *JevFindActiveWindow(void) {
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (scene.activationState != UISceneActivationStateForegroundActive) continue;
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;

        UIWindowScene *sceneWindow = (UIWindowScene *)scene;

        for (UIWindow *window in sceneWindow.windows) {
            if (window.isKeyWindow && window != gJevOverlayWindow) return window;
        }
        for (UIWindow *window in sceneWindow.windows) {
            if (window != gJevOverlayWindow && !window.hidden && window.alpha > 0.0 &&
                window.windowLevel == UIWindowLevelNormal) {
                return window;
            }
        }
    }
    return nil;
}

#pragma mark - Text extraction

static void JevCollectTextInView(UIView *view, NSMutableArray<NSString *> *out) {
    if (!view) return;

    if ([view isKindOfClass:[UILabel class]]) {
        NSString *s = [(UILabel *)view text];
        if (s.length) [out addObject:s];
    } else if ([view isKindOfClass:[UITextView class]]) {
        NSString *s = [(UITextView *)view text];
        if (s.length) [out addObject:s];
    } else if ([view isKindOfClass:[UITextField class]]) {
        NSString *s = [(UITextField *)view text];
        if (s.length) [out addObject:s];
    }

    for (UIView *sub in view.subviews) {
        JevCollectTextInView(sub, out);
    }
}

static NSString *JevCleanText(NSString *raw) {
    if (!raw.length) return @"";
    NSString *s = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    s = [s stringByReplacingOccurrencesOfString:@"\u200b" withString:@""];
    return s;
}

static NSString *JevUniqueJoined(NSArray<NSString *> *items) {
    NSMutableArray *clean = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (NSString *raw in items) {
        NSString *s = JevCleanText(raw);
        if (s.length < 2 || s.length > 1000) continue;
        if ([seen containsObject:s]) continue;
        [seen addObject:s];
        [clean addObject:s];
    }
    return [clean componentsJoinedByString:@"\n"];
}

// Prefer the smallest useful text-bearing subtree at/above the tapped view.
static NSString *JevMessageTextForTappedView(UIView *hitView) {
    if (!hitView) return @"";

    UIView *candidate = hitView;
    for (NSInteger level = 0; candidate && level < 10; level++, candidate = candidate.superview) {
        NSMutableArray *items = [NSMutableArray array];
        JevCollectTextInView(candidate, items);

        NSString *joined = JevUniqueJoined(items);
        if (joined.length >= 2) {
            // If a candidate contains a large amount of UI text, keep the first
            // compact block rather than sending the whole screen to the model.
            NSArray *lines = [joined componentsSeparatedByString:@"\n"];
            if (lines.count > 8) {
                NSMutableArray *small = [NSMutableArray array];
                for (NSString *line in lines) {
                    if (line.length >= 2 && line.length <= 500) {
                        [small addObject:line];
                        if (small.count >= 3) break;
                    }
                }
                NSString *compact = [small componentsJoinedByString:@"\n"];
                if (compact.length) return compact;
            }
            return joined;
        }
    }
    return @"";
}

#pragma mark - Result window

@interface JevOverlayController : UIViewController
@property(nonatomic, copy) NSString *titleText;
@property(nonatomic, copy) NSString *bodyText;
@property(nonatomic, assign) BOOL closeOnTap;
@end

@implementation JevOverlayController

- (void)loadView {
    self.view = [[UIView alloc] initWithFrame:CGRectZero];
    self.view.backgroundColor = [UIColor clearColor];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self buildCard];
}

- (void)buildCard {
    for (UIView *v in [self.view.subviews copy]) [v removeFromSuperview];

    CGFloat width = MIN(self.view.bounds.size.width - 32.0, 360.0);
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(16, 0, width, 10)];
    card.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.96];
    card.layer.cornerRadius = 18.0;
    card.layer.masksToBounds = YES;
    card.userInteractionEnabled = YES;

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(18, 14, width - 60, 28)];
    title.text = self.titleText.length ? self.titleText : @"Jev · TypeSafe";
    title.textColor = [UIColor whiteColor];
    title.font = [UIFont boldSystemFontOfSize:17];
    title.numberOfLines = 1;

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.frame = CGRectMake(width - 48, 8, 40, 40);
    [close setTitle:@"×" forState:UIControlStateNormal];
    [close setTitleColor:[UIColor colorWithRed:0.2 green:0.55 blue:1 alpha:1] forState:UIControlStateNormal];
    close.titleLabel.font = [UIFont boldSystemFontOfSize:28];
    [close addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];

    UILabel *body = [[UILabel alloc] initWithFrame:CGRectMake(18, 50, width - 36, 10)];
    body.text = self.bodyText ?: @"";
    body.textColor = [UIColor whiteColor];
    body.font = [UIFont systemFontOfSize:14];
    body.numberOfLines = 0;
    body.lineBreakMode = NSLineBreakByWordWrapping;
    [body sizeToFit];

    CGFloat bodyHeight = MAX(body.bounds.size.height, 30);
    CGFloat cardHeight = MIN(MAX(92.0 + bodyHeight, 120.0), self.view.bounds.size.height - 70.0);
    card.frame = CGRectMake((self.view.bounds.size.width - width) / 2.0,
                            MAX(60.0, self.view.safeAreaInsets.top + 12.0),
                            width, cardHeight);
    body.frame = CGRectMake(18, 52, width - 36, cardHeight - 90);

    UILabel *hint = [[UILabel alloc] initWithFrame:CGRectMake(18, cardHeight - 34, width - 36, 22)];
    hint.text = @"轻点卡片关闭";
    hint.textColor = [UIColor colorWithWhite:0.75 alpha:1];
    hint.font = [UIFont systemFontOfSize:12];

    [card addSubview:title];
    [card addSubview:close];
    [card addSubview:body];
    [card addSubview:hint];
    [self.view addSubview:card];

    if (self.closeOnTap) {
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(cardTapped:)];
        [card addGestureRecognizer:tap];
    }
}

- (void)closeTapped {
    if (gJevOverlayWindow) {
        gJevOverlayWindow.hidden = YES;
        gJevOverlayWindow.rootViewController = nil;
        gJevOverlayWindow = nil;
    }
}

- (void)cardTapped:(UITapGestureRecognizer *)gr {
    if (gr.state == UIGestureRecognizerStateEnded) [self closeTapped];
}

@end

static void JevHideOverlay(void) {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ JevHideOverlay(); });
        return;
    }
    if (gJevOverlayWindow) {
        gJevOverlayWindow.hidden = YES;
        gJevOverlayWindow.rootViewController = nil;
        gJevOverlayWindow = nil;
    }
}

static void JevShowOverlay(NSString *title, NSString *body) {
    void (^work)(void) = ^{
        UIWindow *mainWindow = JevFindActiveWindow();
        if (!mainWindow || !mainWindow.windowScene) return;

        // Remove the previous Jev window synchronously. Never schedule a
        // deferred hide here, otherwise the new window can be hidden too.
        JevHideOverlay();

        UIWindow *overlay = [[UIWindow alloc] initWithWindowScene:mainWindow.windowScene];
        overlay.frame = mainWindow.bounds;
        overlay.backgroundColor = [UIColor clearColor];
        overlay.windowLevel = UIWindowLevelAlert + 1.0;
        overlay.tag = kJevOverlayWindowTag;
        overlay.hidden = NO;
        overlay.alpha = 1.0;

        JevOverlayController *vc = [JevOverlayController new];
        vc.titleText = title ?: @"Jev · TypeSafe";
        vc.bodyText = body ?: @"";
        vc.closeOnTap = YES;
        overlay.rootViewController = vc;

        gJevOverlayWindow = overlay;
        [overlay makeKeyAndVisible];
        NSLog(@"[JevWeChatTweak] overlay shown");
    };

    if ([NSThread isMainThread]) work();
    else dispatch_async(dispatch_get_main_queue(), work);
}

#pragma mark - API key

static NSString *JevNormalizedAPIKey(NSString *input) {
    NSString *key = [input stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([key hasPrefix:@"Bearer "]) key = [key substringFromIndex:7];
    if ([key hasPrefix:@"bearer "]) key = [key substringFromIndex:7];
    return [key stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static void JevAskForAPIKey(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = JevFindActiveWindow();
        if (!window) return;
        UIViewController *presenter = window.rootViewController;
        if (!presenter) return;
        while (presenter.presentedViewController) presenter = presenter.presentedViewController;

        NSString *oldKey = [[NSUserDefaults standardUserDefaults] stringForKey:kJevAPIKey] ?: @"";
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:oldKey.length ? @"修改 Jev API Key" : @"Jev API Key"
                                                                         message:@"输入 TypeSafe 直连 API Key。保存后不会自动分析聊天。"
                                                                  preferredStyle:UIAlertControllerStyleAlert];
        [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
            field.placeholder = @"apikey_...";
            field.secureTextEntry = YES;
            field.clearButtonMode = UITextFieldViewModeWhileEditing;
            field.text = oldKey;
        }];
        [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            NSString *key = JevNormalizedAPIKey(alert.textFields.firstObject.text ?: @"");
            if (key.length < 8) {
                JevShowOverlay(@"Jev", @"API Key 太短，请检查复制内容。\n\n不会自动调用 API。");
                return;
            }
            [[NSUserDefaults standardUserDefaults] setObject:key forKey:kJevAPIKey];
            [[NSUserDefaults standardUserDefaults] synchronize];
            JevShowOverlay(@"Jev", @"API Key 已保存。\n\n点击 Jev 后选择一条消息即可分析。");
        }]];
        [presenter presentViewController:alert animated:YES completion:nil];
    });
}

#pragma mark - API formatting

static NSString *JevPrettyAnswer(NSDictionary *answer) {
    if (![answer isKindOfClass:[NSDictionary class]]) return @"未返回";
    NSString *type = answer[@"type"];
    if ([type isEqualToString:@"choice"]) {
        NSString *choice = answer[@"choice"];
        NSNumber *confidence = answer[@"confidence"];
        if (choice.length && [confidence isKindOfClass:[NSNumber class]])
            return [NSString stringWithFormat:@"选择：%@\n置信度：%.0f%%", choice, confidence.doubleValue * 100.0];
        if (choice.length) return [NSString stringWithFormat:@"选择：%@", choice];
    }
    if ([type isEqualToString:@"score"]) {
        NSNumber *score = answer[@"score"];
        NSNumber *confidence = answer[@"confidence"];
        if ([score isKindOfClass:[NSNumber class]] && [confidence isKindOfClass:[NSNumber class]])
            return [NSString stringWithFormat:@"评分：%@\n置信度：%.0f%%", score, confidence.doubleValue * 100.0];
        if ([score isKindOfClass:[NSNumber class]]) return [NSString stringWithFormat:@"评分：%@", score];
    }
    if ([type isEqualToString:@"noul"]) {
        NSNumber *noul = answer[@"noul"];
        if ([noul isKindOfClass:[NSNumber class]]) return [NSString stringWithFormat:@"概率：%.0f%%", noul.doubleValue * 100.0];
    }
    return [NSString stringWithFormat:@"%@", answer];
}

static void JevCallAPIWithState(NSString *state) {
    NSString *apiKey = [[NSUserDefaults standardUserDefaults] stringForKey:kJevAPIKey];
    if (apiKey.length == 0) {
        JevAskForAPIKey();
        return;
    }
    if (gJevRequestInFlight) return;
    gJevRequestInFlight = YES;

    JevShowOverlay(@"Jev · TypeSafe", @"正在分析这条消息……");

    NSDictionary *body = @{
        @"model": @"jev-latest",
        @"state": state ?: @"",
        @"questions": @{
            @"intent": @{
                @"type": @"choice",
                @"instructions": @"判断这条消息的主要意图。",
                @"criteria": @{
                    @"question": @"主要是在询问信息或寻求解释。",
                    @"request": @"主要是在要求对方做某件事。",
                    @"social": @"主要是闲聊、社交或关系表达。",
                    @"conflict": @"包含明显的不满、争执、投诉或紧张。",
                    @"planning": @"主要是在安排时间、计划或物流。",
                    @"other": @"以上都不明确符合。"
                }
            },
            @"urgency": @{
                @"type": @"score",
                @"instructions": @"判断这条消息表达的紧急程度。",
                @"criteria": @[ @"不紧急", @"低", @"中等", @"高", @"非常紧急" ]
            },
            @"needs_care": @{
                @"type": @"noul",
                @"instructions": @"回复这条消息前是否需要额外谨慎，以避免不恰当回复使情况变差？"
            }
        }
    };

    NSError *jsonError = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:body options:0 error:&jsonError];
    if (!jsonData || jsonError) {
        gJevRequestInFlight = NO;
        JevShowOverlay(@"Jev · TypeSafe", @"请求数据生成失败。\n\n请重试。");
        return;
    }

    NSURL *url = [NSURL URLWithString:@"https://api.typesafe.ai/v1/systemone"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    request.timeoutInterval = 20.0;
    [request setValue:[NSString stringWithFormat:@"Bearer %@", apiKey] forHTTPHeaderField:@"Authorization"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    request.HTTPBody = jsonData;

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            gJevRequestInFlight = NO;
            if (error) {
                JevShowOverlay(@"Jev · TypeSafe", [NSString stringWithFormat:@"网络请求失败\n\n%@", error.localizedDescription ?: @"未知错误"]);
                return;
            }
            NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
            if (http.statusCode < 200 || http.statusCode >= 300) {
                NSString *serverText = data.length ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"无返回内容";
                if (serverText.length > 900) serverText = [serverText substringToIndex:900];
                JevShowOverlay(@"Jev · TypeSafe", [NSString stringWithFormat:@"HTTP %ld\n\n%@", (long)http.statusCode, serverText]);
                return;
            }

            NSError *parseError = nil;
            NSDictionary *payload = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];
            if (![payload isKindOfClass:[NSDictionary class]] || parseError) {
                JevShowOverlay(@"Jev · TypeSafe", @"API 返回内容无法解析。\n\n请把这个结果截图给我。");
                return;
            }
            NSDictionary *answers = payload[@"answers"];
            if (![answers isKindOfClass:[NSDictionary class]]) {
                NSString *raw = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
                if (raw.length > 900) raw = [raw substringToIndex:900];
                JevShowOverlay(@"Jev · TypeSafe", [NSString stringWithFormat:@"没有返回 answers。\n\n%@", raw]);
                return;
            }

            NSString *intent = JevPrettyAnswer(answers[@"intent"]);
            NSString *urgency = JevPrettyAnswer(answers[@"urgency"]);
            NSString *care = JevPrettyAnswer(answers[@"needs_care"]);
            NSString *message = [NSString stringWithFormat:@"对话意图\n%@\n\n紧急程度\n%@\n\n是否需要谨慎\n%@\n\n轻点卡片关闭", intent, urgency, care];
            JevShowOverlay(@"Jev · TypeSafe", message);
        });
    }];
    [task resume];
}

#pragma mark - Message selection
static UILabel *gJevSelectionBanner = nil;

static void JevShowSelectionBanner(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = gJevMainWindow ?: JevFindActiveWindow();
        if (!window) return;
        if (gJevSelectionBanner) return;

        CGFloat width = MIN(window.bounds.size.width - 40.0, 320.0);
        UILabel *banner = [[UILabel alloc] initWithFrame:CGRectMake((window.bounds.size.width - width) / 2.0,
                                                                      window.safeAreaInsets.top + 72.0,
                                                                      width, 38.0)];
        banner.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.92];
        banner.textColor = [UIColor whiteColor];
        banner.textAlignment = NSTextAlignmentCenter;
        banner.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
        banner.text = @"点击一条文字消息，Jev 将分析它";
        banner.layer.cornerRadius = 14.0;
        banner.layer.masksToBounds = YES;
        banner.userInteractionEnabled = NO;
        [window addSubview:banner];
        gJevSelectionBanner = banner;
    });
}

static void JevHideSelectionBanner(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [gJevSelectionBanner removeFromSuperview];
        gJevSelectionBanner = nil;
    });
}


static void JevSetSelecting(BOOL selecting) {
    gJevSelectingMessage = selecting;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (gJevMainWindow) {
            UIButton *button = (UIButton *)[gJevMainWindow viewWithTag:kJevButtonTag];
            if ([button isKindOfClass:[UIButton class]]) {
                [button setTitle:selecting ? @"选消息" : @"Jev" forState:UIControlStateNormal];
                button.backgroundColor = selecting ? [UIColor colorWithRed:0.12 green:0.45 blue:0.95 alpha:0.95] : [UIColor colorWithWhite:0.08 alpha:0.92];
            }
        }
        if (selecting) JevShowSelectionBanner();
        else JevHideSelectionBanner();
    });
}

static void JevHandleMessageTap(UITapGestureRecognizer *gesture) {
    if (!gJevSelectingMessage) return;
    if (gesture.state != UIGestureRecognizerStateEnded) return;

    UIWindow *window = gJevMainWindow ?: JevFindActiveWindow();
    if (!window) return;

    CGPoint point = [gesture locationInView:window];
    UIView *hit = [window hitTest:point withEvent:nil];

    // Ignore our own button or unrelated controls.
    if ([hit isKindOfClass:[UIButton class]] || [hit viewWithTag:kJevButtonTag]) {
        return;
    }

    NSString *text = JevMessageTextForTappedView(hit);
    if (text.length < 2) {
        JevShowOverlay(@"Jev", @"没有识别到这条消息的文字。\n\n请点击文字气泡本身再试一次。");
        return;
    }

    JevSetSelecting(NO);
    NSLog(@"[JevWeChatTweak] selected message length=%lu", (unsigned long)text.length);
    JevCallAPIWithState(text);
}

#pragma mark - Button

@interface JevController : NSObject
- (void)buttonTapped:(UIButton *)sender;
- (void)buttonLongPressed:(UILongPressGestureRecognizer *)gesture;
@end

@implementation JevController

- (void)buttonTapped:(UIButton *)sender {
    if (gJevSelectingMessage) {
        JevSetSelecting(NO);
        return;
    }
    JevSetSelecting(YES);
}

- (void)buttonLongPressed:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        JevSetSelecting(NO);
        JevAskForAPIKey();
    }
}

@end

static JevController *gJevController = nil;

@interface JevSelectionTarget : NSObject
+ (instancetype)sharedTarget;
- (void)handleTap:(UITapGestureRecognizer *)gesture;
@end

static void JevInstallButton(void) {
    UIWindow *window = JevFindActiveWindow();
    if (!window) return;
    gJevMainWindow = window;

    UIButton *existing = (UIButton *)[window viewWithTag:kJevButtonTag];
    if ([existing isKindOfClass:[UIButton class]]) return;

    if (!gJevController) gJevController = [JevController new];

    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.tag = kJevButtonTag;
    button.frame = CGRectMake(window.bounds.size.width - 88.0, window.safeAreaInsets.top + 20.0, 68.0, 40.0);
    button.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleBottomMargin;
    button.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.92];
    [button setTitle:@"Jev" forState:UIControlStateNormal];
    [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    button.layer.cornerRadius = 12.0;
    [button addTarget:gJevController action:@selector(buttonTapped:) forControlEvents:UIControlEventTouchUpInside];

    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:gJevController action:@selector(buttonLongPressed:)];
    longPress.minimumPressDuration = 0.8;
    [button addGestureRecognizer:longPress];

    [window addSubview:button];

    if (!gJevSelectionTap) {
        gJevSelectionTap = [[UITapGestureRecognizer alloc] initWithTarget:[JevSelectionTarget sharedTarget] action:@selector(handleTap:)];
        gJevSelectionTap.numberOfTapsRequired = 1;
        gJevSelectionTap.cancelsTouchesInView = NO;
        gJevSelectionTap.delaysTouchesBegan = NO;
        gJevSelectionTap.delaysTouchesEnded = NO;
        [window addGestureRecognizer:gJevSelectionTap];
    }

    NSLog(@"[JevWeChatTweak] V7 button installed");
}

// Small proxy object so the gesture recognizer can safely retain its target.
@implementation JevSelectionTarget
+ (instancetype)sharedTarget { static JevSelectionTarget *x; static dispatch_once_t once; dispatch_once(&once, ^{ x = [JevSelectionTarget new]; }); return x; }
- (void)handleTap:(UITapGestureRecognizer *)gesture { JevHandleMessageTap(gesture); }
@end

%ctor {
    @autoreleasepool {
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(__unused NSNotification *notification) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                JevInstallButton();
            });
        }];

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            JevInstallButton();
        });
    }
}
