
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

static NSString * const kJevAPIKeyKey = @"JevWeChatAPIKey";
static NSInteger const kJevButtonTag = 20260929;
static NSInteger const kJevOverlayTag = 20260931;
static NSString * const kJevEndpoint = @"https://api.typesafe.ai/v1/systemone";

#pragma mark - Window / Presentation

static UIWindow *JevFindActiveWindow(void) {
    UIApplication *app = UIApplication.sharedApplication;
    UIWindow *fallback = nil;

    for (UIScene *scene in app.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        UIWindowScene *ws = (UIWindowScene *)scene;

        for (UIWindow *window in ws.windows) {
            if (window.hidden || window.alpha < 0.01 || window.windowLevel != UIWindowLevelNormal) continue;
            if (window.isKeyWindow) return window;
            if (!fallback && window.rootViewController) fallback = window;
        }
    }
    return fallback;
}

static UIViewController *JevTopViewController(void) {
    UIWindow *window = JevFindActiveWindow();
    UIViewController *vc = window.rootViewController;
    if (!vc) return nil;

    while (YES) {
        UIViewController *next = nil;
        if (vc.presentedViewController) next = vc.presentedViewController;
        else if ([vc isKindOfClass:[UINavigationController class]]) next = [(UINavigationController *)vc visibleViewController];
        else if ([vc isKindOfClass:[UITabBarController class]]) next = [(UITabBarController *)vc selectedViewController];

        if (!next || next == vc) break;
        vc = next;
    }
    return vc;
}

#pragma mark - Text extraction

static void JevCollectText(UIView *view, NSMutableArray<NSString *> *items) {
    if (!view || items.count >= 80) return;

    if ([view isKindOfClass:[UILabel class]]) {
        NSString *s = ((UILabel *)view).text;
        if (s.length) [items addObject:s];
    } else if ([view isKindOfClass:[UITextView class]]) {
        NSString *s = ((UITextView *)view).text;
        if (s.length) [items addObject:s];
    } else if ([view isKindOfClass:[UITextField class]]) {
        NSString *s = ((UITextField *)view).text;
        if (s.length) [items addObject:s];
    }

    for (UIView *subview in view.subviews) {
        JevCollectText(subview, items);
        if (items.count >= 80) break;
    }
}

static NSString *JevVisibleConversationText(UIWindow *window) {
    if (!window) return @"";

    NSMutableArray<NSString *> *items = [NSMutableArray array];
    JevCollectText(window, items);

    NSMutableArray<NSString *> *clean = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];

    for (NSString *raw in items) {
        NSString *s = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (s.length < 2 || s.length > 800) continue;
        if ([seen containsObject:s]) continue;
        [seen addObject:s];
        [clean addObject:s];
    }

    // Avoid sending a giant amount of unrelated WeChat UI text.
    if (clean.count > 30) {
        clean = [[clean subarrayWithRange:NSMakeRange(clean.count - 30, 30)] mutableCopy];
    }

    return [clean componentsJoinedByString:@"\n"];
}

#pragma mark - API Key

static NSString *JevNormalizedAPIKey(NSString *raw) {
    NSString *key = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([key.lowercaseString hasPrefix:@"bearer "]) {
        key = [key substringFromIndex:7];
        key = [key stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }
    return key;
}

static NSString *JevCurrentAPIKey(void) {
    NSString *key = [[NSUserDefaults standardUserDefaults] stringForKey:kJevAPIKeyKey];
    return JevNormalizedAPIKey(key ?: @"");
}

static void JevSaveAPIKey(NSString *raw) {
    NSString *key = JevNormalizedAPIKey(raw);
    if (key.length) {
        [[NSUserDefaults standardUserDefaults] setObject:key forKey:kJevAPIKeyKey];
    } else {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:kJevAPIKeyKey];
    }
    [[NSUserDefaults standardUserDefaults] synchronize];
}

#pragma mark - Result Overlay

@interface JevOverlayCloser : NSObject
+ (instancetype)shared;
- (void)close:(id)sender;
@end

static void JevRemoveOverlay(void);

