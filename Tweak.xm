#import <UIKit/UIKit.h>

static NSString * const kJevAPIKeyKey = @"JevWeChatAPIKey";
static NSInteger const kJevButtonTag = 20260929;

#pragma mark - Window

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

static UIViewController *JevTopViewController(UIWindow *window) {
    if (!window) return nil;

    UIViewController *vc = window.rootViewController;
    if (!vc) return nil;

    while (vc.presentedViewController) {
        vc = vc.presentedViewController;
    }

    return vc;
}

#pragma mark - Visible WeChat Text

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

    // Limit payload size while retaining the latest visible strings.
    NSUInteger maxItems = 20;
    if (clean.count > maxItems) {
        clean = [[clean subarrayWithRange:
                  NSMakeRange(clean.count - maxItems, maxItems)] mutableCopy];
    }

    return [clean componentsJoinedByString:@"\n"];
}

#pragma mark - UI

static void JevShowAlert(NSString *title, NSString *message) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = JevFindActiveWindow();
        UIViewController *presenter = JevTopViewController(window);
        if (!presenter) return;

        UIAlertController *alert =
            [UIAlertController alertControllerWithTitle:title
                                                message:message ?: @""
                                         preferredStyle:UIAlertControllerStyleAlert];

        [alert addAction:
            [UIAlertAction actionWithTitle:@"确定"
                                     style:UIAlertActionStyleDefault
                                   handler:nil]];

        [presenter presentViewController:alert animated:YES completion:nil];
    });
}

static void JevShowLoading(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = JevFindActiveWindow();
        UIViewController *presenter = JevTopViewController(window);
        if (!presenter) return;

        UIAlertController *alert =
            [UIAlertController alertControllerWithTitle:@"Jev"
                                                message:@"正在分析当前聊天……"
                                         preferredStyle:UIAlertControllerStyleAlert];

        alert.view.tag = 20260930;

        [presenter presentViewController:alert animated:YES completion:nil];
    });
}

static void JevHideLoading(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = JevFindActiveWindow();
        if (!window) return;

        UIViewController *vc = window.rootViewController;
        if (!vc) return;

        while (vc.presentedViewController) {
            UIViewController *next = vc.presentedViewController;

            if ([next isKindOfClass:[UIAlertController class]] &&
                next.view.tag == 20260930) {
                [next dismissViewControllerAnimated:NO completion:nil];
                return;
            }

            vc = next;
        }
    });
}

static void JevAskForAPIKey(void);
static void JevCallAPIWithState(NSString *state);

#pragma mark - API Response Formatting

static NSString *JevFormatAnswer(NSDictionary *answer) {
    if (![answer isKindOfClass:[NSDictionary class]]) {
        return @"未返回有效结果";
    }

    NSString *type = answer[@"type"];

    if ([type isEqualToString:@"choice"]) {
        NSString *choice = answer[@"choice"];
        NSNumber *confidence = answer[@"confidence"];

        if (choice.length && [confidence isKindOfClass:[NSNumber class]]) {
            return [NSString stringWithFormat:@"选择：%@\n置信度：%.0f%%",
                    choice, confidence.doubleValue * 100.0];
        }

        if (choice.length) {
            return [NSString stringWithFormat:@"选择：%@", choice];
        }
    }

    if ([type isEqualToString:@"score"]) {
        NSNumber *score = answer[@"score"];
        NSNumber *confidence = answer[@"confidence"];

        if ([score isKindOfClass:[NSNumber class]] &&
            [confidence isKindOfClass:[NSNumber class]]) {
            return [NSString stringWithFormat:@"评分：%.2f\n置信度：%.0f%%",
                    score.doubleValue, confidence.doubleValue * 100.0];
        }

        if ([score isKindOfClass:[NSNumber class]]) {
            return [NSString stringWithFormat:@"评分：%.2f",
                    score.doubleValue];
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

static NSString *JevServerErrorText(NSData *data) {
    if (!data.length) return @"服务器没有返回错误详情。";

    NSString *text = [[NSString alloc] initWithData:data
                                           encoding:NSUTF8StringEncoding];

    if (text.length > 1500) {
        text = [text substringToIndex:1500];
    }

    return text.length ? text : @"服务器返回了无法显示的错误内容。";
}

#pragma mark - Loading Result Helper

static void JevHideLoadingAndShowAlert(NSString *title, NSString *message) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = JevFindActiveWindow();
        if (!window) return;

        UIViewController *vc = window.rootViewController;
        if (!vc) return;

        while (vc.presentedViewController) {
            UIViewController *next = vc.presentedViewController;

            if ([next isKindOfClass:[UIAlertController class]] &&
                next.view.tag == 20260930) {
                [next dismissViewControllerAnimated:NO completion:^{
                    JevShowAlert(title, message);
                }];
                return;
            }

            vc = next;
        }

        JevShowAlert(title, message);
    });
}


