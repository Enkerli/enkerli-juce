# EnkerliPlugin.cmake — the suite's known-good JUCE plugin settings, once.
#
# JUCE plugins break on PROJECT SETTINGS far more often than on DSP or GUI
# code: the IS_MIDI_EFFECT/IS_SYNTH axis, AU plist details Logic silently
# rejects, iOS flags that only fail at archive time. This file encodes the
# combinations that are known to build and validate, with the reasons kept
# next to the settings. Plugins call ONE function and add sources.
#
# Archetypes:
#   enkerli_add_midi_effect_plugin(<target> ...)   — aumi, like DrawnQurve/Serpe
#   enkerli_add_instrument_plugin(<target> ...)    — aumu, like Vane
#
# Common one-value args: PRODUCT_NAME PLUGIN_CODE BUNDLE_ID VERSION DESCRIPTION
#                        ICON_BIG ICON_SMALL LV2_URI
# The Apple team id comes from -DENKERLI_IOS_TEAM_ID=… (cache var).

set(ENKERLI_IOS_TEAM_ID "P8W7XXJN6C" CACHE STRING "Apple Developer Team ID for iOS signing")

# ── JUCE resolution: installed → local JUCE/ or -DJUCE_PATH → FetchContent ──
macro(enkerli_resolve_juce)
    if(NOT TARGET juce::juce_core)
        find_package(JUCE CONFIG QUIET)
        if(NOT JUCE_FOUND)
            set(JUCE_PATH "${CMAKE_SOURCE_DIR}/JUCE" CACHE PATH "Path to JUCE directory")
            # One local JUCE for every repo: probe (in order) the repo-local
            # JUCE/ dir or -DJUCE_PATH, a JUCE_PATH environment variable
            # (export it once on Linux — no /Applications there), and the
            # macOS install. Only then fetch.
            if(NOT EXISTS "${JUCE_PATH}/CMakeLists.txt" AND EXISTS "$ENV{JUCE_PATH}/CMakeLists.txt")
                set(JUCE_PATH "$ENV{JUCE_PATH}")
            endif()
            if(NOT EXISTS "${JUCE_PATH}/CMakeLists.txt" AND EXISTS "/Applications/JUCE/CMakeLists.txt")
                set(JUCE_PATH "/Applications/JUCE")
            endif()
            if(EXISTS "${JUCE_PATH}/CMakeLists.txt")
                add_subdirectory("${JUCE_PATH}" "${CMAKE_BINARY_DIR}/JUCE")
            else()
                message(STATUS "JUCE not found locally — fetching juce-framework/JUCE 8.0.13")
                include(FetchContent)
                FetchContent_Declare(JUCE
                    GIT_REPOSITORY https://github.com/juce-framework/JUCE.git
                    GIT_TAG 8.0.13
                    GIT_SHALLOW TRUE)
                FetchContent_MakeAvailable(JUCE)
            endif()
        endif()
    endif()
endmacro()

# ── clap-juce-extensions: wraps a JUCE plugin as a CLAP, on every desktop OS ──
# CLAP is not an iOS format, so this is a no-op there. Resolved like JUCE:
# a local checkout (submodule or -DCLAP_JUCE_PATH) wins, else FetchContent.
# clap-juce-extensions pulls the CLAP SDK (clap + clap-helpers) itself, so no
# extra submodules are needed in the plugin repos. Idempotent (guarded on the
# imported target) so calling it per-plugin is safe.
macro(enkerli_resolve_clap)
    if(NOT CMAKE_SYSTEM_NAME STREQUAL "iOS" AND NOT TARGET clap_juce_extensions)
        set(CLAP_JUCE_PATH "${CMAKE_SOURCE_DIR}/clap-juce-extensions" CACHE PATH "Path to clap-juce-extensions")
        if(EXISTS "${CLAP_JUCE_PATH}/CMakeLists.txt")
            add_subdirectory("${CLAP_JUCE_PATH}" "${CMAKE_BINARY_DIR}/clap-juce-extensions")
        else()
            message(STATUS "clap-juce-extensions not found locally — fetching free-audio/clap-juce-extensions")
            include(FetchContent)
            FetchContent_Declare(clap-juce-extensions
                GIT_REPOSITORY https://github.com/free-audio/clap-juce-extensions.git
                GIT_TAG main)   # not GIT_SHALLOW: it carries the CLAP SDK as submodules
            FetchContent_MakeAvailable(clap-juce-extensions)
        endif()
    endif()
endmacro()

