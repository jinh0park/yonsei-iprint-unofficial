#import "NativeCore.h"
#import <CommonCrypto/CommonDigest.h>
#include <sys/socket.h>
#include <netdb.h>
#include <arpa/inet.h>
#include <poll.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>

void IPFail(NSString *s) { @throw [NSException exceptionWithName:@"iPrintError" reason:s userInfo:nil]; }
static NSData *ascii(NSString *s) {
    NSData *d=[s dataUsingEncoding:NSASCIIStringEncoding allowLossyConversion:NO];
    if (!d) IPFail(@"현재 시험판의 ID와 비밀번호는 영문·숫자·기호를 지원합니다.");
    return d;
}
static NSString *hex(NSData *d) {
    const uint8_t *p=d.bytes; NSMutableString *s=[NSMutableString stringWithCapacity:d.length*2];
    for(NSUInteger i=0;i<d.length;i++) [s appendFormat:@"%02X",p[i]];
    return s;
}
static NSData *unhex(NSString *s) {
    if(s.length%2) IPFail(@"서버가 올바르지 않은 인증 정보를 반환했습니다.");
    NSMutableData *d=[NSMutableData data];
    for(NSUInteger i=0;i<s.length;i+=2) {
        NSString *pair=[s substringWithRange:NSMakeRange(i,2)]; unsigned v;
        NSScanner *scan=[NSScanner scannerWithString:pair];
        if(![scan scanHexInt:&v] || !scan.isAtEnd || v>255) IPFail(@"서버 인증 정보를 해석할 수 없습니다.");
        uint8_t b=v; [d appendBytes:&b length:1];
    }
    return d;
}
static uint16_t saltKey(NSString *salt) {
    if(!salt.length || salt.length>5 || [salt rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location!=NSNotFound)
        IPFail(@"서버의 인증 시간 정보가 올바르지 않습니다.");
    return (uint16_t)(salt.intValue+0x2b67);
}
NSString *IPIdentity(NSData *plain,NSString *salt) {
    uint16_t key=saltKey(salt); NSMutableData *out=[NSMutableData data]; const uint8_t *p=plain.bytes;
    for(NSUInteger i=0;i<plain.length;i++) {uint8_t b=p[i]^(key>>8);[out appendBytes:&b length:1];key=(uint16_t)((key+b)*0x6009+0xd425);}
    return hex(out);
}
static NSString *decodeIdentity(NSString *encoded, NSString *salt) {
    NSData *in=unhex(encoded);const uint8_t *p=in.bytes;uint16_t key=saltKey(salt);NSMutableData *out=[NSMutableData data];
    for(NSUInteger i=0;i<in.length;i++){uint8_t b=p[i]^(key>>8);[out appendBytes:&b length:1];key=(uint16_t)((key+p[i])*0x6009+0xd425);}
    NSString *s=[[NSString alloc] initWithData:out encoding:NSASCIIStringEncoding];
    if(!s) IPFail(@"서버의 사용자 ID를 해석할 수 없습니다.");return s;
}
NSString *IPPassword(NSString *password) {
    NSData *d=ascii(password);unsigned char digest[CC_SHA1_DIGEST_LENGTH];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    CC_SHA1(d.bytes,(CC_LONG)d.length,digest);
#pragma clang diagnostic pop
    return [ascii([hex([NSData dataWithBytes:digest length:sizeof digest]) lowercaseString]) base64EncodedStringWithOptions:0];
}
static void shortPut(NSMutableData *d, NSUInteger off,NSUInteger cap,NSData *s) {
    if(s.length>cap || off+cap+1>d.length) IPFail(@"인쇄 정보가 허용된 길이를 넘었습니다.");
    uint8_t *p=d.mutableBytes;p[off]=(uint8_t)s.length;memcpy(p+off+1,s.bytes,s.length);
}
static NSData *shortGet(NSData *d,NSUInteger off,NSUInteger cap) {
    if(off+cap+1>d.length)IPFail(@"서버 응답 길이가 올바르지 않습니다.");
    const uint8_t *p=d.bytes;if(p[off]>cap)IPFail(@"서버 응답 필드 길이가 올바르지 않습니다.");
    return [d subdataWithRange:NSMakeRange(off+1,p[off])];
}
static NSString *text(NSData *d) {
    NSStringEncoding cp=CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingDOSKorean);
    NSString *s=[[NSString alloc] initWithData:d encoding:cp];
    if(!s) s=[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
    return s ?: @"";
}
static NSString *currentSalt(void) {
    NSDateComponents *c=[NSCalendar.currentCalendar components:NSCalendarUnitHour|NSCalendarUnitMinute|NSCalendarUnitSecond fromDate:NSDate.date];
    NSString *s=[NSString stringWithFormat:@"%ld%02ld%02ld",(long)c.hour,(long)c.minute,(long)c.second];
    return [s substringToIndex:MIN(5,s.length)]; // Delphi FormatDateTime('HNNSS'), ShortString[5].
}
NSData *IPAuthRequest(NSString *user,NSString *password,NSString *salt) {
    NSData *u=ascii(user);if(!u.length || u.length>25 || !password.length)IPFail(@"ID(최대 25자)와 비밀번호를 입력해 주세요.");
    NSMutableData *d=[NSMutableData dataWithLength:0x1d7];
    shortPut(d,8,50,ascii(IPIdentity(u,salt)));shortPut(d,0x3b,56,ascii(IPPassword(password)));shortPut(d,0x1d1,5,ascii(salt));return d;
}
static int32_t intGet(NSData *d,NSUInteger off) {if(off+4>d.length)IPFail(@"응답이 잘렸습니다.");uint32_t n;memcpy(&n,(const uint8_t*)d.bytes+off,4);return (int32_t)CFSwapInt32LittleToHost(n);}
NSDictionary *IPAccount(NSData *d,NSString *expectedUser) {
    if(d.length!=0x1d7)IPFail(@"인증 응답 길이가 올바르지 않습니다.");
    NSString *salt=text(shortGet(d,0x1d1,5));NSString *encrypted=text(shortGet(d,8,50));
    NSString *user=decodeIdentity(encrypted,salt);
    if(![user isEqualToString:expectedUser])IPFail(@"인증 응답의 사용자 ID가 입력한 ID와 다릅니다.");
    return @{@"user":user,@"encryptedID":encrypted,@"salt":salt,@"name":text(shortGet(d,0x74,20)),
             @"phone":text(shortGet(d,0x15f,50)),@"email":text(shortGet(d,0x12c,50)),
             @"_pinData":shortGet(d,0x89,50),
             @"credit":@(intGet(d,0x196)),@"support":@(intGet(d,0x192))};
}
static NSData *profileText(NSString *value, NSUInteger maximum, NSString *field) {
    if(![value isKindOfClass:NSString.class])IPFail(@"회원정보가 올바르지 않습니다. 다시 조회해 주세요.");
    NSData *encoded=[value dataUsingEncoding:CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingDOSKorean) allowLossyConversion:NO];
    if(!encoded)IPFail([NSString stringWithFormat:@"%@에 서버가 지원하지 않는 문자가 있습니다.",field]);
    if(encoded.length>maximum)IPFail([NSString stringWithFormat:@"%@이 너무 깁니다. 최대 %lu바이트까지 지원합니다.",field,(unsigned long)maximum]);
    if([value rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location!=NSNotFound)IPFail(@"회원정보에 줄바꿈이나 제어 문자를 넣을 수 없습니다.");
    return encoded;
}
static NSData *registrationRecord(NSString *user,NSString *password,NSString *salt,NSDictionary *profile) {
    if(![profile[@"user"] isEqualToString:user])IPFail(@"가입 정보의 사용자 ID가 올바르지 않습니다.");
    NSString *name=profile[@"name"],*phone=profile[@"phone"],*email=profile[@"email"];
    if(![name isKindOfClass:NSString.class] || ![email isKindOfClass:NSString.class] || !name.length || !email.length)IPFail(@"이름과 이메일을 입력해 주세요.");
    if(![phone isKindOfClass:NSString.class] || phone.length>13)IPFail(@"연락처는 13자 이내로 입력해 주세요.");
    NSMutableData *record=[IPAuthRequest(user,password,salt) mutableCopy];
    shortPut(record,0x74,20,profileText(name,20,@"이름"));
    shortPut(record,0x15f,50,profileText(phone,50,@"연락처"));
    shortPut(record,0x12c,50,profileText(email,50,@"이메일"));
    // Registration supplies the original transformed-ID card/PIN field.
    NSData *pin=profile[@"_pinData"];
    if(![pin isKindOfClass:NSData.class] || pin.length>50)IPFail(@"기존 회원정보를 다시 조회해 주세요.");
    shortPut(record,0x89,50,pin);
    // Credit/reserved fields remain zero in the new-user record.
    return record;
}
NSData *IPRegistrationRequest(NSString *user,NSString *password,NSString *salt,NSDictionary *profile) {
    NSCharacterSet *idChars=[NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-"];
    if(user.length<5 || user.length>20 || [user rangeOfCharacterFromSet:idChars.invertedSet].location!=NSNotFound)
        IPFail(@"새 ID는 영문·숫자·점·밑줄·하이픈으로 5~20자 입력해 주세요.");
    NSData *pw=ascii(password);
    if(pw.length<5 || pw.length>20 || [password rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location!=NSNotFound)
        IPFail(@"비밀번호는 영문·숫자·기호로 5~20자 입력해 주세요.");
    NSString *phone=profile[@"phone"],*email=profile[@"email"];
    NSCharacterSet *digits=[NSCharacterSet characterSetWithCharactersInString:@"0123456789"];
    if(![phone isKindOfClass:NSString.class] || phone.length<9 || phone.length>13 || [phone rangeOfCharacterFromSet:digits.invertedSet].location!=NSNotFound)
        IPFail(@"연락처를 하이픈 없이 숫자 9~13자로 입력해 주세요.");
    NSArray *parts=[email isKindOfClass:NSString.class] ? [email componentsSeparatedByString:@"@"] : @[];
    if(parts.count!=2 || ![parts[0] length] || ![parts[1] length] || [email rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location!=NSNotFound)
        IPFail(@"이메일 주소를 확인해 주세요.");
    // Registration uses the same user record, with additional original card fields:
    // PIN and card ID = transformed user ID; card password = Type6(user ID).
    NSMutableDictionary *values=[profile mutableCopy];values[@"user"]=user;
    values[@"_pinData"]=ascii(IPIdentity(ascii(user),salt));
    NSMutableData *record=[registrationRecord(user,password,salt,values) mutableCopy];
    shortPut(record,0xbc,50,values[@"_pinData"]);
    shortPut(record,0xef,60,ascii(IPPassword(user)));
    return record;
}
static void u16Put(NSMutableData *d,NSUInteger off,uint16_t n) {n=CFSwapInt16HostToLittle(n);[d replaceBytesInRange:NSMakeRange(off,2) withBytes:&n];}
static void u32Put(NSMutableData *d,NSUInteger off,uint32_t n) {n=CFSwapInt32HostToLittle(n);[d replaceBytesInRange:NSMakeRange(off,4) withBytes:&n];}
NSData *IPPrintRecord(NSString *filename,NSString *title,NSUInteger size,NSUInteger pages,NSDictionary *account,NSString *hostName,NSString *address) {
    return IPPrintRecordWithCopies(filename,title,size,pages,account,hostName,address,1);
}
NSData *IPPrintRecordWithCopies(NSString *filename,NSString *title,NSUInteger size,NSUInteger pages,NSDictionary *account,NSString *hostName,NSString *address,NSUInteger copies) {
    if(!copies || copies>99 || !pages || pages>32767/copies || !size || size>INT32_MAX)IPFail(@"문서가 시험판의 지원 범위를 벗어났습니다.");
    NSMutableData *d=[NSMutableData dataWithLength:0x421];
    shortPut(d,0,255,ascii(filename));u32Put(d,0x100,(uint32_t)size); // high 32 bits stay zero.
    shortPut(d,0x108,255,ascii(title));shortPut(d,0x208,10,ascii(@"A4"));u16Put(d,0x213,(uint16_t)(pages*copies));
    shortPut(d,0x215,50,ascii(@"Samsung M4370 5370 Series"));shortPut(d,0x248,20,ascii(@"POSTSCRIPT"));
    shortPut(d,0x25d,10,ascii(@"Print"));u16Put(d,0x268,'M');u32Put(d,0x26a,(uint32_t)pages);
    // Original PostScript import (0xcbed4c) retains 'S' for either binding.
    // Duplex/Tumble are controlled by the printer's PostScript page device.
    u16Put(d,0x26e,1);u16Put(d,0x270,(uint16_t)copies);u16Put(d,0x272,'S');u16Put(d,0x274,'R');
    shortPut(d,0x276,50,ascii(account[@"encryptedID"]));
    shortPut(d,0x2a9,255,ascii(hostName));shortPut(d,0x3a9,50,ascii(address));
    NSData *station=[@"N음대신관2층도서관1번" dataUsingEncoding:CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingDOSKorean)];
    shortPut(d,0x3dc,50,station);u16Put(d,0x419,'C');shortPut(d,0x41b,5,ascii(account[@"salt"]));return d;
}
NSString *IPPostScriptOptions(NSUInteger copies,NSUInteger duplexMode) {
    if(!copies || copies>99 || duplexMode>2)IPFail(@"부수(1~99)와 단면·양면 설정을 확인해 주세요.");
    return [NSString stringWithFormat:@"%%%%BeginNonPPDFeature: NumCopies %lu\n<< /NumCopies %lu /Collate true /Duplex %@ /Tumble %@ >> setpagedevice\n%%%%EndFeature",(unsigned long)copies,(unsigned long)copies,duplexMode ? @"true" : @"false",duplexMode==2 ? @"true" : @"false"];
}
NSUInteger IPSerializedLength(NSData *d) {
    if(d.length!=0x421)IPFail(@"인쇄 정보 길이가 올바르지 않습니다.");
    // Original computes a stream size but sends the fixed packed record (0xcc1f51).
    // Reproduce its overlapping 4-byte word writes and single ANSI char lengths.
    NSUInteger n=0;
    for(NSArray *field in @[@[@0,@255],@[@0x108,@255],@[@0x208,@10],@[@0x215,@50],@[@0x248,@20],@[@0x25d,@10],@[@0x276,@50],@[@0x2a9,@255],@[@0x3a9,@50],@[@0x3dc,@50]])
        n+=4+shortGet(d,[field[0] unsignedIntegerValue],[field[1] unsignedIntegerValue]).length;
    n+=8+4+4+4+4; // file size, printed pages, doc pages, N-up/copies overlap, copies/duplex overlap.
    for(NSNumber *off in @[@0x268,@0x272,@0x274]) {
        uint16_t c;memcpy(&c,(const uint8_t*)d.bytes+off.unsignedIntegerValue,2);
        if(CFSwapInt16LittleToHost(c)>127)IPFail(@"지원하지 않는 인쇄 옵션입니다.");n+=5;
    }
    return n;
}
NSData *IPWrapPostScript(NSData *ps,NSString *jobName,NSString *date,NSString *osVersion) {
    if(![jobName length] || [jobName rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"] invertedSet]].location!=NSNotFound)
        IPFail(@"작업 이름이 올바르지 않습니다.");
    NSString *head=[NSString stringWithFormat:
      @"\033%%-12345X@PJL DEFAULT SERVICEDATE=%@\r\n"
       "@PJL COMMENT OS information : %@\r\n"
       "@PJL COMMENT Model Name : Samsung M4370 5370 Series\r\n"
       "@PJL COMMENT PPD Version : 1.23\r\n"
       "@PJL COMMENT Model path : /Library/Printers/Samsung/M4370_5370/\r\n"
       "@PJL SET RESOLUTION=600\n@PJL SET BITSPERPIXEL=2\n@PJL SET COLORMODE=MONO\r\n"
       "@PJL SET USERNAME=\"iprint-mac\"\r\n@PJL SET JOBNAME=\"%@\"\r\n"
       "@PJL SET ECONOMODE = OFF\r\n@PJL SET LDAPPERMISSION=PERSONAL\r\n"
       "@PJL SET MULTIBINMODE=PRINTERDEFAULT\r\n@PJL SET XIGNOREFF=OFF\r\n"
       "@PJL SET DARKENTEXT=OFF\r\n@PJL SET EDGEENHANCE=NORMAL\r\n"
       "@PJL SET ESCMSCOLORADJUSTMENT=ON\n@PJL SET ESCMSBRIGHTNESS=50\n@PJL SET ESCMSCONTRAST=50\r\n"
       "@PJL COMMENT NORMAL PRINT\r\n@PJL SET HOLD=OFF\r\n"
       "@PJL SET USERNAME=\"iprint-mac\"\r\n@PJL SET JOBNAME=\"%@\"\r\n"
       "@PJL ENTER LANGUAGE = POSTSCRIPT\r\n",date,osVersion,jobName,jobName];
    NSMutableData *d=[ascii(head) mutableCopy];[d appendData:ps];[d appendData:ascii(@"\033%-12345X")];return d;
}
// Original GetSvrWaitJobList (0xcc2e80): ShortString[50] ID + ShortString[5] salt.
NSData *IPWaitQueueRequest(NSString *user,NSString *salt) {
    NSData *u=ascii(user);if(!u.length || u.length>25)IPFail(@"대기 문서를 조회할 사용자 ID가 올바르지 않습니다.");
    NSMutableData *d=[NSMutableData dataWithLength:57];
    shortPut(d,0,50,ascii(IPIdentity(u,salt)));shortPut(d,51,5,ascii(salt));return d;
}
static BOOL decimalField(NSString *s) {
    return s.length && [s rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"0123456789"].invertedSet].location==NSNotFound;
}
static void validateJobID(NSString *jobID) {
    if(![jobID isKindOfClass:NSString.class] || !decimalField(jobID) || jobID.length>10 || jobID.longLongValue<1 || jobID.longLongValue>INT32_MAX)
        IPFail(@"서버 대기 문서의 식별자가 올바르지 않습니다. 삭제하지 않았습니다.");
}
NSArray<NSDictionary *> *IPWaitJobs(NSData *response) {
    if(response.length>1024*1024)IPFail(@"서버 대기 문서 목록이 너무 큽니다.");
    NSStringEncoding cp=CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingDOSKorean);
    NSString *body=[[NSString alloc]initWithData:response encoding:cp];
    if(!body)IPFail(@"서버 대기 문서 목록의 문자 인코딩을 해석할 수 없습니다.");
    // Original ExtractStrings: ';' records, leading whitespace skipped, quotes
    // protect separators and remain in each record. '&' fields are not unescaped.
    NSMutableArray *rows=[NSMutableArray new];NSUInteger start=0;unichar quote=0;
    for(NSUInteger i=0;i<=body.length;i++) {
        unichar c=i<body.length ? [body characterAtIndex:i] : 0;
        if(c==0 && i<body.length)IPFail(@"서버 대기 문서 목록에 잘못된 제어 문자가 있습니다.");
        if(quote){if(c==quote)quote=0;}
        else if(c=='\"' || c=='\'')quote=c;
        if(c==0 || (c==';' && !quote)) {
            NSString *row=[[body substringWithRange:NSMakeRange(start,i-start)] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if(row.length)[rows addObject:row];start=i+1;
        }
    }
    if(quote || rows.count>2000)IPFail(@"서버 대기 문서 목록의 형식이 올바르지 않습니다.");
    NSMutableArray *jobs=[NSMutableArray new];NSMutableSet *ids=[NSMutableSet new];
    for(NSString *row in rows) {
        if([row rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location!=NSNotFound)IPFail(@"서버 대기 문서 목록에 잘못된 제어 문자가 있습니다.");
        NSMutableArray *f=[[row componentsSeparatedByString:@"&"] mutableCopy];
        if([f.lastObject isEqual:@""] && f.count==10)[f removeLastObject];
        if(f.count<7 || f.count>9)IPFail(@"서버 대기 문서 항목의 형식이 예상과 다릅니다. 삭제 기능을 사용하지 않았습니다.");
        NSString *jobID=f[0];validateJobID(jobID);
        if([ids containsObject:jobID] || !decimalField(f[4]) || [f[4] longLongValue]>INT32_MAX || !decimalField(f[5]) || [f[5] longLongValue]>INT32_MAX)
            IPFail(@"서버 대기 문서의 번호·페이지·단가를 확인할 수 없습니다.");
        [ids addObject:jobID];
        [jobs addObject:@{@"id":jobID,@"date":f[1],@"title":f[2],@"paper":f[3],@"pages":@([f[4] longLongValue]),@"unitCost":@([f[5] longLongValue]),@"driver":f[6],@"source":f.count>7 ? f[7] : @"",@"color":f.count>8 ? f[8] : @""}];
    }
    return jobs;
}
@implementation IPConnection { int _fd; NSString *_localAddress; BOOL _registrationMayHaveBeenSent; }
- (BOOL)registrationMayHaveBeenSent {return _registrationMayHaveBeenSent;}
- (instancetype)initWithHost:(NSString*)host port:(uint16_t)port {
    if((self=[super init])) {
        _fd=-1;struct addrinfo hints={0},*list=NULL;hints.ai_family=AF_INET;hints.ai_socktype=SOCK_STREAM;
        if(getaddrinfo(host.UTF8String,[@(port).stringValue UTF8String],&hints,&list))IPFail(@"학교 서버 주소를 찾을 수 없습니다. 캠퍼스 네트워크 연결을 확인해 주세요.");
        for(struct addrinfo *a=list;a;a=a->ai_next){
            int fd=socket(a->ai_family,a->ai_socktype,a->ai_protocol);if(fd<0)continue;
            fcntl(fd,F_SETFL,O_NONBLOCK);int r=connect(fd,a->ai_addr,a->ai_addrlen);
            if(r<0 && errno==EINPROGRESS){struct pollfd p={.fd=fd,.events=POLLOUT};int err=0;socklen_t len=sizeof err;r=poll(&p,1,10000);if(r>0 && !getsockopt(fd,SOL_SOCKET,SO_ERROR,&err,&len) && !err)r=0;else r=-1;}
            if(!r){_fd=fd;fcntl(fd,F_SETFL,0);break;}close(fd);
        }
        freeaddrinfo(list);if(_fd<0)IPFail(@"학교 서버에 연결할 수 없습니다. 캠퍼스 네트워크에서 다시 시도해 주세요.");
        int noSig=1;setsockopt(_fd,SOL_SOCKET,SO_NOSIGPIPE,&noSig,sizeof noSig);
        struct timeval timeout={15,0};setsockopt(_fd,SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof timeout);setsockopt(_fd,SOL_SOCKET,SO_SNDTIMEO,&timeout,sizeof timeout);
        struct sockaddr_in addr;socklen_t len=sizeof addr;char b[INET_ADDRSTRLEN]={0};
        if(!getsockname(_fd,(struct sockaddr*)&addr,&len))inet_ntop(AF_INET,&addr.sin_addr,b,sizeof b);
        _localAddress=@(b);
    }return self;
}
- (NSString*)localAddress{return _localAddress ?: @"";}
- (void)close{if(_fd>=0){close(_fd);_fd=-1;}}
- (void)dealloc{[self close];}
- (void)write:(NSData*)d {const uint8_t *p=d.bytes;NSUInteger n=d.length;while(n){ssize_t k=send(_fd,p,n,0);if(k<0 && errno==EINTR)continue;if(k<=0)IPFail(@"서버 전송이 중단됐습니다.");p+=k;n-=k;}}
- (NSData*)read:(NSUInteger)n {NSMutableData *d=[NSMutableData dataWithLength:n];uint8_t *p=d.mutableBytes;NSUInteger left=n;while(left){ssize_t k=recv(_fd,p,left,0);if(k<0 && errno==EINTR)continue;if(k<=0)IPFail(@"서버 응답이 없거나 연결이 중단됐습니다.");p+=k;left-=k;}return d;}
- (NSString*)line {NSMutableData *d=[NSMutableData data];for(NSUInteger i=0;i<1024;i++){NSData *b=[self read:1];if(*(const uint8_t*)b.bytes=='\n')return [text(d) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];[d appendData:b];}IPFail(@"서버 응답이 너무 깁니다.");return @"";}
- (NSDictionary*)authenticateUser:(NSString*)user password:(NSString*)password {
    NSData *request=IPAuthRequest(user,password,currentSalt());
    [self write:ascii(@"USERAUTH:COMMAND\r\n")];
    if(![[[self line] uppercaseString] isEqualToString:@"USERAUTH:OK"])IPFail(@"서버가 사용자 인증 요청을 승인하지 않았습니다.");
    [self write:request];
    NSString *reply=[[self line] uppercaseString];
    if(![reply isEqualToString:@"AUTHUSERPROC:OK"]) {
        NSCharacterSet *allowed=[NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789:_ -"];
        BOOL safe=reply.length<=80 && [reply rangeOfCharacterFromSet:allowed.invertedSet].location==NSNotFound && [reply hasPrefix:@"AUTHUSERPROC:"];
        IPFail(safe ? [@"서버가 인증을 승인하지 않았습니다. 응답: " stringByAppendingString:reply] : @"서버가 예상과 다른 인증 응답을 보냈습니다.");
    }
    return IPAccount([self read:0x1d7],user);
}
- (NSDictionary*)profileForUser:(NSString*)user password:(NSString*)password {
    NSData *request=IPAuthRequest(user,password,currentSalt());
    [self write:ascii(@"GETUSER:COMMAND\r\n")];
    if(![[[self line] uppercaseString] isEqualToString:@"GETUSER:OK"])IPFail(@"서버가 회원정보 조회 요청을 승인하지 않았습니다.");
    [self write:request];
    if(![[[self line] uppercaseString] isEqualToString:@"GETUSERPROC:OK"])IPFail(@"회원정보를 조회하지 못했습니다.");
    return IPAccount([self read:0x1d7],user);
}
- (void)registerUser:(NSString*)user password:(NSString*)password profile:(NSDictionary*)profile {
    NSData *request=IPRegistrationRequest(user,password,currentSalt(),profile);
    [self write:ascii(@"USERDUP:COMMAND\r\n")];
    if(![[[self line] uppercaseString] isEqualToString:@"USERDUP:OK"])IPFail(@"서버가 ID 확인 요청을 승인하지 않았습니다.");
    [self write:request];
    if(![[[self line] uppercaseString] isEqualToString:@"IDUSE:OK"])IPFail(@"서버가 이 ID의 사용을 승인하지 않았습니다. 이미 가입된 ID이거나 다른 제한이 있을 수 있습니다. 가입 요청은 보내지 않았습니다.");
    // The original uses both commands on the SAME connection and SAME record.
    [self write:ascii(@"USERINS:COMMAND\r\n")];
    if(![[[self line] uppercaseString] isEqualToString:@"ADDUSER:OK"])IPFail(@"서버가 회원가입 요청을 승인하지 않았습니다.");
    _registrationMayHaveBeenSent=YES;
    @try {
        [self write:request];
        if(![[[self line] uppercaseString] isEqualToString:@"ADDUSERINS:OK"])IPFail(@"서버가 가입 완료 응답을 보내지 않았습니다.");
    }@catch(NSException *e){IPFail([e.reason stringByAppendingString:@"\n가입 여부가 불확실합니다. 같은 정보로 자동 재시도하지 않습니다. 창을 닫고 새 ID로 로그인해 먼저 확인해 주세요."]);}
}
- (NSArray<NSDictionary *>*)waitJobsForUser:(NSString*)user {
    NSData *request=IPWaitQueueRequest(user,currentSalt());
    [self write:ascii(@"GETWAITJOBLIST:COMMAND\r\n")];
    if(![[[self line]uppercaseString]isEqualToString:@"GETWAITJOBLIST:OK"])IPFail(@"서버가 대기 문서 조회 요청을 승인하지 않았습니다.");
    [self write:request];
    NSMutableData *data=[NSMutableData new];uint8_t buffer[4096];
    // Peek before consuming to stop exactly at LF without reading beyond it.
    while(data.length<=1024*1024) {
        ssize_t n=recv(_fd,buffer,sizeof buffer,MSG_PEEK);
        if(n<0 && errno==EINTR)continue;
        if(n<=0)IPFail(@"대기 문서 목록을 받는 중 연결이 중단됐습니다.");
        uint8_t *lf=memchr(buffer,'\n',(size_t)n);NSUInteger take=lf ? (NSUInteger)(lf-buffer)+1 : (NSUInteger)n;
        [data appendData:[self read:take]];
        if(lf){[data setLength:data.length-1];if(data.length && ((const uint8_t*)data.bytes)[data.length-1]=='\r')[data setLength:data.length-1];return IPWaitJobs(data);}
    }
    IPFail(@"서버 대기 문서 목록이 너무 큽니다.");return @[];
}
// Private: the public operation below verifies membership in a fresh own-account
// list before passing a server-returned ID here. Original WaitJobDel has no ACK.
- (void)requestWaitJobDeletion:(NSString*)jobID {
    validateJobID(jobID);
    [self write:ascii(@"WAITJOBDEL:COMMAND\r\n")];
    if(![[[self line]uppercaseString]isEqualToString:@"WAITJOBDEL:OK"])IPFail(@"서버가 대기 문서 삭제 요청을 승인하지 않았습니다. 문서 번호는 보내지 않았습니다.");
    @try{[self write:ascii([jobID stringByAppendingString:@"\r\n"])];}
    @catch(NSException *e){IPFail(@"삭제 요청의 전달 여부가 불확실합니다. 자동으로 다시 삭제하지 않습니다. 대기 문서를 새로고침해 확인해 주세요.");}
}
- (void)ack {NSString *s=[[NSString alloc] initWithData:[self read:4] encoding:NSASCIIStringEncoding];if(![s isEqualToString:@"0000"])IPFail([NSString stringWithFormat:@"서버가 문서를 거절했습니다. 응답 코드: %@",s ?: @"해석 불가"]);}
- (void)upload:(NSData*)document record:(NSData*)record progress:(void(^)(double))progress {
    if(record.length!=0x421 || intGet(record,0x100)!=(int32_t)document.length)IPFail(@"문서와 인쇄 정보의 크기가 다릅니다.");
    NSString *prefix=[NSString stringWithFormat:@"TASA_V300\r\n004%lu#$A",(unsigned long)IPSerializedLength(record)];
    [self write:ascii(prefix)];[self write:record];[self ack];
    [self write:ascii(@"1.0.0.0\r\n")]; // Original VS_FIXEDFILEINFO FileVersion = 1.0.0.0.
    BOOL sent=NO;
    @try {for(NSUInteger off=0;off<document.length;){NSUInteger n=MIN((NSUInteger)32768,document.length-off);sent=YES;[self write:[document subdataWithRange:NSMakeRange(off,n)]];[self ack];off+=n;progress((double)off/document.length);}[self ack];}
    @catch(NSException *e){if(sent)IPFail([e.reason stringByAppendingString:@"\n전송 완료 여부가 불확실합니다. 복합기 대기목록을 확인한 뒤 재시도해 주세요."]);@throw;}
}
@end

NSArray<NSDictionary *> *IPFetchWaitJobs(NSString *host,uint16_t port,NSString *user,NSString *password) {
    IPConnection *auth=[[IPConnection alloc]initWithHost:host port:port];
    @try{[auth authenticateUser:user password:password];}@finally{[auth close];}
    IPConnection *list=[[IPConnection alloc]initWithHost:host port:port];
    @try{return [list waitJobsForUser:user];}@finally{[list close];}
}
NSArray<NSDictionary *> *IPDeleteWaitJob(NSString *host,uint16_t port,NSString *user,NSString *password,NSDictionary *job) {
    validateJobID(job[@"id"]);
    NSArray *fresh=IPFetchWaitJobs(host,port,user,password);NSDictionary *match=nil;
    for(NSDictionary *item in fresh)if([item[@"id"]isEqual:job[@"id"]]){match=item;break;}
    if(!match)IPFail(@"이 문서는 현재 대기 목록에 없습니다. 이미 출력되거나 삭제됐을 수 있습니다. 삭제 요청은 보내지 않았습니다. 새로고침해 주세요.");
    if(![match isEqualToDictionary:job])IPFail(@"서버의 문서 정보가 변경됐습니다. 삭제 요청은 보내지 않았습니다. 새로고침한 뒤 다시 선택해 주세요.");
    IPConnection *remove=[[IPConnection alloc]initWithHost:host port:port];
    @try{[remove requestWaitJobDeletion:match[@"id"]];}@finally{[remove close];}
    NSArray *after=nil;
    @try{after=IPFetchWaitJobs(host,port,user,password);}
    @catch(NSException *e){IPFail(@"삭제 요청을 보냈지만 대기 목록을 다시 확인하지 못했습니다. 자동으로 다시 삭제하지 않습니다. 새로고침해 확인해 주세요.");}
    for(NSDictionary *item in after)if([item[@"id"]isEqual:job[@"id"]])IPFail(@"삭제 요청을 보냈지만 문서가 아직 대기 목록에 있습니다. 서버 처리 중이거나 삭제가 반영되지 않았을 수 있습니다. 새로고침해 확인해 주세요.");
    return after;
}
