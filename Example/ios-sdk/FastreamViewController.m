//
//  FASTREAMViewController.m
//  ios-sdk
//
//  Created by lukasz7251 on 06/06/2020.
//  Copyright (c) 2020 lukasz7251. All rights reserved.
//

#import "FastreamViewController.h"
#import "FastreamAppDelegate.h"

@interface FastreamViewController ()

@end

@implementation FastreamViewController
- (IBAction)sendEventButtonPressed {
    Fastream *fastream = [Fastream sharedInstance];
    [fastream track:@"Test" properties:nil];
    [fastream flush];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
