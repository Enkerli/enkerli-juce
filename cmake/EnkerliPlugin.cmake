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
    elseif(archetype STREQUAL "instrument")
        set(_type_props
            IS_SYNTH                TRUE
            IS_MIDI_EFFECT          FALSE
            NEEDS_MIDI_INPUT        TRUE
            NEEDS_MIDI_OUTPUT       FALSE)
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
        ${_type_props}
        ${_icon_props})

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
        juce_add_plugin(${target}
            ${_base_props}
            FORMATS                     LV2 Standalone
            LV2_URI                     "${ARG_LV2_URI}"
            COPY_PLUGIN_AFTER_BUILD     TRUE)
    else()
        juce_add_plugin(${target}
            ${_base_props}
            FORMATS                     Standalone
            COPY_PLUGIN_AFTER_BUILD     FALSE)
    endif()

    # Suite-standard compile definitions: WebView UIs on, curl/splash off,
    # and never advertise VST2 replacement (no VST2 SDK exists here).
    target_compile_definitions(${target} PUBLIC
        JUCE_WEB_BROWSER=1
        JUCE_USE_CURL=0
        JUCE_VST3_CAN_REPLACE_VST2=0
        JUCE_DISPLAY_SPLASH_SCREEN=0)
endfunction()

function(enkerli_add_midi_effect_plugin target)
    _enkerli_add_plugin(${target} midi_effect ${ARGN})
endfunction()

function(enkerli_add_instrument_plugin target)
    _enkerli_add_plugin(${target} instrument ${ARGN})
endfunction()