static void JevShowOverlay(NSString *title, NSString *message, BOOL loading) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = JevFindActiveWindow();
        if (!window) return;

        JevRemoveOverlay();

        UIView *overlay = [[UIView alloc] initWithFrame:window.bounds];
        overlay.tag = kJevOverlayTag;
        overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        overlay.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.10];

        CGFloat width = MIN(window.bounds.size.width - 36.0, 390.0);
        UIView *panel = [[UIView alloc] initWithFrame:CGRectMake((window.bounds.size.width-width)/2.0,
                                                                  100.0,
                                                                  width,
                                                                  260.0)];
        panel.backgroundColor = [UIColor systemBackgroundColor];
        panel.layer.cornerRadius = 16.0;
        panel.layer.shadowColor = [UIColor blackColor].CGColor;
        panel.layer.shadowOpacity = 0.18;
        panel.layer.shadowRadius = 16.0;
        panel.layer.shadowOffset = CGSizeMake(0, 6);
        panel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
        [overlay addSubview:panel];

        UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(18, 14, width-64, 28)];
        titleLabel.text = title ?: @"Jev";
        titleLabel.font = [UIFont boldSystemFontOfSize:18];
        titleLabel.textColor = [UIColor labelColor];
        [panel addSubview:titleLabel];

        UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
        close.frame = CGRectMake(width-48, 10, 38, 38);
        close.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
        [close setTitle:@"×" forState:UIControlStateNormal];
        close.titleLabel.font = [UIFont systemFontOfSize:28 weight:UIFontWeightRegular];
        [close addTarget:[JevOverlayCloser shared] action:@selector(close:) forControlEvents:UIControlEventTouchUpInside];
        [panel addSubview:close];

        UITextView *text = [[UITextView alloc] initWithFrame:CGRectMake(14, 50, width-28, 175)];
        text.editable = NO;
        text.selectable = YES;
        text.backgroundColor = UIColor.clearColor;
        text.font = [UIFont systemFontOfSize:15];
        text.textColor = [UIColor labelColor];
        text.text = message ?: @"";
        text.textContainerInset = UIEdgeInsetsMake(8, 6, 8, 6);
        [panel addSubview:text];

        UIButton *bottomClose = [UIButton buttonWithType:UIButtonTypeSystem];
        bottomClose.frame = CGRectMake(18, 222, width-36, 30);
        [bottomClose setTitle:@"轻点关闭" forState:UIControlStateNormal];
        [bottomClose addTarget:[JevOverlayCloser shared] action:@selector(close:) forControlEvents:UIControlEventTouchUpInside];
        [panel addSubview:bottomClose];

        [window addSubview:overlay];
    });
}

@implementation JevOverlayCloser
+ (instancetype)shared {
    static JevOverlayCloser *obj;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ obj = [JevOverlayCloser new]; });
    return obj;
}
- (void)close:(id)sender {
    JevRemoveOverlay();
}
@end

static void JevRemoveOverlay(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = JevFindActiveWindow();
        UIView *overlay = [window viewWithTag:kJevOverlayTag];
        [overlay removeFromSuperview];
    });
}

#pragma mark - API error / formatting

static NSString *JevStringFromJSON(id obj) {
    if (!obj) return @"";
    if ([obj isKindOfClass:[NSString class]]) return obj;
    if ([obj isKindOfClass:[NSNumber class]]) return [obj description];

    if ([NSJSONSerialization isValidJSONObject:obj]) {
        NSData *data = [NSJSONSerialization dataWithJSONObject:obj options:NSJSONWritingPrettyPrinted error:nil];
        NSString *s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (s.length) return s;
    }
    return [obj description];
}

static NSString *JevHTTPMessage(NSHTTPURLResponse *response, NSData *data) {
    NSString *body = data.length ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"";
    if (body.length > 1800) body = [body substringToIndex:1800];

    if (body.length) {
        id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (json) body = JevStringFromJSON(json);
    }

    return [NSString stringWithFormat:@"HTTP %ld\n\n%@", (long)response.statusCode,
            body.length ? body : @"服务器没有返回正文"];
}

