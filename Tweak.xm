#import <UIKit/UIKit.h>

@interface JevTestButtonController : NSObject
@end

@implementation JevTestButtonController

- (UIWindow *)activeWindow {
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState != UISceneActivationStateForegroundActive ||
                ![scene isKindOfClass:[UIWindowScene class]]) continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                if (window.isKeyWindow) return window;
            }
        }
    }
    for (UIWindow *window in [UIApplication sharedApplication].windows) {
        if (window.isKeyWindow) return window;
    }
    return nil;
}

- (void)jev_buttonTapped:(UIButton *)sender {
    UIWindow *window = [self activeWindow];
    UIViewController *presenter = window.rootViewController;
    while (presenter.presentedViewController) presenter = presenter.presentedViewController;

    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"Jev"
                                            message:@"JevWeChatTweak 注入成功"
                                     preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定"
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
    [presenter presentViewController:alert animated:YES completion:nil];
}

@end

static JevTestButtonController *gJevController;

static void JevInstallTestButton(void) {
    UIWindow *window = nil;

    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState != UISceneActivationStateForegroundActive ||
                ![scene isKindOfClass:[UIWindowScene class]]) continue;
            for (UIWindow *candidate in ((UIWindowScene *)scene).windows) {
                if (candidate.isKeyWindow) {
                    window = candidate;
                    break;
                }
            }
            if (window) break;
        }
    }

    if (!window) {
        for (UIWindow *candidate in [UIApplication sharedApplication].windows) {
            if (candidate.isKeyWindow) {
                window = candidate;
                break;
            }
        }
    }

    if (!window || [window viewWithTag:20260929]) return;

    gJevController = [JevTestButtonController new];

    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.tag = 20260929;
    button.frame = CGRectMake(window.bounds.size.width - 86.0,
                              window.safeAreaInsets.top + 20.0,
                              66.0, 40.0);
    button.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin |
                              UIViewAutoresizingFlexibleBottomMargin;
    button.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.92];
    [button setTitle:@"Jev" forState:UIControlStateNormal];
    [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    button.layer.cornerRadius = 12.0;
    [button addTarget:gJevController
               action:@selector(jev_buttonTapped:)
     forControlEvents:UIControlEventTouchUpInside];

    [window addSubview:button];
    NSLog(@"[JevWeChatTweak] injection successful");
}

%ctor {
    @autoreleasepool {
        [[NSNotificationCenter defaultCenter]
            addObserverForName:UIApplicationDidBecomeActiveNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(__unused NSNotification *notification) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                JevInstallTestButton();
            });
        }];
    }
}
