#import <UIKit/UIKit.h>

static NSString * const kJevAPIKey = @"JevWeChatAPIKey";
static NSString * const kJevButtonTag = @"20260929";

#pragma mark - Utilities

static UIWindow *JevFindActiveWindow(void) {
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (scene.activationState != UISceneActivationStateForegroundActive) continue;
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;

        UIWindowScene *windowScene = (UIWindowScene *)scene;

        for (UIWindow *window in windowScene.windows) {
            if (window.isKeyWindow) return window;
        }

        for (UIWindow *window in windowScene.windows) {
            if (!window.hidden &&
                window.alpha > 0.0 &&
                window.windowLevel == UIWindowLevelNormal) {
                return window;
            }
        }
    }
    return nil;
}

static void JevCollectText(UIView *view, NSMutableArray<NSString *> *result) {
    if (!view) return;

    if ([view isKindOfClass:[UILabel class]]) {
        NSString *text = [(UILabel *)view text];
        if (text.length > 0) [result addObject:text];
    } else if ([view isKindOfClass:[UITextView class]]) {
        NSString *text = [(UITextView *)view text];
        if (text.length > 0) [result addObject:text];
    } else if ([view isKindOfClass:[UITextField class]]) {
        NSString *text = [(UITextField *)view text];
        if (text.length > 0) [result addObject:text];
    }

    for (UIView *subview in view.subviews) {
        JevCollectText(subview, result);
    }
}

static NSString *JevVisibleConversationText(UIWindow *window) {
    NSMutableArray<NSString *> *items = [NSMutableArray array];
    JevCollectText(window, items);

    NSMutableArray<NSString *> *clean = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];

    for (NSString *raw in items) {
        NSString *text = [raw stringByTrimmingCharactersInSet:
                          [NSCharacterSet whitespaceAndNewlineCharacterSet]];

        if (text.length < 2 || text.length > 500) continue;
        if ([seen containsObject:text]) continue;

        [seen addObject:text];
        [clean addObject:text];
    }

    // Keep the most recent-looking visible text without trying to depend
    // on private WeChat classes.
    NSUInteger maxItems = 20;
    if (clean.count > maxItems) {
        clean = [[clean subarrayWithRange:NSMakeRange(clean.count - maxItems, maxItems)] mutableCopy];
    }

    return [clean componentsJoinedByString:@"\n"];
}

#pragma mark - Jev API

static void JevShowAlert(NSString *title, NSString *message) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = JevFindActiveWindow();
        if (!window) return;

        UIViewController *presenter = window.rootViewController;
        if (!presenter) return;

        while (presenter.presentedViewController) {
            presenter = presenter.presentedViewController;
        }

        UIAlertController *alert =
            [UIAlertController alertControllerWithTitle:title
                                                message:message
                                         preferredStyle:UIAlertControllerStyleAlert];

        [alert addAction:
            [UIAlertAction actionWithTitle:@"确定"
                                     style:UIAlertActionStyleDefault
                                   handler:nil]];

        [presenter presentViewController:alert animated:YES completion:nil];
    });
}

static void JevAskForAPIKey(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = JevFindActiveWindow();
        if (!window) return;

        UIViewController *presenter = window.rootViewController;
        if (!presenter) return;

        while (presenter.presentedViewController) {
            presenter = presenter.presentedViewController;
        }

        UIAlertController *alert =
            [UIAlertController alertControllerWithTitle:@"Jev API Key"
                                                message:@"第一次使用请输入 Jev API Key。只保存在本机，不写入 GitHub。"
                                         preferredStyle:UIAlertControllerStyleAlert];

        [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
            field.placeholder = @"Bearer API Key";
            field.secureTextEntry = YES;
            field.clearButtonMode = UITextFieldViewModeWhileEditing;
        }];

        [alert addAction:
            [UIAlertAction actionWithTitle:@"取消"
                                     style:UIAlertActionStyleCancel
                                   handler:nil]];

        [alert addAction:
            [UIAlertAction actionWithTitle:@"保存并分析"
                                     style:UIAlertActionStyleDefault
                                   handler:^(UIAlertAction *action) {
            NSString *key = alert.textFields.firstObject.text;
            if (key.length < 10) {
                JevShowAlert(@"Jev", @"API Key 看起来不正确。");
                return;
            }

            [[NSUserDefaults standardUserDefaults] setObject:key forKey:kJevAPIKey];
            [[NSUserDefaults standardUserDefaults] synchronize];

            // Re-run after saving.
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter]
                    postNotificationName:@"JevRunAnalysis"
                    object:nil];
            });
        }]];

        [presenter presentViewController:alert animated:YES completion:nil];
    });
}