static NSString *JevFormatAnswer(NSString *name, NSDictionary *answer) {
    if (![answer isKindOfClass:[NSDictionary class]]) {
        return [NSString stringWithFormat:@"%@：%@", name, JevStringFromJSON(answer)];
    }

    NSString *type = [answer[@"type"] isKindOfClass:[NSString class]] ? answer[@"type"] : @"";

    if ([type isEqualToString:@"choice"]) {
        NSString *choice = [answer[@"choice"] isKindOfClass:[NSString class]] ? answer[@"choice"] : @"";
        NSNumber *confidence = answer[@"confidence"];
        if (choice.length && [confidence isKindOfClass:[NSNumber class]]) {
            return [NSString stringWithFormat:@"%@：%@\n置信度：%.0f%%",
                    name, choice, confidence.doubleValue * 100.0];
        }
        if (choice.length) return [NSString stringWithFormat:@"%@：%@", name, choice];
    }

    if ([type isEqualToString:@"score"]) {
        id score = answer[@"score"];
        NSNumber *confidence = answer[@"confidence"];
        if ([score isKindOfClass:[NSNumber class]]) {
            if ([confidence isKindOfClass:[NSNumber class]]) {
                return [NSString stringWithFormat:@"%@：%.2f\n置信度：%.0f%%",
                        name, [score doubleValue], confidence.doubleValue * 100.0];
            }
            return [NSString stringWithFormat:@"%@：%.2f", name, [score doubleValue]];
        }
    }

    if ([type isEqualToString:@"noul"]) {
        NSNumber *noul = answer[@"noul"];
        if ([noul isKindOfClass:[NSNumber class]]) {
            return [NSString stringWithFormat:@"%@：%.0f%%", name, noul.doubleValue * 100.0];
        }
    }

    return [NSString stringWithFormat:@"%@：%@", name, JevStringFromJSON(answer)];
}

#pragma mark - API request