#pragma mark - V3 API Connection Test

static NSString *JevFormatAnswer(NSDictionary *answer);
static NSString *JevServerErrorText(NSData *data);

static void JevTestAPIKey(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = JevFindActiveWindow();
        UIViewController *presenter = JevTopViewController(window);
        if (!presenter) return;

        NSString *apiKey = [[NSUserDefaults standardUserDefaults]
            stringForKey:kJevAPIKeyKey];

        if (apiKey.length == 0) {
            JevShowAlert(@"Jev API 测试", @"当前没有保存 API Key。请先长按 Jev 修改/保存 Key。");
            return;
        }

        UIAlertController *loading =
            [UIAlertController alertControllerWithTitle:@"Jev API 测试"
                                                message:@"正在测试 API Key 与 Jev API……\n\n这次不会读取微信聊天内容。"
                                         preferredStyle:UIAlertControllerStyleAlert];
        loading.view.tag = 20260931;
        [presenter presentViewController:loading animated:YES completion:nil];

        NSDictionary *body = @{
            @"model": @"jev-latest",
            @"state": @"这是一次 Jev API 连通性测试。请判断这句话是否表达了紧急情况。",
            @"questions": @{
                @"is_urgent": @{
                    @"type": @"noul",
                    @"instructions": @"Does this convey urgency?"
                }
            }
        };

        NSError *jsonError = nil;
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:body options:0 error:&jsonError];
        if (!jsonData || jsonError) {
            [loading dismissViewControllerAnimated:NO completion:^{
                JevShowAlert(@"Jev API 测试失败", [NSString stringWithFormat:@"本地 JSON 生成失败。\n\n%@", jsonError.localizedDescription]);
            }];
            return;
        }

        NSURL *url = [NSURL URLWithString:@"https://thejevai.com/v1/systemone"];
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
        request.HTTPMethod = @"POST";
        request.timeoutInterval = 20.0;
        [request setValue:[NSString stringWithFormat:@"Bearer %@", apiKey]
       forHTTPHeaderField:@"Authorization"];
        [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
        request.HTTPBody = jsonData;

        NSLog(@"[JevWeChatTweak] V3 API test start");

        NSURLSessionDataTask *task = [[NSURLSession sharedSession]
            dataTaskWithRequest:request
              completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {

            dispatch_async(dispatch_get_main_queue(), ^{
                UIViewController *root = JevFindActiveWindow().rootViewController;
                UIViewController *vc = root;
                while (vc.presentedViewController) vc = vc.presentedViewController;

                NSString *detail = nil;

                if (error) {
                    detail = [NSString stringWithFormat:@"网络请求失败：\n%@", error.localizedDescription];
                } else {
                    NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
                    NSString *server = JevServerErrorText(data);

                    if (http.statusCode >= 200 && http.statusCode < 300) {
                        NSError *parseError = nil;
                        id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];
                        if ([json isKindOfClass:[NSDictionary class]]) {
                            NSDictionary *answers = ((NSDictionary *)json)[@"answers"];
                            if ([answers isKindOfClass:[NSDictionary class]]) {
                                NSDictionary *answer = answers[@"is_urgent"];
                                detail = [NSString stringWithFormat:@"HTTP %ld\n\nAPI Key：有效\nAPI：连接正常\n模型：jev-latest\n\n返回：\n%@",
                                          (long)http.statusCode,
                                          JevFormatAnswer(answer)];
                            } else {
                                detail = [NSString stringWithFormat:@"HTTP %ld\n\n请求成功，但返回中没有 answers。\n\n原始返回：\n%@",
                                          (long)http.statusCode, server];
                            }
                        } else {
                            detail = [NSString stringWithFormat:@"HTTP %ld\n\nAPI 已响应，但返回不是有效 JSON。\n\n原始返回：\n%@",
                                      (long)http.statusCode, server];
                        }
                    } else {
                        detail = [NSString stringWithFormat:@"HTTP %ld\n\n服务器返回：\n%@",
                                  (long)http.statusCode, server];
                    }
                }

                if ([vc isKindOfClass:[UIAlertController class]] && vc.view.tag == 20260931) {
                    [vc dismissViewControllerAnimated:NO completion:^{
                        JevShowAlert(error ? @"Jev API 测试失败" : @"Jev API 测试结果", detail ?: @"没有返回详情。");
                    }];
                } else {
                    JevShowAlert(error ? @"Jev API 测试失败" : @"Jev API 测试结果", detail ?: @"没有返回详情。");
                }
            });
        }];

        [task resume];
    });
}

