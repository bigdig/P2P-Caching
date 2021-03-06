//
//  P2PNode.m
//  P2PCache
//
//  Created by Alex Krebiehl on 2/12/14.
//  Copyright (c) 2014 NKU Research. All rights reserved.
//

#import "P2PNode.h"
#import "P2PPeerFileAvailibilityRequest.h"
#import "NSMutableArray+QueueExtension.h"
#import "P2PNodeConnection.h"
#import "P2PFileManager.h"
#import "P2PFileChunkRequest.h"
#import "P2PPeerFileAvailbilityResponse.h"
#import "P2PFileChunk.h"
#import "P2PFileListRequest.h"
#import "P2PFileListResponse.h"
#import <zlib.h>

@interface P2PNode ()

@property (strong, nonatomic, readwrite) P2PNodeConnection *connection;
@property (copy, nonatomic, readwrite) NSString *displayableName;

@end

@implementation P2PNode
{
    NSMutableDictionary *_pendingRequests;
}

#pragma mark - Initialization
static dispatch_queue_t dispatchQueuePeerNode = nil;
static NSUInteger nextNodeID = 0;
NSUInteger getNextNodeID() { return nextNodeID++; }

- (id) init
{
    return [self initWithInputStream:nil outputStream:nil displayableName:nil];
}

- (id)initWithInputStream:(NSInputStream *)inStream outputStream:(NSOutputStream *)outStream displayableName:(NSString *)name
{
    if ( self = [super init] )
    {
        _nodeID = @( getNextNodeID() );
        self.displayableName = name;
        
        if ( inStream != nil && outStream != nil )
        {
            self.connection = [[P2PNodeConnection alloc] initWithInputStream:inStream outputStream:outStream];
            self.connection.delegate = self;
            [self.connection openConnection];
        }
        
        if ( dispatchQueuePeerNode == nil )
        {
            dispatchQueuePeerNode = dispatch_queue_create("dispatchQueuePeerNode", DISPATCH_QUEUE_SERIAL);
        }
    }
    return self;
}

#pragma mark - Object Transmission
- (void)transmitObject:(P2PTransmittableObject *)transmittableObject
{
    [self transmitObject:transmittableObject toNodeConnection:self.connection];
}

- (void)transmitObject:(P2PTransmittableObject *)transmittableObject toNodeConnection:(P2PNodeConnection *)connection
{
    // If connection is nil, we can't send this object
    if ( connection == nil )
    {
        [transmittableObject peer:self failedToSendObjectWithError:P2PTransmissionErrorNoConnectionToNode];
    }
    else
    {
        dispatch_async(dispatchQueuePeerNode, ^
        {
            if ( transmittableObject.shouldWaitForResponse )
            {
                if ( _pendingRequests == nil )
                {
                    _pendingRequests = [[NSMutableDictionary alloc] init];
                }
                [_pendingRequests setObject:transmittableObject forKey:transmittableObject.requestId];
            }
            
            // Serialize data... Add header and footer to the transmission
            NSData *preparedData = [self prepareObjectForTransmission:transmittableObject];
            [connection sendData:preparedData];
        });
        [transmittableObject peerDidBeginToSendObject:self];
    }
}


/** Serializes an object to be sent to another peer.  Adds header and footer information to the binary data
 
 Packet format:
 32-bit file size (file_size_type)
 archived object
 32-bit checksum (crc_type)
 */
- (NSData *)prepareObjectForTransmission:(id<NSCoding>)object
{
    NSData *objectData = [NSKeyedArchiver archivedDataWithRootObject:object];
    file_size_type fileSize = (file_size_type)[objectData length];
    crc_type crc = (crc_type) crc32( 0, [objectData bytes], (uInt)[objectData length] );
    
    // Combine the pieces
    NSMutableData *combinedData = [[NSMutableData alloc] initWithCapacity:sizeof( fileSize ) + [objectData length] + sizeof( crc )];
    [combinedData appendBytes:&fileSize length:sizeof( fileSize )];
    [combinedData appendBytes:[objectData bytes] length:[objectData length]];
    [combinedData appendBytes:&crc length:sizeof( crc )];
    
    return combinedData;
}




#pragma mark - P2PNodeConnectionDelegate Methods
- (void)nodeConnection:(P2PNodeConnection *)connection didRecieveObject:(P2PTransmittableObject *)object
{
    P2PTransmittableObject *requestingObject = [_pendingRequests objectForKey:object.responseForRequestId];
    if ( requestingObject )
    {
        // We got a response to a request we sent
        [_pendingRequests removeObjectForKey:requestingObject.requestId];
        [requestingObject peer:self didRecieveResponse:object];
    }
    else
    {
        P2PTransmittableObject *response;
        if ( [object isMemberOfClass:[P2PPeerFileAvailibilityRequest class]] )
        {
            // Check file availability
            response = [[P2PFileManager sharedManager] fileAvailibilityForRequest:(P2PPeerFileAvailibilityRequest *)object];
        }
        else if ( [object isMemberOfClass:[P2PFileChunkRequest class]] )
        {
            // A peer is requesting a file chunk
            response = [[P2PFileManager sharedManager] fileChunkForRequest:(P2PFileChunkRequest *)object];
        }
        else if ( [object isMemberOfClass:[P2PFileListRequest class]] )
        {
            // A node wants to know all of the filenames that we have information on
            response = [[P2PFileManager sharedManager] fileListForRequest:(P2PFileListRequest *)object];
        }
        else
        {
            NSAssert( NO, @"Recieved unexpected object" );
        }
        [self transmitObject:response toNodeConnection:connection];
    }
}

- (void)nodeConnection:(P2PNodeConnection *)connection failedToDownloadWithError:(P2PIncomingDataErrorCode)errorCode
{
    switch ( errorCode )
    {
        case P2PIncomingDataErrorCodeNoData:
            P2PLog( P2PLogLevelWarning, @"%@ - failed with error: NO DATA", connection );
            break;
        case P2PIncomingDataErrorCodeStreamError:
            P2PLog( P2PLogLevelWarning, @"%@ - failed with error: Error with stream", connection );
            break;
        case P2PIncomingDataErrorCodeCurruptFile:
            P2PLog( P2PLogLevelWarning, @"%@ - failed with error: Currupt file", connection );
            break;
        case P2PIncomingDataErrorCodeInvalidHeader:
            P2PLog( P2PLogLevelWarning, @"%@ - failed with error: Invalid header", connection );
            break;
        default:
            break;
    }
}

- (void)nodeConnectionDidEnd:(P2PNodeConnection *)node
{
    if ( node == self.connection )
    {
        self.connection = nil;
    }
    
    P2PLog( P2PLogLevelWarning, @"%@ - connection lost: %@", self, node);
    
    dispatch_async(dispatchQueuePeerNode, ^
    {
        for ( P2PTransmittableObject *obj in [_pendingRequests allValues] )
        {
            [obj peer:self failedToRecieveResponseWithError:P2PTransmissionErrorNoConnectionToNode];
        }
        _pendingRequests = nil;
    });
}



#pragma mark - Misc
- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@: %@>", NSStringFromClass([self class]), self.displayableName];
}

- (void)cleanup
{
    [self.connection dropConnection];
}

@end