static void JevCallAPI(NSString *state, BOOL isTest) {
    NSString *apiKey = JevCurrentAPIKey();

    if (apiKey.length < 10) {
        JevShowOverlay(@"Jev", @"还没有有效的 API Key。\n\n请长按 Jev → 修改 API Key。", NO);
        return;
    }

    NSDictionary *questions;

    if (isTest) {
        questions = @{
            @"test": @{
                @"type": @"noul",
                @"instructions": @"这是一条 API 连通性测试。请判断这句话是否表达了紧迫性。",
                @"criteria": @{
                    @"true": @"明确表达需要立即处理",
                    @"false": @"没有表达紧迫性"
                }
            }
        };
        state = @"这是一次 Jev API 连通性测试，没有任何紧急事项。";
    } else {
        questions = @{
            @"intent": @{
                @"type": @"choice",
                @"instructions": @"判断这段聊天的主要意图。",
                @"criteria": @{
                    @"buy": @"明确准备购买、下单或接受购买安排",
                    @"ask": @"主要是在询问信息、价格、时间或细节",
                    @"discuss": @"主要是在讨论、比较、协商或表达意见",
                    @"other": @"不属于以上情况"
                }
            },
            @"urgency": @{
                @"type": @"score",
                @"instructions": @"判断这段聊天表达的紧迫程度。",
                @"criteria": @[
                    @"不紧急",
                    @"一般紧急",
                    @"比较紧急",
                    @"非常紧急"
                ]
            },
            @"needs_care": @{
                @"type": @"noul",
                @"instructions": @"这段聊天是否需要谨慎处理，避免草率回复？",
                @"criteria": @{
                    @"true": @"存在歧义、敏感表达、明显冲突或回复失误风险",
                    @"false": @"普通、明确、低风险对话"
                }
            }
        };
    }

    NSDictionary *body = @{
        @"model": @"jev-latest",
        @"state": state ?: @"",
        @"questions": questions
    };

    NSError *jsonError = nil;
    NSData *bodyData = [NSJSONSerialization dataWithJSONObject:body options:0 error:&jsonError];

    if (!bodyData) {
        JevShowOverlay(@"Jev API 错误", jsonError.localizedDescription ?: @"无法生成请求", NO);
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:kJevEndpoint]
                                                            cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                        timeoutInterval:20.0];

    request.HTTPMethod = @"POST";
    request.HTTPBody = bodyData;
    [request setValue:[NSString stringWithFormat:@"Bearer %@", apiKey] forHTTPHeaderField:@"Authorization"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];

    NSLog(@"[JevWeChatTweak] POST TypeSafe System One, test=%d, state=%lu chars",
          isTest, (unsigned long)state.length);

    JevShowOverlay(isTest ? @"测试 Jev API" : @"正在分析当前聊天……",
                   @"请求已经发送。\n\n等待 Jev 返回结果……", YES);

    [[[NSURLSession sharedSession] dataTaskWithRequest:request
                                     completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {

        if (error) {
            NSString *message = [NSString stringWithFormat:@"网络请求失败\n\n%@\n\n请检查网络/VPN，并确认 api.typesafe.ai 可以访问。",
                                 error.localizedDescription ?: @"未知网络错误"];
            JevShowOverlay(@"Jev API 测试失败", message, NO);
            return;
        }

        NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;

        if (http.statusCode < 200 || http.statusCode >= 300) {
            NSString *message = JevHTTPMessage(http, data);
            JevShowOverlay(isTest ? @"TypeSafe Key 测试失败" : @"Jev 分析失败", message, NO);
            return;
        }

        NSError *parseError = nil;
        id json = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError] : nil;

        if (!json) {
            NSString *raw = data.length ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"";
            if (raw.length > 1800) raw = [raw substringToIndex:1800];
            JevShowOverlay(@"Jev 返回异常",
                           [NSString stringWithFormat:@"HTTP %ld\n\n无法解析 JSON。\n\n%@",
                            (long)http.statusCode, raw.length ? raw : @"空响应"], NO);
            return;
        }

        if (isTest) {
            NSString *pretty = JevStringFromJSON(json);
            if (pretty.length > 1800) pretty = [pretty substringToIndex:1800];
            JevShowOverlay(@"TypeSafe API 测试成功",
                           [NSString stringWithFormat:@"HTTP %ld\n\nKey：已通过认证\n模型：jev-latest\nEndpoint：api.typesafe.ai\n\n返回：\n%@",
                            (long)http.statusCode, pretty], NO);
            return;
        }

        NSDictionary *dict = [json isKindOfClass:[NSDictionary class]] ? json : nil;
        NSDictionary *answers = [dict[@"answers"] isKindOfClass:[NSDictionary class]] ? dict[@"answers"] : nil;

        if (!answers) {
            NSString *pretty = JevStringFromJSON(json);
            if (pretty.length > 1800) pretty = [pretty substringToIndex:1800];
            JevShowOverlay(@"Jev 返回异常",
                           [NSString stringWithFormat:@"HTTP %ld\n\n响应中没有找到 answers。\n\n%@",
                            (long)http.statusCode, pretty], NO);
            return;
        }

        NSMutableArray<NSString *> *lines = [NSMutableArray array];

        NSDictionary *intent = [answers[@"intent"] isKindOfClass:[NSDictionary class]] ? answers[@"intent"] : nil;
        NSDictionary *urgency = [answers[@"urgency"] isKindOfClass:[NSDictionary class]] ? answers[@"urgency"] : nil;
        NSDictionary *care = [answers[@"needs_care"] isKindOfClass:[NSDictionary class]] ? answers[@"needs_care"] : nil;

        if (intent) [lines addObject:JevFormatAnswer(@"对话意图", intent)];
        if (urgency) [lines addObject:JevFormatAnswer(@"紧急程度", urgency)];
        if (care) [lines addObject:JevFormatAnswer(@"是否需要谨慎", care)];

        if (lines.count == 0) {
            for (NSString *key in answers) {
                [lines addObject:JevFormatAnswer(key, answers[key])];
            }
        }

        NSString *result = [lines componentsJoinedByString:@"\n\n"];
        if (!result.length) result = JevStringFromJSON(json);

        JevShowOverlay(@"Jev 分析结果",
                       [NSString stringWithFormat:@"%@\n\n轻点关闭", result], NO);
    }] resume];
}

#pragma mark - Key dialog / menu

static void JevShowKeyEditor(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *presenter = JevTopViewController();
        if (!presenter) return;

        UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"Jev API Key"
                                            message:@"请输入 TypeSafe 直连 API Key。\n只保存到本机，不写入 GitHub。"
                                     preferredStyle:UIAlertControllerStyleAlert];

        [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
            field.placeholder = @"apikey_...";
            field.secureTextEntry = YES;
            field.clearButtonMode = UITextFieldViewModeWhileEditing;
            NSString *current = JevCurrentAPIKey();
            if (current.length) field.text = current;
        }];

        [alert addAction:[UIAlertAction actionWithTitle:@"取消"
                                                  style:UIAlertActionStyleCancel
                                                handler:nil]];

        [alert addAction:[UIAlertAction actionWithTitle:@"保存"
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *action) {
            NSString *key = JevNormalizedAPIKey(alert.textFields.firstObject.text ?: @"");
            if (key.length < 10) {
                JevShowOverlay(@"Jev", @"API Key 太短，请检查是否完整复制。", NO);
                return;
            }
            JevSaveAPIKey(key);
            JevShowOverlay(@"Jev", @"API Key 已保存。\n\n现在可以长按 Jev → 测试 API Key。", NO);
        }]];

        [presenter presentViewController:alert animated:YES completion:nil];
    });
}

