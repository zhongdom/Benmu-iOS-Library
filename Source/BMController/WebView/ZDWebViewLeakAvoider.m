//
//  ZDWebViewLeakAvoider.m
//  AFNetworking
//
//  Created by zhongdong on 2019/5/28.
//

#import "ZDWebViewLeakAvoider.h"

@implementation ZDWebViewLeakAvoider

- (instancetype)initWithDelegate:(id<WKScriptMessageHandler>)scriptDelegate{
    self = [super init];
    if (self) {
        _scriptDelegate = scriptDelegate;
    }
    return self;
}

- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message{
    [self.scriptDelegate userContentController:userContentController didReceiveScriptMessage:message];
}


@end