static NSString *JevPrettyAnswer(NSDictionary *answer) {
    if (![answer isKindOfClass:[NSDictionary class]]) return @"";

    NSString *type = answer[@"type"];
    if ([type isEqualToString:@"choice"]) {
        NSString *choice = answer[@"choice"];
        NSNumber *confidence = answer[@"confidence"];
        if (choice.length) {
            if ([confidence isKindOfClass:[NSNumber class]]) {
                return [NSString stringWithFormat:@"选择：%@\n置信度：%.0f%%",
                        choice, confidence.doubleValue * 100.0];
            }
            return [NSString stringWithFormat:@"选择：%@", choice];
        }
    }

    if ([type isEqualToString:@"score"]) {
        NSNumber *score = answer[@"score"];
        NSNumber *confidence = answer[@"confidence"];
        if ([score isKindOfClass:[NSNumber class]]) {
            if ([confidence isKindOfClass:[NSNumber class]]) {
                return [NSString stringWithFormat:@"评分：%@\n置信度：%.0f%%",
                        score, confidence.doubleValue * 100.0];
            }
            return [NSString stringWithFormat:@"评分：%@", score];
        }
    }

    if ([type isEqualToString:@"noul"]) {
        NSNumber *noul = answer[@"noul"];
        if ([noul isKindOfClass:[NSNumber class]]) {
            return [NSString stringWithFormat:@"概率：%.0f%%",
                    noul.doubleValue * 100.0];
        }
    }

    return [NSString stringWithFormat:@"%@", answer];
}

static void JevCallAPIWithState(NSString *state) {
    NSString *apiKey = [[NSUserDefaults standardUserDefaults] stringForKey:kJevAPIKey];

    if (apiKey.length == 0) {
        JevAskForAPIKey();
        return;
    }

    NSDictionary *body = @{
        @"model": @"typesafe/jev-1.13",
        @"state": state ?: @"",
        @"questions": @{
            @"intent": @{
                @"type": @"choice",
                @"instructions": @"What is the main intent of this conversation?",
                @"criteria": @{
                    @"question": @"The other person is mainly asking a question or seeking information.",
                    @"request": @"The other person is asking the user to do something.",
                    @"social": @"The conversation is mainly social, casual, or relational.",
                    @"conflict": @"The conversation contains disagreement, tension, complaint, or conflict.",
                    @"planning": @"The conversation is mainly about arranging plans, timing, or logistics.",
                    @"other": @"None of the above clearly applies."
                }
            },
            @"urgency": @{
                @"type": @"score",
                @"instructions": @"How urgent is the situation conveyed by the conversation?",
                @"criteria": @[
                    @"not urgent",
                    @"low urgency",
                    @"moderate urgency",
                    @"high urgency",
                    @"critical urgency"
                ]
            },
            @"needs_care": @{
                @"type": @"noul",
                @"instructions": @"Does this conversation require extra care before replying because a careless response could worsen the situation?"
            }
        }
    };

    NSError *jsonError = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:body options:0 error:&jsonError];

    if (!jsonData || jsonError) {
        JevShowAlert(@"Jev", @"请求数据生成失败。");
        return;
    }

    NSURL *url = [NSURL URLWithString:@"https://thejevai.com/v1/systemone"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:[NSString stringWithFormat:@"Bearer %@", apiKey]
   forHTTPHeaderField:@"Authorization"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    request.HTTPBody = jsonData;

    NSURLSessionDataTask *task =
    [[NSURLSession sharedSession]
        dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {

        if (error) {
            JevShowAlert(@"Jev", [NSString stringWithFormat:@"网络请求失败：\n%@",
                                  error.localizedDescription]);
            return;
        }

        NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;

        if (http.statusCode < 200 || http.statusCode >= 300) {
            NSString *serverText = data.length
                ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]
                : @"";
            JevShowAlert(@"Jev",
                         [NSString stringWithFormat:@"API 返回 HTTP %ld\n%@",
                          (long)http.statusCode, serverText ?: @""]);
            return;
        }

        NSError *parseError = nil;
        NSDictionary *payload =
            [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];

        if (!payload || parseError) {
            JevShowAlert(@"Jev", @"API 返回内容无法解析。");
            return;
        }

        NSDictionary *answers = payload[@"answers"];
        if (![answers isKindOfClass:[NSDictionary class]]) {
            JevShowAlert(@"Jev", @"API 没有返回 answers。");
            return;
        }

        NSString *intent = JevPrettyAnswer(answers[@"intent"]);
        NSString *urgency = JevPrettyAnswer(answers[@"urgency"]);
        NSString *care = JevPrettyAnswer(answers[@"needs_care"]);

        NSString *message =
            [NSString stringWithFormat:
                @"%@\n\n%@\n\n需要谨慎：%@",
                intent.length ? intent : @"意图：未返回",
                urgency.length ? urgency : @"紧急程度：未返回",
                care.length ? care : @"未返回"];

        JevShowAlert(@"Jev 分析结果", message);
    }];

    [task resume];
}

