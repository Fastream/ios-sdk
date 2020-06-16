//
//  FASTREAMAppDelegate.h
//  ios-sdk
//
//  Created by lukasz7251 on 06/06/2020.
//  Copyright (c) 2020 lukasz7251. All rights reserved.
//

@import UIKit;
#import <ios_sdk/Fastream.h>

@interface FASTREAMAppDelegate : UIResponder <UIApplicationDelegate>

@property (strong, nonatomic) UIWindow *window;

@property(nonatomic, strong) id fastream;
@end