#pragma mark - API Key

static void JevAskForAPIKey(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = JevFindActiveWindow();
        UIViewController *presenter = JevTopViewController(window);
        if (!presenter) return;

        NSString *oldKey =
            [[NSUserDefaults standardUserDefaults] stringForKey:kJevAPIKeyKey];

        BOOL editing = oldKey.length > 0;

        NSString *title = editing ? @"修改 Jev API Key" : @"Jev API Key";
        NSString *message = editing
            ? @"输入新的 Jev API Key，保存后会覆盖当前 Key。"
            : @"输入你的 Jev API Key。测试版只保存在本机，不会写入 GitHub。";

        UIAlertController *alert =
            [UIAlertController alertControllerWithTitle:title
                                                message:message
                                         preferredStyle:UIAlertControllerStyleAlert];

        [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
            field.placeholder = @"sk_……";
            field.secureTextEntry = YES;
            field.clearButtonMode = UITextFieldViewModeWhileEditing;

            if (editing) {
                field.text = oldKey;
            }
        }];

        [alert addAction:
            [UIAlertAction actionWithTitle:@"取消"
                                     style:UIAlertActionStyleCancel
                                   handler:^(UIAlertAction *action) {
            JevHideLoading();
        }]];

        [alert addAction:
            [UIAlertAction actionWithTitle:@"保存并分析"
                                     style:UIAlertActionStyleDefault
                                   handler:^(UIAlertAction *action) {
            NSString *key =
                [alert.textFields.firstObject.text
                    stringByTrimmingCharactersInSet:
                        [NSCharacterSet whitespaceAndNewlineCharacterSet]];

            if (key.length < 10) {
                JevShowAlert(@"Jev", @"API Key 看起来不正确。");
                return;
            }

            [[NSUserDefaults standardUserDefaults]
                setObject:key forKey:kJevAPIKeyKey];

            [[NSUserDefaults standardUserDefaults] synchronize];

            dispatch_async(dispatch_get_main_queue(), ^{
                UIWindow *currentWindow = JevFindActiveWindow();
                NSString *currentState =
                    JevVisibleConversationText(currentWindow);

                if (currentState.length < 5) {
                    JevShowAlert(
                        @"Jev",
                        @"API Key 已保存，但没有读取到足够的聊天文字。"
                    );
                    return;
                }

                JevShowLoading();
                JevCallAPIWithState(currentState);
            });
        }]];

        [presenter presentViewController:alert animated:YES completion:nil];
    });
}


#pragma mark - Jev API

