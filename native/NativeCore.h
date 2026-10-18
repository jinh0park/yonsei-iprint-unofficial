#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSString *IPIdentity(NSData *plain, NSString *salt);
FOUNDATION_EXPORT NSString *IPPassword(NSString *password);
FOUNDATION_EXPORT NSData *IPAuthRequest(NSString *user, NSString *password, NSString *salt);
FOUNDATION_EXPORT NSDictionary *IPAccount(NSData *record, NSString *expectedUser);
FOUNDATION_EXPORT NSData *IPRegistrationRequest(NSString *user, NSString *password, NSString *salt, NSDictionary *profile);
FOUNDATION_EXPORT NSData *IPPrintRecord(NSString *filename, NSString *title, NSUInteger size, NSUInteger pages, NSDictionary *account, NSString *hostName, NSString *address);
FOUNDATION_EXPORT NSData *IPPrintRecordWithCopies(NSString *filename, NSString *title, NSUInteger size, NSUInteger pages, NSDictionary *account, NSString *hostName, NSString *address, NSUInteger copies);
// Duplex mode: 0 = simplex, 1 = long edge, 2 = short edge.
FOUNDATION_EXPORT NSString *IPPostScriptOptions(NSUInteger copies, NSUInteger duplexMode);
FOUNDATION_EXPORT NSUInteger IPSerializedLength(NSData *record);
FOUNDATION_EXPORT NSData *IPWrapPostScript(NSData *ps, NSString *jobName, NSString *date, NSString *osVersion);
FOUNDATION_EXPORT NSData *IPWaitQueueRequest(NSString *user, NSString *salt);
FOUNDATION_EXPORT NSArray<NSDictionary *> *IPWaitJobs(NSData *response);
FOUNDATION_EXPORT NSArray<NSDictionary *> *IPFetchWaitJobs(NSString *host, uint16_t port, NSString *user, NSString *password);
FOUNDATION_EXPORT NSArray<NSDictionary *> *IPDeleteWaitJob(NSString *host, uint16_t port, NSString *user, NSString *password, NSDictionary *job);
FOUNDATION_EXPORT void IPFail(NSString *message);
@interface IPConnection : NSObject
@property(readonly) NSString *localAddress;
@property(readonly) BOOL registrationMayHaveBeenSent;
- (instancetype)initWithHost:(NSString *)host port:(uint16_t)port;
- (NSDictionary *)authenticateUser:(NSString *)user password:(NSString *)password;
- (NSDictionary *)profileForUser:(NSString *)user password:(NSString *)password;
- (void)registerUser:(NSString *)user password:(NSString *)password profile:(NSDictionary *)profile;
- (void)upload:(NSData *)document record:(NSData *)record progress:(void(^)(double))progress;
- (NSArray<NSDictionary *> *)waitJobsForUser:(NSString *)user;
- (void)close;
@end
NS_ASSUME_NONNULL_END