# ── Internal: shared argument parsing + platform-split juce_add_plugin ──────
function(_enkerli_add_plugin target archetype)
    cmake_parse_arguments(ARG ""
        "PRODUCT_NAME;PLUGIN_CODE;BUNDLE_ID;VERSION;DESCRIPTION;ICON_BIG;ICON_SMALL;LV2_URI;PLIST_TO_MERGE"
        "" ${ARGN})

    if(NOT ARG_PRODUCT_NAME)
        set(ARG_PRODUCT_NAME "${target}")
    endif()
    if(NOT ARG_PLUGIN_CODE)
        message(FATAL_ERROR "enkerli_add_*_plugin(${target}): PLUGIN_CODE is required "
            "(4 chars, at least one uppercase). Changing it later breaks every saved "
            "host session — choose once.")
    endif()
    if(NOT ARG_BUNDLE_ID)
        string(TOLOWER "${ARG_PRODUCT_NAME}" _lower)
        # Bundle ids (and CLAP ids) must be reverse-DNS with no spaces; a product
        # name like "Progression Studio" would otherwise yield the malformed
        # "com.enkerli.progression studio" (JUCE warns, CLAP rejects). Strip them.
        string(REPLACE " " "" _lower "${_lower}")
        set(ARG_BUNDLE_ID "com.enkerli.${_lower}")
    endif()
    if(NOT ARG_VERSION)
        set(ARG_VERSION "0.1.0")
    endif()

    # ── The archetype axis. Getting ONE of these four flags wrong is the
    #    classic source of "it builds but the host won't list it":
    #    * MIDI effect (aumi): hosts expect MIDI in AND out; IS_SYNTH must be
    #      FALSE or auval tests the wrong API contract.
    #    * Instrument (aumu): NEEDS_MIDI_OUTPUT should be FALSE unless the
    #      synth really emits MIDI — advertising an output you never write
    #      makes some hosts (AUM) draw useless MIDI routing for it.
    #    VST3 has no pure MIDI-effect concept: JUCE builds the aumi archetype
    #    as a VST3 "Fx" that passes audio through — that is expected, not a bug.
    if(archetype STREQUAL "midi_effect")
        set(_type_props
            IS_SYNTH                FALSE
            IS_MIDI_EFFECT          TRUE
            NEEDS_MIDI_INPUT        TRUE
            NEEDS_MIDI_OUTPUT       TRUE)
        # CLAP standard feature set for a MIDI/note processor.
        set(_clap_features "note-effect")
    elseif(archetype STREQUAL "instrument")
        set(_type_props
            IS_SYNTH                TRUE
            IS_MIDI_EFFECT          FALSE
            NEEDS_MIDI_INPUT        TRUE
            NEEDS_MIDI_OUTPUT       FALSE)
        set(_clap_features "instrument" "synthesizer")
    else()
        message(FATAL_ERROR "unknown archetype ${archetype}")
    endif()

    set(_icon_props "")
    if(ARG_ICON_BIG)
        list(APPEND _icon_props ICON_BIG "${ARG_ICON_BIG}")
    endif()
    if(ARG_ICON_SMALL)
        list(APPEND _icon_props ICON_SMALL "${ARG_ICON_SMALL}")
    endif()

    set(_base_props
        COMPANY_NAME                "Enkerli"
        COMPANY_WEBSITE             "https://enkerli.com"
        BUNDLE_ID                   "${ARG_BUNDLE_ID}"
        PLUGIN_MANUFACTURER_CODE    Enke
        PLUGIN_CODE                 ${ARG_PLUGIN_CODE}
        PRODUCT_NAME                "${ARG_PRODUCT_NAME}"
        VERSION                     "${ARG_VERSION}"
        DESCRIPTION                 "${ARG_DESCRIPTION}"
        EDITOR_WANTS_KEYBOARD_FOCUS FALSE
        # No suite plugin records audio; never trigger the mic-permission
        # dialog (it also complicates App Review).
        MICROPHONE_PERMISSION_ENABLED FALSE
        # Every suite UI is a WebView. NEEDS_WEB_BROWSER makes JUCE link the
        # platform web deps — WKWebView (macOS/iOS), WebView2 (Windows), and
        # crucially webkit2gtk+gtk on Linux (else juce_gui_extra can't find
        # gtk/gtk.h at compile). NEEDS_CURL FALSE matches JUCE_USE_CURL=0.
        NEEDS_WEB_BROWSER           TRUE
        NEEDS_CURL                  FALSE
        ${_type_props}
        ${_icon_props})

    # Windows: JUCE_USE_WIN_WEBVIEW2 makes juce_gui_extra include <WebView2.h>,
    # which JUCE does not vendor. Fetch the SDK (a NuGet .nupkg is just a zip)
    # and put its headers on the include path for every target built here.
    if(WIN32 AND NOT TARGET _enkerli_webview2)
        include(FetchContent)
        FetchContent_Declare(webview2
            URL https://www.nuget.org/api/v2/package/Microsoft.Web.WebView2/1.0.2792.45
            DOWNLOAD_EXTRACT_TIMESTAMP TRUE)
        FetchContent_MakeAvailable(webview2)
        add_custom_target(_enkerli_webview2)   # guard: fetch once per build tree
    endif()
    if(WIN32)
        include_directories("${webview2_SOURCE_DIR}/build/native/include")
    endif()

    set(_ios_plist "")
    if(ARG_PLIST_TO_MERGE)
        set(_ios_plist PLIST_TO_MERGE "${ARG_PLIST_TO_MERGE}")
    endif()

    if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
        # iPadOS lessons (each learned the hard way):
        #  * COPY_PLUGIN_AFTER_BUILD must be FALSE — cross-compiles have no
        #    install path on the build host; TRUE fails late and cryptically.
        #  * BACKGROUND_AUDIO keeps the standalone's audio session (and any
        #    AUv3 it hosts) alive when backgrounded — without it MIDI stalls.
        #  * All four orientations: AUM/hosts present plugin UIs in either
        #    orientation; locking one gets the UI letterboxed or clipped.
        #  * The AUv3 appex inherits signing from the standalone — one team id.
        juce_add_plugin(${target}
            ${_base_props}
            FORMATS                     AUv3 Standalone
            COPY_PLUGIN_AFTER_BUILD     FALSE
            DEVELOPMENT_TEAM            "${ENKERLI_IOS_TEAM_ID}"
            BACKGROUND_AUDIO_ENABLED    TRUE
            ${_ios_plist}
            IPHONE_SCREEN_ORIENTATIONS
                UIInterfaceOrientationPortrait
                UIInterfaceOrientationPortraitUpsideDown
                UIInterfaceOrientationLandscapeLeft
                UIInterfaceOrientationLandscapeRight
            IPAD_SCREEN_ORIENTATIONS
                UIInterfaceOrientationPortrait
                UIInterfaceOrientationPortraitUpsideDown
                UIInterfaceOrientationLandscapeLeft
                UIInterfaceOrientationLandscapeRight)
    elseif(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
        # macOS lesson (from Vane): JUCE writes "network.client" and
        # "temporary-exception.files.all.read-write" into the AU plist
        # resourceUsage block; Logic/GarageBand treat the broad files grant
        # as a violation and SILENTLY refuse to list the AU. Suppressing the
        # block costs nothing for an in-process AU and makes Logic happy.
        juce_add_plugin(${target}
            ${_base_props}
            FORMATS                     AU VST3 Standalone
            COPY_PLUGIN_AFTER_BUILD     TRUE
            SUPPRESS_AU_PLIST_RESOURCE_USAGE TRUE)
    elseif(CMAKE_SYSTEM_NAME STREQUAL "Linux")
        if(NOT ARG_LV2_URI)
            set(ARG_LV2_URI "https://enkerli.com/plugins/${target}")
        endif()
        # VST3 is a first-class Linux format (Bitwig, Reaper, Ardour, Qtractor
        # all load Linux VST3) and the suite's pre-consolidation Linux builds
        # shipped it — JUCE builds it with no extra SDK, and these plugins
        # already link WebKitGTK for the Standalone/LV2 WebView, so VST3 adds
        # no new dependency. LV2 stays alongside it (the native Linux format);
        # CLAP is added separately below.
        juce_add_plugin(${target}
            ${_base_props}
            FORMATS                     LV2 VST3 Standalone
            LV2_URI                     "${ARG_LV2_URI}"
            COPY_PLUGIN_AFTER_BUILD     TRUE)
    else()
        # Windows (and any other desktop): VST3 is THE plugin format there, so
        # build it alongside Standalone (AU is Apple-only; LV2 is the Linux
        # branch; CLAP is added separately below on every desktop OS).
        juce_add_plugin(${target}
            ${_base_props}
            FORMATS                     VST3 Standalone
            COPY_PLUGIN_AFTER_BUILD     FALSE)
    endif()

    # Suite-standard compile definitions: WebView UIs on, curl/splash off,
    # and never advertise VST2 replacement (no VST2 SDK exists here).
    # JUCE_USE_WIN_WEBVIEW2 selects the modern Edge/WebView2 backend on Windows —
    # required for the resource-provider WebView the UIs use (Options::
    # withResourceProvider isn't a member without it). No-op off Windows.
    target_compile_definitions(${target} PUBLIC
        JUCE_WEB_BROWSER=1
        JUCE_USE_WIN_WEBVIEW2=1
        JUCE_USE_CURL=0
        JUCE_VST3_CAN_REPLACE_VST2=0
        JUCE_DISPLAY_SPLASH_SCREEN=0)

    # ── CLAP (macOS / Linux / Windows) — a <target>_CLAP target building the
    #    .clap, sharing the same sources/definitions as the JUCE plugin above.
    #    CLAP_ID must be stable (like PLUGIN_CODE, host sessions key off it);
    #    reuse the bundle id. Skipped on iOS (not a CLAP platform).
    if(NOT CMAKE_SYSTEM_NAME STREQUAL "iOS")
        enkerli_resolve_clap()
        clap_juce_extensions_plugin(TARGET ${target}
            CLAP_ID       "${ARG_BUNDLE_ID}"
            CLAP_FEATURES ${_clap_features})
    endif()
endfunction()

function(enkerli_add_midi_effect_plugin target)
    _enkerli_add_plugin(${target} midi_effect ${ARGN})
endfunction()

function(enkerli_add_instrument_plugin target)
    _enkerli_add_plugin(${target} instrument ${ARGN})
endfunction()
