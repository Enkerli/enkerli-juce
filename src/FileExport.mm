// iOS implementation of enkerli::exportBytes — see FileExport.h.
// Compiles to nothing on macOS (the header's inline FileChooser path is
// used there); add this file to target_sources on Apple platforms.

#include "FileExport.h"

#if JUCE_IOS

#import <UIKit/UIKit.h>

namespace enkerli
{

void exportBytes (juce::Component& anchor,
                  const juce::String& filename,
                  const juce::MemoryBlock& bytes)
{
    // Share sheets need a real file URL; the temp dir is extension-safe.
    auto temp = juce::File::getSpecialLocation (juce::File::tempDirectory)
                    .getChildFile (filename);
    if (! temp.replaceWithData (bytes.getData(), bytes.getSize()))
        return;

    auto* peer = anchor.getPeer();
    if (peer == nullptr)
        return;

    auto* view = (UIView*) peer->getNativeHandle();
    if (view == nil)
        return;

    // Find the nearest view controller up the responder chain — inside an
    // AUv3 app extension UIApplication.sharedApplication is off-limits, but
    // presenting from the extension's own view controller is fine.
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

    NSURL* url = [NSURL fileURLWithPath:
        [NSString stringWithUTF8String: temp.getFullPathName().toRawUTF8()]];

    auto* sheet = [[UIActivityViewController alloc]
        initWithActivityItems: @[url] applicationActivities: nil];

    // iPad presents this as a popover; it must have an anchor or UIKit throws.
    if (auto* pop = sheet.popoverPresentationController)
    {
        pop.sourceView = view;
        pop.sourceRect = CGRectMake (view.bounds.size.width / 2.0,
                                     view.bounds.size.height / 2.0, 1.0, 1.0);
    }

    [host presentViewController: sheet animated: YES completion: nil];
}

} // namespace enkerli

#endif // JUCE_IOS