#pragma mark - Controller

@interface JevController : NSObject
- (void)buttonTapped:(UIButton *)sender;
@end

@implementation JevController

- (void)buttonTapped:(UIButton *)sender {
    UIWindow *window = JevFindActiveWindow();
    if (!window) return;

    NSString *state = JevVisibleConversationText(window);

    if (state.length < 5) {
        JevShowAlert(@"Jev", @"没有读取到足够的聊天文字。\n请进入具体聊天窗口后再点 Jev。");
        return;
    }

    JevCallAPIWithState(state);
}

@end

static JevController *gJevController;

static void JevInstallButton(void) {
    UIWindow *window = JevFindActiveWindow();
    if (!window) return;

    if ([window viewWithTag:20260929]) return;

    if (!gJevController) {
        gJevController = [JevController new];
    }

    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.tag = 20260929;

    button.frame = CGRectMake(
        window.bounds.size.width - 86.0,
        window.safeAreaInsets.top + 20.0,
        66.0,
        40.0
    );

    button.autoresizingMask =
        UIViewAutoresizingFlexibleLeftMargin |
        UIViewAutoresizingFlexibleBottomMargin;

    button.backgroundColor =
        [UIColor colorWithWhite:0.08 alpha:0.92];

    [button setTitle:@"Jev" forState:UIControlStateNormal];
    [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    button.layer.cornerRadius = 12.0;

    [button addTarget:gJevController
               action:@selector(buttonTapped:)
     forControlEvents:UIControlEventTouchUpInside];

    [window addSubview:button];

    NSLog(@"[JevWeChatTweak] full version loaded");
}

%ctor {
    @autoreleasepool {
        [[NSNotificationCenter defaultCenter]
            addObserverForName:UIApplicationDidBecomeActiveNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(__unused NSNotification *notification) {

            dispatch_after(
                dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)),
                dispatch_get_main_queue(), ^{
                    JevInstallButton();
                }
            );
        }];

        [[NSNotificationCenter defaultCenter]
            addObserverForName:@"JevRunAnalysis"
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(__unused NSNotification *notification) {
            UIWindow *window = JevFindActiveWindow();
            if (!window) return;

            NSString *state = JevVisibleConversationText(window);
            if (state.length < 5) {
                JevShowAlert(@"Jev", @"没有读取到足够的聊天文字。");
                return;
            }

            JevCallAPIWithState(state);
        }];
    }
}
