# Testing doctrine

JUCE plugins fail on **project settings and host quirks** far more often
than on DSP/GUI code, and they fail differently per device. Nothing counts
as working until it has passed this ladder — "it builds" is step zero.

## The ladder

1. **Build matrix** (automatable, every change):
   - macOS: `cmake -B build && cmake --build build` → AU, VST3, Standalone
   - iOS compile check (no signing needed):
     `cmake -B build-ios -G Xcode -DCMAKE_SYSTEM_NAME=iOS`
     `xcodebuild … -destination "generic/platform=iOS" CODE_SIGNING_ALLOWED=NO`
     — builds both the Standalone and the AUv3 appex schemes.
2. **auval** (automatable, macOS):
   - MIDI effect: `auval -v aumi <CODE> Enke`
   - Instrument:  `auval -v aumu <CODE> Enke`
   - Stale registrations poison results: `killall -9 AudioComponentRegistrar`
     first; if the component doesn't appear at all, check `pluginkit -mv`
     and re-copy to `~/Library/Audio/Plug-Ins/Components`.
   - BridgePilot (this repo's pathfinder) passes — any archetype change to
     `EnkerliPlugin.cmake` must keep it passing.
3. **pluginval** (automatable, macOS, VST3+AU):
   `pluginval --strictness-level 8 <path>` — catches threading and
   lifecycle issues auval doesn't.
4. **Real hosts, real devices** (manual — the part that cannot be skipped):

| Surface | Hosts to cover | What breaks here |
|---|---|---|
| macOS arm64 | Logic, Live or Reaper, GarageBand | Logic silently refuses AUs over plist details (see below); GarageBand is stricter than Logic |
| iPadOS device A (recent) | AUM, Logic for iPad | AUv3 lifecycle, WebView memory, orientation |
| iPadOS device B (oldest supported) | AUM, Drambo | **memory ceiling** (AUv3 extensions get far less than apps — old devices enforce harshly), WKWebView performance |
| Patchbox OS (when LV2 ships) | PlugData / MOD host | headless behavior, no WebView |

Test on at least two physically different iPads before calling an iPadOS
build good — extension memory limits, WKWebView behavior, and audio-session
handling all vary by device generation and OS version.

## Known traps (encoded in EnkerliPlugin.cmake — kept passing by BridgePilot)

- **Logic/GarageBand silently hide AUs** whose plist `resourceUsage` block
  contains JUCE's default `temporary-exception.files.all.read-write`.
  → `SUPPRESS_AU_PLIST_RESOURCE_USAGE TRUE` on macOS. (Learned in Vane.)
- **MIDI effect vs instrument is four flags, not one.** aumi needs
  `IS_MIDI_EFFECT TRUE` + MIDI in *and* out + `IS_SYNTH FALSE`; mismatches
  produce plugins that build but fail auval or never appear in host lists.
  VST3 has no pure MIDI-effect type — JUCE wraps it as an Fx; that's
  expected, not a bug.
- **`COPY_PLUGIN_AFTER_BUILD` must be FALSE for iOS** cross-compiles; TRUE
  fails late with an unrelated-looking error.
- **iPadOS orientations**: declare all four for both idioms — hosts present
  plugin UIs in any orientation and a locked Info.plist gets you clipped UI.
- **`BACKGROUND_AUDIO_ENABLED TRUE`** on iOS or MIDI/audio stalls when the
  standalone is backgrounded.
- **Plugin codes are forever**: changing `PLUGIN_CODE` orphans every saved
  session (the Serpe RPEd/RPEi lesson). Set once in the archetype call.
- **WKWebView in an AUv3 extension works** (Vane ships it) but the
  extension's memory ceiling is the binding constraint: keep bundles lean,
  avoid large in-page assets, prefer canvas redraw over DOM churn.
- **AudioPlayHead is audio-thread only.** Querying `getPlayHead()` from an
  editor timer returns empty/stale data in AUv3 hosts — AUM shows "stopped"
  while playing — though some macOS hosts let it slide, which is exactly why
  it survives desktop testing. Capture in `processBlock` into
  `enkerli::TransportSnapshot` (atomics); UIs read the snapshot.
  (Found on-device in BridgePilot, 2026-06-12.)
- **iPadOS file access**: extensions can't show document pickers reliably;
  ship content in BinaryData or App Group containers (Vane's wavetable
  "iOS-friendly load path" exists for this reason).

## "The AUv3 doesn't show up in AUM" ritual (in order)

1. **aumi plugins live under MIDI Processor nodes**, not the Audio Unit
   source/effect pickers. In AUM: **+ → MIDI Processor** → your plugin.
   Instruments (aumu) are the ones in the audio pickers. Wrong-list is the
   most common "missing plugin" of all.
2. Install the **Standalone** scheme (it embeds the appex in `PlugIns/`)
   and **launch the app once** on the device — that triggers extension
   registration. Building the AUv3 scheme alone installs nothing usable.
3. Registration cache: force-quit and relaunch the host → reboot the iPad
   → delete app, reboot, reinstall. (iOS's slower, more stubborn version
   of macOS's `killall AudioComponentRegistrar`.)
4. Signing: app **and** appex must be signed with the same team
   (`-DENKERLI_IOS_TEAM_ID`). A team mismatch installs a working app whose
   extension silently never registers.
5. Only then suspect the plist. Verify the artifact before suspecting the
   device:
   `plutil -p <app>/PlugIns/*.appex/Info.plist` — wants `type aumi` (or
   `aumu`), 4-char subtype/manufacturer, `NSExtensionPointIdentifier`
   `com.apple.AudioUnit-UI`, and an appex bundle id prefixed by the app's.

## Per-release checklist

- [ ] macOS build matrix green
- [ ] iOS unsigned compile green (Standalone + AUv3 schemes)
- [ ] auval PASS (correct type: aumi/aumu)
- [ ] pluginval level 8 PASS
- [ ] Logic: plugin appears, loads, state survives save/reopen
- [ ] AUM (newest iPad): loads, UI both orientations, survives background/foreground
- [ ] AUM (oldest iPad): loads under memory pressure, no WebView blank-outs
- [ ] Host transport: play/stop/loop/tempo-change followed correctly
- [ ] Session round-trip on every host (the plugin-code contract)
