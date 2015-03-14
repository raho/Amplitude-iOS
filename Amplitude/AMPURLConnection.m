//
//  AMPURLConnection.m
//  Amplitude
//
//  Created by Allan on 3/13/15.
//  Copyright (c) 2015 Amplitude. All rights reserved.
//

#import "AMPURLConnection.h"
#import "AMPARCMacros.h"
#import "AMPConstants.h"
#import "ISPCertificatePinning.h"
#import "ISPPinnedNSURLConnectionDelegate.h"

@interface AMPURLConnection ()

@property (nonatomic, copy) void (^completionHandler)(NSURLResponse *, NSData *, NSError *);
@property (nonatomic, retain) NSURLConnection *connection;
@property (nonatomic, retain) NSMutableData *data;
@property (nonatomic, retain) NSURLResponse *response;
@property (nonatomic, retain) AMPURLConnection *delegate;

@end

@implementation AMPURLConnection

+ (NSDictionary *)loadSSLCertificate
{
    // We pin the anchor/CA certificate
    NSString *certFilename = @"ComodoCaLimitedRsaCertificationAuthority";
    NSString *certPath =  [[NSBundle bundleForClass:[self class]] pathForResource:certFilename ofType:@"der"];
    NSData *certData = SAFE_ARC_AUTORELEASE([[NSData alloc] initWithContentsOfFile:certPath]);

    if (certData == nil) {
        NSLog(@"Failed to load a certificate");
        return nil;
    }

    NSMutableDictionary *certs = [[NSMutableDictionary alloc] init];
    [certs setObject:[NSArray arrayWithObject:certData] forKey:kAMPEventLogDomain];
    return certs;
}

+ (void)sendAsynchronousRequest:(NSURLRequest *)request
                          queue:(NSOperationQueue *)queue
              completionHandler:(void (^)(NSURLResponse *response, NSData *data, NSError *connectionError))handler
{

#ifdef AMPLITUDE_SSL_PINNING
    // Create our SSL pins dictionnary
    NSDictionary *certs = [AMPURLConnection loadSSLCertificate];
    if (certs == nil) {
        NSLog(@"Failed to pin a certificate");
    }

    // Save the SSL pins so that our connection delegates automatically use them
    if ([ISPCertificatePinning setupSSLPinsUsingDictionnary:certs] != YES) {
        NSLog(@"Failed to pin the certificates");
    }
#endif

    AMPURLConnection *connection = [[AMPURLConnection alloc] initWithRequest:request
                                                                       queue:queue
                                                           completionHandler:handler];
}

- (AMPURLConnection *)initWithRequest:(NSURLRequest *)request
                                queue:(NSOperationQueue *)queue
                    completionHandler:(void (^)(NSURLResponse *response, NSData *data, NSError *connectionError))handler
{

    if (self = [super init]) {
        self.completionHandler = handler;
        self.data = nil;
        self.response = nil;

        // Have to retain self so it's not deallocated after the connection
        // finishes, but before the completion handler runs and self gets
        // cleaned up. When instantiated by sendAsynchronousRequest, the instance
        // is really it's own owner. The NSUrlConnection holds a strong reference
        // to the instance as a delegate, but releases after the connection completes.
        self.delegate = self;
    }


    _connection = [[NSURLConnection alloc] initWithRequest:request
                                                  delegate:self
                                          startImmediately:NO];

    [self.connection setDelegateQueue:queue];
    [self.connection start];


    return self;
}

- (void)dealloc
{
    SAFE_ARC_RELEASE(self.connection);
    SAFE_ARC_RELEASE(self.completionHandler);
    SAFE_ARC_RELEASE(self.data);
    SAFE_ARC_RELEASE(self.response);
    SAFE_ARC_SUPER_DEALLOC();
}

- (void)complete:(NSError *)error
{
    self.completionHandler(self.response, self.data, error);

    // The instance has done it's work. Release thyself.
    SAFE_ARC_RELEASE(self);
    self.delegate = nil;
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    [self complete:nil];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    [self complete:error];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    [self.data appendData:data];
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    self.response = response;
    _data = [[NSMutableData alloc] init];
}

@end