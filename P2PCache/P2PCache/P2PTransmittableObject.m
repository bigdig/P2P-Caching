//
//  P2PTransmittableObject.m
//  P2PCache
//
//  Created by Alex Krebiehl on 3/26/14.
//  Copyright (c) 2014 NKU Research. All rights reserved.
//

#import "P2PTransmittableObject.h"
#import "P2PNode.h"

static NSString *P2PTransmittableObjectRequestIdKey =   @"RequestId";
static NSString *P2PTransmittableObjectResponseIdKey =  @"ResponseId";

static NSUInteger nextId = 0;
NSNumber* nextRequestId() { return [NSNumber numberWithUnsignedInteger:nextId++]; }

@implementation P2PTransmittableObject
{
    NSTimer *_timeoutTimer;
}

- (void)setShouldWaitForResponse:(bool)shouldWaitForResponse
{
    if ( shouldWaitForResponse && _requestId == nil )
    {
        _requestId = nextRequestId();
    }
    _shouldWaitForResponse = shouldWaitForResponse;
}

- (id)initWithCoder:(NSCoder *)aDecoder
{
    if ( self = [super init] )
    {
        _requestId = [aDecoder decodeObjectForKey:P2PTransmittableObjectRequestIdKey];
        _responseForRequestId = [aDecoder decodeObjectForKey:P2PTransmittableObjectResponseIdKey];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:self.requestId forKey:P2PTransmittableObjectRequestIdKey];
    [aCoder encodeObject:self.responseForRequestId forKey:P2PTransmittableObjectResponseIdKey];
}

- (void)peer:(P2PNode *)peer failedToSendObjectWithError:(P2PTransmissionError)error
{
    P2PLog( P2PLogLevelWarning, @"<%@> peer: %@ failed to send transmission", self, peer );
}

- (void)peer:(P2PNode *)peer failedToRecieveResponseWithError:(P2PTransmissionError)error
{
    // If this object is waiting for a response, this method should be overridden
    P2PLog( P2PLogLevelWarning, @"<%@> peer: %@ failed to recieve response", self, peer );
}

- (void)peerDidBeginToSendObject:(P2PNode *)peer
{
    _associatedNode = peer;
 
    if ( self.shouldWaitForResponse )
    {
        _timeoutTimer = [NSTimer timerWithTimeInterval:P2PTransmittableObjectTimeout target:self selector:@selector(requestTimedOut) userInfo:nil repeats:NO];
        [[NSRunLoop mainRunLoop] addTimer:_timeoutTimer forMode:NSDefaultRunLoopMode];
    }
}

- (void)peer:(P2PNode *)peer didRecieveResponse:(P2PTransmittableObject *)recievedObject
{
    [_timeoutTimer invalidate];
    _timeoutTimer = nil;
    
    _associatedNode = peer;
    recievedObject.associatedNode = peer;
}

- (void)requestTimedOut
{
    [self peer:self.associatedNode failedToRecieveResponseWithError:P2PTransmissionErrorTimeout];
}

@end