static void JevShowLongPressMenu(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *presenter = JevTopViewController();
        if (!presenter) return;

        UIAlertController *menu =
        [UIAlertController alertControllerWithTitle:@"Jev"
                                            message:@"选择操作"
                                     preferredStyle:UIAlertControllerStyleActionSheet];

        [menu addAction:[UIAlertAction actionWithTitle:@"测试 API Key"
                                                 style:UIAlertActionStyleDefault
                                               handler:^(UIAlertAction *action) {
            JevCallAPI(@"", YES);
        }]];

        [menu addAction:[UIAlertAction actionWithTitle:@"修改 API Key"
                                                 style:UIAlertActionStyleDefault
                                               handler:^(UIAlertAction *action) {
            JevShowKeyEditor();
        }]];

        [menu addAction:[UIAlertAction actionWithTitle:@"清除 API Key"
                                                 style:UIAlertActionStyleDestructive
                                               handler:^(UIAlertAction *action) {
            JevSaveAPIKey(@"");
            JevShowOverlay(@"Jev", @"API Key 已清除。", NO);
        }]];

        [menu addAction:[UIAlertAction actionWithTitle:@"取消"
                                                 style:UIAlertActionStyleCancel
                                               handler:nil]];

        if (menu.popoverPresentationController) {
            menu.popoverPresentationController.sourceView = presenter.view;
            menu.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(presenter.view.bounds),
                                                                        CGRectGetMinY(presenter.view.bounds) + 100,
                                                                        1, 1);
        }

        [presenter presentViewController:menu animated:YES completion:nil];
    });
}

#pragma mark - Controller

@interface JevController : NSObject
- (void)buttonTapped:(UIButton *)sender;
- (void)longPressed:(UILongPressGestureRecognizer *)gesture;
@end

@implementation JevController

- (void)buttonTapped:(UIButton *)sender {
    UIWindow *window = JevFindActiveWindow();
    if (!window) return;

    NSString *key = JevCurrentAPIKey();
    if (key.length < 10) {
        JevShowKeyEditor();
        return;
    }

    NSString *state = JevVisibleConversationText(window);
    if (state.length < 5) {
        JevShowOverlay(@"Jev", @"没有读取到足够的聊天文字。\n\n请进入具体聊天窗口后再点击 Jev。", NO);
        return;
    }

    JevCallAPI(state, NO);
}

- (void)longPressed:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        JevShowLongPressMenu();
    }
}

@end

static JevController *gJevController;

static void JevInstallButton(void) {
    UIWindow *window = JevFindActiveWindow();
    if (!window) return;
    if ([window viewWithTag:kJevButtonTag]) return;

    if (!gJevController) gJevController = [JevController new];

    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.tag = kJevButtonTag;

    button.frame = CGRectMake(window.bounds.size.width - 86.0,
                              window.safeAreaInsets.top + 20.0,
                              66.0,
                              40.0);

    button.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleBottomMargin;
    button.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.92];
    [button setTitle:@"Jev" forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    button.layer.cornerRadius = 12.0;

    [button addTarget:gJevController
               action:@selector(buttonTapped:)
     forControlEvents:UIControlEventTouchUpInside];

    UILongPressGestureRecognizer *longPress =
        [[UILongPressGestureRecognizer alloc] initWithTarget:gJevController
                                                      action:@selector(longPressed:)];
    longPress.minimumPressDuration = 0.8;
    [button addGestureRecognizer:longPress];

    [window addSubview:button];

    NSLog(@"[JevWeChatTweak] FINAL TypeSafe version loaded");
}

%ctor {
    @autoreleasepool {
        dispatch_async(dispatch_get_main_queue(), ^{
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                JevInstallButton();
            });
        });

        [[NSNotificationCenter defaultCenter]
            addObserverForName:UIApplicationDidBecomeActiveNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(__unused NSNotification *notification) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                JevInstallButton();
            });
        }];
    }
}
