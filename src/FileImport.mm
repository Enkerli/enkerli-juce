// iOS implementation of enkerli::importFile — see FileImport.h.
// Compiles to nothing on macOS; add to target_sources on Apple platforms.

#include "FileImport.h"

#if JUCE_IOS

#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface EnkerliDocPickerDelegate : NSObject <UIDocumentPickerDelegate>
@property (nonatomic, copy) void (^handler) (NSURL* _Nullable url);
@end

// The picker doesn't retain its delegate; park live ones here until done.
static NSMutableSet<EnkerliDocPickerDelegate*>* enkerliLiveDelegates()
{
    static NSMutableSet* set = [NSMutableSet new];
    return set;
}

@implementation EnkerliDocPickerDelegate
- (void) documentPicker: (UIDocumentPickerViewController*) picker
    didPickDocumentsAtURLs: (NSArray<NSURL*>*) urls
{
    if (self.handler)
        self.handler (urls.firstObject);
    [enkerliLiveDelegates() removeObject: self];
}
- (void) documentPickerWasCancelled: (UIDocumentPickerViewController*) picker
{
    if (self.handler)
        self.handler (nil);
    [enkerliLiveDelegates() removeObject: self];
}
@end

namespace enkerli
{

void importFile (juce::Component& anchor,
                 const juce::String& filePatterns,
                 ImportCallback done)
{
    auto* peer = anchor.getPeer();
    if (peer == nullptr)
        return;
    auto* view = (UIView*) peer->getNativeHandle();
    if (view == nil)
        return;

    UIViewController* host = nil;
    for (UIResponder* r = view; r != nil; r = [r nextResponder])
    {
        if ([r isKindOfClass: [UIViewController class]])
        {
            host = (UIViewController*) r;
            break;
        }
    }
    if (host == nil)
        return;

    // "*.mid;*.midi" → UTTypes; unknown extensions fall back to plain data.
    NSMutableArray<UTType*>* types = [NSMutableArray new];
    for (const auto& pattern : juce::StringArray::fromTokens (filePatterns, ";,", {}))
    {
        const auto ext = pattern.fromLastOccurrenceOf (".", false, false).trim();
        if (ext.isNotEmpty())
            if (UTType* t = [UTType typeWithFilenameExtension:
                    [NSString stringWithUTF8String: ext.toRawUTF8()]])
                [types addObject: t];
    }
    if (types.count == 0)
        [types addObject: UTTypeData];

    // asCopy gives us a readable local copy — no security-scoped access
    // dance, which matters inside app extensions.
    auto* picker = [[UIDocumentPickerViewController alloc]
        initForOpeningContentTypes: types asCopy: YES];

    auto* delegate = [EnkerliDocPickerDelegate new];
    delegate.handler = ^(NSURL* url)
    {
        if (url == nil)
            return;
        const juce::File file ([url.path UTF8String]);
        juce::MemoryBlock bytes;
        if (file.loadFileAsData (bytes))
            done (file.getFileName(), bytes);
    };
    [enkerliLiveDelegates() addObject: delegate];
    picker.delegate = delegate;

    [host presentViewController: picker animated: YES completion: nil];
}

} // namespace enkerli

#endif // JUCE_IOS
