//
//  BMConfigManager.m
//  WeexDemo
//
//  Created by XHY on 2017/1/10.
//  Copyright © 2017年 taobao. All rights reserved.
//

#import "BMConfigManager.h"
#import "YTKNetwork.h"
#import "BMDefine.h"
#import <SVProgressHUD.h>
#import <CryptLib.h>

#import "BMPayManager.h"
#import "WXApi.h"

#import "BMUserInfoModel.h"
#import "BMDB.h"
#import "BMMediatorManager.h"
#import "BMDB.h"

#import "WXImgLoaderDefaultImpl.h"
#import "BMMonitorHandler.h"
#import "BMConfigCenterHandler.h"

#import <BMMaskComponent.h>
#import "BMTextComponent.h"
#import <BMPopupComponent.h>
#import "BMCalendarComponent.h"
#import "BMSpanComponent.h"
#import "BMChartComponent.h"

#import "BMRouterModule.h"
#import "BMAxiosNetworkModule.h"
#import "BMGeolocationModule.h"
#import "BMModalModule.h"
#import "BMCameraModule.h"
#import "BMPayModule.h"
#import "BMStorageModule.h"
#import "BMShareModule.h"
#import "BMAppConfigModule.h"
#import "BMToolsModule.h"
#import "BMNavigatorModule.h"
#import "BMAuthorLoginModule.h"
#import "BMCommunicationModule.h"
#import "BMImageModule.h"
#import "BMWebSocketModule.h"

#import <WeexSDK/WeexSDK.h>
#import "WXUtility.h"

#import <UMengUShare/UMSocialCore/UMSocialCore.h>

#import "WXBMNetworkDefaultlpml.h"

#import "BMResourceManager.h"
#import "BMEventsModule.h"
#import "BMBrowserImgModule.h"
#import "BMRichTextComponent.h"

#import <AFNetworking/AFNetworkReachabilityManager.h>


#ifdef DEBUG
#import "BMDebugManager.h"
#endif

@implementation BMConfigManager

- (instancetype)init
{
    if (self = [super init]) {
        
        NSString *jStr = [NSString stringWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"eros.native" ofType:@"json"] encoding:NSUTF8StringEncoding error:nil];
        NSString *decryptStr = [[[CryptLib alloc] init] decryptCipherTextWith:jStr key:AES_KEY iv:AES_IV];
        NSData *jData = [decryptStr dataUsingEncoding:NSUTF8StringEncoding];
        
//        NSData *jData = [NSData dataWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"eros.native" ofType:@"json"]];
        NSDictionary *jDic = [NSJSONSerialization JSONObjectWithData:jData options:NSJSONReadingAllowFragments error:nil];
        _platform = [BMPlatformModel yy_modelWithJSON:jDic];
    }
    return self;
}

- (NSDictionary *)envInfo
{
    if (!_envInfo) {
        _envInfo = [WXUtility getEnvironment];
    }
    return _envInfo;
}

#pragma mark - Public Func

+ (instancetype)shareInstance
{
    static BMConfigManager *_instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _instance = [[BMConfigManager alloc] init];
    });
    return _instance;
}
+ (void)configDefaultData
{
    /* 启动网络变化监控 */
    AFNetworkReachabilityManager *reachability = [AFNetworkReachabilityManager sharedManager];
    [reachability startMonitoring];
    
    /** 初始化Weex */
    [BMConfigManager initWeexSDK];
    
    BMPlatformModel *platformInfo = TK_PlatformInfo();
    
    
    /** 设置统一请求url */
    [[YTKNetworkConfig sharedConfig] setBaseUrl:platformInfo.url.request];
    [[YTKNetworkConfig sharedConfig] setCdnUrl:platformInfo.url.image];
    
    /** 应用最新js资源文件 */
    [[BMResourceManager sharedInstance] compareVersion];
    
    /** 初始化数据库 */
    [[BMDB DB] configDB];
    
    /** 设置 HUD */
    [BMConfigManager configProgressHUD];
    
    /** 配置友盟相关sdk */
    if (platformInfo.umeng.enabled) {
        [BMConfigManager configUmeng];
    }
    
    
    if (platformInfo.wechat.enabled) {
        /* 注册微信SDK */
        [WXApi registerApp:platformInfo.wechat.appId];
    }
    
    
    /* 监听截屏事件 */
//    [[BMScreenshotEventManager shareInstance] monitorScreenshotEvent];
    
}

