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
   `pluginval --strictness-level 8 --validate-in-process --skip-gui-tests <path>`
   — catches threading and lifecycle issues auval doesn't.

**Rungs 1–3 in one command** (used by every suite plugin):
```bash
enkerli-juce/tools/validate.sh <project-dir> <aumi|aumu> <CODE> [ProductName]
```

**Rung 0 for WebView UIs — render the artifact before it ships:**
```bash
swift enkerli-juce/tools/webview-smoke.swift <index.html | http://…>
```
A real WKWebView (the same engine as iPadOS) loads the exact embedded
bundle and fails unless the UI mounts with zero page errors. Wire it
into the bundle build (Progression Studio's WebUI/build.mjs does).
Unit tests of pure logic never *render* — the smoke caught an App-level
render crash (TDZ in a hook dependency array referencing a memo declared
later) that 649 passing unit tests sailed past and an iPad found first.
For diagnosis: file:// sanitizes errors to "Script error."; re-run over
http://localhost (`python3 -m http.server`) with an unminified build
(`PSP_DEBUG=1`) to get real names and stacks. jsc (the raw engine,
`/System/Library/Frameworks/JavaScriptCore.framework/.../jsc`) separates
JS-semantics failures from DOM-context ones. happy-dom/jsdom are NOT
faithful runtimes for this purpose — they failed to execute the bundle
at all while WKWebView ran it.
4. **Real hosts, real devices** (manual — the part that cannot be skipped).
   The foundation makes runtime state readable ON the device:
   - `RuntimeInfo` (src/RuntimeInfo.h): the UI shows host name, wrapper,
     sample rate, JUCE version, and **phys_footprint memory** — the number
     iOS enforces extension limits against. Watch it on the oldest iPad;
     extensions die without a dialog when it crosses the ceiling.
   - The error overlay (plugin web builds): uncaught JS errors paint onto
     the page — a blank WebView always names its reason.
   - BridgePilot additionally probes bridge round-trip latency
     (enkerliPing/Pong) — a stalling bridge shows up as climbing ms.


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
- **Inline ES modules don't run under the custom scheme in WKWebView.**
  A `<script type="module">` page served via JUCE's resource provider
  stays silently blank on iPadOS (classic inline scripts work — Vane and
  BridgePilot both use them). Build embedded bundles as classic IIFE and
  inject an error overlay so a blank page can never be silent.
  Corollary: classic inline scripts are NOT deferred — place them at the
  END of <body>, or they run before the DOM exists (React error #299).
  (Both found on-device in the Progression Studio plugin, 2026-06-12 —
  the second one by the overlay itself, same day it was added.)
- **WKWebView cannot download.** A `blob:`/`data:` anchor click (the
  standard browser "save file" idiom) has no download manager under the
  juce:// scheme: WebKit aborts with **"Frame load interrupted" on a dead
  blank page** — no back navigation, UI gone until the editor reopens.
  Send the bytes over the bridge (`saveFile` in enkerli-bridge.js →
  "enkerliSaveFile") and save natively with `enkerli::exportBytes()`
  (FileExport.h): FileChooser on desktop, share sheet on iPadOS —
  presented from the responder chain, since document pickers are the
  unreliable path inside appexes. (Found in AUM: Progression Studio MIDI
  export, 2026-06-12.) Device-verified working 2026-06-12 — and it adds
  its own benign log storm: `Failed to request default share mode for
  fileURL … -10814`, `Only support loading options for CKShare and SWY
  types`, `error fetching item/file provider domain for URL`, `Failed to
  locate container app bundle record`, LaunchServices `-54 process may
  not map database`, RemoteTextInput sessionID errors. All of it appears
  on a SUCCESSFUL share-sheet save; judge by whether the sheet appeared
  and the file landed, not by the console.
- **WKWebView log noise is not your bug**: `ManagedConfiguration: Could
  not create a sandbox extension`, `ResourceLoadStatistics: fopen failed`,
  and `Unable to hide query parameters` appear in healthy WKWebView apps.
  Diagnose blanks with an in-page error overlay, not the device console.
- **AudioPlayHead is audio-thread only.** Querying `getPlayHead()` from an
  editor timer returns empty/stale data in AUv3 hosts — AUM shows "stopped"
  while playing — though some macOS hosts let it slide, which is exactly why
  it survives desktop testing. Capture in `processBlock` into
  `enkerli::TransportSnapshot` (atomics); UIs read the snapshot.
  (Found on-device in BridgePilot, 2026-06-12.)
- **`window.confirm`/`alert`/`prompt` are NO-OPS in the WebView.** JUCE's
  WebBrowserComponent wires no native JS dialog panel, so `confirm()`
  returns falsy immediately and `alert()`/`prompt()` do nothing. Any
  destructive action guarded by `if (confirm(...))` then SILENTLY never
  runs on device — looks like a dead button. (Found: MIDIcurator's
  "Clear All" and per-clip "Delete" did nothing in the AUv3.) Use a
  DOM-based dialog instead — `@enkerli/ui/confirm` (`esConfirm`/`esAlert`,
  Promise-based, token-styled, works in both browser and WebView).
- **`fetch('/relative/asset')` 404s in the WebView.** The page is served
  from a custom resource-provider scheme with no co-located HTTP server,
  so any app feature that fetches bundled assets by path (MIDIcurator's
  sample-progression loader, the loop DB) fails — in the standalone *and*
  the AUv3. Gate such features on a real origin
  (`!IN_PLUGIN && /^https?:$/.test(location.protocol)`), or embed the
  asset in BinaryData. (Found: iPadOS standalone, 2026-06-14.)
- **`callAsync` lambdas outlive the editor.** `parameterChanged` (and any
  host callback) can fire off the message thread while the host is tearing
  the editor down; a queued `MessageManager::callAsync` capturing raw
  `this` then runs on a freed editor. pluginval 8's "Open editor whilst
  processing" segfaults on exactly this — and it survives casual host
  testing because humans don't close editors mid-automation. Capture
  `juce::Component::SafePointer` in every queued/cross-thread lambda and
  null-check it. (Found by pluginval in PitchFold, 2026-06-12.)
- **MIDI INPUT to an aumi AUv3 is host-dependent — verify per host.**
  A MIDI-effect plugin receives played notes in `processBlock`'s MidiBuffer
  ONLY if the host routes a MIDI source into it; many setups don't by
  default. In AUM: the plugin needs a MIDI input assigned (the keyboard/
  controller routed to the MIDI Processor node), which is separate from the
  audio/MIDI *output* routing. Test the chord-input path with an actual
  controller routed in, and don't assume "no notes arriving" is a bug in
  the plugin — check the host routing first.
  Threading: never read incoming MIDI on anything but the audio thread, and
  never touch the WebView from `processBlock`. Carry events out via
  `enkerli::MidiInputCollector` (lock-free SPSC ring; the editor timer
  drains and emits over the bridge). Overflow drops oldest, so a dropped
  note-off can stick — the JS held-notes tracker resyncs on an idle gap.
  (Added with ProgGenie ChordID, 2026-06-14; on-device verification pending.)
- **iPadOS file access**: PARTLY REHABILITATED 2026-06-12 — a
  `UIDocumentPickerViewController` (`asCopy:YES`, presented from the
  responder chain: `enkerli::importFile`) **works inside AUM's AUv3**,
  device-verified importing MIDI into MIDIcurator. The old guidance
  (ship content in BinaryData or App Group containers — Vane's wavetable
  "iOS-friendly load path") still applies to *bulk/always-needed* content
  and to hosts not yet tested; verify per host before relying on it.

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

### Stale AUv3 *icon* in AUM (a distinct cache from registration)

AUM caches the AUv3's icon keyed by the **AudioComponent version**, separate
from the registration cache — so a new icon shows on the SpringBoard
(SpringBoard reads the app's `AppIcon`) but AUM keeps drawing the old one,
and delete+reboot does *not* clear it because the component version is
unchanged. **Trigger: bump the plugin `VERSION`** (CFBundleVersion of the
appex; pass `VERSION "${PROJECT_VERSION}"` and bump `project(... VERSION)`),
rebuild, reinstall, relaunch the standalone once. The version change forces
`audiocomponentregistrard` to re-read the bundle, icon included.
**RESOLVED on-device 2026-06-13**: the version bump (0.1.0→0.1.1) was
necessary but NOT sufficient — what finally refreshed the icons was
**force-quitting AUM** (swipe it away in the app switcher), *not* a reboot.
Surprising but important: **AUM caches AUv3 icons in its own process and a
reboot relaunches it from that cache — only a clean quit re-reads them.** So
the real ritual is: bump `VERSION`, rebuild/reinstall, launch the standalone
once, then **force-quit and relaunch AUM**. (PitchFold's appeared first
because it already carried the bumped version; ProgGenie/MIDIcurator showed
after the AUM quit.) Reboot is the wrong reflex here — it's the registration
cache's fix, not the icon cache's.

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
