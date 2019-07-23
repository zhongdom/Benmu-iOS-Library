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
#import <PBViewController.h>
#import <SDWebImage.h>
#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>

@interface ZDWKWebViewController ()<WKUIDelegate, WKNavigationDelegate, WKScriptMessageHandler, PBViewControllerDelegate, PBViewControllerDataSource>

@property (nonatomic, assign) BOOL showProgress;

@property (nonatomic, strong) WKWebView *webView;

@property (nonatomic, copy) NSString *urlStr;

/** 伪进度条 */
@property (nonatomic, strong) CAShapeLayer *progressLayer;
/** 进度条定时器 */
@property (nonatomic, strong) NSTimer *timer;

/** 是否 echat 链接 **/
@property (nonatomic, assign) BOOL isEchat;
// web端传过来的图片数组
@property (nonatomic, strong) NSArray *imageArr;
// 视频播放VC
@property (nonatomic, strong) AVPlayerViewController *playerVC;
/** echat会话状态 **/
@property(nonatomic,assign) NSInteger chatEvent;
/** 是否退出echat会话页面（消息盒子） **/
@property(nonatomic,assign) BOOL isLeaveChatWindow;
@property(nonatomic,assign) BOOL isMsgBox;

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
        if ([model.url hasPrefix:@"https://echat.renrenyoupin.com"]) {
            self.isEchat = YES;
        } else {
            self.isEchat = NO;
        }
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
    
    if (self.isEchat) {
        [config.userContentController addScriptMessageHandler:avoidDlegate name:@"callEchatNative"];
        [config.userContentController addScriptMessageHandler:avoidDlegate name:@"callEchatNativeConnect"];
    }
    
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

- (void)closeChat {
    [self callJSFunction:@"closeChat" andValue:@""];
}

- (void)dealloc {
    NSLog(@"dealloc >>>>>>>>>>>>> ZDWKWebViewController");
}

- (void)progressAnimation:(NSTimer *)timer{
    self.progressLayer.strokeEnd += 0.005f;
    
//    NSLog(@"%f",self.progressLayer.strokeEnd);
    
    if (self.progressLayer.strokeEnd >= 0.9f) {
        [_timer pauseTimer];
    }
}

-(void)callJSFunction: (NSString *)functionName andValue:(id)value{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSMutableDictionary * dictM = [NSMutableDictionary dictionary];
        if (functionName != nil) {
            [dictM setObject:functionName forKey:@"functionName"];
        }
        if (value != nil) {
            [dictM setObject:value forKey:@"value"];
        }
        NSString * jsonStr = [self obj2String:dictM];
        [self.webView evaluateJavaScript:[NSString stringWithFormat:@"window.callEchatJs(%@)",jsonStr] completionHandler:^(id _Nullable result, NSError * _Nullable error) {
            if (error) {
                NSLog(@"CALLJS ❌ error = %@---%@\n%@--%@--%@",error,result,functionName,value,jsonStr);
            }
        }];
    });
}

-(NSString *)obj2String:(id)data{
    NSError * error = nil;
    NSData * datas = [NSJSONSerialization dataWithJSONObject:data options:kNilOptions error:&error];
    NSString * string = [[NSString alloc]initWithData:datas encoding:NSUTF8StringEncoding];
    if (error) {
        NSAssert(error != nil,@"obj ---> string 解析异常");
        return nil;
    }
    return [self noWhiteSpaceString:string];
}

- (NSString *)noWhiteSpaceString:(NSString *)string{
    NSString *newString = string;
    //去除掉首尾的空白字符和换行字符
    newString = [newString stringByReplacingOccurrencesOfString:@"\r" withString:@""];
    newString = [newString stringByReplacingOccurrencesOfString:@"\n" withString:@""];
    newString = [newString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    //去除掉首尾的空白字符和换行字符使用可能会影响html标签显示异常
    //    newString = [newString stringByReplacingOccurrencesOfString:@" " withString:@""];
    //    可以去掉空格，注意此时生成的strUrl是autorelease属性的，所以不必对strUrl进行release操作！
    return newString;
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
    
    if (self.isEchat) {
        //native去接管 Video 和 图片轮播管理
        [self callJSFunction:@"setMediaPlayer" andValue:@{@"video":@1,@"image":@1}];
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
        dispatch_async(dispatch_get_main_queue(), ^{
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
        if (self.isEchat) {
            //事件分发
            [self methods:[self string2Dict:message.body]];
        }
    }
}

//事件分发
-(void)methods:(NSDictionary *)dict{
    NSString * fuckey = @"functionName";
    NSString * valueKey = @"value";
    NSString * fucName = (NSString *)dict[fuckey];
    NSString * value = (NSString *)dict[valueKey];
    //根据不同参数调用不的方法//
    NSString * finalFucName = [NSString stringWithFormat:@"%@%@",fucName,value?@":":@""];
    SEL method = NSSelectorFromString(finalFucName);
    if ([dict.allKeys containsObject:fuckey] && [self respondsToSelector:method]) {
        [self performSelector:method withObject:value afterDelay:0];
    }
}

-(NSDictionary *)string2Dict:(NSString *)str{
    //转换
    NSData * jsonData = [str dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error;
    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:jsonData options:NSJSONReadingMutableContainers error:&error];
    if(error) {
        return nil;
    }
    return dict;
}

-(void)closeWeb{
    _isLeaveChatWindow = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.presentingViewController != nil) {
            [self.presentingViewController dismissViewControllerAnimated:NO completion:^{
                
            }];
        }else{
            if ([self.navigationController.childViewControllers.lastObject isKindOfClass:[self class]]) {
                [self.navigationController popViewControllerAnimated:YES];
            }
        }
    });
}

