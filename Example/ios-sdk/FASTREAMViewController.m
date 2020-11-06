//
//  FASTREAMViewController.m
//  ios-sdk
//
//  Created by lukasz7251 on 06/06/2020.
//  Copyright (c) 2020 lukasz7251. All rights reserved.
//

#import "FASTREAMViewController.h"
#import "FASTREAMAppDelegate.h"

@interface FASTREAMViewController ()

@end

@implementation FASTREAMViewController
- (IBAction)sendEventButtonPressed {
    Fastream *fastream = ((FASTREAMAppDelegate*)UIApplication.sharedApplication.delegate).fastream;
    [fastream track:@"Button clicked!" customEvent:nil];
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
