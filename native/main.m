#import <Cocoa/Cocoa.h>
#import <PDFKit/PDFKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "NativeCore.h"

static NSString *schoolHost=@"yonsei.svr.i-print.co.kr";
static uint16_t schoolPort=30013;
static BOOL localProfilePreview=NO;
static BOOL localRegistrationPreview=NO;
static BOOL localDashboardPreview=NO;
static BOOL localDarkPreview=NO;
static BOOL localNetworkPreview=NO;
static NSString *localPreviewPDFPath=nil;
static NSColor *IPTint(CGFloat r,CGFloat g,CGFloat b){return [NSColor colorWithSRGBRed:r green:g blue:b alpha:1];}
static NSColor *IPAccent(void){return [NSColor colorWithName:@"iPrintAccent" dynamicProvider:^NSColor*(NSAppearance *a){BOOL dark=[[a bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua,NSAppearanceNameDarkAqua]] isEqualToString:NSAppearanceNameDarkAqua];return dark ? IPTint(.43,.65,1) : IPTint(.10,.23,.44);}];}
static NSColor *IPBackground(void){return [NSColor colorWithName:@"iPrintBackground" dynamicProvider:^NSColor*(NSAppearance *a){BOOL dark=[[a bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua,NSAppearanceNameDarkAqua]] isEqualToString:NSAppearanceNameDarkAqua];return dark ? IPTint(.10,.12,.15) : IPTint(.95,.96,.98);}];}
@interface IPSurface : NSView
@property NSColor *fillColor,*strokeColor;
@property CGFloat radius;
@end
@implementation IPSurface
- (void)drawRect:(NSRect)dirty{NSRect rect=NSInsetRect(self.bounds,.5,.5);NSBezierPath *path=[NSBezierPath bezierPathWithRoundedRect:rect xRadius:self.radius yRadius:self.radius];[self.fillColor setFill];[path fill];if(self.strokeColor){[self.strokeColor setStroke];path.lineWidth=1;[path stroke];}}
- (void)viewDidChangeEffectiveAppearance{[super viewDidChangeEffectiveAppearance];self.needsDisplay=YES;}
@end
static void printJSON(id obj){NSData *d=[NSJSONSerialization dataWithJSONObject:obj options:NSJSONWritingPrettyPrinted error:nil];fwrite(d.bytes,1,d.length,stdout);fputc('\n',stdout);}
static NSString *dateStamp(void){NSDateFormatter *f=[NSDateFormatter new];f.locale=[[NSLocale alloc]initWithLocaleIdentifier:@"en_US_POSIX"];f.dateFormat=@"yyyyMMdd";return [f stringFromDate:NSDate.date];}
static NSString *osVersion(void){NSOperatingSystemVersion v=NSProcessInfo.processInfo.operatingSystemVersion;return [NSString stringWithFormat:@"%ld.%ld.%ld",(long)v.majorVersion,(long)v.minorVersion,(long)v.patchVersion];}
static void verifyVectors(NSString *path){
    NSDictionary *v=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:path] options:0 error:nil];if(!v)IPFail(@"Missing oracle vectors");
    for(NSDictionary *r in v[@"vectors"]){NSString *h=r[@"input_hex"];NSMutableData *b=[NSMutableData data];for(NSUInteger i=0;i<h.length;i+=2){unsigned n;[[NSScanner scannerWithString:[h substringWithRange:NSMakeRange(i,2)]] scanHexInt:&n];uint8_t c=n;[b appendBytes:&c length:1];}NSString *p=[[NSString alloc]initWithData:b encoding:NSASCIIStringEncoding];if(![IPPassword(p) isEqual:r[@"type6"]])IPFail(@"Password vector mismatch");}
    for(NSDictionary *r in v[@"identities"])if(![IPIdentity([r[@"input"] dataUsingEncoding:NSASCIIStringEncoding],r[@"time"]) isEqual:r[@"encoded"]])IPFail(@"Identity vector mismatch");
    printJSON(@{@"passed":@YES,@"passwordVectors":@([v[@"vectors"] count]),@"identityVectors":@([v[@"identities"] count]),@"architecture":@"arm64"});
}
static int cli(int argc,const char *argv[]){
 @try {
    NSString *op=@(argv[1]);
    if([op isEqual:@"--self-test"] && argc==3){verifyVectors(@(argv[2]));return 0;}
    if([op isEqual:@"--fixtures"] && argc==3){
        NSString *folder=@(argv[2]);[[NSFileManager defaultManager]createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
        NSData *auth=IPAuthRequest(@"NativeTest",@"Native-Test-17",@"21345");[auth writeToFile:[folder stringByAppendingPathComponent:@"auth.bin"] atomically:YES];
        NSDictionary *account=@{@"encryptedID":IPIdentity([@"NativeTest" dataUsingEncoding:NSASCIIStringEncoding],@"21345"),@"salt":@"21345"};
        NSData *record=IPPrintRecord(@"C:\\i-Print\\Spool\\native-A4-1.prn",@"iPrint-Native-test",70000,1,account,@"Mac-Native",@"127.0.0.1");[record writeToFile:[folder stringByAppendingPathComponent:@"record.bin"] atomically:YES];
        NSData *ps=[@"%!PS-Adobe-3.0\n%%Pages: 1\nshowpage\n" dataUsingEncoding:NSASCIIStringEncoding];
        [IPWrapPostScript(ps,@"iPrint-Native-test",@"20261017",@"27.0.1") writeToFile:[folder stringByAppendingPathComponent:@"wrapped.prn"] atomically:YES];
        [ps writeToFile:[folder stringByAppendingPathComponent:@"input.ps"] atomically:YES];
        [IPRegistrationRequest(@"NativeTest",@"Native-Test-17",@"21345",@{@"name":@"가나다",@"phone":@"01012345678",@"email":@"native@example.com"}) writeToFile:[folder stringByAppendingPathComponent:@"registration.bin"] atomically:YES];
        printJSON(@{@"serializedLength":@(IPSerializedLength(record)),@"recordBytes":@(record.length)});return 0;
    }
    // Synthetic fixture account only; no CLI path accepts real credentials.
    if([op isEqual:@"--test-network"] && argc==5){
        NSString *host=@(argv[2]);uint16_t port=atoi(argv[3]);
        if(![host isEqual:@"127.0.0.1"])IPFail(@"Test mode only accepts loopback");
        NSString *testMode=@(argv[4]);
        if([testMode hasPrefix:@"queue-"]){
            NSArray *jobs=IPFetchWaitJobs(host,port,@"NativeTest",@"Native-Test-17");
            if([testMode isEqual:@"queue-delete"]){if(!jobs.count)IPFail(@"Synthetic queue is empty");jobs=IPDeleteWaitJob(host,port,@"NativeTest",@"Native-Test-17",jobs[0]);}
            printJSON(@{@"success":@YES,@"synthetic":@YES,@"jobs":jobs});return 0;
        }
        if([@(argv[4]) isEqual:@"register"]){
            IPConnection *r=[[IPConnection alloc]initWithHost:host port:port];
            @try {[r registerUser:@"NativeTest" password:@"Native-Test-17" profile:@{@"name":@"가나다",@"phone":@"01012345678",@"email":@"native@example.com"}];[r close];}
            @catch(NSException *e){printJSON(@{@"success":@NO,@"synthetic":@YES,@"error":e.reason,@"registrationMayHaveBeenSent":@(r.registrationMayHaveBeenSent)});[r close];return 1;}
        }
        IPConnection *a=[[IPConnection alloc]initWithHost:host port:port];NSDictionary *account=[a authenticateUser:@"NativeTest" password:@"Native-Test-17"];[a close];
        if([@(argv[4]) isEqual:@"register"] && ![account[@"name"] isEqualToString:@"가나다"])IPFail(@"Synthetic registration name read-back mismatch");
        if([@(argv[4]) isEqual:@"upload"]){IPConnection *p=[[IPConnection alloc]initWithHost:host port:port];NSMutableData *document=[NSMutableData dataWithLength:70000];uint8_t *b=document.mutableBytes;for(NSUInteger i=0;i<document.length;i++)b[i]=i%251;
            NSData *record=IPPrintRecord(@"C:\\i-Print\\Spool\\native-A4-1.prn",@"iPrint-Native-test",document.length,1,account,@"Mac-Native",p.localAddress);
            [p upload:document record:record progress:^(double n){}];[p close];}
        if([@(argv[4]) isEqual:@"profile-read"]){
            IPConnection *p=[[IPConnection alloc]initWithHost:host port:port];NSDictionary *profile=[p profileForUser:@"NativeTest" password:@"Native-Test-17"];[p close];
            printJSON(@{@"success":@YES,@"synthetic":@YES,@"name":profile[@"name"],@"phone":profile[@"phone"],@"email":profile[@"email"]});return 0;
        }
        printJSON(@{@"success":@YES,@"synthetic":@YES,@"user":account[@"user"],@"credit":account[@"credit"]});return 0;
    }
    IPFail(@"Unknown test command");
 }@catch(NSException *e){printJSON(@{@"success":@NO,@"error":e.reason ?: @"오류"});return 1;}return 1;
}
@interface NativeApp : NSObject<NSApplicationDelegate,NSWindowDelegate,NSTextFieldDelegate,NSTableViewDataSource,NSTableViewDelegate>
@property NSWindow *window;
@property NSTextField *userField,*accountLabel,*fileLabel,*status;
@property NSSecureTextField *passwordField;
@property NSButton *login,*choose,*send;
@property NSButton *profileButton,*profileCancel;
@property NSPanel *profileWindow;
@property NSButton *signupButton,*signupSubmit,*signupCancel,*signupAgree;
@property NSPanel *signupWindow;
@property NSTextField *signupID,*signupName,*signupPhone,*signupEmail;
@property NSSecureTextField *signupPassword,*signupRepeat;
@property BOOL signupNeedsVerification;
@property NSButton *queueButton,*queueReload,*queueDelete,*queueClose;
@property NSPanel *queueWindow;
@property NSTableView *queueTable;
@property NSTextField *queueStatus;
@property NSArray<NSDictionary *> *queueJobs;
@property BOOL queueFresh;
@property NSProgressIndicator *progress;
@property NSURL *pdfURL;
@property NSString *jobName,*folder,*prnPath,*signedInUser;
@property NSUInteger pages;
@property BOOL busy;
@property NSTextField *fileHint,*documentState,*sendHint;
@property NSProgressIndicator *activity;
@property BOOL submissionCompleted;
@property NSImageView *thumbnailView;
@property NSUInteger thumbnailGeneration;
@property NSPopUpButton *sidesChoice;
@property NSTextField *copiesField;
@property NSStepper *copiesStepper;
@property NSUInteger jobCopies,jobDuplex;
@end
@implementation NativeApp
- (void)installMenus {
    NSMenu *bar=[NSMenu new];NSMenuItem *appItem=[NSMenuItem new];[bar addItem:appItem];NSMenu *appMenu=[[NSMenu alloc]initWithTitle:@"연세 iPrint (비공식)"];appItem.submenu=appMenu;
    NSMenuItem *about=[appMenu addItemWithTitle:@"연세 iPrint (비공식)에 관하여" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];about.target=NSApp;
    [appMenu addItem:NSMenuItem.separatorItem];NSMenuItem *quit=[appMenu addItemWithTitle:@"연세 iPrint (비공식) 종료" action:@selector(terminate:) keyEquivalent:@"q"];quit.target=NSApp;
    NSMenuItem *editItem=[NSMenuItem new];[bar addItem:editItem];NSMenu *edit=[[NSMenu alloc]initWithTitle:@"편집"];editItem.submenu=edit;
    [edit addItemWithTitle:@"실행 취소" action:@selector(undo:) keyEquivalent:@"z"];
    NSMenuItem *redo=[edit addItemWithTitle:@"다시 실행" action:@selector(redo:) keyEquivalent:@"z"];redo.keyEquivalentModifierMask=NSEventModifierFlagCommand|NSEventModifierFlagShift;
    [edit addItem:NSMenuItem.separatorItem];[edit addItemWithTitle:@"잘라내기" action:@selector(cut:) keyEquivalent:@"x"];[edit addItemWithTitle:@"복사" action:@selector(copy:) keyEquivalent:@"c"];[edit addItemWithTitle:@"붙여넣기" action:@selector(paste:) keyEquivalent:@"v"];[edit addItemWithTitle:@"모두 선택" action:@selector(selectAll:) keyEquivalent:@"a"];NSApp.mainMenu=bar;
}
- (NSTextField*)text:(NSString*)s frame:(NSRect)r size:(CGFloat)size weight:(NSFontWeight)weight color:(NSColor*)color in:(NSView*)parent {
    NSTextField *v=[NSTextField wrappingLabelWithString:s];v.frame=r;v.font=[NSFont systemFontOfSize:size weight:weight];v.textColor=color;[parent addSubview:v];return v;
}
- (IPSurface*)surface:(NSRect)frame fill:(NSColor*)fill radius:(CGFloat)radius in:(NSView*)parent {
    IPSurface *v=[[IPSurface alloc]initWithFrame:frame];v.fillColor=fill;v.radius=radius;v.strokeColor=[NSColor.labelColor colorWithAlphaComponent:.08];[parent addSubview:v];return v;
}
- (void)symbol:(NSString*)name frame:(NSRect)frame size:(CGFloat)size color:(NSColor*)color in:(NSView*)parent {
    NSImageView *v=[[NSImageView alloc]initWithFrame:frame];v.image=[[NSImage imageWithSystemSymbolName:name accessibilityDescription:nil] imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:size weight:NSFontWeightMedium]];v.contentTintColor=color;[v setAccessibilityElement:NO];[parent addSubview:v];
}
- (void)styleField:(NSTextField*)field {
    field.font=[NSFont systemFontOfSize:14];field.controlSize=NSControlSizeLarge;field.bezeled=YES;field.bezelStyle=NSTextFieldRoundedBezel;field.drawsBackground=YES;field.backgroundColor=NSColor.textBackgroundColor;
}
- (void)styleButton:(NSButton*)button primary:(BOOL)primary {
    button.bezelStyle=NSBezelStyleRounded;button.controlSize=NSControlSizeLarge;button.font=[NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
    if(primary){button.bezelColor=IPTint(.10,.23,.44);button.contentTintColor=NSColor.whiteColor;}
}
- (NSButton*)action:(NSString*)title frame:(NSRect)frame selector:(SEL)selector primary:(BOOL)primary in:(NSView*)parent {
    NSButton *button=[NSButton buttonWithTitle:title target:self action:selector];button.frame=frame;[self styleButton:button primary:primary];[parent addSubview:button];return button;
}
- (void)pill:(NSString*)title frame:(NSRect)frame in:(NSView*)parent {
    IPSurface *v=[self surface:frame fill:IPBackground() radius:8 in:parent];v.strokeColor=nil;
    NSTextField *text=[self text:title frame:NSMakeRect(0,5,frame.size.width,19) size:12 weight:NSFontWeightMedium color:NSColor.secondaryLabelColor in:v];text.alignment=NSTextAlignmentCenter;
}
- (void)applicationDidFinishLaunching:(NSNotification*)n {
    [self installMenus];
    self.window=[[NSWindow alloc]initWithContentRect:NSMakeRect(0,0,920,624) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable backing:NSBackingStoreBuffered defer:NO];
    self.window.title=@"연세 iPrint (비공식) · 0.1.14";self.window.titlebarAppearsTransparent=YES;self.window.backgroundColor=IPBackground();self.window.delegate=self;[self.window center];
    IPSurface *root=[[IPSurface alloc]initWithFrame:NSMakeRect(0,0,920,624)];root.fillColor=IPBackground();self.window.contentView=root;
    IPSurface *account=[self surface:NSMakeRect(24,122,252,478) fill:NSColor.controlBackgroundColor radius:18 in:root];
    [self text:@"계정" frame:NSMakeRect(22,436,208,20) size:11 weight:NSFontWeightSemibold color:IPAccent() in:account];
    [self text:@"내 아이프린트" frame:NSMakeRect(22,397,208,28) size:20 weight:NSFontWeightSemibold color:NSColor.labelColor in:account];
    [self text:@"ID" frame:NSMakeRect(22,358,208,18) size:12 weight:NSFontWeightMedium color:NSColor.secondaryLabelColor in:account];
    self.userField=[[NSTextField alloc]initWithFrame:NSMakeRect(20,318,212,36)];self.userField.placeholderString=@"아이프린트 ID";[self styleField:self.userField];[account addSubview:self.userField];
    [self text:@"비밀번호" frame:NSMakeRect(22,287,208,18) size:12 weight:NSFontWeightMedium color:NSColor.secondaryLabelColor in:account];
    self.passwordField=[[NSSecureTextField alloc]initWithFrame:NSMakeRect(20,247,212,36)];self.passwordField.placeholderString=@"비밀번호 입력";[self styleField:self.passwordField];[account addSubview:self.passwordField];
    self.login=[self action:@"로그인" frame:NSMakeRect(18,197,216,40) selector:@selector(toggleAuthentication:) primary:YES in:account];
    self.signupButton=[self action:@"새 회원가입…" frame:NSMakeRect(22,161,208,28) selector:@selector(doSignup:) primary:NO in:account];self.signupButton.bordered=NO;self.signupButton.contentTintColor=IPAccent();self.signupButton.font=[NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
    NSBox *line=[[NSBox alloc]initWithFrame:NSMakeRect(22,147,208,1)];line.boxType=NSBoxSeparator;[account addSubview:line];
    self.accountLabel=[self text:@"로그인 전" frame:NSMakeRect(22,96,208,43) size:12 weight:NSFontWeightMedium color:NSColor.secondaryLabelColor in:account];
    self.profileButton=[self action:@"회원 정보 확인" frame:NSMakeRect(18,55,216,32) selector:@selector(doProfile:) primary:NO in:account];self.profileButton.font=[NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
    self.queueButton=[self action:@"서버 대기 문서…" frame:NSMakeRect(18,17,216,32) selector:@selector(doQueue:) primary:NO in:account];self.queueButton.font=[NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
    IPSurface *document=[self surface:NSMakeRect(296,310,600,290) fill:NSColor.controlBackgroundColor radius:18 in:root];
    [self text:@"문서" frame:NSMakeRect(24,249,300,20) size:11 weight:NSFontWeightSemibold color:IPAccent() in:document];
    self.documentState=[self text:@"선택 전" frame:NSMakeRect(440,249,136,20) size:11 weight:NSFontWeightMedium color:NSColor.tertiaryLabelColor in:document];self.documentState.alignment=NSTextAlignmentRight;
    [self text:@"출력할 PDF" frame:NSMakeRect(24,208,350,30) size:21 weight:NSFontWeightSemibold color:NSColor.labelColor in:document];
    self.choose=[self action:@"PDF 선택…" frame:NSMakeRect(428,204,150,38) selector:@selector(doChoose:) primary:NO in:document];
    IPSurface *file=[self surface:NSMakeRect(24,92,552,96) fill:IPBackground() radius:12 in:document];file.strokeColor=nil;
    self.thumbnailView=[[NSImageView alloc]initWithFrame:NSMakeRect(16,10,60,76)];self.thumbnailView.imageScaling=NSImageScaleProportionallyUpOrDown;[self.thumbnailView setAccessibilityLabel:@"PDF 첫 장 미리보기"];[file addSubview:self.thumbnailView];[self updateThumbnail];
    self.fileLabel=[self text:@"PDF 파일을 선택해 주세요" frame:NSMakeRect(92,43,442,37) size:15 weight:NSFontWeightMedium color:NSColor.labelColor in:file];self.fileLabel.maximumNumberOfLines=2;self.fileLabel.lineBreakMode=NSLineBreakByTruncatingMiddle;
    self.fileHint=[self text:@"인쇄할 문서를 PDF 형식으로 준비해 주세요." frame:NSMakeRect(92,17,442,21) size:12 weight:NSFontWeightRegular color:NSColor.secondaryLabelColor in:file];
    [self pill:@"A4" frame:NSMakeRect(24,47,56,28) in:document];
    [self pill:@"흑백" frame:NSMakeRect(90,47,56,28) in:document];
    self.sidesChoice=[[NSPopUpButton alloc]initWithFrame:NSMakeRect(160,45,244,32) pullsDown:NO];
    [self.sidesChoice addItemsWithTitles:@[@"단면",@"양면 · 긴 쪽 넘김",@"양면 · 짧은 쪽 넘김"]];self.sidesChoice.font=[NSFont systemFontOfSize:12 weight:NSFontWeightMedium];self.sidesChoice.target=self;self.sidesChoice.action=@selector(printOptionsChanged:);[self.sidesChoice setAccessibilityLabel:@"인쇄 면 설정"];self.sidesChoice.toolTip=@"긴 쪽: 책처럼 넘김 · 짧은 쪽: 달력처럼 넘김";[document addSubview:self.sidesChoice];
    [self text:@"부수" frame:NSMakeRect(418,51,32,20) size:12 weight:NSFontWeightMedium color:NSColor.secondaryLabelColor in:document];
    self.copiesField=[[NSTextField alloc]initWithFrame:NSMakeRect(454,46,66,30)];[self styleField:self.copiesField];self.copiesField.font=[NSFont systemFontOfSize:13];self.copiesField.alignment=NSTextAlignmentCenter;self.copiesField.stringValue=@"1";self.copiesField.delegate=self;[self.copiesField setAccessibilityLabel:@"인쇄 부수"];self.copiesField.toolTip=@"1~99부";[document addSubview:self.copiesField];
    self.copiesStepper=[[NSStepper alloc]initWithFrame:NSMakeRect(530,47,19,28)];self.copiesStepper.minValue=1;self.copiesStepper.maxValue=99;self.copiesStepper.increment=1;self.copiesStepper.integerValue=1;self.copiesStepper.valueWraps=NO;self.copiesStepper.target=self;self.copiesStepper.action=@selector(stepCopies:);[self.copiesStepper setAccessibilityLabel:@"부수 조절"];[document addSubview:self.copiesStepper];
    [self symbol:@"arrow.down" frame:NSMakeRect(584,278,24,24) size:19 color:IPAccent() in:root];
    IPSurface *actions=[self surface:NSMakeRect(296,122,600,148) fill:NSColor.controlBackgroundColor radius:18 in:root];
    [self text:@"인쇄" frame:NSMakeRect(24,110,552,20) size:11 weight:NSFontWeightSemibold color:IPAccent() in:actions];
    self.sendHint=[self text:@"로그인 후 보낼 수 있어요." frame:NSMakeRect(24,63,300,26) size:13 weight:NSFontWeightMedium color:NSColor.labelColor in:actions];
    self.send=[self action:@"인쇄 보내기" frame:NSMakeRect(348,54,232,44) selector:@selector(doSend:) primary:YES in:actions];
    [self text:@"전송 후 복합기에서 로그인해 대기 문서를 출력하세요." frame:NSMakeRect(24,19,552,22) size:12 weight:NSFontWeightRegular color:NSColor.secondaryLabelColor in:actions];
    IPSurface *status=[self surface:NSMakeRect(24,20,872,86) fill:NSColor.controlBackgroundColor radius:14 in:root];
    [self text:@"진행 상태" frame:NSMakeRect(20,62,832,16) size:10 weight:NSFontWeightSemibold color:NSColor.tertiaryLabelColor in:status];
    self.activity=[[NSProgressIndicator alloc]initWithFrame:NSMakeRect(832,59,18,18)];self.activity.style=NSProgressIndicatorStyleSpinning;self.activity.controlSize=NSControlSizeSmall;self.activity.displayedWhenStopped=NO;[status addSubview:self.activity];
    self.status=[self text:@"기존 계정으로 로그인하고 PDF를 선택해 주세요." frame:NSMakeRect(20,21,832,37) size:12 weight:NSFontWeightRegular color:NSColor.secondaryLabelColor in:status];
    self.progress=[[NSProgressIndicator alloc]initWithFrame:NSMakeRect(20,10,832,5)];self.progress.indeterminate=NO;self.progress.minValue=0;self.progress.maxValue=1;[status addSubview:self.progress];
    if(localProfilePreview){
        self.window.title=@"네이티브 회원정보 화면 시험 (로컬)";self.signedInUser=@"NativeTest";self.userField.stringValue=@"NativeTest";self.passwordField.stringValue=@"Native-Test-17";
        self.accountLabel.stringValue=@"가나다 · 적립금 0원 · 지원금 0원";
    }
    if(localRegistrationPreview){self.window.title=@"네이티브 회원가입 화면 시험 (로컬)";[self doSignup:nil];}
    if(localDashboardPreview)self.window.title=@"iPrint UI 미리보기 · 로컬";
    if(localNetworkPreview){self.userField.stringValue=@"NativeTest";self.passwordField.stringValue=@"Native-Test-17";
        if(localPreviewPDFPath.length){self.pdfURL=[NSURL fileURLWithPath:localPreviewPDFPath];self.fileLabel.stringValue=self.pdfURL.lastPathComponent;[self updateThumbnail];}
    }
    [self refresh];[self.window makeKeyAndOrderFront:nil];[NSApp activateIgnoringOtherApps:YES];
    if(localProfilePreview)dispatch_async(dispatch_get_main_queue(),^{[self presentProfile:@{@"user":@"NativeTest",@"name":@"가나다",@"phone":@"01012345678",@"email":@"native@example.com"}];});
}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)app{return YES;}
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication*)app {if(self.busy){NSBeep();return NSTerminateCancel;}return NSTerminateNow;}
- (void)applicationWillTerminate:(NSNotification*)notification {[self discardJob];self.passwordField.stringValue=@"";self.signupPassword.stringValue=@"";self.signupRepeat.stringValue=@"";}
- (BOOL)windowShouldClose:(NSWindow*)sender {if(self.busy){NSBeep();return NO;}return YES;}
- (void)refresh {
    self.login.enabled=!self.busy;self.login.title=self.signedInUser ? @"로그아웃" : @"로그인";self.choose.enabled=!self.busy;
    self.sidesChoice.enabled=!self.busy&&!self.submissionCompleted;self.copiesField.enabled=!self.busy&&!self.submissionCompleted;self.copiesStepper.enabled=!self.busy&&!self.submissionCompleted;
    self.send.enabled=!self.busy&&self.pdfURL!=nil&&self.signedInUser!=nil&&!self.submissionCompleted;
    self.userField.enabled=!self.busy&&self.signedInUser==nil;self.passwordField.enabled=!self.busy&&self.signedInUser==nil;
    self.profileButton.enabled=!self.busy&&self.signedInUser!=nil;
    self.profileCancel.enabled=!self.busy;
    self.queueButton.enabled=!self.busy&&self.signedInUser!=nil;
    self.queueReload.enabled=!self.busy;self.queueClose.enabled=!self.busy;
    self.queueDelete.enabled=!self.busy&&self.queueFresh&&self.queueTable.selectedRow>=0&&self.queueTable.selectedRow<(NSInteger)self.queueJobs.count;
    self.queueTable.enabled=!self.busy;
    self.signupButton.enabled=!self.busy;
    if(self.signupWindow)for(NSTextField *field in @[self.signupID,self.signupName,self.signupPassword,self.signupRepeat,self.signupPhone,self.signupEmail])field.enabled=!self.busy&&!self.signupNeedsVerification;
    self.signupAgree.enabled=!self.busy&&!self.signupNeedsVerification;
    self.signupSubmit.enabled=!self.busy&&!self.signupNeedsVerification&&self.signupAgree.state==NSControlStateValueOn;
    self.signupCancel.enabled=!self.busy;
    self.accountLabel.textColor=self.signedInUser ? NSColor.labelColor : NSColor.secondaryLabelColor;
    self.documentState.stringValue=self.submissionCompleted ? @"전송 완료" : self.prnPath ? @"문서 준비됨" : self.pdfURL ? @"선택 완료" : @"선택 전";
    self.documentState.textColor=self.submissionCompleted ? NSColor.systemGreenColor : NSColor.secondaryLabelColor;
    self.fileHint.stringValue=self.submissionCompleted ? @"복합기에서 출력하세요. 다시 보내려면 PDF를 다시 선택해 주세요." : self.prnPath ? [NSString stringWithFormat:@"%lu페이지 · 전송 결과는 아래 진행 상태를 확인해 주세요.",(unsigned long)self.pages] : self.pdfURL ? @"‘인쇄 보내기’를 누르면 자동으로 준비해 전송합니다." : @"인쇄할 문서를 PDF 형식으로 준비해 주세요.";
    self.sendHint.stringValue=self.submissionCompleted ? @"복합기에서 출력해 주세요." : !self.signedInUser ? @"로그인 후 보낼 수 있어요." : !self.pdfURL ? @"인쇄할 PDF를 선택해 주세요." : [NSString stringWithFormat:@"%@ · %@부",self.sidesChoice.titleOfSelectedItem,self.copiesField.stringValue];
    self.send.title=self.submissionCompleted ? @"전송 완료" : @"인쇄 보내기";
    if(self.busy)[self.activity startAnimation:nil];else[self.activity stopAnimation:nil];
}
- (void)run:(NSString*)message work:(NSString*(^)(void))work {
    self.busy=YES;self.status.stringValue=message;[self refresh];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{@autoreleasepool{
        NSString *result=nil,*error=nil;@try{result=work();}@catch(NSException *e){error=e.reason ?: @"작업에 실패했습니다.";}
        dispatch_async(dispatch_get_main_queue(),^{self.busy=NO;self.status.stringValue=error ?: result ?: @"완료";[self refresh];if(error){if(self.queueWindow)self.queueStatus.stringValue=error;NSAlert *a=[NSAlert new];a.messageText=@"작업을 완료하지 못했습니다";a.informativeText=error;[a addButtonWithTitle:@"확인"];[a beginSheetModalForWindow:self.signupWindow ?: self.profileWindow ?: self.queueWindow ?: self.window completionHandler:nil];}});
    }});
}
- (void)toggleAuthentication:(id)sender {
    if(self.busy)return;
    if(self.signedInUser)[self doLogout:sender];else[self doLogin:sender];
}
- (void)doLogin:(id)sender {
    NSString *user=[self.userField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];NSString *password=self.passwordField.stringValue;
    [self run:@"로그인 중…" work:^NSString*{
        IPConnection *a=[[IPConnection alloc]initWithHost:schoolHost port:schoolPort];NSDictionary *account=[a authenticateUser:user password:password];[a close];
        dispatch_async(dispatch_get_main_queue(),^{self.signedInUser=user;self.accountLabel.stringValue=[NSString stringWithFormat:@"%@ · 적립금 %@원 · 지원금 %@원",[account[@"name"] length]?account[@"name"]:user,account[@"credit"],account[@"support"]];});
        return @"로그인했습니다. PDF를 선택하고 ‘인쇄 보내기’를 눌러 주세요.";
    }];
}
- (void)doLogout:(id)sender {self.signedInUser=nil;self.passwordField.stringValue=@"";self.accountLabel.stringValue=@"로그인 전";self.status.stringValue=@"로그아웃했습니다.";[self refresh];}
- (void)doQueue:(id)sender {
    if(self.busy || !self.signedInUser || self.queueWindow || self.signupWindow || self.profileWindow)return;
    NSPanel *panel=[[NSPanel alloc]initWithContentRect:NSMakeRect(0,0,780,460) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    panel.title=@"서버 대기 문서";panel.backgroundColor=IPBackground();IPSurface *background=[[IPSurface alloc]initWithFrame:NSMakeRect(0,0,780,460)];background.fillColor=IPBackground();panel.contentView=background;self.queueWindow=panel;self.queueJobs=@[];self.queueFresh=NO;
    [self text:@"출력을 기다리는 문서" frame:NSMakeRect(24,406,732,30) size:23 weight:NSFontWeightSemibold color:NSColor.labelColor in:panel.contentView];
    [self text:@"현재 로그인한 계정으로 서버에 보낸 문서입니다." frame:NSMakeRect(24,378,732,22) size:12 weight:NSFontWeightRegular color:NSColor.secondaryLabelColor in:panel.contentView];
    NSScrollView *scroll=[[NSScrollView alloc]initWithFrame:NSMakeRect(24,130,732,238)];scroll.hasVerticalScroller=YES;scroll.hasHorizontalScroller=YES;scroll.borderType=NSLineBorder;
    NSTableView *table=[[NSTableView alloc]initWithFrame:scroll.bounds];table.dataSource=self;table.delegate=self;table.rowHeight=34;table.intercellSpacing=NSMakeSize(6,0);table.usesAlternatingRowBackgroundColors=YES;table.allowsMultipleSelection=NO;table.allowsEmptySelection=YES;table.columnAutoresizingStyle=NSTableViewLastColumnOnlyAutoresizingStyle;
    NSArray *identifiers=@[@"title",@"date",@"paper",@"pages"],*titles=@[@"문서명",@"접수 시각",@"용지",@"페이지"];
    CGFloat widths[]={350,190,70,70};for(NSUInteger i=0;i<identifiers.count;i++){NSTableColumn *column=[[NSTableColumn alloc]initWithIdentifier:identifiers[i]];column.title=titles[i];column.width=widths[i];column.minWidth=50;column.editable=NO;[table addTableColumn:column];}
    [table setAccessibilityLabel:@"서버 출력 대기 문서 목록"];self.queueTable=table;scroll.documentView=table;[panel.contentView addSubview:scroll];
    self.queueStatus=[self text:@"대기 문서를 불러오고 있습니다…" frame:NSMakeRect(24,69,732,49) size:12 weight:NSFontWeightRegular color:NSColor.secondaryLabelColor in:panel.contentView];self.queueStatus.maximumNumberOfLines=3;
    self.queueReload=[self action:@"새로고침" frame:NSMakeRect(18,16,120,38) selector:@selector(reloadQueue:) primary:NO in:panel.contentView];
    self.queueDelete=[self action:@"선택 문서 삭제…" frame:NSMakeRect(146,16,162,38) selector:@selector(deleteQueueJob:) primary:NO in:panel.contentView];
    self.queueClose=[self action:@"닫기" frame:NSMakeRect(640,16,122,38) selector:@selector(closeQueue:) primary:YES in:panel.contentView];
    [self.window beginSheet:panel completionHandler:nil];[self reloadQueue:nil];
}
- (NSInteger)numberOfRowsInTableView:(NSTableView*)table {return self.queueJobs.count;}
- (NSView*)tableView:(NSTableView*)table viewForTableColumn:(NSTableColumn*)column row:(NSInteger)row {
    NSTableCellView *cell=[table makeViewWithIdentifier:column.identifier owner:self];
    if(!cell){
        cell=[[NSTableCellView alloc]initWithFrame:NSMakeRect(0,0,column.width,table.rowHeight)];cell.identifier=column.identifier;
        NSTextField *field=[NSTextField labelWithString:@""];field.frame=NSMakeRect(6,8,column.width-12,18);field.autoresizingMask=NSViewWidthSizable;
        field.font=[NSFont systemFontOfSize:12];field.lineBreakMode=NSLineBreakByTruncatingMiddle;field.maximumNumberOfLines=1;
        if([column.identifier isEqualToString:@"pages"])field.alignment=NSTextAlignmentRight;
        cell.textField=field;[cell addSubview:field];
    }
    id value=self.queueJobs[row][column.identifier];cell.textField.stringValue=[value description] ?: @"";cell.toolTip=cell.textField.stringValue;return cell;
}
- (void)tableViewSelectionDidChange:(NSNotification*)note {[self refresh];}
- (void)applyQueueJobs:(NSArray*)jobs {
    self.queueJobs=jobs;self.queueFresh=YES;[self.queueTable deselectAll:nil];[self.queueTable reloadData];
    self.queueStatus.stringValue=jobs.count ? [NSString stringWithFormat:@"대기 문서 %lu개 · 삭제할 문서를 선택해 주세요. 출력 중인 문서는 취소되지 않을 수 있습니다.",(unsigned long)jobs.count] : @"서버에서 대기 중인 문서가 없습니다.";
}
- (void)reloadQueue:(id)sender {
    if(self.busy || !self.queueWindow || !self.signedInUser)return;
    self.queueFresh=NO;NSString *user=self.signedInUser,*password=self.passwordField.stringValue;self.queueStatus.stringValue=@"서버 대기 문서를 확인하고 있습니다…";
    [self run:@"서버 대기 문서 조회 중…" work:^NSString*{
        NSArray *jobs=IPFetchWaitJobs(schoolHost,schoolPort,user,password);
        dispatch_async(dispatch_get_main_queue(),^{[self applyQueueJobs:jobs];});
        return [NSString stringWithFormat:@"서버 대기 문서 %lu개를 확인했습니다.",(unsigned long)jobs.count];
    }];
}
- (void)deleteQueueJob:(id)sender {
    NSInteger row=self.queueTable.selectedRow;
    if(self.busy || !self.queueFresh || !self.signedInUser || row<0 || row>=(NSInteger)self.queueJobs.count)return;
    NSDictionary *job=self.queueJobs[row];NSString *user=self.signedInUser,*password=self.passwordField.stringValue;
    NSAlert *alert=[NSAlert new];alert.alertStyle=NSAlertStyleWarning;alert.messageText=@"이 대기 문서를 삭제할까요?";
    alert.informativeText=[NSString stringWithFormat:@"%@\n%@ · %@페이지\n서버의 대기 문서만 삭제합니다. Mac의 원본 PDF는 유지됩니다. 이미 출력을 시작한 문서는 취소되지 않을 수 있습니다.",job[@"title"],job[@"date"],job[@"pages"]];
    [alert addButtonWithTitle:@"취소"];[alert addButtonWithTitle:@"대기 문서 삭제"];
    [alert beginSheetModalForWindow:self.queueWindow completionHandler:^(NSModalResponse response){
        if(response!=NSAlertSecondButtonReturn || self.busy || ![self.signedInUser isEqualToString:user])return;
        self.queueFresh=NO;self.queueStatus.stringValue=@"현재 대기 목록을 확인한 뒤 선택한 문서의 삭제를 요청합니다…";
        [self run:@"대기 문서 삭제 및 결과 확인 중…" work:^NSString*{
            NSArray *jobs=IPDeleteWaitJob(schoolHost,schoolPort,user,password,job);
            dispatch_async(dispatch_get_main_queue(),^{[self applyQueueJobs:jobs];self.queueStatus.stringValue=@"삭제 요청 후 해당 문서가 서버 대기 목록에서 사라진 것을 확인했습니다.";});
            return @"선택한 문서가 서버 대기 목록에서 사라진 것을 확인했습니다.";
        }];
    }];
}
- (void)closeQueue:(id)sender {
    if(self.busy)return;[self.window endSheet:self.queueWindow];self.queueWindow=nil;self.queueJobs=nil;self.queueFresh=NO;
    self.queueTable=nil;self.queueStatus=nil;self.queueReload=nil;self.queueDelete=nil;self.queueClose=nil;[self refresh];
}
- (void)doSignup:(id)sender {
    if(self.signupWindow || self.profileWindow || self.queueWindow || self.busy)return;
    NSString *path=[NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"Source/RegistrationTerms.txt"];
    NSString *terms=localRegistrationPreview ? @"로컬 화면 시험입니다. 실제 약관 동의나 가입은 이루어지지 않습니다." : [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    if(!terms.length){self.status.stringValue=@"이용약관 파일을 읽을 수 없어 가입 화면을 열지 못했습니다.";return;}
    self.signupNeedsVerification=NO;
    NSPanel *panel=[[NSPanel alloc]initWithContentRect:NSMakeRect(0,0,640,690) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];panel.title=@"새 회원가입";panel.backgroundColor=IPBackground();self.signupWindow=panel;
    [self text:@"아이프린트 시작하기" frame:NSMakeRect(25,640,590,30) size:23 weight:NSFontWeightSemibold color:NSColor.labelColor in:panel.contentView];
    [self text:@"가입 정보는 아이프린트 서버로 전송됩니다. 한글 이름을 입력해 주세요." frame:NSMakeRect(25,612,590,23) size:12 weight:NSFontWeightRegular color:NSColor.secondaryLabelColor in:panel.contentView];
    [self surface:NSMakeRect(16,343,608,264) fill:NSColor.controlBackgroundColor radius:14 in:panel.contentView];
    NSArray *labels=@[@"새 ID",@"이름",@"비밀번호",@"비밀번호 확인",@"연락처",@"이메일"];
    for(NSUInteger i=0;i<labels.count;i++){
        CGFloat y=565-i*42;[self text:labels[i] frame:NSMakeRect(30,y+5,110,23) size:12 weight:NSFontWeightMedium color:NSColor.secondaryLabelColor in:panel.contentView];
        NSTextField *field=(i==2 || i==3) ? [NSSecureTextField new] : [NSTextField new];field.frame=NSMakeRect(145,y,460,34);[self styleField:field];[panel.contentView addSubview:field];
        switch(i){case 0:self.signupID=field;field.placeholderString=@"영문·숫자·점·밑줄·하이픈 5~20자";break;case 1:self.signupName=field;field.placeholderString=@"최대 20바이트(한글 10자)";break;case 2:self.signupPassword=(NSSecureTextField*)field;field.placeholderString=@"영문·숫자·기호 5~20자";break;case 3:self.signupRepeat=(NSSecureTextField*)field;break;case 4:self.signupPhone=field;field.placeholderString=@"하이픈 없이 숫자만 입력";break;case 5:self.signupEmail=field;field.placeholderString=@"본인의 이메일 주소";break;}
    }
    [self text:@"원본 설치파일에 포함된 이용약관·개인정보 안내" frame:NSMakeRect(25,309,590,23) size:11 weight:NSFontWeightMedium color:NSColor.secondaryLabelColor in:panel.contentView];
    NSScrollView *scroll=[[NSScrollView alloc]initWithFrame:NSMakeRect(25,118,590,184)];scroll.hasVerticalScroller=YES;scroll.borderType=NSLineBorder;
    NSTextView *view=[[NSTextView alloc]initWithFrame:NSMakeRect(0,0,570,184)];view.editable=NO;view.selectable=YES;view.richText=NO;view.font=[NSFont systemFontOfSize:12];view.textContainerInset=NSMakeSize(10,10);view.string=terms;view.textContainer.widthTracksTextView=YES;view.verticallyResizable=YES;view.autoresizingMask=NSViewWidthSizable;scroll.documentView=view;[panel.contentView addSubview:scroll];
    self.signupAgree=[NSButton checkboxWithTitle:localRegistrationPreview ? @"로컬 시험용 확인 (실제 약관 동의 없음)" : @"위 이용약관 및 개인정보 안내를 확인하고 동의합니다." target:self action:@selector(signupConsentChanged:)];self.signupAgree.frame=NSMakeRect(25,76,590,30);self.signupAgree.font=[NSFont systemFontOfSize:12];self.signupAgree.state=NSControlStateValueOff;[panel.contentView addSubview:self.signupAgree];
    self.signupCancel=[self action:@"닫기" frame:NSMakeRect(355,20,100,38) selector:@selector(closeSignup:) primary:NO in:panel.contentView];
    self.signupSubmit=[self action:@"동의하고 가입" frame:NSMakeRect(465,20,150,38) selector:@selector(submitSignup:) primary:YES in:panel.contentView];
    [self.window beginSheet:panel completionHandler:nil];[self refresh];
}
- (void)signupConsentChanged:(id)sender {[self refresh];}
- (void)closeSignup:(id)sender {
    self.signupPassword.stringValue=@"";self.signupRepeat.stringValue=@"";[self.window endSheet:self.signupWindow];self.signupWindow=nil;
    self.signupID=nil;self.signupName=nil;self.signupPassword=nil;self.signupRepeat=nil;self.signupPhone=nil;self.signupEmail=nil;
    self.signupAgree=nil;self.signupSubmit=nil;self.signupCancel=nil;self.signupNeedsVerification=NO;
}
- (void)submitSignup:(id)sender {
    if(self.busy || self.signupNeedsVerification || self.signupAgree.state!=NSControlStateValueOn)return;
    NSCharacterSet *trim=NSCharacterSet.whitespaceAndNewlineCharacterSet;
    NSString *user=[self.signupID.stringValue stringByTrimmingCharactersInSet:trim],*password=self.signupPassword.stringValue;
    NSDictionary *profile=@{@"name":[[self.signupName.stringValue stringByTrimmingCharactersInSet:trim] precomposedStringWithCanonicalMapping],@"phone":[self.signupPhone.stringValue stringByTrimmingCharactersInSet:trim],@"email":[self.signupEmail.stringValue stringByTrimmingCharactersInSet:trim]};
    @try {
        if(![password isEqualToString:self.signupRepeat.stringValue])IPFail(@"비밀번호와 확인 입력이 다릅니다.");
        IPRegistrationRequest(user,password,@"00000",profile);
    }@catch(NSException *e){NSAlert *alert=[NSAlert new];alert.messageText=@"가입 정보를 확인해 주세요";alert.informativeText=e.reason;[alert addButtonWithTitle:@"확인"];[alert beginSheetModalForWindow:self.signupWindow completionHandler:nil];return;}
    [self run:@"ID 확인 및 회원가입 중…" work:^NSString*{
        IPConnection *c=[[IPConnection alloc]initWithHost:schoolHost port:schoolPort];
        @try {[c registerUser:user password:password profile:profile];}
        @catch(NSException *e){BOOL uncertain=c.registrationMayHaveBeenSent;[c close];if(uncertain)dispatch_async(dispatch_get_main_queue(),^{self.signupNeedsVerification=YES;});@throw;}
        [c close];
        NSDictionary *account=nil;
        @try {IPConnection *a=[[IPConnection alloc]initWithHost:schoolHost port:schoolPort];account=[a authenticateUser:user password:password];[a close];}
        @catch(NSException *e){dispatch_async(dispatch_get_main_queue(),^{[self closeSignup:nil];[self doLogout:nil];self.userField.stringValue=user;});return @"서버가 가입을 승인했습니다. 자동 로그인 확인은 완료하지 못했으니 새 ID로 로그인해 주세요. 가입을 다시 시도하지 마세요.";}
        BOOL nameMatches=[[account[@"name"] precomposedStringWithCanonicalMapping] isEqualToString:profile[@"name"]];
        dispatch_async(dispatch_get_main_queue(),^{[self closeSignup:nil];self.signedInUser=user;self.userField.stringValue=user;self.passwordField.stringValue=password;self.accountLabel.stringValue=[NSString stringWithFormat:@"%@ · 적립금 %@원 · 지원금 %@원",[account[@"name"] length]?account[@"name"]:user,account[@"credit"],account[@"support"]];});
        return nameMatches ? @"가입 후 로그인과 한글 이름 조회까지 확인했습니다." : @"가입과 로그인은 확인됐지만 서버의 이름이 입력한 이름과 다릅니다. 회원정보를 확인해 주세요.";
    }];
}
- (NSDictionary*)fetchProfileForUser:(NSString*)user password:(NSString*)password {
    IPConnection *a=[[IPConnection alloc]initWithHost:schoolHost port:schoolPort];[a authenticateUser:user password:password];[a close];
    IPConnection *p=[[IPConnection alloc]initWithHost:schoolHost port:schoolPort];NSDictionary *profile=[p profileForUser:user password:password];[p close];return profile;
}
- (void)doProfile:(id)sender {
    NSString *user=self.signedInUser,*password=self.passwordField.stringValue;
    [self run:@"회원정보 조회 중…" work:^NSString*{
        NSDictionary *profile=[self fetchProfileForUser:user password:password];
        dispatch_async(dispatch_get_main_queue(),^{[self presentProfile:profile];});
        return @"회원정보를 불러왔습니다. 등록된 내용을 확인해 주세요.";
    }];
}
- (void)presentProfile:(NSDictionary*)profile {
    NSPanel *panel=[[NSPanel alloc]initWithContentRect:NSMakeRect(0,0,590,408) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    panel.title=@"회원 정보 확인";panel.backgroundColor=IPBackground();self.profileWindow=panel;
    [self text:@"회원 정보 확인" frame:NSMakeRect(25,351,540,30) size:23 weight:NSFontWeightSemibold color:NSColor.labelColor in:panel.contentView];
    [self text:@"아이프린트에 등록된 회원정보입니다." frame:NSMakeRect(25,328,540,22) size:12 weight:NSFontWeightRegular color:NSColor.secondaryLabelColor in:panel.contentView];
    [self surface:NSMakeRect(16,124,558,198) fill:NSColor.controlBackgroundColor radius:14 in:panel.contentView];
    NSArray *labels=@[@"ID",@"이름",@"연락처",@"이메일"];
    NSArray *values=@[self.signedInUser,profile[@"name"],profile[@"phone"],profile[@"email"]];
    for(NSUInteger i=0;i<4;i++){
        CGFloat y=274-i*46;[self text:labels[i] frame:NSMakeRect(30,y+5,85,24) size:12 weight:NSFontWeightMedium color:NSColor.secondaryLabelColor in:panel.contentView];
        NSTextField *field=[self text:values[i] frame:NSMakeRect(130,y+4,429,26) size:14 weight:NSFontWeightRegular color:NSColor.labelColor in:panel.contentView];
        field.editable=NO;field.selectable=YES;field.maximumNumberOfLines=1;field.lineBreakMode=NSLineBreakByTruncatingMiddle;field.toolTip=values[i];
    }
    [self text:@"조회 전용 화면입니다. 회원정보는 변경할 수 없습니다." frame:NSMakeRect(25,78,540,28) size:12 weight:NSFontWeightRegular color:NSColor.secondaryLabelColor in:panel.contentView];
    self.profileCancel=[self action:@"닫기" frame:NSMakeRect(448,14,120,38) selector:@selector(closeProfile:) primary:YES in:panel.contentView];
    self.profileCancel.keyEquivalent=@"\r";panel.initialFirstResponder=self.profileCancel;
    [self.window beginSheet:panel completionHandler:nil];[self refresh];
}
- (void)closeProfile:(id)sender {
    [self.window endSheet:self.profileWindow];self.profileWindow=nil;self.profileCancel=nil;
}
- (void)discardJob {if(self.folder)[[NSFileManager defaultManager]removeItemAtPath:self.folder error:nil];self.folder=nil;self.prnPath=nil;self.progress.doubleValue=0;}
- (void)updateThumbnail {
    NSUInteger generation=++self.thumbnailGeneration;
    NSURL *url=self.pdfURL;
    self.thumbnailView.image=[[NSImage imageWithSystemSymbolName:@"doc.richtext" accessibilityDescription:nil] imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:31 weight:NSFontWeightMedium]];
    self.thumbnailView.contentTintColor=IPAccent();
    self.thumbnailView.toolTip=url ? @"첫 장 미리보기를 불러오는 중…" : @"PDF를 선택하면 첫 장을 보여줍니다.";
    if(!url)return;
    // Render only the first page at thumbnail size, without a disk cache or uploads.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{@autoreleasepool{
        BOOL scoped=[url startAccessingSecurityScopedResource];
        NSImage *image=nil;
        @try {
            PDFDocument *pdf=[[PDFDocument alloc]initWithURL:url];
            if(pdf && !pdf.isLocked && pdf.pageCount)image=[[pdf pageAtIndex:0] thumbnailOfSize:NSMakeSize(120,152) forBox:kPDFDisplayBoxCropBox];
        }@catch(NSException *exception){image=nil;}
        @finally{if(scoped)[url stopAccessingSecurityScopedResource];}
        dispatch_async(dispatch_get_main_queue(),^{
            if(generation!=self.thumbnailGeneration)return;
            if(image){self.thumbnailView.image=image;self.thumbnailView.contentTintColor=nil;}
            self.thumbnailView.toolTip=image ? @"PDF 첫 장 미리보기 · 실제 출력은 A4 흑백입니다." : @"첫 장을 미리 볼 수 없습니다. 암호가 없는 정상 PDF인지 확인해 주세요.";
        });
    }});
}
- (void)doChoose:(id)sender {
    NSOpenPanel *p=[NSOpenPanel openPanel];p.allowedContentTypes=@[UTTypePDF];p.canChooseFiles=YES;p.canChooseDirectories=NO;p.allowsMultipleSelection=NO;
    [p beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result){if(result==NSModalResponseOK){[self discardJob];self.submissionCompleted=NO;self.pdfURL=p.URL;self.fileLabel.stringValue=self.pdfURL.lastPathComponent;[self updateThumbnail];self.status.stringValue=@"‘인쇄 보내기’를 누르면 문서 준비와 전송이 자동으로 진행됩니다.";[self refresh];}}];
}
- (NSUInteger)selectedCopies {
    NSString *value=[self.copiesField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if(!value.length || [value rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"0123456789"].invertedSet].location!=NSNotFound || value.length>2 || value.integerValue<1 || value.integerValue>99)IPFail(@"부수는 1~99 사이의 숫자로 입력해 주세요.");
    return value.integerValue;
}
- (void)printOptionsChanged:(id)sender {
    if(self.busy || self.submissionCompleted)return;
    [self discardJob];
    @try{self.copiesStepper.integerValue=[self selectedCopies];}@catch(NSException *e){}
    self.status.stringValue=@"인쇄 설정을 변경했습니다. ‘인쇄 보내기’를 누르면 이 설정으로 준비합니다.";[self refresh];
}
- (void)controlTextDidChange:(NSNotification*)notification {if(notification.object==self.copiesField)[self printOptionsChanged:nil];}
- (void)stepCopies:(id)sender {self.copiesField.stringValue=self.copiesStepper.stringValue;[self printOptionsChanged:sender];}
- (NSString*)prepareDocument {
    BOOL scoped=[self.pdfURL startAccessingSecurityScopedResource];
    @try {
        PDFDocument *pdf=[[PDFDocument alloc]initWithURL:self.pdfURL];
        if(!pdf || pdf.isLocked || !pdf.pageCount)IPFail(@"암호가 걸리지 않은 정상적인 PDF를 선택해 주세요.");
        self.pages=pdf.pageCount;if(self.pages>32767/self.jobCopies)IPFail(@"페이지 수가 시험판 지원 범위를 넘습니다.");
        NSString *root=NSProcessInfo.processInfo.environment[@"IPRINT_NATIVE_DATA_DIR"] ?: [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Yonsei iPrint Native"];
        NSString *uid=[[NSUUID UUID].UUIDString lowercaseString];self.folder=[[root stringByAppendingPathComponent:@"Jobs"]stringByAppendingPathComponent:uid];
        NSError *err=nil;[[NSFileManager defaultManager]createDirectoryAtPath:self.folder withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:&err];if(err)IPFail(@"문서 준비 폴더를 만들 수 없습니다.");
        self.jobName=[@"iPrint-Native-" stringByAppendingString:uid];NSString *psPath=[self.folder stringByAppendingPathComponent:@"document.ps"];
        NSString *resources=NSBundle.mainBundle.resourcePath;NSString *gs=[resources stringByAppendingPathComponent:@"ghostscript/bin/gs"];
        if(![[NSFileManager defaultManager]isExecutableFileAtPath:gs])IPFail(@"PDF 변환기가 누락됐습니다. 앱을 다시 복사해 주세요.");
        NSTask *t=[NSTask new];t.executableURL=[NSURL fileURLWithPath:gs];t.arguments=@[@"-q",@"-dSAFER",@"-dBATCH",@"-dNOPAUSE",@"-sDEVICE=ps2write",@"-sPAPERSIZE=a4",@"-dFIXEDMEDIA",@"-dPDFFitPage",@"-r600",@"-dNoOutputFonts",@"-dCompressPages=true",[@"-sICCProfilesDir=" stringByAppendingString:[resources stringByAppendingPathComponent:@"ghostscript/iccprofiles/"]],[@"-sOutputFile=" stringByAppendingString:psPath],@"-c",[NSString stringWithFormat:@"<< /PSDocOptions (%@) >> setdistillerparams",IPPostScriptOptions(self.jobCopies,self.jobDuplex)],@"-f",self.pdfURL.path];
        NSString *base=[resources stringByAppendingPathComponent:@"ghostscript"];NSMutableDictionary *env=[NSProcessInfo.processInfo.environment mutableCopy];
        for(NSString *k in [env.allKeys copy])if([k hasPrefix:@"DYLD_"] || [k hasPrefix:@"_PYI_"] || [k hasPrefix:@"GS_"]) [env removeObjectForKey:k];
        env[@"GS_LIB"]=[NSString stringWithFormat:@"%@/Resource/Init:%@/lib:%@/Resource/Font",base,base,base];env[@"GS_FONTPATH"]=[base stringByAppendingPathComponent:@"Resource/Font"];t.environment=env;
        NSString *log=[self.folder stringByAppendingPathComponent:@"conversion.log"];[[NSFileManager defaultManager]createFileAtPath:log contents:nil attributes:@{NSFilePosixPermissions:@0600}];NSFileHandle *handle=[NSFileHandle fileHandleForWritingAtPath:log];t.standardOutput=handle;t.standardError=handle;t.standardInput=NSFileHandle.fileHandleWithNullDevice;
        if(![t launchAndReturnError:&err]){[handle closeFile];IPFail(@"PDF 변환기를 시작할 수 없습니다.");}
        NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:300];while(t.running && deadline.timeIntervalSinceNow>0)[NSThread sleepForTimeInterval:.1];
        if(t.running){[t terminate];[handle closeFile];IPFail(@"문서 변환 시간이 5분을 넘었습니다. PDF를 나누어 시도해 주세요.");}
        [t waitUntilExit];[handle closeFile];if(t.terminationStatus)IPFail(@"PDF 변환에 실패했습니다. 다른 PDF로 시도해 주세요.");
        NSData *ps=[NSData dataWithContentsOfFile:psPath];if(ps.length<10 || memcmp(ps.bytes,"%!PS-Adobe",10))IPFail(@"변환된 문서 형식이 올바르지 않습니다.");
        NSString *psText=[[NSString alloc]initWithData:ps encoding:NSISOLatin1StringEncoding];NSRegularExpression *re=[NSRegularExpression regularExpressionWithPattern:@"(?m)^%%Pages: +([0-9]+)\\s*$" options:0 error:nil];NSArray *matches=[re matchesInString:psText options:0 range:NSMakeRange(0,psText.length)];
        if(!matches.count)IPFail(@"변환된 문서의 페이지 수를 확인할 수 없습니다.");for(NSTextCheckingResult *m in matches)if([[psText substringWithRange:[m rangeAtIndex:1]]integerValue]!=self.pages)IPFail(@"PDF와 변환된 문서의 페이지 수가 다릅니다.");
        NSData *wrapped=IPWrapPostScript(ps,self.jobName,dateStamp(),osVersion());NSString *out=[self.folder stringByAppendingPathComponent:@"document.prn"];
        if(![wrapped writeToFile:out options:NSDataWritingAtomic error:&err])IPFail(@"변환된 문서를 저장할 수 없습니다.");
        [[NSFileManager defaultManager]removeItemAtPath:psPath error:nil];[[NSFileManager defaultManager]removeItemAtPath:log error:nil];self.prnPath=out;
        return [NSString stringWithFormat:@"%lu페이지 준비 완료 · %.1fMB\n‘서버로 보내기’를 누르면 학교 서버로 전송합니다.",(unsigned long)self.pages,wrapped.length/1000000.0];
    }@finally{if(scoped)[self.pdfURL stopAccessingSecurityScopedResource];}
}
- (void)doSend:(id)sender {
    if(self.busy || self.submissionCompleted || !self.signedInUser || !self.pdfURL)return;
    @try{self.jobCopies=[self selectedCopies];self.jobDuplex=self.sidesChoice.indexOfSelectedItem;IPPostScriptOptions(self.jobCopies,self.jobDuplex);}
    @catch(NSException *e){NSAlert *alert=[NSAlert new];alert.messageText=@"인쇄 설정을 확인해 주세요";alert.informativeText=e.reason;[alert addButtonWithTitle:@"확인"];[alert beginSheetModalForWindow:self.window completionHandler:nil];return;}
    NSString *user=self.signedInUser,*password=self.passwordField.stringValue;
    if(!self.prnPath)[self discardJob];
    [self run:self.prnPath ? @"학교 서버로 전송 중…" : @"인쇄할 문서를 자동으로 준비하고 있습니다…" work:^NSString*{
        if(!self.prnPath)[self prepareDocument];
        dispatch_async(dispatch_get_main_queue(),^{self.status.stringValue=@"문서 준비 완료 · 학교 서버로 전송 중…";[self refresh];});
        IPConnection *a=[[IPConnection alloc]initWithHost:schoolHost port:schoolPort];NSDictionary *account=[a authenticateUser:user password:password];[a close];
        NSData *document=[NSData dataWithContentsOfFile:self.prnPath];if(!document)IPFail(@"준비한 문서를 찾을 수 없습니다.");
        IPConnection *p=[[IPConnection alloc]initWithHost:schoolHost port:schoolPort];
        NSString *fname=[NSString stringWithFormat:@"C:\\i-Print\\Spool\\%@-A4-%lu.prn",self.jobName,(unsigned long)self.pages];
        NSData *record=IPPrintRecordWithCopies(fname,self.jobName,document.length,self.pages,account,@"Mac-Native",p.localAddress,self.jobCopies);
        [p upload:document record:record progress:^(double n){dispatch_async(dispatch_get_main_queue(),^{self.progress.doubleValue=n;});}];[p close];
        dispatch_async(dispatch_get_main_queue(),^{[self discardJob];self.submissionCompleted=YES;self.progress.doubleValue=1;self.accountLabel.stringValue=[NSString stringWithFormat:@"%@ · 적립금 %@원 · 지원금 %@원",[account[@"name"] length]?account[@"name"]:user,account[@"credit"],account[@"support"]];});
        return @"서버 전송 완료. 복합기에서 로그인해 대기 문서를 확인하고 출력하세요.";
    }];
}
@end
int main(int argc,const char *argv[]){@autoreleasepool{if(argc==2 && strcmp(argv[1],"--preview-profile")==0){localProfilePreview=YES;schoolHost=@"127.0.0.1";schoolPort=1;}else if(argc==2 && strcmp(argv[1],"--preview-registration")==0){localRegistrationPreview=YES;schoolHost=@"127.0.0.1";schoolPort=1;}else if(argc==2 && strcmp(argv[1],"--preview-dashboard")==0){localDashboardPreview=YES;schoolHost=@"127.0.0.1";schoolPort=1;}else if(argc==2 && strcmp(argv[1],"--preview-dashboard-dark")==0){localDashboardPreview=YES;localDarkPreview=YES;schoolHost=@"127.0.0.1";schoolPort=1;}else if((argc==3 || argc==4) && strcmp(argv[1],"--preview-send-test")==0){char *end=NULL;long port=strtol(argv[2],&end,10);if(!end || *end || port<1 || port>65535)return 2;localDashboardPreview=YES;localNetworkPreview=YES;if(argc==4)localPreviewPDFPath=@(argv[3]);schoolHost=@"127.0.0.1";schoolPort=(uint16_t)port;}else if(argc>1 && strncmp(argv[1],"--",2)==0)return cli(argc,argv);NSApplication *app=NSApplication.sharedApplication;if(localDarkPreview)app.appearance=[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];app.activationPolicy=NSApplicationActivationPolicyRegular;NativeApp *delegate=[NativeApp new];app.delegate=delegate;[app run];}return 0;}