#pragma mark -- 消息盒子
-(void)echatPageStatus:(id)value{
    NSInteger chatEvent = [value[@"event"] integerValue];
    self.chatEvent = chatEvent;
    
    switch (chatEvent) {
        case 6:{
//            self.isMsgBox = NO;
        }
            break;
        case 4:{
            self.isMsgBox = YES;
            self.navigationItem.rightBarButtonItem.customView.hidden = YES;
        }
            break;
        case 3:{
            [self closeWeb];
        }
            break;
        case 2:{
            self.isMsgBox = YES;
            self.navigationItem.rightBarButtonItem.customView.hidden = YES;
        }
            break;
        case 1:{
            self.navigationItem.rightBarButtonItem.customView.hidden = NO;
        }
            break;
        default:
            break;
    }
}

#pragma mark --  对话状态
-(void)chatStatus:(id)value{
    //匹配关闭状态
    NSString *regex = @"^end\\-[0-8]\\-[0]";//结束
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"SELF MATCHES %@", regex];
    BOOL isCloseFlag = [predicate evaluateWithObject:value];
    if (isCloseFlag) {
        //询问H5
        _isLeaveChatWindow = YES;
        if (self.chatEvent != 0) {
            [self callJSFunction:@"echatBackEvent" andValue:@""];
        }else{
            [self closeWeb];
        }
        //页面未打开或者无状态,点击返回按钮立马返回
        if (self.chatEvent == 0) {
            [self closeWeb];
        }
    }
    
    // 聊天中显示关闭对话按钮
    if ([value isEqualToString:@"chatting"]){
        UIBarButtonItem *closeItem = [[UIBarButtonItem alloc] initWithTitle:@"关闭" style:UIBarButtonItemStylePlain target:self action:@selector(closeChat)];
        self.navigationItem.rightBarButtonItem = closeItem;
    } else {
        self.navigationItem.rightBarButtonItem.customView.hidden = YES;
    }
}

// 评价回调 ---> 评价后关闭
-(void)visitorEvaluate:(id)value{
    NSString *regex = @"^[01]\\-2";
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"SELF MATCHES %@", regex];
    BOOL isCloseFlag = [predicate evaluateWithObject:value];
    if (isCloseFlag) {
        //询问H5
        _isLeaveChatWindow = YES;
        if (self.chatEvent != 0) {
            [self callJSFunction:@"echatBackEvent" andValue:@""];
        }else{
            [self closeWeb];
        }
    }
}

#pragma mark -- 播放视频
-(void)video:(id)value{
    if ([value isKindOfClass:[NSString class]]) {
        NSDictionary * dict = [self string2Dict:value]; //jsonString 转 Json
        if ([[dict objectForKey:@"type"] isEqualToString:@"play"]) {
            NSString * videoUrlStr = [dict objectForKey:@"url"];
            //判断链接string是否包含中文,如果是中文就进行转码
            videoUrlStr = [self encodingURLString:videoUrlStr];
            NSURL *videoUrl = [NSURL URLWithString:videoUrlStr];
            if (videoUrl) {
                // 播放视频
                self.playerVC = [[AVPlayerViewController alloc] init];
                NSDictionary * optional = @{@"AVURLAssetPreferPreciseDurationAndTimingKey":@(YES)};
                AVURLAsset * urlAssert = [[AVURLAsset alloc] initWithURL:videoUrl options:optional];
                AVPlayerItem * playerItem = [[AVPlayerItem alloc] initWithAsset:urlAssert];
                
                //创建AVPLAYER
                AVPlayer * player = [[AVPlayer alloc] initWithPlayerItem:playerItem];
                self.playerVC.player = player;
                self.playerVC.videoGravity = AVLayerVideoGravityResizeAspect;
                self.playerVC.showsPlaybackControls = YES;
                self.playerVC.view.translatesAutoresizingMaskIntoConstraints = YES;
                [self presentViewController:self.playerVC animated:YES completion:^{
                    [self.playerVC.player play];
                }];
            }
        }
    }
}

//判断中文转码
//判断是否有string是否有包含中文
-(NSString * )encodingURLString:(NSString * )string{
    for (int i = 0; i < string.length; i++) {
        int a = [string characterAtIndex:i];
        if (a > 0x4e00 && a < 0x9fff) {
            if ([UIDevice currentDevice].systemVersion.floatValue >= 9.0f) {
                return [string stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
            }else{
                return [string stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
            }
        }
    }
    return string;
}

#pragma mark -- 浏览图片
-(void)previewImage:(id)value{
    NSDictionary *param = [self string2Dict:value];
    if (!param) {
        return ;
    }
    self.imageArr = param[@"urls"];
    PBViewController *pbViewController = [[PBViewController alloc] init];
    pbViewController.pb_dataSource = self;
    pbViewController.pb_delegate = self;
    pbViewController.pb_startPage = [param[@"current"] integerValue] - 1;
    [self presentViewController:pbViewController animated:YES completion:nil];
    
}

#pragma mark - PBViewControllerDataSource

- (NSInteger)numberOfPagesInViewController:(PBViewController *)viewController {
    return self.imageArr.count;
}

- (void)viewController:(PBViewController *)viewController presentImageView:(UIImageView *)imageView forPageAtIndex:(NSInteger)index progressHandler:(void (^)(NSInteger, NSInteger))progressHandler {
    NSDictionary *imageDict = self.imageArr[index];
    [imageView sd_setImageWithURL:[NSURL URLWithString:imageDict[@"sourceImg"]]];
}

- (UIView *)thumbViewForPageAtIndex:(NSInteger)index {
    return nil;
}
#pragma mark - PBViewControllerDelegate

- (void)viewController:(PBViewController *)viewController didSingleTapedPageAtIndex:(NSInteger)index presentedImage:(UIImage *)presentedImage {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
