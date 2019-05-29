//
//  ZDWKWebViewController.m
//  AFNetworking
//
//  Created by zhongdong on 2019/5/28.
//

#import "ZDWKWebViewController.h"
#import <Masonry/Masonry.h>
#import <WebKit/WebKit.h>
#import "UIColor+Util.h"
#import "CommonMacro.h"
#import "BMDefine.h"
#import "NSString+Util.h"
#import "UIView+Util.h"
#import "UINavigationController+FDFullscreenPopGesture.h"
#import "NSTimer+Addition.h"
#import "ZDWebViewLeakAvoider.h"
#import "BMNotifactionCenter.h"

@interface ZDWKWebViewController ()<WKUIDelegate, WKNavigationDelegate, WKScriptMessageHandler>

@property (nonatomic, assign) BOOL showProgress;

@property (nonatomic, strong) WKWebView *webView;

@property (nonatomic, copy) NSString *urlStr;

/** 伪进度条 */
@property (nonatomic, strong) CAShapeLayer *progressLayer;
/** 进度条定时器 */
@property (nonatomic, strong) NSTimer *timer;

@end

@implementation ZDWKWebViewController

- (CAShapeLayer *)progressLayer{
    if (!_progressLayer) {
        UIBezierPath *path = [[UIBezierPath alloc] init];
        [path moveToPoint:CGPointMake(0, self.navigationController.navigationBar.height - 2)];
        [path addLineToPoint:CGPointMake(K_SCREEN_WIDTH, self.navigationController.navigationBar.height - 2)];
        _progressLayer = [CAShapeLayer layer];
        _progressLayer.path = path.CGPath;
        _progressLayer.strokeColor =  [UIColor lightGrayColor].CGColor;
        _progressLayer.fillColor = K_CLEAR_COLOR.CGColor;
        _progressLayer.lineWidth = 2;
        
        _progressLayer.strokeStart = 0.0f;
        _progressLayer.strokeEnd = 0.0f;
        
        [self.navigationController.navigationBar.layer addSublayer:_progressLayer];
    }
    return _progressLayer;
}

- (instancetype)initWithRouterModel:(BMWebViewRouterModel *)model {
    if (self = [super init]) {
        self.routerInfo = model;
        [self subInit];
    }
    return self;
    
}

- (void)subInit {
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    ZDWebViewLeakAvoider *avoidDlegate = [[ZDWebViewLeakAvoider alloc] initWithDelegate:self];
    // 注入原生暴露给JS调用的方法
    [config.userContentController addScriptMessageHandler:avoidDlegate name:@"closePage"];
    [config.userContentController addScriptMessageHandler:avoidDlegate name:@"fireEvent"];
    
    self.webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:config];
    self.webView.backgroundColor = self.routerInfo.backgroundColor? [UIColor colorWithHexString:self.routerInfo.backgroundColor]: K_BACKGROUND_COLOR;
    self.webView.scrollView.bounces = NO;
    self.webView.UIDelegate = self;
    self.webView.navigationDelegate = self;
    self.view.backgroundColor = self.routerInfo.backgroundColor? [UIColor colorWithHexString:self.routerInfo.backgroundColor]: K_BACKGROUND_COLOR;
    [self.view addSubview:self.webView];
    [self.webView mas_makeConstraints:^(MASConstraintMaker *make) {
        if (@available(iOS 11.0, *)) {
            make.edges.mas_offset(self.view.safeAreaInsets);
        } else {
            make.edges.equalTo(self.view);
        }
    }];
    
    self.urlStr = self.routerInfo.url;
    [self reloadURL];
    
}

- (void)reloadURL{
    if ([self.urlStr isHasChinese]) {
        self.urlStr = [self.urlStr stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    }
    NSString *loadURL = [NSString stringWithFormat:@"%@",self.urlStr];
    NSURL *url = [NSURL URLWithString:loadURL];
    url = [url.scheme isEqualToString:BM_LOCAL] ? TK_RewriteBMLocalURL(loadURL) : url;
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [self.webView loadRequest:request];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    [[BMMediatorManager shareInstance] setCurrentViewController:self];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    
    if (_timer) {
        [_timer invalidate];
        _timer = nil;
    }
    
    if (_progressLayer) {
        [_progressLayer removeFromSuperlayer];
        _progressLayer = nil;
    }
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    /* 解析 router 数据 */
    self.navigationItem.title = self.routerInfo.title;
    self.view.backgroundColor = K_BACKGROUND_COLOR;
    
    if (!self.routerInfo.navShow) {
        self.fd_prefersNavigationBarHidden = YES;
    } else {
        self.fd_prefersNavigationBarHidden = NO;
    }
    
    /* 返回按钮 */
    UIBarButtonItem *backItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"NavBar_BackItemIcon"] style:UIBarButtonItemStylePlain target:self action:@selector(backItemClicked)];
    self.navigationItem.leftBarButtonItem = backItem;
    
    _showProgress = YES;
}

