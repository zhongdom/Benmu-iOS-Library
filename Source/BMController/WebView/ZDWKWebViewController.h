//
//  ZDWKWebViewController.h
//  AFNetworking
//
//  Created by zhongdong on 2019/5/28.
//

#import <UIKit/UIKit.h>
#import "BMWebViewRouterModel.h"

NS_ASSUME_NONNULL_BEGIN

@interface ZDWKWebViewController : UIViewController

@property (nonatomic, strong) BMWebViewRouterModel *routerInfo;

- (instancetype)initWithRouterModel:(BMWebViewRouterModel *)model;

@end

NS_ASSUME_NONNULL_END
