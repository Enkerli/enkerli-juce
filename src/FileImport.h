#pragma once

// FileImport — open a file through native UI and hand the bytes to the
// WebView UI. Counterpart of FileExport.h: `<input type="file">` is as
// unreliable inside plugin WebViews as blob downloads are, so the UI sends
// "enkerliOpenFile" over the bridge and the editor calls
// enkerli::importFile():
//   * macOS / Linux standalone — async juce::FileChooser open dialog.
//   * iOS / iPadOS — UIDocumentPickerViewController (asCopy, so no
//     security-scoped bookkeeping), presented from the responder chain.
//     Device-verified working inside AUM's AUv3 (2026-06-12, MIDIcurator);
//     other hosts unverified — the callback simply never fires when
//     presentation fails, so degradation is silent but safe.
//
// The iOS implementation is ObjC++: add src/FileImport.mm to the plugin's
// sources when targeting Apple platforms (it compiles empty on macOS).
// The callback runs on the message thread with the chosen file's name and
// contents; it is not called when the user cancels.

#include <juce_gui_basics/juce_gui_basics.h>

namespace enkerli
{

using ImportCallback =
    std::function<void (const juce::String& filename, const juce::MemoryBlock& bytes)>;

void importFile (juce::Component& anchor,
                 const juce::String& filePatterns, // e.g. "*.mid;*.midi"
                 ImportCallback done);

#if ! JUCE_IOS
inline void importFile (juce::Component& anchor,
                        const juce::String& filePatterns,
                        ImportCallback done)
{
    juce::ignoreUnused (anchor);
    auto chooser = std::make_shared<juce::FileChooser> (
        "Open", juce::File::getSpecialLocation (juce::File::userHomeDirectory),
        filePatterns);

    chooser->launchAsync (juce::FileBrowserComponent::openMode
                              | juce::FileBrowserComponent::canSelectFiles,
                          [chooser, done] (const juce::FileChooser& fc)
                          {
                              const auto file = fc.getResult();
                              if (file == juce::File())
                                  return;
                              juce::MemoryBlock bytes;
                              if (file.loadFileAsData (bytes))
                                  done (file.getFileName(), bytes);
                          });
}
#endif

} // namespace enkerli
