#import <Foundation/Foundation.h>
#import "NativeCore.h"
static int checks=0;
static void check(BOOL ok){if(!ok)IPFail(@"print option assertion");checks++;}
static uint16_t word(NSData *d,NSUInteger off){uint16_t v;memcpy(&v,(const uint8_t*)d.bytes+off,2);return CFSwapInt16LittleToHost(v);}
int main(int argc,const char *argv[]){@autoreleasepool{@try {
    if(argc!=2)return 2;
    NSString *folder=@(argv[1]);[[NSFileManager defaultManager]createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
    NSDictionary *account=@{@"encryptedID":IPIdentity([@"NativeTest" dataUsingEncoding:NSASCIIStringEncoding],@"21345"),@"salt":@"21345"};
    NSMutableArray *rows=[NSMutableArray new];
    for(NSNumber *count in @[@1,@2,@99])for(NSUInteger mode=0;mode<3;mode++){
        NSUInteger copies=count.unsignedIntegerValue;
        NSData *record=IPPrintRecordWithCopies(@"C:\\i-Print\\Spool\\test.prn",@"Options-test",70000,3,account,@"Mac-Native",@"127.0.0.1",copies);
        check(word(record,0x213)==3*copies);check(word(record,0x270)==copies);check(word(record,0x272)=='S');
        check(IPSerializedLength(record)>0);
        NSString *stem=[NSString stringWithFormat:@"options-%lu-%lu",(unsigned long)mode,(unsigned long)copies];
        [record writeToFile:[folder stringByAppendingPathComponent:[stem stringByAppendingString:@".bin"]] atomically:YES];
        [rows addObject:@{@"mode":@(mode),@"copies":count,@"setup":IPPostScriptOptions(copies,mode),@"record":stem,@"serialized_length":@(IPSerializedLength(record))}];
    }
    for(NSArray *bad in @[@[@0,@0],@[@100,@0],@[@1,@3]]){
        BOOL rejected=NO;@try{IPPostScriptOptions([bad[0] unsignedIntegerValue],[bad[1] unsignedIntegerValue]);}@catch(NSException *e){rejected=YES;}check(rejected);
    }
    for(NSArray *bad in @[@[@0,@3],@[@100,@3],@[@99,@332]]){
        BOOL rejected=NO;@try{IPPrintRecordWithCopies(@"test.prn",@"Options-test",70000,[bad[1] unsignedIntegerValue],account,@"Mac-Native",@"127.0.0.1",[bad[0] unsignedIntegerValue]);}@catch(NSException *e){rejected=YES;}check(rejected);
    }
    NSData *json=[NSJSONSerialization dataWithJSONObject:@{@"passed":@YES,@"checks":@(checks),@"cases":rows} options:NSJSONWritingPrettyPrinted error:nil];
    [json writeToFile:[folder stringByAppendingPathComponent:@"options.json"] atomically:YES];
    printf("{\"passed\":true,\"checks\":%d}\n",checks);return 0;
}@catch(NSException *e){fprintf(stderr,"%s\n",e.reason.UTF8String);return 1;}}}