+ (void)configUmeng
{
    BMPlatformModel *platformInfo = TK_PlatformInfo();
    
    /* 友盟分享 */
    [[UMSocialManager defaultManager] setUmSocialAppkey:platformInfo.umeng.iOSAppKey];
    
    
    /** 友盟微信分享功能 */
    if (platformInfo.wechat.appId.length && platformInfo.wechat.appSecret.length) {
        //设置微信AppId，设置分享url，默认使用友盟的网址
        [[UMSocialManager defaultManager] setPlaform:UMSocialPlatformType_WechatSession
                                              appKey:platformInfo.wechat.appId appSecret:platformInfo.wechat.appSecret
                                         redirectURL:@""];
    }
    
}

+ (void)configProgressHUD
{
    [SVProgressHUD setBackgroundColor:[K_BLACK_COLOR colorWithAlphaComponent:0.70f]];
    [SVProgressHUD setForegroundColor:K_WHITE_COLOR];
    [SVProgressHUD setCornerRadius:4.0];
    [SVProgressHUD setMinimumDismissTimeInterval:1.5];
}

+ (void)registerBmHandlers
{
    [WXSDKEngine registerHandler:[WXImgLoaderDefaultImpl new] withProtocol:@protocol(WXImgLoaderProtocol)];
    [WXSDKEngine registerHandler:[WXBMNetworkDefaultlpml new] withProtocol:@protocol(WXResourceRequestHandler)];
    [WXSDKEngine registerHandler:[BMMonitorHandler new] withProtocol:@protocol(WXAppMonitorProtocol)];
    [WXSDKEngine registerHandler:[BMConfigCenterHandler new] withProtocol:@protocol(WXConfigCenterProtocol)];
}

+ (void)registerBmComponents
{
    
    NSDictionary *components = @{
                                @"bmmask":          NSStringFromClass([BMMaskComponent class]),
                                @"bmpop":           NSStringFromClass([BMPopupComponent class]),
                                @"bmtext":          NSStringFromClass([BMTextComponent class]),
                                @"bmrichtext":      NSStringFromClass([BMRichTextComponent class]),
                                @"bmcalendar":      NSStringFromClass([BMCalendarComponent class]),
                                @"bmspan":          NSStringFromClass([BMSpanComponent class]),
                                @"bmchart":         NSStringFromClass([BMChartComponent class])
                                };
    for (NSString *componentName in components) {
        [WXSDKEngine registerComponent:componentName withClass:NSClassFromString([components valueForKey:componentName])];
    }
}

+ (void)registerBmModules
{
    NSDictionary *modules = @{
                              @"bmRouter" :         NSStringFromClass([BMRouterModule class]),
                              @"bmAxios":           NSStringFromClass([BMAxiosNetworkModule class]),
                              @"bmGeolocation":     NSStringFromClass([BMGeolocationModule class]),
                              @"bmModal":           NSStringFromClass([BMModalModule class]),
                              @"bmCamera":          NSStringFromClass([BMCameraModule class]),
                              @"bmPay":             NSStringFromClass([BMPayModule class]),
                              @"bmStorage":         NSStringFromClass([BMStorageModule class]),
                              @"bmShare":           NSStringFromClass([BMShareModule class]),
                              @"bmFont":            NSStringFromClass([BMAppConfigModule class]),
                              @"bmEvents":          NSStringFromClass([BMEventsModule class]),
                              @"bmBrowserImg":      NSStringFromClass([BMBrowserImgModule class]),
                              @"bmTool":            NSStringFromClass([BMToolsModule class]),
                              @"bmAuth":            NSStringFromClass([BMAuthorLoginModule class]),
                              @"bmNavigator":       NSStringFromClass([BMNavigatorModule class]),
                              @"bmCommunication":   NSStringFromClass([BMCommunicationModule class]),
                              @"bmImage":           NSStringFromClass([BMImageModule class]),
                              @"bmWebSocket":       NSStringFromClass([BMWebSocketModule class])
                              };
    
    for (NSString *moduleName in modules.allKeys) {
        [WXSDKEngine registerModule:moduleName withClass:NSClassFromString([modules valueForKey:moduleName])];
    }
}

+ (void)initWeexSDK
{
    [WXSDKEngine initSDKEnvironment];
    
    [BMConfigManager registerBmHandlers];
    [BMConfigManager registerBmComponents];
    [BMConfigManager registerBmModules];
    
#ifdef DEBUG
    [WXDebugTool setDebug:YES];
    [WXLog setLogLevel:WXLogLevelLog];
    [[BMDebugManager shareInstance] show];
//    [[ATManager shareInstance] show];
    
#else
    [WXDebugTool setDebug:NO];
    [WXLog setLogLevel:WXLogLevelError];
#endif
}

- (BOOL)applicationOpenURL:(NSURL *)url
{
    return YES;
}

@end