# enkerli-juce

The shared C++/CMake foundation for the Enkerli music suite's plugins
(Vane · Serpe · DrawnQurve · PitchFold · the Progression Studio plugin).
JUCE projects break on **settings**, not code — this repo encodes the
known-good settings once, with the reasons kept next to them, and proves
them continuously with a pathfinder plugin.

## What's here

| Piece | Purpose |
|---|---|
| [`cmake/EnkerliPlugin.cmake`](cmake/EnkerliPlugin.cmake) | The two plugin archetypes as one-call CMake functions: `enkerli_add_midi_effect_plugin` (aumi, like DrawnQurve/Serpe) and `enkerli_add_instrument_plugin` (aumu, like Vane). Platform splits (macOS/iOS/Linux), the Logic plist trap, iOS orientation/background/signing flags, JUCE resolution (installed → local → FetchContent 8.0.13) — all encoded with comments explaining each scar. |
| [`src/EnkerliWebView.h`](src/EnkerliWebView.h) | `BridgedWebView`: WebView UI served from BinaryData with the suite's JS↔C++ event contract (the Vane pattern: `emitEvent` / `emitEventIfBrowserIsVisible`). |
| [`src/MidiClipScheduler.h`](src/MidiClipScheduler.h) | Host-synced, lock-free playback of beat-positioned MIDI clips for aumi plugins: follows the host transport (tempo, loops, relocations flush hung notes), free-runs without one. |
| [`web/enkerli-bridge.js`](web/enkerli-bridge.js) | The JS side: one UI codebase across JUCE WebView / Chromium WebMIDI / WebKit no-MIDI (progressive enhancement per the suite's F7 decision). |
| [`examples/BridgePilot`](examples/BridgePilot) | The proof: a minimal aumi plugin (WebView UI → bridge → scheduler → host MIDI, ii–V–I loop). **macOS AU passes auval; AU/VST3/Standalone + iOS Standalone/AUv3 all build.** Any change to the foundation must keep it green. |
| [`TESTING.md`](TESTING.md) | The testing ladder: build matrix → auval → pluginval → real hosts on multiple physical devices, plus the catalogued traps. |

## Using it

```cmake
include(enkerli-juce/cmake/EnkerliPlugin.cmake)
enkerli_resolve_juce()

enkerli_add_midi_effect_plugin(MyPlugin
    PRODUCT_NAME "My Plugin"
    PLUGIN_CODE  Mypl            # forever — see TESTING.md
    DESCRIPTION  "…")

target_sources(MyPlugin PRIVATE Source/Plugin.cpp)
target_link_libraries(MyPlugin PRIVATE
    juce::juce_audio_utils juce::juce_gui_extra
    PUBLIC juce::juce_recommended_config_flags juce::juce_recommended_warning_flags)
```

Consume as a git submodule from plugin repos (per the suite plan).
iOS signing: `-DENKERLI_IOS_TEAM_ID=XXXXXXXXXX`.

## Verify the foundation

```bash
cd examples/BridgePilot
cmake -B build && cmake --build build          # macOS AU/VST3/Standalone
auval -v aumi Bpil Enke                        # must say VALIDATION SUCCEEDED
cmake -B build-ios -G Xcode -DCMAKE_SYSTEM_NAME=iOS
xcodebuild -project build-ios/BridgePilot.xcodeproj -scheme BridgePilot_AUv3 \
  -destination "generic/platform=iOS" CODE_SIGNING_ALLOWED=NO build
```

CC0-1.0.

## Suite handoff

This repo is part of the Enkerli music suite. For the whole-suite picture —
repo map, conventions (leftmost-LSB bit order, structural spelling),
build/validation ladders, and open queues — start at the suite handoff:
<https://github.com/Enkerli/music-suite/blob/main/HANDOFF.md>.
