//
//  P2PFileManager.h
//  P2PCache
//
//  Created by Alex Krebiehl on 2/7/14.
//  Copyright (c) 2014 NKU Research. All rights reserved.
//

#import <Foundation/Foundation.h>

@class P2PPeerFileAvailibilityRequest, P2PPeerFileAvailbilityResponse, P2PFileChunk,
P2PFileChunkRequest, P2PFileRequest, P2PFileInfo, P2PFileListResponse, P2PFileListRequest;

/** The defualt size (in bytes) file a file chunk */
static const NSUInteger P2PFileManagerFileChunkSize = 1024 * 64;  // 64k File chunk size

@interface P2PFileManager : NSFileManager

/** A set of fileIds that the @c P2PFileManager has information on */
@property (strong, nonatomic, readonly) NSOrderedSet *allFileIds;

/** Directory of cache on disk */
@property (strong, nonatomic, readonly) NSURL *cacheDirectory;


/** A dictionary containing a dictionary with all fileNames in the cache as keys, with an array
 of fileIds that are mapped to that filename as values */
@property (strong, nonatomic, readonly) NSDictionary *filenamesToFileIds;


/** Returns the shared instance of the file manager
 
 @return The shared file manager
 */
+ (P2PFileManager *)sharedManager;


/** Responds to a peer asking what we have available of a certian file
 
 @param request A request from a peer
 @return Returns a response to the peer detailing what we have available
 */
- (P2PPeerFileAvailbilityResponse *)fileAvailibilityForRequest:(P2PPeerFileAvailibilityRequest *)request;


/** Returns a file chunk from disk to send to another peer on the network
 
 @param request A chunk request from a peer
 @return A file chunk object, or nil if the data couldn't be located 
 */
- (P2PFileChunk *)fileChunkForRequest:(P2PFileChunkRequest *)request;


/** A file request should call this method to save a recieved fileChunk to disk
 
 @param fileRequest The file request needing to save data
 @param chunk A chunk object with data as well as chunk information
 */
- (void)fileRequest:(P2PFileRequest *)fileRequest didRecieveFileChunk:(P2PFileChunk *)chunk;


/** Adds a file to the caching system.  This will probably only be used for testing
 
 @param file A data object containing a complete file from the user or other input
 @param filename The name of the file
 */
- (void)cacheFile:(NSData *)file withFileName:(NSString *)filename;


/** Returns info about a file given either it's ID, or a file name.  If a filename is given, this will return a P2PFileInfo object if exactly one match to the name is found.  If there are multiple matches, nil is returned and a fileId must be supplied.
 
 @param fileId The identifier unique to a file
 @param filename The name of a file to retrieve info on
 @return Returns information if a match is found, otherwise nil 
 */
- (P2PFileInfo *)fileInfoForFileId:(NSString *)fileId filename:(NSString *)filename;


/** Responds to a file list request, returning an object wrapping a list of filenames available from ourselves
 
 @param request A file list request
 @return An object detailing what files we have on hand
 */
- (P2PFileListResponse *)fileListForRequest:(P2PFileListRequest *)request;


/** If critial pieces of information on a file changes (filename, fileId, or total size), the FileInfo object should pass itself to this method in order to be saved.
 
 @param fileInfo A file info object that needs to be saved to disk
 */
- (void)saveFileInfoToDisk:(P2PFileInfo *)fileInfo;


/** Deletes all information about a file from the cache.
 
 @param fileInfo Information about a file to be deleted
 @return YES if successful, NO otherwise
 */
- (bool)deleteFileFromCache:(P2PFileInfo *)fileInfo;


@end

