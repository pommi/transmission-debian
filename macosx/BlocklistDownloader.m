/******************************************************************************
 * $Id: BlocklistDownloader.m 10624 2010-05-02 18:03:49Z livings124 $
 *
 * Copyright (c) 2008-2010 Transmission authors and contributors
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 *****************************************************************************/

#import "BlocklistDownloader.h"
#import "BlocklistDownloaderViewController.h"
#import "BlocklistScheduler.h"
#import "PrefsController.h"

#define LIST_URL @"http://update.transmissionbt.com/level1.gz"
#define FILE_NAME @"level1.gz"

@interface BlocklistDownloader (Private)

- (void) startDownload;
- (void) finishDownloadSuccess;

@end

@implementation BlocklistDownloader

BlocklistDownloader * fDownloader = nil;
+ (BlocklistDownloader *) downloader
{
    if (!fDownloader)
    {
        fDownloader = [[BlocklistDownloader alloc] init];
        [fDownloader startDownload];
    }
    
    return fDownloader;
}

+ (BOOL) isRunning
{
    return fDownloader != nil;
}

- (void) setViewController: (BlocklistDownloaderViewController *) viewController
{
    fViewController = viewController;
    if (fViewController)
    {
        switch (fState)
        {
            case BLOCKLIST_DL_START:
                [fViewController setStatusStarting];
                break;
            case BLOCKLIST_DL_DOWNLOADING:
                [fViewController setStatusProgressForCurrentSize: fCurrentSize expectedSize: fExpectedSize];
                break;
            case BLOCKLIST_DL_PROCESSING:
                [fViewController setStatusProcessing];
                break;
        }
    }
}

- (void) dealloc
{
    [fDownload release];
    [fDestination release];
    [super dealloc];
}

- (void) cancelDownload
{
    [fViewController setFinished];
    
    [fDownload cancel];
    
    [[BlocklistScheduler scheduler] updateSchedule];
    
    fDownloader = nil;
    [self release];
}

- (void) download: (NSURLDownload *) download didCreateDestination: (NSString *) path
{
    fDestination = [path retain];
}

- (void) download: (NSURLDownload *) download didReceiveResponse: (NSURLResponse *) response
{
    fState = BLOCKLIST_DL_DOWNLOADING;
    
    fCurrentSize = 0;
    fExpectedSize = [response expectedContentLength];
    
    [fViewController setStatusProgressForCurrentSize: fCurrentSize expectedSize: fExpectedSize];
}

- (void) download: (NSURLDownload *) download didReceiveDataOfLength: (NSUInteger) length
{
    fCurrentSize += length;
    [fViewController setStatusProgressForCurrentSize: fCurrentSize expectedSize: fExpectedSize];
}

- (void) download: (NSURLDownload *) download didFailWithError: (NSError *) error
{
    #warning remove
    NSLog(@"%@", [error localizedDescription]);
    NSLog(@"%@", [error localizedFailureReason]);
    NSLog(@"%@", [error localizedRecoverySuggestion]);
    [fViewController setFailed: [error localizedDescription]];
    
    [[BlocklistScheduler scheduler] updateSchedule];
    
    fDownloader = nil;
    [self release];
}

- (void) downloadDidFinish: (NSURLDownload *) download
{
    fState = BLOCKLIST_DL_PROCESSING;
    [self performSelectorInBackground: @selector(finishDownloadSuccess) withObject: nil];
}

@end

@implementation BlocklistDownloader (Private)

- (void) startDownload
{
    fState = BLOCKLIST_DL_START;
    
    [[BlocklistScheduler scheduler] cancelSchedule];
    
    NSURLRequest * request = [NSURLRequest requestWithURL: [NSURL URLWithString: LIST_URL]];
    
    fDownload = [[NSURLDownload alloc] initWithRequest: request delegate: self];
    [fDownload setDestination: [NSTemporaryDirectory() stringByAppendingPathComponent: FILE_NAME] allowOverwrite: YES];
}

- (void) finishDownloadSuccess
{
    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
    
    [fViewController setStatusProcessing];
    
    //process data
    NSAssert(fDestination != nil, @"the blocklist file destination has not been specified");
    tr_blocklistSetContent([PrefsController handle], [fDestination UTF8String]);
    
    //delete downloaded file
    [[NSFileManager defaultManager] removeItemAtPath: fDestination error: NULL];
    
    [fViewController setFinished];
    
    //update last updated date for schedule
    [[NSUserDefaults standardUserDefaults] setObject: [NSDate date] forKey: @"BlocklistLastUpdate"];
    [[BlocklistScheduler scheduler] updateSchedule];
    
    [[NSNotificationCenter defaultCenter] postNotificationName: @"BlocklistUpdated" object: nil];
    
    [pool drain];
    
    fDownloader = nil;
    [self release];
}

@end
