#import <UIKit/UIKit.h>

static NSString * const kJevAPIKeyKey = @"JevWeChatAPIKey";
static NSInteger const kJevButtonTag = 20260929;

#pragma mark - Window

static UIWindow *JevFindActiveWindow(void) {
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (scene.activationState != UISceneActivationStateForegroundActive) {
            continue;
        }

        if (![scene isKindOfClass:[UIWindowScene class]]) {
            continue;
        }

        UIWindowScene *windowScene = (UIWindowScene *)scene;

        for (UIWindow *window in windowScene.windows) {
            if (window.isKeyWindow) {
                return window;
            }
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
    if (!window) {
        return nil;
    }

    UIViewController *vc = window.rootViewController;

    if (!vc) {
        return nil;
    }

    while (vc.presentedViewController) {
        vc = vc.presentedViewController;
    }

    return vc;
}

#pragma mark - Visible Text

static void JevCollectText(UIView *view,
                           NSMutableArray<NSString *> *result) {
    if (!view) {
        return;
    }

    if ([view isKindOfClass:[UILabel class]]) {
        NSString *text = [(UILabel *)view text];

        if (text.length > 0) {
            [result addObject:text];
        }
    }
    else if ([view isKindOfClass:[UITextView class]]) {
        NSString *text = [(UITextView *)view text];

        if (text.length > 0) {
            [result addObject:text];
        }
    }
    else if ([view isKindOfClass:[UITextField class]]) {
        NSString *text = [(UITextField *)view text];

        if (text.length > 0) {
            [result addObject:text];
        }
    }

    for (UIView *subview in view.subviews) {
        JevCollectText(subview, result);
    }
}

static NSString *JevVisibleConversationText(UIWindow *window) {
    NSMutableArray<NSString *> *items =
        [NSMutableArray array];

    JevCollectText(window, items);

    NSMutableArray<NSString *> *clean =
        [NSMutableArray array];

    NSMutableSet<NSString *> *seen =
        [NSMutableSet set];

    for (NSString *raw in items) {

        NSString *text =
            [raw stringByTrimmingCharactersInSet:
                [NSCharacterSet whitespaceAndNewlineCharacterSet]];

        if (text.length < 2 ||
            text.length > 500) {
            continue;
        }

        if ([seen containsObject:text]) {
            continue;
        }

        [seen addObject:text];
        [clean addObject:text];
    }

    NSUInteger maxItems = 20;

    if (clean.count > maxItems) {
        clean =
            [[clean subarrayWithRange:
                NSMakeRange(clean.count - maxItems,
                            maxItems)] mutableCopy];
    }

    return [clean componentsJoinedByString:@"\n"];
}

#pragma mark - Alert

static void JevShowAlert(NSString *title,
                         NSString *message) {

    dispatch_async(dispatch_get_main_queue(), ^{

        UIWindow *window =
            JevFindActiveWindow();

        UIViewController *presenter =
            JevTopViewController(window);

        if (!presenter) {
            return;
        }

        UIAlertController *alert =
            [UIAlertController
                alertControllerWithTitle:title
                message:message ?: @""
                preferredStyle:UIAlertControllerStyleAlert];

        [alert addAction:
            [UIAlertAction
                actionWithTitle:@"确定"
                style:UIAlertActionStyleDefault
                handler:nil]];

        [presenter
            presentViewController:alert
            animated:YES
            completion:nil];
    });
}

#pragma mark - Loading

static void JevShowLoading(void) {

    dispatch_async(dispatch_get_main_queue(), ^{

        UIWindow *window =
            JevFindActiveWindow();

        UIViewController *presenter =
            JevTopViewController(window);

        if (!presenter) {
            return;
        }

        UIAlertController *alert =
            [UIAlertController
                alertControllerWithTitle:@"Jev"
                message:@"正在分析当前聊天……"
                preferredStyle:UIAlertControllerStyleAlert];

        alert.view.tag = 20260930;

        [presenter
            presentViewController:alert
            animated:YES
            completion:nil];
    });
}

static void JevHideLoading(void) {

    dispatch_async(dispatch_get_main_queue(), ^{

        UIWindow *window =
            JevFindActiveWindow();

        if (!window) {
            return;
        }

        UIViewController *vc =
            window.rootViewController;

        if (!vc) {
            return;
        }

        while (vc.presentedViewController) {

            UIViewController *next =
                vc.presentedViewController;

            if ([next isKindOfClass:
                    [UIAlertController class]] &&
                next.view.tag == 20260930) {

                [next
                    dismissViewControllerAnimated:NO
                    completion:nil];

                return;
            }

            vc = next;
        }
    });
}

#pragma mark - API Key
static void JevCallAPIWithState(NSString *state);
static void JevAskForAPIKey(void) {

    dispatch_async(dispatch_get_main_queue(), ^{

        UIWindow *window =
            JevFindActiveWindow();

        UIViewController *presenter =
            JevTopViewController(window);

        if (!presenter) {
            return;
        }

        UIAlertController *alert =
            [UIAlertController
                alertControllerWithTitle:@"Jev API Key"
                message:@"输入你的 Jev API Key。只保存在本机。"
                preferredStyle:UIAlertControllerStyleAlert];

        [alert addTextFieldWithConfigurationHandler:
            ^(UITextField *field) {

            field.placeholder = @"API Key";
            field.secureTextEntry = YES;
            field.clearButtonMode =
                UITextFieldViewModeWhileEditing;
        }];

        [alert addAction:
            [UIAlertAction
                actionWithTitle:@"取消"
                style:UIAlertActionStyleCancel
                handler:^(UIAlertAction *action) {

            JevHideLoading();
        }]];

        [alert addAction:
            [UIAlertAction
                actionWithTitle:@"保存并分析"
                style:UIAlertActionStyleDefault
                handler:^(UIAlertAction *action) {

            NSString *key =
                [alert.textFields.firstObject.text
                    stringByTrimmingCharactersInSet:
                    [NSCharacterSet
                        whitespaceAndNewlineCharacterSet]];

            if (key.length < 10) {

                JevShowAlert(
                    @"Jev",
                    @"API Key 看起来不正确。"
                );

                return;
            }

            [[NSUserDefaults standardUserDefaults]
                setObject:key
                forKey:kJevAPIKeyKey];

            [[NSUserDefaults standardUserDefaults]
                synchronize];

            /*
             等 API Key 弹窗关闭后，
             再启动 Loading。
             避免两个 UIAlertController 叠在一起。
             */

            dispatch_async(
                dispatch_get_main_queue(),
                ^{

                UIWindow *currentWindow =
                    JevFindActiveWindow();

                NSString *currentState =
                    JevVisibleConversationText(
                        currentWindow
                    );

                if (currentState.length < 5) {

                    JevShowAlert(
                        @"Jev",
                        @"API Key 已保存，但没有读取到足够的聊天文字。"
                    );

                    return;
                }

                JevShowLoading();

                JevCallAPIWithState(
                    currentState
                );
            });
        }]];

        [presenter
            presentViewController:alert
            animated:YES
            completion:nil];
    });
}

#pragma mark - Response Formatting

static NSString *JevFormatAnswer(
    NSDictionary *answer) {

    if (![answer isKindOfClass:
            [NSDictionary class]]) {

        return @"未返回有效结果";
    }

    NSString *type =
        answer[@"type"];

    if ([type isEqualToString:@"choice"]) {

        NSString *choice =
            answer[@"choice"];

        NSNumber *confidence =
            answer[@"confidence"];

        if (choice.length &&
            [confidence isKindOfClass:
                [NSNumber class]]) {

            return
                [NSString stringWithFormat:
                    @"选择：%@\n置信度：%.0f%%",
                    choice,
                    confidence.doubleValue * 100.0];
        }

        if (choice.length) {

            return
                [NSString stringWithFormat:
                    @"选择：%@",
                    choice];
        }
    }

    if ([type isEqualToString:@"score"]) {

        NSNumber *score =
            answer[@"score"];

        NSNumber *confidence =
            answer[@"confidence"];

        if ([score isKindOfClass:
                [NSNumber class]] &&
            [confidence isKindOfClass:
                [NSNumber class]]) {

            return
                [NSString stringWithFormat:
                    @"评分：%.2f\n置信度：%.0f%%",
                    score.doubleValue,
                    confidence.doubleValue * 100.0];
        }

        if ([score isKindOfClass:
                [NSNumber class]]) {

            return
                [NSString stringWithFormat:
                    @"评分：%.2f",
                    score.doubleValue];
        }
    }

    if ([type isEqualToString:@"noul"]) {

        NSNumber *noul =
            answer[@"noul"];

        if ([noul isKindOfClass:
                [NSNumber class]]) {

            return
                [NSString stringWithFormat:
                    @"概率：%.0f%%",
                    noul.doubleValue * 100.0];
        }
    }

    return
        [NSString stringWithFormat:@"%@", answer];
}

static NSString *JevServerErrorText(NSData *data) {

    if (!data.length) {
        return @"服务器没有返回错误详情。";
    }

    NSString *text =
        [[NSString alloc]
            initWithData:data
            encoding:NSUTF8StringEncoding];

    if (text.length > 1500) {
        text =
            [text substringToIndex:1500];
    }

    return text.length
        ? text
        : @"服务器返回了无法显示的错误内容。";
}

#pragma mark - API

static void JevCallAPIWithState(NSString *state) {

    NSString *apiKey =
        [[NSUserDefaults standardUserDefaults]
            stringForKey:kJevAPIKeyKey];

    /*
     如果没有 Key，直接进入 Key 输入流程。
     不显示 Loading。
     */

    if (apiKey.length == 0) {

        JevAskForAPIKey();

        return;
    }

    NSDictionary *body = @{

        @"model": @"jev-latest",

        @"state": state ?: @"",

        @"questions": @{

            @"intent": @{

                @"type": @"choice",

                @"instructions":
                    @"Classify the main intent of the visible conversation from the user's perspective.",

                @"criteria": @{

                    @"question":
                        @"The other person is mainly asking a question or seeking information.",

                    @"request":
                        @"The other person is asking the user to do something.",

                    @"social":
                        @"The conversation is mainly casual, social, or relational.",

                    @"conflict":
                        @"The conversation contains disagreement, tension, complaint, or conflict.",

                    @"planning":
                        @"The conversation is mainly about plans, timing, or logistics.",

                    @"other":
                        @"None of the above clearly applies."
                }
            },

            @"urgency": @{

                @"type": @"score",

                @"instructions":
                    @"Rate how urgent the situation conveyed by the visible conversation is.",

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

                @"instructions":
                    @"Does this conversation require extra care before replying because a careless response could worsen the situation?",

                @"criteria": @{

                    @"true":
                        @"A careless reply could reasonably worsen the situation.",

                    @"false":
                        @"A normal reply is unlikely to worsen the situation."
                }
            }
        }
    };

    NSError *jsonError = nil;

    NSData *jsonData =
        [NSJSONSerialization
            dataWithJSONObject:body
            options:0
            error:&jsonError];

    if (!jsonData || jsonError) {

        JevHideLoading();

        JevShowAlert(
            @"Jev",
            @"请求数据生成失败。"
        );

        return;
    }

    NSURL *url =
        [NSURL URLWithString:
            @"https://thejevai.com/v1/systemone"];

    NSMutableURLRequest *request =
        [NSMutableURLRequest requestWithURL:url];

    request.HTTPMethod = @"POST";

    [request setValue:
        [NSString stringWithFormat:
            @"Bearer %@",
            apiKey]
        forHTTPHeaderField:@"Authorization"];

    [request setValue:
        @"application/json"
        forHTTPHeaderField:@"Content-Type"];

    request.HTTPBody =
        jsonData;

    NSURLSessionDataTask *task =
        [[NSURLSession sharedSession]
            dataTaskWithRequest:request
            completionHandler:
            ^(NSData *data,
              NSURLResponse *response,
              NSError *error) {

        if (error) {

            JevHideLoading();

            JevShowAlert(
                @"Jev 网络错误",
                [NSString stringWithFormat:
                    @"请求失败：\n%@",
                    error.localizedDescription]
            );

            return;
        }

        NSHTTPURLResponse *http =
            (NSHTTPURLResponse *)response;

        if (http.statusCode < 200 ||
            http.statusCode >= 300) {

            JevHideLoading();

            JevShowAlert(
                @"Jev API 错误",
                [NSString stringWithFormat:
                    @"HTTP %ld\n\n%@",
                    (long)http.statusCode,
                    JevServerErrorText(data)]
            );

            return;
        }

        NSError *parseError = nil;

        id json =
            [NSJSONSerialization
                JSONObjectWithData:data
                options:0
                error:&parseError];

        if (parseError ||
            ![json isKindOfClass:
                [NSDictionary class]]) {

            JevHideLoading();

            JevShowAlert(
                @"Jev",
                @"API 返回不是有效 JSON。"
            );

            return;
        }

        NSDictionary *payload =
            (NSDictionary *)json;

        NSDictionary *answers =
            payload[@"answers"];

        if (![answers isKindOfClass:
                [NSDictionary class]]) {

            JevHideLoading();

            JevShowAlert(
                @"Jev 返回异常",
                [NSString stringWithFormat:
                    @"没有找到 answers。\n\n服务器返回：\n%@",
                    JevServerErrorText(data)]
            );

            return;
        }

        NSString *intent =
            JevFormatAnswer(
                answers[@"intent"]
            );

        NSString *urgency =
            JevFormatAnswer(
                answers[@"urgency"]
            );

        NSString *care =
            JevFormatAnswer(
                answers[@"needs_care"]
            );

        NSString *message =
            [NSString stringWithFormat:

                @"对话意图\n%@\n\n"
                 "紧急程度\n%@\n\n"
                 "是否需要谨慎\n%@",

                intent,

                urgency,

                care
            ];

        JevHideLoading();

        JevShowAlert(
            @"Jev 分析结果",
            message
        );
    }];

    [task resume];
}

#pragma mark - Controller

@interface JevController : NSObject

- (void)buttonTapped:(UIButton *)sender;

@end

@implementation JevController

- (void)buttonTapped:(UIButton *)sender {

    UIWindow *window =
        JevFindActiveWindow();

    if (!window) {

        JevShowAlert(
            @"Jev",
            @"没有找到当前微信窗口。"
        );

        return;
    }

    NSString *state =
        JevVisibleConversationText(
            window
        );

    if (state.length < 5) {

        JevShowAlert(
            @"Jev",
            @"没有读取到足够的聊天文字。\n\n请先进入具体聊天窗口，再点击 Jev。"
        );

        return;
    }

    NSLog(
        @"[JevWeChatTweak] state:\n%@",
        state
    );

    /*
     关键修复：
     先检查 API Key。
     没有 Key 时绝对不能先显示 Loading。
     */

    NSString *apiKey =
        [[NSUserDefaults standardUserDefaults]
            stringForKey:kJevAPIKeyKey];

    if (apiKey.length == 0) {

        JevAskForAPIKey();

        return;
    }

    JevShowLoading();

    JevCallAPIWithState(
        state
    );
}

@end

static JevController *gJevController;

#pragma mark - Button

static void JevInstallButton(void) {

    UIWindow *window =
        JevFindActiveWindow();

    if (!window) {
        return;
    }

    if ([window viewWithTag:kJevButtonTag]) {
        return;
    }

    if (!gJevController) {
        gJevController =
            [JevController new];
    }

    UIButton *button =
        [UIButton buttonWithType:
            UIButtonTypeSystem];

    button.tag =
        kJevButtonTag;

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
        [UIColor colorWithWhite:
            0.08
            alpha:0.92];

    [button setTitle:
        @"Jev"
        forState:UIControlStateNormal];

    [button setTitleColor:
        [UIColor whiteColor]
        forState:UIControlStateNormal];

    button.layer.cornerRadius =
        12.0;

    [button addTarget:
        gJevController
        action:@selector(buttonTapped:)
        forControlEvents:
            UIControlEventTouchUpInside];

    [window addSubview:button];

    NSLog(
        @"[JevWeChatTweak] full version loaded"
    );
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
                        (int64_t)
                            (1 * NSEC_PER_SEC)
                    ),

                    dispatch_get_main_queue(),

                    ^{

                        JevInstallButton();
                    }
                );
            }
        ];

        /*
         保留这个通知作为兼容流程。
         */

        [[NSNotificationCenter defaultCenter]

            addObserverForName:
                @"JevRunAnalysis"

            object:nil

            queue:
                [NSOperationQueue mainQueue]

            usingBlock:
            ^(__unused NSNotification *notification) {

                UIWindow *window =
                    JevFindActiveWindow();

                if (!window) {

                    JevShowAlert(
                        @"Jev",
                        @"没有找到当前微信窗口。"
                    );

                    return;
                }

                NSString *state =
                    JevVisibleConversationText(
                        window
                    );

                if (state.length < 5) {

                    JevShowAlert(
                        @"Jev",
                        @"没有读取到足够的聊天文字。"
                    );

                    return;
                }

                NSString *apiKey =
                    [[NSUserDefaults standardUserDefaults]
                        stringForKey:kJevAPIKeyKey];

                if (apiKey.length == 0) {

                    JevAskForAPIKey();

                    return;
                }

                JevShowLoading();

                JevCallAPIWithState(
                    state
                );
            }
        ];
    }
}
