//
//  FASTREAMAppDelegate.m
//  ios-sdk
//
//  Created by lukasz7251 on 06/06/2020.
//  Copyright (c) 2020 lukasz7251. All rights reserved.
//

#import "FASTREAMAppDelegate.h"

@implementation FASTREAMAppDelegate

@synthesize fastream;

- (Fastream*)createFastreamWithToken:(NSString*)token serverURL:(NSString*)server {
    return [[Fastream alloc] initWithToken:token
                               serverURL:server andFlushInterval:60];
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    fastream = [self createFastreamWithToken:@"eyJhbGciOiJIUzI1NiJ9.eyJpbnB1dF9uYW1lIjoieHRiIiwiaW5wdXRfZXZlbnRfbmFtZSI6Inh0YiIsImlzcyI6ImZhc3RyZWFtIiwic3ViIjoiTW9iaWxlU2RrSW5wdXQiLCJpYXQiOjE1OTgyMzUwNjR9.IVQBq9fe3TQMdO4O3RdX_AXp4hoNRKJLmq7-5PFQvTw" serverURL:@"https://prototype.fastream.io"];
    return YES;
}

- (void)applicationWillResignActive:(UIApplication *)application
{
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
}

- (void)applicationWillTerminate:(UIApplication *)application
{
}

@end