- (void)backItemClicked {
    if ([self.webView canGoBack]) {
        _showProgress = NO;
        [self.webView goBack];
        
        if ([self.webView canGoBack] && [self.navigationItem.leftBarButtonItems count] < 2) {
            UIBarButtonItem *backItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"NavBar_BackItemIcon"] style:UIBarButtonItemStylePlain target:self action:@selector(backItemClicked)];
            UIBarButtonItem *closeItem = [[UIBarButtonItem alloc] initWithTitle:@"关闭" style:UIBarButtonItemStylePlain target:self action:@selector(closeItemClicked)];
            self.navigationItem.leftBarButtonItems = @[backItem, closeItem];
        }
        
    } else {
        [self.navigationController popViewControllerAnimated:YES];
    }
}

- (void)closeItemClicked {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.navigationController popViewControllerAnimated:YES];
    });
}

- (void)dealloc {
    NSLog(@"dealloc >>>>>>>>>>>>> ZDWKWebViewController");
}

- (void)progressAnimation:(NSTimer *)timer{
    self.progressLayer.strokeEnd += 0.005f;
    
    NSLog(@"%f",self.progressLayer.strokeEnd);
    
    if (self.progressLayer.strokeEnd >= 0.9f) {
        [_timer pauseTimer];
    }
}

#pragma mark --- WKNavigationDelegate
// 页面开始加载时调用
- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation {
    if (!self.timer) {
        self.timer = [NSTimer scheduledTimerWithTimeInterval:0.15 target:self selector:@selector(progressAnimation:) userInfo:nil repeats:YES];
    }
    if (_showProgress) {
        [self.timer resumeTimer];
    }
    _showProgress = YES;
}
// 当内容开始返回时调用
//- (void)webView:(WKWebView *)webView didCommitNavigation:(WKNavigation *)navigation {
//
//}
// 页面加载完成之后调用
- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    if (_timer != nil) {
        [_timer pauseTimer];
    }
    
    if (_progressLayer) {
        _progressLayer.strokeEnd = 1.0f;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.7 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self.progressLayer removeFromSuperlayer];
            self.progressLayer = nil;
        });
    }
}
// 页面加载失败时调用
- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation {
    if (_timer != nil) {
        [_timer pauseTimer];
    }
    
    if (_progressLayer) {
        [_progressLayer removeFromSuperlayer];
        _progressLayer = nil;
    }
}

// 接收到服务器跳转请求之后调用
//- (void)webView:(WKWebView *)webView didReceiveServerRedirectForProvisionalNavigation:(WKNavigation *)navigation {
//
//}
// 在收到响应后，决定是否跳转
//- (void)webView:(WKWebView *)webView decidePolicyForNavigationResponse:(WKNavigationResponse *)navigationResponse decisionHandler:(void (^)(WKNavigationResponsePolicy))decisionHandler {
//    decisionHandler(WKNavigationResponsePolicyAllow);
//}
// 在发送请求之前，决定是否跳转
- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    NSURL *URL = navigationAction.request.URL;
    NSString *scheme = [URL scheme];
    if ([scheme isEqualToString:@"tel"]) {
        NSString *resourceSpecifier = [URL resourceSpecifier];
        NSString *callPhone = [NSString stringWithFormat:@"telprompt://%@", resourceSpecifier];
        // 防止iOS 10及其之后，拨打电话系统弹出框延迟出现
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            [[UIApplication sharedApplication] openURL:[NSURL URLWithString:callPhone]];
        });
         decisionHandler(WKNavigationActionPolicyCancel);
    }
    else {
        decisionHandler(WKNavigationActionPolicyAllow);
    }
}
#pragma mark --- WKUIDelegate
//- (void)webView:(WKWebView *)webView runJavaScriptAlertPanelWithMessage:(NSString *)message initiatedByFrame:(void (^)(void))completionHandler {
//
//}

#pragma mark --- WKScriptMessageHandler
- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message{
    // message.name 有两个值：fireEvent，closePage
    if ([message.name isEqualToString:@"closePage"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[BMMediatorManager shareInstance].currentViewController.navigationController popViewControllerAnimated:YES];
            [[BMMediatorManager shareInstance].currentViewController dismissViewControllerAnimated:YES completion:nil];
        });
    }else if ([message.name isEqualToString:@"fireEvent"]) {
        NSDictionary *temp = (NSDictionary *)message.body;
        NSString *event = temp[@"event"];
        if (event) {
            [[BMNotifactionCenter defaultCenter] emit:event info:temp[@"param"]];
        }
    } else {
        
    }
}

@end