static void JevCallAPIWithState(NSString *state) {
    NSString *apiKey =
        [[NSUserDefaults standardUserDefaults] stringForKey:kJevAPIKeyKey];

    if (apiKey.length == 0) {
        JevAskForAPIKey();
        return;
    }

    /*
     Jev System One:
       POST https://thejevai.com/v1/systemone

     We use:
       - Choice: conversation intent
       - Score: urgency
       - Noul: whether extra care is needed
    */

    NSDictionary *body = @{
        @"model": @"jev-latest",

        @"state": state ?: @"",

        @"questions": @{
            @"intent": @{
                @"type": @"choice",
                @"instructions": @"Classify the main intent of the visible conversation from the user's perspective.",
                @"criteria": @{
                    @"question": @"The other person is mainly asking a question or seeking information.",
                    @"request": @"The other person is asking the user to do something.",
                    @"social": @"The conversation is mainly casual, social, or relational.",
                    @"conflict": @"The conversation contains disagreement, tension, complaint, or conflict.",
                    @"planning": @"The conversation is mainly about plans, timing, or logistics.",
                    @"other": @"None of the above clearly applies."
                }
            },

            @"urgency": @{
                @"type": @"score",
                @"instructions": @"Rate how urgent the situation conveyed by the visible conversation is.",
                @"criteria": @[
                    @"Not urgent",
                    @"Low urgency",
                    @"Moderate urgency",
                    @"High urgency",
                    @"Critical urgency"
                ]
            },

            @"needs_care": @{
                @"type": @"noul",
                @"instructions": @"Does this conversation require extra care before replying because a careless response could worsen the situation?",
                @"criteria": @{
                    @"true": @"A careless reply could reasonably worsen the situation.",
                    @"false": @"A normal reply is unlikely to worsen the situation."
                }
            }
        }
    };

    NSError *jsonError = nil;
    NSData *jsonData =
        [NSJSONSerialization dataWithJSONObject:body
                                        options:0
                                          error:&jsonError];

    if (!jsonData || jsonError) {
        JevHideLoading();
        JevShowAlert(@"Jev", @"请求数据生成失败。");
        return;
    }

    NSURL *url =
        [NSURL URLWithString:@"https://thejevai.com/v1/systemone"];

    NSMutableURLRequest *request =
        [NSMutableURLRequest requestWithURL:url];

    request.HTTPMethod = @"POST";

    [request setValue:
        [NSString stringWithFormat:@"Bearer %@", apiKey]
       forHTTPHeaderField:@"Authorization"];

    [request setValue:@"application/json"
   forHTTPHeaderField:@"Content-Type"];

    request.HTTPBody = jsonData;

    NSLog(@"[JevWeChatTweak] API request start, state length=%lu",
          (unsigned long)state.length);

    // Never leave the UI stuck on “正在分析” if the network/API hangs.
    request.timeoutInterval = 20.0;

    NSURLSessionDataTask *task =
        [[NSURLSession sharedSession]
            dataTaskWithRequest:request
              completionHandler:^(NSData *data,
                                  NSURLResponse *response,
                                  NSError *error) {

        if (error) {
            JevHideLoadingAndShowAlert(
                @"Jev 网络错误",
                [NSString stringWithFormat:@"请求失败：\n%@",
                 error.localizedDescription]
            );
            return;
        }

        NSHTTPURLResponse *http =
            (NSHTTPURLResponse *)response;

        if (http.statusCode < 200 || http.statusCode >= 300) {
            NSString *serverError = JevServerErrorText(data);

            JevHideLoadingAndShowAlert(
                @"Jev API 错误",
                [NSString stringWithFormat:
                    @"HTTP %ld\n\n%@",
                    (long)http.statusCode,
                    serverError]
            );
            return;
        }

        NSError *parseError = nil;

        id json =
            [NSJSONSerialization JSONObjectWithData:data
                                            options:0
                                              error:&parseError];

        if (parseError || ![json isKindOfClass:[NSDictionary class]]) {
            JevHideLoadingAndShowAlert(
                @"Jev",
                [NSString stringWithFormat:
                    @"API 返回不是有效 JSON。\n\n%@",
                    JevServerErrorText(data)]
            );
            return;
        }

        NSDictionary *payload = (NSDictionary *)json;
        NSDictionary *answers = payload[@"answers"];

        if (![answers isKindOfClass:[NSDictionary class]]) {
            JevHideLoadingAndShowAlert(
                @"Jev 返回异常",
                [NSString stringWithFormat:
                    @"没有找到 answers。\n\n服务器返回：\n%@",
                    JevServerErrorText(data)]
            );
            return;
        }

        NSDictionary *intentAnswer = answers[@"intent"];
        NSDictionary *urgencyAnswer = answers[@"urgency"];
        NSDictionary *careAnswer = answers[@"needs_care"];

        NSString *intentText =
            JevFormatAnswer(intentAnswer);

        NSString *urgencyText =
            JevFormatAnswer(urgencyAnswer);

        NSString *careText =
            JevFormatAnswer(careAnswer);

        NSString *message =
            [NSString stringWithFormat:
                @"对话意图\n%@\n\n"
                 "紧急程度\n%@\n\n"
                 "是否需要谨慎\n%@",
                 intentText,
                 urgencyText,
                 careText];

        JevHideLoadingAndShowAlert(@"Jev 分析结果", message);
    }];

    [task resume];
}

