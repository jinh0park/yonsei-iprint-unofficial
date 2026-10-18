// Compile this instead of main.m, with NativeCore.m. Run inside a test-only copy
// of the app bundle so production prepareDocument locates its usual resources.
#define main IPrintProductionMain
#import "../main.m"
#undef main

@interface PrintFlowHarness : NativeApp
@end
@implementation PrintFlowHarness
- (void)refresh {}
- (void)run:(NSString*)message work:(NSString*(^)(void))work {
    self.busy=YES;
    @try {
        NSString *result=work();
        dispatch_async(dispatch_get_main_queue(),^{
            if(!self.submissionCompleted || self.prnPath || self.folder)exit(3);
            printf("{\"passed\":true,\"production_prepare_and_send\":true,\"completed_and_temp_job_removed\":true,\"message\":\"%s\"}\n",result.UTF8String);
            exit(0);
        });
    }@catch(NSException *e){fprintf(stderr,"%s\n",e.reason.UTF8String);exit(1);}
}
@end

int main(int argc,const char *argv[]){@autoreleasepool{
    if(argc!=3)return 2;
    schoolHost=@"127.0.0.1";schoolPort=(uint16_t)atoi(argv[1]);
    NSApplication *application=NSApplication.sharedApplication;application.activationPolicy=NSApplicationActivationPolicyProhibited;
    PrintFlowHarness *app=[PrintFlowHarness new];
    app.copiesField=[NSTextField new];app.copiesStepper=[NSStepper new];app.copiesStepper.minValue=1;app.copiesStepper.maxValue=99;
    app.sidesChoice=[[NSPopUpButton alloc]initWithFrame:NSZeroRect pullsDown:NO];[app.sidesChoice addItemsWithTitles:@[@"단면",@"양면 · 긴 쪽 넘김",@"양면 · 짧은 쪽 넘김"]];
    for(NSString *invalid in @[@"",@"0",@"100",@"-1",@"1.5",@"2abc"]){
        app.copiesField.stringValue=invalid;BOOL rejected=NO;@try{[app selectedCopies];}@catch(NSException *e){rejected=YES;}if(!rejected)return 4;
    }
    app.copiesField.stringValue=@"1";app.copiesStepper.integerValue=2;[app stepCopies:nil];if([app selectedCopies]!=2)return 5;
    NSString *temp=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    [[NSFileManager defaultManager]createDirectoryAtPath:temp withIntermediateDirectories:YES attributes:nil error:nil];app.folder=temp;app.prnPath=[temp stringByAppendingPathComponent:@"old-settings.prn"];
    [app.sidesChoice selectItemAtIndex:1];[app printOptionsChanged:nil];
    if(app.folder || app.prnPath || [[NSFileManager defaultManager]fileExistsAtPath:temp])return 6;
    IPConnection *login=[[IPConnection alloc]initWithHost:schoolHost port:schoolPort];[login authenticateUser:@"NativeTest" password:@"Native-Test-17"];[login close];
    app.pdfURL=[NSURL fileURLWithPath:@(argv[2])];app.signedInUser=@"NativeTest";app.passwordField=[NSSecureTextField new];app.passwordField.stringValue=@"Native-Test-17";
    [app doSend:nil];dispatch_main();
}}
