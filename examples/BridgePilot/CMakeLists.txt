cmake_minimum_required(VERSION 3.22)
project(BridgePilot VERSION 0.1.0)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED YES)

include("${CMAKE_CURRENT_SOURCE_DIR}/../../cmake/EnkerliPlugin.cmake")
enkerli_resolve_juce()

enkerli_add_midi_effect_plugin(BridgePilot
    PRODUCT_NAME "BridgePilot"
    PLUGIN_CODE  Bpil
    DESCRIPTION  "enkerli-juce pathfinder: WebView bridge + host-synced MIDI clip scheduler"
)

target_sources(BridgePilot PRIVATE Source/Plugin.cpp)

juce_add_binary_data(BridgePilotWebUI
    HEADER_NAME BinaryDataWebUI.h
    NAMESPACE   BinaryData
    SOURCES     WebUI/index.html)

target_link_libraries(BridgePilot PRIVATE
    BridgePilotWebUI
    juce::juce_audio_utils
    juce::juce_gui_extra
    PUBLIC
    juce::juce_recommended_config_flags
    juce::juce_recommended_warning_flags)