#pragma mark - Controller

@interface JevController : NSObject
- (void)buttonTapped:(UIButton *)sender;
- (void)buttonLongPressed:(UILongPressGestureRecognizer *)gesture;
- (void)buttonDoubleTapped:(UITapGestureRecognizer *)gesture;
@end

@implementation JevController

- (void)buttonLongPressed:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;

    // Long press Jev to run an API-only test.
    // Triple tap is intentionally not used; use the API test first to isolate auth/network issues.
    JevTestAPIKey();
}

- (void)buttonDoubleTapped:(UITapGestureRecognizer *)gesture {
    JevAskForAPIKey();
}

- (void)buttonTapped:(UIButton *)sender {
    UIWindow *window = JevFindActiveWindow();

    if (!window) {
        JevShowAlert(@"Jev", @"没有找到当前微信窗口。");
        return;
    }

    NSString *state =
        JevVisibleConversationText(window);

    if (state.length < 5) {
        JevShowAlert(
            @"Jev",
            @"没有读取到足够的聊天文字。\n\n请先进入具体聊天窗口，再点击 Jev。"
        );
        return;
    }

    NSLog(@"[JevWeChatTweak] state:\n%@", state);

    NSString *apiKey =
        [[NSUserDefaults standardUserDefaults] stringForKey:kJevAPIKeyKey];

    // Do not put a loading alert underneath the API-key dialog.
    if (apiKey.length == 0) {
        JevAskForAPIKey();
        return;
    }

    JevShowLoading();
    JevCallAPIWithState(state);
}

@end

static JevController *gJevController;

#pragma mark - Button

static void JevInstallButton(void) {
    UIWindow *window = JevFindActiveWindow();

    if (!window) return;

    if ([window viewWithTag:kJevButtonTag]) {
        return;
    }

    if (!gJevController) {
        gJevController = [JevController new];
    }

    UIButton *button =
        [UIButton buttonWithType:UIButtonTypeSystem];

    button.tag = kJevButtonTag;

    button.frame =
        CGRectMake(
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

    [button setTitle:@"Jev"
            forState:UIControlStateNormal];

    [button setTitleColor:[UIColor whiteColor]
                 forState:UIControlStateNormal];

    button.layer.cornerRadius = 12.0;

    [button addTarget:gJevController
               action:@selector(buttonTapped:)
     forControlEvents:UIControlEventTouchUpInside];

    UILongPressGestureRecognizer *longPress =
        [[UILongPressGestureRecognizer alloc]
            initWithTarget:gJevController
                    action:@selector(buttonLongPressed:)];

    longPress.minimumPressDuration = 0.8;
    [button addGestureRecognizer:longPress];

    UITapGestureRecognizer *doubleTap =
        [[UITapGestureRecognizer alloc] initWithTarget:gJevController
                                                action:@selector(buttonDoubleTapped:)];
    doubleTap.numberOfTapsRequired = 2;
    [button addGestureRecognizer:doubleTap];

    [window addSubview:button];

    NSLog(@"[JevWeChatTweak] full version loaded");
}

#pragma mark - Constructor

%ctor {
    @autoreleasepool {

        [[NSNotificationCenter defaultCenter]
            addObserverForName:
                UIApplicationDidBecomeActiveNotification
                        object:nil
                         queue:
                [NSOperationQueue mainQueue]
                    usingBlock:
                ^(__unused NSNotification *notification) {

            dispatch_after(
                dispatch_time(
                    DISPATCH_TIME_NOW,
                    (int64_t)(1 * NSEC_PER_SEC)
                ),
                dispatch_get_main_queue(),
                ^{
                    JevInstallButton();
                }
            );
        }];

        [[NSNotificationCenter defaultCenter]
            addObserverForName:@"JevRunAnalysis"
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:
                ^(__unused NSNotification *notification) {

            UIWindow *window = JevFindActiveWindow();

            if (!window) {
                JevShowAlert(@"Jev", @"没有找到当前微信窗口。");
                return;
            }

            NSString *state =
                JevVisibleConversationText(window);

            if (state.length < 5) {
                JevShowAlert(
                    @"Jev",
                    @"没有读取到足够的聊天文字。"
                );
                return;
            }

            JevShowLoading();
            JevCallAPIWithState(state);
        }];
    }
}
