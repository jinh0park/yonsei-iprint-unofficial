#import <Foundation/Foundation.h>
#import "NativeCore.h"
static int checks=0;
static void check(BOOL ok){if(!ok)IPFail(@"registration core assertion");checks++;}
static NSData *field(NSData *r,NSUInteger offset){const uint8_t*p=r.bytes;return [r subdataWithRange:NSMakeRange(offset+1,p[offset])];}
int main(void){@autoreleasepool{@try {
 NSDictionary *p=@{@"name":@"가나다",@"phone":@"01012345678",@"email":@"native@example.com"};
 NSData *r=IPRegistrationRequest(@"NativeTest",@"Native-Test-17",@"21345",p);
 NSData *identity=[IPIdentity([@"NativeTest" dataUsingEncoding:NSASCIIStringEncoding],@"21345") dataUsingEncoding:NSASCIIStringEncoding];
 check(r.length==471);check([field(r,8) isEqual:identity]);check([field(r,137) isEqual:identity]);check([field(r,188) isEqual:identity]);
 check([field(r,239) isEqual:[IPPassword(@"NativeTest") dataUsingEncoding:NSASCIIStringEncoding]]);
 check([field(r,59) isEqual:[IPPassword(@"Native-Test-17") dataUsingEncoding:NSASCIIStringEncoding]]);
 check([field(r,116) isEqual:[NSData dataWithBytes:(uint8_t[]){0xb0,0xa1,0xb3,0xaa,0xb4,0xd9} length:6]]);
 check([IPAccount(r,@"NativeTest")[@"name"] isEqual:@"가나다"]);
 check([field(r,300) isEqual:[@"native@example.com" dataUsingEncoding:NSASCIIStringEncoding]]);
 check([field(r,351) isEqual:[@"01012345678" dataUsingEncoding:NSASCIIStringEncoding]]);
 for(NSDictionary *bad in @[@{@"user":@"tiny"},@{@"user":@"한글아이디"},@{@"user":@"bad space"},@{@"user":@"ABCDEFGHIJKLMNOPQRSTU"},@{@"password":@"tiny"},@{@"password":@"ABCDEFGHIJKLMNOPQRSTU"},@{@"password":@"한글암호"},@{@"password":@"bad\npass"},@{@"name":@""},@{@"name":@"😀"},@{@"name":@"가나다라마바사아자차카"},@{@"phone":@""},@{@"phone":@"010-1234-5678"},@{@"email":@""},@{@"email":@"invalid@"},@{@"email":@"a@b@c"},@{@"email":@"a b@c"}]){
  NSMutableDictionary *v=[p mutableCopy];[v addEntriesFromDictionary:bad];BOOL rejected=NO;
  @try{IPRegistrationRequest(bad[@"user"] ?: @"NativeTest",bad[@"password"] ?: @"Native-Test-17",@"21345",v);}@catch(NSException*e){rejected=YES;}check(rejected);
 }
 printf("{\"passed\":true,\"checks\":%d,\"synthetic_only\":true}\n",checks);return 0;
 }@catch(NSException*e){fprintf(stderr,"%s\n",e.reason.UTF8String);return 1;}}}
