#pragma once
/*
  EnkerliWebView — the suite's WebView↔C++ bridge (the Vane pattern).

  One self-contained WebView surface per plugin, served from BinaryData via
  a resource provider; JS↔C++ traffic uses JUCE 8's native integration:

      JS → C++ : window.__JUCE__.backend.emitEvent(id, payload)
      C++ → JS : emitEventIfBrowserIsVisible(id, payload)

  The JS counterpart is web/enkerli-bridge.js (feature-detects __JUCE__,
  falls back to WebMIDI in Chromium browsers, no-ops elsewhere) — the same
  UI code runs in a browser tab and inside the plugin.
*/

#include <juce_gui_extra/juce_gui_extra.h>
#include <map>

namespace enkerli
{

class BridgedWebView : public juce::WebBrowserComponent
{
public:
    struct Resource
    {
        const char* data;
        int size;
        const char* mime;
    };

    /** path (e.g. "/index.html") → embedded bytes. "/" aliases "/index.html". */
    using ResourceMap = std::map<juce::String, Resource>;
    using EventHandler = std::function<void (const juce::var&)>;
    using EventMap = std::map<juce::String, EventHandler>;

    BridgedWebView (ResourceMap resources, EventMap events)
        : juce::WebBrowserComponent (makeOptions (std::move (resources), std::move (events)))
    {
    }

    /** Load the embedded UI. Call once the component is on screen. */
    void start()
    {
        goToURL (juce::WebBrowserComponent::getResourceProviderRoot());
    }

    /** C++ → JS event (dropped while the page is hidden — cheap by design). */
    void emit (const juce::String& id, const juce::var& payload)
    {
        emitEventIfBrowserIsVisible (id, payload);
    }

private:
    /**
     * JS run before the page loads, publishing the NATIVE side's build stamps.
     * The WebUI bundle stamps itself at bundle time (see each repo's
     * cmake/write-build-tag.cmake); this is the other half, and the pair makes a
     * mismatch visible:
     *
     *   UI newer than the binary  the bundle was rebuilt but never embedded and
     *                             relinked — the running UI is not what you built
     *   both old                  the built plugin never replaced the installed one
     *
     * Both happened on 2026-07-29/30 and neither was visible from the plugin.
     */
    static juce::String buildStampScript()
    {
        // currentExecutableFile, NOT currentApplicationFile: the latter is the
        // .app/.component/.appex PACKAGE FOLDER on Apple platforms, and macOS
        // does not touch a bundle directory's mtime when Contents/MacOS/<exe>
        // is replaced. Two symptoms, both seen 2026-08-11 in RND Companion:
        // a macOS standalone reporting a binary a day older than the build it
        // was running, and an iPadOS AUv3 reporting 1969-12-31 -- epoch, i.e.
        // the bundle was not stat-able from inside the extension at all.
        // Either way the badge cried staleness that was not real, which is
        // worse than no badge: it is the diagnostic you are supposed to trust.
        const auto self = juce::File::getSpecialLocation (juce::File::currentExecutableFile);
        const auto when = self.exists()
            ? self.getLastModificationTime().formatted ("%Y-%m-%d %H:%M")
            : juce::String ("unknown");
        return "window.__CPP_BUILD_TAG__ = " + juce::JSON::toString (when)
             + "; window.__CPP_COMPILED__ = "
             + juce::JSON::toString (juce::String (__DATE__ " " __TIME__)) + ";";
    }

    static juce::WebBrowserComponent::Options makeOptions (ResourceMap resources, EventMap events)
    {
        auto resourcesShared = std::make_shared<ResourceMap> (std::move (resources));

        auto options = juce::WebBrowserComponent::Options {}
            .withResourceProvider (
                [resourcesShared] (const juce::String& path)
                    -> std::optional<juce::WebBrowserComponent::Resource>
                {
                    auto key = (path == "/" || path.isEmpty()) ? juce::String ("/index.html") : path;
                    auto it = resourcesShared->find (key);
                    if (it == resourcesShared->end())
                        return std::nullopt;

                    const auto& r = it->second;
                    // WKWebView sniffs encodings unreliably; a BOM pins HTML to UTF-8.
                    const bool bom = juce::String (r.mime).startsWith ("text/html");
                    std::vector<std::byte> bytes;
                    bytes.reserve (static_cast<size_t> (r.size) + 3);
                    if (bom)
                    {
                        bytes.push_back (std::byte { 0xEF });
                        bytes.push_back (std::byte { 0xBB });
                        bytes.push_back (std::byte { 0xBF });
                    }
                    const auto* p = reinterpret_cast<const std::byte*> (r.data);
                    bytes.insert (bytes.end(), p, p + r.size);
                    return juce::WebBrowserComponent::Resource { std::move (bytes), juce::String (r.mime) };
                },
                juce::WebBrowserComponent::getResourceProviderRoot())
            .withUserScript (buildStampScript())
            .withNativeIntegrationEnabled()
           #if JUCE_MAC
            .withKeepPageLoadedWhenBrowserIsHidden()
           #endif
            ;

        for (auto& [id, handler] : events)
        {
            options = options.withEventListener (id,
                [h = handler] (const juce::Array<juce::var>& args)
                {
                    h (args.isEmpty() ? juce::var() : args[0]);
                });
        }
        return options;
    }
};

} // namespace enkerli
